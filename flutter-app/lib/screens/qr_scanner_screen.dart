import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../services/pairing_service.dart';
import '../services/encryption_service.dart';

/// Schermata per scansionare il QR code e importare K_family
/// Questa è l'opzione "Leggo la chiave famiglia"
class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _isProcessing = false;

  Future<void> _handleQRCode(String qrData) async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    final pairingService = Provider.of<PairingService>(context, listen: false);
    final encryptionService = Provider.of<EncryptionService>(context, listen: false);

    try {
      // Genera le chiavi RSA per questo utente se non esistono
      await encryptionService.generateAndStoreKeyPair();

      // Ottieni la chiave pubblica
      final myPublicKey = await encryptionService.getPublicKey();
      if (myPublicKey == null) {
        throw Exception('Impossibile generare chiave pubblica');
      }

      // Salva la chiave pubblica per calcolare l'ID utente
      await pairingService.saveMyPublicKey(myPublicKey);

      // Importa K_family dal QR
      final success = await pairingService.importFamilyKeyFromQR(qrData);

      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        if (success) {
          // Pairing completato
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.qrScannerPairingSuccess),
              backgroundColor: Colors.green,
            ),
          );

          // Torna indietro
          Navigator.pop(context, true);
        } else {
          // Errore nel pairing
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.qrScannerInvalidQRCode),
              backgroundColor: Colors.red,
            ),
          );

          setState(() {
            _isProcessing = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.error(e.toString())),
            backgroundColor: Colors.red,
          ),
        );

        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.qrScannerTitle),
        centerTitle: true,
        actions: [
          IconButton(
            icon: ListenableBuilder(
              listenable: _controller,
              builder: (context, child) {
                final torchState = _controller.value.torchState;
                switch (torchState) {
                  case TorchState.off:
                    return const Icon(Icons.flash_off);
                  case TorchState.on:
                    return const Icon(Icons.flash_on, color: Colors.yellow);
                  case TorchState.unavailable:
                  case TorchState.auto:
                    return const Icon(Icons.flash_off);
                }
              },
            ),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Scanner
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                final String? code = barcode.rawValue;
                if (code != null && !_isProcessing) {
                  _handleQRCode(code);
                  break;
                }
              }
            },
          ),

          // Overlay con istruzioni
          Positioned(
            top: 20,
            left: 20,
            right: 20,
            child: Card(
              color: Colors.black.withOpacity(0.7),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  l10n.qrScannerInstructions,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),

          // Overlay con griglia per guidare la scansione
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.green,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),

          // Indicator di processing
          if (_isProcessing)
            Container(
              color: Colors.black.withOpacity(0.7),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.qrScannerImporting,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
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
