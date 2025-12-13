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
    'messages_channel', // id
    'Messaggi', // nome
    description: 'Notifiche per i nuovi messaggi',
    importance: Importance.defaultImportance,
  );

  static const AndroidNotificationChannel _todoChannel = AndroidNotificationChannel(
    'todo_reminders', // id
    'Promemoria To Do', // nome
    description: 'Notifiche per i promemoria degli eventi',
    importance: Importance.high,
  );

  // Inizializza le notifiche
  Future<void> initialize() async {
    // 0. Inizializza timezone per scheduled notifications
    tz.initializeTimeZones();

    // 1. Configura il background message handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 2. Inizializza le notifiche locali
    await _initializeLocalNotifications();

    // 3. Richiedi permessi
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      if (kDebugMode) print('✅ User granted notification permission');

      // 4. Ottieni il token FCM
      String? token = await _firebaseMessaging.getToken();
      if (kDebugMode) print('🔑 FCM Token: $token');

      // 5. Gestisci messaggi in foreground
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        if (kDebugMode) {
          print('📨 Foreground message received: ${message.notification?.title}');
        }
        _showLocalNotification(message);
      });

      // 6. Gestisci tap su notifiche quando l'app è in background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        if (kDebugMode) {
          print('🔔 App opened from notification: ${message.notification?.title}');
        }
        // Qui puoi navigare alla chat screen se necessario
      });

      // 7. Gestisci messaggi ricevuti mentre l'app era chiusa
      RemoteMessage? initialMessage =
          await _firebaseMessaging.getInitialMessage();
      if (initialMessage != null) {
        if (kDebugMode) {
          print('🚀 App opened from terminated state: ${initialMessage.notification?.title}');
        }
      }
    } else {
      if (kDebugMode) print('❌ User declined notification permission');
    }
  }

  // Inizializza le notifiche locali
  Future<void> _initializeLocalNotifications() async {
    // Android settings
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS settings
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

    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (kDebugMode) {
          print('🔔 Notification tapped: ${response.payload}');
        }
        // Qui puoi gestire il tap sulla notifica
      },
    );

    // Crea i canali Android
    final androidImplementation = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidImplementation?.createNotificationChannel(_channel);
    await androidImplementation?.createNotificationChannel(_todoChannel);
  }

  // Mostra una notifica locale
  Future<void> _showLocalNotification(RemoteMessage message) async {
    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

    if (notification != null && android != null) {
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
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: message.data.toString(),
      );
    }
  }

  // Ottieni il token FCM
  Future<String?> getToken() async {
    return await _firebaseMessaging.getToken();
  }

  // Salva il token FCM in Firestore per l'utente
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

        if (kDebugMode) {
          print('✅ FCM token saved to Firestore for user: $userId');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error saving FCM token: $e');
      }
    }
  }

  // Aggiorna il token sul server quando cambia
  void onTokenRefresh(Function(String) callback) {
    _firebaseMessaging.onTokenRefresh.listen(callback);
  }

  // Cancella il token quando l'utente si disconnette
  Future<void> deleteToken() async {
    try {
      await _firebaseMessaging.deleteToken();
      if (kDebugMode) print('🗑️ FCM token deleted');
    } catch (e) {
      if (kDebugMode) print('❌ Error deleting token: $e');
    }
  }

  /// Elimina il token FCM e l'utente da Firestore quando si fa unpair
  Future<void> deleteTokenFromFirestore(
    String familyChatId,
    String userId,
  ) async {
    try {
      // Elimina il documento dell'utente dalla subcollection users
      await _firestore
          .collection('families')
          .doc(familyChatId)
          .collection('users')
          .doc(userId)
          .delete();

      if (kDebugMode) {
        print('✅ User data deleted from Firestore: $userId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error deleting user data from Firestore: $e');
      }
    }
  }

  /// Schedula una notifica per un momento futuro
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    try {
      if (kDebugMode) {
        print('📅 Scheduling notification #$id for ${scheduledDate.toIso8601String()}');
      }

      await _localNotifications.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(scheduledDate, tz.local),
        NotificationDetails(
          android: AndroidNotificationDetails(
            _todoChannel.id,
            _todoChannel.name,
            channelDescription: _todoChannel.description,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );

      if (kDebugMode) {
        print('✅ Notification scheduled successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error scheduling notification: $e');
      }
    }
  }

  /// Cancella una notifica schedulata
  Future<void> cancelNotification(int id) async {
    try {
      await _localNotifications.cancel(id);
      if (kDebugMode) {
        print('🗑️ Notification #$id cancelled');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error cancelling notification: $e');
      }
    }
  }

  /// Cancella tutte le notifiche schedulate
  Future<void> cancelAllNotifications() async {
    try {
      await _localNotifications.cancelAll();
      if (kDebugMode) {
        print('🗑️ All notifications cancelled');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error cancelling all notifications: $e');
      }
    }
  }
}
