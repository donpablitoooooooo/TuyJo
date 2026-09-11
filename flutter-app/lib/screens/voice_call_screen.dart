import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:private_messaging/generated/l10n/app_localizations.dart';
import '../services/pairing_service.dart';
import '../services/couple_selfie_service.dart';
import '../services/encryption_service.dart';
import '../services/notification_service.dart';
import '../services/webrtc_service.dart';
import '../widgets/permission_denied_dialog.dart';

/// Schermo per la chiamata vocale con il partner
class VoiceCallScreen extends StatefulWidget {
  /// Se true, questa è una chiamata in uscita (noi chiamiamo)
  /// Se false, è una chiamata in entrata già accettata dalla UI nativa CallKit
  final bool isOutgoing;

  const VoiceCallScreen({
    Key? key,
    this.isOutgoing = true,
  }) : super(key: key);

  /// True mentre una VoiceCallScreen è montata: evita doppie aperture
  /// (es. evento CallKit accept + activeCalls() al riavvio).
  static bool isActive = false;

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

enum CallState {
  ringing,
  connecting,
  connected,
  reconnecting,
  ended,
}

class _VoiceCallScreenState extends State<VoiceCallScreen>
    with TickerProviderStateMixin {
  CallState _callState = CallState.ringing;
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _partnerMuted = false;
  bool _p2pDialogShown = false;
  bool _p2pDialogOpen = false;
  bool _ending = false;
  Timer? _callTimer;
  Timer? _ringingTimeoutTimer;
  int _callDurationSeconds = 0;
  String? _familyChatId;
  String? _myUserId;
  CallStats? _stats;
  late final WebRTCService _webrtcService;
  late final NotificationService _notificationService;

  /// Deve coincidere con `duration: 30000` in CallKitParams: lo squillo
  /// lato caller e lato callee finiscono insieme.
  static const _ringTimeout = Duration(seconds: 30);

  // Animazione pulsazione per stato "chiamata in corso"
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    VoiceCallScreen.isActive = true;

    _webrtcService = WebRTCService(
      encryptionService: Provider.of<EncryptionService>(context, listen: false),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Se l'utente termina dalla UI nativa (lock screen iOS, notifica Android)
    _notificationService = Provider.of<NotificationService>(context, listen: false);
    _notificationService.callScreenActive = true;
    _notificationService.onNativeCallEnded = () {
      if (mounted) _endCall(localHangup: true, fromNative: true);
    };

    _initCall();
  }

  @override
  void dispose() {
    VoiceCallScreen.isActive = false;
    _callTimer?.cancel();
    _ringingTimeoutTimer?.cancel();
    _stopRingbackTone();
    _pulseController.dispose();
    _notificationService.onNativeCallEnded = null;
    _notificationService.callScreenActive = false;
    _setProximity(false);
    // Chiudi WebRTC (stream audio + peer connection)
    _webrtcService.dispose();
    // Pulisci lo stato della chiamata su Firestore
    _cleanupCallState();
    super.dispose();
  }

  Future<void> _initCall() async {
    final pairingService = Provider.of<PairingService>(context, listen: false);
    final notificationService = _notificationService;
    _familyChatId = await pairingService.getFamilyChatId();
    _myUserId = await pairingService.getMyUserId();
    final partnerPublicKey = pairingService.partnerPublicKey;

    if (_familyChatId == null || _myUserId == null || partnerPublicKey == null) {
      if (kDebugMode) print('❌ [VOICE_CALL] Not paired, cannot call');
      if (mounted) Navigator.of(context).pop();
      return;
    }

    _wireCallbacks();

    try {
      await _webrtcService.initialize();
    } catch (e) {
      if (kDebugMode) print('❌ [VOICE_CALL] Failed to initialize WebRTC (microphone permission?): $e');
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        await showPermissionDeniedDialog(
          context: context,
          title: l10n.permissionMicDeniedTitle,
          message: l10n.permissionMicDeniedMessage,
          isPermanentlyDenied: true,
        );
        if (mounted) _endCall(localHangup: true);
      }
      return;
    }
    if (!mounted) return;

    if (widget.isOutgoing) {
      // Chiamata in uscita: CallKit "startCall" registra la chiamata nel
      // sistema (iOS: sessione audio + lock screen; Android: foreground
      // service con microfono così la chiamata sopravvive in background).
      await notificationService.startOutgoingCallKit(_familyChatId!, _myUserId!);
      await _webrtcService.startCall(
        familyChatId: _familyChatId!,
        myUserId: _myUserId!,
        partnerPublicKey: partnerPublicKey,
      );
      _startRingbackTone();
      _ringingTimeoutTimer = Timer(_ringTimeout, () {
        if (mounted && _callState == CallState.ringing) {
          if (kDebugMode) print('⏰ [VOICE_CALL] Ringing timeout - ending call');
          _endCall(localHangup: true);
        }
      });
    } else {
      // Chiamata in entrata (accettata via CallKit): rispondi subito
      setState(() => _callState = CallState.connecting);
      final ok = await _webrtcService.answerCall(
        familyChatId: _familyChatId!,
        myUserId: _myUserId!,
      );
      if (!ok && mounted) {
        if (kDebugMode) print('❌ [VOICE_CALL] No offer: caller probably hung up');
        _endCall(localHangup: true);
      }
    }
  }

  void _wireCallbacks() {
    final notificationService = _notificationService;

    _webrtcService.onAnswerReceived = () {
      if (!mounted) return;
      _stopRingbackTone();
      _ringingTimeoutTimer?.cancel();
      if (_callState == CallState.ringing) {
        setState(() => _callState = CallState.connecting);
      }
    };

    _webrtcService.onConnected = () {
      if (!mounted) return;
      _stopRingbackTone();
      _ringingTimeoutTimer?.cancel();
      notificationService.setCallKitConnected();
      setState(() => _callState = CallState.connected);
      _pulseController.stop();
      _startCallTimer();
      _updateProximity();
    };

    _webrtcService.onReconnecting = () {
      if (!mounted) return;
      setState(() => _callState = CallState.reconnecting);
    };

    _webrtcService.onReconnected = () {
      if (!mounted) return;
      setState(() => _callState = CallState.connected);
    };

    _webrtcService.onP2PUnavailable = () {
      if (!mounted) return;
      _showP2PUnavailableDialog();
    };

    _webrtcService.onRemoteHangup = (reason) {
      if (!mounted) return;
      if (kDebugMode) print('📞 [VOICE_CALL] Remote hangup: $reason');
      _endCall(localHangup: false);
    };

    _webrtcService.onPartnerMuteChanged = (muted) {
      if (!mounted) return;
      setState(() => _partnerMuted = muted);
    };

    _webrtcService.onStats = (stats) {
      if (!mounted) return;
      setState(() => _stats = stats);
    };
  }

  /// Scrive lo stato finale della chiamata su Firestore.
  /// `ended_by` permette alla Cloud Function di mandare al callee un push
  /// di annullamento se il caller riaggancia mentre squilla ancora.
  Future<void> _writeEnded() async {
    if (_familyChatId == null || _myUserId == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('families')
          .doc(_familyChatId)
          .collection('calls')
          .doc('current')
          .set({
        'status': 'ended',
        'ended_by': _myUserId,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      if (kDebugMode) print('❌ [VOICE_CALL] Error writing ended: $e');
    }
  }

  void _startCallTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _callDurationSeconds++);
      }
    });
  }

  String _formatDuration(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Termina la chiamata.
  /// [localHangup] true se abbiamo riagganciato noi (avvisa il partner),
  /// false se è stato il partner (non serve avvisare).
  Future<void> _endCall({required bool localHangup, bool fromNative = false}) async {
    if (_ending) return;
    _ending = true;
    _stopRingbackTone();
    _callTimer?.cancel();
    _ringingTimeoutTimer?.cancel();
    if (mounted) setState(() => _callState = CallState.ended);
    _pulseController.stop();
    _setProximity(false);

    if (localHangup) {
      // 1. "bye" P2P istantaneo, 2. stato su Firestore (fallback + cancel push)
      await _webrtcService.sendBye();
      await _writeEnded();
    }
    // Chiudi WebRTC (così l'audio si ferma)
    await _webrtcService.dispose();
    // Poi termina CallKit (ora è safe disattivare la sessione audio)
    if (!fromNative) {
      await _notificationService.endCallKit();
    }
    // Se il pop-up "non disponibile in P2P" è aperto, non chiudere la
    // schermata adesso: il pop() chiuderebbe il dialog e non lo schermo.
    // Sarà il dialog, alla chiusura, a far uscire dalla chiamata.
    if (_p2pDialogOpen) return;
    if (mounted) {
      // Breve pausa per far leggere "Chiamata terminata"
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _cleanupCallState() async {
    if (_familyChatId == null) return;
    try {
      await _webrtcService.cleanupFirestore(_familyChatId!);
    } catch (e) {
      if (kDebugMode) print('⚠️ [VOICE_CALL] Error cleaning up call state: $e');
    }
  }

  /// Pop-up grande e chiaro: i due telefoni non riescono a parlarsi in
  /// diretta (NAT simmetrico / CGNAT). Senza TURN non c'è alternativa.
  Future<void> _showP2PUnavailableDialog() async {
    if (_p2pDialogShown || !mounted) return;
    _p2pDialogShown = true;
    _p2pDialogOpen = true;
    _stopRingbackTone();
    final l10n = AppLocalizations.of(context)!;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1A1A2E),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xFFFF5252), width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFF5252).withValues(alpha: 0.15),
                  border: Border.all(color: const Color(0xFFFF5252), width: 3),
                ),
                child: const Icon(Icons.phonelink_off, size: 60, color: Color(0xFFFF5252)),
              ),
              const SizedBox(height: 24),
              Text(
                l10n.voiceCallP2PUnavailableTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.voiceCallP2PUnavailableMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 16,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.voiceCallP2PUnavailableHint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF5252),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(
                    l10n.voiceCallP2PUnavailableButton,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    _p2pDialogOpen = false;
    if (!mounted) return;
    if (_ending) {
      // La chiamata è già stata chiusa (es. il partner ha riagganciato
      // mentre il pop-up era aperto): esci dalla schermata.
      Navigator.of(context).pop();
    } else {
      _endCall(localHangup: true);
    }
  }

  /// Avvia il ringback tone nativo (ToneGenerator su STREAM_VOICE_CALL)
  static const _toneChannel = MethodChannel('com.privatemessaging.tuyjo/tone_generator');
  bool _ringbackPlaying = false;

  Future<void> _startRingbackTone() async {
    if (_ringbackPlaying) return;
    _ringbackPlaying = true;
    try {
      await _toneChannel.invokeMethod('startRingback');
      if (kDebugMode) print('🔔 [VOICE_CALL] Ringback tone started');
    } catch (e) {
      if (kDebugMode) print('⚠️ [VOICE_CALL] Could not start ringback tone: $e');
    }
  }

  Future<void> _stopRingbackTone() async {
    if (!_ringbackPlaying) return;
    _ringbackPlaying = false;
    try {
      await _toneChannel.invokeMethod('stopRingback');
    } catch (e) {
      if (kDebugMode) print('⚠️ [VOICE_CALL] Could not stop ringback tone: $e');
    }
  }

  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    _webrtcService.setMicMuted(_isMuted);
  }

  void _toggleSpeaker() {
    setState(() => _isSpeakerOn = !_isSpeakerOn);
    _webrtcService.setSpeakerOn(_isSpeakerOn);
    _updateProximity();
  }

  // ─── Sensore di prossimità ────────────────────────────────────────
  // Attivo solo a chiamata connessa e con altoparlante spento: con il
  // vivavoce il telefono sta lontano dal viso e lo schermo deve restare acceso.
  static const _proximityChannel = MethodChannel('com.privatemessaging.tuyjo/proximity');
  bool _proximityEnabled = false;

  void _updateProximity() {
    final wanted = _callState == CallState.connected && !_isSpeakerOn && !_ending;
    _setProximity(wanted);
  }

  Future<void> _setProximity(bool enable) async {
    if (_proximityEnabled == enable) return;
    _proximityEnabled = enable;
    try {
      await _proximityChannel.invokeMethod(enable ? 'enable' : 'disable');
      if (kDebugMode) print('📵 [VOICE_CALL] Proximity ${enable ? "on" : "off"}');
    } catch (e) {
      if (kDebugMode) print('⚠️ [VOICE_CALL] Proximity channel error: $e');
    }
  }

  String _statusText(AppLocalizations l10n) {
    switch (_callState) {
      case CallState.ringing:
        return widget.isOutgoing ? l10n.voiceCallCalling : l10n.voiceCallIncoming;
      case CallState.connecting:
        return l10n.voiceCallConnecting;
      case CallState.connected:
        return _formatDuration(_callDurationSeconds);
      case CallState.reconnecting:
        return l10n.voiceCallReconnecting;
      case CallState.ended:
        return l10n.voiceCallEnded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_ending) _endCall(localHangup: true);
      },
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF1A1A2E),
                Color(0xFF16213E),
                Color(0xFF0F3460),
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 40),

                // Stato chiamata
                Text(
                  _statusText(l10n),
                  style: TextStyle(
                    color: _callState == CallState.reconnecting
                        ? const Color(0xFFFFB74D)
                        : Colors.white.withValues(alpha: 0.7),
                    fontSize: 16,
                    letterSpacing: 1.2,
                  ),
                ),

                const SizedBox(height: 10),
                _buildQualityRow(l10n),

                const Spacer(flex: 1),

                // Avatar partner con animazione pulsazione
                ScaleTransition(
                  scale: _callState == CallState.ringing || _callState == CallState.connecting
                      ? _pulseAnimation
                      : const AlwaysStoppedAnimation(1.0),
                  child: _buildPartnerAvatar(),
                ),

                const SizedBox(height: 32),

                // Nome / titolo
                Text(
                  l10n.voiceCallTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),
                AnimatedOpacity(
                  opacity: _partnerMuted ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.mic_off, color: Colors.white54, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        l10n.voiceCallPartnerMuted,
                        style: const TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                    ],
                  ),
                ),

                const Spacer(flex: 2),

                _buildCallControls(l10n),

                const SizedBox(height: 60),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Indicatore qualità (3 barre) + percorso di rete, visibile solo a
  /// chiamata connessa. Il percorso (host/srflx) dice se siamo sulla stessa
  /// LAN o attraverso NAT: utile per capire quanto spesso il P2P riesce.
  Widget _buildQualityRow(AppLocalizations l10n) {
    final stats = _stats;
    final visible = _callState == CallState.connected && stats != null;
    final quality = stats?.quality ?? CallQuality.unknown;

    Color color;
    int bars;
    String label;
    switch (quality) {
      case CallQuality.good:
        color = const Color(0xFF66BB6A);
        bars = 3;
        label = l10n.voiceCallQualityGood;
        break;
      case CallQuality.fair:
        color = const Color(0xFFFFB74D);
        bars = 2;
        label = l10n.voiceCallQualityFair;
        break;
      case CallQuality.poor:
        color = const Color(0xFFFF5252);
        bars = 1;
        label = l10n.voiceCallQualityPoor;
        break;
      case CallQuality.unknown:
        color = Colors.white38;
        bars = 0;
        label = '';
        break;
    }

    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 300),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (int i = 0; i < 3; i++)
            Container(
              width: 5,
              height: 6.0 + i * 4,
              margin: const EdgeInsets.only(right: 3),
              decoration: BoxDecoration(
                color: i < bars ? color : Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 12, letterSpacing: 0.5),
          ),
          if (stats?.rttMs != null) ...[
            const SizedBox(width: 10),
            Text(
              '${stats!.rttMs!.round()} ms · ${stats.pathLabel}',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPartnerAvatar() {
    return Consumer<CoupleSelfieService>(
      builder: (context, coupleSelfieService, _) {
        final hasSelfie = coupleSelfieService.hasSelfie;
        final cachedSelfieBytes = coupleSelfieService.cachedSelfieBytes;
        final connected = _callState == CallState.connected;
        final borderColor = connected
            ? const Color(0xFF3BA8B0)
            : _callState == CallState.reconnecting
                ? const Color(0xFFFFB74D)
                : Colors.white;

        return Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: connected ? borderColor : borderColor.withValues(alpha: 0.3),
              width: 4,
            ),
            boxShadow: [
              BoxShadow(
                color: borderColor.withValues(alpha: 0.2),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: ClipOval(
            child: hasSelfie && cachedSelfieBytes != null
                ? Image.memory(
                    cachedSelfieBytes,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildDefaultAvatar(),
                  )
                : _buildDefaultAvatar(),
          ),
        );
      },
    );
  }

  Widget _buildDefaultAvatar() {
    return Container(
      color: const Color(0xFF3BA8B0).withValues(alpha: 0.3),
      child: const Icon(
        Icons.person,
        size: 80,
        color: Colors.white70,
      ),
    );
  }

  Widget _buildCallControls(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Mute
          _buildControlButton(
            icon: _isMuted ? Icons.mic_off : Icons.mic,
            label: l10n.voiceCallMute,
            isActive: _isMuted,
            onPressed: _toggleMute,
          ),

          // End call
          _buildEndCallButton(l10n),

          // Speaker
          _buildControlButton(
            icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
            label: l10n.voiceCallSpeaker,
            isActive: _isSpeakerOn,
            onPressed: _toggleSpeaker,
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onPressed,
  }) {
    return Column(
      children: [
        GestureDetector(
          onTap: onPressed,
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: isActive
                  ? Colors.white.withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildEndCallButton(AppLocalizations l10n) {
    return Column(
      children: [
        GestureDetector(
          onTap: () => _endCall(localHangup: true),
          child: Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0x66FF0000),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(
              Icons.call_end,
              color: Colors.white,
              size: 36,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.voiceCallEnd,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}
