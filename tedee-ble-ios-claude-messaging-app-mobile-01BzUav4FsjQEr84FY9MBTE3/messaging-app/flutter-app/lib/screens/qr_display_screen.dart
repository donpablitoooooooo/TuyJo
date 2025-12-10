import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/pairing_service.dart';
import '../services/auth_service.dart';
import 'chat_screen.dart';

/// Schermata che genera e mostra il QR code contenente K_family
/// Questa è l'opzione "Creo io la chiave famiglia"
class QRDisplayScreen extends StatefulWidget {
  const QRDisplayScreen({super.key});

  @override
  State<QRDisplayScreen> createState() => _QRDisplayScreenState();
}

class _QRDisplayScreenState extends State<QRDisplayScreen> {
  String? _qrData;
  bool _isGenerating = true;

  @override
  void initState() {
    super.initState();
    _generateQRData();
  }

  Future<void> _generateQRData() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final pairingService = Provider.of<PairingService>(context, listen: false);

    try {
      // Verifica che l'utente sia autenticato
      if (authService.currentUser == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Devi prima autenticarti')),
          );
          Navigator.pop(context);
        }
        return;
      }

      // Ottieni chiave pubblica dell'utente corrente
      final myPublicKey = authService.currentUser!.publicKey;

      // Genera QR data (include K_family + chiave pubblica)
      final qrData = await pairingService.getFamilyKeyQRData(myPublicKey);

      setState(() {
        _qrData = qrData;
        _isGenerating = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore nella generazione QR: $e')),
        );
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mostra QR Code'),
        centerTitle: true,
      ),
      body: _isGenerating
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Generazione chiave famiglia...'),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.qr_code,
                    size: 80,
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Fai scansionare questo QR Code',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Il tuo partner dovrà selezionare "Leggo la chiave famiglia" e scansionare questo codice',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),

                  // QR Code
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: _qrData != null
                        ? QrImageView(
                            data: _qrData!,
                            version: QrVersions.auto,
                            size: 280,
                            backgroundColor: Colors.white,
                          )
                        : const SizedBox(
                            width: 280,
                            height: 280,
                            child: Center(child: CircularProgressIndicator()),
                          ),
                  ),

                  const SizedBox(height: 40),

                  const Card(
                    color: Colors.blue,
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.white),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Dopo la scansione, il pairing sarà completo e potrete iniziare a chattare in modo sicuro',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  ElevatedButton.icon(
                    onPressed: () {
                      // Vai alla chat (rimuovi tutte le schermate precedenti dallo stack)
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (context) => const ChatScreen()),
                        (route) => false,
                      );
                    },
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Inizia a chattare'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
