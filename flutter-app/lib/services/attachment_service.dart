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
        // 4096px mantiene risoluzione di stampa (fino a ~13x13" a 300 DPI).
        // q85 vs q95: ~40% meno byte, differenza visiva impercettibile anche
        // in stampa (gli artefatti JPEG compaiono sotto q70-75).
        maxWidth: 4096,
        maxHeight: 4096,
        imageQuality: 85,
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
        // Stessi parametri di pickImageFromGallery: 4096px per stampa,
        // q85 per upload veloci senza artefatti visibili.
        maxWidth: 4096,
        maxHeight: 4096,
        imageQuality: 85,
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
  ///
  /// Prima chiamavamo img.decodeImage sui bytes originali (fino a 20 MP di
  /// un Samsung/iPhone) → CPU al 100%, ~10-13s sul main o su isolate.
  ///
  /// Ora prima resize NATIVA a ~600x600 via FlutterImageCompress (decode+
  /// resize su thread nativo, ~100-200ms), POI center-crop pure-Dart su una
  /// sola 600×600 (trivial, <50ms su isolate), poi resize finale nativa.
  Future<Uint8List?> _generateThumbnail(Uint8List imageBytes) async {
    try {
      final stopwatch = Stopwatch()..start();

      // Step 1: NATIVE decode + resize a max 600px lato corto.
      // FlutterImageCompress usa libjpeg/libpng/native sul thread nativo.
      final Uint8List resized = await FlutterImageCompress.compressWithList(
        imageBytes,
        minWidth: 600,
        minHeight: 600,
        quality: 90,
        format: CompressFormat.jpeg,
        keepExif: false,
      );
      final nativeResizeMs = stopwatch.elapsedMilliseconds;

      // Step 2: center-crop su isolate. Lavoriamo su ~600×600, non più
      // sull'originale 20 MP: l'operazione è ora sub-50ms.
      final Uint8List? cropped = await compute(thumbnailCropEntry, resized);
      if (cropped == null) return null;
      final cropMs = stopwatch.elapsedMilliseconds - nativeResizeMs;

      // Step 3: resize finale 300x300 nativo (assicura dimensioni coerenti).
      final Uint8List thumbnailBytes = await FlutterImageCompress.compressWithList(
        cropped,
        minWidth: 300,
        minHeight: 300,
        quality: 85,
        format: CompressFormat.jpeg,
        keepExif: false,
      );
      final finalResizeMs = stopwatch.elapsedMilliseconds - nativeResizeMs - cropMs;
      stopwatch.stop();

      if (kDebugMode) {
        print('📐 Generated thumbnail:');
        print('   Original: ${(imageBytes.length / 1024).toStringAsFixed(1)} KB');
        print('   Thumbnail: ${(thumbnailBytes.length / 1024).toStringAsFixed(1)} KB');
        print('⏱ [TIMING] thumbnail gen: native-resize ${nativeResizeMs}ms + crop ${cropMs}ms + final-resize ${finalResizeMs}ms');
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

      // ═══════════════════════════════════════════════════════════════
      // PARALLELIZZAZIONE: il flusso serial era encrypt → upload full →
      // gen thumb → encrypt thumb → upload thumb. Qui facciamo:
      //
      //   [encrypt full]  ‖  [gen thumbnail]           <- isolate
      //          ↓                  ↓
      //   [upload full]   ‖  [encrypt thumb]→[upload thumb]
      //
      // Upload full e upload thumb girano in parallelo su Firebase. Sulla
      // chiamata tipica (~2-4 MB) si risparmia tutto il tempo di gen+
      // encrypt+upload del thumbnail (era in coda all'upload principale).
      // ═══════════════════════════════════════════════════════════════

      if (kDebugMode) print('🔐 Encrypting + generating thumbnail (parallel)...');

      // ⏱ TIMING: scandaglia ogni fase dell'upload così possiamo vedere
      // esattamente dove vanno i secondi (encrypt vs upload vs getDownloadURL).
      final totalStopwatch = Stopwatch()..start();
      final encryptStopwatch = Stopwatch()..start();

      // Phase 1: encrypt full file (AES-GCM nativo, zero isolate) e
      // generate thumbnail (compute() perché è Dart puro) in parallelo.
      // L'encrypt ora usa il plugin cryptography_flutter → AES hardware
      // Android/iOS, tipicamente <100ms per MB invece dei 1-4s di pointycastle.
      final encryptFuture = encryptionService.encryptFileDualGcm(
        fileBytes,
        senderPublicKey,
        recipientPublicKey,
      );
      final Future<Uint8List?> thumbnailGenFuture = (attachmentType == 'photo')
          ? _generateThumbnail(fileBytes)
          : Future<Uint8List?>.value(null);

      final encryptedData = await encryptFuture;
      final Uint8List encryptedFileBytes = encryptedData['encryptedFileBytes'] as Uint8List;
      final String encryptedKeyRecipient = encryptedData['encryptedKeyRecipient'] as String;
      final String encryptedKeySender = encryptedData['encryptedKeySender'] as String;
      final String iv = encryptedData['iv'] as String;
      final Uint8List aesKey = encryptedData['aesKey'] as Uint8List;
      final String encryptVersion = encryptedData['encryptVersion'] as String; // 'gcm-v1'
      encryptStopwatch.stop();

      if (kDebugMode) {
        print('✅ File encrypted successfully');
        print('   Encrypted size: ${(encryptedFileBytes.length / 1024 / 1024).toStringAsFixed(2)} MB');
        print('⏱ [TIMING] encrypt(parallel with thumb gen): ${encryptStopwatch.elapsedMilliseconds}ms');
      }

      // Phase 2: kick off full file upload subito (non aspetta il thumbnail).
      final String storagePath = 'families/$familyChatId/attachments/$attachmentType/$attachmentId';
      if (kDebugMode) {
        print('📤 Uploading encrypted file to Firebase Storage...');
        print('   Path: $storagePath');
      }

      final fullUploadStopwatch = Stopwatch()..start();
      final UploadTask fullUploadTask = _storage.ref().child(storagePath).putData(
        encryptedFileBytes,
        SettableMetadata(
          contentType: 'application/octet-stream',
          customMetadata: {
            'senderId': senderId,
            'originalFileName': fileName,
            'originalMimeType': mimeType ?? 'application/octet-stream',
            'encrypted': 'true',
          },
        ),
      );
      // Usiamo await in un helper invece di .then(): sull'UploadTask .then
      // sembra non far partire il callback in modo affidabile, perdiamo i
      // log di timing. Con await diretto è garantito.
      final fullSizeKB = (encryptedFileBytes.length / 1024).toStringAsFixed(0);
      final Future<String> fullDownloadUrlFuture = () async {
        final snapshot = await fullUploadTask;
        final uploadMs = fullUploadStopwatch.elapsedMilliseconds;
        final urlStopwatch = Stopwatch()..start();
        final url = await snapshot.ref.getDownloadURL();
        final urlMs = urlStopwatch.elapsedMilliseconds;
        fullUploadStopwatch.stop();
        if (kDebugMode) {
          print('✅ Encrypted attachment uploaded successfully');
          print('   URL: $url');
          print('⏱ [TIMING] full upload(${fullSizeKB}KB): ${uploadMs}ms + getDownloadURL: ${urlMs}ms');
        }
        return url;
      }();

      // Phase 3: aspetta il thumbnail (può essere già pronto), poi
      // avvia il suo upload IN PARALLELO con l'upload full.
      Future<String?> thumbnailUrlFuture = Future.value(null);
      Uint8List? thumbnailBytes;
      // GCM vieta nonce-reuse con la stessa chiave, quindi il thumbnail ha
      // un nonce suo (generato dentro encryptFileWithExistingKeyGcm).
      String? thumbnailIv;
      if (attachmentType == 'photo') {
        try {
          thumbnailBytes = await thumbnailGenFuture;
          if (thumbnailBytes != null) {
            final tBytes = thumbnailBytes;
            thumbnailUrlFuture = () async {
              final thumbStopwatch = Stopwatch()..start();
              final thumbEncryptResult = await encryptionService.encryptFileWithExistingKeyGcm(
                tBytes, aesKey,
              );
              final encryptedThumbnailBytes = thumbEncryptResult['encryptedFileBytes'] as Uint8List;
              thumbnailIv = thumbEncryptResult['iv'] as String;
              final thumbEncryptMs = thumbStopwatch.elapsedMilliseconds;
              final thumbnailPath = 'families/$familyChatId/attachments/$attachmentType/thumbnails/$attachmentId';
              if (kDebugMode) {
                print('📤 Uploading encrypted thumbnail (in parallel)...');
                print('   Path: $thumbnailPath');
              }
              final thumbUploadStart = thumbStopwatch.elapsedMilliseconds;
              final thumbTask = _storage.ref().child(thumbnailPath).putData(
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
              final snap = await thumbTask;
              final thumbUploadMs = thumbStopwatch.elapsedMilliseconds - thumbUploadStart;
              final thumbUrlStart = thumbStopwatch.elapsedMilliseconds;
              final url = await snap.ref.getDownloadURL();
              final thumbUrlMs = thumbStopwatch.elapsedMilliseconds - thumbUrlStart;
              thumbStopwatch.stop();
              if (kDebugMode) {
                print('✅ Thumbnail uploaded successfully');
                print('   URL: $url');
                print('⏱ [TIMING] thumb encrypt: ${thumbEncryptMs}ms + upload: ${thumbUploadMs}ms + getDownloadURL: ${thumbUrlMs}ms');
              }
              return url;
            }();
          }
        } catch (e) {
          if (kDebugMode) print('⚠️ Thumbnail gen failed (non-fatal): $e');
        }
      }

      // Phase 4: aspetta entrambi gli upload in parallelo.
      final String downloadUrl = await fullDownloadUrlFuture;
      String? thumbnailUrl;
      try {
        thumbnailUrl = await thumbnailUrlFuture;
      } catch (e) {
        if (kDebugMode) print('⚠️ Thumbnail upload failed (non-fatal): $e');
      }

      // 🚀 PRE-POPULATE CACHE per il receiver-side-equivalente (il Firestore
      // listener sulla stessa istanza che ora vedrà il messaggio arrivare).
      final cacheStopwatch = Stopwatch()..start();
      await _cacheService.saveToCache(attachmentId, fileBytes, isThumbnail: false);
      if (thumbnailBytes != null) {
        await _cacheService.saveToCache(attachmentId, thumbnailBytes, isThumbnail: true);
      }
      cacheStopwatch.stop();

      totalStopwatch.stop();

      // Crea l'oggetto Attachment con metadata di cifratura
      if (kDebugMode) {
        print('✅ [uploadAttachment] Returning Attachment: id=$attachmentId, url=${downloadUrl.length > 50 ? '${downloadUrl.substring(0, 50)}...' : downloadUrl}');
        print('⏱ [TIMING] ══════════════════════════════════════════');
        print('⏱ [TIMING] uploadAttachment TOTAL: ${totalStopwatch.elapsedMilliseconds}ms');
        print('⏱ [TIMING]   pre-populate cache: ${cacheStopwatch.elapsedMilliseconds}ms');
        print('⏱ [TIMING] ══════════════════════════════════════════');
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
        encryptVersion: encryptVersion, // 'gcm-v1' per tutti i nuovi file
        thumbnailIv: thumbnailIv,       // nonce separato del thumbnail (GCM)
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

      // Per GCM il thumbnail usa un nonce diverso dal full image. Gli
      // allegati vecchi (CBC) e il full image GCM usano il campo iv.
      final String ivToUse = (useThumbnail && attachment.thumbnailIv != null)
          ? attachment.thumbnailIv!
          : attachment.iv;

      // Route in base a encryptVersion:
      //   'gcm-v1' → decrypt AES-GCM nativo (veloce, ~<100ms/MB)
      //   null     → CBC legacy via pointycastle (slow path per file vecchi)
      final Uint8List decryptedBytes;
      if (attachment.encryptVersion == 'gcm-v1') {
        decryptedBytes = await encryptionService.decryptFileGcm(
          encryptedBytes,
          encryptedAesKey,
          ivToUse,
        );
      } else {
        decryptedBytes = await encryptionService.decryptFileAsync(
          encryptedBytes,
          encryptedAesKey,
          ivToUse,
        );
      }

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
