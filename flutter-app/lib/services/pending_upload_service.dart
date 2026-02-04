import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'attachment_service.dart';
import 'chat_service.dart';
import 'location_service.dart';

/// Represents a pending upload that failed due to offline/network issues
class PendingUpload {
  final String id; // Same as the pending message tempId
  final String familyChatId;
  final String senderId;
  final String messageText;
  final List<String> filePaths; // Permanent copies of files to upload
  final String senderPublicKey;
  final String recipientPublicKey;
  final DateTime createdAt;
  final String type; // 'attachment' or 'location_share'
  final int? durationSeconds; // For location_share: duration in seconds

  PendingUpload({
    required this.id,
    required this.familyChatId,
    required this.senderId,
    required this.messageText,
    required this.filePaths,
    required this.senderPublicKey,
    required this.recipientPublicKey,
    required this.createdAt,
    required this.type,
    this.durationSeconds,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'familyChatId': familyChatId,
    'senderId': senderId,
    'messageText': messageText,
    'filePaths': filePaths,
    'senderPublicKey': senderPublicKey,
    'recipientPublicKey': recipientPublicKey,
    'createdAt': createdAt.toIso8601String(),
    'type': type,
    if (durationSeconds != null) 'durationSeconds': durationSeconds,
  };

  factory PendingUpload.fromJson(Map<String, dynamic> json) => PendingUpload(
    id: json['id'] ?? '',
    familyChatId: json['familyChatId'] ?? '',
    senderId: json['senderId'] ?? '',
    messageText: json['messageText'] ?? '',
    filePaths: List<String>.from(json['filePaths'] ?? []),
    senderPublicKey: json['senderPublicKey'] ?? '',
    recipientPublicKey: json['recipientPublicKey'] ?? '',
    createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
    type: json['type'] ?? 'attachment',
    durationSeconds: json['durationSeconds'],
  );
}

/// Service to manage pending uploads that failed due to offline/network issues.
/// Uses SharedPreferences for persistence and copies files to a permanent directory.
class PendingUploadService {
  static const String _prefsKey = 'pending_uploads';

  /// Get the permanent directory for pending files
  Future<Directory> _getPendingDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final pendingDir = Directory(p.join(appDir.path, 'pending_uploads'));
    if (!pendingDir.existsSync()) {
      pendingDir.createSync(recursive: true);
    }
    return pendingDir;
  }

  /// Copy a file to the permanent pending directory
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

  /// Copy files to permanent directory and return new paths
  Future<List<String>> copyFilesToPending(List<String> sourcePaths) async {
    final permanentPaths = <String>[];
    for (final path in sourcePaths) {
      final permanentPath = await _copyFileToPending(path);
      permanentPaths.add(permanentPath);
    }
    return permanentPaths;
  }

  /// Add a pending upload to the queue
  Future<void> addPendingUpload(PendingUpload upload) async {
    final prefs = await SharedPreferences.getInstance();
    final uploads = await getPendingUploads();
    uploads.add(upload);
    await prefs.setString(
      _prefsKey,
      json.encode(uploads.map((u) => u.toJson()).toList()),
    );

    if (kDebugMode) {
      print('💾 [PENDING] Added pending upload: ${upload.id} (${upload.type})');
      print('   Files: ${upload.filePaths.length}');
    }
  }

  /// Get all pending uploads
  Future<List<PendingUpload>> getPendingUploads() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_prefsKey);
    if (jsonString == null) return [];

    try {
      final List<dynamic> list = json.decode(jsonString);
      return list.map((item) => PendingUpload.fromJson(item)).toList();
    } catch (e) {
      if (kDebugMode) print('❌ [PENDING] Error parsing pending uploads: $e');
      return [];
    }
  }

  /// Get pending uploads for a specific family
  Future<List<PendingUpload>> getPendingUploadsForFamily(String familyChatId) async {
    final uploads = await getPendingUploads();
    return uploads.where((u) => u.familyChatId == familyChatId).toList();
  }

  /// Remove a pending upload from the queue
  Future<void> removePendingUpload(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final uploads = await getPendingUploads();
    uploads.removeWhere((u) => u.id == id);
    await prefs.setString(
      _prefsKey,
      json.encode(uploads.map((u) => u.toJson()).toList()),
    );

    if (kDebugMode) {
      print('🗑️ [PENDING] Removed pending upload: $id');
    }
  }

  /// Clean up the files of a pending upload
  Future<void> cleanupFiles(PendingUpload upload) async {
    for (final filePath in upload.filePaths) {
      try {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        if (kDebugMode) print('⚠️ [PENDING] Error cleaning up file $filePath: $e');
      }
    }
  }

  /// Process all pending uploads for a family.
  /// Returns the number of successfully processed uploads.
  Future<int> processPendingUploads({
    required String familyChatId,
    required AttachmentService attachmentService,
    required ChatService chatService,
    required LocationService locationService,
  }) async {
    final pendingUploads = await getPendingUploadsForFamily(familyChatId);
    if (pendingUploads.isEmpty) return 0;

    if (kDebugMode) {
      print('🔄 [PENDING] Processing ${pendingUploads.length} pending uploads...');
    }

    int successCount = 0;

    for (final upload in pendingUploads) {
      try {
        if (upload.type == 'attachment') {
          // Retry attachment upload
          final files = upload.filePaths.map((filePath) => File(filePath)).toList();

          // Check all files still exist
          bool allExist = true;
          for (final file in files) {
            if (!await file.exists()) {
              allExist = false;
              break;
            }
          }

          if (!allExist) {
            if (kDebugMode) print('⚠️ [PENDING] Files missing for upload ${upload.id}, removing');
            await cleanupFiles(upload);
            await removePendingUpload(upload.id);
            chatService.removePendingMessage(upload.id);
            continue;
          }

          // Try uploading
          final uploadedAttachments = await attachmentService.uploadMultipleAttachments(
            files,
            upload.familyChatId,
            upload.senderId,
            upload.senderPublicKey,
            upload.recipientPublicKey,
          );

          if (uploadedAttachments.isNotEmpty) {
            // Upload succeeded! Now send the message
            final messageId = await chatService.sendMessage(
              upload.messageText,
              upload.familyChatId,
              upload.senderId,
              upload.senderPublicKey,
              upload.recipientPublicKey,
              attachments: uploadedAttachments,
            );

            if (messageId != null) {
              // Remove pending message and cleanup
              chatService.removePendingMessage(upload.id);
              await cleanupFiles(upload);
              await removePendingUpload(upload.id);
              successCount++;

              if (kDebugMode) {
                print('✅ [PENDING] Successfully processed upload ${upload.id}');
              }
            }
          }
        } else if (upload.type == 'location_share') {
          // Retry location share
          final duration = Duration(seconds: upload.durationSeconds ?? 3600);
          final success = await locationService.startSharingLocation(duration);

          if (success) {
            final expiresAt = DateTime.now().add(duration);
            final messageId = await chatService.sendLocationShare(
              expiresAt,
              locationService.currentSessionId!,
              upload.familyChatId,
              upload.senderId,
              upload.senderPublicKey,
              upload.recipientPublicKey,
            );

            if (messageId != null) {
              locationService.setLocationShareMessageId(messageId);
              chatService.removePendingMessage(upload.id);
              await removePendingUpload(upload.id);
              successCount++;

              if (kDebugMode) {
                print('✅ [PENDING] Successfully processed location share ${upload.id}');
              }
            }
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('❌ [PENDING] Failed to process upload ${upload.id}: $e');
        }
        // Leave it in the queue for next retry
      }
    }

    if (kDebugMode) {
      print('🔄 [PENDING] Processed $successCount/${pendingUploads.length} pending uploads');
    }

    return successCount;
  }
}
