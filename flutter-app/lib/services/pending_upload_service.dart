import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'attachment_service.dart';
import 'chat_service.dart';

/// Messaggio con allegati in attesa di upload su Firebase Storage.
/// Il messaggio NON viene inviato a Firestore finché l'upload non è completo.
/// Quando si torna online: upload file → invia messaggio completo a Firestore.
class PendingUpload {
  final String id;
  final String messageId; // ID pre-generato per il messaggio Firestore
  final String familyChatId;
  final String senderId;
  final List<String> filePaths;
  final String senderPublicKey;
  final String recipientPublicKey;
  final DateTime createdAt;
  final String messageText; // Testo del messaggio da inviare con gli allegati

  PendingUpload({
    required this.id,
    required this.messageId,
    required this.familyChatId,
    required this.senderId,
    required this.filePaths,
    required this.senderPublicKey,
    required this.recipientPublicKey,
    required this.createdAt,
    this.messageText = '',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'messageId': messageId,
    'familyChatId': familyChatId,
    'senderId': senderId,
    'filePaths': filePaths,
    'senderPublicKey': senderPublicKey,
    'recipientPublicKey': recipientPublicKey,
    'createdAt': createdAt.toIso8601String(),
    'messageText': messageText,
  };

  factory PendingUpload.fromJson(Map<String, dynamic> json) => PendingUpload(
    id: json['id'] ?? '',
    messageId: json['messageId'] ?? '',
    familyChatId: json['familyChatId'] ?? '',
    senderId: json['senderId'] ?? '',
    filePaths: List<String>.from(json['filePaths'] ?? []),
    senderPublicKey: json['senderPublicKey'] ?? '',
    recipientPublicKey: json['recipientPublicKey'] ?? '',
    createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
    messageText: json['messageText'] ?? '',
  );
}

/// Coda per messaggi con allegati che non sono riusciti a caricarsi (offline).
/// Il messaggio NON è ancora su Firestore. Quando si torna online:
/// upload file → sendMessage completo → ricevente vede tutto insieme.
///
/// Usa persistenza su file (non SharedPreferences) perché SharedPreferences
/// su Android usa apply() che è asincrono e può perdere dati se l'app viene
/// killata prima che il commit su disco sia completato.
class PendingUploadService {
  static const String _fileName = 'pending_uploads.json';
  static const String _diagFileName = 'pending_uploads_diag.log';

  Future<Directory> _getPendingDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final pendingDir = Directory(p.join(appDir.path, 'pending_uploads'));
    if (!pendingDir.existsSync()) {
      pendingDir.createSync(recursive: true);
    }
    return pendingDir;
  }

  /// File JSON che contiene la lista di pending uploads.
  /// Scritto con flush: true per garantire persistenza su disco.
  Future<File> _getQueueFile() async {
    final appDir = await getApplicationDocumentsDirectory();
    return File(p.join(appDir.path, _fileName));
  }

  /// Scrive la lista su file con flush sincrono su disco.
  Future<void> _writeQueue(List<PendingUpload> uploads) async {
    final file = await _getQueueFile();
    final jsonString = json.encode(uploads.map((u) => u.toJson()).toList());
    await file.writeAsString(jsonString, flush: true);
  }

  /// Log diagnostico su file (sopravvive a kill app).
  /// Al prossimo avvio, printPreviousSessionDiag() lo stampa e lo cancella.
  Future<void> logDiag(String message) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final file = File(p.join(appDir.path, _diagFileName));
      final timestamp = DateTime.now().toIso8601String();
      await file.writeAsString(
        '[$timestamp] $message\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {}
  }

  /// Stampa e cancella il log diagnostico della sessione precedente.
  /// Chiamare all'avvio dell'app.
  Future<void> printPreviousSessionDiag() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final file = File(p.join(appDir.path, _diagFileName));
      final exists = await file.exists();

      if (kDebugMode) {
        print('═══════════════════════════════════════════');
        print('📜 PREVIOUS SESSION DIAGNOSTIC LOG:');
        if (!exists) {
          print('   (diag file does not exist - no log from previous session)');
        } else {
          final content = await file.readAsString();
          if (content.isEmpty) {
            print('   (diag file exists but is EMPTY - previous session wrote nothing)');
          } else {
            print(content);
          }
          // Cancella per la prossima sessione
          await file.writeAsString('', flush: true);
        }
        print('═══════════════════════════════════════════');
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error reading previous diag log: $e');
    }
  }

  /// Stampa lo stato del file della coda all'avvio (per debug).
  /// Mostra se il file esiste, la sua dimensione, e il contenuto grezzo.
  Future<void> printQueueFileStatus() async {
    try {
      final file = await _getQueueFile();
      final exists = await file.exists();
      if (kDebugMode) {
        if (!exists) {
          print('📋 [QUEUE] Queue file does NOT exist (no pending uploads)');
        } else {
          final content = await file.readAsString();
          final size = await file.length();
          print('📋 [QUEUE] Queue file: ${file.path}');
          print('📋 [QUEUE] Size: $size bytes, content empty: ${content.isEmpty}');
          if (content.isNotEmpty) {
            // Tronca se troppo lungo
            final preview = content.length > 500 ? '${content.substring(0, 500)}...' : content;
            print('📋 [QUEUE] Content: $preview');
          }
        }
      }

      // Controlla anche la directory dei file copiati
      final pendingDir = await _getPendingDir();
      final files = await pendingDir.list().toList();
      if (kDebugMode) {
        print('📋 [QUEUE] Pending files dir: ${pendingDir.path} (${files.length} files)');
        for (final f in files) {
          if (f is File) {
            final stat = await f.stat();
            print('   ${p.basename(f.path)} (${stat.size} bytes)');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) print('❌ [QUEUE] Error reading queue status: $e');
    }
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
    await logDiag('addPendingUpload START: id=${upload.id}, msgId=${upload.messageId}, files=${upload.filePaths.length}');

    final uploads = await getPendingUploads();
    uploads.add(upload);
    await _writeQueue(uploads);

    // Verifica read-back: rileggi immediatamente per confermare persistenza
    final verifyFile = await _getQueueFile();
    final verifyExists = await verifyFile.exists();
    final verifySize = verifyExists ? await verifyFile.length() : 0;

    // Verifica anche che i file copiati esistano
    for (final fp in upload.filePaths) {
      final exists = await File(fp).exists();
      await logDiag('  file: $fp (exists: $exists)');
    }

    await logDiag('addPendingUpload DONE: queueFile exists=$verifyExists, size=$verifySize bytes');

    if (kDebugMode) {
      print('💾 [PENDING] Queued ${upload.filePaths.length} files for message ${upload.messageId}');
      print('   File: ${verifyFile.path}, exists: $verifyExists, size: $verifySize');
    }
  }

  Future<List<PendingUpload>> getPendingUploads() async {
    try {
      final file = await _getQueueFile();
      if (!await file.exists()) return [];
      final jsonString = await file.readAsString();
      if (jsonString.isEmpty) return [];
      final List<dynamic> list = json.decode(jsonString);
      return list.map((item) => PendingUpload.fromJson(item)).toList();
    } catch (e) {
      if (kDebugMode) print('❌ [PENDING] Error reading queue file: $e');
      return [];
    }
  }

  Future<List<PendingUpload>> getPendingUploadsForFamily(String familyChatId) async {
    final uploads = await getPendingUploads();
    return uploads.where((u) => u.familyChatId == familyChatId).toList();
  }

  Future<void> removePendingUpload(String id) async {
    final uploads = await getPendingUploads();
    uploads.removeWhere((u) => u.id == id);
    await _writeQueue(uploads);
  }

  Future<void> _cleanupFiles(PendingUpload upload) async {
    for (final filePath in upload.filePaths) {
      try {
        final file = File(filePath);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  /// Prova a uploadare i file in coda e inviare il messaggio completo su Firestore.
  /// Il messaggio NON esiste ancora su Firestore: viene creato qui con gli allegati reali.
  ///
  /// [excludeIds] sono i PendingUpload.id attualmente già in carico dal path
  /// "diretto" (quello che parte al momento dell'invio). Saltando quegli id
  /// evitiamo di uploadare la stessa foto due volte in parallelo.
  Future<int> processPendingUploads({
    required String familyChatId,
    required AttachmentService attachmentService,
    required ChatService chatService,
    Set<String> excludeIds = const {},
  }) async {
    final allPending = await getPendingUploadsForFamily(familyChatId);
    final pendingUploads = excludeIds.isEmpty
        ? allPending
        : allPending.where((u) => !excludeIds.contains(u.id)).toList();
    if (pendingUploads.isEmpty) return 0;

    if (kDebugMode) {
      final skipped = allPending.length - pendingUploads.length;
      print('🔄 [PENDING] Processing ${pendingUploads.length} pending uploads...'
          '${skipped > 0 ? ' (skipped $skipped in-flight)' : ''}');
    }

    int successCount = 0;

    for (final upload in pendingUploads) {
      try {
        if (kDebugMode) {
          print('🔄 [PENDING] Processing upload ${upload.id} for pre-gen ID ${upload.messageId}');
        }
        await logDiag('PROCESS_PENDING START: id=${upload.id}, msgId=${upload.messageId}');

        final files = upload.filePaths.map((fp) => File(fp)).toList();

        // Controlla che i file esistano ancora
        bool allExist = true;
        for (final file in files) {
          if (!await file.exists()) {
            if (kDebugMode) print('⚠️ [PENDING] File missing: ${file.path}');
            allExist = false;
            break;
          }
        }

        if (!allExist) {
          if (kDebugMode) print('⚠️ [PENDING] Files missing for ${upload.id}, removing');
          await logDiag('PROCESS_PENDING SKIP: files missing');
          await _cleanupFiles(upload);
          await removePendingUpload(upload.id);
          continue;
        }

        // 1) Upload file su Firebase Storage
        if (kDebugMode) print('📤 [PENDING] Uploading ${files.length} files...');

        final uploadedAttachments = await attachmentService.uploadMultipleAttachments(
          files,
          upload.familyChatId,
          upload.senderId,
          upload.senderPublicKey,
          upload.recipientPublicKey,
        );

        await logDiag('PROCESS_PENDING UPLOAD: ${uploadedAttachments.length} attachments');
        if (kDebugMode) print('📤 [PENDING] Upload returned ${uploadedAttachments.length} attachments');

        if (uploadedAttachments.isNotEmpty) {
          // 2) Upload riuscito! Invia il messaggio COMPLETO su Firestore
          //    Il messaggio non esisteva ancora — lo creiamo ora con allegati reali.
          if (kDebugMode) print('📤 [PENDING] Sending complete message ${upload.messageId} with ${uploadedAttachments.length} real attachments...');

          final sentId = await chatService.sendMessage(
            upload.messageText,
            upload.familyChatId,
            upload.senderId,
            upload.senderPublicKey,
            upload.recipientPublicKey,
            attachments: uploadedAttachments,
            messageId: upload.messageId,
          );

          await logDiag('PROCESS_PENDING SENT: sentId=$sentId');

          if (sentId != null) {
            await _cleanupFiles(upload);
            await removePendingUpload(upload.id);
            successCount++;
            if (kDebugMode) print('✅ [PENDING] Sent complete message $sentId with ${uploadedAttachments.length} attachments');
          } else {
            if (kDebugMode) print('⚠️ [PENDING] sendMessage returned null for ${upload.messageId}');
          }
        } else {
          if (kDebugMode) print('⚠️ [PENDING] Upload returned empty list for ${upload.id}');
        }
      } catch (e) {
        await logDiag('PROCESS_PENDING EXCEPTION: $e');
        if (kDebugMode) print('❌ [PENDING] Upload ${upload.id} still failing: $e');
      }
    }

    if (kDebugMode && pendingUploads.isNotEmpty) {
      print('🔄 [PENDING] Processed $successCount/${pendingUploads.length}');
    }

    return successCount;
  }
}
