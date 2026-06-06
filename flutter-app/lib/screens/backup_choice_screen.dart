import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/backup_service.dart';

/// Menu di scelta del backup del CERTIFICATO (la chiave privata che serve a
/// decifrare i messaggi). Stile coerente con la pagina QR successiva.
///
/// Al nuovo pairing è un passo OBBLIGATORIO ([mandatory] true): niente è
/// preselezionato e "Avanti" si attiva solo dopo aver scelto. Da Impostazioni
/// mostra la scelta corrente. Restituisce la [BackupStrategy] via pop.
class BackupChoiceScreen extends StatefulWidget {
  final bool mandatory;
  const BackupChoiceScreen({super.key, this.mandatory = false});

  @override
  State<BackupChoiceScreen> createState() => _BackupChoiceScreenState();
}

class _BackupChoiceScreenState extends State<BackupChoiceScreen> {
  static const Color _teal = Color(0xFF3BA8B0);
  static const Color _tealDark = Color(0xFF145A60);

  final BackupService _backup = BackupService();
  BackupStrategy? _selected;
  final TextEditingController _filename =
      TextEditingController(text: 'TuyJo-certificato.txt');

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

  void _select(BackupStrategy s) => setState(() => _selected = s);

  Future<void> _confirm() async {
    final s = _selected;
    if (s == null) return;
    await _backup.setStrategy(s);
    if (s == BackupStrategy.manual) {
      await _shareCertificateFile();
    }
    if (!mounted) return;
    Navigator.pop(context, s);
  }

  Future<void> _shareCertificateFile() async {
    final priv = await const FlutterSecureStorage().read(key: 'rsa_private_key');
    if (priv == null) return;
    var name = _filename.text.trim();
    if (name.isEmpty) name = 'TuyJo-certificato.txt';
    if (!name.contains('.')) name = '$name.txt';
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsString(priv);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'TuyJo — certificato (backup)',
      ),
    );
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
                // Header
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
                          'Scegli il tipo di backup',
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
                      const Text(
                        'Il backup è del tuo certificato — la chiave che serve a '
                        'decifrare i messaggi, NON dei messaggi. Senza il '
                        'certificato nessuno potrà più leggere le chat.',
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
                            'Salvi tu il file del certificato (ti si apre la '
                            'condivisione). Per ripristinare lo importi.',
                        color: _tealDark,
                      ),
                      if (_selected == BackupStrategy.manual) _filenameCard(),
                      _option(
                        strategy: BackupStrategy.none,
                        icon: Icons.block,
                        title: 'Nessuno',
                        subtitle:
                            'Niente backup. Se perdi il telefono non potrai più '
                            'leggere i messaggi.',
                        color: Colors.red,
                      ),
                    ],
                  ),
                ),
                // Avanti
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _selected == null ? null : _confirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: _tealDark,
                        disabledBackgroundColor: Colors.white24,
                        disabledForegroundColor: Colors.white60,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Avanti',
                        style:
                            TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filenameCard() {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Nome del file',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            TextField(
              controller: _filename,
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                prefixIcon: Icon(Icons.description_outlined, color: _teal),
              ),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const Text(
              'Lo salvi dove preferisci (Drive, File, ecc.). Tienilo al sicuro: '
              'chi ha questo file può decifrare le vostre chat.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
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
  }) {
    final selected = _selected == strategy;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? color : Colors.transparent,
          width: 2,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(icon, color: color, size: 30),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(subtitle),
        ),
        trailing: selected ? Icon(Icons.check_circle, color: color) : null,
        onTap: () => _select(strategy),
      ),
    );
  }
}
