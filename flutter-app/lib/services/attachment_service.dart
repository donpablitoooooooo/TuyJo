import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import 'package:uuid/uuid.dart';
import '../models/message.dart';

class AttachmentService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _imagePicker = ImagePicker();
  final Uuid _uuid = const Uuid();

  /// Seleziona una foto dalla galleria
  Future<File?> pickImageFromGallery() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
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
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
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

  /// Carica un file su Firebase Storage e restituisce l'URL
  Future<Attachment?> uploadAttachment(
    File file,
    String familyChatId,
    String senderId,
  ) async {
    try {
      final String fileName = file.path.split('/').last;
      final String? mimeType = lookupMimeType(file.path);
      final int fileSize = await file.length();

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

      // Path su Firebase Storage: /families/{familyChatId}/attachments/{attachmentType}/{attachmentId}
      final String storagePath = 'families/$familyChatId/attachments/$attachmentType/$attachmentId';

      if (kDebugMode) {
        print('📤 Uploading attachment to Firebase Storage...');
        print('   File: $fileName');
        print('   Size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');
        print('   Type: $attachmentType');
        print('   Path: $storagePath');
      }

      // Upload del file
      final Reference ref = _storage.ref().child(storagePath);
      final UploadTask uploadTask = ref.putFile(
        file,
        SettableMetadata(
          contentType: mimeType,
          customMetadata: {
            'senderId': senderId,
            'originalFileName': fileName,
          },
        ),
      );

      // Attendi il completamento
      final TaskSnapshot snapshot = await uploadTask;

      // Ottieni l'URL di download
      final String downloadUrl = await snapshot.ref.getDownloadURL();

      if (kDebugMode) {
        print('✅ Attachment uploaded successfully');
        print('   URL: $downloadUrl');
      }

      // Crea l'oggetto Attachment
      return Attachment(
        id: attachmentId,
        type: attachmentType,
        url: downloadUrl,
        fileName: fileName,
        fileSize: fileSize,
        mimeType: mimeType,
      );
    } catch (e) {
      if (kDebugMode) print('❌ Error uploading attachment: $e');
      return null;
    }
  }

  /// Carica più allegati contemporaneamente
  Future<List<Attachment>> uploadMultipleAttachments(
    List<File> files,
    String familyChatId,
    String senderId,
  ) async {
    final List<Attachment> uploadedAttachments = [];

    for (final file in files) {
      final attachment = await uploadAttachment(file, familyChatId, senderId);
      if (attachment != null) {
        uploadedAttachments.add(attachment);
      }
    }

    return uploadedAttachments;
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
