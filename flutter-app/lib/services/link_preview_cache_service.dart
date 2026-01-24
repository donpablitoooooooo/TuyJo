import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_link_previewer/flutter_link_previewer.dart';

/// Servizio per cache locale dei metadati delle link preview
class LinkPreviewCacheService {
  static final LinkPreviewCacheService _instance = LinkPreviewCacheService._internal();
  factory LinkPreviewCacheService() => _instance;
  LinkPreviewCacheService._internal();

  static const String _cachePrefix = 'link_preview_';

  /// Salva i dati della preview in cache
  Future<void> savePreviewData(String url, PreviewData data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _getCacheKey(url);

      // Serializza i dati della preview
      final jsonData = {
        'title': data.title,
        'description': data.description,
        'image': data.image?.url,
        'link': data.link,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      await prefs.setString(cacheKey, jsonEncode(jsonData));

      if (kDebugMode) {
        print('💾 Cached link preview: $url');
        print('   Title: ${data.title}');
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error caching link preview: $e');
    }
  }

  /// Carica i dati della preview dalla cache
  Future<PreviewData?> loadPreviewData(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _getCacheKey(url);

      final jsonString = prefs.getString(cacheKey);
      if (jsonString == null) return null;

      final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;

      // Ricostruisci PreviewData
      final previewData = PreviewData(
        title: jsonData['title'] as String?,
        description: jsonData['description'] as String?,
        image: jsonData['image'] != null
            ? PreviewDataImage(link: jsonData['image'] as String)
            : null,
        link: jsonData['link'] as String?,
      );

      if (kDebugMode) {
        print('⚡ Loaded link preview from cache: $url');
        print('   Title: ${previewData.title}');
      }

      return previewData;
    } catch (e) {
      if (kDebugMode) print('❌ Error loading link preview from cache: $e');
      return null;
    }
  }

  /// Verifica se esiste una preview in cache
  Future<bool> hasPreviewData(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _getCacheKey(url);
      return prefs.containsKey(cacheKey);
    } catch (e) {
      return false;
    }
  }

  /// Genera chiave cache dall'URL
  String _getCacheKey(String url) {
    // Normalizza URL (rimuovi trailing slash, lowercase)
    final normalized = url.trim().toLowerCase().replaceAll(RegExp(r'/$'), '');
    return '$_cachePrefix${normalized.hashCode}';
  }

  /// Pulisce cache più vecchia di X giorni
  Future<void> clearOldCache({int daysOld = 30}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(_cachePrefix));
      final now = DateTime.now().millisecondsSinceEpoch;
      int deletedCount = 0;

      for (final key in keys) {
        final jsonString = prefs.getString(key);
        if (jsonString != null) {
          try {
            final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;
            final timestamp = jsonData['timestamp'] as int?;

            if (timestamp != null) {
              final age = Duration(milliseconds: now - timestamp).inDays;
              if (age > daysOld) {
                await prefs.remove(key);
                deletedCount++;
              }
            }
          } catch (e) {
            // Se non riesce a parsare, elimina
            await prefs.remove(key);
            deletedCount++;
          }
        }
      }

      if (kDebugMode && deletedCount > 0) {
        print('🧹 Cleaned $deletedCount old link preview cache entries');
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error cleaning link preview cache: $e');
    }
  }
}
