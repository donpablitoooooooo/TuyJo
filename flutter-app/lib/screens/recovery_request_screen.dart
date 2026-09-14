import 'dart:async';

import 'package:flutter/material.dart';
import 'package:private_messaging/generated/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/encryption_service.dart';
import '../services/pairing_service.dart';
import '../services/recovery_service.dart';

enum _Phase { preparing, waiting, received, expired, failed }

/// "Recupera la chat" (telefono nuovo): mostra un QR con una richiesta di
/// recupero. Il telefono del partner (Aiuta il partner a recuperare) o il
/// vecchio telefono (Trasferisci a un nuovo telefono) lo inquadra e risponde
/// con il certificato, cifrato per questo telefono. Ricevuto il certificato,
/// la chat si ricompone da sola con lo stesso ID di prima.
class RecoveryRequestScreen extends StatefulWidget {
  const RecoveryRequestScreen({super.key});

  @override
  State<RecoveryRequestScreen> createState() => _RecoveryRequestScreenState();
}

class _RecoveryRequestScreenState extends State<RecoveryRequestScreen> {
  static const Color _teal = Color(0xFF3BA8B0);
  static const Color _tealDark = Color(0xFF145A60);
  static const Color _ink = Color(0xFF2d3436);

  final RecoveryService _recovery = RecoveryService();
  RecoveryRequest? _request;
  StreamSubscription<RecoveryBundle?>? _sub;
  Timer? _expiryTimer;
  _Phase _phase = _Phase.preparing;
  String? _errorText;
  bool _answered = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _expiryTimer?.cancel();
    final req = _request;
    if (req != null && !_answered) _recovery.deleteRequest(req.id);
    super.dispose();
  }

  Future<void> _start() async {
    _sub?.cancel();
    _expiryTimer?.cancel();
    final old = _request;
    if (old != null) _recovery.deleteRequest(old.id);
    setState(() {
      _phase = _Phase.preparing;
      _request = null;
      _errorText = null;
      _answered = false;
    });
    try {
      final crypto = Provider.of<EncryptionService>(context, listen: false);
      // La generazione RSA-2048 dura 1–3 s sul telefono: lo spinner lo copre.
      await Future.delayed(const Duration(milliseconds: 50));
      final req = await _recovery.createRequest(crypto);
      if (!mounted) return;
      setState(() {
        _request = req;
        _phase = _Phase.waiting;
      });
      _expiryTimer = Timer(req.expiresAt.difference(DateTime.now()), () {
        if (!mounted || _phase != _Phase.waiting) return;
        _sub?.cancel();
        setState(() => _phase = _Phase.expired);
      });
      _sub = _recovery.watchRequest(req, crypto).listen(
        (bundle) {
          if (bundle != null) _onBundle(bundle);
        },
        onError: (e) => _fail(e.toString()),
      );
    } catch (e) {
      _fail(e.toString());
    }
  }

  Future<void> _onBundle(RecoveryBundle bundle) async {
    if (_answered) return;
    _answered = true;
    _sub?.cancel();
    _expiryTimer?.cancel();
    setState(() => _phase = _Phase.received);
    final req = _request;
    if (req != null) _recovery.deleteRequest(req.id);

    try {
      final crypto = Provider.of<EncryptionService>(context, listen: false);
      final pairing = Provider.of<PairingService>(context, listen: false);
      await _recovery.installBundle(bundle);
      await crypto.loadStoredKeyPair();
      await pairing.saveMyPublicKey(bundle.pub);
      final ok = await pairing.restorePairing(bundle.partner);
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      if (!ok) {
        switch (pairing.lastRestoreOutcome) {
          case RestoreOutcome.familyMissing:
            _fail(l10n.restoreConflictFamilyMissing, raw: true);
            return;
          case RestoreOutcome.keyMismatch:
            _fail(l10n.restoreConflictKeyMismatch, raw: true);
            return;
          default:
            _fail(l10n.recoveryRequestError('restorePairing'), raw: true);
            return;
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.recoveryRequestDone),
          backgroundColor: _tealDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      // La UI passa alla chat via Provider: basta chiudere la pagina.
      Navigator.of(context).pop();
    } catch (e) {
      _fail(e.toString());
    }
  }

  void _fail(String message, {bool raw = false}) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _phase = _Phase.failed;
      _errorText = raw ? message : l10n.recoveryRequestError(message);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: _tealDark,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_teal, _tealDark],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(
                        l10n.recoveryRequestTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      l10n.recoveryRequestIntro,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 14, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    _qrCard(),
                    const SizedBox(height: 16),
                    _statusCard(l10n),
                  ],
                ),
              ),
              if (_phase == _Phase.expired || _phase == _Phase.failed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: _gradientButton(
                    icon: Icons.refresh,
                    label: l10n.recoveryRequestNewQr,
                    onTap: _start,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _qrCard() {
    final req = _request;
    final showQr = req != null && _phase == _Phase.waiting;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: AspectRatio(
        aspectRatio: 1,
        child: Center(
          child: showQr
              ? QrImageView(
                  data: req.qrData,
                  version: QrVersions.auto,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                  backgroundColor: Colors.white,
                )
              : _phase == _Phase.preparing
                  ? const CircularProgressIndicator(color: _teal)
                  : Icon(
                      _phase == _Phase.received
                          ? Icons.check_circle
                          : Icons.qr_code_2,
                      size: 96,
                      color: _phase == _Phase.received
                          ? _teal
                          : Colors.grey.shade300,
                    ),
        ),
      ),
    );
  }

  Widget _statusCard(AppLocalizations l10n) {
    IconData icon;
    String title;
    String subtitle;
    bool busy = false;
    Color color = _teal;
    switch (_phase) {
      case _Phase.preparing:
        icon = Icons.hourglass_top;
        title = l10n.recoveryRequestPreparing;
        subtitle = '';
        busy = true;
        break;
      case _Phase.waiting:
        icon = Icons.phonelink_ring;
        title = l10n.recoveryRequestWaiting;
        subtitle = l10n.recoveryRequestWaitingSubtitle;
        busy = true;
        break;
      case _Phase.received:
        icon = Icons.download_done;
        title = l10n.recoveryRequestReceived;
        subtitle = '';
        busy = true;
        break;
      case _Phase.expired:
        icon = Icons.timer_off;
        title = l10n.recoveryRequestExpired;
        subtitle = l10n.recoveryRequestExpiredSubtitle;
        color = Colors.orange.shade700;
        break;
      case _Phase.failed:
        icon = Icons.error_outline;
        title = l10n.recoveryRequestFailedTitle;
        subtitle = _errorText ?? '';
        color = Colors.red.shade600;
        break;
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          if (busy)
            const SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(strokeWidth: 3, color: _teal),
            )
          else
            Icon(icon, color: color, size: 30),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _ink,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey.shade600, height: 1.35),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      );

  Widget _gradientButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return SizedBox(
      width: double.infinity,
      child: Container(
        decoration: BoxDecoration(
          gradient:
              enabled ? const LinearGradient(colors: [_teal, _tealDark]) : null,
          color: enabled ? null : Colors.white24,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: Colors.white),
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
