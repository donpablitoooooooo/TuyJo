import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/pairing_service.dart';
import '../services/encryption_service.dart';
import '../services/chat_service.dart';
import 'pairing_wizard_screen.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _storage = const FlutterSecureStorage();
  final _keyController = TextEditingController();
  bool _isLoading = false;
  bool _isPaired = false;

  @override
  void initState() {
    super.initState();
    _checkPairingStatus();
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _checkPairingStatus() async {
    final pairingService = Provider.of<PairingService>(context, listen: false);
    final isPaired = pairingService.isPaired;
    setState(() {
      _isPaired = isPaired;
    });
  }

  Future<void> _copyPrivateKey() async {
    setState(() => _isLoading = true);
    try {
      final privateKey = await _storage.read(key: 'rsa_private_key');

      if (privateKey == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nessuna chiave privata trovata. Crea prima un pairing.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      await Clipboard.setData(ClipboardData(text: privateKey));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chiave privata copiata negli appunti'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _restorePrivateKey() async {
    final key = _keyController.text.trim();

    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Inserisci una chiave privata valida'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final encryptionService = Provider.of<EncryptionService>(context, listen: false);
      final pairingService = Provider.of<PairingService>(context, listen: false);

      // STEP 1: Valida la chiave PRIMA di salvare (atomicità)
      encryptionService.loadPrivateKey(key);

      // STEP 2: Deriva la chiave pubblica dalla chiave privata
      final publicKey = await encryptionService.deriveAndSavePublicKey();
      if (publicKey == null) {
        throw Exception('Impossibile derivare la chiave pubblica dalla chiave privata');
      }

      // STEP 3: Verifica se la chiave pubblica è diversa da quella esistente
      final existingPublicKey = await _storage.read(key: 'rsa_public_key');
      final bool isDifferentKey = existingPublicKey != null && existingPublicKey != publicKey;

      // STEP 4: Solo DOPO tutte le validazioni, salva la chiave privata
      await _storage.write(key: 'rsa_private_key', value: key);
      await pairingService.saveMyPublicKey(publicKey);

      // STEP 5: Se la chiave è diversa, pulisci il pairing esistente (Fix 2)
      if (isDifferentKey) {
        if (kDebugMode) print('⚠️ Chiave pubblica diversa rilevata - pulizia pairing');

        // Pulisci pairing perché la chiave è cambiata
        await pairingService.clearPairing();

        // Aggiorna stato UI
        setState(() => _isPaired = false);

        if (!mounted) return;
        _keyController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '⚠️ Chiave ripristinata con successo.\n'
              'Il pairing è stato resettato perché la chiave è diversa.\n'
              'Devi rifare il pairing per chattare.',
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
          ),
        );
        return;
      }

      if (!mounted) return;
      _keyController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Chiave privata ripristinata con successo'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Errore nel ripristino: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deletePairing(bool deleteMessages) async {
    setState(() => _isLoading = true);
    try {
      final pairingService = Provider.of<PairingService>(context, listen: false);
      final chatService = Provider.of<ChatService>(context, listen: false);

      // STEP 1: Ottieni chatId PRIMA di eliminare il pairing
      final chatId = await pairingService.getFamilyChatId();

      if (deleteMessages) {
        // Fix 3: Elimina TUTTO da Firestore (messaggi + documento family)
        if (chatId != null) {
          await chatService.deleteFamily(chatId);
          if (kDebugMode) print('✅ Family completamente eliminata da Firestore');
        } else {
          if (kDebugMode) print('⚠️ Nessun chatId trovato, skip eliminazione Firestore');
        }
      }

      // STEP 2: Elimina il pairing locale
      await pairingService.clearPairing();
      if (kDebugMode) print('✅ Pairing locale eliminato');

      // STEP 3: Ferma i listener e pulisci i messaggi locali
      chatService.stopListening();
      chatService.clearMessages();
      if (kDebugMode) print('✅ Listener fermati e cache locale pulita');

      // STEP 4: Aggiorna stato UI
      if (!mounted) return;
      setState(() => _isPaired = false);

      // Fix 4: Conferma successo con feedback chiaro
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deleteMessages
                ? '✅ Pairing e messaggi eliminati completamente.\n'
                  'Firestore: pulito | Cache locale: pulita'
                : '✅ Pairing eliminato.\n'
                  'Messaggi conservati su Firestore (non più leggibili senza re-pairing).'
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      // Fix 4: Gestione errore dettagliata
      if (kDebugMode) print('❌ Errore eliminazione pairing: $e');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Errore durante l\'eliminazione: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Pairing'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Scegli come resettare il pairing:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Text('📱 Solo Pairing'),
            SizedBox(height: 4),
            Text(
              'Elimina solo il pairing. I messaggi restano su Firestore (ma non saranno più leggibili senza re-pairing).',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            SizedBox(height: 16),
            Text('🗑️ Pairing e Messaggi'),
            SizedBox(height: 4),
            Text(
              'Elimina TUTTO: pairing e messaggi da Firestore. Nessun recupero possibile.',
              style: TextStyle(fontSize: 12, color: Colors.red),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deletePairing(false);
            },
            child: const Text('📱 Solo Pairing'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deletePairing(true);
            },
            child: const Text(
              '🗑️ Pairing e Messaggi',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Impostazioni'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Sezione Backup/Ripristino
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.backup, color: Colors.blue),
                            SizedBox(width: 8),
                            Text(
                              'Backup & Ripristino',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Copia la tua chiave privata per backup',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _copyPrivateKey,
                            icon: const Icon(Icons.copy),
                            label: const Text('Copia Chiave Privata'),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Ripristina da backup (nuovo telefono)',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _keyController,
                          decoration: const InputDecoration(
                            hintText: 'Incolla qui la chiave privata',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.all(12),
                          ),
                          maxLines: 3,
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _restorePrivateKey,
                            icon: const Icon(Icons.restore),
                            label: const Text('Ripristina Chiave'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Sezione Pairing
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.favorite, color: Colors.red),
                            SizedBox(width: 8),
                            Text(
                              'Pairing',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (_isPaired) ...[
                          const Text(
                            'Dispositivi già accoppiati ❤️',
                            style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                        ] else ...[
                          const Text(
                            'Accoppia i dispositivi per chattare',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                        ],
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const PairingWizardScreen(),
                                ),
                              );
                              _checkPairingStatus();
                            },
                            icon: const Icon(Icons.qr_code),
                            label: Text(_isPaired ? 'Rifai Pairing' : 'Inizia Pairing'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Sezione Elimina Pairing
                if (_isPaired)
                  Card(
                    color: Colors.red[50],
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.warning, color: Colors.red),
                              SizedBox(width: 8),
                              Text(
                                'Zona Pericolosa',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Elimina il pairing con il dispositivo accoppiato',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _showDeleteDialog,
                              icon: const Icon(Icons.delete_forever),
                              label: const Text('Elimina Pairing'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
