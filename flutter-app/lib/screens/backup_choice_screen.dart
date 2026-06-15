import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:private_messaging/generated/l10n/app_localizations.dart';
import '../services/backup_service.dart';

/// Pagina "Backup del certificato": scelta di come custodire il certificato (la
/// chiave privata che serve a decifrare i messaggi). Riusa lo stile del wizard
/// QR (box bianchi radius 16 + ombra, bottoni a gradiente teal).
class BackupChoiceScreen extends StatefulWidget {
  final bool mandatory;
  const BackupChoiceScreen({super.key, this.mandatory = false});

  @override
  State<BackupChoiceScreen> createState() => _BackupChoiceScreenState();
}

class _BackupChoiceScreenState extends State<BackupChoiceScreen> {
  static const Color _teal = Color(0xFF3BA8B0);
  static const Color _tealDark = Color(0xFF145A60);
  static const Color _ink = Color(0xFF2d3436);

  final BackupService _backup = BackupService();
  BackupStrategy? _selected;
  bool _manualCopied = false;
  String? _certText; // testo del certificato pronto da copiare

  @override
  void initState() {
    super.initState();
    if (!widget.mandatory) {
      _backup.getStrategy().then((s) {
        if (mounted) setState(() => _selected = s);
      });
    }
    _loadCertificate();
  }

  bool get _isApple =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;
  String get _cloudName => _isApple ? 'iCloud' : 'Google';

  bool get _canProceed {
    final s = _selected;
    if (s == null) return false;
    if (s == BackupStrategy.manual) return _manualCopied;
    return true;
  }

  void _select(BackupStrategy s) => setState(() => _selected = s);

  Future<void> _confirm() async {
    final s = _selected;
    if (s == null) return;
    await _backup.setStrategy(s);
    if (!mounted) return;
    Navigator.pop(context, s);
  }

  /// Prepara il testo del certificato da copiare: bundle completo
  /// base64(json{v, priv, partner}) se accoppiato, altrimenti la sola chiave
  /// privata. Stesso formato che la pagina Ripristino sa incollare.
  /// Nel flusso "Nuovo pairing" le chiavi vengono generate in background da
  /// main.dart: se non sono ancora pronte riprova per qualche secondo.
  Future<void> _loadCertificate() async {
    const storage = FlutterSecureStorage();
    String? priv;
    for (var i = 0; i < 20; i++) {
      priv = await storage.read(key: 'rsa_private_key');
      if (priv != null || !mounted) break;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    if (priv == null || !mounted) return;
    final partner = await storage.read(key: 'partner_public_key');
    final text = partner != null
        ? base64Encode(utf8.encode(jsonEncode({
            'v': 1,
            'priv': priv,
            'partner': partner,
          })))
        : priv;
    if (mounted) setState(() => _certText = text);
  }

  Future<void> _copyCertificate() async {
    final text = _certText;
    if (text == null) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) setState(() => _manualCopied = true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      canPop: !widget.mandatory,
      child: Scaffold(
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
                      if (!widget.mandatory)
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        )
                      else
                        const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l10n.backupChoiceTitle,
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
                        l10n.backupChoiceIntro,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                      _option(
                        strategy: BackupStrategy.cloud,
                        icon: Icons.cloud_done,
                        title: l10n.backupChoiceCloudTitle(_cloudName),
                        subtitle: l10n.backupChoiceCloudSubtitle(_cloudName),
                        color: _teal,
                      ),
                      _option(
                        strategy: BackupStrategy.manual,
                        icon: Icons.vpn_key,
                        title: l10n.backupChoiceManualTitle,
                        subtitle: l10n.backupChoiceManualSubtitle,
                        color: _tealDark,
                        expanded: _manualExtra(),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: _gradientButton(
                    icon: Icons.arrow_forward,
                    label: l10n.commonNext,
                    onTap: _canProceed ? _confirm : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Box bianco stile wizard (radius 16 + ombra) ──────────────────────────
  BoxDecoration _cardDecoration({Color? border}) => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: border != null ? Border.all(color: border, width: 2) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      );

  // ── Bottone a gradiente stile wizard ─────────────────────────────────────
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
          gradient: enabled
              ? const LinearGradient(colors: [_teal, _tealDark])
              : null,
          color: enabled ? null : Colors.white24,
          borderRadius: BorderRadius.circular(12),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: _teal.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
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
                  Icon(icon, color: enabled ? Colors.white : Colors.white60),
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: TextStyle(
                      color: enabled ? Colors.white : Colors.white60,
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

  Widget _option({
    required BackupStrategy strategy,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    Widget? expanded,
  }) {
    final selected = _selected == strategy;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: _cardDecoration(border: selected ? color : null),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _select(strategy),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
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
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (selected)
                      Icon(Icons.check_circle, color: color),
                  ],
                ),
              ),
            ),
          ),
          if (selected && expanded != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: expanded,
            ),
        ],
      ),
    );
  }

  /// Dettaglio opzione manuale: anteprima del certificato + bottone copia.
  /// Niente file né condivisione (un file su Drive sarebbe di nuovo un cloud):
  /// l'utente incolla il certificato dove vuole lui — gestore di password,
  /// nota cifrata, persino carta. Massimo controllo per chi ci tiene.
  Widget _manualExtra() {
    final l10n = AppLocalizations.of(context)!;
    final cert = _certText;
    final preview = cert == null
        ? l10n.backupChoicePreparing
        : '${cert.substring(0, cert.length < 18 ? cert.length : 18)}…';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        const SizedBox(height: 10),
        Text(l10n.backupChoiceYourCertificate,
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F3F4),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            preview,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              letterSpacing: 1.2,
              color: _ink,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _gradientButton(
                icon: _manualCopied ? Icons.check : Icons.copy,
                label: _manualCopied
                    ? l10n.backupChoiceCopiedButton
                    : l10n.backupChoiceCopyButton,
                onTap: cert == null ? null : _copyCertificate,
              ),
            ),
            if (_manualCopied)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.check_circle, color: Colors.green),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          l10n.backupChoiceManualNote,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}
