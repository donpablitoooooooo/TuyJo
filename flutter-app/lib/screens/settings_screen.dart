import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:intl/intl.dart';
import 'package:private_messaging/generated/l10n/app_localizations.dart';
import '../services/pairing_service.dart';
import '../services/chat_service.dart';
import '../services/notification_service.dart';
import '../services/backup_service.dart';
import '../services/couple_selfie_service.dart';
import 'pairing_wizard_screen.dart';
import 'backup_choice_screen.dart';
import 'couple_selfie_screen.dart';
import 'restore_screen.dart';
import 'delete_messages_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
  }

  /// Elimina messaggi con 3 modalità (modello "Dov'è" di Apple: i wipe
  /// selettivi svuotano il singolo telefono, i dati restano sul server e
  /// si recuperano rifacendo il pairing):
  /// - 'all': elimina pairing + messaggi da entrambi i telefoni E dal server
  ///   (irreversibile); entrambi tornano alla schermata di pairing
  /// - 'mine': elimina i messaggi solo da QUESTO telefono; il server non
  ///   viene toccato e il PARTNER resta paired in chat; questo telefono
  ///   torna alla schermata di pairing e rientrando recupera tutto dal server
  /// - 'partner': elimina i messaggi solo dal telefono del PARTNER (via flag
  ///   delete_cache_requested); il server non viene toccato e QUESTO telefono
  ///   resta paired e continua a vedere la chat; il partner dovrà rifare il
  ///   pairing con me per rientrare (la chat gli si ripristinerà dal server)
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
        await chatService.clearMessages(familyChatId: chatId);
        if (chatId != null) {
          // Pulisci SOLO cache locale (il server è già stato pulito da deleteMessagesAndCoupleSelfie)
          await coupleSelfieService.removeCoupleSelfie(
            chatId,
            deleteFromServer: false,
          );
        }
      } else if (mode == 'mine') {
        // OPZIONE 2: Elimina i messaggi solo da QUESTO telefono (stile
        // "Dov'è" di Apple: wipe del dispositivo, dati sul server intatti).
        // Il PARTNER resta paired e continua a vedere la chat: per questo il
        // mio documento utente NON va eliminato (la famiglia deve restare
        // completa). Tolgo solo il token FCM, così questo telefono non riceve
        // più notifiche. Rientrando con un nuovo pairing recupero tutto.
        if (chatId != null && myUserId != null) {
          try {
            await FirebaseFirestore.instance
                .collection('families')
                .doc(chatId)
                .collection('users')
                .doc(myUserId)
                .update({'fcm_token': FieldValue.delete()});
          } catch (_) {
            // Continua comunque con la pulizia locale
          }
        }

        // Unpair SOLO locale: nessun documento Firestore viene toccato
        await pairingService.unpairLocallyOnly();
        notificationService.clearSavedTokenTarget();
        chatService.stopListening();
        await chatService.clearMessages(familyChatId: chatId);
        if (chatId != null) {
          // Pulisci SOLO cache locale, mantieni sul server
          await coupleSelfieService.removeCoupleSelfie(
            chatId,
            deleteFromServer: false,
          );
        }
      } else if (mode == 'partner') {
        // OPZIONE 3: Elimina i messaggi solo dal telefono del PARTNER.
        // Il server NON viene toccato e IO resto paired: continuo a vedere la
        // chat. Il partner verrà spaiato dal suo telefono quando processa il
        // flag; per rientrare dovrà rifare il pairing con me.
        if (chatId != null && myUserId != null) {
          // Scrivi flag in Firestore: il listener del partner lo processa e
          // pulisce la sua cache. set+merge invece di update così non fallisce
          // se il documento del partner non esiste più.
          final partnerId = await pairingService.getPartnerId();
          if (partnerId != null) {
            await FirebaseFirestore.instance
                .collection('families')
                .doc(chatId)
                .collection('users')
                .doc(partnerId)
                .set({
              'delete_cache_requested': true,
              'delete_cache_requested_at': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }
        }
        // Niente unpair/stopListening/clearMessages: questo telefono resta in chat
      }

      // Rimuovi il MIO documento utente (token FCM compreso) SOLO per 'all':
      // in 'mine' e 'partner' i documenti devono sopravvivere, altrimenti il
      // telefono che mantiene la chat verrebbe auto-spaiato dal listener
      if (mode == 'all' && chatId != null && myUserId != null && mounted) {
        await notificationService.deleteTokenFromFirestore(chatId, myUserId);
        notificationService.clearSavedTokenTarget();
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

  /// Ripristino (pagina intera): cerca il certificato sul telefono e nel
  /// cloud, oppure lo fa caricare da file; con il certificato completo
  /// riconnette direttamente alla chat, altrimenti prosegue col wizard QR.
  Future<void> _openRestoreScreen() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RestoreScreen()),
    );
  }

  Future<void> _showBackupChoice() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BackupChoiceScreen()),
    );
    if (mounted) setState(() {});
  }

  /// Verifica attiva del backup: riscrive e rilegge il blob cloud, oppure
  /// controlla che il certificato copiato a mano sia ancora aggiornato.
  Future<void> _verifyBackup() async {
    final l10n = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final status = await BackupService().checkStatus();
    if (!mounted) return;
    Navigator.of(context).pop(); // chiude lo spinner

    final locale = Localizations.localeOf(context).toString();
    final when = status.savedAt != null
        ? DateFormat.yMd(locale).add_Hm().format(status.savedAt!.toLocal())
        : '—';
    final cloudName = Theme.of(context).platform == TargetPlatform.iOS ||
            Theme.of(context).platform == TargetPlatform.macOS
        ? 'iCloud'
        : 'Google';
    String message;
    bool ok;
    switch (status.health) {
      case BackupHealth.cloudOk:
        ok = true;
        message = l10n.backupCheckCloudOk(cloudName, when);
        break;
      case BackupHealth.cloudIncomplete:
        ok = false;
        message = l10n.backupCheckCloudIncomplete;
        break;
      case BackupHealth.cloudMissing:
        ok = false;
        message = l10n.backupCheckCloudMissing;
        break;
      case BackupHealth.manualOk:
        ok = true;
        message = l10n.backupCheckManualOk(when);
        break;
      case BackupHealth.manualOutdated:
        ok = false;
        message = l10n.backupCheckManualOutdated;
        break;
      case BackupHealth.none:
        ok = false;
        message = l10n.backupCheckNone;
        break;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(ok ? Icons.verified : Icons.warning_amber_rounded,
                color: ok ? const Color(0xFF3BA8B0) : Colors.orange[700]),
            const SizedBox(width: 10),
            Expanded(child: Text(l10n.backupCheckTitle)),
          ],
        ),
        content: Text(message, style: const TextStyle(height: 1.4)),
        actions: [
          if (!ok)
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _showBackupChoice();
              },
              child: Text(l10n.settingsBackupCertificateButton),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }

  /// Flusso "Nuovo pairing": 1) scelta backup obbligatoria (full page) →
  /// 2) scambio QR.
  Future<void> _startNewPairingFlow() async {
    final strategy = await Navigator.push<BackupStrategy>(
      context,
      MaterialPageRoute(
        builder: (_) => const BackupChoiceScreen(mandatory: true),
      ),
    );
    if (strategy == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PairingWizardScreen()),
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

  /// Pagina "Elimina Messaggi" (full page, stile wizard): la pagina ritorna
  /// la modalità scelta e l'esecuzione resta qui.
  Future<void> _openDeleteMessagesScreen() async {
    final mode = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const DeleteMessagesScreen()),
    );
    if (mode == null || !mounted) return;
    await _deletePairing(mode: mode);
  }

  @override
  Widget build(BuildContext context) {
    // Leggi lo stato pairing dal PairingService (con listen: true per auto-aggiornamento)
    final pairingService = Provider.of<PairingService>(context);
    final isPaired = pairingService.isPaired;

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3BA8B0)),
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
                    colors: [Color(0xFF3BA8B0), Color(0xFF145A60)],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF3BA8B0).withValues(alpha: 0.3),
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
                  color: Color(0xFF3BA8B0),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),

        // Welcome intro (only when not paired)
        if (!isPaired) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF3BA8B0).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF3BA8B0).withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              AppLocalizations.of(context)!.pairingWizardIntro,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 14,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
        ],

        // Profile Photo Section (only if paired) — first when paired
        if (isPaired) ...[
          _SettingsSection(
            title: AppLocalizations.of(context)!.settingsSectionProfilePhoto,
            icon: Icons.camera_alt,
            iconColor: const Color(0xFF3BA8B0),
            children: [
              // Anteprima foto profilo corrente
              Center(
                child: Consumer<CoupleSelfieService>(
                  builder: (context, coupleSelfieService, _) {
                    final hasSelfie = coupleSelfieService.hasSelfie;
                    final cachedSelfieBytes = coupleSelfieService.cachedSelfieBytes;

                    return Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF3BA8B0).withValues(alpha: 0.3),
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF3BA8B0).withValues(alpha: 0.15),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: hasSelfie && cachedSelfieBytes != null
                            ? Image.memory(
                                cachedSelfieBytes,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Image.asset(
                                  'assets/logo_teal.png',
                                  width: 100,
                                  height: 100,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : Image.asset(
                                'assets/logo_teal.png',
                                width: 100,
                                height: 100,
                                fit: BoxFit.cover,
                              ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Text(
                AppLocalizations.of(context)!.settingsProfilePhotoDescription,
                style: const TextStyle(color: Colors.grey, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              _PurpleButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CoupleSelfieScreen(),
                    ),
                  );
                },
                icon: Icons.camera_alt,
                label: AppLocalizations.of(context)!.settingsChangeProfilePhoto,
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],

        // Pairing Section
        _SettingsSection(
          title: AppLocalizations.of(context)!.settingsSectionPairing,
          icon: Icons.favorite,
          iconColor: const Color(0xFF3BA8B0),
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
              // Ricollega il nuovo telefono del partner (cambio telefono,
              // wipe, chiave persa): apre direttamente il wizard QR.
              _OutlineButton(
                onPressed: _startPairingWizard,
                icon: Icons.qr_code,
                label: AppLocalizations.of(context)!.settingsRestorePartnerButton,
              ),
              const SizedBox(height: 12),
              _OutlineButton(
                onPressed: _showBackupChoice,
                icon: Icons.cloud,
                label:
                    AppLocalizations.of(context)!.settingsBackupCertificateButton,
              ),
              const SizedBox(height: 12),
              _OutlineButton(
                onPressed: _verifyBackup,
                icon: Icons.verified_outlined,
                label: AppLocalizations.of(context)!.settingsVerifyBackupButton,
              ),
            ] else ...[
              // Unpaired: scelta Nuovo vs Ripristino
              Text(
                AppLocalizations.of(context)!.settingsChooseAction,
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(context)!.settingsAutoRestoreHint,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12, height: 1.35),
              ),
              const SizedBox(height: 16),
              _PurpleButton(
                onPressed: _startNewPairingFlow,
                icon: Icons.favorite,
                label: AppLocalizations.of(context)!.settingsNewPairingButton,
              ),
              const SizedBox(height: 12),
              _OutlineButton(
                onPressed: _openRestoreScreen,
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
                onPressed: _openDeleteMessagesScreen,
                icon: Icons.delete_outline,
                label: AppLocalizations.of(context)!.settingsResetPairingButton,
                color: Colors.red,
              ),
            ],
          ),
        ],

        // Versione app in fondo
        const SizedBox(height: 40),
        FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              return Center(
                child: Text(
                  'Tuijo v${snapshot.data!.version} (${snapshot.data!.buildNumber})',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[400],
                  ),
                ),
              );
            }
            return const SizedBox.shrink();
          },
        ),
        const SizedBox(height: 20),
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
            color: Colors.black.withValues(alpha: 0.05),
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
              Icon(icon, color: iconColor ?? const Color(0xFF3BA8B0), size: 24),
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
              colors: [Color(0xFF3BA8B0), Color(0xFF145A60)],
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
    final buttonColor = color ?? const Color(0xFF3BA8B0);

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
