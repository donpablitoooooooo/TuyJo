import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:private_messaging/generated/l10n/app_localizations.dart';
import '../services/call_controller.dart';
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

  /// Chiamata già avviata da mostrare (accettata da CallKit, anche con l'app
  /// in background). Se è già terminata la schermata si chiude subito, senza
  /// avviarne un'altra.
  final CallController? controller;

  const VoiceCallScreen({
    Key? key,
    this.isOutgoing = true,
    this.controller,
  }) : super(key: key);

  /// True mentre una VoiceCallScreen è montata: evita doppie aperture
  /// (es. evento CallKit accept + activeCalls() al riavvio).
  static bool isActive = false;

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen>
    with TickerProviderStateMixin {
  /// La chiamata mostrata da questa schermata. Può essere nata prima della
  /// schermata (accettata da CallKit con l'app in background) oppure qui
  /// (chiamata in uscita, o in entrata senza permesso microfono).
  CallController? _controller;
  bool _p2pDialogShown = false;
  bool _p2pDialogOpen = false;
  bool _popScheduled = false;
  CallState _lastState = CallState.ringing;

  // Lo stato vive nel controller: getter con i vecchi nomi per la UI.
  CallState get _callState => _controller?.state ?? CallState.ringing;
  bool get _isMuted => _controller?.isMuted ?? false;
  bool get _isSpeakerOn => _controller?.isSpeakerOn ?? false;
  bool get _partnerMuted => _controller?.partnerMuted ?? false;
  bool get _ending => _controller?.isEnding ?? false;
  int get _callDurationSeconds => _controller?.durationSeconds ?? 0;
  CallStats? get _stats => _controller?.stats;

  // Animazione pulsazione per stato "chiamata in corso"
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    VoiceCallScreen.isActive = true;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    final existing = widget.controller ?? CallController.active;
    if (existing != null) {
      // Chiamata già avviata (accettata da CallKit, anche a schermo bloccato).
      // Se nel frattempo è finita, _attach chiude la schermata.
      _attach(existing);
    } else {
      _startNewCall();
    }
  }

  @override
  void dispose() {
    VoiceCallScreen.isActive = false;
    _pulseController.dispose();
    _setProximity(false);
    final controller = _controller;
    if (controller != null) {
      controller.removeListener(_onControllerChanged);
      controller.screenAttached = false;
      // Rete di sicurezza: schermata chiusa senza passare da "riaggancia"
      // → chiudi comunque la chiamata (WebRTC, CallKit, Firestore).
      if (!controller.isEnding) controller.endCall(localHangup: true);
    }
    super.dispose();
  }

  void _attach(CallController controller) {
    _controller = controller;
    controller.screenAttached = true;
    controller.addListener(_onControllerChanged);
    // Evento già avvenuto prima che la schermata esistesse (pop-up P2P,
    // chiamata già chiusa): gestiscilo dopo il primo frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onControllerChanged());
  }

  Future<void> _startNewCall() async {
    final pairingService = Provider.of<PairingService>(context, listen: false);
    final notificationService = Provider.of<NotificationService>(context, listen: false);
    final encryptionService = Provider.of<EncryptionService>(context, listen: false);

    // Spiegazione in-app prima del prompt di sistema per il microfono.
    final micStatus = await Permission.microphone.status;
    if (!mounted) return;
    if (!micStatus.isGranted && !micStatus.isPermanentlyDenied) {
      final l10n = AppLocalizations.of(context)!;
      final ok = await showPermissionRationaleDialog(
        context: context,
        icon: Icons.mic_none,
        title: l10n.permissionMicRationaleTitle,
        message: l10n.permissionMicRationaleMessage,
      );
      if (!mounted) return;
      if (!ok) {
        // Nessuna chiamata avviata; se era in entrata va chiusa CallKit e
        // avvisato il chiamante: lo fa un controller che si chiude subito.
        if (!widget.isOutgoing) {
          final controller = CallController.create(
            isOutgoing: false,
            encryption: encryptionService,
            pairing: pairingService,
            notifications: notificationService,
            familyChatIdHint: await pairingService.getFamilyChatId(),
          );
          _attach(controller);
          await controller.endCall(localHangup: true);
        } else {
          Navigator.of(context).pop();
        }
        return;
      }
    }

    // Nel frattempo può essere arrivata una chiamata accettata da CallKit
    final existing = CallController.active;
    if (existing != null) {
      _attach(existing);
      return;
    }

    final controller = CallController.create(
      isOutgoing: widget.isOutgoing,
      encryption: encryptionService,
      pairing: pairingService,
      notifications: notificationService,
    );
    _attach(controller);
    final result = await controller.start();
    if (result == CallStartResult.micUnavailable) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        await showPermissionDeniedDialog(
          context: context,
          title: l10n.permissionMicDeniedTitle,
          message: l10n.permissionMicDeniedMessage,
          isPermanentlyDenied: true,
        );
      }
      await controller.endCall(localHangup: true);
    }
  }

  void _onControllerChanged() {
    final controller = _controller;
    if (!mounted || controller == null) return;

    final state = controller.state;
    if (state != _lastState) {
      _lastState = state;
      if (state == CallState.connected || state == CallState.ended) {
        _pulseController.stop();
      }
      _updateProximity();
    }

    if (controller.p2pUnavailable && !_p2pDialogShown && !controller.isEnding) {
      _showP2PUnavailableDialog();
    }

    if (controller.isFinished) _scheduleClose();
    setState(() {});
  }

  /// Chiude la schermata a chiamata terminata, dopo una breve pausa per far
  /// leggere "Chiamata terminata". Se il pop-up "non disponibile in P2P" è
  /// aperto non chiude: il pop() chiuderebbe il dialog e non lo schermo, ci
  /// pensa il dialog alla sua chiusura.
  void _scheduleClose() {
    if (_popScheduled || _p2pDialogOpen) return;
    _popScheduled = true;
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _endCall({required bool localHangup}) {
    final controller = _controller;
    if (controller == null) {
      Navigator.of(context).pop();
      return;
    }
    controller.endCall(localHangup: localHangup);
  }

  String _formatDuration(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Pop-up grande e chiaro: i due telefoni non riescono a parlarsi in
  /// diretta (NAT simmetrico / CGNAT). Senza TURN non c'è alternativa.
  Future<void> _showP2PUnavailableDialog() async {
    if (_p2pDialogShown || !mounted) return;
    _p2pDialogShown = true;
    _p2pDialogOpen = true;
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
    if (_controller?.isFinished ?? true) {
      // La chiamata è già stata chiusa (es. il partner ha riagganciato
      // mentre il pop-up era aperto): esci dalla schermata.
      _scheduleClose();
    } else {
      _endCall(localHangup: true);
    }
  }

  void _toggleMute() => _controller?.toggleMute();

  void _toggleSpeaker() {
    _controller?.toggleSpeaker();
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
