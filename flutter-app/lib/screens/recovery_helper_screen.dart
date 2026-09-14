import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:private_messaging/generated/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../services/encryption_service.dart';
import '../services/recovery_service.dart';
import '../widgets/permission_denied_dialog.dart';
import 'recovery_style.dart';

enum _Phase { idle, scanning, sending, sent, failed }

/// Telefono che AIUTA il recupero, stesso stile del wizard di pairing:
/// 1) inquadra il QR del telefono nuovo, 2) invio del certificato.
/// - [RecoveryRole.helpPartner]: invio il certificato del PARTNER (dal suo
///   deposito, apribile solo con la mia chiave).
/// - [RecoveryRole.transferSelf]: invio il MIO certificato (vecchio telefono).
/// Il QR dice da chi il telefono nuovo si aspetta il certificato: se non
/// corrisponde al ruolo di questo pulsante l'invio viene rifiutato.
class RecoveryHelperScreen extends StatefulWidget {
  final RecoveryRole role;
  const RecoveryHelperScreen({super.key, required this.role});

  @override
  State<RecoveryHelperScreen> createState() => _RecoveryHelperScreenState();
}

class _RecoveryHelperScreenState extends State<RecoveryHelperScreen> {
  MobileScannerController? _controller;
  _Phase _phase = _Phase.idle;
  bool _handling = false;
  bool _scanned = false;
  String? _resultText;
  DateTime _lastInvalidToast = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _isTransfer => widget.role == RecoveryRole.transferSelf;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _openScannerOrExplain() async {
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
      if (!mounted || !ok) return;
    }
    final status = await Permission.camera.request();
    if (!mounted) return;
    if (status.isGranted || status.isLimited) {
      _controller?.dispose();
      setState(() {
        _controller = MobileScannerController();
        _phase = _Phase.scanning;
      });
      return;
    }
    await showPermissionDeniedDialog(
      context: context,
      title: l10n.permissionCameraDeniedTitle,
      message: l10n.permissionCameraPairingMessage,
      isPermanentlyDenied: true,
    );
  }

  void _closeScanner() {
    _controller?.dispose();
    _controller = null;
    setState(() => _phase = _Phase.idle);
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
    final l10n = AppLocalizations.of(context)!;
    final qr = RecoveryService.parseQr(raw);
    if (qr == null) {
      final now = DateTime.now();
      if (now.difference(_lastInvalidToast).inSeconds >= 3) {
        _lastInvalidToast = now;
        _snack(l10n.recoveryHelperInvalidQr, error: true);
      }
      return;
    }
    _handling = true;
    _controller?.dispose();
    _controller = null;
    setState(() => _phase = _Phase.idle);

    // Ruolo sbagliato: il telefono nuovo ha scelto l'altra sorgente.
    final expected = _isTransfer ? RecoverySource.self : RecoverySource.partner;
    if (qr.wants != expected) {
      _handling = false;
      await _showInfo(
        l10n.recoveryHelperConfirmTitle,
        _isTransfer
            ? l10n.recoveryHelperRoleMismatchTransfer
            : l10n.recoveryHelperRoleMismatchPartner,
      );
      return;
    }

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
            style: FilledButton.styleFrom(backgroundColor: RecoveryStyle.teal),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.recoveryHelperSend),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) {
      _handling = false;
      return;
    }

    setState(() {
      _scanned = true;
      _phase = _Phase.sending;
    });
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
      case RecoveryAnswerResult.roleMismatch:
        text = _isTransfer
            ? l10n.recoveryHelperRoleMismatchTransfer
            : l10n.recoveryHelperRoleMismatchPartner;
        break;
      case RecoveryAnswerResult.notPaired:
      case RecoveryAnswerResult.invalid:
        text = l10n.recoveryHelperInvalidQr;
        break;
      case RecoveryAnswerResult.error:
        text = l10n.recoveryHelperError;
        break;
    }
    _handling = false;
    setState(() {
      _phase = ok ? _Phase.sent : _Phase.failed;
      _resultText = text;
      if (!ok) _scanned = false;
    });
  }

  Future<void> _showInfo(String title, String message) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title),
        content: Text(message, style: const TextStyle(height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppLocalizations.of(context)!.close),
          ),
        ],
      ),
    );
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red[600] : RecoveryStyle.teal,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controller = _controller;
    if (_phase == _Phase.scanning && controller != null) {
      return RecoveryScannerView(
        controller: controller,
        onDetect: _onDetect,
        onClose: _closeScanner,
        hint: l10n.recoveryHelperScanHint,
      );
    }

    return RecoveryScaffold(
      title: _isTransfer
          ? l10n.recoveryHelperTitleTransfer
          : l10n.recoveryHelperTitlePartner,
      subtitle: _isTransfer
          ? l10n.recoveryHelperSubtitleTransfer
          : l10n.recoveryHelperSubtitlePartner,
      children: [
        // STEP 1: inquadra il QR
        RecoveryStepCard(
          title: l10n.recoveryHelperStep1Title,
          description: _isTransfer
              ? l10n.recoveryHelperStep1DescriptionTransfer
              : l10n.recoveryHelperStep1DescriptionPartner,
          isCompleted: _scanned,
          child: _scanned
              ? RecoveryCompletedBox(text: l10n.recoveryHelperQrScanned)
              : RecoveryGradientButton(
                  icon: Icons.qr_code_scanner,
                  label: l10n.recoveryHelperScanButton,
                  onTap: _openScannerOrExplain,
                ),
        ),
        if (_scanned || _phase == _Phase.failed) ...[
          const SizedBox(height: 24),
          // STEP 2: invio
          RecoveryStepCard(
            title: l10n.recoveryHelperStep2Title,
            description: l10n.recoveryHelperStep2Description,
            isCompleted: _phase == _Phase.sent,
            child: _step2Body(l10n),
          ),
        ],
      ],
    );
  }

  Widget _step2Body(AppLocalizations l10n) {
    switch (_phase) {
      case _Phase.sending:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: RecoveryStyle.teal),
            ),
            const SizedBox(width: 12),
            Text(
              l10n.recoveryHelperSending,
              style: const TextStyle(fontSize: 14, color: RecoveryStyle.ink),
            ),
          ],
        );
      case _Phase.sent:
        return Column(
          children: [
            const Icon(Icons.check_circle, color: RecoveryStyle.teal, size: 48),
            const SizedBox(height: 12),
            Text(
              _resultText ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: RecoveryStyle.teal,
                fontWeight: FontWeight.bold,
                fontSize: 16,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
            RecoveryGradientButton(
              icon: Icons.check,
              label: l10n.close,
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        );
      case _Phase.failed:
        return Column(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade600, size: 40),
            const SizedBox(height: 10),
            Text(
              _resultText ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.red.shade700, height: 1.4),
            ),
            const SizedBox(height: 14),
            RecoveryGradientButton(
              icon: Icons.qr_code_scanner,
              label: l10n.recoveryHelperScanAgain,
              onTap: _openScannerOrExplain,
            ),
          ],
        );
      case _Phase.idle:
      case _Phase.scanning:
        return const SizedBox.shrink();
    }
  }
}
