import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:private_messaging/generated/l10n/app_localizations.dart';
import '../services/pairing_service.dart';
import '../services/couple_selfie_service.dart';
import '../services/notification_service.dart';
import '../services/webrtc_service.dart';

/// Schermo per la chiamata vocale con il partner
class VoiceCallScreen extends StatefulWidget {
  /// Se true, questa è una chiamata in uscita (noi chiamiamo)
  /// Se false, è una chiamata in entrata (il partner ci chiama)
  final bool isOutgoing;

  const VoiceCallScreen({
    Key? key,
    this.isOutgoing = true,
  }) : super(key: key);

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

enum CallState {
  ringing,     // Caller: attende risposta. Callee: sta squillando.
  connecting,  // Partner ha risposto, WebRTC sta negoziando.
  connected,   // Audio verificato, si parla.
  failed,      // Connessione P2P fallita.
  ended,       // Chiamata terminata normalmente.
}

class _VoiceCallScreenState extends State<VoiceCallScreen>
    with TickerProviderStateMixin {
  CallState _callState = CallState.ringing;
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  Timer? _callTimer;
  Timer? _ringTimeout;
  Timer? _connectTimeout;
  int _callDurationSeconds = 0;
  String? _familyChatId;
  String? _myUserId;
  StreamSubscription? _callSubscription;
  final WebRTCService _webrtcService = WebRTCService();

  // Animazione pulsazione per stato "chiamata in corso"
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _initCall();

    // Per chiamate in uscita, cancella eventuali notifiche residue
    // Per chiamate in ENTRATA, NON terminare CallKit — iOS usa la sessione
    // audio di CallKit per WebRTC. Terminarlo disattiva l'audio.
    if (widget.isOutgoing) {
      final notificationService = Provider.of<NotificationService>(context, listen: false);
      notificationService.cancelCallNotification();
    }
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    _ringTimeout?.cancel();
    _connectTimeout?.cancel();
    _callSubscription?.cancel();
    _pulseController.dispose();
    // Chiudi WebRTC (stream audio + peer connection + ringback)
    _webrtcService.dispose();
    // Pulisci lo stato della chiamata su Firestore
    _cleanupCallState();
    super.dispose();
  }

  Future<void> _initCall() async {
    final pairingService = Provider.of<PairingService>(context, listen: false);
    _familyChatId = await pairingService.getFamilyChatId();
    _myUserId = await pairingService.getMyUserId();

    if (_familyChatId == null || _myUserId == null) return;

    // ─── Setup callbacks WebRTC ───
    // onConnected: WebRTC ha stabilito la connessione (ICE ok).
    // A questo punto NON mostriamo ancora "connected" — aspettiamo la verifica audio.
    _webrtcService.onConnected = () {
      if (mounted && _callState != CallState.connected && _callState != CallState.ended) {
        if (kDebugMode) print('📞 [CALL] WebRTC connected, waiting for audio verification...');
        // Passa a "connecting" se eravamo ancora in ringing
        if (_callState == CallState.ringing) {
          setState(() => _callState = CallState.connecting);
        }
        // Il timer di connessione parte da quando WebRTC è connesso
        _connectTimeout?.cancel();
      }
    };

    // onAudioVerified: i pacchetti audio fluiscono veramente!
    // ORA possiamo dire "connected" e far partire la chiamata.
    _webrtcService.onAudioVerified = () {
      if (mounted && _callState != CallState.connected && _callState != CallState.ended) {
        if (kDebugMode) print('✅ [CALL] Audio verified! Call is truly connected.');
        _webrtcService.stopRingback();
        _connectTimeout?.cancel();
        _ringTimeout?.cancel();
        setState(() {
          _callState = CallState.connected;
        });
        _pulseController.stop();
        _startCallTimer();
      }
    };

    // onConnectionFailed: ICE fallito o audio non fluisce.
    _webrtcService.onConnectionFailed = () {
      if (mounted && _callState != CallState.ended && _callState != CallState.failed) {
        if (kDebugMode) print('❌ [CALL] P2P connection failed');
        _webrtcService.stopRingback();
        _connectTimeout?.cancel();
        _ringTimeout?.cancel();
        setState(() {
          _callState = CallState.failed;
        });
        _pulseController.stop();
        _showConnectionFailedDialog();
      }
    };

    // onDisconnected: connessione persa durante la chiamata.
    _webrtcService.onDisconnected = () {
      if (mounted && _callState == CallState.connected) {
        _endCall();
      }
    };

    await _webrtcService.initialize();

    if (widget.isOutgoing) {
      // ─── Chiamata in uscita ───
      // 1. Scrivi "ringing" su Firestore → trigger FCM al partner
      await _writeCallSignal('ringing');
      // 2. Crea offer WebRTC
      await _webrtcService.createOffer(_familyChatId!);
      // 3. Avvia ringback tone (tu-tu... tu-tu...)
      await _webrtcService.startRingback();
      // 4. Ascolta risposta del partner
      _listenForCallResponse();
      // 5. Timeout: se nessuna risposta entro 45s → fine
      _ringTimeout = Timer(const Duration(seconds: 45), () {
        if (mounted && _callState == CallState.ringing) {
          if (kDebugMode) print('⏰ [CALL] Ring timeout - no answer');
          _webrtcService.stopRingback();
          setState(() => _callState = CallState.ended);
          _pulseController.stop();
          _showNoAnswerAndClose();
        }
      });
    } else {
      // ─── Chiamata in entrata (accettata via CallKit) ───
      // 1. Ascolta cambiamenti stato
      _listenForCallResponse();
      // 2. Crea answer WebRTC (legge offer, scrive answer)
      final success = await _webrtcService.createAnswer(_familyChatId!);
      if (!success) {
        // Offer non trovato — segnala errore
        if (mounted) {
          if (kDebugMode) print('❌ [CALL] Failed to create answer - offer not found');
          setState(() => _callState = CallState.failed);
          _pulseController.stop();
          _showConnectionFailedDialog();
        }
        return;
      }
      // 3. Scrivi "answered" su Firestore (NON "connected"!)
      // Il caller vedrà che abbiamo risposto.
      await _writeCallSignal('answered');
      // 4. Passa a "connecting" — aspettiamo che WebRTC si connetta + audio verificato
      if (mounted) {
        setState(() => _callState = CallState.connecting);
      }
      // 5. Timeout connessione: se dopo 20s WebRTC non si connette → fallito
      _connectTimeout = Timer(const Duration(seconds: 20), () {
        if (mounted && _callState == CallState.connecting) {
          if (kDebugMode) print('⏰ [CALL] Connection timeout - P2P failed');
          _webrtcService.onConnectionFailed?.call();
        }
      });
    }
  }

  /// Scrive il segnale della chiamata su Firestore
  Future<void> _writeCallSignal(String status) async {
    if (_familyChatId == null || _myUserId == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('families')
          .doc(_familyChatId)
          .collection('calls')
          .doc('current')
          .set({
        'caller_id': _myUserId,
        'status': status, // ringing, answered, ended, declined
        'started_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      if (kDebugMode) print('❌ [VOICE_CALL] Error writing call signal: $e');
    }
  }

  /// Ascolta i cambiamenti dello stato della chiamata
  void _listenForCallResponse() {
    if (_familyChatId == null) return;

    _callSubscription = FirebaseFirestore.instance
        .collection('families')
        .doc(_familyChatId)
        .collection('calls')
        .doc('current')
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists || !mounted) return;

      final data = snapshot.data()!;
      final status = data['status'] as String?;

      if (status == 'answered' && widget.isOutgoing && _callState == CallState.ringing) {
        // Il partner ha risposto! Passa a "connecting".
        // NON fermiamo il ringback ancora — aspettiamo audio verificato.
        if (kDebugMode) print('📞 [CALL] Partner answered, waiting for WebRTC...');
        setState(() => _callState = CallState.connecting);
        // Timeout: se dopo 20s ancora non connesso → fallito
        _connectTimeout?.cancel();
        _connectTimeout = Timer(const Duration(seconds: 20), () {
          if (mounted && (_callState == CallState.connecting || _callState == CallState.ringing)) {
            if (kDebugMode) print('⏰ [CALL] Connection timeout after answer');
            _webrtcService.onConnectionFailed?.call();
          }
        });
      } else if ((status == 'ended' || status == 'declined') && _callState != CallState.ended) {
        _webrtcService.stopRingback();
        _callTimer?.cancel();
        _ringTimeout?.cancel();
        _connectTimeout?.cancel();
        setState(() {
          _callState = CallState.ended;
        });
        _pulseController.stop();
        // Chiudi lo schermo dopo un breve delay
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) Navigator.of(context).pop();
        });
      }
    });
  }

  void _startCallTimer() {
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _callDurationSeconds++;
        });
      }
    });
  }

  String _formatDuration(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _endCall() async {
    if (_callState == CallState.ended) return; // Evita doppia chiusura
    _callTimer?.cancel();
    _ringTimeout?.cancel();
    _connectTimeout?.cancel();
    setState(() {
      _callState = CallState.ended;
    });
    // Prima chiudi WebRTC (così l'audio si ferma + ringback si ferma)
    await _webrtcService.dispose();
    // Poi termina CallKit (ora è safe disattivare la sessione audio)
    final notificationService = Provider.of<NotificationService>(context, listen: false);
    notificationService.endCallKit();
    // Scrivi stato ended su Firestore
    _writeCallSignal('ended');
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _acceptCall() async {
    // Crea answer WebRTC (legge offer, stabilisce connessione audio)
    if (_familyChatId != null) {
      final success = await _webrtcService.createAnswer(_familyChatId!);
      if (!success) {
        if (mounted) {
          setState(() => _callState = CallState.failed);
          _pulseController.stop();
          _showConnectionFailedDialog();
        }
        return;
      }
    }
    await _writeCallSignal('answered');
    setState(() {
      _callState = CallState.connecting;
    });
    // Timeout connessione
    _connectTimeout = Timer(const Duration(seconds: 20), () {
      if (mounted && _callState == CallState.connecting) {
        _webrtcService.onConnectionFailed?.call();
      }
    });
  }

  Future<void> _declineCall() async {
    _webrtcService.stopRingback();
    _writeCallSignal('declined');
    final notificationService = Provider.of<NotificationService>(context, listen: false);
    notificationService.endCallKit();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _cleanupCallState() async {
    if (_familyChatId == null) return;
    try {
      // Pulisci ICE candidates + documento chiamata
      await _webrtcService.cleanupFirestore(_familyChatId!);
    } catch (e) {
      if (kDebugMode) print('⚠️ [VOICE_CALL] Error cleaning up call state: $e');
    }
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
    });
    _webrtcService.setMicMuted(_isMuted);
  }

  void _toggleSpeaker() {
    setState(() {
      _isSpeakerOn = !_isSpeakerOn;
    });
    _webrtcService.setSpeakerOn(_isSpeakerOn);
  }

  // ─── Dialogs ─────────────────────────────────────────────────────

  void _showNoAnswerAndClose() {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.voiceCallPartnerNotAvailable),
        duration: const Duration(seconds: 2),
      ),
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) _endCall();
    });
  }

  void _showConnectionFailedDialog() {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.voiceCallConnectionFailedTitle),
        content: Text(l10n.voiceCallConnectionFailedMessage),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _endCall();
            },
            child: Text(l10n.close),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _retryCall();
            },
            child: Text(l10n.retry),
          ),
        ],
      ),
    );
  }

  Future<void> _retryCall() async {
    // Chiudi la connessione precedente
    await _webrtcService.dispose();
    _callSubscription?.cancel();
    _callTimer?.cancel();

    // Reset stato
    setState(() {
      _callState = CallState.ringing;
      _callDurationSeconds = 0;
    });
    _pulseController.repeat(reverse: true);

    // Ricrea tutto
    _initCall();
  }

  // ─── UI ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
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
                _getStatusText(l10n),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 16,
                  letterSpacing: 1.2,
                ),
                textAlign: TextAlign.center,
              ),

              const Spacer(flex: 1),

              // Avatar partner con animazione pulsazione
              ScaleTransition(
                scale: (_callState == CallState.ringing || _callState == CallState.connecting)
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

              const Spacer(flex: 2),

              // Pulsanti di controllo
              if (_callState == CallState.ringing && !widget.isOutgoing) ...[
                // Chiamata in entrata: Accept / Decline
                _buildIncomingCallButtons(l10n),
              ] else if (_callState == CallState.failed) ...[
                // Chiamata fallita: mostra solo End
                _buildCallControls(l10n),
              ] else ...[
                // Chiamata in uscita, connecting o connessa: Mute / Speaker / End
                _buildCallControls(l10n),
              ],

              const SizedBox(height: 60),
            ],
          ),
        ),
      ),
    );
  }

  String _getStatusText(AppLocalizations l10n) {
    switch (_callState) {
      case CallState.ringing:
        return widget.isOutgoing
            ? l10n.voiceCallCalling
            : l10n.voiceCallIncoming;
      case CallState.connecting:
        return l10n.voiceCallConnecting;
      case CallState.connected:
        return _formatDuration(_callDurationSeconds);
      case CallState.failed:
        return l10n.voiceCallConnectionFailed;
      case CallState.ended:
        return l10n.voiceCallEnded;
    }
  }

  Widget _buildPartnerAvatar() {
    return Consumer<CoupleSelfieService>(
      builder: (context, coupleSelfieService, _) {
        final hasSelfie = coupleSelfieService.hasSelfie;
        final cachedSelfieBytes = coupleSelfieService.cachedSelfieBytes;

        // Colore bordo in base allo stato
        Color borderColor;
        if (_callState == CallState.connected) {
          borderColor = const Color(0xFF3BA8B0);
        } else if (_callState == CallState.failed) {
          borderColor = Colors.red.withOpacity(0.6);
        } else if (_callState == CallState.connecting) {
          borderColor = Colors.amber.withOpacity(0.6);
        } else {
          borderColor = Colors.white.withOpacity(0.3);
        }

        return Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: borderColor,
              width: 4,
            ),
            boxShadow: [
              BoxShadow(
                color: borderColor.withOpacity(0.2),
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
      color: const Color(0xFF3BA8B0).withOpacity(0.3),
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

  Widget _buildIncomingCallButtons(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 60),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Decline
          Column(
            children: [
              GestureDetector(
                onTap: _declineCall,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.call_end,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.voiceCallDecline,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),

          // Accept
          Column(
            children: [
              GestureDetector(
                onTap: _acceptCall,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.call,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.voiceCallAccept,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
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
                  ? Colors.white.withOpacity(0.3)
                  : Colors.white.withOpacity(0.1),
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
          onTap: _endCall,
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
