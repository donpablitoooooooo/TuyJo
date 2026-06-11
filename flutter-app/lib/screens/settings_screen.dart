import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:private_messaging/generated/l10n/app_localizations.dart';
import '../services/pairing_service.dart';
import '../services/encryption_service.dart';
import '../services/chat_service.dart';
import '../services/notification_service.dart';
import '../services/backup_service.dart';
import '../services/couple_selfie_service.dart';
import 'pairing_wizard_screen.dart';
import 'backup_choice_screen.dart';
import 'couple_selfie_screen.dart';
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

      // Backup "completo": se accoppiato includi anche la chiave pubblica del
      // partner (e così l'ID famiglia è ricostruibile), così il ripristino può
      // riconnettere senza rifare il pairing. Se non accoppiato, esporta la
      // sola chiave privata come prima.
      final partnerKey = await _storage.read(key: 'partner_public_key');
      final String backupText;
      if (partnerKey != null) {
        backupText = base64Encode(utf8.encode(jsonEncode({
          'v': 1,
          'priv': privateKey,
          'partner': partnerKey,
        })));
      } else {
        backupText = privateKey;
      }

      await Clipboard.setData(ClipboardData(text: backupText));

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
  /// - 'all': elimina pairing + messaggi da entrambi i telefoni E dal server
  ///   (irreversibile); entrambi tornano alla schermata di pairing
  /// - 'mine': elimina i messaggi solo da QUESTO telefono; il server non viene
  ///   toccato; entrambi tornano alla schermata di pairing e dopo un nuovo
  ///   pairing la chat si ripristina dal server
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
        // OPZIONE 2: Elimina i messaggi solo da QUESTO telefono (es. Cambio Telefono)
        // NON eliminare dal server: il partner mantiene i suoi e la chat si
        // ripristina dal server dopo un nuovo pairing
        await pairingService.clearPairing();
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

      // Rimuovi token FCM (elimina il MIO documento utente, quindi NON in
      // modalità 'partner': lì resto paired e il documento deve sopravvivere)
      if (mode != 'partner' && chatId != null && myUserId != null && mounted) {
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
            const Icon(Icons.favorite, color: Color(0xFF3BA8B0)),
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
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF3BA8B0)),
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
            const Icon(Icons.backup, color: Color(0xFF3BA8B0)),
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
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF3BA8B0)),
            child: Text(l10n.settingsSaveKeyNow),
          ),
        ],
      ),
    );
  }

  /// Ripristino: carica il file del certificato (la chiave privata salvata col
  /// backup) e poi rifai il pairing QR per riprendere la chiave del partner.
  /// Se il file è un bundle completo (priv + partner) riconnette direttamente.
  Future<void> _startRestoreFlow() async {
    final l10n = AppLocalizations.of(context)!;

    // Passo 1 — spiega i due passaggi: carica il certificato, poi rifai il pair.
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.restore, color: Color(0xFF3BA8B0)),
            const SizedBox(width: 12),
            Expanded(child: Text(l10n.settingsRestoreDialogTitle)),
          ],
        ),
        content: const Text(
          'Per ripristinare:\n'
          '1) carichi il file del certificato salvato col backup;\n'
          '2) rifai il pairing con il partner tramite QR.\n\n'
          'Il certificato è la chiave che decifra i messaggi: senza, le chat '
          'non sono leggibili.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF3BA8B0)),
            child: const Text('Carica certificato'),
          ),
        ],
      ),
    );

    if (proceed != true || !mounted) return;

    // Passo 2 — scegli il file del certificato dal dispositivo.
    String raw;
    try {
      final result = await FilePicker.platform.pickFiles(withData: true);
      if (result == null || result.files.isEmpty) return; // annullato
      final picked = result.files.first;
      if (picked.bytes != null) {
        raw = utf8.decode(picked.bytes!).trim();
      } else if (picked.path != null) {
        raw = (await File(picked.path!).readAsString()).trim();
      } else {
        throw Exception('File non leggibile');
      }
    } catch (e) {
      if (!mounted) return;
      _showRestoreError(AppLocalizations.of(context)!.error(e.toString()));
      return;
    }

    // Il certificato può essere un bundle completo base64(json{priv, partner})
    // → riconnessione diretta, oppure la sola chiave privata → pairing QR.
    String key = raw;
    String? partnerKey;
    try {
      final obj = jsonDecode(utf8.decode(base64Decode(raw)));
      if (obj is Map && obj['priv'] is String) {
        key = obj['priv'] as String;
        partnerKey = obj['partner'] as String?;
      }
    } catch (_) {
      // non è un bundle: chiave privata grezza
    }

    if (!mounted) return;
    if (key.isEmpty) {
      _showRestoreError(
          AppLocalizations.of(context)!.settingsRestoreEmptyKeyError);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final encryptionService =
          Provider.of<EncryptionService>(context, listen: false);
      final pairingService =
          Provider.of<PairingService>(context, listen: false);

      encryptionService.loadPrivateKey(key);
      final publicKey = await encryptionService.deriveAndSavePublicKey();
      if (publicKey == null) {
        throw Exception('Impossibile derivare la chiave pubblica');
      }

      await _storage.write(key: 'rsa_private_key', value: key);
      await pairingService.saveMyPublicKey(publicKey);

      if (!mounted) return;
      final l10nOk = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text(l10nOk.settingsRestoreSuccess)),
            ],
          ),
          backgroundColor: Colors.green[600],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );

      if (partnerKey != null) {
        // Backup completo: riconnetti direttamente, senza pairing QR.
        // La UI passa automaticamente alla chat via Provider.
        await pairingService.restorePairing(partnerKey);
      } else {
        // Solo chiave privata: rifai il pairing QR per riprendere la chiave
        // del partner.
        await Future.delayed(const Duration(milliseconds: 600));
        if (!mounted) return;
        _startPairingWizard();
      }
    } catch (e) {
      if (!mounted) return;
      _showRestoreError(AppLocalizations.of(context)!.error(e.toString()));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showRestoreError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red[600],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _showBackupChoice() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BackupChoiceScreen()),
    );
    if (mounted) setState(() {});
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
        content: SingleChildScrollView(
          child: Column(
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
              const SizedBox(height: 12),
              // Rifai pairing / collega il nuovo dispositivo del partner
              // (es. se il partner ha perso la chiave).
              _OutlineButton(
                onPressed: _startNewPairingFlow,
                icon: Icons.qr_code,
                label: AppLocalizations.of(context)!.settingsNewPairingButton,
              ),
              const SizedBox(height: 12),
              _OutlineButton(
                onPressed: _showBackupChoice,
                icon: Icons.cloud,
                label: 'Backup e sicurezza',
              ),
            ] else ...[
              // Unpaired: scelta Nuovo vs Ripristino
              Text(
                AppLocalizations.of(context)!.settingsChooseAction,
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 16),
              _PurpleButton(
                onPressed: _startNewPairingFlow,
                icon: Icons.favorite,
                label: AppLocalizations.of(context)!.settingsNewPairingButton,
              ),
              const SizedBox(height: 12),
              _OutlineButton(
                onPressed: _startRestoreFlow,
                icon: Icons.restore,
                label: AppLocalizations.of(context)!.settingsRestoreFromBackupButton,
              ),
              const SizedBox(height: 12),
              _OutlineButton(
                onPressed: _showBackupChoice,
                icon: Icons.cloud,
                label: 'Backup e sicurezza',
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
