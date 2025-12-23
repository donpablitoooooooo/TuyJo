import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/pairing_service.dart';
import '../services/encryption_service.dart';

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
    final pairingService = Provider.of<PairingService>(context, listen: false);
    final encryptionService = Provider.of<EncryptionService>(context, listen: false);

    try {
      // Genera le chiavi RSA per l'utente se non esistono
      await encryptionService.generateAndStoreKeyPair();

      // Ottieni la chiave pubblica
      final myPublicKey = await encryptionService.getPublicKey();
      if (myPublicKey == null) {
        throw Exception('Impossibile generare chiave pubblica');
      }

      // Salva la chiave pubblica nel PairingService per calcolare l'ID utente
      await pairingService.saveMyPublicKey(myPublicKey);

      // Genera QR data (include K_family + chiave pubblica)
      final qrData = await pairingService.getFamilyKeyQRData(myPublicKey);

      setState(() {
        _qrData = qrData;
        _isGenerating = false;
      });
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.qrDisplayGenerationError(e.toString()))),
        );
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.qrDisplayTitle),
        centerTitle: true,
      ),
      body: _isGenerating
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(l10n.qrDisplayGenerating),
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
                  Text(
                    l10n.qrDisplayInstructions,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.qrDisplayDescription,
                    style: const TextStyle(
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

                  Card(
                    color: Colors.blue,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: Colors.white),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              l10n.qrDisplayInfoMessage,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  ElevatedButton.icon(
                    onPressed: () {
                      // Torna alla root per far rivalutare AuthWrapper
                      // che vedrà isPaired = true e mostrerà ChatScreen
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                    icon: const Icon(Icons.check),
                    label: Text(l10n.done),
                    style: ElevatedButton.styleFrom(
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
