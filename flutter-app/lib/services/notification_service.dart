import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'dart:ui' as ui;
import 'dart:math';

// Handler per i messaggi in background (deve essere top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kDebugMode) {
    print('📱 Background message received: ${message.data}');
  }

  // Se è una notifica di chiamata, mostra la UI nativa CallKit
  if (message.data['type'] == 'incoming_call') {
    await _showCallKitIncoming(message.data);
  }
}

/// Genera un UUID v4 valido (RFC 4122) per iOS CallKit
String _generateUUID() {
  final random = Random();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  // Imposta versione 4 (0100xxxx)
  bytes[6] = (bytes[6] & 0x0F) | 0x40;
  // Imposta variante (10xxxxxx)
  bytes[8] = (bytes[8] & 0x3F) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
}

/// Mostra la UI nativa di chiamata in arrivo via CallKit (top-level per background handler)
Future<void> _showCallKitIncoming(Map<String, dynamic> data) async {
  final callerId = data['callerId'] ?? '';
  final familyChatId = data['familyChatId'] ?? '';
  // Genera UUID v4 valido (RFC 4122) — iOS CallKit richiede questo formato
  final uuid = _generateUUID();

  if (kDebugMode) {
    print('📞 [CALLKIT] Showing incoming call UI:');
    print('   uuid: $uuid');
    print('   callerId: $callerId');
    print('   familyChatId: $familyChatId');
  }

  try {
    final params = CallKitParams(
      id: uuid,
      nameCaller: 'Partner',
      handle: 'TuyJo',
      type: 0, // 0 = audio call
      duration: 30000, // 30 secondi timeout
      textAccept: 'Accept',
      textDecline: 'Decline',
      extra: <String, dynamic>{
        'familyChatId': familyChatId,
        'callerId': callerId,
      },
      android: const AndroidParams(
        isCustomNotification: false,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#1A1A2E',
        actionColor: '#3BA8B0',
        isShowFullLockedScreen: true,
      ),
      ios: const IOSParams(
        iconName: 'AppIcon',
        handleType: 'generic',
        supportsVideo: false,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        ringtonePath: 'system_ringtone_default',
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
    if (kDebugMode) print('✅ [CALLKIT] showCallkitIncoming called successfully');
  } catch (e) {
    if (kDebugMode) print('❌ [CALLKIT] Error showing incoming call: $e');
  }
}

class NotificationService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// GlobalKey per navigare dall'esterno (usato per aprire VoiceCallScreen dalle notifiche)
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// Callback per gestire la chiamata in arrivo (accept) — impostato da main.dart
  void Function(String familyChatId, String callerId)? onIncomingCall;

  /// Callback per gestire il rifiuto della chiamata — impostato da main.dart
  void Function(String familyChatId, String callerId)? onCallDeclined;

  /// Callback per gestire la fine della chiamata — impostato da main.dart
  void Function(String familyChatId, String callerId)? onCallEnded;

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
    importance: Importance.defaultImportance,
    playSound: true,
    enableVibration: true,
  );

  /// UUID della chiamata CallKit attiva (per poterla terminare)
  String? _activeCallUuid;

  /// True se il permesso notifiche FCM è stato negato dall'utente
  bool _notificationPermissionDenied = false;
  bool get isNotificationPermissionDenied => _notificationPermissionDenied;

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

    // 2.5. Inizializza CallKit event listeners
    _initializeCallKitListeners();

    // 2.6. Richiedi permessi CallKit (Android 14+ full screen intent, notifiche)
    await _requestCallKitPermissions();

    // 3. Richiedi permessi FCM
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      _notificationPermissionDenied = true;
      if (kDebugMode) print('❌ FCM permission denied: ${settings.authorizationStatus}');
      return;
    }

    if (kDebugMode) print('✅ FCM permission granted');

    String? token = await _firebaseMessaging.getToken();
    if (kDebugMode) print('🔑 FCM Token: $token');

    // Gestisci messaggi in foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (kDebugMode) {
        print('📨 Foreground message: ${message.notification?.title}');
        print('   Data: ${message.data}');
      }

      // Controlla se è una notifica di chiamata
      if (message.data['type'] == 'incoming_call') {
        _handleIncomingCallNotification(message);
      } else {
        _showLocalNotification(message);
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      if (kDebugMode) {
        print('🔔 App opened from notification: ${message.data}');
      }
      // Se l'utente ha tappato su una notifica di chiamata
      if (message.data['type'] == 'incoming_call') {
        _handleIncomingCallNotification(message);
      }
    });

    RemoteMessage? initialMessage = await _firebaseMessaging.getInitialMessage();
    if (initialMessage != null) {
      if (kDebugMode) print('🚀 App opened from terminated state');
      // Se l'app è stata aperta da una notifica di chiamata
      if (initialMessage.data['type'] == 'incoming_call') {
        // Ritarda per dare tempo al widget tree di costruirsi
        Future.delayed(const Duration(seconds: 1), () {
          _handleIncomingCallNotification(initialMessage);
        });
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

  /// Richiedi permessi necessari per CallKit (Android 14+ full screen intent)
  Future<void> _requestCallKitPermissions() async {
    try {
      // Android 13+: permesso notifiche (necessario per mostrare la UI di chiamata)
      await FlutterCallkitIncoming.requestNotificationPermission({
        "rationaleMessagePermission": "Per ricevere le chiamate in arrivo è necessario il permesso notifiche.",
        "postNotificationMessage": "Per ricevere le chiamate in arrivo, abilita le notifiche nelle impostazioni.",
      });

      // Android 14+: permesso full screen intent (schermata chiamata a schermo intero)
      final canFullScreen = await FlutterCallkitIncoming.canUseFullScreenIntent();
      if (canFullScreen == false) {
        await FlutterCallkitIncoming.requestFullIntentPermission();
      }

      if (kDebugMode) {
        print('✅ [CALLKIT] Permissions requested (fullScreen: $canFullScreen)');
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ [CALLKIT] Error requesting permissions: $e');
      }
    }
  }

  /// Inizializza i listener per gli eventi CallKit (accept, decline, end, timeout)
  void _initializeCallKitListeners() {
    FlutterCallkitIncoming.onEvent.listen((CallEvent? event) {
      if (event == null) return;

      if (kDebugMode) {
        print('📞 [CALLKIT] Event: ${event.event}, body: ${event.body}');
      }

      final body = event.body as Map<dynamic, dynamic>?;
      final extra = body?['extra'] as Map<dynamic, dynamic>?;
      final familyChatId = extra?['familyChatId'] as String? ?? '';
      final callerId = extra?['callerId'] as String? ?? '';
      final uuid = body?['id'] as String?;

      final eventType = event.event;

      if (eventType == Event.actionCallAccept) {
        if (kDebugMode) print('📞 [CALLKIT] Call accepted');
        _activeCallUuid = uuid;
        if (onIncomingCall != null) {
          onIncomingCall!(familyChatId, callerId);
        }
      } else if (eventType == Event.actionCallDecline) {
        if (kDebugMode) print('📞 [CALLKIT] Call declined');
        _activeCallUuid = null;
        if (onCallDeclined != null) {
          onCallDeclined!(familyChatId, callerId);
        }
      } else if (eventType == Event.actionCallEnded) {
        if (kDebugMode) print('📞 [CALLKIT] Call ended');
        _activeCallUuid = null;
        if (onCallEnded != null) {
          onCallEnded!(familyChatId, callerId);
        }
      } else if (eventType == Event.actionCallTimeout) {
        if (kDebugMode) print('📞 [CALLKIT] Call timeout');
        _activeCallUuid = null;
      }
    });
  }

  /// Gestisce una notifica di chiamata in arrivo (app in foreground)
  void _handleIncomingCallNotification(RemoteMessage message) {
    final familyChatId = message.data['familyChatId'] as String?;
    final callerId = message.data['callerId'] as String?;

    if (kDebugMode) {
      print('📞 [CALL] Incoming call notification (foreground):');
      print('   familyChatId: $familyChatId');
      print('   callerId: $callerId');
    }

    if (familyChatId != null && callerId != null) {
      // Mostra la UI nativa di chiamata via CallKit
      _showCallKitIncoming(message.data);
    }
  }

  /// Termina la chiamata CallKit attiva
  Future<void> endCallKit() async {
    try {
      if (_activeCallUuid != null) {
        await FlutterCallkitIncoming.endCall(_activeCallUuid!);
        _activeCallUuid = null;
      } else {
        await FlutterCallkitIncoming.endAllCalls();
      }
    } catch (e) {
      if (kDebugMode) print('⚠️ [CALLKIT] Error ending call: $e');
      _activeCallUuid = null;
    }
  }

  /// Cancella la notifica di chiamata attiva (legacy + CallKit)
  Future<void> cancelCallNotification() async {
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (e) {
      if (kDebugMode) print('⚠️ [CALLKIT] Error cancelling call: $e');
    }
    _activeCallUuid = null;
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

      // Ottieni la lingua del dispositivo
      final locale = ui.PlatformDispatcher.instance.locale;
      String languageCode = locale.languageCode; // es: 'it', 'en', 'es', 'ca'

      // 🔧 FIX: Crea sempre il documento user, anche senza token
      // Questo è necessario per typing indicator e altri features
      await _firestore
          .collection('families')
          .doc(familyChatId)
          .collection('users')
          .doc(userId)
          .set({
        if (token != null) 'fcm_token': token,
        'language': languageCode, // Salva la lingua per notifiche localizzate
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (kDebugMode) {
        if (token != null) {
          print('✅ FCM token saved (language: $languageCode)');
        } else {
          print('⚠️ User document created without FCM token (token not available)');
        }
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

  /// Azzera il badge dell'app (icona notifiche)
  Future<void> clearBadge() async {
    try {
      // Cancella tutte le notifiche dalla barra di notifica
      await _localNotifications.cancelAll();
      if (kDebugMode) print('🔴 Badge cleared');
    } catch (e) {
      if (kDebugMode) print('❌ Error clearing badge: $e');
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
            _todoChannel.id,  // Usa il canale todo_reminders
            _todoChannel.name,
            channelDescription: _todoChannel.description,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            icon: 'ic_notification',  // Stessa icona di FCM che funziona
            playSound: true,
            enableVibration: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );

      if (kDebugMode) {
        print('✅ Notification #$id scheduled (inexact, ±15min delay possible)');

        // Verifica che la notifica sia effettivamente pending
        final pendingNotifications = await _localNotifications.pendingNotificationRequests();
        final pendingIds = pendingNotifications.map((n) => n.id).toList();
        print('📋 Total pending notifications: ${pendingNotifications.length}');
        print('📋 Pending IDs: $pendingIds');

        if (pendingIds.contains(id)) {
          print('✅ Notification #$id confirmed in pending list!');
        } else {
          print('⚠️ WARNING: Notification #$id NOT found in pending list!');
        }
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
