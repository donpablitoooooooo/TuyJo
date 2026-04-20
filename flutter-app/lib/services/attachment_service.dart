import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../models/message.dart';
import 'encryption_service.dart';
import 'attachment_cache_service.dart';
import 'crypto_isolate.dart';

/// Eccezione lanciata quando un permesso necessario per un allegato è negato
class AttachmentPermissionDeniedException implements Exception {
  final String permissionType; // 'camera' o 'photo'
  const AttachmentPermissionDeniedException(this.permissionType);
  @override
  String toString() => 'AttachmentPermissionDeniedException: $permissionType access denied';
}

class AttachmentService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _imagePicker = ImagePicker();
  final Uuid _uuid = const Uuid();
  final EncryptionService encryptionService;
  final AttachmentCacheService _cacheService = AttachmentCacheService();

  AttachmentService({required this.encryptionService}) {
    _cacheService.initialize();
  }

  /// Seleziona una o più foto dalla galleria (selezione multipla).
  /// Lancia [AttachmentPermissionDeniedException] se il permesso foto è negato.
  Future<List<File>> pickImageFromGallery() async {
    try {
      final List<XFile> images = await _imagePicker.pickMultiImage(
        maxWidth: 4096,  // Qualità stampa
        maxHeight: 4096, // Qualità stampa
        imageQuality: 95, // Alta qualità per stampa
      );

      if (images.isNotEmpty) {
        return images.map((xfile) => File(xfile.path)).toList();
      }
      return [];
    } on PlatformException catch (e) {
      if (e.code == 'photo_access_denied') {
        throw const AttachmentPermissionDeniedException('photo');
      }
      if (kDebugMode) print('❌ Error picking images: $e');
      return [];
    } catch (e) {
      if (kDebugMode) print('❌ Error picking images: $e');
      return [];
    }
  }

  /// Seleziona una foto dalla fotocamera.
  /// Lancia [AttachmentPermissionDeniedException] se il permesso camera è negato.
  Future<File?> pickImageFromCamera() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 4096,  // Qualità stampa
        maxHeight: 4096, // Qualità stampa
        imageQuality: 95, // Alta qualità per stampa
      );

      if (image != null) {
        return File(image.path);
      }
      return null;
    } on PlatformException catch (e) {
      if (e.code == 'camera_access_denied') {
        throw const AttachmentPermissionDeniedException('camera');
      }
      if (kDebugMode) print('❌ Error taking photo: $e');
      return null;
    } catch (e) {
      if (kDebugMode) print('❌ Error taking photo: $e');
      return null;
    }
  }

  /// Seleziona un video dalla galleria.
  /// Lancia [AttachmentPermissionDeniedException] se il permesso foto è negato.
  Future<File?> pickVideoFromGallery() async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5), // Max 5 minuti
      );

      if (video != null) {
        return File(video.path);
      }
      return null;
    } on PlatformException catch (e) {
      if (e.code == 'photo_access_denied') {
        throw const AttachmentPermissionDeniedException('photo');
      }
      if (kDebugMode) print('❌ Error picking video: $e');
      return null;
    } catch (e) {
      if (kDebugMode) print('❌ Error picking video: $e');
      return null;
    }
  }

  /// Seleziona un video dalla fotocamera.
  /// Lancia [AttachmentPermissionDeniedException] se il permesso camera è negato.
  Future<File?> pickVideoFromCamera() async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 5), // Max 5 minuti
      );

      if (video != null) {
        return File(video.path);
      }
      return null;
    } on PlatformException catch (e) {
      if (e.code == 'camera_access_denied') {
        throw const AttachmentPermissionDeniedException('camera');
      }
      if (kDebugMode) print('❌ Error recording video: $e');
      return null;
    } catch (e) {
      if (kDebugMode) print('❌ Error recording video: $e');
      return null;
    }
  }

  /// Seleziona un documento
  Future<File?> pickDocument() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'txt', 'xls', 'xlsx', 'ppt', 'pptx'],
      );

      if (result != null && result.files.single.path != null) {
        return File(result.files.single.path!);
      }
      return null;
    } catch (e) {
      if (kDebugMode) print('❌ Error picking document: $e');
      return null;
    }
  }

  /// Genera thumbnail quadrato 300x300 con center crop.
  /// Il decode + center-crop + encode JPEG gira su un isolate di background
  /// (compute()); il resize finale usa FlutterImageCompress che già usa
  /// un thread nativo, quindi non blocca l'UI.
  Future<Uint8List?> _generateThumbnail(Uint8List imageBytes) async {
    try {
      final Uint8List? croppedBytes = await compute(thumbnailCropEntry, imageBytes);
      if (croppedBytes == null) return null;

      final thumbnailBytes = await FlutterImageCompress.compressWithList(
        croppedBytes,
        minWidth: 300,
        minHeight: 300,
        quality: 90,
        format: CompressFormat.jpeg,
        keepExif: false,
      );

      if (kDebugMode) {
        print('📐 Generated thumbnail:');
        print('   Original: ${(imageBytes.length / 1024).toStringAsFixed(1)} KB');
        print('   Thumbnail: ${(thumbnailBytes.length / 1024).toStringAsFixed(1)} KB');
      }

      return thumbnailBytes;
    } catch (e) {
      if (kDebugMode) print('❌ Error generating thumbnail: $e');
      return null;
    }
  }

  /// Carica un file su Firebase Storage (con cifratura E2E dual)
  /// Il file viene cifrato prima dell'upload usando AES con dual encryption delle chiavi
  Future<Attachment?> uploadAttachment(
    File file,
    String familyChatId,
    String senderId,
    String senderPublicKey,
    String recipientPublicKey,
  ) async {
    try {
      final String fileName = file.path.split('/').last;
      final String? mimeType = lookupMimeType(file.path);

      // Leggi i byte del file ORIGINALE
      final Uint8List fileBytes = await file.readAsBytes();
      final int originalFileSize = fileBytes.length;

      // Determina il tipo di allegato
      String attachmentType;
      if (mimeType?.startsWith('image/') == true) {
        attachmentType = 'photo';
      } else if (mimeType?.startsWith('video/') == true) {
        attachmentType = 'video';
      } else {
        attachmentType = 'document';
      }

      // Genera un ID unico per l'allegato
      final String attachmentId = _uuid.v4();

      if (kDebugMode) {
        print('🔐 Encrypting attachment before upload...');
        print('   File: $fileName');
        print('   Size: ${(originalFileSize / 1024 / 1024).toStringAsFixed(2)} MB');
        print('   Type: $attachmentType');
      }

      // 🔐 CIFRA IL FILE con dual encryption (su isolate di background per non
      // bloccare la UI con AES su file grandi + due RSA encrypt)
      final encryptedData = await encryptionService.encryptFileDualAsync(
        fileBytes,
        senderPublicKey,
        recipientPublicKey,
      );

      final Uint8List encryptedFileBytes = encryptedData['encryptedFileBytes'] as Uint8List;
      final String encryptedKeyRecipient = encryptedData['encryptedKeyRecipient'] as String;
      final String encryptedKeySender = encryptedData['encryptedKeySender'] as String;
      final String iv = encryptedData['iv'] as String;
      final Uint8List aesKey = encryptedData['aesKey'] as Uint8List; // Salva chiave AES per thumbnail

      if (kDebugMode) {
        print('✅ File encrypted successfully');
        print('   Encrypted size: ${(encryptedFileBytes.length / 1024 / 1024).toStringAsFixed(2)} MB');
      }

      // Path su Firebase Storage: /families/{familyChatId}/attachments/{attachmentType}/{attachmentId}
      final String storagePath = 'families/$familyChatId/attachments/$attachmentType/$attachmentId';

      if (kDebugMode) {
        print('📤 Uploading encrypted file to Firebase Storage...');
        print('   Path: $storagePath');
      }

      // Upload del file CIFRATO
      final Reference ref = _storage.ref().child(storagePath);
      final UploadTask uploadTask = ref.putData(
        encryptedFileBytes,
        SettableMetadata(
          contentType: 'application/octet-stream', // File cifrato binario
          customMetadata: {
            'senderId': senderId,
            'originalFileName': fileName,
            'originalMimeType': mimeType ?? 'application/octet-stream',
            'encrypted': 'true',
          },
        ),
      );

      // Attendi il completamento
      final TaskSnapshot snapshot = await uploadTask;

      // Ottieni l'URL di download
      final String downloadUrl = await snapshot.ref.getDownloadURL();

      if (kDebugMode) {
        print('✅ Encrypted attachment uploaded successfully');
        print('   URL: $downloadUrl');
      }

      // 🚀 PRE-POPULATE CACHE: abbiamo già i bytes decifrati (fileBytes) e
      // ora conosciamo l'attachmentId finale. Salvandoli nella cache ora
      // evitiamo che AttachmentImage ri-scarichi e ri-decifri lo stesso
      // file quando il Firestore listener arriverà col messaggio reale.
      await _cacheService.saveToCache(attachmentId, fileBytes, isThumbnail: false);

      // 🖼️ GENERA E CARICA THUMBNAIL (solo per foto)
      // Wrappato in try/catch separato: un errore thumbnail NON deve
      // impedire il ritorno dell'Attachment (il full image è già caricato)
      String? thumbnailUrl;
      if (attachmentType == 'photo') {
        try {
          if (kDebugMode) print('📐 Generating thumbnail for photo...');

          final Uint8List? thumbnailBytes = await _generateThumbnail(fileBytes);

          if (thumbnailBytes != null) {
            // Cifra il thumbnail con le STESSE chiavi AES e IV del full image
            // (su isolate di background)
            final Uint8List encryptedThumbnailBytes = await encryptionService.encryptFileWithExistingKeyAsync(
              thumbnailBytes,
              aesKey, // Usa la stessa chiave AES del full image
              iv,     // Usa lo stesso IV del full image
            );

            // Upload thumbnail cifrato con path diverso
            final String thumbnailPath = 'families/$familyChatId/attachments/$attachmentType/thumbnails/$attachmentId';
            final Reference thumbnailRef = _storage.ref().child(thumbnailPath);

            if (kDebugMode) {
              print('📤 Uploading encrypted thumbnail...');
              print('   Path: $thumbnailPath');
            }

            final UploadTask thumbnailUploadTask = thumbnailRef.putData(
              encryptedThumbnailBytes,
              SettableMetadata(
                contentType: 'application/octet-stream',
                customMetadata: {
                  'senderId': senderId,
                  'type': 'thumbnail',
                  'encrypted': 'true',
                },
              ),
            );

            final TaskSnapshot thumbnailSnapshot = await thumbnailUploadTask;
            thumbnailUrl = await thumbnailSnapshot.ref.getDownloadURL();

            if (kDebugMode) {
              print('✅ Thumbnail uploaded successfully');
              print('   URL: $thumbnailUrl');
            }

            // 🚀 PRE-POPULATE CACHE: stesso motivo del full image — zero
            // round-trip a Firebase quando il messaggio arriva via listener.
            await _cacheService.saveToCache(attachmentId, thumbnailBytes, isThumbnail: true);
          }
        } catch (e) {
          // Thumbnail fallito, ma il full image è già caricato → continua
          if (kDebugMode) print('⚠️ Thumbnail generation/upload failed (non-fatal): $e');
        }
      }

      // Crea l'oggetto Attachment con metadata di cifratura
      if (kDebugMode) {
        print('✅ [uploadAttachment] Returning Attachment: id=$attachmentId, url=${downloadUrl.length > 50 ? '${downloadUrl.substring(0, 50)}...' : downloadUrl}');
      }
      return Attachment(
        id: attachmentId,
        type: attachmentType,
        url: downloadUrl,
        fileName: fileName,
        fileSize: originalFileSize, // Dimensione ORIGINALE (non cifrata)
        mimeType: mimeType,
        thumbnailUrl: thumbnailUrl, // URL thumbnail cifrato (solo per foto)
        encryptedKeyRecipient: encryptedKeyRecipient,
        encryptedKeySender: encryptedKeySender,
        iv: iv,
      );
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('❌ Error uploading encrypted attachment: $e');
        print('   Stack: ${stackTrace.toString().split('\n').take(5).join('\n')}');
      }
      return null;
    }
  }

  /// Carica più allegati contemporaneamente (con cifratura E2E dual)
  Future<List<Attachment>> uploadMultipleAttachments(
    List<File> files,
    String familyChatId,
    String senderId,
    String senderPublicKey,
    String recipientPublicKey,
  ) async {
    final List<Attachment> uploadedAttachments = [];

    for (final file in files) {
      final attachment = await uploadAttachment(
        file,
        familyChatId,
        senderId,
        senderPublicKey,
        recipientPublicKey,
      );
      if (attachment != null) {
        uploadedAttachments.add(attachment);
      }
    }

    return uploadedAttachments;
  }

  /// Scarica e decifra un allegato da Firebase Storage (con cache locale)
  /// Restituisce i byte del file DECIFRATO
  /// @param attachment - l'oggetto Attachment con i metadata di cifratura
  /// @param currentUserId - l'ID dell'utente corrente (per determinare quale chiave usare)
  /// @param messageSenderId - l'ID del sender del messaggio
  /// @param useThumbnail - se true, usa thumbnail invece di full image (solo per foto)
  Future<Uint8List?> downloadAndDecryptAttachment(
    Attachment attachment,
    String currentUserId,
    String messageSenderId, {
    bool useThumbnail = false,
  }) async {
    try {
      // 🚀 CACHE: Prova prima a caricare dalla cache locale
      final cachedBytes = await _cacheService.loadFromCache(
        attachment.id,
        isThumbnail: useThumbnail,
      );

      if (cachedBytes != null) {
        if (kDebugMode) {
          print('💨 Loaded ${useThumbnail ? "thumbnail" : "full image"} from cache: ${attachment.fileName}');
        }
        return cachedBytes;
      }

      // 🔒 DEDUPLICAZIONE: Controlla se c'è già una richiesta in corso per questo attachment
      final existingRequest = _cacheService.getPendingRequest(attachment.id, isThumbnail: useThumbnail);
      if (existingRequest != null) {
        if (kDebugMode) {
          print('⏳ Waiting for existing download to complete: ${useThumbnail ? "thumbnail" : "full"} ${attachment.fileName}');
        }
        return await existingRequest.future;
      }

      // 🔓 Registra questa richiesta come pendente
      final completer = _cacheService.registerPendingRequest(attachment.id, isThumbnail: useThumbnail);

      // Se richiesta thumbnail ma non esiste, usa full image
      final url = (useThumbnail && attachment.thumbnailUrl != null)
          ? attachment.thumbnailUrl!
          : attachment.url;

      // Se URL è vuoto o è un path locale (placeholder in upload), non scaricare
      if (url.isEmpty || (!url.startsWith('http') && !url.startsWith('gs://'))) {
        if (kDebugMode) {
          print('⏳ Attachment URL not ready (placeholder): $url');
        }
        _cacheService.completePendingRequest(attachment.id, null, isThumbnail: useThumbnail);
        return null;
      }

      if (kDebugMode) {
        print('📥 Downloading encrypted ${useThumbnail ? "thumbnail" : "full image"}...');
        print('   File: ${attachment.fileName}');
        print('   URL: $url');
      }

      // Scarica i byte cifrati da Firebase Storage
      final Reference ref = _storage.refFromURL(url);
      final Uint8List? encryptedBytes = await ref.getData();

      if (encryptedBytes == null) {
        if (kDebugMode) print('❌ Failed to download encrypted file');
        _cacheService.completePendingRequest(attachment.id, null, isThumbnail: useThumbnail);
        return null;
      }

      if (kDebugMode) {
        print('✅ Encrypted file downloaded');
        print('   Size: ${(encryptedBytes.length / 1024 / 1024).toStringAsFixed(2)} MB');
        print('🔓 Decrypting file...');
      }

      // Determina quale chiave usare: se sono il sender uso encryptedKeySender, altrimenti encryptedKeyRecipient
      final String encryptedAesKey = (currentUserId == messageSenderId)
          ? attachment.encryptedKeySender
          : attachment.encryptedKeyRecipient;

      if (kDebugMode) {
        print('   Using ${currentUserId == messageSenderId ? "sender" : "recipient"} key for decryption');
      }

      // Decifra il file usando la propria chiave privata (su isolate di background)
      final Uint8List decryptedBytes = await encryptionService.decryptFileAsync(
        encryptedBytes,
        encryptedAesKey,
        attachment.iv,
      );

      if (kDebugMode) {
        print('✅ File decrypted successfully');
        print('   Original size: ${(decryptedBytes.length / 1024 / 1024).toStringAsFixed(2)} MB');
      }

      // 💾 Salva in cache per prossimi utilizzi
      await _cacheService.saveToCache(
        attachment.id,
        decryptedBytes,
        isThumbnail: useThumbnail,
      );

      // 🔓 Completa la richiesta pendente con i dati
      _cacheService.completePendingRequest(attachment.id, decryptedBytes, isThumbnail: useThumbnail);

      return decryptedBytes;
    } catch (e) {
      if (kDebugMode) print('❌ Error downloading/decrypting attachment: $e');
      // Gestisci errore nella richiesta pendente
      _cacheService.errorPendingRequest(attachment.id, e, isThumbnail: useThumbnail);
      return null;
    }
  }

  /// Elimina un allegato da Firebase Storage
  Future<bool> deleteAttachment(String attachmentUrl) async {
    try {
      final Reference ref = _storage.refFromURL(attachmentUrl);
      await ref.delete();

      if (kDebugMode) {
        print('🗑️ Attachment deleted: $attachmentUrl');
      }

      return true;
    } catch (e) {
      if (kDebugMode) print('❌ Error deleting attachment: $e');
      return false;
    }
  }

  /// Ottiene il tipo di file leggibile
  String getFileTypeLabel(String type) {
    switch (type) {
      case 'photo':
        return 'Foto';
      case 'video':
        return 'Video';
      case 'document':
        return 'Documento';
      default:
        return 'File';
    }
  }

  /// Formatta la dimensione del file
  String formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
  }
}
