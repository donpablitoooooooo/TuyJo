import 'package:flutter/material.dart';
import 'package:private_messaging/generated/l10n/app_localizations.dart';

/// Pagina "Elimina Messaggi" (stile wizard QR: gradiente teal, box bianchi):
/// scelta tra le 3 modalità di eliminazione. Non esegue nulla da sola —
/// ritorna la modalità scelta ('all' | 'mine' | 'partner') via Navigator.pop
/// e l'esecuzione resta in SettingsScreen (stesso pattern di
/// BackupChoiceScreen). Per "Tutti" (irreversibile) chiede una conferma.
class DeleteMessagesScreen extends StatefulWidget {
  const DeleteMessagesScreen({super.key});

  @override
  State<DeleteMessagesScreen> createState() => _DeleteMessagesScreenState();
}

class _DeleteMessagesScreenState extends State<DeleteMessagesScreen> {
  static const Color _teal = Color(0xFF3BA8B0);
  static const Color _tealDark = Color(0xFF145A60);
  static const Color _ink = Color(0xFF2d3436);

  String? _selected; // 'all' | 'mine' | 'partner'

  Future<void> _confirm() async {
    final mode = _selected;
    if (mode == null) return;

    // "Tutti" è irreversibile (cancella anche il server): chiedi conferma
    if (mode == 'all') {
      final l10n = AppLocalizations.of(context)!;
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.warning_amber, color: Colors.red),
              const SizedBox(width: 12),
              Expanded(child: Text(l10n.settingsDeleteAllMessagesTitle)),
            ],
          ),
          content: Text(l10n.settingsDeleteAllMessagesDescription),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(l10n.actionDelete),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    if (!mounted) return;
    Navigator.pop(context, mode);
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
                        l10n.settingsResetPairingDialogTitle,
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
                      l10n.settingsResetPairingDialogPrompt,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    _option(
                      mode: 'all',
                      icon: Icons.delete_forever,
                      title: l10n.settingsDeleteAllMessagesTitle,
                      subtitle: l10n.settingsDeleteAllMessagesDescription,
                      color: Colors.red[700]!,
                    ),
                    _option(
                      mode: 'mine',
                      icon: Icons.phone_android,
                      title: l10n.settingsDeleteMyMessagesTitle,
                      subtitle: l10n.settingsDeleteMyMessagesDescription,
                      color: _teal,
                    ),
                    _option(
                      mode: 'partner',
                      icon: Icons.phonelink_erase,
                      title: l10n.settingsDeletePartnerMessagesTitle,
                      subtitle: l10n.settingsDeletePartnerMessagesDescription,
                      color: _tealDark,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: _gradientButton(
                  icon: Icons.delete_outline,
                  label: l10n.actionDelete,
                  destructive: _selected == 'all',
                  onTap: _selected != null ? _confirm : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _option({
    required String mode,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    final selected = _selected == mode;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: _cardDecoration(border: selected ? color : null),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _selected = mode),
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
                if (selected) Icon(Icons.check_circle, color: color),
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

  // ── Bottone a gradiente stile wizard (rosso se distruttivo) ─────────────
  Widget _gradientButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool destructive = false,
  }) {
    final enabled = onTap != null;
    final colors = destructive
        ? [Colors.red.shade400, Colors.red.shade800]
        : const [_teal, _tealDark];
    final shadowColor = destructive ? Colors.red.shade400 : _teal;
    return SizedBox(
      width: double.infinity,
      child: Container(
        decoration: BoxDecoration(
          gradient: enabled ? LinearGradient(colors: colors) : null,
          color: enabled ? null : Colors.white24,
          borderRadius: BorderRadius.circular(12),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: shadowColor.withValues(alpha: 0.3),
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
}
