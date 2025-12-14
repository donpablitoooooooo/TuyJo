import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

// Handler per i messaggi in background (deve essere top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kDebugMode) {
    print('📱 Background message received: ${message.notification?.title}');
  }
}

class NotificationService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'messages_channel',
    'Messaggi',
    description: 'Notifiche per i nuovi messaggi',
    importance: Importance.defaultImportance,
  );

  static const AndroidNotificationChannel _todoChannel = AndroidNotificationChannel(
    'todo_reminders',
    'Promemoria To Do',
    description: 'Notifiche per i promemoria degli eventi',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  // Inizializza le notifiche
  Future<void> initialize() async {
    // 0. Inizializza timezone
    tz.initializeTimeZones();
    try {
      final now = DateTime.now();
      final offset = now.timeZoneOffset;
      String timeZoneName = _guessTimezoneName(offset);
      tz.setLocalLocation(tz.getLocation(timeZoneName));
      if (kDebugMode) {
        print('🌍 Timezone: $timeZoneName (offset: ${offset.inHours}h)');
      }
    } catch (e) {
      tz.setLocalLocation(tz.getLocation('UTC'));
    }

    // 1. Configura background handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 2. Inizializza notifiche locali
    await _initializeLocalNotifications();

    // 3. Richiedi permessi FCM
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      if (kDebugMode) print('✅ FCM permission granted');

      String? token = await _firebaseMessaging.getToken();
      if (kDebugMode) print('🔑 FCM Token: $token');

      // Gestisci messaggi in foreground
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        if (kDebugMode) {
          print('📨 Foreground message: ${message.notification?.title}');
        }
        _showLocalNotification(message);
      });

      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        if (kDebugMode) {
          print('🔔 App opened from notification');
        }
      });

      RemoteMessage? initialMessage = await _firebaseMessaging.getInitialMessage();
      if (initialMessage != null && kDebugMode) {
        print('🚀 App opened from terminated state');
      }
    }
  }

  Future<void> _initializeLocalNotifications() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(settings);

    final androidImplementation = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidImplementation?.createNotificationChannel(_channel);
    await androidImplementation?.createNotificationChannel(_todoChannel);

    // Richiedi permessi Android 13+ per notifiche
    await androidImplementation?.requestNotificationsPermission();
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    RemoteNotification? notification = message.notification;
    if (notification != null) {
      await _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            icon: 'ic_notification',
          ),
        ),
      );
    }
  }

  Future<String?> getToken() async {
    return await _firebaseMessaging.getToken();
  }

  Future<void> saveTokenToFirestore(
    String familyChatId,
    String userId,
  ) async {
    try {
      String? token = await getToken();
      if (token != null) {
        await _firestore
            .collection('families')
            .doc(familyChatId)
            .collection('users')
            .doc(userId)
            .set({
          'fcm_token': token,
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        if (kDebugMode) print('✅ FCM token saved');
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error saving FCM token: $e');
    }
  }

  Future<void> deleteToken() async {
    try {
      await _firebaseMessaging.deleteToken();
      if (kDebugMode) print('🗑️ FCM token deleted');
    } catch (e) {
      if (kDebugMode) print('❌ Error deleting token: $e');
    }
  }

  Future<void> deleteTokenFromFirestore(
    String familyChatId,
    String userId,
  ) async {
    try {
      await _firestore
          .collection('families')
          .doc(familyChatId)
          .collection('users')
          .doc(userId)
          .delete();
      if (kDebugMode) print('✅ User data deleted from Firestore');
    } catch (e) {
      if (kDebugMode) print('❌ Error deleting user data: $e');
    }
  }

  /// Schedula una notifica con androidAllowWhileIdle per bypassare Doze mode
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    try {
      final tzScheduledDate = tz.TZDateTime.from(scheduledDate, tz.local);
      final now = tz.TZDateTime.now(tz.local);
      final difference = tzScheduledDate.difference(now);

      if (kDebugMode) {
        print('📅 Scheduling notification #$id');
        print('   Title: $title');
        print('   Scheduled for: $scheduledDate');
        print('   Difference: ${difference.inSeconds}s');
      }

      if (difference.isNegative) {
        if (kDebugMode) print('⚠️ Scheduled time is in the past!');
        return;
      }

      await _localNotifications.zonedSchedule(
        id,
        title,
        body,
        tzScheduledDate,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _todoChannel.id,
            _todoChannel.name,
            channelDescription: _todoChannel.description,
            importance: Importance.max,
            priority: Priority.max,
            icon: '@mipmap/ic_launcher',
            playSound: true,
            enableVibration: true,
            visibility: NotificationVisibility.public,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );

      if (kDebugMode) {
        print('✅ Notification #$id scheduled (inexact, ±15min delay possible)');
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error scheduling: $e');
    }
  }

  Future<void> cancelNotification(int id) async {
    try {
      await _localNotifications.cancel(id);
      if (kDebugMode) print('🗑️ Notification #$id cancelled');
    } catch (e) {
      if (kDebugMode) print('❌ Error cancelling: $e');
    }
  }

  String _guessTimezoneName(Duration offset) {
    final hours = offset.inHours;
    switch (hours) {
      case 0:
        return 'Europe/London';
      case 1:
        return 'Europe/Madrid';
      case 2:
        return 'Europe/Athens';
      case 3:
        return 'Europe/Moscow';
      case -5:
        return 'America/New_York';
      case -6:
        return 'America/Chicago';
      case -7:
        return 'America/Denver';
      case -8:
        return 'America/Los_Angeles';
      default:
        return 'UTC';
    }
  }
}
