import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:private_messaging/generated/l10n/app_localizations.dart';
import '../services/location_service.dart';
import '../services/chat_service.dart';
import '../services/pairing_service.dart';
import '../services/encryption_service.dart';
import 'location_sharing_screen.dart';

/// Pagina full-screen per configurare la condivisione della posizione.
/// Mostra posizione corrente, accuratezza, durata e modalità (live / questa posizione).
class LocationShareSetupPage extends StatefulWidget {
  const LocationShareSetupPage({Key? key}) : super(key: key);

  @override
  State<LocationShareSetupPage> createState() => _LocationShareSetupPageState();
}

class _LocationShareSetupPageState extends State<LocationShareSetupPage>
    with SingleTickerProviderStateMixin {
  Position? _position;
  bool _isAcquiringGps = true;
  bool _isSending = false;

  // Opzioni selezionate
  Duration _selectedDuration = const Duration(hours: 1);
  String _selectedMode = 'live'; // 'live' oppure 'static'

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  Timer? _gpsRetryTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _acquireGps();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _gpsRetryTimer?.cancel();
    super.dispose();
  }

  Future<void> _acquireGps() async {
    final locationService = Provider.of<LocationService>(context, listen: false);
    final position = await locationService.getCurrentPosition();
    if (!mounted) return;

    if (position != null) {
      setState(() {
        _position = position;
        _isAcquiringGps = false;
      });
    } else {
      // Riprova ogni 3 secondi
      _gpsRetryTimer?.cancel();
      _gpsRetryTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
        final pos = await locationService.getCurrentPosition();
        if (mounted && pos != null) {
          _gpsRetryTimer?.cancel();
          setState(() {
            _position = pos;
            _isAcquiringGps = false;
          });
        }
      });
    }
  }

  Future<void> _startSharing() async {
    if (_isSending || _position == null) return;
    setState(() => _isSending = true);

    final locationService = Provider.of<LocationService>(context, listen: false);
    final chatService = Provider.of<ChatService>(context, listen: false);
    final pairingService = Provider.of<PairingService>(context, listen: false);
    final encryptionService = Provider.of<EncryptionService>(context, listen: false);

    final familyChatId = await pairingService.getFamilyChatId();
    final myDeviceId = await pairingService.getMyUserId();
    final myPublicKey = await encryptionService.getPublicKey();
    final partnerPublicKey = pairingService.partnerPublicKey;

    if (familyChatId == null || myDeviceId == null ||
        myPublicKey == null || partnerPublicKey == null) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.locationShareErrorPairing),
            duration: const Duration(seconds: 5),
            backgroundColor: Colors.red[700],
          ),
        );
        setState(() => _isSending = false);
      }
      return;
    }

    // 1) Prepara sessione
    final sessionId = const Uuid().v4();
    final expiresAt = DateTime.now().add(_selectedDuration);
    locationService.prepareSession(sessionId, _selectedDuration);

    // 2) Manda il messaggio su Firestore con la modalità
    final messageId = await chatService.sendLocationShare(
      expiresAt,
      sessionId,
      familyChatId,
      myDeviceId,
      myPublicKey,
      partnerPublicKey,
      mode: _selectedMode,
    );

    if (messageId != null) {
      locationService.setLocationShareMessageId(messageId);
    }

    // 3) Avvia GPS sharing
    await locationService.startSharingLocation(_selectedDuration, sessionId: sessionId);

    if (!mounted) return;

    // 4) Naviga alla schermata di navigazione
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => LocationSharingScreen(
          expectedSessionId: sessionId,
          isSender: true,
          mode: _selectedMode,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF3BA8B0), Color(0xFF145A60)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 20),

              // Freccia animata
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Opacity(
                    opacity: _isAcquiringGps ? _pulseAnimation.value : 1.0,
                    child: Icon(
                      Icons.navigation,
                      size: 120,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: 32),

              // Stato GPS
              _buildGpsStatus(l10n),

              const SizedBox(height: 40),

              // Opzioni
              if (!_isAcquiringGps) ...[
                _buildDurationSelector(l10n),
                const SizedBox(height: 20),
                _buildModeSelector(l10n),
                const Spacer(),
                _buildShareButton(l10n),
                const SizedBox(height: 40),
              ] else ...[
                const Spacer(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGpsStatus(AppLocalizations l10n) {
    if (_isAcquiringGps) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          children: [
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              l10n.locationShareAcquiringGps,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w300,
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        children: [
          Text(
            l10n.locationShareYourPosition,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w300,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_position!.latitude.toStringAsFixed(5)}, ${_position!.longitude.toStringAsFixed(5)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.0,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              l10n.locationShareAccuracy(_position!.accuracy.toInt()),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDurationSelector(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        children: [
          Text(
            l10n.locationShareDurationLabel,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                _buildToggleOption(
                  label: l10n.locationShareDuration1Hour,
                  selected: _selectedDuration == const Duration(hours: 1),
                  onTap: () => setState(() => _selectedDuration = const Duration(hours: 1)),
                  isLeft: true,
                ),
                _buildToggleOption(
                  label: l10n.locationShareDuration8Hours,
                  selected: _selectedDuration == const Duration(hours: 8),
                  onTap: () => setState(() => _selectedDuration = const Duration(hours: 8)),
                  isLeft: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        children: [
          Text(
            l10n.locationShareModeLabel,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                _buildToggleOption(
                  label: l10n.locationShareModeLive,
                  selected: _selectedMode == 'live',
                  onTap: () => setState(() => _selectedMode = 'live'),
                  isLeft: true,
                ),
                _buildToggleOption(
                  label: l10n.locationShareModeStatic,
                  selected: _selectedMode == 'static',
                  onTap: () => setState(() => _selectedMode = 'static'),
                  isLeft: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _selectedMode == 'live'
                ? l10n.locationShareModeLiveDesc
                : l10n.locationShareModeStaticDesc,
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 12,
              fontWeight: FontWeight.w300,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildToggleOption({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required bool isLeft,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected ? Colors.white.withOpacity(0.25) : Colors.transparent,
            borderRadius: BorderRadius.horizontal(
              left: isLeft ? const Radius.circular(15) : Radius.zero,
              right: isLeft ? Radius.zero : const Radius.circular(15),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white60,
              fontSize: 15,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShareButton(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _isSending ? null : _startSharing,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF145A60),
            disabledBackgroundColor: Colors.white38,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 0,
          ),
          child: _isSending
              ? const SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF145A60)),
                )
              : Text(
                  l10n.locationShareButton,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
        ),
      ),
    );
  }
}
