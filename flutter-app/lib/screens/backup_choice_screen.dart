import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
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
  bool _manualShared = false;
  final TextEditingController _filename =
      TextEditingController(text: 'Tuijo-certificato.txt');

  @override
  void initState() {
    super.initState();
    if (!widget.mandatory) {
      _backup.getStrategy().then((s) {
        if (mounted) setState(() => _selected = s);
      });
    }
  }

  @override
  void dispose() {
    _filename.dispose();
    super.dispose();
  }

  bool get _isApple =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;
  String get _cloudName => _isApple ? 'iCloud' : 'Google';

  bool get _canProceed {
    final s = _selected;
    if (s == null) return false;
    if (s == BackupStrategy.manual) return _manualShared;
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

  Future<void> _shareCertificateFile() async {
    final priv = await const FlutterSecureStorage().read(key: 'rsa_private_key');
    if (priv == null) return;
    var name = _filename.text.trim();
    if (name.isEmpty) name = 'Tuijo-certificato.txt';
    if (!name.contains('.')) name = '$name.txt';
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsString(priv);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'Tuijo — certificato (backup)',
      ),
    );
    if (mounted) setState(() => _manualShared = true);
  }

  @override
  Widget build(BuildContext context) {
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
                      const Expanded(
                        child: Text(
                          'Backup del certificato',
                          style: TextStyle(
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
                      const Text(
                        'Il certificato è la chiave che serve a decifrare i '
                        'messaggi. Il backup salva il certificato, non i '
                        'messaggi: senza, nessuno potrà più leggere le chat.',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                      _option(
                        strategy: BackupStrategy.cloud,
                        icon: Icons.cloud_done,
                        title: 'Cloud automatico ($_cloudName)',
                        subtitle:
                            'Il certificato si salva nel tuo $_cloudName. Cambiando '
                            'telefono (stesso account) ritrovi tutto in automatico.',
                        color: _teal,
                      ),
                      _option(
                        strategy: BackupStrategy.manual,
                        icon: Icons.vpn_key,
                        title: 'Manuale',
                        subtitle:
                            'Salvi tu il file del certificato dove preferisci. '
                            'Per ripristinare lo importi.',
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
                    label: 'Avanti',
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

  Widget _manualExtra() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        const SizedBox(height: 8),
        const Text('Nome del file',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
        TextField(
          controller: _filename,
          decoration: const InputDecoration(
            isDense: true,
            border: InputBorder.none,
            prefixIcon: Icon(Icons.description_outlined, color: _teal),
          ),
          style: const TextStyle(fontWeight: FontWeight.w600, color: _ink),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _gradientButton(
                icon: _manualShared ? Icons.check : Icons.ios_share,
                label: _manualShared
                    ? 'Condividi di nuovo'
                    : 'Salva / Condividi il file',
                onTap: _shareCertificateFile,
              ),
            ),
            if (_manualShared)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.check_circle, color: Colors.green),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Lo salvi dove preferisci (Drive, File, ecc.). Tienilo al sicuro: '
          'chi ha questo file può decifrare le vostre chat.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}
