import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'dart:ui' as ui;
import 'dart:io';
import 'dart:async';
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
  } else if (message.data['type'] == 'call_cancelled') {
    // Il caller ha riagganciato mentre squillava ancora: chiudi la UI nativa
    await _dismissRingingCallKit();
  }
}

/// Scrive `declined` sul documento chiamata così il caller smette di
/// squillare. Top-level: usato sia dal main isolate sia dal background
/// handler CallKit (rifiuto con app terminata, Android).
Future<void> writeCallDeclined(String familyChatId, {String? callId}) async {
  if (familyChatId.isEmpty) return;
  try {
    await FirebaseFirestore.instance
        .collection('families')
        .doc(familyChatId)
        .collection('calls')
        .doc('current')
        .set({
      'status': 'declined',
      if (callId != null && callId.isNotEmpty) 'declined_call_id': callId,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (kDebugMode) print('📞 [CALLKIT] declined written for family ${familyChatId.substring(0, 8)}…');
  } catch (e) {
    if (kDebugMode) print('❌ [CALLKIT] Error writing declined: $e');
  }
}

/// Handler CallKit per eventi ricevuti con app TERMINATA (Android).
/// Gira in un isolate separato: Firebase va inizializzato qui.
@pragma('vm:entry-point')
Future<void> _callKitBackgroundHandler(CallEvent event) async {
  if (event is! CallEventActionCallDecline) return;
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // già inizializzato o non necessario
  }
  final extra = event.callKitParams.extra ?? const {};
  await writeCallDeclined(
    extra['familyChatId'] as String? ?? '',
    callId: extra['callId'] as String?,
  );
}

/// Chiude la UI CallKit di chiamata in arrivo (top-level per background handler)
Future<void> _dismissRingingCallKit() async {
  try {
    await FlutterCallkitIncoming.endAllCalls();
    if (kDebugMode) print('📞 [CALLKIT] Ringing call dismissed (caller cancelled)');
  } catch (e) {
    if (kDebugMode) print('⚠️ [CALLKIT] Error dismissing call: $e');
  }
}

/// Parametri iOS condivisi da chiamate in entrata e in uscita.
/// `voiceChat` attiva il voice processing di Apple (AEC/AGC) e 48 kHz è il
/// sample rate nativo di Opus: WebRTC non deve ricampionare.
const IOSParams _callKitIosParams = IOSParams(
  iconName: 'AppIcon',
  handleType: 'generic',
  supportsVideo: false,
  maximumCallGroups: 1,
  maximumCallsPerCallGroup: 1,
  supportsDTMF: false,
  supportsHolding: false,
  supportsGrouping: false,
  supportsUngrouping: false,
  includesCallsInRecents: true,
  configureAudioSession: true,
  audioSessionMode: 'voiceChat',
  audioSessionActive: true,
  audioSessionPreferredSampleRate: 48000.0,
  audioSessionPreferredIOBufferDuration: 0.02,
  ringtonePath: 'system_ringtone_default',
);

const AndroidParams _callKitAndroidParams = AndroidParams(
  isCustomNotification: false,
  isShowLogo: false,
  ringtonePath: 'system_ringtone_default',
  backgroundColor: '#1A1A2E',
  actionColor: '#3BA8B0',
  isShowFullLockedScreen: true,
  isImportant: true,
  textAccept: 'Accept',
  textDecline: 'Decline',
);

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
  final callId = data['callId'] ?? '';
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
      appName: 'TuyJo',
      handle: 'TuyJo',
      type: 0, // 0 = audio call
      duration: 30000, // 30 secondi: allineato al timeout lato caller
      extra: <String, dynamic>{
        'familyChatId': familyChatId,
        'callerId': callerId,
        'callId': callId,
      },
      android: _callKitAndroidParams,
      ios: _callKitIosParams,
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

  /// Impostato da VoiceCallScreen: l'utente ha terminato la chiamata dalla
  /// UI nativa (lock screen iOS, notifica Android) → chiudi anche WebRTC.
  VoidCallback? onNativeCallEnded;

  /// Listener sul documento chiamata mentre CallKit squilla: se il caller
  /// riaggancia prima della risposta, chiudiamo subito la UI nativa.
  StreamSubscription? _ringingWatcher;
  String? _ringingCallId;
  /// callId dell'ultima chiamata rifiutata (letto da main.dart per il write)
  String? _lastDeclinedCallId;
  String? get lastDeclinedCallId => _lastDeclinedCallId;

  /// True mentre VoiceCallScreen è montata (impostato dalla schermata).
  /// Serve per il "glare": se arriva una chiamata mentre ne abbiamo già una
  /// aperta, l'accept CallKit non deve aprire una seconda schermata.
  bool callScreenActive = false;

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

  /// Salvati per poter ri-salvare il token su onTokenRefresh
  String? _savedFamilyChatId;
  String? _savedUserId;

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
    if (Platform.isAndroid) {
      try {
        await FlutterCallkitIncoming.onBackgroundMessage(_callKitBackgroundHandler);
      } catch (e) {
        if (kDebugMode) print('⚠️ [CALLKIT] onBackgroundMessage registration failed: $e');
      }
    }

    // 2.6. Richiedi permessi CallKit (Android 14+ full screen intent, notifiche)
    await _requestCallKitPermissions();

    // 2.7. App avviata da CallKit (iOS PushKit / Android full screen intent)
    // con chiamata già accettata: l'evento accept può essere partito prima
    // che Flutter fosse in ascolto. Recuperalo da activeCalls().
    _resumeAcceptedCallIfAny();

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

    // Prova a ottenere il token FCM con retry (Play Services potrebbe non essere subito disponibile)
    String? token;
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        token = await _firebaseMessaging.getToken();
        break;
      } catch (e) {
        if (kDebugMode) print('⚠️ FCM getToken attempt $attempt/3 failed: $e');
        if (attempt < 3) {
          await Future.delayed(Duration(seconds: attempt * 2));
        }
      }
    }
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
      } else if (message.data['type'] == 'call_cancelled') {
        // Ignora un annullamento in ritardo riferito a una chiamata diversa
        final cancelledId = message.data['callId'] as String? ?? '';
        if (cancelledId.isEmpty || _ringingCallId == null || cancelledId == _ringingCallId) {
          _ringingWatcher?.cancel();
          _ringingWatcher = null;
          _dismissRingingCallKit();
        }
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

    // Ascolta refresh del token (succede quando Play Services lo rinnova)
    _firebaseMessaging.onTokenRefresh.listen((newToken) {
      if (kDebugMode) print('🔄 FCM token refreshed: $newToken');
      if (_savedFamilyChatId != null && _savedUserId != null) {
        saveTokenToFirestore(_savedFamilyChatId!, _savedUserId!);
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

  /// Richiedi permessi necessari per CallKit (notifiche + Android 14+ full
  /// screen intent).
  ///
  /// Le notifiche sono un permesso "degradante": l'app funziona anche senza.
  /// NON usiamo più FlutterCallkitIncoming.requestNotificationPermission, che a
  /// ogni avvio mostra un dialog coercivo ("Notification permission is
  /// required... go to settings") quando il permesso è negato. Chiediamo invece
  /// il permesso col prompt di SISTEMA (permission_handler), una sola volta: se
  /// è già concesso o negato in modo permanente non compare nulla. Il promemoria
  /// gentile + opt-out è gestito dal MaterialBanner. Se l'utente ha fatto
  /// opt-out, non chiediamo nulla.
  Future<void> _requestCallKitPermissions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final optedOut = prefs.getBool('notifications_opt_out') ?? false;
      if (optedOut) return;

      // Android 13+: permesso notifiche (serve anche per la UI di chiamata).
      // Lo chiediamo col prompt di sistema solo se è ancora richiedibile; se è
      // già negato in modo permanente NON mostriamo alcun dialog coercivo.
      final notifStatus = await Permission.notification.status;
      if (notifStatus.isDenied) {
        await Permission.notification.request();
      }

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
      if (kDebugMode) print('📞 [CALLKIT] Event: $event');

      String familyChatIdOf(CallKitParams p) =>
          p.extra?['familyChatId'] as String? ?? '';
      String callerIdOf(CallKitParams p) => p.extra?['callerId'] as String? ?? '';

      switch (event) {
        case CallEventActionCallIncoming(:final callKitParams):
          _watchRingingCall(
            familyChatIdOf(callKitParams),
            callKitParams.extra?['callId'] as String? ?? '',
          );
          break;

        case CallEventActionCallAccept(:final callKitParams):
          if (kDebugMode) print('📞 [CALLKIT] Call accepted (${callKitParams.id})');
          _ringingWatcher?.cancel();
          if (callKitParams.id == _activeCallUuid) {
            // Il plugin può emettere l'accept due volte per la stessa
            // chiamata (in particolare con app in primo piano): ignora.
            if (kDebugMode) print('📞 [CALLKIT] Duplicate accept for active call → ignored');
            break;
          }
          if (callScreenActive) {
            // Glare: siamo già in un'ALTRA chiamata. Chiudi solo questa
            // entry CallKit senza toccare quella della chiamata in corso.
            if (kDebugMode) print('⚠️ [CALLKIT] Accept while another call is active → dropping');
            FlutterCallkitIncoming.endCall(callKitParams.id).catchError((_) {});
            break;
          }
          _activeCallUuid = callKitParams.id;
          onIncomingCall?.call(familyChatIdOf(callKitParams), callerIdOf(callKitParams));
          break;

        case CallEventActionCallDecline(:final callKitParams):
          if (kDebugMode) print('📞 [CALLKIT] Call declined (extra: ${callKitParams.extra})');
          _ringingWatcher?.cancel();
          _activeCallUuid = null;
          _lastDeclinedCallId = callKitParams.extra?['callId'] as String?;
          onCallDeclined?.call(familyChatIdOf(callKitParams), callerIdOf(callKitParams));
          break;

        case CallEventActionCallEnded(:final callKitParams):
          if (kDebugMode) print('📞 [CALLKIT] Call ended (${callKitParams.id}, active: $_activeCallUuid)');
          _ringingWatcher?.cancel();
          if (_activeCallUuid != null && callKitParams.id != _activeCallUuid) {
            // Fine di un'entry CallKit diversa da quella della chiamata in
            // corso (es. glare scartato): non toccare la chiamata attiva.
            if (kDebugMode) print('📞 [CALLKIT] Ended event for a different call → ignored');
            break;
          }
          _activeCallUuid = null;
          onNativeCallEnded?.call();
          onCallEnded?.call(familyChatIdOf(callKitParams), callerIdOf(callKitParams));
          break;

        case CallEventActionCallTimeout():
          if (kDebugMode) print('📞 [CALLKIT] Call timeout');
          _activeCallUuid = null;
          _ringingWatcher?.cancel();
          break;

        case CallEventActionDidUpdateDevicePushTokenVoip():
          // iOS: PushKit ha rinnovato il token VoIP → risalva su Firestore
          if (kDebugMode) print('📞 [CALLKIT] VoIP push token updated');
          if (_savedFamilyChatId != null && _savedUserId != null) {
            saveTokenToFirestore(_savedFamilyChatId!, _savedUserId!);
          }
          break;

        default:
          break;
      }
    });
  }

  /// Se all'avvio c'è una chiamata CallKit già accettata (app lanciata da
  /// PushKit o dalla notifica full screen), apri la schermata chiamata.
  Future<void> _resumeAcceptedCallIfAny() async {
    try {
      final calls = await FlutterCallkitIncoming.activeCalls();
      for (final call in calls) {
        if (!call.isAccepted) continue;
        final extra = call.extra ?? const {};
        final familyChatId = extra['familyChatId'] as String? ?? '';
        final callerId = extra['callerId'] as String? ?? '';
        final callId = extra['callId'] as String? ?? '';
        if (familyChatId.isEmpty) continue;

        // Il plugin può conservare una chiamata "accettata" di una sessione
        // precedente (crash, kill). Riprendila solo se su Firestore è
        // ancora viva, altrimenti ripulisci CallKit.
        final alive = await _isCallStillAlive(familyChatId, callId);
        if (!alive) {
          if (kDebugMode) print('🧹 [CALLKIT] Stale accepted call ${call.id} → ending');
          await FlutterCallkitIncoming.endCall(call.id);
          continue;
        }
        if (kDebugMode) print('📞 [CALLKIT] Resuming accepted call ${call.id}');
        _activeCallUuid = call.id;
        onIncomingCall?.call(familyChatId, callerId);
        return;
      }
    } catch (e) {
      if (kDebugMode) print('⚠️ [CALLKIT] activeCalls() failed: $e');
    }
  }

  Future<bool> _isCallStillAlive(String familyChatId, String callId) async {
    try {
      final snap = await _firestore
          .collection('families')
          .doc(familyChatId)
          .collection('calls')
          .doc('current')
          .get(const GetOptions(source: Source.server));
      final data = snap.data();
      if (!snap.exists || data == null) return false;
      final status = data['status'] as String?;
      if (status != 'ringing' && status != 'connected') return false;
      if (callId.isNotEmpty && data['callId'] != null && data['callId'] != callId) {
        return false;
      }
      return true;
    } catch (e) {
      if (kDebugMode) print('⚠️ [CALLKIT] Cannot verify call on Firestore: $e');
      return false;
    }
  }

  /// Mentre CallKit squilla, osserva il documento chiamata: se il caller
  /// riaggancia (status ended / documento eliminato) chiudi la UI nativa
  /// invece di lasciarla squillare fino al timeout.
  ///
  /// Attenzione alla cache Firestore: il primo snapshot può essere lo stato
  /// della chiamata PRECEDENTE (documento cancellato o `ended`). Per questo
  /// ignoriamo gli snapshot dalla cache, agiamo solo dopo aver visto dal
  /// server la chiamata in corso, e confrontiamo il `callId`.
  void _watchRingingCall(String familyChatId, String callId) {
    if (familyChatId.isEmpty) return;
    _ringingWatcher?.cancel();
    _ringingCallId = callId.isEmpty ? null : callId;
    bool seenRingingFromServer = false;

    _ringingWatcher = _firestore
        .collection('families')
        .doc(familyChatId)
        .collection('calls')
        .doc('current')
        .snapshots()
        .listen((snap) {
      if (snap.metadata.isFromCache) return;
      final data = snap.data();

      if (snap.exists) {
        final docCallId = data?['callId'] as String?;
        if (callId.isNotEmpty && docCallId != null && docCallId != callId) {
          return; // documento di un'altra chiamata
        }
        final status = data?['status'] as String?;
        if (status == 'ringing') {
          seenRingingFromServer = true;
          return;
        }
        if (status != 'ended' && status != 'declined') return;
      } else if (!seenRingingFromServer) {
        return; // non abbiamo ancora visto questa chiamata: non è un annullamento
      }

      if (kDebugMode) print('📞 [CALLKIT] Caller cancelled while ringing → dismiss');
      _ringingWatcher?.cancel();
      _ringingWatcher = null;
      _dismissRingingCallKit();
    }, onError: (_) {});

    // Sicurezza: non restare in ascolto oltre lo squillo
    Future.delayed(const Duration(seconds: 40), () {
      _ringingWatcher?.cancel();
      _ringingWatcher = null;
    });
  }

  /// Registra una chiamata in uscita nel sistema (CallKit / ConnectionService).
  /// iOS: la chiamata compare nel lock screen e CallKit gestisce la sessione
  /// audio. Android: parte il foreground service con tipo microphone, così
  /// il microfono continua a funzionare con app in background o schermo spento.
  Future<void> startOutgoingCallKit(String familyChatId, String myUserId) async {
    final uuid = _generateUUID();
    try {
      await FlutterCallkitIncoming.startCall(CallKitParams(
        id: uuid,
        nameCaller: 'Partner',
        appName: 'TuyJo',
        handle: 'TuyJo',
        type: 0,
        extra: <String, dynamic>{
          'familyChatId': familyChatId,
          'callerId': myUserId,
        },
        android: _callKitAndroidParams,
        ios: _callKitIosParams,
      ));
      _activeCallUuid = uuid;
      if (kDebugMode) print('📞 [CALLKIT] Outgoing call registered: $uuid');
    } catch (e) {
      if (kDebugMode) print('⚠️ [CALLKIT] startCall failed: $e');
    }
  }

  /// Segnala al sistema che la chiamata è connessa (timer nativo, notifica
  /// "chiamata in corso" su Android).
  Future<void> setCallKitConnected() async {
    final uuid = _activeCallUuid;
    if (uuid == null) return;
    try {
      await FlutterCallkitIncoming.setCallConnected(uuid);
    } catch (e) {
      if (kDebugMode) print('⚠️ [CALLKIT] setCallConnected failed: $e');
    }
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
    _ringingWatcher?.cancel();
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (e) {
      if (kDebugMode) print('⚠️ [CALLKIT] Error cancelling call: $e');
    }
    _activeCallUuid = null;
  }

  Future<String?> getToken() async {
    try {
      return await _firebaseMessaging.getToken();
    } catch (e) {
      if (kDebugMode) print('⚠️ FCM getToken failed: $e');
      return null;
    }
  }

  Future<void> saveTokenToFirestore(
    String familyChatId,
    String userId,
  ) async {
    // Salva per onTokenRefresh
    _savedFamilyChatId = familyChatId;
    _savedUserId = userId;

    try {
      String? token = await getToken();

      // iOS: token PushKit VoIP. Le chiamate in arrivo su iOS arrivano SOLO
      // via push VoIP (i push FCM in background non sono affidabili e non
      // vengono consegnati ad app terminata). La Cloud Function lo usa
      // per inviare direttamente ad APNs.
      String? voipToken;
      if (Platform.isIOS) {
        try {
          final t = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
          if (t != null && t.isNotEmpty) voipToken = t;
        } catch (e) {
          if (kDebugMode) print('⚠️ getDevicePushTokenVoIP failed: $e');
        }
      }

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
        if (voipToken != null) 'voip_token': voipToken,
        'platform': Platform.isIOS ? 'ios' : 'android',
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

  /// Dimentica il target di salvataggio del token. Da chiamare quando questo
  /// telefono lascia la chat (unpair / wipe): senza, onTokenRefresh
  /// ri-scriverebbe il token FCM sulla famiglia abbandonata e il telefono
  /// continuerebbe a ricevere notifiche per una chat che non ha più.
  void clearSavedTokenTarget() {
    _savedFamilyChatId = null;
    _savedUserId = null;
    if (kDebugMode) print('🔇 Token save target cleared');
  }

  static const _badgeChannel = MethodChannel('com.privatemessaging.tuyjo/badge');

  /// Azzera il badge dell'app (icona notifiche).
  /// Android: il badge del launcher segue le notifiche → basta cancellarle.
  /// iOS: il badge è un numero indipendente dalle notifiche, impostato dal
  /// push; va azzerato esplicitamente via canale nativo.
  Future<void> clearBadge() async {
    try {
      // Cancella tutte le notifiche dalla barra di notifica
      await _localNotifications.cancelAll();
    } catch (e) {
      if (kDebugMode) print('❌ Error cancelling notifications: $e');
    }
    if (Platform.isIOS) {
      try {
        await _badgeChannel.invokeMethod('set', 0);
      } catch (e) {
        if (kDebugMode) print('❌ Error clearing iOS badge: $e');
      }
    }
    if (kDebugMode) print('🔴 Badge cleared');
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
