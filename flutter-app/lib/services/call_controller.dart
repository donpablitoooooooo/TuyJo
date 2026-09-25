import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'encryption_service.dart';
import 'notification_service.dart';
import 'pairing_service.dart';
import 'webrtc_service.dart';

enum CallState {
  ringing,
  connecting,
  connected,
  reconnecting,
  ended,
}

/// Esito di [CallController.start].
enum CallStartResult {
  /// Chiamata avviata (o già terminata dal partner nel frattempo).
  started,

  /// Microfono non disponibile: la chiamata NON è stata chiusa, così la
  /// schermata può spiegarlo all'utente prima di chiamare [CallController.endCall].
  micUnavailable,

  /// Avvio fallito: la chiamata è già stata chiusa e il partner avvisato.
  failed,
}

/// Una chiamata vocale in corso, indipendente dalla UI.
///
/// Prima tutta la logica viveva nella `VoiceCallScreen`: una chiamata
/// accettata dalla schermata di sistema (iPhone bloccato, app in background)
/// non partiva, perché con l'app in background Flutter non costruisce
/// widget, quindi nessuno rispondeva e il chiamante continuava a squillare.
/// Ora la risposta parte appena si accetta da CallKit e la schermata, quando
/// viene aperta, si limita a mostrare questo controller.
///
/// C'è al massimo una chiamata attiva alla volta ([active]).
class CallController extends ChangeNotifier {
  CallController._({
    required this.isOutgoing,
    required EncryptionService encryption,
    required PairingService pairing,
    required NotificationService notifications,
    this.familyChatIdHint,
  })  : _encryption = encryption,
        _pairing = pairing,
        _notifications = notifications,
        _webrtc = WebRTCService(encryptionService: encryption);

  /// Crea la chiamata e la registra come [active].
  factory CallController.create({
    required bool isOutgoing,
    required EncryptionService encryption,
    required PairingService pairing,
    required NotificationService notifications,
    String? familyChatIdHint,
  }) {
    final controller = CallController._(
      isOutgoing: isOutgoing,
      encryption: encryption,
      pairing: pairing,
      notifications: notifications,
      familyChatIdHint: familyChatIdHint,
    );
    _active = controller;
    return controller;
  }

  static CallController? _active;

  /// La chiamata in corso, se c'è (null anche dopo la sua chiusura).
  static CallController? get active => _active;

  /// Deve coincidere con `duration: 30000` in CallKitParams: lo squillo
  /// lato caller e lato callee finiscono insieme.
  static const ringTimeout = Duration(seconds: 30);

  final bool isOutgoing;

  /// familyChatId arrivato con la chiamata (extra CallKit): serve per
  /// avvisare il chiamante anche se le chiavi locali non sono leggibili.
  final String? familyChatIdHint;

  final EncryptionService _encryption;
  final PairingService _pairing;
  final NotificationService _notifications;
  final WebRTCService _webrtc;

  CallState _state = CallState.ringing;
  CallState get state => _state;

  bool _isMuted = false;
  bool get isMuted => _isMuted;

  bool _isSpeakerOn = false;
  bool get isSpeakerOn => _isSpeakerOn;

  bool _partnerMuted = false;
  bool get partnerMuted => _partnerMuted;

  int _durationSeconds = 0;
  int get durationSeconds => _durationSeconds;

  CallStats? _stats;
  CallStats? get stats => _stats;

  /// I due telefoni non riescono a parlarsi in diretta: la schermata mostra
  /// il pop-up e alla sua chiusura chiama [endCall].
  bool _p2pUnavailable = false;
  bool get p2pUnavailable => _p2pUnavailable;

  /// true da quando la chiusura è iniziata.
  bool _ending = false;
  bool get isEnding => _ending;

  /// true a chiusura completata (WebRTC, CallKit e Firestore puliti).
  bool _finished = false;
  bool get isFinished => _finished;

  /// Impostato dalla schermata mentre è montata.
  bool screenAttached = false;

  String? _familyChatId;
  String? _myUserId;
  bool _started = false;
  Timer? _callTimer;
  Timer? _ringingTimeoutTimer;
  VoidCallback? _nativeEndedHandler;

  /// Avvia la chiamata. Per la chiamata in uscita la spiegazione sul
  /// permesso del microfono va mostrata dalla schermata PRIMA di chiamarlo.
  ///
  /// Non lancia mai: qualsiasi errore chiude la chiamata e avvisa il partner,
  /// così dall'altra parte non si resta a squillare fino al timeout.
  Future<CallStartResult> start() async {
    if (_started) return CallStartResult.started;
    _started = true;

    _notifications.callScreenActive = true;
    _nativeEndedHandler = () => endCall(localHangup: true, fromNative: true);
    _notifications.onNativeCallEnded = _nativeEndedHandler;

    try {
      // Avvio a freddo da CallKit: pairing e chiavi potrebbero non essere
      // ancora caricati (in main.dart partono senza await).
      await _pairing.initialize();
      if (_encryption.privateKeyBase64 == null) {
        await _encryption.loadStoredKeyPair();
      }
      _familyChatId = await _pairing.getFamilyChatId();
      _myUserId = await _pairing.getMyUserId();
    } catch (e) {
      _diag('pairing/chiavi non leggibili: $e');
    }
    final partnerPublicKey = _pairing.partnerPublicKey;
    if (_familyChatId == null || _myUserId == null || partnerPublicKey == null) {
      _diag('non accoppiato o chiavi non disponibili: chiamata chiusa');
      await endCall(localHangup: true);
      return CallStartResult.failed;
    }

    _wireCallbacks();

    try {
      await _webrtc.initialize();
    } catch (e) {
      _diag('WebRTC non inizializzato (microfono?): $e');
      return CallStartResult.micUnavailable;
    }
    if (_ending) return CallStartResult.started;

    try {
      if (isOutgoing) {
        // CallKit "startCall" registra la chiamata nel sistema (iOS: sessione
        // audio + lock screen; Android: foreground service con microfono così
        // la chiamata sopravvive in background).
        await _notifications.startOutgoingCallKit(_familyChatId!, _myUserId!);
        await _webrtc.startCall(
          familyChatId: _familyChatId!,
          myUserId: _myUserId!,
          partnerPublicKey: partnerPublicKey,
        );
        // Nel frattempo la chiamata può essere stata chiusa: lo squillo non
        // deve ripartire dopo la chiusura (resterebbe acceso per sempre).
        if (_ending) return CallStartResult.started;
        _startRingbackTone();
        _ringingTimeoutTimer = Timer(ringTimeout, () {
          if (_state == CallState.ringing) {
            _diag('nessuna risposta entro ${ringTimeout.inSeconds}s');
            endCall(localHangup: true);
          }
        });
      } else {
        // Chiamata in entrata già accettata via CallKit: rispondi subito
        _setState(CallState.connecting);
        final ok = await _webrtc.answerCall(
          familyChatId: _familyChatId!,
          myUserId: _myUserId!,
        );
        if (!ok) {
          _diag('offer non trovata o non decifrabile: chiamata chiusa');
          await endCall(localHangup: true);
          return CallStartResult.failed;
        }
      }
    } catch (e) {
      _diag('avvio chiamata fallito: $e');
      await endCall(localHangup: true);
      return CallStartResult.failed;
    }
    return CallStartResult.started;
  }

  void _wireCallbacks() {
    _webrtc.onAnswerReceived = () {
      _stopRingbackTone();
      _ringingTimeoutTimer?.cancel();
      if (_state == CallState.ringing) _setState(CallState.connecting);
    };

    _webrtc.onConnected = () {
      if (_ending) return;
      _stopRingbackTone();
      _ringingTimeoutTimer?.cancel();
      _notifications.setCallKitConnected();
      _startCallTimer();
      _setState(CallState.connected);
    };

    _webrtc.onReconnecting = () {
      if (_ending) return;
      _setState(CallState.reconnecting);
    };

    _webrtc.onReconnected = () {
      if (_ending) return;
      _setState(CallState.connected);
    };

    _webrtc.onP2PUnavailable = () {
      if (_ending || _p2pUnavailable) return;
      _p2pUnavailable = true;
      _stopRingbackTone();
      final inForeground =
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
      if (screenAttached && inForeground) {
        notifyListeners();
      } else {
        // Nessuna schermata a cui spiegarlo (UI di sistema, app in
        // background): notifica che spiega il motivo, poi chiudi.
        _notifications.showCallFailedNotification();
        endCall(localHangup: true);
      }
    };

    _webrtc.onRemoteHangup = (reason) {
      if (kDebugMode) print('📞 [CALL] Remote hangup: $reason');
      endCall(localHangup: false);
    };

    _webrtc.onPartnerMuteChanged = (muted) {
      _partnerMuted = muted;
      notifyListeners();
    };

    _webrtc.onStats = (stats) {
      _stats = stats;
      notifyListeners();
    };
  }

  void toggleMute() {
    if (_ending) return;
    _isMuted = !_isMuted;
    _webrtc.setMicMuted(_isMuted);
    notifyListeners();
  }

  void toggleSpeaker() {
    if (_ending) return;
    _isSpeakerOn = !_isSpeakerOn;
    _webrtc.setSpeakerOn(_isSpeakerOn);
    notifyListeners();
  }

  /// Termina la chiamata.
  /// [localHangup] true se abbiamo riagganciato noi (avvisa il partner),
  /// false se è stato il partner (non serve avvisare).
  /// [fromNative] true se la chiusura arriva dalla UI di sistema (CallKit /
  /// notifica Android): la chiamata di sistema è già chiusa.
  Future<void> endCall({required bool localHangup, bool fromNative = false}) async {
    if (_ending) return;
    _ending = true;
    _stopRingbackTone();
    _callTimer?.cancel();
    _ringingTimeoutTimer?.cancel();
    _setState(CallState.ended);

    try {
      if (localHangup) {
        // 1. "bye" P2P istantaneo, 2. stato su Firestore (fallback + cancel push)
        await _webrtc.sendBye();
        // Offline una scrittura Firestore non si completa finché non torna la
        // rete: non deve bloccare la chiusura (resta comunque in coda).
        await _writeEnded().timeout(const Duration(seconds: 5), onTimeout: () {});
      }
      // Chiudi WebRTC (così l'audio si ferma). Timeout: se lo smontaggio si
      // blocca non deve impedire la chiusura di CallKit qui sotto.
      await _webrtc.dispose().timeout(const Duration(seconds: 3));
    } catch (e) {
      _diag('errore durante la chiusura: $e');
    }
    // Poi termina CallKit (ora è safe disattivare la sessione audio).
    // Va fatto SEMPRE: se resta aperta, su Android rimangono la notifica
    // "chiamata in corso" e la connessione Telecom che blocca le chiamate
    // di altre app finché non si preme "Riaggancia".
    if (!fromNative) {
      await _notifications.endCallKit();
    }
    if (identical(_notifications.onNativeCallEnded, _nativeEndedHandler)) {
      _notifications.onNativeCallEnded = null;
    }
    _notifications.callScreenActive = false;

    _finished = true;
    if (identical(_active, this)) _active = null;
    notifyListeners();

    // Pulizia del documento chiamata: dopo la chiusura e senza attenderla
    // (offline non si completerebbe).
    final fid = _familyChatId;
    if (fid != null) {
      _webrtc.cleanupFirestore(fid).catchError((Object e) {
        if (kDebugMode) print('⚠️ [CALL] Error cleaning up call state: $e');
      });
    }
  }

  /// Scrive lo stato finale della chiamata su Firestore.
  /// `ended_by` permette alla Cloud Function di mandare al callee un push
  /// di annullamento se il caller riaggancia mentre squilla ancora.
  Future<void> _writeEnded() async {
    final fid = _familyChatId ?? familyChatIdHint;
    if (fid == null || fid.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('families')
          .doc(fid)
          .collection('calls')
          .doc('current')
          .set({
        'status': 'ended',
        if (_myUserId != null) 'ended_by': _myUserId,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      _diag('scrittura "ended" fallita: $e');
    }
  }

  void _setState(CallState state) {
    if (_state == state) return;
    _state = state;
    notifyListeners();
  }

  void _startCallTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _durationSeconds++;
      notifyListeners();
    });
  }

  // ─── Ringback tone nativo (ToneGenerator / AVAudioPlayer) ────────
  static const _toneChannel = MethodChannel('com.privatemessaging.tuyjo/tone_generator');
  bool _ringbackPlaying = false;

  Future<void> _startRingbackTone() async {
    if (_ringbackPlaying) return;
    _ringbackPlaying = true;
    try {
      await _toneChannel.invokeMethod('startRingback');
    } catch (e) {
      if (kDebugMode) print('⚠️ [CALL] Could not start ringback tone: $e');
    }
  }

  Future<void> _stopRingbackTone() async {
    if (!_ringbackPlaying) return;
    _ringbackPlaying = false;
    try {
      await _toneChannel.invokeMethod('stopRingback');
    } catch (e) {
      if (kDebugMode) print('⚠️ [CALL] Could not stop ringback tone: $e');
    }
  }

  /// Log visibile anche in release (logcat tag `flutter`, console Xcode):
  /// solo per i casi in cui una chiamata fallisce.
  void _diag(String message) {
    debugPrint('📞 [CALL] $message');
  }
}
