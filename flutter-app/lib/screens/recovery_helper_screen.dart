import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:private_messaging/generated/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../services/encryption_service.dart';
import '../services/recovery_service.dart';
import '../widgets/permission_denied_dialog.dart';

enum _Phase { scanning, confirming, sending, sent, failed }

/// Telefono che AIUTA il recupero. Due ruoli:
/// - [RecoveryRole.helpPartner]: il partner ha un telefono nuovo. Inquadro
///   il suo QR e gli invio il SUO certificato (dal deposito che ha lasciato
///   per me, apribile solo con la mia chiave).
/// - [RecoveryRole.transferSelf]: sono io ad avere un telefono nuovo e ho
///   ancora il vecchio. Inquadro il QR del nuovo e gli invio il MIO
///   certificato.
/// Solo in presenza: la richiesta si trova solo inquadrando il QR.
class RecoveryHelperScreen extends StatefulWidget {
  final RecoveryRole role;
  const RecoveryHelperScreen({super.key, required this.role});

  @override
  State<RecoveryHelperScreen> createState() => _RecoveryHelperScreenState();
}

class _RecoveryHelperScreenState extends State<RecoveryHelperScreen> {
  static const Color _teal = Color(0xFF3BA8B0);
  static const Color _tealDark = Color(0xFF145A60);
  static const Color _ink = Color(0xFF2d3436);

  MobileScannerController? _controller;
  _Phase _phase = _Phase.scanning;
  bool _cameraReady = false;
  bool _handling = false;
  String? _resultText;
  DateTime _lastInvalidToast = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _isTransfer => widget.role == RecoveryRole.transferSelf;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestCamera());
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _requestCamera() async {
    final current = await Permission.camera.status;
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    if (!current.isGranted &&
        !current.isLimited &&
        !current.isPermanentlyDenied) {
      final ok = await showPermissionRationaleDialog(
        context: context,
        icon: Icons.qr_code_scanner,
        title: l10n.permissionCameraRationaleTitle,
        message: l10n.permissionCameraRationaleMessage,
      );
      if (!mounted) return;
      if (!ok) {
        Navigator.pop(context);
        return;
      }
    }
    final status = await Permission.camera.request();
    if (!mounted) return;
    if (status.isGranted || status.isLimited) {
      setState(() {
        _controller = MobileScannerController();
        _cameraReady = true;
      });
      return;
    }
    await showPermissionDeniedDialog(
      context: context,
      title: l10n.permissionCameraDeniedTitle,
      message: l10n.permissionCameraPairingMessage,
      isPermanentlyDenied: true,
    );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling || _phase != _Phase.scanning) return;
    String? raw;
    for (final b in capture.barcodes) {
      if (b.rawValue != null) {
        raw = b.rawValue;
        break;
      }
    }
    if (raw == null) return;
    final qr = RecoveryService.parseQr(raw);
    if (qr == null) {
      final now = DateTime.now();
      if (now.difference(_lastInvalidToast).inSeconds >= 3) {
        _lastInvalidToast = now;
        _snack(AppLocalizations.of(context)!.recoveryHelperInvalidQr, error: true);
      }
      return;
    }
    _handling = true;
    await _controller?.stop();
    if (!mounted) return;
    setState(() => _phase = _Phase.confirming);

    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l10n.recoveryHelperConfirmTitle),
        content: Text(
          _isTransfer
              ? l10n.recoveryHelperConfirmTransfer
              : l10n.recoveryHelperConfirmPartner,
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _teal),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.recoveryHelperSend),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) {
      _handling = false;
      setState(() => _phase = _Phase.scanning);
      await _controller?.start();
      return;
    }

    setState(() => _phase = _Phase.sending);
    final crypto = Provider.of<EncryptionService>(context, listen: false);
    final result = await RecoveryService().answerRequest(
      qr: qr,
      role: widget.role,
      crypto: crypto,
    );
    if (!mounted) return;
    String text;
    bool ok = false;
    switch (result) {
      case RecoveryAnswerResult.sent:
        ok = true;
        text = l10n.recoveryHelperSent;
        break;
      case RecoveryAnswerResult.expired:
        text = l10n.recoveryHelperExpired;
        break;
      case RecoveryAnswerResult.noDeposit:
        text = l10n.recoveryHelperNoDeposit;
        break;
      case RecoveryAnswerResult.notPaired:
      case RecoveryAnswerResult.invalid:
        text = l10n.recoveryHelperInvalidQr;
        break;
      case RecoveryAnswerResult.error:
        text = l10n.recoveryHelperError;
        break;
    }
    setState(() {
      _phase = ok ? _Phase.sent : _Phase.failed;
      _resultText = text;
    });
  }

  Future<void> _scanAgain() async {
    _handling = false;
    setState(() {
      _phase = _Phase.scanning;
      _resultText = null;
    });
    await _controller?.start();
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red[600] : _teal,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final title = _isTransfer
        ? l10n.recoveryHelperTitleTransfer
        : l10n.recoveryHelperTitlePartner;
    final showScanner =
        _cameraReady && (_phase == _Phase.scanning || _phase == _Phase.confirming);

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
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (showScanner)
                      IconButton(
                        icon: const Icon(Icons.flashlight_on, color: Colors.white),
                        onPressed: () => _controller?.toggleTorch(),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  _isTransfer
                      ? l10n.recoveryHelperIntroTransfer
                      : l10n.recoveryHelperIntroPartner,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 14, height: 1.4),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: showScanner ? _scanner() : _resultCard(l10n),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scanner() {
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: controller, onDetect: _onDetect),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 3),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 16,
            child: Text(
              AppLocalizations.of(context)!.recoveryHelperScanHint,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultCard(AppLocalizations l10n) {
    final sending = _phase == _Phase.sending || !_cameraReady;
    final ok = _phase == _Phase.sent;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              if (sending)
                const CircularProgressIndicator(color: _teal)
              else
                Icon(
                  ok ? Icons.check_circle : Icons.error_outline,
                  size: 56,
                  color: ok ? _teal : Colors.red.shade600,
                ),
              const SizedBox(height: 16),
              Text(
                sending
                    ? l10n.recoveryHelperSending
                    : (_resultText ?? ''),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: _ink, height: 1.4),
              ),
            ],
          ),
        ),
        const Spacer(),
        if (!sending)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: _tealDark,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: ok ? () => Navigator.pop(context) : _scanAgain,
              icon: Icon(ok ? Icons.check : Icons.qr_code_scanner),
              label: Text(ok ? l10n.close : l10n.recoveryHelperScanAgain),
            ),
          ),
      ],
    );
  }
}
