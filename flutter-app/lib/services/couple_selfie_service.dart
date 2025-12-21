import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path/path.dart' as path;

/// Servizio per gestire la foto di coppia condivisa tra i due dispositivi
class CoupleSelfieService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  String? _selfieUrl;
  bool _isLoading = false;

  String? get selfieUrl => _selfieUrl;
  bool get isLoading => _isLoading;
  bool get hasSelfie => _selfieUrl != null && _selfieUrl!.isNotEmpty;

  /// Inizializza il servizio e carica la foto esistente se presente
  Future<void> initialize(String familyChatId) async {
    if (kDebugMode) print('🖼️ [COUPLE_SELFIE] Initializing for family: $familyChatId');

    try {
      final docRef = _firestore.collection('families').doc(familyChatId);
      final doc = await docRef.get();

      if (doc.exists) {
        final data = doc.data();
        _selfieUrl = data?['couple_selfie_url'] as String?;

        if (kDebugMode) {
          print('🖼️ [COUPLE_SELFIE] Loaded selfie: ${_selfieUrl != null ? "YES" : "NO"}');
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
  /// 3. Notifica tutti i listener
  Future<bool> uploadCoupleSelfie(File imageFile, String familyChatId) async {
    if (_isLoading) return false;

    _isLoading = true;
    notifyListeners();

    try {
      if (kDebugMode) print('📤 [COUPLE_SELFIE] Uploading selfie for family: $familyChatId');

      // 1. Upload file to Firebase Storage
      final fileName = 'couple_selfie_${DateTime.now().millisecondsSinceEpoch}${path.extension(imageFile.path)}';
      final storageRef = _storage.ref().child('families/$familyChatId/$fileName');

      final uploadTask = await storageRef.putFile(
        imageFile,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      // 2. Get download URL
      final downloadUrl = await uploadTask.ref.getDownloadURL();

      if (kDebugMode) print('✅ [COUPLE_SELFIE] Upload complete: $downloadUrl');

      // 3. Save URL to Firestore
      final docRef = _firestore.collection('families').doc(familyChatId);
      await docRef.set({
        'couple_selfie_url': downloadUrl,
        'couple_selfie_updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 4. Update local state
      _selfieUrl = downloadUrl;
      _isLoading = false;
      notifyListeners();

      if (kDebugMode) print('✅ [COUPLE_SELFIE] Selfie saved successfully');

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

      // 2. Update local state
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
        _selfieUrl = url;
        notifyListeners();

        return url;
      }
      return null;
    });
  }
}
