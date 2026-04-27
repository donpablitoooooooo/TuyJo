import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:private_messaging/generated/l10n/app_localizations.dart';
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
  bool _bothPaired = false; // Entrambi i dispositivi hanno completato il pairing
  bool _myQrWasScanned = false; // Il partner ha scansionato il mio QR
  String? _myPublicKey;
  StreamSubscription<QuerySnapshot>? _pairingStatusSubscription;
  StreamSubscription? _qrScannedSubscription;

  @override
  void initState() {
    super.initState();
    _generateMyQR();
  }

  @override
  void dispose() {
    _pairingStatusSubscription?.cancel();
    _qrScannedSubscription?.cancel();
    super.dispose();
  }

  /// Inizia ad ascoltare quando entrambi completano il pairing
  void _startListeningForBothPaired() async {
    final pairingService = Provider.of<PairingService>(context, listen: false);
    final familyChatId = await pairingService.getFamilyChatId();

    if (familyChatId == null) {
      if (kDebugMode) print('⚠️ No familyChatId yet, cannot listen');
      return;
    }

    if (kDebugMode) print('🎧 Starting listener for both paired on family: ${familyChatId.substring(0, 10)}...');

    // Ascolta la famiglia per vedere quando userCount >= 2
    _pairingStatusSubscription = FirebaseFirestore.instance
        .collection('families')
        .doc(familyChatId)
        .collection('users')
        .snapshots()
        .listen((snapshot) {
      final userCount = snapshot.docs.length;

      if (kDebugMode) print('👥 Wizard family users count: $userCount');

      if (mounted) {
        setState(() {
          _bothPaired = userCount >= 2;
        });
      }
    });
  }

  /// Ascolta quando il partner scansiona il nostro QR code
  void _startListeningForQRScanned(String myPublicKey) {
    final pairingService = Provider.of<PairingService>(context, listen: false);
    _qrScannedSubscription = pairingService.listenForMyQRScanned(myPublicKey, () {
      if (mounted && !_myQrWasScanned) {
        setState(() {
          _myQrWasScanned = true;
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

      // Store per uso futuro e avvia listener
      _myPublicKey = myPublicKey;
      await pairingService.cleanupPairingSignal(myPublicKey);
      _startListeningForQRScanned(myPublicKey);

      // Genera QR data (solo public key!)
      final qrData = await pairingService.getMyPublicKeyQRData(myPublicKey);

      setState(() {
        _myQrData = qrData;
        _isGeneratingQR = false;
        _step1Completed = true; // Step 1 completato automaticamente quando il QR è generato
      });

      // Se ho già la chiave partner (riapro wizard dopo aver fatto pairing),
      // avvia subito il listener
      if (pairingService.partnerPublicKey != null) {
        _startListeningForBothPaired();
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        _showFloatingSnackBar(l10n.pairingWizardQRGenerationError(e.toString()), isError: true);
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
        backgroundColor: isError ? Colors.red : const Color(0xFF3BA8B0),
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
        final l10n = AppLocalizations.of(context)!;
        if (success) {
          setState(() {
            _step2Completed = true;
            _showScanner = false;
          });

          _showFloatingSnackBar(l10n.pairingWizardQRScannedPartnerSuccess);

          // Inizia ad ascoltare quando entrambi hanno completato
          _startListeningForBothPaired();

          // NON navigare automaticamente - lascia che l'utente prema il pulsante
          // quando il partner ha completato il suo pairing
        } else {
          _showFloatingSnackBar(l10n.pairingWizardInvalidQRCode, isError: true);
        }
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        _showFloatingSnackBar(l10n.error(e.toString()), isError: true);
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
      backgroundColor: const Color(0xFF145A60),
      body: SizedBox.expand(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF3BA8B0),
                Color(0xFF145A60),
              ],
            ),
          ),
          child: Stack(
            children: [
              // Main content
              SafeArea(
              child: _isGeneratingQR
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            AppLocalizations.of(context)!.pairingWizardPreparingPairing,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Builder(
                      builder: (context) {
                        final l10n = AppLocalizations.of(context)!;
                        return SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Header
                              Text(
                                l10n.pairingWizardTitle,
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                l10n.pairingWizardSubtitle,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.white70,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 24),

                              // STEP 1: Mostra il tuo QR
                              _buildStepCard(
                                context: context,
                                stepNumber: 1,
                                title: l10n.pairingWizardStep1Title,
                                description: l10n.pairingWizardStep1Description,
                                isCompleted: _step1Completed,
                            child: Column(
                              children: [
                                if (_myQrData != null && !_myQrWasScanned) ...[
                                  Center(
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.05),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: QrImageView(
                                        data: _myQrData!,
                                        version: QrVersions.auto,
                                        size: 240,
                                        backgroundColor: Colors.white,
                                        eyeStyle: const QrEyeStyle(
                                          eyeShape: QrEyeShape.square,
                                          color: Color(0xFF3BA8B0),
                                        ),
                                        dataModuleStyle: const QrDataModuleStyle(
                                          dataModuleShape: QrDataModuleShape.square,
                                          color: Color(0xFF3BA8B0),
                                        ),
                                      ),
                                    ),
                                  ),
                                ] else if (_myQrWasScanned) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF3BA8B0).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: const Color(0xFF3BA8B0),
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        l10n.pairingWizardStepCompleted,
                                        style: const TextStyle(
                                          color: Color(0xFF3BA8B0),
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),

                          // STEP 2: Scansiona QR partner
                          _buildStepCard(
                            context: context,
                            stepNumber: 2,
                            title: l10n.pairingWizardStep2Title,
                            description: l10n.pairingWizardStep2Description,
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
                                            Color(0xFF3BA8B0),
                                            Color(0xFF145A60),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF3BA8B0).withValues(alpha: 0.3),
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
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                const Icon(
                                                  Icons.qr_code_scanner,
                                                  color: Colors.white,
                                                ),
                                                const SizedBox(width: 12),
                                                Text(
                                                  l10n.pairingWizardScanQRButton,
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
                                    ),
                                  ),
                                ] else ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF3BA8B0).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: const Color(0xFF3BA8B0),
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        l10n.pairingWizardStepCompleted,
                                        style: const TextStyle(
                                          color: Color(0xFF3BA8B0),
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),

                          const SizedBox(height: 32),

                          // Stato completamento - solo quando entrambi sono paired
                          if (_bothPaired) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  const Icon(
                                    Icons.favorite,
                                    color: Color(0xFF3BA8B0),
                                    size: 48,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    l10n.pairingWizardPairingCompleted,
                                    style: const TextStyle(
                                      color: Color(0xFF3BA8B0),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    width: double.infinity,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0xFF3BA8B0),
                                            Color(0xFF145A60),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF3BA8B0).withValues(alpha: 0.3),
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
                                            Navigator.of(context).popUntil((route) => route.isFirst);
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(vertical: 16),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                const Icon(
                                                  Icons.chat,
                                                  color: Colors.white,
                                                ),
                                                const SizedBox(width: 12),
                                                Text(
                                                  l10n.pairingWizardGoToChatButton,
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
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                    },
                  ),
            ),

            // Floating close button (last in Stack so it's on top)
            Positioned(
              top: 48,
              left: 16,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (kDebugMode) print('❌ [WIZARD] X button tapped - closing');
                  Navigator.of(context).pop();
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(Icons.close, color: Color(0xFF3BA8B0), size: 22),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildStepCard({
    required BuildContext context,
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
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2d3436),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
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
              Color(0xFF3BA8B0),
              Color(0xFF145A60),
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

            // Floating close button
            Positioned(
              top: 48,
              left: 16,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF3BA8B0)),
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
                      color: Colors.black.withValues(alpha: 0.3),
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
                          return const Icon(Icons.flash_off, color: Color(0xFF3BA8B0));
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
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(
                  AppLocalizations.of(context)!.pairingWizardScanInstructions,
                  style: const TextStyle(
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
                      color: Colors.black.withValues(alpha: 0.3),
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
                color: Colors.black.withValues(alpha: 0.8),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        AppLocalizations.of(context)!.pairingWizardImportingKey,
                        style: const TextStyle(
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
