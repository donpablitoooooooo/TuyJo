import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:private_messaging/generated/l10n/app_localizations.dart';
import '../services/pairing_service.dart';
import '../services/couple_selfie_service.dart';
import '../services/notification_service.dart';
import '../services/webrtc_service.dart';
import '../widgets/permission_denied_dialog.dart';

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
  ringing,
  connected,
  ended,
}

class _VoiceCallScreenState extends State<VoiceCallScreen>
    with TickerProviderStateMixin {
  CallState _callState = CallState.ringing;
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  Timer? _callTimer;
  Timer? _ringingTimeoutTimer;
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
    _ringingTimeoutTimer?.cancel();
    _callSubscription?.cancel();
    _stopRingbackTone();
    _pulseController.dispose();
    // Chiudi WebRTC (stream audio + peer connection)
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

    // Inizializza WebRTC (cattura microfono, crea peer connection)
    _webrtcService.onConnected = () {
      if (mounted && _callState != CallState.connected) {
        _stopRingbackTone();
        setState(() {
          _callState = CallState.connected;
        });
        _pulseController.stop();
        _startCallTimer();
      }
    };
    _webrtcService.onDisconnected = () {
      if (mounted && _callState == CallState.connected) {
        _endCall();
      }
    };
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
        if (mounted) _endCall();
      }
      return;
    }

    if (widget.isOutgoing) {
      // Chiamata in uscita: scrivi lo stato + crea offer WebRTC
      await _writeCallSignal('ringing');
      _startRingbackTone();
      await _webrtcService.createOffer(_familyChatId!);
      _listenForCallResponse();
      // Timeout: se nessuna risposta entro 45 secondi, termina la chiamata
      _ringingTimeoutTimer = Timer(const Duration(seconds: 45), () {
        if (mounted && _callState == CallState.ringing) {
          if (kDebugMode) print('⏰ [VOICE_CALL] Ringing timeout - ending call');
          _endCall();
        }
      });
    } else {
      // Chiamata in entrata (accettata via CallKit):
      // Il callee ha già accettato dalla UI nativa CallKit, quindi
      // creiamo subito l'answer WebRTC per stabilire la connessione audio.
      // IMPORTANTE: leggere l'offer PRIMA di scrivere 'connected',
      // altrimenti la cache locale Firestore non ha ancora l'offer.
      _listenForCallResponse();
      await _webrtcService.createAnswer(_familyChatId!);
      await _writeCallSignal('connected');
      if (mounted) {
        setState(() {
          _callState = CallState.connected;
        });
        _pulseController.stop();
        _startCallTimer();
      }
    }
  }

  /// Scrive il segnale della chiamata su Firestore
  /// Solo il caller scrive caller_id e started_at (al primo segnale 'ringing')
  /// Il callee aggiorna solo status e updated_at
  Future<void> _writeCallSignal(String status) async {
    if (_familyChatId == null || _myUserId == null) return;

    try {
      final Map<String, dynamic> data = {
        'status': status,
        'updated_at': FieldValue.serverTimestamp(),
      };

      // Solo per la chiamata in uscita (ringing) impostiamo caller_id e started_at
      if (status == 'ringing' && widget.isOutgoing) {
        data['caller_id'] = _myUserId;
        data['started_at'] = FieldValue.serverTimestamp();
      }

      await FirebaseFirestore.instance
          .collection('families')
          .doc(_familyChatId)
          .collection('calls')
          .doc('current')
          .set(data, SetOptions(merge: true));
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

      if (status == 'connected' && _callState != CallState.connected) {
        _stopRingbackTone();
        setState(() {
          _callState = CallState.connected;
        });
        _pulseController.stop();
        _startCallTimer();
      } else if ((status == 'ended' || status == 'declined') && _callState != CallState.ended) {
        _stopRingbackTone();
        _callTimer?.cancel();
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
    _ringingTimeoutTimer?.cancel(); // Call connected, cancel ringing timeout
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
    _stopRingbackTone();
    _callTimer?.cancel();
    setState(() {
      _callState = CallState.ended;
    });
    // Prima chiudi WebRTC (così l'audio si ferma)
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
    // IMPORTANTE: creare l'answer PRIMA di scrivere 'connected',
    // altrimenti la cache locale Firestore potrebbe non avere ancora l'offer
    if (_familyChatId != null) {
      await _webrtcService.createAnswer(_familyChatId!);
    }
    await _writeCallSignal('connected');
    if (mounted) {
      setState(() {
        _callState = CallState.connected;
      });
      _pulseController.stop();
      _startCallTimer();
    }
  }

  Future<void> _declineCall() async {
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

  /// Avvia il ringback tone nativo (ToneGenerator su STREAM_VOICE_CALL)
  static const _toneChannel = MethodChannel('com.privatemessaging.tuyjo/tone_generator');

  Future<void> _startRingbackTone() async {
    try {
      await _toneChannel.invokeMethod('startRingback');
      if (kDebugMode) print('🔔 [VOICE_CALL] Ringback tone started (native ToneGenerator)');
    } catch (e) {
      if (kDebugMode) print('⚠️ [VOICE_CALL] Could not start ringback tone: $e');
    }
  }

  Future<void> _stopRingbackTone() async {
    try {
      await _toneChannel.invokeMethod('stopRingback');
    } catch (e) {
      if (kDebugMode) print('⚠️ [VOICE_CALL] Could not stop ringback tone: $e');
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
                _callState == CallState.ringing
                    ? (widget.isOutgoing
                        ? l10n.voiceCallCalling
                        : l10n.voiceCallIncoming)
                    : _callState == CallState.connected
                        ? _formatDuration(_callDurationSeconds)
                        : l10n.voiceCallEnded,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 16,
                  letterSpacing: 1.2,
                ),
              ),

              const Spacer(flex: 1),

              // Avatar partner con animazione pulsazione
              ScaleTransition(
                scale: _callState == CallState.ringing
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
              ] else ...[
                // Chiamata in uscita o connessa: Mute / Speaker / End
                _buildCallControls(l10n),
              ],

              const SizedBox(height: 60),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPartnerAvatar() {
    return Consumer<CoupleSelfieService>(
      builder: (context, coupleSelfieService, _) {
        final hasSelfie = coupleSelfieService.hasSelfie;
        final cachedSelfieBytes = coupleSelfieService.cachedSelfieBytes;

        return Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: _callState == CallState.connected
                  ? const Color(0xFF3BA8B0)
                  : Colors.white.withOpacity(0.3),
              width: 4,
            ),
            boxShadow: [
              BoxShadow(
                color: (_callState == CallState.connected
                        ? const Color(0xFF3BA8B0)
                        : Colors.white)
                    .withOpacity(0.2),
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
