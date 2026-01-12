import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:private_messaging/generated/l10n/app_localizations.dart';
import '../services/couple_selfie_service.dart';
import '../services/pairing_service.dart';
import '../services/chat_service.dart';
import '../services/attachment_service.dart';
import '../services/encryption_service.dart';

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
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF5DBECC),
              Color(0xFF3B9DA6),
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
                  icon: const Icon(Icons.arrow_back, color: Color(0xFF5DBECC)),
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
                      Text(
                        l10n.coupleSelfieTitle,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l10n.coupleSelfieSubtitle,
                        style: const TextStyle(
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
                          color: Color(0xFF5DBECC),
                          size: 80,
                        ),
                      ),

                      const SizedBox(height: 64),

                      // Camera button
                      _buildActionButton(
                        icon: Icons.camera_alt,
                        label: l10n.coupleSelfieTakePhoto,
                        onPressed: _isProcessing ? null : () => _pickImage(ImageSource.camera),
                      ),

                      const SizedBox(height: 16),

                      // Gallery button
                      _buildActionButton(
                        icon: Icons.photo_library,
                        label: l10n.coupleSelfieChooseFromGallery,
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
                    Color(0xFF5DBECC),
                    Color(0xFF3B9DA6),
                  ],
                )
              : null,
          color: onPressed == null ? Colors.grey : null,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: (onPressed != null ? const Color(0xFF5DBECC) : Colors.grey)
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

      // 2. Crop image in square shape (will be displayed as circle)
      final l10n = AppLocalizations.of(context)!;
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: pickedFile.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: l10n.coupleSelfieCropTitle,
            toolbarColor: const Color(0xFF5DBECC),
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: const Color(0xFF5DBECC),
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
            hideBottomControls: false,
            backgroundColor: Colors.black,
          ),
          IOSUiSettings(
            title: l10n.coupleSelfieCropTitle,
            minimumAspectRatio: 1.0,
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
          ),
        ],
      );

      // Se croppedFile è null, il cropper potrebbe aver fallito o l'utente
      // potrebbe aver premuto OK senza modificare (bug di image_cropper).
      // In questo caso, croppiamo manualmente l'immagine a square
      File imageToUpload;
      if (croppedFile != null) {
        imageToUpload = File(croppedFile.path);
      } else {
        if (kDebugMode) print('⚠️ Cropper returned null, manually cropping to square...');
        imageToUpload = await _cropImageToSquare(File(pickedFile.path));
      }

      // 3. Upload to Firebase
      final coupleSelfieService = Provider.of<CoupleSelfieService>(context, listen: false);
      final pairingService = Provider.of<PairingService>(context, listen: false);
      final familyChatId = await pairingService.getFamilyChatId();

      if (familyChatId == null) {
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          _showSnackBar(l10n.coupleSelfieFamilyChatIdError, isError: true);
        }
        setState(() => _isProcessing = false);
        return;
      }

      // Carica la foto come couple selfie
      final success = await coupleSelfieService.uploadCoupleSelfie(
        imageToUpload,
        familyChatId,
      );

      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        if (success) {
          // Invia messaggio in chat con la nuova foto
          // IMPORTANTE: Questo carica la foto una seconda volta come allegato cifrato
          // La foto di coppia e l'allegato del messaggio sono due file separati:
          // - Foto di coppia: pubblica, sincronizzata automaticamente tra i dispositivi
          // - Allegato: cifrato end-to-end, parte del messaggio in chat
          try {
            await _sendPhotoChangeMessage(imageToUpload, familyChatId);
            _showSnackBar(l10n.coupleSelfieSaveSuccess);
          } catch (e) {
            // Foto caricata ma messaggio fallito - avvisa l'utente
            if (kDebugMode) print('⚠️ Photo uploaded but message failed: $e');
            _showSnackBar(
              '${l10n.coupleSelfieSaveSuccess}\n⚠️ Could not send message: ${e.toString()}',
              isError: false, // Non è un errore grave - la foto è stata caricata
            );
          }

          // Return to previous screen
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              Navigator.of(context, rootNavigator: false).pop();
            }
          });
        } else {
          _showSnackBar(l10n.coupleSelfieSaveError, isError: true);
        }
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        _showSnackBar(l10n.error(e.toString()), isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  /// Invia un messaggio in chat con la nuova foto di coppia
  /// Restituisce true se il messaggio è stato inviato con successo, false altrimenti
  Future<bool> _sendPhotoChangeMessage(File photoFile, String familyChatId) async {
    if (kDebugMode) print('📤 [COUPLE_SELFIE_SCREEN] Sending photo change message...');

    final chatService = Provider.of<ChatService>(context, listen: false);
    final attachmentService = Provider.of<AttachmentService>(context, listen: false);
    final pairingService = Provider.of<PairingService>(context, listen: false);
    final encryptionService = Provider.of<EncryptionService>(context, listen: false);

    // Ottieni le chiavi e gli ID necessari
    final senderId = await pairingService.getMyUserId();
    final senderPublicKey = await encryptionService.getPublicKey();
    final recipientPublicKey = pairingService.partnerPublicKey;

    if (senderId == null || senderPublicKey == null || recipientPublicKey == null) {
      if (kDebugMode) {
        print('❌ [COUPLE_SELFIE_SCREEN] Missing keys or IDs:');
        print('   senderId: $senderId');
        print('   senderPublicKey: ${senderPublicKey != null ? "present" : "null"}');
        print('   recipientPublicKey: ${recipientPublicKey != null ? "present" : "null"}');
      }
      throw Exception('Cannot send message: pairing keys not available. Please try again.');
    }

    // Upload della foto come allegato cifrato
    final attachment = await attachmentService.uploadAttachment(
      photoFile,
      familyChatId,
      senderId,
      senderPublicKey,
      recipientPublicKey,
    );

    if (attachment == null) {
      if (kDebugMode) print('❌ [COUPLE_SELFIE_SCREEN] Failed to upload attachment');
      throw Exception('Failed to upload photo attachment. Please try again.');
    }

    // Invia il messaggio con l'allegato
    final l10n = AppLocalizations.of(context)!;
    final messageSent = await chatService.sendMessage(
      l10n.coupleSelfieNewProfilePictureMessage,
      familyChatId,
      senderId,
      senderPublicKey,
      recipientPublicKey,
      attachments: [attachment],
    );

    if (kDebugMode) {
      if (messageSent) {
        print('✅ [COUPLE_SELFIE_SCREEN] Photo change message sent');
      } else {
        print('❌ [COUPLE_SELFIE_SCREEN] Failed to send message');
      }
    }

    if (!messageSent) {
      throw Exception('Failed to send photo change message. Please try again.');
    }

    return true;
  }

  /// Croppa manualmente un'immagine a formato square (1:1)
  /// Prende la dimensione più piccola e croppa dal centro
  Future<File> _cropImageToSquare(File imageFile) async {
    try {
      // Leggi l'immagine
      final bytes = await imageFile.readAsBytes();
      img.Image? image = img.decodeImage(bytes);

      if (image == null) {
        throw Exception('Failed to decode image');
      }

      // Calcola le dimensioni per il crop square
      final size = image.width < image.height ? image.width : image.height;
      final offsetX = (image.width - size) ~/ 2;
      final offsetY = (image.height - size) ~/ 2;

      // Croppa l'immagine
      final croppedImage = img.copyCrop(
        image,
        x: offsetX,
        y: offsetY,
        width: size,
        height: size,
      );

      // Salva il file croppato
      final tempDir = await getTemporaryDirectory();
      final croppedFile = File('${tempDir.path}/cropped_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await croppedFile.writeAsBytes(img.encodeJpg(croppedImage, quality: 95));

      if (kDebugMode) print('✅ Image manually cropped to ${size}x${size}');

      return croppedFile;
    } catch (e) {
      if (kDebugMode) print('❌ Error manually cropping image: $e');
      rethrow;
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
        backgroundColor: isError ? Colors.red : const Color(0xFF5DBECC),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
}
