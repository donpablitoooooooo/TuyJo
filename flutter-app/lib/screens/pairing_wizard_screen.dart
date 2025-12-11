import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/pairing_service.dart';
import '../services/encryption_service.dart';

/// Wizard di pairing con checklist a 2 step
/// Step 1: Mostra il tuo QR
/// Step 2: Scansiona il QR del partner
class PairingWizardScreen extends StatefulWidget {
  const PairingWizardScreen({Key? key}) : super(key: key);

  @override
  State<PairingWizardScreen> createState() => _PairingWizardScreenState();
}

class _PairingWizardScreenState extends State<PairingWizardScreen> {
  bool _step1Completed = false; // Mostra il tuo QR
  bool _step2Completed = false; // Scansiona QR partner
  String? _myQrData;
  bool _isGeneratingQR = true;
  bool _showScanner = false;
  bool _isProcessingQR = false;

  @override
  void initState() {
    super.initState();
    _generateMyQR();
  }

  Future<void> _generateMyQR() async {
    final pairingService = Provider.of<PairingService>(context, listen: false);
    final encryptionService = Provider.of<EncryptionService>(context, listen: false);

    try {
      // Genera le chiavi RSA se non esistono
      await encryptionService.generateAndStoreKeyPair();

      // Ottieni la chiave pubblica
      final myPublicKey = await encryptionService.getPublicKey();
      if (myPublicKey == null) {
        throw Exception('Impossibile generare chiave pubblica');
      }

      // Salva la chiave pubblica
      await pairingService.saveMyPublicKey(myPublicKey);

      // Genera QR data (solo public key!)
      final qrData = await pairingService.getMyPublicKeyQRData(myPublicKey);

      setState(() {
        _myQrData = qrData;
        _isGeneratingQR = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore generazione QR: $e')),
        );
      }
    }
  }

  Future<void> _handlePartnerQRCode(String qrData) async {
    if (_isProcessingQR) return;

    setState(() {
      _isProcessingQR = true;
    });

    final pairingService = Provider.of<PairingService>(context, listen: false);

    try {
      // Importa la chiave pubblica del partner
      final success = await pairingService.importPartnerPublicKeyFromQR(qrData);

      if (mounted) {
        if (success) {
          // UNPAIR SYNC: Ripristina pairing status su Firestore quando si completa il pairing
          await pairingService.resetPairingStatus();

          setState(() {
            _step2Completed = true;
            _showScanner = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ QR del partner scansionato!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );

          // Se entrambi gli step completati, naviga a ChatScreen
          if (_step1Completed && _step2Completed) {
            await Future.delayed(const Duration(milliseconds: 500));
            if (mounted) {
              Navigator.of(context).popUntil((route) => route.isFirst);
            }
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ QR Code non valido'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isProcessingQR = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showScanner) {
      return _buildQRScanner();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pairing'),
        centerTitle: true,
      ),
      body: _isGeneratingQR
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Preparazione pairing...'),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pairing con il tuo amore ❤️',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Completa entrambi i passaggi per accoppiare i dispositivi',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // STEP 1: Mostra il tuo QR
                  _buildStepCard(
                    stepNumber: 1,
                    title: 'Mostra il tuo QR',
                    description: 'Fai scansionare questo QR al tuo amore',
                    isCompleted: _step1Completed,
                    child: Column(
                      children: [
                        if (_myQrData != null) ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: QrImageView(
                              data: _myQrData!,
                              version: QrVersions.auto,
                              size: 200,
                              backgroundColor: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 16),
                          CheckboxListTile(
                            title: const Text('Il mio amore ha scansionato il QR'),
                            value: _step1Completed,
                            onChanged: (value) {
                              setState(() {
                                _step1Completed = value ?? false;
                              });
                            },
                            controlAffinity: ListTileControlAffinity.leading,
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // STEP 2: Scansiona QR partner
                  _buildStepCard(
                    stepNumber: 2,
                    title: 'Leggi il QR del tuo amore',
                    description: 'Scansiona il QR mostrato dal tuo amore',
                    isCompleted: _step2Completed,
                    child: Column(
                      children: [
                        if (!_step2Completed) ...[
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _showScanner = true;
                                });
                              },
                              icon: const Icon(Icons.qr_code_scanner),
                              label: const Text('Scansiona QR'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                            ),
                          ),
                        ] else ...[
                          const Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.green, size: 32),
                              SizedBox(width: 12),
                              Text(
                                'QR scansionato con successo!',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Stato completamento
                  if (_step1Completed && _step2Completed) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.favorite, color: Colors.red, size: 32),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Pairing completato! Potete iniziare a chattare in modo sicuro ❤️',
                              style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context).popUntil((route) => route.isFirst);
                        },
                        icon: const Icon(Icons.chat),
                        label: const Text('Vai alla Chat'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.green,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildStepCard({
    required int stepNumber,
    required String title,
    required String description,
    required bool isCompleted,
    required Widget child,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isCompleted ? Colors.green : Colors.blue,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: isCompleted
                        ? const Icon(Icons.check, color: Colors.white)
                        : Text(
                            '$stepNumber',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        description,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildQRScanner() {
    final controller = MobileScannerController();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scansiona QR'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            controller.dispose();
            setState(() {
              _showScanner = false;
            });
          },
        ),
        actions: [
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: controller.torchState,
              builder: (context, state, child) {
                switch (state) {
                  case TorchState.off:
                    return const Icon(Icons.flash_off);
                  case TorchState.on:
                    return const Icon(Icons.flash_on, color: Colors.yellow);
                }
              },
            ),
            onPressed: () => controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                final String? code = barcode.rawValue;
                if (code != null && !_isProcessingQR) {
                  controller.dispose();
                  _handlePartnerQRCode(code);
                  break;
                }
              }
            },
          ),
          Positioned(
            top: 20,
            left: 20,
            right: 20,
            child: Card(
              color: Colors.black.withOpacity(0.7),
              child: const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Inquadra il QR Code del tuo amore',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
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
          if (_isProcessingQR)
            Container(
              color: Colors.black.withOpacity(0.7),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Importazione chiave...',
                      style: TextStyle(
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
