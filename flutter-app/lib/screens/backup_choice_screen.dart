import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/backup_service.dart';

/// Menu di scelta del backup delle chiavi.
///
/// Al nuovo pairing è un passo OBBLIGATORIO ([mandatory] true): niente è
/// preselezionato, e il bottone "Avanti" si attiva solo dopo aver scelto.
/// Da Impostazioni mostra la scelta corrente e permette di cambiarla.
/// Restituisce la [BackupStrategy] scelta via Navigator.pop.
class BackupChoiceScreen extends StatefulWidget {
  /// Se true l'utente DEVE scegliere per proseguire (niente "indietro").
  final bool mandatory;
  const BackupChoiceScreen({super.key, this.mandatory = false});

  @override
  State<BackupChoiceScreen> createState() => _BackupChoiceScreenState();
}

class _BackupChoiceScreenState extends State<BackupChoiceScreen> {
  static const Color _teal = Color(0xFF3BA8B0);
  final BackupService _backup = BackupService();
  BackupStrategy? _selected;

  @override
  void initState() {
    super.initState();
    // Nuovo pairing (mandatory): niente preselezionato.
    // Da Impostazioni: mostra la scelta corrente.
    if (!widget.mandatory) {
      _backup.getStrategy().then((s) {
        if (mounted) setState(() => _selected = s);
      });
    }
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
    if (!mounted) return;
    Navigator.pop(context, s);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.mandatory,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !widget.mandatory,
          title: const Text('Scegli il tipo di backup'),
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Come vuoi proteggere le tue chiavi? Da questo dipende se '
                    'potrai recuperare le chat cambiando telefono.',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  _option(
                    strategy: BackupStrategy.cloud,
                    icon: Icons.cloud_done,
                    title: 'Cloud automatico ($_cloudName)',
                    subtitle:
                        'Le chiavi si salvano nel tuo $_cloudName. Cambiando '
                        'telefono (stesso account) ritrovi tutto in automatico.',
                    color: _teal,
                  ),
                  _option(
                    strategy: BackupStrategy.manual,
                    icon: Icons.vpn_key,
                    title: 'Manuale',
                    subtitle:
                        'Salvi tu la chiave (ti si apre la condivisione). Per '
                        'ripristinare la importi.',
                    color: Colors.blueGrey,
                  ),
                  _option(
                    strategy: BackupStrategy.none,
                    icon: Icons.block,
                    title: 'Nessuno',
                    subtitle:
                        'Niente backup. Se perdi il telefono, perdi tutto.',
                    color: Colors.red,
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _selected == null ? null : _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _teal,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade300,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Avanti',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
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
