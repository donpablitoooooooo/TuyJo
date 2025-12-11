import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/pairing_service.dart';
import '../services/encryption_service.dart';
import '../services/chat_service.dart';
import 'qr_display_screen.dart';
import 'qr_scanner_screen.dart';
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
      // Verifica che la chiave sia valida provando a caricarla
      final encryptionService = Provider.of<EncryptionService>(context, listen: false);
      encryptionService.loadPrivateKey(key);

      // Salva la chiave privata
      await _storage.write(key: 'rsa_private_key', value: key);

      // Deriva e salva la chiave pubblica dalla chiave privata
      final publicKey = await encryptionService.deriveAndSavePublicKey();
      if (publicKey != null) {
        final pairingService = Provider.of<PairingService>(context, listen: false);
        await pairingService.saveMyPublicKey(publicKey);
      }

      if (!mounted) return;
      _keyController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chiave privata ripristinata con successo'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore nel ripristino: $e'),
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

      if (deleteMessages) {
        final familyChatId = await pairingService.getFamilyChatId();
        if (familyChatId != null) {
          await _deleteAllMessagesFromFirestore(familyChatId);
        }
      }

      // Ferma il listener e pulisci i messaggi locali
      chatService.stopListening();
      chatService.clearMessages();

      // Elimina il pairing
      await pairingService.clearPairing();

      if (!mounted) return;
      setState(() => _isPaired = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deleteMessages
              ? 'Pairing e messaggi eliminati'
              : 'Pairing eliminato'
          ),
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

  Future<void> _deleteAllMessagesFromFirestore(String familyChatId) async {
    try {
      final chatService = Provider.of<ChatService>(context, listen: false);
      // Usa il metodo deleteAllMessages che aggiungeremo al ChatService
      await chatService.deleteAllMessages(familyChatId);
      print('✅ All messages deleted from Firestore');
    } catch (e) {
      print('❌ Error deleting messages: $e');
      rethrow;
    }
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Elimina Pairing'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('Vuoi eliminare anche tutti i messaggi?'),
            SizedBox(height: 8),
            Text(
              'Questa azione non può essere annullata.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
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
            child: const Text('Solo Pairing'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deletePairing(true);
            },
            child: const Text(
              'Pairing e Messaggi',
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
                            Icon(Icons.qr_code, color: Colors.green),
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
                            'Dispositivi già accoppiati',
                            style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
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
                                  builder: (context) => const QRDisplayScreen(),
                                ),
                              );
                              _checkPairingStatus();
                            },
                            icon: const Icon(Icons.qr_code_2),
                            label: const Text('Crea QR Code'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const QRScannerScreen(),
                                ),
                              );
                              _checkPairingStatus();
                            },
                            icon: const Icon(Icons.qr_code_scanner),
                            label: const Text('Scansiona QR Code'),
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
