import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

/// Servizio per cache locale di allegati decifrati
class AttachmentCacheService {
  static final AttachmentCacheService _instance = AttachmentCacheService._internal();
  factory AttachmentCacheService() => _instance;
  AttachmentCacheService._internal();

  Directory? _cacheDir;
  final Map<String, Uint8List> _memoryCache = {}; // Cache in memoria
  final Map<String, Completer<Uint8List?>> _pendingRequests = {}; // Deduplicazione richieste

  /// Inizializza la directory di cache
  Future<void> initialize() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _cacheDir = Directory('${appDir.path}/attachment_cache');

      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      }

      if (kDebugMode) print('✅ Attachment cache initialized: ${_cacheDir!.path}');
    } catch (e) {
      if (kDebugMode) print('❌ Error initializing attachment cache: $e');
    }
  }

  /// Genera chiave cache da attachment ID
  String _getCacheKey(String attachmentId, {bool isThumbnail = false}) {
    final suffix = isThumbnail ? '_thumb' : '_full';
    return md5.convert(utf8.encode(attachmentId + suffix)).toString();
  }

  /// Salva file decifrato in cache (memoria + disco)
  Future<void> saveToCache(
    String attachmentId,
    Uint8List decryptedBytes, {
    bool isThumbnail = false,
  }) async {
    try {
      final cacheKey = _getCacheKey(attachmentId, isThumbnail: isThumbnail);

      // Cache in memoria
      _memoryCache[cacheKey] = decryptedBytes;

      // Cache su disco
      if (_cacheDir != null) {
        final file = File('${_cacheDir!.path}/$cacheKey');
        await file.writeAsBytes(decryptedBytes);

        if (kDebugMode) {
          print('💾 Cached ${isThumbnail ? "thumbnail" : "full image"}: $attachmentId');
          print('   Size: ${(decryptedBytes.length / 1024).toStringAsFixed(1)} KB');
        }
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error saving to cache: $e');
    }
  }

  /// Carica file da cache (prima memoria, poi disco)
  Future<Uint8List?> loadFromCache(
    String attachmentId, {
    bool isThumbnail = false,
  }) async {
    try {
      final cacheKey = _getCacheKey(attachmentId, isThumbnail: isThumbnail);

      // Prova cache in memoria
      if (_memoryCache.containsKey(cacheKey)) {
        if (kDebugMode) print('⚡ Loaded from memory cache: $attachmentId');
        return _memoryCache[cacheKey];
      }

      // Prova cache su disco
      if (_cacheDir != null) {
        final file = File('${_cacheDir!.path}/$cacheKey');
        if (await file.exists()) {
          final bytes = await file.readAsBytes();

          // Salva anche in memoria per prossimi accessi
          _memoryCache[cacheKey] = bytes;

          if (kDebugMode) print('💽 Loaded from disk cache: $attachmentId');
          return bytes;
        }
      }

      return null;
    } catch (e) {
      if (kDebugMode) print('❌ Error loading from cache: $e');
      return null;
    }
  }

  /// Verifica se file è in cache
  Future<bool> isCached(
    String attachmentId, {
    bool isThumbnail = false,
  }) async {
    final cacheKey = _getCacheKey(attachmentId, isThumbnail: isThumbnail);

    // Memoria
    if (_memoryCache.containsKey(cacheKey)) return true;

    // Disco
    if (_cacheDir != null) {
      final file = File('${_cacheDir!.path}/$cacheKey');
      return await file.exists();
    }

    return false;
  }

  /// Elimina file dalla cache
  Future<void> removeFromCache(String attachmentId) async {
    try {
      // Rimuovi entrambe le versioni (full + thumb)
      for (final isThumbnail in [true, false]) {
        final cacheKey = _getCacheKey(attachmentId, isThumbnail: isThumbnail);

        // Memoria
        _memoryCache.remove(cacheKey);

        // Disco
        if (_cacheDir != null) {
          final file = File('${_cacheDir!.path}/$cacheKey');
          if (await file.exists()) {
            await file.delete();
          }
        }
      }

      if (kDebugMode) print('🗑️ Removed from cache: $attachmentId');
    } catch (e) {
      if (kDebugMode) print('❌ Error removing from cache: $e');
    }
  }

  /// Pulisce cache più vecchia di X giorni
  Future<void> clearOldCache({int daysOld = 30}) async {
    try {
      if (_cacheDir == null) return;

      final now = DateTime.now();
      final files = await _cacheDir!.list().toList();
      int deletedCount = 0;

      for (final file in files) {
        if (file is File) {
          final stat = await file.stat();
          final age = now.difference(stat.modified).inDays;

          if (age > daysOld) {
            await file.delete();
            deletedCount++;
          }
        }
      }

      // Pulisci anche memoria
      _memoryCache.clear();

      if (kDebugMode) print('🧹 Cleaned $deletedCount old cache files');
    } catch (e) {
      if (kDebugMode) print('❌ Error cleaning cache: $e');
    }
  }

  /// Ottieni dimensione totale cache
  Future<int> getCacheSize() async {
    try {
      if (_cacheDir == null) return 0;

      int totalSize = 0;
      final files = await _cacheDir!.list().toList();

      for (final file in files) {
        if (file is File) {
          final stat = await file.stat();
          totalSize += stat.size;
        }
      }

      return totalSize;
    } catch (e) {
      if (kDebugMode) print('❌ Error getting cache size: $e');
      return 0;
    }
  }

  /// Ottieni un Completer per richieste pendenti (evita download duplicati)
  Completer<Uint8List?>? getPendingRequest(String attachmentId, {bool isThumbnail = false}) {
    final cacheKey = _getCacheKey(attachmentId, isThumbnail: isThumbnail);
    return _pendingRequests[cacheKey];
  }

  /// Registra una richiesta pendente
  Completer<Uint8List?> registerPendingRequest(String attachmentId, {bool isThumbnail = false}) {
    final cacheKey = _getCacheKey(attachmentId, isThumbnail: isThumbnail);
    final completer = Completer<Uint8List?>();
    _pendingRequests[cacheKey] = completer;

    if (kDebugMode) {
      print('🔒 Registered pending request for: ${isThumbnail ? "thumbnail" : "full"} $attachmentId');
    }

    return completer;
  }

  /// Completa una richiesta pendente
  void completePendingRequest(String attachmentId, Uint8List? data, {bool isThumbnail = false}) {
    final cacheKey = _getCacheKey(attachmentId, isThumbnail: isThumbnail);
    final completer = _pendingRequests[cacheKey];

    if (completer != null && !completer.isCompleted) {
      completer.complete(data);
      _pendingRequests.remove(cacheKey);

      if (kDebugMode) {
        print('🔓 Completed pending request for: ${isThumbnail ? "thumbnail" : "full"} $attachmentId');
      }
    }
  }

  /// Gestisce errore in richiesta pendente
  void errorPendingRequest(String attachmentId, dynamic error, {bool isThumbnail = false}) {
    final cacheKey = _getCacheKey(attachmentId, isThumbnail: isThumbnail);
    final completer = _pendingRequests[cacheKey];

    if (completer != null && !completer.isCompleted) {
      completer.completeError(error);
      _pendingRequests.remove(cacheKey);

      if (kDebugMode) {
        print('❌ Error in pending request for: ${isThumbnail ? "thumbnail" : "full"} $attachmentId');
      }
    }
  }
}
