import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'messages_channel', // id
    'Messaggi', // nome
    description: 'Notifiche per i nuovi messaggi',
    importance: Importance.defaultImportance,
  );

  // Inizializza le notifiche
  Future<void> initialize() async {
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

    // Crea il canale Android per notifiche ad alta priorità
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
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
            icon: '@mipmap/ic_launcher',
            importance: Importance.high,
            priority: Priority.high,
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
}
