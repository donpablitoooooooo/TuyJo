import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class NotificationService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  // Inizializza le notifiche
  Future<void> initialize() async {
    // Richiedi permesso
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
      if (kDebugMode) print('User granted permission');

      // Ottieni il token FCM
      String? token = await _firebaseMessaging.getToken();
      if (kDebugMode) print('FCM Token: $token');

      // Gestisci messaggi in foreground
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        if (kDebugMode) {
          print('Messaggio ricevuto in foreground: ${message.notification?.title}');
        }
      });

      // Gestisci messaggi quando l'app viene aperta da una notifica
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        if (kDebugMode) {
          print('App aperta da notifica: ${message.notification?.title}');
        }
      });
    } else {
      if (kDebugMode) print('User declined or has not accepted permission');
    }
  }

  // Ottieni il token FCM
  Future<String?> getToken() async {
    return await _firebaseMessaging.getToken();
  }

  // Aggiorna il token sul server quando cambia
  void onTokenRefresh(Function(String) callback) {
    _firebaseMessaging.onTokenRefresh.listen(callback);
  }
}
