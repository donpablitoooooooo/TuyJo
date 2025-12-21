import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:provider/provider.dart';
import '../services/couple_selfie_service.dart';
import '../services/pairing_service.dart';

/// Schermo per selezionare e croppare la foto di coppia
class CoupleSelfieScreen extends StatefulWidget {
  const CoupleSelfieScreen({Key? key}) : super(key: key);

  @override
  State<CoupleSelfieScreen> createState() => _CoupleSelfieScreenState();
}

class _CoupleSelfieScreenState extends State<CoupleSelfieScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
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
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Header
                      const Text(
                        'Foto di Coppia',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Scatta o seleziona una foto che rappresenta voi due',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white70,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 48),

                      // Preview circle with icon
                      Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.favorite,
                          color: Color(0xFF667eea),
                          size: 80,
                        ),
                      ),

                      const SizedBox(height: 64),

                      // Camera button
                      _buildActionButton(
                        icon: Icons.camera_alt,
                        label: 'Scatta Foto',
                        onPressed: _isProcessing ? null : () => _pickImage(ImageSource.camera),
                      ),

                      const SizedBox(height: 16),

                      // Gallery button
                      _buildActionButton(
                        icon: Icons.photo_library,
                        label: 'Scegli dalla Galleria',
                        onPressed: _isProcessing ? null : () => _pickImage(ImageSource.gallery),
                      ),

                      if (_isProcessing) ...[
                        const SizedBox(height: 24),
                        const CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: Container(
        decoration: BoxDecoration(
          gradient: onPressed != null
              ? const LinearGradient(
                  colors: [
                    Color(0xFF667eea),
                    Color(0xFF764ba2),
                  ],
                )
              : null,
          color: onPressed == null ? Colors.grey : null,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: (onPressed != null ? const Color(0xFF667eea) : Colors.grey)
                  .withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onPressed,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: Colors.white, size: 28),
                  const SizedBox(width: 16),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
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

  Future<void> _pickImage(ImageSource source) async {
    setState(() => _isProcessing = true);

    try {
      // 1. Pick image
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 95,
      );

      if (pickedFile == null) {
        setState(() => _isProcessing = false);
        return;
      }

      // 2. Crop image in circular shape
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: pickedFile.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        cropStyle: CropStyle.circle, // Circular crop!
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Centra le Facce',
            toolbarColor: const Color(0xFF667eea),
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: const Color(0xFF667eea),
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
            hideBottomControls: false,
          ),
          IOSUiSettings(
            title: 'Centra le Facce',
            minimumAspectRatio: 1.0,
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
          ),
        ],
      );

      if (croppedFile == null) {
        setState(() => _isProcessing = false);
        return;
      }

      // 3. Upload to Firebase
      final coupleSelfieService = Provider.of<CoupleSelfieService>(context, listen: false);
      final pairingService = Provider.of<PairingService>(context, listen: false);
      final familyChatId = await pairingService.getFamilyChatId();

      if (familyChatId == null) {
        if (mounted) {
          _showSnackBar('Errore: Family Chat ID non trovato', isError: true);
        }
        setState(() => _isProcessing = false);
        return;
      }

      final success = await coupleSelfieService.uploadCoupleSelfie(
        File(croppedFile.path),
        familyChatId,
      );

      if (mounted) {
        if (success) {
          _showSnackBar('Foto di coppia salvata!');
          // Return to previous screen
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              Navigator.of(context, rootNavigator: false).pop();
            }
          });
        } else {
          _showSnackBar('Errore nel salvare la foto', isError: true);
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Errore: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
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
      ),
    );
  }
}
