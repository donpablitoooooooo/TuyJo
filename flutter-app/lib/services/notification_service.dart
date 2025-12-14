import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Handler per i messaggi in background (deve essere top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kDebugMode) {
    print('📱 Background message received: ${message.notification?.title}');
  }
}

class NotificationService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Inizializza le notifiche
  Future<void> initialize() async {
    // 1. Inizializza Awesome Notifications
    await AwesomeNotifications().initialize(
      null, // icona default dell'app
      [
        // Canale per messaggi normali
        NotificationChannel(
          channelKey: 'messages_channel',
          channelName: 'Messaggi',
          channelDescription: 'Notifiche per i nuovi messaggi',
          defaultColor: const Color(0xFF9D50DD),
          ledColor: Colors.white,
          importance: NotificationImportance.Default,
        ),
        // Canale per todo reminders (alta priorità)
        NotificationChannel(
          channelKey: 'todo_reminders',
          channelName: 'Promemoria To Do',
          channelDescription: 'Notifiche per i promemoria dei To Do',
          defaultColor: const Color(0xFFFF5722),
          ledColor: Colors.orange,
          importance: NotificationImportance.High,
          playSound: true,
          enableVibration: true,
          criticalAlerts: true,
        ),
      ],
      debug: kDebugMode,
    );

    // 2. Richiedi permessi per le notifiche
    bool isAllowed = await AwesomeNotifications().isNotificationAllowed();
    if (!isAllowed) {
      await AwesomeNotifications().requestPermissionToSendNotifications();
    }

    // 3. Richiedi permessi per exact alarms (Android 12+)
    if (kDebugMode) {
      print('📅 Requesting exact alarm permissions...');
    }

    // Awesome Notifications gestisce automaticamente i permessi exact alarm
    // quando scheduli una notifica, quindi non serve richiederli esplicitamente

    if (kDebugMode) {
      print('✅ Awesome Notifications initialized');
    }

    // 4. Configura Firebase Messaging
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 5. Richiedi permessi FCM
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
      if (kDebugMode) print('✅ User granted FCM permission');

      // 6. Ottieni il token FCM
      String? token = await _firebaseMessaging.getToken();
      if (kDebugMode) print('🔑 FCM Token: $token');

      // 7. Gestisci messaggi in foreground
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        if (kDebugMode) {
          print('📨 Foreground message received: ${message.notification?.title}');
        }
        _showFCMNotification(message);
      });

      // 8. Gestisci tap su notifiche quando l'app è in background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        if (kDebugMode) {
          print('🔔 App opened from notification: ${message.notification?.title}');
        }
      });

      // 9. Gestisci messaggi ricevuti mentre l'app era chiusa
      RemoteMessage? initialMessage = await _firebaseMessaging.getInitialMessage();
      if (initialMessage != null) {
        if (kDebugMode) {
          print('🚀 App opened from terminated state: ${initialMessage.notification?.title}');
        }
      }
    } else {
      if (kDebugMode) print('❌ User declined FCM permission');
    }
  }

  /// Mostra notifica FCM locale quando arriva un messaggio
  void _showFCMNotification(RemoteMessage message) {
    AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: message.hashCode,
        channelKey: 'messages_channel',
        title: message.notification?.title ?? '💬 Nuovo messaggio',
        body: message.notification?.body ?? 'Hai ricevuto un nuovo messaggio',
        notificationLayout: NotificationLayout.Default,
        payload: {
          'familyChatId': message.data['familyChatId'] ?? '',
          'messageId': message.data['messageId'] ?? '',
          'senderId': message.data['senderId'] ?? '',
        },
      ),
    );
  }

  /// Salva il token FCM in Firestore
  Future<void> saveTokenToFirestore(
    String familyChatId,
    String userId,
  ) async {
    try {
      final token = await _firebaseMessaging.getToken();
      if (token != null) {
        await _firestore
            .collection('families')
            .doc(familyChatId)
            .collection('users')
            .doc(userId)
            .set({
          'fcm_token': token,
          'updated_at': FieldValue.serverTimestamp(),
        });

        if (kDebugMode) {
          print('✅ FCM token saved to Firestore for user: $userId');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error saving FCM token to Firestore: $e');
      }
    }
  }

  /// Ottiene il token FCM corrente
  Future<String?> getToken() async {
    return await _firebaseMessaging.getToken();
  }

  /// Elimina il token FCM
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
      final now = DateTime.now();
      final difference = scheduledDate.difference(now);

      if (kDebugMode) {
        print('📅 Scheduling notification #$id');
        print('   Title: $title');
        print('   Body: $body');
        print('   Scheduled for: ${scheduledDate.toIso8601String()}');
        print('   Now: ${now.toIso8601String()}');
        print('   Difference: ${difference.inSeconds} seconds (${difference.inMinutes} minutes)');
      }

      if (difference.isNegative) {
        if (kDebugMode) {
          print('⚠️ WARNING: Scheduled time is in the past! Notification will not be delivered.');
        }
        return;
      }

      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: id,
          channelKey: 'todo_reminders',
          title: title,
          body: body,
          notificationLayout: NotificationLayout.Default,
          criticalAlert: true,
          wakeUpScreen: true,
          category: NotificationCategory.Reminder,
        ),
        schedule: NotificationCalendar.fromDate(
          date: scheduledDate,
          preciseAlarm: true, // Abilita exact alarm
          allowWhileIdle: true, // Permetti anche in idle mode
        ),
      );

      if (kDebugMode) {
        print('✅ Notification #$id scheduled successfully with EXACT ALARM!');
        print('   Will arrive in ~${difference.inSeconds} seconds');
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
      await AwesomeNotifications().cancel(id);
      if (kDebugMode) {
        print('🗑️ Notification #$id cancelled');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error cancelling notification: $e');
      }
    }
  }
}
