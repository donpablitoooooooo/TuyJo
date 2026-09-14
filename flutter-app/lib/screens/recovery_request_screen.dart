import 'dart:async';

import 'package:flutter/material.dart';
import 'package:private_messaging/generated/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../services/encryption_service.dart';
import '../services/pairing_service.dart';
import '../services/recovery_service.dart';
import 'recovery_style.dart';

enum _Phase { choosing, preparing, waiting, received, done, expired, failed }

/// "Recupera i messaggi" (telefono nuovo), stesso stile del wizard di pairing:
/// 1) da chi recuperare (partner / un altro mio telefono), 2) QR da far
/// inquadrare, 3) recupero. Il certificato arriva cifrato per una chiave
/// temporanea di questo telefono; la chat si ricompone con lo stesso ID.
class RecoveryRequestScreen extends StatefulWidget {
  const RecoveryRequestScreen({super.key});

  @override
  State<RecoveryRequestScreen> createState() => _RecoveryRequestScreenState();
}

class _RecoveryRequestScreenState extends State<RecoveryRequestScreen> {
  final RecoveryService _recovery = RecoveryService();
  RecoverySource? _source;
  RecoveryRequest? _request;
  StreamSubscription<RecoveryBundle?>? _sub;
  Timer? _expiryTimer;
  _Phase _phase = _Phase.choosing;
  String? _errorText;
  bool _answered = false;

  @override
  void dispose() {
    _sub?.cancel();
    _expiryTimer?.cancel();
    final req = _request;
    if (req != null && !_answered) _recovery.deleteRequest(req.id);
    super.dispose();
  }

  Future<void> _choose(RecoverySource source) async {
    setState(() => _source = source);
    await _start();
  }

  Future<void> _start() async {
    final source = _source;
    if (source == null) return;
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
      final req = await _recovery.createRequest(crypto, source: source);
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
      setState(() => _phase = _Phase.done);
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
    final source = _source;
    final step1Done = source != null;
    final step2Done = _phase == _Phase.received || _phase == _Phase.done;
    final step3Done = _phase == _Phase.done;

    return RecoveryScaffold(
      title: l10n.recoveryRequestTitle,
      subtitle: l10n.recoveryRequestSubtitle,
      children: [
        // STEP 1: da chi recuperare
        RecoveryStepCard(
          title: l10n.recoveryRequestStep1Title,
          description: l10n.recoveryRequestStep1Description,
          isCompleted: step1Done,
          child: Column(
            children: [
              _sourceTile(
                source: RecoverySource.partner,
                icon: Icons.favorite,
                title: l10n.recoveryRequestSourcePartner,
                subtitle: l10n.recoveryRequestSourcePartnerSubtitle,
              ),
              const SizedBox(height: 10),
              _sourceTile(
                source: RecoverySource.self,
                icon: Icons.phonelink,
                title: l10n.recoveryRequestSourceSelf,
                subtitle: l10n.recoveryRequestSourceSelfSubtitle,
              ),
            ],
          ),
        ),
        if (step1Done) ...[
          const SizedBox(height: 24),
          // STEP 2: QR da far inquadrare
          RecoveryStepCard(
            title: l10n.recoveryRequestStep2Title,
            description: source == RecoverySource.partner
                ? l10n.recoveryRequestStep2DescriptionPartner
                : l10n.recoveryRequestStep2DescriptionSelf,
            isCompleted: step2Done,
            child: _step2Body(l10n),
          ),
        ],
        if (step2Done) ...[
          const SizedBox(height: 24),
          // STEP 3: recupero
          RecoveryStepCard(
            title: l10n.recoveryRequestStep3Title,
            description: l10n.recoveryRequestStep3Description,
            isCompleted: step3Done,
            child: _step3Body(l10n),
          ),
        ],
        if (_phase == _Phase.failed) ...[
          const SizedBox(height: 24),
          RecoveryStepCard(
            title: l10n.recoveryRequestFailedTitle,
            description: _errorText ?? '',
            isCompleted: false,
            child: RecoveryGradientButton(
              icon: Icons.refresh,
              label: l10n.recoveryRequestNewQr,
              onTap: _start,
            ),
          ),
        ],
      ],
    );
  }

  Widget _sourceTile({
    required RecoverySource source,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final selected = _source == source;
    final locked = _phase != _Phase.choosing &&
        _phase != _Phase.waiting &&
        _phase != _Phase.expired &&
        _phase != _Phase.failed;
    return Material(
      color: selected
          ? RecoveryStyle.teal.withValues(alpha: 0.1)
          : const Color(0xFFF7F8F8),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: locked || selected ? null : () => _choose(source),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? RecoveryStyle.teal : Colors.grey.shade300,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: RecoveryStyle.teal, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: RecoveryStyle.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle, color: RecoveryStyle.teal),
            ],
          ),
        ),
      ),
    );
  }

  Widget _step2Body(AppLocalizations l10n) {
    final req = _request;
    switch (_phase) {
      case _Phase.preparing:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: CircularProgressIndicator(color: RecoveryStyle.teal),
        );
      case _Phase.waiting:
        return Column(
          children: [
            RecoveryQrBox(data: req!.qrData),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: RecoveryStyle.teal),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    l10n.recoveryRequestWaitingSubtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),
              ],
            ),
          ],
        );
      case _Phase.expired:
        return Column(
          children: [
            Text(
              l10n.recoveryRequestExpiredSubtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.orange.shade800),
            ),
            const SizedBox(height: 12),
            RecoveryGradientButton(
              icon: Icons.refresh,
              label: l10n.recoveryRequestNewQr,
              onTap: _start,
            ),
          ],
        );
      case _Phase.received:
      case _Phase.done:
        return RecoveryCompletedBox(text: l10n.recoveryRequestQrScanned);
      case _Phase.choosing:
      case _Phase.failed:
        return const SizedBox.shrink();
    }
  }

  Widget _step3Body(AppLocalizations l10n) {
    if (_phase == _Phase.done) {
      return Column(
        children: [
          const Icon(Icons.check_circle, color: RecoveryStyle.teal, size: 48),
          const SizedBox(height: 12),
          Text(
            l10n.recoveryRequestDone,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: RecoveryStyle.teal,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 16),
          RecoveryGradientButton(
            icon: Icons.chat_bubble,
            label: l10n.recoveryRequestGoToChat,
            // La UI sotto è già in chat (Provider): basta chiudere la pagina.
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: RecoveryStyle.teal),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            l10n.recoveryRequestReceived,
            style: const TextStyle(fontSize: 14, color: RecoveryStyle.ink),
          ),
        ),
      ],
    );
  }
}
