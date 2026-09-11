import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import 'encryption_service.dart';

/// Stato di connettività del media P2P (indipendente dallo stato UI).
enum P2PConnectionState {
  idle,
  connecting,
  connected,
  reconnecting,
  failed,
  closed,
}

/// Qualità stimata della connessione, derivata dalle statistiche WebRTC.
enum CallQuality { unknown, good, fair, poor }

/// Statistiche di rete raccolte da `getStats()` ogni pochi secondi.
class CallStats {
  final double? rttMs;
  final double? jitterMs;
  final double lossPercent;
  final int? bitrateKbps;
  final String? localCandidateType;
  final String? remoteCandidateType;

  const CallStats({
    this.rttMs,
    this.jitterMs,
    this.lossPercent = 0,
    this.bitrateKbps,
    this.localCandidateType,
    this.remoteCandidateType,
  });

  CallQuality get quality {
    if (rttMs == null && jitterMs == null) return CallQuality.unknown;
    final rtt = rttMs ?? 0;
    final jitter = jitterMs ?? 0;
    if (lossPercent > 8 || rtt > 500 || jitter > 80) return CallQuality.poor;
    if (lossPercent > 3 || rtt > 250 || jitter > 40) return CallQuality.fair;
    return CallQuality.good;
  }

  /// Percorso di rete: 'host' = stessa LAN, 'srflx'/'prflx' = attraverso NAT
  /// con STUN, 'relay' = TURN (mai, finché non c'è un TURN server).
  String get pathLabel {
    final l = localCandidateType ?? '?';
    final r = remoteCandidateType ?? '?';
    return '$l ↔ $r';
  }

  @override
  String toString() =>
      'CallStats(rtt=${rttMs?.toStringAsFixed(0)}ms jitter=${jitterMs?.toStringAsFixed(0)}ms '
      'loss=${lossPercent.toStringAsFixed(1)}% br=${bitrateKbps}kbps path=$pathLabel)';
}

/// Servizio WebRTC per chiamate vocali peer-to-peer.
///
/// Signaling su Firestore (`families/{id}/calls/current`), cifrato end-to-end:
/// il caller genera una chiave AES-256 di sessione, la avvolge con la chiave
/// pubblica RSA del partner e cifra con AES-GCM offer, answer e candidati ICE.
/// Firestore vede solo ciphertext: niente SDP, fingerprint DTLS o IP in chiaro.
///
/// Flusso:
/// 1. Caller: [startCall] → scrive offer cifrata + candidati su Firestore
/// 2. Callee: [answerCall] → legge offer, scrive answer + candidati
/// 3. Entrambi ascoltano candidati e stato documento
/// 4. Dopo la connessione un RTCDataChannel `control` trasporta hangup e
///    mute in puro P2P (istantaneo, senza passare da Firestore)
/// 5. Su perdita di rete: grace period → ICE restart (offer/answer con
///    nuova generazione). Se fallisce definitivamente → [onP2PUnavailable]
class WebRTCService {
  WebRTCService({
    required EncryptionService encryptionService,
  }) : _encryption = encryptionService;

  final EncryptionService _encryption;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  RTCDataChannel? _controlChannel;

  StreamSubscription? _remoteCandidatesSubscription;
  StreamSubscription? _docSubscription;
  Timer? _statsTimer;
  Timer? _graceTimer;
  Timer? _connectTimeoutTimer;

  bool _isCaller = false;
  bool _disposed = false;
  String? _familyChatId;
  String? _callId;
  String? _sessionKeyBase64;

  /// Generazione ICE corrente (0 = prima negoziazione, +1 per ogni restart)
  int _gen = 0;
  int _lastRestartRequestHandled = 0;
  int _restartCount = 0;
  bool _restarting = false;
  DateTime? _restartStartedAt;
  bool _remoteDescriptionSet = false;
  bool _everConnected = false;
  bool _p2pFailureReported = false;

  /// Candidati remoti arrivati prima della remote description (per gen)
  final List<_PendingCandidate> _pendingCandidates = [];
  final Set<String> _seenCandidateDocs = {};

  P2PConnectionState _state = P2PConnectionState.idle;
  P2PConnectionState get state => _state;
  bool get isConnected => _state == P2PConnectionState.connected;
  CallStats? lastStats;

  // ─── Callback verso la UI ────────────────────────────────────────────
  /// Prima connessione media stabilita
  VoidCallback? onConnected;
  /// Connessione ripristinata dopo un ICE restart
  VoidCallback? onReconnected;
  /// Persa la connettività, tentativo di ripristino in corso
  VoidCallback? onReconnecting;
  /// Nessun percorso P2P trovato (o perso definitivamente). Senza TURN non
  /// possiamo fare altro: la UI mostra il pop-up "non disponibile in P2P".
  VoidCallback? onP2PUnavailable;
  /// Il partner ha riagganciato (via data channel o Firestore).
  /// [reason] ∈ {'bye', 'ended', 'declined', 'deleted'}
  void Function(String reason)? onRemoteHangup;
  /// Il partner ha attivato/disattivato il muto
  void Function(bool muted)? onPartnerMuteChanged;
  /// Il callee ha risposto (answer ricevuta): ICE in corso
  VoidCallback? onAnswerReceived;
  /// Nuove statistiche disponibili
  void Function(CallStats stats)? onStats;

  // ─── Configurazione ──────────────────────────────────────────────────
  static const _graceBeforeRestart = Duration(seconds: 4);
  static const _connectTimeout = Duration(seconds: 20);
  static const _recoveryTimeout = Duration(seconds: 10);
  /// Restart massimi: se non ci siamo MAI connessi, un fallimento iniziale è
  /// già una prova forte che non c'è percorso P2P → un solo ritentativo.
  static const _maxRestartsAfterConnected = 3;
  static const _maxRestartsNeverConnected = 1;
  int get _maxRestarts =>
      _everConnected ? _maxRestartsAfterConnected : _maxRestartsNeverConnected;
  static const _statsInterval = Duration(seconds: 2);

  /// STUN pubblici: più provider così se uno è bloccato dalla rete
  /// (es. alcune reti aziendali filtrano Google) l'altro risponde.
  /// `iceCandidatePoolSize` pre-raccoglie i candidati alla creazione del
  /// peer connection: la fase ICE parte già con i candidati pronti.
  static final Map<String, dynamic> _rtcConfig = {
    'iceServers': [
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
        ]
      },
      {'urls': 'stun:stun.cloudflare.com:3478'},
    ],
    'iceCandidatePoolSize': 2,
    'bundlePolicy': 'max-bundle',
    'rtcpMuxPolicy': 'require',
    'sdpSemantics': 'unified-plan',
  };

  /// Vincoli audio espliciti: AEC, noise suppression, AGC e highpass.
  /// Android li aggiunge da solo, iOS no: esplicitarli è gratis.
  static final Map<String, dynamic> _audioConstraints = {
    'audio': {
      'mandatory': {
        'googEchoCancellation': true,
        'googNoiseSuppression': true,
        'googAutoGainControl': true,
        'googHighpassFilter': true,
      },
      'optional': <Map<String, dynamic>>[],
    },
    'video': false,
  };

  DocumentReference<Map<String, dynamic>> _callDoc(String familyChatId) =>
      _firestore
          .collection('families')
          .doc(familyChatId)
          .collection('calls')
          .doc('current');

  // ═══════════════════════════════════════════════════════════════════
  // Inizializzazione
  // ═══════════════════════════════════════════════════════════════════

  /// Configura la sessione audio nativa, crea il peer connection e cattura
  /// il microfono.
  Future<void> initialize() async {
    await _configureNativeAudio();

    _peerConnection = await createPeerConnection(_rtcConfig);
    final pc = _peerConnection!;

    _localStream = await navigator.mediaDevices.getUserMedia(_audioConstraints);
    for (final track in _localStream!.getAudioTracks()) {
      await pc.addTrack(track, _localStream!);
    }

    pc.onTrack = (RTCTrackEvent event) {
      _log('Remote track received: ${event.track.kind}');
    };

    pc.onIceConnectionState = _handleIceState;

    pc.onConnectionState = (RTCPeerConnectionState state) {
      _log('PC state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _handleConnectivityLoss(immediate: true);
      }
    };

    pc.onIceGatheringState = (state) => _log('ICE gathering: $state');
    pc.onSignalingState = (state) => _log('Signaling: $state');

    // Il callee riceve il data channel creato dal caller
    pc.onDataChannel = (RTCDataChannel channel) {
      _log('Data channel received: ${channel.label}');
      _attachControlChannel(channel);
    };
  }

  Future<void> _configureNativeAudio() async {
    try {
      if (Platform.isAndroid) {
        await Helper.setAndroidAudioConfiguration(AndroidAudioConfiguration(
          manageAudioFocus: true,
          androidAudioMode: AndroidAudioMode.inCommunication,
          androidAudioFocusMode: AndroidAudioFocusMode.gainTransient,
          androidAudioStreamType: AndroidAudioStreamType.voiceCall,
          androidAudioAttributesUsageType:
              AndroidAudioAttributesUsageType.voiceCommunication,
          androidAudioAttributesContentType:
              AndroidAudioAttributesContentType.speech,
        ));
      } else if (Platform.isIOS) {
        await Helper.setAppleAudioConfiguration(AppleAudioConfiguration(
          appleAudioCategory: AppleAudioCategory.playAndRecord,
          appleAudioCategoryOptions: {
            AppleAudioCategoryOption.allowBluetooth,
            AppleAudioCategoryOption.allowBluetoothA2DP,
          },
          appleAudioMode: AppleAudioMode.voiceChat,
        ));
      }
    } catch (e) {
      _log('⚠️ Native audio configuration failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // CALLER
  // ═══════════════════════════════════════════════════════════════════

  /// Crea l'offer e scrive su Firestore, in un'unica scrittura, stato
  /// `ringing` + chiave di sessione + offer cifrata. Il documento viene
  /// sovrascritto (no merge) così nessun residuo di chiamate precedenti
  /// (answer vecchia, candidati) può inquinare questa.
  Future<void> startCall({
    required String familyChatId,
    required String myUserId,
    required String partnerPublicKey,
  }) async {
    final pc = _peerConnection;
    if (pc == null) return;

    _isCaller = true;
    _familyChatId = familyChatId;
    _callId = const Uuid().v4();
    _sessionKeyBase64 = _encryption.generateSessionKey();
    _gen = 0;
    _setState(P2PConnectionState.connecting);

    final callDoc = _callDoc(familyChatId);
    await _wipeCandidates(callDoc);

    pc.onIceCandidate = (c) => _publishCandidate('callerCandidates', c);

    // Data channel di controllo (deve esistere prima dell'offer per finire nell'SDP)
    final init = RTCDataChannelInit()..ordered = true;
    final channel = await pc.createDataChannel('control', init);
    _attachControlChannel(channel);

    final offer = await pc.createOffer({});
    final tuned = RTCSessionDescription(_tuneOpus(offer.sdp!), offer.type);
    await pc.setLocalDescription(tuned);

    final wrappedKey = _encryption.encryptAesKeyOnly(
      base64Decode(_sessionKeyBase64!),
      partnerPublicKey,
    );

    await callDoc.set({
      'status': 'ringing',
      'caller_id': myUserId,
      'callId': _callId,
      'started_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
      'key_for_callee': wrappedKey,
      'offer': _seal({'type': tuned.type, 'sdp': tuned.sdp}),
      'offerGen': 0,
      'v': 2,
    });
    _log('Offer written (callId=${_callId!.substring(0, 8)})');

    _listenCallDoc(callDoc);
    _listenRemoteCandidates(callDoc.collection('calleeCandidates'));
  }

  // ═══════════════════════════════════════════════════════════════════
  // CALLEE
  // ═══════════════════════════════════════════════════════════════════

  /// Legge l'offer, decifra la chiave di sessione, scrive answer + stato
  /// `connected` in una sola scrittura. Ritorna false se l'offer non c'è.
  Future<bool> answerCall({
    required String familyChatId,
    required String myUserId,
  }) async {
    final pc = _peerConnection;
    if (pc == null) return false;

    _isCaller = false;
    _familyChatId = familyChatId;
    final callDoc = _callDoc(familyChatId);

    // Leggi dal server: la cache locale potrebbe non avere ancora l'offer
    Map<String, dynamic>? data;
    for (int attempt = 0; attempt < 6; attempt++) {
      try {
        final snap = await callDoc.get(const GetOptions(source: Source.server));
        final d = snap.data();
        if (snap.exists && d != null && d['offer'] != null && d['key_for_callee'] != null) {
          data = d;
          break;
        }
      } catch (e) {
        _log('⚠️ Server read attempt $attempt failed: $e');
      }
      await Future.delayed(Duration(milliseconds: 400 * (attempt + 1)));
    }
    if (data == null) {
      _log('❌ No offer found in Firestore');
      return false;
    }

    try {
      final keyBytes = _encryption.decryptAesKeyOnly(data['key_for_callee'] as String);
      _sessionKeyBase64 = base64Encode(keyBytes);
    } catch (e) {
      _log('❌ Cannot unwrap session key: $e');
      return false;
    }
    _callId = data['callId'] as String?;
    _gen = (data['offerGen'] as num?)?.toInt() ?? 0;
    _setState(P2PConnectionState.connecting);

    pc.onIceCandidate = (c) => _publishCandidate('calleeCandidates', c);

    final offerJson = _open(data['offer']);
    if (offerJson == null) return false;
    await _applyRemoteOfferAndAnswer(callDoc, offerJson, _gen, initialStatus: 'connected');

    _listenCallDoc(callDoc);
    _listenRemoteCandidates(callDoc.collection('callerCandidates'));
    _startConnectTimeout();
    return true;
  }

  Future<void> _applyRemoteOfferAndAnswer(
    DocumentReference<Map<String, dynamic>> callDoc,
    Map<String, dynamic> offerJson,
    int gen, {
    String? initialStatus,
  }) async {
    final pc = _peerConnection!;
    final offer = RTCSessionDescription(
      _tuneOpus(offerJson['sdp'] as String),
      offerJson['type'] as String,
    );
    await pc.setRemoteDescription(offer);
    _remoteDescriptionSet = true;
    _flushPendingCandidates();
    _log('Remote offer set (gen=$gen)');

    final answer = await pc.createAnswer({});
    final tuned = RTCSessionDescription(_tuneOpus(answer.sdp!), answer.type);
    await pc.setLocalDescription(tuned);

    await callDoc.set({
      if (initialStatus != null) 'status': initialStatus,
      'updated_at': FieldValue.serverTimestamp(),
      'answer': _seal({'type': tuned.type, 'sdp': tuned.sdp}),
      'answerGen': gen,
    }, SetOptions(merge: true));
    _log('Answer written (gen=$gen)');
  }

  // ═══════════════════════════════════════════════════════════════════
  // Listener Firestore
  // ═══════════════════════════════════════════════════════════════════

  void _listenCallDoc(DocumentReference<Map<String, dynamic>> callDoc) {
    _docSubscription?.cancel();
    _docSubscription = callDoc.snapshots().listen((snapshot) async {
      if (_disposed) return;
      if (!snapshot.exists) {
        _log('Call document deleted → hangup');
        onRemoteHangup?.call('deleted');
        return;
      }
      final data = snapshot.data()!;
      final status = data['status'] as String?;
      if (status == 'ended' || status == 'declined') {
        onRemoteHangup?.call(status!);
        return;
      }
      // Documento di un'altra chiamata (residuo o nuova): ignora
      if (data['callId'] != null && _callId != null && data['callId'] != _callId) {
        return;
      }

      if (_isCaller) {
        await _callerHandleDoc(callDoc, data);
      } else {
        await _calleeHandleDoc(callDoc, data);
      }
    }, onError: (e) => _log('⚠️ Call doc listener error: $e'));
  }

  Future<void> _callerHandleDoc(
    DocumentReference<Map<String, dynamic>> callDoc,
    Map<String, dynamic> data,
  ) async {
    final pc = _peerConnection;
    if (pc == null) return;

    // Answer per la generazione corrente
    final answerGen = (data['answerGen'] as num?)?.toInt();
    if (data['answer'] != null && answerGen == _gen && !_remoteDescriptionSet) {
      final answerJson = _open(data['answer']);
      if (answerJson == null) return;
      final answer = RTCSessionDescription(
        _tuneOpus(answerJson['sdp'] as String),
        answerJson['type'] as String,
      );
      // Flag impostato PRIMA dell'await: i callback del listener Firestore
      // sono concorrenti e uno snapshot successivo (es. updated_at) non deve
      // riapplicare la stessa answer.
      _remoteDescriptionSet = true;
      try {
        await pc.setRemoteDescription(answer);
      } catch (e) {
        _log('⚠️ setRemoteDescription(answer) failed: $e');
        _remoteDescriptionSet = false;
        return;
      }
      _restarting = false;
      _flushPendingCandidates();
      _log('Remote answer set (gen=$_gen)');
      if (_gen == 0) {
        onAnswerReceived?.call();
        _startConnectTimeout();
      }
    }

    // Il callee ha perso la rete e chiede un restart
    final requested = (data['restartRequested'] as num?)?.toInt() ?? 0;
    if (requested > _lastRestartRequestHandled) {
      _lastRestartRequestHandled = requested;
      _log('Callee requested ICE restart #$requested');
      await _restartIce();
    }
  }

  Future<void> _calleeHandleDoc(
    DocumentReference<Map<String, dynamic>> callDoc,
    Map<String, dynamic> data,
  ) async {
    final offerGen = (data['offerGen'] as num?)?.toInt() ?? 0;
    if (offerGen > _gen && data['offer'] != null) {
      final offerJson = _open(data['offer']);
      if (offerJson == null) return;
      _log('New offer gen=$offerGen (ICE restart)');
      _gen = offerGen;
      _remoteDescriptionSet = false;
      _pendingCandidates.removeWhere((c) => c.gen < _gen);
      try {
        await _applyRemoteOfferAndAnswer(callDoc, offerJson, offerGen);
      } catch (e) {
        _log('⚠️ Restart answer failed: $e');
      }
    }
  }

  void _listenRemoteCandidates(CollectionReference<Map<String, dynamic>> col) {
    _remoteCandidatesSubscription?.cancel();
    _remoteCandidatesSubscription = col.snapshots().listen((snapshot) {
      if (_disposed) return;
      for (final change in snapshot.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        if (!_seenCandidateDocs.add(change.doc.id)) continue;
        final data = change.doc.data();
        if (data == null) continue;
        if (data['callId'] != _callId) continue; // residuo di altra chiamata
        final gen = (data['gen'] as num?)?.toInt() ?? 0;
        final json = _open(data['c']);
        if (json == null) continue;
        final candidate = RTCIceCandidate(
          json['candidate'] as String?,
          json['sdpMid'] as String?,
          (json['sdpMLineIndex'] as num?)?.toInt(),
        );
        _enqueueOrAddCandidate(_PendingCandidate(gen, candidate));
      }
    }, onError: (e) => _log('⚠️ Candidate listener error: $e'));
  }

  void _enqueueOrAddCandidate(_PendingCandidate pc) {
    if (pc.gen < _gen) return; // vecchia generazione, inutile
    if (pc.gen > _gen || !_remoteDescriptionSet) {
      _pendingCandidates.add(pc);
      return;
    }
    _addCandidate(pc.candidate);
  }

  void _flushPendingCandidates() {
    final ready = _pendingCandidates.where((c) => c.gen == _gen).toList();
    _pendingCandidates.removeWhere((c) => c.gen <= _gen);
    for (final c in ready) {
      _addCandidate(c.candidate);
    }
    if (ready.isNotEmpty) _log('Flushed ${ready.length} queued candidates');
  }

  Future<void> _addCandidate(RTCIceCandidate candidate) async {
    try {
      await _peerConnection?.addCandidate(candidate);
    } catch (e) {
      _log('⚠️ addCandidate failed: $e');
    }
  }

  void _publishCandidate(String subcollection, RTCIceCandidate candidate) {
    final c = candidate.candidate;
    if (_disposed || _familyChatId == null || c == null || c.isEmpty) return;
    _callDoc(_familyChatId!).collection(subcollection).add({
      'callId': _callId,
      'gen': _gen,
      'c': _seal({
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      }),
      'created_at': FieldValue.serverTimestamp(),
    }).then((_) {}, onError: (e) {
      _log('⚠️ Candidate write failed: $e');
    });
  }

  // ═══════════════════════════════════════════════════════════════════
  // Stato ICE, grace period, ICE restart
  // ═══════════════════════════════════════════════════════════════════

  void _handleIceState(RTCIceConnectionState state) {
    _log('ICE state: $state');
    switch (state) {
      case RTCIceConnectionState.RTCIceConnectionStateConnected:
      case RTCIceConnectionState.RTCIceConnectionStateCompleted:
        _graceTimer?.cancel();
        _connectTimeoutTimer?.cancel();
        _restartCount = 0;
        final wasReconnecting = _state == P2PConnectionState.reconnecting;
        _setState(P2PConnectionState.connected);
        if (!_everConnected) {
          _everConnected = true;
          _startStats();
          onConnected?.call();
        } else if (wasReconnecting) {
          onReconnected?.call();
        }
        break;
      case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
        _handleConnectivityLoss(immediate: false);
        break;
      case RTCIceConnectionState.RTCIceConnectionStateFailed:
        _handleConnectivityLoss(immediate: true);
        break;
      case RTCIceConnectionState.RTCIceConnectionStateClosed:
        _setState(P2PConnectionState.closed);
        break;
      default:
        break;
    }
  }

  /// `disconnected` è spesso transitorio (cambio Wi-Fi ↔ 4G): aspettiamo un
  /// grace period prima di fare ICE restart. `failed` è definitivo: restart
  /// subito. Esauriti i tentativi → P2P non disponibile.
  void _handleConnectivityLoss({required bool immediate}) {
    if (_disposed || _state == P2PConnectionState.closed) return;
    if (_state != P2PConnectionState.reconnecting) {
      _setState(P2PConnectionState.reconnecting);
      if (_everConnected) onReconnecting?.call();
    }
    _graceTimer?.cancel();
    if (immediate) {
      _attemptRecovery();
    } else {
      _graceTimer = Timer(_graceBeforeRestart, () {
        if (_state == P2PConnectionState.reconnecting) _attemptRecovery();
      });
    }
  }

  DateTime? _lastRecoveryAt;

  Future<void> _attemptRecovery() async {
    if (_disposed) return;
    // ICE `failed` e PeerConnection `failed` arrivano quasi insieme: un solo
    // tentativo per finestra, altrimenti bruciamo i restart disponibili.
    final now = DateTime.now();
    if (_lastRecoveryAt != null &&
        now.difference(_lastRecoveryAt!) < const Duration(seconds: 3)) {
      return;
    }
    _lastRecoveryAt = now;
    if (_restartCount >= _maxRestarts) {
      _reportP2PFailure();
      return;
    }
    if (_isCaller) {
      await _restartIce();
    } else {
      await _requestRestartFromCaller();
    }
    // Se entro il timeout non torniamo connected, riproviamo o ci arrendiamo
    _graceTimer?.cancel();
    _graceTimer = Timer(_recoveryTimeout, () {
      if (_state == P2PConnectionState.reconnecting) _attemptRecovery();
    });
  }

  /// Solo il caller rinegozia (evita glare). Nuova offer con iceRestart.
  Future<void> _restartIce() async {
    final pc = _peerConnection;
    if (pc == null || _familyChatId == null) return;
    // Restart già in corso da poco (answer non ancora arrivata): non
    // sovrapporne un altro. Se invece è vecchio, l'answer non arriverà più.
    if (_restarting &&
        _restartStartedAt != null &&
        DateTime.now().difference(_restartStartedAt!) < _recoveryTimeout) {
      return;
    }
    if (_restartCount >= _maxRestarts) {
      _reportP2PFailure();
      return;
    }
    _restarting = true;
    _restartStartedAt = DateTime.now();
    _restartCount++;
    _gen++;
    _remoteDescriptionSet = false;
    _pendingCandidates.removeWhere((c) => c.gen < _gen);
    _log('ICE restart #$_restartCount → gen $_gen');
    try {
      await pc.restartIce();
      final offer = await pc.createOffer({'iceRestart': true});
      final tuned = RTCSessionDescription(_tuneOpus(offer.sdp!), offer.type);
      await pc.setLocalDescription(tuned);
      await _callDoc(_familyChatId!).set({
        'offer': _seal({'type': tuned.type, 'sdp': tuned.sdp}),
        'offerGen': _gen,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      _log('⚠️ ICE restart failed: $e');
      _restarting = false;
    }
  }

  Future<void> _requestRestartFromCaller() async {
    if (_familyChatId == null) return;
    _restartCount++;
    try {
      await _callDoc(_familyChatId!).set({
        'restartRequested': FieldValue.increment(1),
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _log('Requested ICE restart from caller');
    } catch (e) {
      _log('⚠️ restartRequested write failed: $e');
    }
  }

  void _startConnectTimeout() {
    _connectTimeoutTimer?.cancel();
    _connectTimeoutTimer = Timer(_connectTimeout, () {
      if (_state == P2PConnectionState.connecting) {
        _log('Connect timeout: no P2P path within ${_connectTimeout.inSeconds}s');
        _handleConnectivityLoss(immediate: true);
      }
    });
  }

  void _reportP2PFailure() {
    if (_p2pFailureReported) return;
    _p2pFailureReported = true;
    _setState(P2PConnectionState.failed);
    _log('❌ P2P unavailable after $_restartCount restart(s)');
    onP2PUnavailable?.call();
  }

  void _setState(P2PConnectionState s) {
    if (_state == s) return;
    _state = s;
    _log('P2P state → $s');
  }

  // ═══════════════════════════════════════════════════════════════════
  // Data channel di controllo
  // ═══════════════════════════════════════════════════════════════════

  void _attachControlChannel(RTCDataChannel channel) {
    _controlChannel = channel;
    channel.onDataChannelState = (s) => _log('Control channel: $s');
    channel.onMessage = (RTCDataChannelMessage msg) {
      if (msg.isBinary) return;
      try {
        final m = jsonDecode(msg.text) as Map<String, dynamic>;
        switch (m['t']) {
          case 'bye':
            onRemoteHangup?.call('bye');
            break;
          case 'mute':
            onPartnerMuteChanged?.call(m['v'] == true);
            break;
        }
      } catch (e) {
        _log('⚠️ Bad control message: $e');
      }
    };
  }

  Future<void> _sendControl(Map<String, dynamic> m) async {
    final ch = _controlChannel;
    if (ch == null || ch.state != RTCDataChannelState.RTCDataChannelOpen) return;
    try {
      await ch.send(RTCDataChannelMessage(jsonEncode(m)));
    } catch (e) {
      _log('⚠️ Control send failed: $e');
    }
  }

  /// Avvisa il partner del riaggancio via data channel (istantaneo).
  Future<void> sendBye() => _sendControl({'t': 'bye'});

  // ═══════════════════════════════════════════════════════════════════
  // Controlli audio
  // ═══════════════════════════════════════════════════════════════════

  void setMicMuted(bool muted) {
    final stream = _localStream;
    if (stream != null) {
      for (final track in stream.getAudioTracks()) {
        track.enabled = !muted;
      }
    }
    _sendControl({'t': 'mute', 'v': muted});
    _log('Mic ${muted ? "muted" : "unmuted"}');
  }

  Future<void> setSpeakerOn(bool speakerOn) async {
    try {
      await Helper.setSpeakerphoneOn(speakerOn);
      _log('Speaker ${speakerOn ? "on" : "off"}');
    } catch (e) {
      _log('⚠️ setSpeakerphoneOn failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Statistiche
  // ═══════════════════════════════════════════════════════════════════

  int? _lastPacketsReceived;
  int? _lastPacketsLost;
  int? _lastBytesReceived;
  double? _lastStatsTimestampMs;

  void _startStats() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(_statsInterval, (_) => _collectStats());
  }

  Future<void> _collectStats() async {
    final pc = _peerConnection;
    if (pc == null || _disposed) return;
    List<StatsReport> reports;
    try {
      reports = await pc.getStats();
    } catch (e) {
      return;
    }

    double? rttMs;
    double? jitterMs;
    int? packetsReceived;
    int? packetsLost;
    int? bytesReceived;
    double? timestampMs;
    String? localCandidateId;
    String? remoteCandidateId;
    final candidatesById = <String, Map<dynamic, dynamic>>{};

    for (final r in reports) {
      final v = r.values;
      switch (r.type) {
        case 'candidate-pair':
          final succeeded = v['state'] == 'succeeded';
          final nominated = v['nominated'] == true || v['nominated'] == 'true';
          if (succeeded && (nominated || localCandidateId == null)) {
            final rtt = _num(v['currentRoundTripTime']);
            if (rtt != null) rttMs = rtt * 1000;
            localCandidateId = v['localCandidateId'] as String?;
            remoteCandidateId = v['remoteCandidateId'] as String?;
          }
          break;
        case 'inbound-rtp':
          final kind = v['kind'] ?? v['mediaType'];
          if (kind == 'audio') {
            final jitter = _num(v['jitter']);
            if (jitter != null) jitterMs = jitter * 1000;
            packetsReceived = _num(v['packetsReceived'])?.toInt();
            packetsLost = _num(v['packetsLost'])?.toInt();
            bytesReceived = _num(v['bytesReceived'])?.toInt();
            // Android riporta il timestamp in microsecondi, iOS in ms
            timestampMs = r.timestamp > 1e14 ? r.timestamp / 1000 : r.timestamp;
          }
          break;
        case 'local-candidate':
        case 'remote-candidate':
          candidatesById[r.id] = v;
          break;
      }
    }

    // Perdita e bitrate calcolati sull'intervallo, non cumulativi
    double loss = 0;
    int? bitrateKbps;
    if (packetsReceived != null && packetsLost != null) {
      if (_lastPacketsReceived != null && _lastPacketsLost != null) {
        final dRecv = packetsReceived - _lastPacketsReceived!;
        final dLost = packetsLost - _lastPacketsLost!;
        final total = dRecv + dLost;
        if (total > 0) loss = (dLost / total * 100).clamp(0, 100).toDouble();
      }
      _lastPacketsReceived = packetsReceived;
      _lastPacketsLost = packetsLost;
    }
    if (bytesReceived != null && timestampMs != null) {
      if (_lastBytesReceived != null && _lastStatsTimestampMs != null) {
        final dt = (timestampMs - _lastStatsTimestampMs!) / 1000;
        if (dt > 0) {
          bitrateKbps = ((bytesReceived - _lastBytesReceived!) * 8 / dt / 1000).round();
        }
      }
      _lastBytesReceived = bytesReceived;
      _lastStatsTimestampMs = timestampMs;
    }

    final stats = CallStats(
      rttMs: rttMs,
      jitterMs: jitterMs,
      lossPercent: loss,
      bitrateKbps: bitrateKbps,
      localCandidateType: candidatesById[localCandidateId]?['candidateType'] as String?,
      remoteCandidateType: candidatesById[remoteCandidateId]?['candidateType'] as String?,
    );
    lastStats = stats;
    _log(stats.toString());
    onStats?.call(stats);
  }

  static double? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  // ═══════════════════════════════════════════════════════════════════
  // Cifratura del signaling (AES-256-GCM con chiave di sessione)
  // ═══════════════════════════════════════════════════════════════════

  Map<String, String> _seal(Map<String, dynamic> json) {
    final enc = _encryption.encryptWithFamilyKey(jsonEncode(json), _sessionKeyBase64!);
    return {
      'd': enc['ciphertext']!,
      'n': enc['nonce']!,
      't': enc['tag']!,
    };
  }

  Map<String, dynamic>? _open(dynamic sealed) {
    if (sealed is! Map || _sessionKeyBase64 == null) return null;
    try {
      final plain = _encryption.decryptWithFamilyKey(
        sealed['d'] as String,
        sealed['n'] as String,
        sealed['t'] as String,
        _sessionKeyBase64!,
      );
      return jsonDecode(plain) as Map<String, dynamic>;
    } catch (e) {
      _log('⚠️ Cannot decrypt signaling payload: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Tuning Opus (SDP munging)
  // ═══════════════════════════════════════════════════════════════════

  /// Imposta i parametri fmtp di Opus per la voce su rete mobile:
  /// - useinbandfec=1: FEC in-band, recupera pacchetti persi senza retrasmissione
  /// - stereo=0 / sprop-stereo=0: mono, niente banda sprecata
  /// - maxaveragebitrate=40000: 40 kbps è il punto dolce per la voce
  /// - maxplaybackrate=48000: fullband
  /// - usedtx=0: niente DTX, evita "buchi" percepibili nelle pause
  /// - minptime=10
  /// Applicato sia alla description locale che a quella remota, così
  /// entrambi gli encoder vedono gli stessi vincoli.
  @visibleForTesting
  static String tuneOpusSdp(String sdp) => _tuneOpus(sdp);

  static String _tuneOpus(String sdp) {
    final rtpmap = RegExp(r'^a=rtpmap:(\d+) opus/48000(/2)?', multiLine: true, caseSensitive: false)
        .firstMatch(sdp);
    if (rtpmap == null) return sdp;
    final pt = rtpmap.group(1)!;

    const wanted = {
      'minptime': '10',
      'useinbandfec': '1',
      'stereo': '0',
      'sprop-stereo': '0',
      'maxaveragebitrate': '40000',
      'maxplaybackrate': '48000',
      'usedtx': '0',
    };

    final sep = sdp.contains('\r\n') ? '\r\n' : '\n';
    final lines = sdp.split(sep);
    final fmtpPrefix = 'a=fmtp:$pt ';
    bool found = false;
    for (int i = 0; i < lines.length; i++) {
      if (!lines[i].startsWith(fmtpPrefix)) continue;
      final params = <String, String>{};
      for (final kv in lines[i].substring(fmtpPrefix.length).split(';')) {
        final idx = kv.indexOf('=');
        if (idx <= 0) continue;
        params[kv.substring(0, idx).trim()] = kv.substring(idx + 1).trim();
      }
      params.addAll(wanted);
      lines[i] = fmtpPrefix + params.entries.map((e) => '${e.key}=${e.value}').join(';');
      found = true;
    }
    if (!found) {
      final idx = lines.indexWhere((l) => l.startsWith('a=rtpmap:$pt '));
      final fmtp = fmtpPrefix + wanted.entries.map((e) => '${e.key}=${e.value}').join(';');
      if (idx >= 0) {
        lines.insert(idx + 1, fmtp);
      }
    }
    return lines.join(sep);
  }

  // ═══════════════════════════════════════════════════════════════════
  // Pulizia
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _wipeCandidates(DocumentReference<Map<String, dynamic>> callDoc) async {
    try {
      for (final sub in ['callerCandidates', 'calleeCandidates']) {
        final snap = await callDoc.collection(sub).get();
        if (snap.docs.isEmpty) continue;
        final batch = _firestore.batch();
        for (final d in snap.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();
      }
    } catch (e) {
      _log('⚠️ Candidate wipe failed: $e');
    }
  }

  /// Elimina candidati e documento chiamata su Firestore
  Future<void> cleanupFirestore(String familyChatId) async {
    final callDoc = _callDoc(familyChatId);
    await _wipeCandidates(callDoc);
    try {
      await callDoc.delete();
    } catch (e) {
      _log('⚠️ Call doc delete failed: $e');
    }
  }

  /// Chiudi tutto: connessione, stream, listener, timer
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    _statsTimer?.cancel();
    _graceTimer?.cancel();
    _connectTimeoutTimer?.cancel();
    await _docSubscription?.cancel();
    await _remoteCandidatesSubscription?.cancel();

    try {
      await _controlChannel?.close();
    } catch (_) {}
    _controlChannel = null;

    final stream = _localStream;
    if (stream != null) {
      for (final track in stream.getAudioTracks()) {
        try {
          await track.stop();
        } catch (_) {}
      }
      await stream.dispose();
      _localStream = null;
    }

    final pc = _peerConnection;
    _peerConnection = null;
    if (pc != null) {
      try {
        await pc.close();
      } catch (_) {}
      try {
        await pc.dispose();
      } catch (_) {}
    }

    if (Platform.isAndroid) {
      try {
        await Helper.clearAndroidCommunicationDevice();
      } catch (_) {}
    }

    _setState(P2PConnectionState.closed);
    _log('Disposed');
  }

  void _log(String msg) {
    if (kDebugMode) print('📞 [WEBRTC] $msg');
  }
}

class _PendingCandidate {
  final int gen;
  final RTCIceCandidate candidate;
  _PendingCandidate(this.gen, this.candidate);
}
