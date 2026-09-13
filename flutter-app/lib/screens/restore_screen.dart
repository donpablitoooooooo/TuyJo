import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:private_messaging/generated/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../services/backup_service.dart';
import '../services/encryption_service.dart';
import '../services/pairing_service.dart';
import 'pairing_wizard_screen.dart';

/// Da dove arriva il certificato trovato dalla pagina di ripristino.
enum _CertSource { checking, local, cloud, pasted, missing }

/// Pagina "Ripristino": recupera il certificato (la chiave privata salvata
/// col backup) e riporta l'utente in chat. Ordine di ricerca automatico:
/// già sul telefono → cloud (Block Store / iCloud) → incollato dagli appunti
/// (backup manuale). Se il certificato è completo (include la chiave del
/// partner) riconnette direttamente alla chat senza pairing QR; altrimenti
/// prosegue col wizard QR.
/// Riusa lo stile del wizard QR / pagina backup (gradiente teal, box bianchi).
class RestoreScreen extends StatefulWidget {
  const RestoreScreen({super.key});

  @override
  State<RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends State<RestoreScreen> {
  static const Color _teal = Color(0xFF3BA8B0);
  static const Color _tealDark = Color(0xFF145A60);
  static const Color _ink = Color(0xFF2d3436);

  final _storage = const FlutterSecureStorage();
  _CertSource _source = _CertSource.checking;
  String? _pastedKey; // chiave privata incollata dagli appunti
  String? _pastedPartnerKey; // chiave del partner dal bundle incollato
  bool _working = false; // "Avanti" in corso
  bool _manualOpen = false; // sezione "Ho un backup manuale" espansa

  @override
  void initState() {
    super.initState();
    _detectCertificate();
  }

  bool get _certificateReady =>
      _source == _CertSource.local ||
      _source == _CertSource.cloud ||
      _source == _CertSource.pasted;

  /// Cerca il certificato in automatico: prima sul telefono, poi nel cloud.
  Future<void> _detectCertificate() async {
    final priv = await _storage.read(key: 'rsa_private_key');
    final partner = await _storage.read(key: 'partner_public_key');
    // "Già presente" solo se il certificato è COMPLETO (chiave + partner).
    // Una chiave privata senza partner è quasi sempre una chiave nuova creata
    // da un wizard/backup aperto e abbandonato: non è il certificato
    // dell'utente e non deve bloccare il ripristino da cloud o da appunti.
    if (priv != null && partner != null) {
      if (mounted) setState(() => _source = _CertSource.local);
      return;
    }
    final restored =
        await BackupService().cloudRestoreIfNeeded(force: priv != null);
    if (mounted) {
      setState(() {
        _source = restored ? _CertSource.cloud : _CertSource.missing;
        if (!restored) _manualOpen = true;
      });
    }
  }

  /// Incolla il certificato dagli appunti (backup manuale): bundle completo
  /// base64(json{priv,partner}) oppure sola chiave privata grezza.
  Future<void> _pasteCertificate() async {
    String? raw;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      raw = data?.text?.trim();
    } catch (e) {
      if (!mounted) return;
      _showError(AppLocalizations.of(context)!
          .restoreClipboardError(e.toString()));
      return;
    }

    if (raw == null || raw.isEmpty) {
      if (!mounted) return;
      _showError(AppLocalizations.of(context)!.restoreClipboardEmpty);
      return;
    }

    _applyRaw(raw);
  }

  /// Importa il certificato da un file (es. tuyjo-certificato.txt salvato
  /// in Files o nel gestore di password).
  Future<void> _pickCertificateFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(withData: true);
      final file = result?.files.single;
      if (file == null) return;
      final bytes = file.bytes ??
          (file.path != null ? await File(file.path!).readAsBytes() : null);
      if (bytes == null) throw Exception('empty');
      _applyRaw(utf8.decode(bytes).trim());
    } catch (e) {
      if (!mounted) return;
      _showError(AppLocalizations.of(context)!.restoreFileReadError(e.toString()));
    }
  }

  /// Bundle base64(json{priv,pub?,partner?}) oppure chiave privata grezza.
  void _applyRaw(String raw) {
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
    setState(() {
      _pastedKey = key;
      _pastedPartnerKey = partnerKey;
      _source = _CertSource.pasted;
    });
  }

  /// Applica il certificato e prosegui: riconnessione diretta se c'è anche
  /// la chiave del partner, altrimenti wizard QR.
  Future<void> _proceed() async {
    setState(() => _working = true);
    try {
      final encryptionService =
          Provider.of<EncryptionService>(context, listen: false);
      final pairingService =
          Provider.of<PairingService>(context, listen: false);

      // 1. Chiave privata: incollata oppure già in storage (locale/cloud)
      final pasted = _pastedKey;
      final priv = pasted ?? await _storage.read(key: 'rsa_private_key');
      if (priv == null || priv.isEmpty) {
        throw Exception('certificato mancante');
      }
      encryptionService.loadPrivateKey(priv);
      await _storage.write(key: 'rsa_private_key', value: priv);

      // 2. Chiave pubblica. Se il certificato è stato incollato va SEMPRE
      // derivata dalla privata incollata: quella eventualmente in storage
      // potrebbe appartenere a un'altra coppia di chiavi (identità diversa →
      // familyChatId diverso → messaggi invisibili).
      String? pub = pasted != null
          ? await encryptionService.deriveAndSavePublicKey()
          : (await _storage.read(key: 'rsa_public_key') ??
              await encryptionService.deriveAndSavePublicKey());
      if (pub == null) {
        throw Exception('impossibile derivare la chiave pubblica');
      }
      await pairingService.saveMyPublicKey(pub);

      // 3. Chiave del partner: dal bundle incollato (mai da uno storage
      // residuo, che potrebbe riferirsi a un'altra identità) oppure dal
      // ripristino locale/cloud.
      final String? partner;
      if (pasted != null) {
        partner = _pastedPartnerKey;
        if (partner == null) await _storage.delete(key: 'partner_public_key');
      } else {
        partner = await _storage.read(key: 'partner_public_key');
      }

      if (!mounted) return;
      if (partner != null && partner.isNotEmpty) {
        // Certificato completo → riconnessione diretta, senza QR.
        // La UI passa alla chat via Provider: basta chiudere la pagina.
        final ok = await pairingService.restorePairing(partner);
        if (!ok) throw Exception('riconnessione non riuscita');
        if (!mounted) return;
        Navigator.pop(context);
      } else {
        // Solo identità → serve il pairing QR col partner.
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const PairingWizardScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        _showError(
            AppLocalizations.of(context)!.restoreFailed(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[600],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
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
                        l10n.restoreTitle,
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
                      l10n.restoreIntro,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    _statusCard(),
                    if (_source != _CertSource.checking) ...[
                      const SizedBox(height: 16),
                      _manualSection(l10n),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: _gradientButton(
                  icon: Icons.arrow_forward,
                  label:
                      _working ? l10n.restoreWorkingButton : l10n.commonNext,
                  onTap: (_certificateReady && !_working) ? _proceed : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Backup manuale: scelta secondaria, espandibile ───────────────────────
  Widget _manualSection(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextButton.icon(
          onPressed: () => setState(() => _manualOpen = !_manualOpen),
          icon: Icon(_manualOpen ? Icons.expand_less : Icons.expand_more,
              color: Colors.white),
          label: Text(
            l10n.restoreManualToggle,
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
        ),
        if (_manualOpen) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.restoreManualIntro,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4),
                ),
                const SizedBox(height: 12),
                _gradientButton(
                  icon: Icons.content_paste,
                  label: l10n.restorePasteButton,
                  onTap: _pasteCertificate,
                ),
                const SizedBox(height: 8),
                _gradientButton(
                  icon: Icons.folder_open,
                  label: l10n.restorePickFileButton,
                  onTap: _pickCertificateFile,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ── Card con lo stato della ricerca del certificato ──────────────────────
  Widget _statusCard() {
    final l10n = AppLocalizations.of(context)!;
    IconData icon = Icons.search;
    String title = l10n.restoreCheckingTitle;
    String subtitle = l10n.restoreCheckingSubtitle;

    if (_source == _CertSource.local) {
      icon = Icons.smartphone;
      title = l10n.restoreFoundLocalTitle;
      subtitle = l10n.restoreFoundLocalSubtitle;
    } else if (_source == _CertSource.cloud) {
      icon = Icons.cloud_done;
      title = l10n.restoreFoundCloudTitle;
      subtitle = l10n.restoreFoundCloudSubtitle;
    } else if (_source == _CertSource.pasted) {
      icon = Icons.content_paste;
      title = l10n.restorePastedTitle;
      subtitle = l10n.restorePastedSubtitle;
    } else if (_source == _CertSource.missing) {
      icon = Icons.key_off;
      title = l10n.restoreMissingTitle;
      subtitle = l10n.restoreMissingSubtitle;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(border: _certificateReady ? _teal : null),
      child: Row(
        children: [
          if (_source == _CertSource.checking)
            const SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(strokeWidth: 3, color: _teal),
            )
          else
            Icon(
              icon,
              color: _certificateReady ? _teal : Colors.orange[700],
              size: 30,
            ),
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
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          if (_certificateReady) const Icon(Icons.check_circle, color: _teal),
        ],
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
}
