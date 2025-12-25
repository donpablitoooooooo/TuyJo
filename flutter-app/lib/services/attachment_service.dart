import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import 'package:uuid/uuid.dart';
import 'package:image/image.dart' as img;
import '../models/message.dart';
import 'encryption_service.dart';
import 'attachment_cache_service.dart';

class AttachmentService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _imagePicker = ImagePicker();
  final Uuid _uuid = const Uuid();
  final EncryptionService encryptionService;
  final AttachmentCacheService _cacheService = AttachmentCacheService();

  AttachmentService({required this.encryptionService}) {
    _cacheService.initialize();
  }

  /// Seleziona una foto dalla galleria
  Future<File?> pickImageFromGallery() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 4096,  // Qualità stampa
        maxHeight: 4096, // Qualità stampa
        imageQuality: 95, // Alta qualità per stampa
      );

      if (image != null) {
        return File(image.path);
      }
      return null;
    } catch (e) {
      if (kDebugMode) print('❌ Error picking image: $e');
      return null;
    }
  }

  /// Seleziona una foto dalla fotocamera
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
    } catch (e) {
      if (kDebugMode) print('❌ Error taking photo: $e');
      return null;
    }
  }

  /// Seleziona un video dalla galleria
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
    } catch (e) {
      if (kDebugMode) print('❌ Error picking video: $e');
      return null;
    }
  }

  /// Seleziona un video dalla fotocamera
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

  /// Genera thumbnail da immagine (300px lato più lungo, qualità 90)
  Future<Uint8List?> _generateThumbnail(Uint8List imageBytes) async {
    try {
      // Decodifica immagine
      final image = img.decodeImage(imageBytes);
      if (image == null) return null;

      // Ridimensiona mantenendo aspect ratio (300px per qualità migliore)
      final thumbnail = img.copyResize(
        image,
        width: image.width > image.height ? 300 : null,
        height: image.height > image.width ? 300 : null,
      );

      // Encode come JPEG con qualità 90 per migliore visualizzazione
      final thumbnailBytes = img.encodeJpg(thumbnail, quality: 90);

      if (kDebugMode) {
        print('📐 Generated thumbnail:');
        print('   Original: ${(imageBytes.length / 1024).toStringAsFixed(1)} KB');
        print('   Thumbnail: ${(thumbnailBytes.length / 1024).toStringAsFixed(1)} KB');
      }

      return Uint8List.fromList(thumbnailBytes);
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

      // 🔐 CIFRA IL FILE con dual encryption
      final encryptedData = encryptionService.encryptFileDual(
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

      // 🖼️ GENERA E CARICA THUMBNAIL (solo per foto)
      String? thumbnailUrl;
      if (attachmentType == 'photo') {
        if (kDebugMode) print('📐 Generating thumbnail for photo...');

        final Uint8List? thumbnailBytes = await _generateThumbnail(fileBytes);

        if (thumbnailBytes != null) {
          // Cifra il thumbnail con le STESSE chiavi AES e IV del full image
          final Uint8List encryptedThumbnailBytes = encryptionService.encryptFileWithExistingKey(
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
        }
      }

      // Crea l'oggetto Attachment con metadata di cifratura
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
    } catch (e) {
      if (kDebugMode) print('❌ Error uploading encrypted attachment: $e');
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

      // Se richiesta thumbnail ma non esiste, usa full image
      final url = (useThumbnail && attachment.thumbnailUrl != null)
          ? attachment.thumbnailUrl!
          : attachment.url;

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
        return null;
      }

      if (kDebugMode) {
        print('✅ Encrypted file downloaded');
        print('   Size: ${(encryptedBytes.length / 1024 / 1024).toStringAsFixed(2)} MB');
        print('🔓 Decrypting file...');
      }

      // 🎯 OPTIMISTIC UI: Se encryption metadata mancante, è un pending attachment
      // (questo non dovrebbe succedere perché pending usa localPath, ma meglio verificare)
      if (attachment.encryptedKeySender == null ||
          attachment.encryptedKeyRecipient == null ||
          attachment.iv == null) {
        if (kDebugMode) {
          print('⚠️ Attachment missing encryption metadata (pending?), cannot decrypt');
        }
        return null;
      }

      // Determina quale chiave usare: se sono il sender uso encryptedKeySender, altrimenti encryptedKeyRecipient
      final String encryptedAesKey = (currentUserId == messageSenderId)
          ? attachment.encryptedKeySender!
          : attachment.encryptedKeyRecipient!;

      if (kDebugMode) {
        print('   Using ${currentUserId == messageSenderId ? "sender" : "recipient"} key for decryption');
      }

      // Decifra il file usando la propria chiave privata
      final Uint8List decryptedBytes = encryptionService.decryptFile(
        encryptedBytes,
        encryptedAesKey,
        attachment.iv!,
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

      return decryptedBytes;
    } catch (e) {
      if (kDebugMode) print('❌ Error downloading/decrypting attachment: $e');
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
