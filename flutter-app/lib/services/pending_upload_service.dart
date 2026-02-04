import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'attachment_service.dart';
import 'chat_service.dart';

/// Pending file upload queued because Firebase Storage was offline.
/// The text message was already sent to Firestore; these are just the files
/// that need uploading + sending as a follow-up attachment message.
class PendingUpload {
  final String id;
  final String familyChatId;
  final String senderId;
  final List<String> filePaths;
  final String senderPublicKey;
  final String recipientPublicKey;
  final DateTime createdAt;

  PendingUpload({
    required this.id,
    required this.familyChatId,
    required this.senderId,
    required this.filePaths,
    required this.senderPublicKey,
    required this.recipientPublicKey,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'familyChatId': familyChatId,
    'senderId': senderId,
    'filePaths': filePaths,
    'senderPublicKey': senderPublicKey,
    'recipientPublicKey': recipientPublicKey,
    'createdAt': createdAt.toIso8601String(),
  };

  factory PendingUpload.fromJson(Map<String, dynamic> json) => PendingUpload(
    id: json['id'] ?? '',
    familyChatId: json['familyChatId'] ?? '',
    senderId: json['senderId'] ?? '',
    filePaths: List<String>.from(json['filePaths'] ?? []),
    senderPublicKey: json['senderPublicKey'] ?? '',
    recipientPublicKey: json['recipientPublicKey'] ?? '',
    createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
  );
}

/// Coda per file che non sono riusciti a caricarsi su Firebase Storage (offline).
/// Il messaggio di testo è già su Firestore; qui ci sono solo i file da uploadare
/// e mandare come messaggio di follow-up quando si torna online.
class PendingUploadService {
  static const String _prefsKey = 'pending_uploads';

  Future<Directory> _getPendingDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final pendingDir = Directory(p.join(appDir.path, 'pending_uploads'));
    if (!pendingDir.existsSync()) {
      pendingDir.createSync(recursive: true);
    }
    return pendingDir;
  }

  Future<String> _copyFileToPending(String sourcePath) async {
    final pendingDir = await _getPendingDir();
    final fileName = p.basename(sourcePath);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final destPath = p.join(pendingDir.path, '${timestamp}_$fileName');

    final sourceFile = File(sourcePath);
    if (await sourceFile.exists()) {
      await sourceFile.copy(destPath);
      return destPath;
    }
    return sourcePath;
  }

  /// Copia i file in una cartella permanente (quelli temporanei possono sparire)
  Future<List<String>> copyFilesToPending(List<String> sourcePaths) async {
    final permanentPaths = <String>[];
    for (final srcPath in sourcePaths) {
      final permanentPath = await _copyFileToPending(srcPath);
      permanentPaths.add(permanentPath);
    }
    return permanentPaths;
  }

  Future<void> addPendingUpload(PendingUpload upload) async {
    final prefs = await SharedPreferences.getInstance();
    final uploads = await getPendingUploads();
    uploads.add(upload);
    await prefs.setString(
      _prefsKey,
      json.encode(uploads.map((u) => u.toJson()).toList()),
    );
    if (kDebugMode) {
      print('💾 [PENDING] Queued ${upload.filePaths.length} files for later upload');
    }
  }

  Future<List<PendingUpload>> getPendingUploads() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_prefsKey);
    if (jsonString == null) return [];
    try {
      final List<dynamic> list = json.decode(jsonString);
      return list.map((item) => PendingUpload.fromJson(item)).toList();
    } catch (e) {
      if (kDebugMode) print('❌ [PENDING] Error parsing: $e');
      return [];
    }
  }

  Future<List<PendingUpload>> getPendingUploadsForFamily(String familyChatId) async {
    final uploads = await getPendingUploads();
    return uploads.where((u) => u.familyChatId == familyChatId).toList();
  }

  Future<void> removePendingUpload(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final uploads = await getPendingUploads();
    uploads.removeWhere((u) => u.id == id);
    await prefs.setString(
      _prefsKey,
      json.encode(uploads.map((u) => u.toJson()).toList()),
    );
  }

  Future<void> _cleanupFiles(PendingUpload upload) async {
    for (final filePath in upload.filePaths) {
      try {
        final file = File(filePath);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  /// Prova a uploadare i file in coda e mandarli come nuovi messaggi.
  Future<int> processPendingUploads({
    required String familyChatId,
    required AttachmentService attachmentService,
    required ChatService chatService,
  }) async {
    final pendingUploads = await getPendingUploadsForFamily(familyChatId);
    if (pendingUploads.isEmpty) return 0;

    if (kDebugMode) {
      print('🔄 [PENDING] Processing ${pendingUploads.length} pending uploads...');
    }

    int successCount = 0;

    for (final upload in pendingUploads) {
      try {
        final files = upload.filePaths.map((fp) => File(fp)).toList();

        // Controlla che i file esistano ancora
        bool allExist = true;
        for (final file in files) {
          if (!await file.exists()) {
            allExist = false;
            break;
          }
        }

        if (!allExist) {
          if (kDebugMode) print('⚠️ [PENDING] Files missing for ${upload.id}, removing');
          await _cleanupFiles(upload);
          await removePendingUpload(upload.id);
          continue;
        }

        // Upload su Firebase Storage
        final uploadedAttachments = await attachmentService.uploadMultipleAttachments(
          files,
          upload.familyChatId,
          upload.senderId,
          upload.senderPublicKey,
          upload.recipientPublicKey,
        );

        if (uploadedAttachments.isNotEmpty) {
          // Upload riuscito! Manda come nuovo messaggio con gli allegati
          final messageId = await chatService.sendMessage(
            '',
            upload.familyChatId,
            upload.senderId,
            upload.senderPublicKey,
            upload.recipientPublicKey,
            attachments: uploadedAttachments,
          );

          if (messageId != null) {
            await _cleanupFiles(upload);
            await removePendingUpload(upload.id);
            successCount++;
            if (kDebugMode) print('✅ [PENDING] Upload ${upload.id} sent successfully');
          }
        }
      } catch (e) {
        if (kDebugMode) print('❌ [PENDING] Upload ${upload.id} still failing: $e');
        // Rimane in coda per il prossimo tentativo
      }
    }

    if (kDebugMode && pendingUploads.isNotEmpty) {
      print('🔄 [PENDING] Processed $successCount/${pendingUploads.length}');
    }

    return successCount;
  }
}
