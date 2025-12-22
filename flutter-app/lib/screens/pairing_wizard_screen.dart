import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  bool _myQrScannedByPartner = false; // Il partner ha scansionato il mio QR
  bool _bothPaired = false; // Entrambi i dispositivi hanno completato il pairing
  StreamSubscription<QuerySnapshot>? _pairingStatusSubscription;

  @override
  void initState() {
    super.initState();
    _generateMyQR();
  }

  @override
  void dispose() {
    _pairingStatusSubscription?.cancel();
    super.dispose();
  }

  /// Inizia ad ascoltare quando il partner scansiona il mio QR
  void _startListeningForBothPaired() async {
    final pairingService = Provider.of<PairingService>(context, listen: false);
    final myUserId = await pairingService.getMyUserId();

    if (myUserId == null) return;

    // Usa collectionGroup per ascoltare TUTTE le famiglie dove esiste il mio documento
    // Questo funziona anche se non ho ancora scansionato il partner
    _pairingStatusSubscription = FirebaseFirestore.instance
        .collectionGroup('users')
        .where(FieldPath.documentId, isEqualTo: myUserId)
        .snapshots()
        .listen((snapshot) async {
      if (snapshot.docs.isEmpty) {
        // Nessuno mi ha ancora scansionato
        if (mounted) {
          setState(() {
            _myQrScannedByPartner = false;
            _bothPaired = false;
          });
        }
        return;
      }

      // Qualcuno mi ha scansionato! Ottieni il familyChatId dal path
      final docRef = snapshot.docs.first.reference;
      final familyChatId = docRef.parent.parent!.id;

      // Controlla quanti utenti ci sono in questa famiglia
      final familySnapshot = await FirebaseFirestore.instance
          .collection('families')
          .doc(familyChatId)
          .collection('users')
          .get();

      final userCount = familySnapshot.docs.length;

      if (mounted) {
        setState(() {
          _myQrScannedByPartner = userCount >= 1; // Il partner mi ha scansionato
          _bothPaired = userCount >= 2; // Entrambi paired
        });
      }
    });
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
        _step1Completed = true; // Step 1 completato automaticamente quando il QR è generato
      });

      // Inizia subito ad ascoltare per vedere se il partner scansiona il mio QR
      _startListeningForBothPaired();
    } catch (e) {
      if (mounted) {
        _showFloatingSnackBar('Errore generazione QR: $e', isError: true);
      }
    }
  }

  void _showFloatingSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? Colors.red : const Color(0xFF667eea),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: Duration(seconds: isError ? 3 : 2),
      ),
    );
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
          setState(() {
            _step2Completed = true;
            _showScanner = false;
          });

          _showFloatingSnackBar('QR del partner scansionato con successo!');

          // Inizia ad ascoltare quando entrambi hanno completato
          _startListeningForBothPaired();

          // NON navigare automaticamente - lascia che l'utente prema il pulsante
          // quando il partner ha completato il suo pairing
        } else {
          _showFloatingSnackBar('QR Code non valido', isError: true);
        }
      }
    } catch (e) {
      if (mounted) {
        _showFloatingSnackBar('Errore: $e', isError: true);
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF667eea),
              Color(0xFF764ba2),
            ],
          ),
        ),
        child: Stack(
          children: [
            // Floating back button
            Positioned(
              top: 48,
              left: 16,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Color(0xFF667eea)),
                  onPressed: () {
                    Navigator.of(context, rootNavigator: false).pop();
                  },
                ),
              ),
            ),

            // Main content
            SafeArea(
              child: _isGeneratingQR
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Preparazione pairing...',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header
                          const Text(
                            'Pairing con il tuo amore',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Completa entrambi i passaggi per accoppiare i dispositivi',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
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
                                // Mostra il QR finché il partner non lo ha scansionato
                                if (_myQrData != null && !_myQrScannedByPartner) ...[
                                  Center(
                                    child: Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.05),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: QrImageView(
                                        data: _myQrData!,
                                        version: QrVersions.auto,
                                        size: 200,
                                        backgroundColor: Colors.white,
                                        eyeStyle: const QrEyeStyle(
                                          eyeShape: QrEyeShape.square,
                                          color: Color(0xFF667eea),
                                        ),
                                        dataModuleStyle: const QrDataModuleStyle(
                                          dataModuleShape: QrDataModuleShape.square,
                                          color: Color(0xFF667eea),
                                        ),
                                      ),
                                    ),
                                  ),
                                ] else if (_myQrScannedByPartner) ...[
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF667eea).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: const Color(0xFF667eea),
                                      ),
                                    ),
                                    child: const Row(
                                      children: [
                                        Icon(
                                          Icons.check_circle,
                                          color: Color(0xFF667eea),
                                          size: 32,
                                        ),
                                        SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            'QR scansionato dal tuo amore!',
                                            style: TextStyle(
                                              color: Color(0xFF667eea),
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
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
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0xFF667eea),
                                            Color(0xFF764ba2),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF667eea).withOpacity(0.3),
                                            blurRadius: 8,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(12),
                                          onTap: () {
                                            setState(() {
                                              _showScanner = true;
                                            });
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(vertical: 16),
                                            child: const Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.qr_code_scanner,
                                                  color: Colors.white,
                                                ),
                                                SizedBox(width: 12),
                                                Text(
                                                  'Scansiona QR',
                                                  style: TextStyle(
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
                                    ),
                                  ),
                                ] else ...[
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF667eea).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: const Color(0xFF667eea),
                                      ),
                                    ),
                                    child: const Row(
                                      children: [
                                        Icon(
                                          Icons.check_circle,
                                          color: Color(0xFF667eea),
                                          size: 32,
                                        ),
                                        SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            'QR scansionato con successo!',
                                            style: TextStyle(
                                              color: Color(0xFF667eea),
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
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
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    _bothPaired ? Icons.favorite : Icons.favorite_border,
                                    color: const Color(0xFF667eea),
                                    size: 48,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    _bothPaired
                                        ? 'Pairing completato!'
                                        : 'Hai completato il pairing!',
                                    style: const TextStyle(
                                      color: Color(0xFF667eea),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _bothPaired
                                        ? 'Entrambi siete pronti!\nPremi "Vai alla Chat" per iniziare 💜'
                                        : 'Attendi che il tuo amore completi\nentrambi gli step...',
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 14,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: _bothPaired
                                      ? const LinearGradient(
                                          colors: [
                                            Color(0xFF667eea),
                                            Color(0xFF764ba2),
                                          ],
                                        )
                                      : null,
                                  color: _bothPaired ? null : Colors.grey.shade300,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: _bothPaired
                                      ? [
                                          BoxShadow(
                                            color: const Color(0xFF667eea).withOpacity(0.3),
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
                                    onTap: _bothPaired
                                        ? () {
                                            Navigator.of(context).popUntil((route) => route.isFirst);
                                          }
                                        : null,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            _bothPaired ? Icons.chat : Icons.hourglass_empty,
                                            color: _bothPaired ? Colors.white : Colors.grey.shade500,
                                          ),
                                          const SizedBox(width: 12),
                                          Text(
                                            _bothPaired ? 'Vai alla Chat' : 'In attesa...',
                                            style: TextStyle(
                                              color: _bothPaired ? Colors.white : Colors.grey.shade500,
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
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: isCompleted
                      ? const LinearGradient(
                          colors: [
                            Color(0xFF667eea),
                            Color(0xFF764ba2),
                          ],
                        )
                      : null,
                  color: isCompleted ? null : Colors.grey.shade200,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: isCompleted
                      ? const Icon(Icons.check, color: Colors.white, size: 24)
                      : Text(
                          '$stepNumber',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2d3436),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }

  Widget _buildQRScanner() {
    final controller = MobileScannerController();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF667eea),
              Color(0xFF764ba2),
            ],
          ),
        ),
        child: Stack(
          children: [
            // Camera scanner
            ClipRRect(
              borderRadius: BorderRadius.circular(0),
              child: MobileScanner(
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
            ),

            // Floating back button
            Positioned(
              top: 48,
              left: 16,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Color(0xFF667eea)),
                  onPressed: () {
                    controller.dispose();
                    setState(() {
                      _showScanner = false;
                    });
                  },
                ),
              ),
            ),

            // Floating torch button
            Positioned(
              top: 48,
              right: 16,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: ListenableBuilder(
                    listenable: controller,
                    builder: (context, child) {
                      final torchState = controller.value.torchState;
                      switch (torchState) {
                        case TorchState.off:
                          return const Icon(Icons.flash_off, color: Color(0xFF667eea));
                        case TorchState.on:
                          return const Icon(Icons.flash_on, color: Colors.amber);
                        case TorchState.unavailable:
                        case TorchState.auto:
                          return const Icon(Icons.flash_off, color: Colors.grey);
                      }
                    },
                  ),
                  onPressed: () => controller.toggleTorch(),
                ),
              ),
            ),

            // Instructions
            Positioned(
              top: 120,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Text(
                  'Inquadra il QR Code del tuo amore',
                  style: TextStyle(
                    color: Color(0xFF2d3436),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

            // Scan frame
            Center(
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white,
                    width: 3,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
              ),
            ),

            // Processing overlay
            if (_isProcessingQR)
              Container(
                color: Colors.black.withOpacity(0.8),
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
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
