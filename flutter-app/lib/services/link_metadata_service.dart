import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;

/// Metadata estratti da un link
class LinkMetadata {
  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;

  LinkMetadata({
    required this.url,
    this.title,
    this.description,
    this.imageUrl,
  });

  @override
  String toString() {
    return 'LinkMetadata(url: $url, title: $title, description: $description, imageUrl: $imageUrl)';
  }
}

/// Servizio per recuperare metadata e immagini di preview da link
class LinkMetadataService {
  static final LinkMetadataService _instance = LinkMetadataService._internal();
  factory LinkMetadataService() => _instance;
  LinkMetadataService._internal();

  /// Verifica se il testo è un URL valido
  bool isUrl(String text) {
    final trimmed = text.trim();

    // Regex per URL con protocollo
    final urlWithProtocol = RegExp(
      r'^https?://',
      caseSensitive: false,
    );

    // Regex per dominio senza protocollo
    final domainPattern = RegExp(
      r'^([a-zA-Z0-9][-a-zA-Z0-9]{0,62}\.)+[a-zA-Z]{2,6}(/.*)?$',
    );

    return urlWithProtocol.hasMatch(trimmed) || domainPattern.hasMatch(trimmed);
  }

  /// Normalizza URL aggiungendo https:// se mancante
  String normalizeUrl(String url) {
    final trimmed = url.trim();
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      return 'https://$trimmed';
    }
    return trimmed;
  }

  /// Recupera metadata da un URL
  Future<LinkMetadata?> fetchMetadata(String url) async {
    try {
      final normalizedUrl = normalizeUrl(url);

      if (kDebugMode) {
        print('🔍 Fetching metadata from: $normalizedUrl');
      }

      final response = await http.get(
        Uri.parse(normalizedUrl),
        headers: {
          'User-Agent': 'Mozilla/5.0 (compatible; TuyjoBot/1.0)',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        if (kDebugMode) {
          print('❌ Failed to fetch URL: ${response.statusCode}');
        }
        return null;
      }

      // Parse HTML
      final document = html_parser.parse(response.body);

      // Estrai metadata Open Graph
      String? title = _getMetaContent(document, 'og:title') ??
                      _getMetaContent(document, 'twitter:title') ??
                      document.querySelector('title')?.text;

      String? description = _getMetaContent(document, 'og:description') ??
                            _getMetaContent(document, 'twitter:description') ??
                            _getMetaContent(document, 'description');

      String? imageUrl = _getMetaContent(document, 'og:image') ??
                         _getMetaContent(document, 'twitter:image');

      // Rendi l'URL dell'immagine assoluto se relativo
      if (imageUrl != null && !imageUrl.startsWith('http')) {
        final uri = Uri.parse(normalizedUrl);
        if (imageUrl.startsWith('//')) {
          imageUrl = '${uri.scheme}:$imageUrl';
        } else if (imageUrl.startsWith('/')) {
          imageUrl = '${uri.scheme}://${uri.host}$imageUrl';
        } else {
          imageUrl = '${uri.scheme}://${uri.host}/${imageUrl}';
        }
      }

      final metadata = LinkMetadata(
        url: normalizedUrl,
        title: title?.trim(),
        description: description?.trim(),
        imageUrl: imageUrl,
      );

      if (kDebugMode) {
        print('✅ Metadata fetched: $metadata');
      }

      return metadata;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error fetching metadata: $e');
      }
      return null;
    }
  }

  /// Estrae contenuto di meta tag
  String? _getMetaContent(dom.Document document, String property) {
    // Cerca meta tag con property
    var meta = document.querySelector('meta[property="$property"]');
    if (meta != null) {
      return meta.attributes['content'];
    }

    // Cerca meta tag con name
    meta = document.querySelector('meta[name="$property"]');
    if (meta != null) {
      return meta.attributes['content'];
    }

    return null;
  }

  /// Scarica l'immagine di preview e la salva in un file temporaneo
  Future<File?> downloadPreviewImage(String imageUrl) async {
    try {
      if (kDebugMode) {
        print('📥 Downloading preview image: $imageUrl');
      }

      final response = await http.get(
        Uri.parse(imageUrl),
        headers: {
          'User-Agent': 'Mozilla/5.0 (compatible; TuyjoBot/1.0)',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        if (kDebugMode) {
          print('❌ Failed to download image: ${response.statusCode}');
        }
        return null;
      }

      // Determina l'estensione dal content-type
      String extension = 'jpg';
      final contentType = response.headers['content-type'];
      if (contentType != null) {
        if (contentType.contains('png')) {
          extension = 'png';
        } else if (contentType.contains('gif')) {
          extension = 'gif';
        } else if (contentType.contains('webp')) {
          extension = 'webp';
        }
      }

      // Crea file temporaneo
      final tempDir = await getTemporaryDirectory();
      final sharedDir = Directory('${tempDir.path}/shared_media');
      if (!await sharedDir.exists()) {
        await sharedDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'link_preview_$timestamp.$extension';
      final file = File('${sharedDir.path}/$fileName');

      // Scrivi i bytes
      await file.writeAsBytes(response.bodyBytes);

      if (kDebugMode) {
        print('✅ Preview image downloaded: ${file.path}');
        print('   Size: ${(response.bodyBytes.length / 1024).toStringAsFixed(1)} KB');
      }

      return file;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error downloading preview image: $e');
      }
      return null;
    }
  }

  /// Processo completo: fetch metadata + download immagine
  Future<({LinkMetadata? metadata, File? imageFile})> fetchLinkPreview(String url) async {
    final metadata = await fetchMetadata(url);

    if (metadata == null) {
      return (metadata: null, imageFile: null);
    }

    File? imageFile;
    if (metadata.imageUrl != null) {
      imageFile = await downloadPreviewImage(metadata.imageUrl!);
    }

    return (metadata: metadata, imageFile: imageFile);
  }
}
