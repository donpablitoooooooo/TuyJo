import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:private_messaging/generated/l10n/app_localizations.dart';

/// Mostra un dialog generico per permesso negato con opzione "Apri Impostazioni".
///
/// [context] - BuildContext corrente
/// [title] - Titolo del dialog (es. "Microfono non disponibile")
/// [message] - Messaggio che spiega perché il permesso è necessario
/// [isPermanentlyDenied] - Se true, mostra il pulsante "Apri Impostazioni"
Future<void> showPermissionDeniedDialog({
  required BuildContext context,
  required String title,
  required String message,
  bool isPermanentlyDenied = false,
}) async {
  final l10n = AppLocalizations.of(context)!;

  return showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.block, color: Colors.redAccent, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              l10n.close,
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          if (isPermanentlyDenied)
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                openAppSettings();
              },
              child: Text(
                l10n.permissionOpenSettings,
                style: const TextStyle(
                  color: Color(0xFF3BA8B0),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      );
    },
  );
}

/// Mostra un SnackBar per permesso negato (per feedback meno invasivo).
void showPermissionDeniedSnackBar({
  required BuildContext context,
  required String message,
  bool showSettingsAction = false,
}) {
  final l10n = AppLocalizations.of(context)!;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 5),
      backgroundColor: Colors.red[700],
      action: showSettingsAction
          ? SnackBarAction(
              label: l10n.permissionOpenSettings,
              textColor: Colors.white,
              onPressed: () => openAppSettings(),
            )
          : null,
    ),
  );
}
