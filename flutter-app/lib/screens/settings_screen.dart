import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../services/pairing_service.dart';
import '../services/encryption_service.dart';
import '../services/chat_service.dart';
import '../services/notification_service.dart';
import '../services/couple_selfie_service.dart';
import 'pairing_wizard_screen.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _storage = const FlutterSecureStorage();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _copyPrivateKey() async {
    setState(() => _isLoading = true);
    try {
      final privateKey = await _storage.read(key: 'rsa_private_key');

      if (privateKey == null) {
        if (!mounted) return;
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.warning_amber, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text(l10n.settingsPrivateKeyNotFound)),
              ],
            ),
            backgroundColor: Colors.orange[700],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        return;
      }

      await Clipboard.setData(ClipboardData(text: privateKey));

      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text(l10n.settingsPrivateKeyCopied)),
            ],
          ),
          backgroundColor: Colors.green[600],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text(l10n.error(e.toString()))),
            ],
          ),
          backgroundColor: Colors.red[600],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Elimina il pairing con 3 modalità:
  /// - 'all': Elimina tutti i messaggi (server per entrambi)
  /// - 'mine': Elimina solo i miei (cache locale)
  /// - 'partner': Elimina quelli del partner (quando ha cambiato telefono senza unpair)
  Future<void> _deletePairing({required String mode}) async {
    setState(() => _isLoading = true);
    try {
      final pairingService = Provider.of<PairingService>(context, listen: false);
      final chatService = Provider.of<ChatService>(context, listen: false);
      final coupleSelfieService = Provider.of<CoupleSelfieService>(context, listen: false);
      final notificationService = Provider.of<NotificationService>(context, listen: false);

      final chatId = await pairingService.getFamilyChatId();
      final myUserId = await pairingService.getMyUserId();

      if (mode == 'all') {
        // OPZIONE 1: Elimina tutti i messaggi + foto dal server (per entrambi)
        if (chatId != null && mounted) {
          // Elimina messaggi + foto da Firestore e Storage
          await chatService.deleteMessagesAndCoupleSelfie(chatId);
        }

        // Unpair + pulisci cache locale
        await pairingService.clearPairing();
        chatService.stopListening();
        chatService.clearMessages();
        if (chatId != null) {
          // Pulisci SOLO cache locale (il server è già stato pulito da deleteMessagesAndCoupleSelfie)
          await coupleSelfieService.removeCoupleSelfie(
            chatId,
            deleteFromServer: false,
          );
        }
      } else if (mode == 'mine') {
        // OPZIONE 2: Elimina solo cache locale (Cambio Telefono)
        // NON eliminare dal server - il partner deve mantenerla!
        await pairingService.clearPairing();
        chatService.stopListening();
        chatService.clearMessages();
        if (chatId != null) {
          // Pulisci SOLO cache locale, mantieni sul server
          await coupleSelfieService.removeCoupleSelfie(
            chatId,
            deleteFromServer: false,
          );
        }
      } else if (mode == 'partner') {
        // OPZIONE 3: Triggera pulizia cache del partner (ha cambiato telefono senza unpair)
        if (chatId != null && myUserId != null) {
          // Scrivi flag in Firestore per notificare il partner di pulire la cache
          final partnerId = await pairingService.getPartnerId();
          if (partnerId != null) {
            await FirebaseFirestore.instance
                .collection('families')
                .doc(chatId)
                .collection('users')
                .doc(partnerId)
                .update({
              'delete_cache_requested': true,
              'delete_cache_requested_at': FieldValue.serverTimestamp(),
            });
          }
        }

        // Unpair + pulisci cache locale
        await pairingService.clearPairing();
        chatService.stopListening();
        chatService.clearMessages();
        if (chatId != null) {
          // Pulisci SOLO cache locale, mantieni sul server
          await coupleSelfieService.removeCoupleSelfie(
            chatId,
            deleteFromServer: false,
          );
        }
      }

      // Sempre: rimuovi token FCM
      if (chatId != null && myUserId != null && mounted) {
        await notificationService.deleteTokenFromFirestore(chatId, myUserId);
      }

      if (!mounted) return;

      final l10n = AppLocalizations.of(context)!;
      final message = mode == 'all'
          ? l10n.settingsDeleteAllMessagesSuccess
          : mode == 'mine'
              ? l10n.settingsDeleteLocalCacheSuccess
              : l10n.settingsDeletePartnerCacheSuccess;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.green[600],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text(l10n.error(e.toString()))),
            ],
          ),
          backgroundColor: Colors.red[600],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showNewPairingDialog() {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.favorite, color: Color(0xFF667eea)),
            const SizedBox(width: 12),
            Text(l10n.settingsNewPairingDialogTitle),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.settingsNewPairingDialogContent,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.settingsNewPairingDialogTip,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              // Mostra dialog per salvare la chiave (opzionale)
              _showSaveKeyDialog();
            },
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF667eea)),
            child: Text(l10n.continue_),
          ),
        ],
      ),
    );
  }

  void _showSaveKeyDialog() {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.backup, color: Color(0xFF667eea)),
            const SizedBox(width: 12),
            Text(l10n.settingsSaveKeyDialogTitle),
          ],
        ),
        content: Text(
          l10n.settingsSaveKeyDialogContent,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Vai direttamente al wizard
              _startPairingWizard();
            },
            child: Text(l10n.settingsSaveKeyLater),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              // Copia la chiave e poi vai al wizard
              await _copyPrivateKey();
              _startPairingWizard();
            },
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF667eea)),
            child: Text(l10n.settingsSaveKeyNow),
          ),
        ],
      ),
    );
  }

  void _showRestoreDialog() {
    final keyController = TextEditingController();
    final l10n = AppLocalizations.of(context)!;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.restore, color: Color(0xFF667eea)),
            const SizedBox(width: 12),
            Text(l10n.settingsRestoreDialogTitle),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.settingsRestoreDialogPrompt),
            const SizedBox(height: 16),
            TextField(
              controller: keyController,
              decoration: InputDecoration(
                hintText: l10n.settingsRestoreKeyHint,
                filled: true,
                fillColor: Colors.grey[50],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF667eea), width: 2),
                ),
              ),
              maxLines: 4,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              keyController.dispose();
              Navigator.pop(context);
            },
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () async {
              final key = keyController.text.trim();
              keyController.dispose();
              Navigator.pop(context);

              final l10n2 = AppLocalizations.of(context)!;
              if (key.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(Icons.warning_amber, color: Colors.white),
                        const SizedBox(width: 12),
                        Expanded(child: Text(l10n2.settingsRestoreEmptyKeyError)),
                      ],
                    ),
                    backgroundColor: Colors.orange[700],
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                );
                return;
              }

              // Ripristina la chiave
              setState(() => _isLoading = true);
              try {
                final encryptionService = Provider.of<EncryptionService>(context, listen: false);
                final pairingService = Provider.of<PairingService>(context, listen: false);

                encryptionService.loadPrivateKey(key);
                final publicKey = await encryptionService.deriveAndSavePublicKey();

                if (publicKey == null) {
                  throw Exception('Impossibile derivare la chiave pubblica');
                }

                await _storage.write(key: 'rsa_private_key', value: key);
                await pairingService.saveMyPublicKey(publicKey);

                if (!mounted) return;
                final l10n3 = AppLocalizations.of(context)!;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.white),
                        const SizedBox(width: 12),
                        Expanded(child: Text(l10n3.settingsRestoreSuccess)),
                      ],
                    ),
                    backgroundColor: Colors.green[600],
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                );

                // Vai al wizard di pairing
                await Future.delayed(const Duration(seconds: 1));
                _startPairingWizard();
              } catch (e) {
                if (!mounted) return;
                final l10n4 = AppLocalizations.of(context)!;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(Icons.error, color: Colors.white),
                        const SizedBox(width: 12),
                        Expanded(child: Text(l10n4.error(e.toString()))),
                      ],
                    ),
                    backgroundColor: Colors.red[600],
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                );
              } finally {
                setState(() => _isLoading = false);
              }
            },
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF667eea)),
            child: Text(l10n.settingsRestoreButton),
          ),
        ],
      ),
    );
  }

  Future<void> _startPairingWizard() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const PairingWizardScreen(),
      ),
    );
    // Non serve più _checkPairingStatus() - il build() si aggiorna automaticamente via Provider
  }

  void _showDeleteDialog() {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber, color: Colors.red),
            const SizedBox(width: 12),
            Text(l10n.settingsResetPairingDialogTitle),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.settingsResetPairingDialogPrompt),
            const SizedBox(height: 20),
            _DeleteOption(
              icon: Icons.delete_forever,
              title: l10n.settingsDeleteAllMessagesTitle,
              description: l10n.settingsDeleteAllMessagesDescription,
              isDestructive: true,
            ),
            const SizedBox(height: 12),
            _DeleteOption(
              icon: Icons.phone_android,
              title: l10n.settingsDeleteMyMessagesTitle,
              description: l10n.settingsDeleteMyMessagesDescription,
            ),
            const SizedBox(height: 12),
            _DeleteOption(
              icon: Icons.phonelink_erase,
              title: l10n.settingsDeletePartnerMessagesTitle,
              description: l10n.settingsDeletePartnerMessagesDescription,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deletePairing(mode: 'all');
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.settingsDeleteAllButton),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deletePairing(mode: 'mine');
            },
            child: Text(l10n.settingsDeleteMineButton),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deletePairing(mode: 'partner');
            },
            child: Text(l10n.settingsDeletePartnerButton),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Leggi lo stato pairing dal PairingService (con listen: true per auto-aggiornamento)
    final pairingService = Provider.of<PairingService>(context);
    final isPaired = pairingService.isPaired;

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667eea)),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 80, 20, 20),
      children: [
        // Header
        Center(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF667eea).withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.settings, color: Colors.white, size: 40),
              ),
              const SizedBox(height: 16),
              Text(
                AppLocalizations.of(context)!.settingsTitle,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF667eea),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),

        // Pairing Section
        _SettingsSection(
          title: AppLocalizations.of(context)!.settingsSectionPairing,
          icon: Icons.favorite,
          iconColor: const Color(0xFF667eea),
          children: [
            if (isPaired) ...[
              // Paired: mostra status e backup
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green[600]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context)!.settingsPairedStatus,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                AppLocalizations.of(context)!.settingsSavePrivateKeyReminder,
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 12),
              _OutlineButton(
                onPressed: _copyPrivateKey,
                icon: Icons.backup,
                label: AppLocalizations.of(context)!.settingsBackupKeyButton,
              ),
            ] else ...[
              // Unpaired: mostra scelta Nuovo vs Ripristino
              Text(
                AppLocalizations.of(context)!.settingsChooseAction,
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 16),
              _PurpleButton(
                onPressed: _showNewPairingDialog,
                icon: Icons.favorite,
                label: AppLocalizations.of(context)!.settingsNewPairingButton,
              ),
              const SizedBox(height: 12),
              _OutlineButton(
                onPressed: _showRestoreDialog,
                icon: Icons.restore,
                label: AppLocalizations.of(context)!.settingsRestoreFromBackupButton,
              ),
            ],
          ],
        ),

        // Delete Section (only if paired)
        if (isPaired) ...[
          const SizedBox(height: 24),
          _SettingsSection(
            title: AppLocalizations.of(context)!.settingsSectionDangerZone,
            icon: Icons.warning,
            iconColor: Colors.red,
            children: [
              Text(
                AppLocalizations.of(context)!.settingsUnpairWarning,
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 16),
              _OutlineButton(
                onPressed: _showDeleteDialog,
                icon: Icons.delete_outline,
                label: AppLocalizations.of(context)!.settingsResetPairingButton,
                color: Colors.red,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// Custom widgets per il design
class _SettingsSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color? iconColor;
  final List<Widget> children;

  const _SettingsSection({
    required this.title,
    required this.icon,
    this.iconColor,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor ?? const Color(0xFF667eea), size: 24),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF333333),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }
}

class _PurpleButton extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String label;

  const _PurpleButton({
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF667eea), Color(0xFF764ba2)],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Container(
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white),
                const SizedBox(width: 8),
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
    );
  }
}

class _OutlineButton extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final Color? color;

  const _OutlineButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final buttonColor = color ?? const Color(0xFF667eea);

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: buttonColor, width: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: buttonColor),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: buttonColor,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool isDestructive;

  const _DeleteOption({
    required this.icon,
    required this.title,
    required this.description,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          color: isDestructive ? Colors.red : Colors.grey[600],
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDestructive ? Colors.red : Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 12,
                  color: isDestructive ? Colors.red[300] : Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
