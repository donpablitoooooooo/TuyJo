import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

/// Servizio per gestire la foto di coppia condivisa tra i due dispositivi
class CoupleSelfieService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  String? _selfieUrl;
  bool _isLoading = false;
  Uint8List? _cachedSelfieBytes; // Cache in memoria
  File? _cacheFile; // File cache su disco

  String? get selfieUrl => _selfieUrl;
  bool get isLoading => _isLoading;
  bool get hasSelfie => _selfieUrl != null && _selfieUrl!.isNotEmpty;
  Uint8List? get cachedSelfieBytes => _cachedSelfieBytes;

  /// Ottiene il file di cache per la foto di coppia
  Future<File> _getCacheFile() async {
    final appDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${appDir.path}/couple_selfie_cache');

    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    return File('${cacheDir.path}/couple_selfie.jpg');
  }

  /// Scarica la foto da URL e la salva in cache
  Future<void> _downloadAndCacheSelfie(String url) async {
    try {
      if (kDebugMode) print('📥 [COUPLE_SELFIE] Downloading selfie from URL...');

      // Scarica l'immagine
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;

        // Salva in memoria
        _cachedSelfieBytes = bytes;

        // Salva su disco
        _cacheFile = await _getCacheFile();
        await _cacheFile!.writeAsBytes(bytes);

        if (kDebugMode) {
          print('✅ [COUPLE_SELFIE] Selfie cached successfully');
          print('   Size: ${(bytes.length / 1024).toStringAsFixed(1)} KB');
        }
      } else {
        if (kDebugMode) print('❌ [COUPLE_SELFIE] Failed to download selfie: ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) print('❌ [COUPLE_SELFIE] Error downloading selfie: $e');
    }
  }

  /// Carica la foto dalla cache locale
  Future<void> _loadFromCache() async {
    try {
      _cacheFile = await _getCacheFile();

      if (await _cacheFile!.exists()) {
        _cachedSelfieBytes = await _cacheFile!.readAsBytes();

        if (kDebugMode) print('💽 [COUPLE_SELFIE] Loaded selfie from cache');
      }
    } catch (e) {
      if (kDebugMode) print('❌ [COUPLE_SELFIE] Error loading from cache: $e');
    }
  }

  /// Inizializza il servizio e carica la foto esistente se presente
  Future<void> initialize(String familyChatId) async {
    if (kDebugMode) print('🖼️ [COUPLE_SELFIE] Initializing for family: $familyChatId');

    try {
      // Prima prova a caricare dalla cache locale
      await _loadFromCache();

      final docRef = _firestore.collection('families').doc(familyChatId);
      final doc = await docRef.get();

      if (doc.exists) {
        final data = doc.data();
        final url = data?['couple_selfie_url'] as String?;

        _selfieUrl = url;

        if (kDebugMode) {
          print('🖼️ [COUPLE_SELFIE] Loaded selfie: ${_selfieUrl != null ? "YES" : "NO"}');
        }

        // Se c'è un URL e non abbiamo cache, scarica
        if (url != null && _cachedSelfieBytes == null) {
          await _downloadAndCacheSelfie(url);
        }

        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) print('❌ [COUPLE_SELFIE] Error loading selfie: $e');
    }
  }

  /// Carica una nuova foto di coppia
  /// Questa funzione:
  /// 1. Carica la foto su Firebase Storage
  /// 2. Salva l'URL nel documento Firestore della famiglia
  /// 3. Salva in cache locale
  /// 4. Notifica tutti i listener
  Future<bool> uploadCoupleSelfie(File imageFile, String familyChatId) async {
    if (_isLoading) return false;

    _isLoading = true;
    notifyListeners();

    try {
      if (kDebugMode) print('📤 [COUPLE_SELFIE] Uploading selfie for family: $familyChatId');

      // 1. Leggi i bytes dell'immagine
      final imageBytes = await imageFile.readAsBytes();

      // 2. Upload file to Firebase Storage
      final fileName = 'couple_selfie_${DateTime.now().millisecondsSinceEpoch}${path.extension(imageFile.path)}';
      final storageRef = _storage.ref().child('families/$familyChatId/$fileName');

      final uploadTask = await storageRef.putFile(
        imageFile,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      // 3. Get download URL
      final downloadUrl = await uploadTask.ref.getDownloadURL();

      if (kDebugMode) print('✅ [COUPLE_SELFIE] Upload complete: $downloadUrl');

      // 4. Save URL to Firestore
      final docRef = _firestore.collection('families').doc(familyChatId);
      await docRef.set({
        'couple_selfie_url': downloadUrl,
        'couple_selfie_updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 5. Update local state and cache
      _selfieUrl = downloadUrl;
      _cachedSelfieBytes = imageBytes;

      // Salva in cache su disco
      _cacheFile = await _getCacheFile();
      await _cacheFile!.writeAsBytes(imageBytes);

      _isLoading = false;
      notifyListeners();

      if (kDebugMode) print('✅ [COUPLE_SELFIE] Selfie saved and cached successfully');

      return true;
    } catch (e) {
      if (kDebugMode) print('❌ [COUPLE_SELFIE] Error uploading selfie: $e');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Rimuove la foto di coppia
  Future<bool> removeCoupleSelfie(String familyChatId) async {
    try {
      if (kDebugMode) print('🗑️ [COUPLE_SELFIE] Removing selfie for family: $familyChatId');

      // 1. Remove from Firestore
      final docRef = _firestore.collection('families').doc(familyChatId);
      await docRef.update({
        'couple_selfie_url': FieldValue.delete(),
        'couple_selfie_updated_at': FieldValue.delete(),
      });

      // 2. Remove from cache
      _cachedSelfieBytes = null;
      _cacheFile = await _getCacheFile();
      if (await _cacheFile!.exists()) {
        await _cacheFile!.delete();
      }

      // 3. Update local state
      _selfieUrl = null;
      notifyListeners();

      if (kDebugMode) print('✅ [COUPLE_SELFIE] Selfie removed successfully');

      return true;
    } catch (e) {
      if (kDebugMode) print('❌ [COUPLE_SELFIE] Error removing selfie: $e');
      return false;
    }
  }

  /// Listener real-time per aggiornamenti della foto di coppia
  Stream<String?> watchCoupleSelfie(String familyChatId) {
    return _firestore
        .collection('families')
        .doc(familyChatId)
        .snapshots()
        .map((doc) {
      if (doc.exists) {
        final data = doc.data();
        final url = data?['couple_selfie_url'] as String?;

        // Update local state
        final oldUrl = _selfieUrl;
        _selfieUrl = url;

        // Se l'URL è cambiato e non abbiamo cache, scarica la nuova foto
        if (url != null && url != oldUrl) {
          _downloadAndCacheSelfie(url);
        }

        notifyListeners();

        return url;
      }
      return null;
    });
  }
}
