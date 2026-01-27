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

  /// Estrae URL dal testo (anche se c'è altro testo prima/dopo)
  List<String> extractUrls(String text) {
    final urls = <String>[];

    // Regex per URL con protocollo
    final urlWithProtocol = RegExp(
      r'https?://[^\s]+',
      caseSensitive: false,
    );

    // Cerca tutti gli URL con protocollo
    for (final match in urlWithProtocol.allMatches(text)) {
      urls.add(match.group(0)!);
    }

    return urls;
  }

  /// Verifica se il testo contiene esattamente un URL
  bool hasUrl(String text) {
    return extractUrls(text).isNotEmpty;
  }

  /// Abbrevia URL nel testo mostrando dominio + primi 10 caratteri del path
  String shortenUrlsInText(String text) {
    final urls = extractUrls(text);

    String result = text;
    for (final url in urls) {
      final shortened = shortenUrl(url);
      result = result.replaceFirst(url, shortened);
    }

    return result;
  }

  /// Abbrevia un singolo URL
  String shortenUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final domain = uri.host.replaceFirst('www.', '');

      // Path senza query parameters
      String path = uri.path;

      // Se il path è vuoto o solo "/", mostra solo il dominio
      if (path.isEmpty || path == '/') {
        return '${uri.scheme}://$domain';
      }

      // Rimuovi lo slash iniziale
      if (path.startsWith('/')) {
        path = path.substring(1);
      }

      // Mostra dominio + primi 10 caratteri del path
      const maxPathChars = 10;
      if (path.length > maxPathChars) {
        path = '${path.substring(0, maxPathChars)}...';
      }

      return '${uri.scheme}://$domain/$path';
    } catch (e) {
      // Se non riusciamo a parsare, tronca semplicemente
      if (url.length > 40) {
        return '${url.substring(0, 40)}...';
      }
      return url;
    }
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
        print('🔍 [METADATA] Fetching from: $normalizedUrl');
      }

      // Usa WhatsApp User-Agent - molti siti lo permettono per generare preview
      final response = await http.get(
        Uri.parse(normalizedUrl),
        headers: {
          'User-Agent': 'WhatsApp/2.23.20.0 A',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.9,it;q=0.8',
        },
      ).timeout(const Duration(seconds: 10));

      if (kDebugMode) {
        print('📡 [METADATA] Response status: ${response.statusCode}');
      }

      if (response.statusCode != 200) {
        if (kDebugMode) {
          print('❌ [METADATA] Failed with status: ${response.statusCode}');
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
        print('✅ [METADATA] Successfully parsed: title="${metadata.title}", hasImage=${metadata.imageUrl != null}');
      }

      return metadata;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('❌ [METADATA] Error fetching metadata: $e');
        print('❌ [METADATA] Stack trace: ${stackTrace.toString().split('\n').take(3).join('\n')}');
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

  /// Ottiene il favicon del sito usando Google favicon service
  Future<File?> downloadFavicon(String url) async {
    try {
      final uri = Uri.parse(normalizeUrl(url));
      final domain = uri.host;

      // Usa il servizio Google per i favicon (size 128x128)
      final faviconUrl = 'https://www.google.com/s2/favicons?domain=$domain&sz=128';

      if (kDebugMode) {
        print('🌐 Downloading favicon from: $faviconUrl');
      }

      final response = await http.get(
        Uri.parse(faviconUrl),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        if (kDebugMode) {
          print('❌ Failed to download favicon: ${response.statusCode}');
        }
        return null;
      }

      // Salva il favicon
      final tempDir = await getTemporaryDirectory();
      final sharedDir = Directory('${tempDir.path}/shared_media');
      if (!await sharedDir.exists()) {
        await sharedDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'favicon_$timestamp.png';
      final file = File('${sharedDir.path}/$fileName');

      await file.writeAsBytes(response.bodyBytes);

      if (kDebugMode) {
        print('✅ Favicon downloaded: ${file.path}');
      }

      return file;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error downloading favicon: $e');
      }
      return null;
    }
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
          'User-Agent': 'WhatsApp/2.23.20.0 A',
          'Accept': 'image/webp,image/apng,image/*,*/*;q=0.8',
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

  /// Processo completo: fetch metadata + download immagine (con fallback a favicon)
  Future<({LinkMetadata? metadata, File? imageFile})> fetchLinkPreview(String url) async {
    if (kDebugMode) {
      print('🌐 [PREVIEW] Starting fetchLinkPreview for: $url');
    }

    final metadata = await fetchMetadata(url);

    if (metadata == null) {
      if (kDebugMode) {
        print('❌ [PREVIEW] Failed to fetch metadata, returning null');
      }
      return (metadata: null, imageFile: null);
    }

    if (kDebugMode) {
      print('✅ [PREVIEW] Metadata fetched: title="${metadata.title}", imageUrl="${metadata.imageUrl}"');
    }

    File? imageFile;

    // Prova a scaricare l'immagine di preview se disponibile
    if (metadata.imageUrl != null) {
      if (kDebugMode) {
        print('📥 [PREVIEW] Attempting to download preview image...');
      }
      imageFile = await downloadPreviewImage(metadata.imageUrl!);

      if (imageFile != null) {
        if (kDebugMode) {
          print('✅ [PREVIEW] Preview image downloaded successfully');
        }
      } else {
        if (kDebugMode) {
          print('⚠️ [PREVIEW] Preview image download failed');
        }
      }
    } else {
      if (kDebugMode) {
        print('⚠️ [PREVIEW] No preview image URL in metadata');
      }
    }

    // Se non c'è immagine o il download è fallito, usa il favicon come fallback
    if (imageFile == null) {
      if (kDebugMode) {
        print('🔄 [PREVIEW] Falling back to favicon...');
      }
      imageFile = await downloadFavicon(url);

      if (imageFile != null) {
        if (kDebugMode) {
          print('✅ [PREVIEW] Favicon downloaded successfully');
        }
      } else {
        if (kDebugMode) {
          print('❌ [PREVIEW] Favicon download also failed, no image available');
        }
      }
    }

    return (metadata: metadata, imageFile: imageFile);
  }
}
