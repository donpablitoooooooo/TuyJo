import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'encryption_service.dart';
import 'pairing_service.dart';

/// Servizio per gestire la foto di coppia condivisa tra i due dispositivi
class CoupleSelfieService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final EncryptionService encryptionService;
  final PairingService pairingService;

  String? _selfieUrl;
  bool _isLoading = false;
  Uint8List? _cachedSelfieBytes; // Cache in memoria
  File? _cacheFile; // File cache su disco
  StreamSubscription<String?>? _selfieSubscription; // Listener real-time

  // Metadati di crittografia per la foto corrente
  Map<String, String>? _encryptedKeys; // Map userId -> encryptedKey
  String? _iv;

  CoupleSelfieService({
    required this.encryptionService,
    required this.pairingService,
  });

  String? get selfieUrl => _selfieUrl;

  /// Calcola l'userId da una chiave pubblica (SHA-256)
  String _getUserIdFromPublicKey(String publicKey) {
    final bytes = utf8.encode(publicKey);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
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

  /// Scarica la foto da URL, la decifra e la salva in cache
  Future<void> _downloadAndCacheSelfie(String url, String? encryptedKey, String? iv) async {
    try {
      if (kDebugMode) print('📥 [COUPLE_SELFIE] Downloading encrypted selfie from URL...');

      // Scarica l'immagine CRIPTATA
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final encryptedBytes = response.bodyBytes;

        if (kDebugMode) {
          print('✅ [COUPLE_SELFIE] Downloaded encrypted file');
          print('   Size: ${(encryptedBytes.length / 1024).toStringAsFixed(1)} KB');
        }

        // Verifica che abbiamo i metadati di crittografia
        if (encryptedKey == null || iv == null) {
          if (kDebugMode) print('⚠️ [COUPLE_SELFIE] Missing encryption metadata, cannot decrypt');
          return;
        }

        // Decifra il file
        if (kDebugMode) print('🔓 [COUPLE_SELFIE] Decrypting photo...');
        final decryptedBytes = encryptionService.decryptFile(
          encryptedBytes,
          encryptedKey,
          iv,
        );

        if (kDebugMode) {
          print('✅ [COUPLE_SELFIE] Photo decrypted successfully');
          print('   Decrypted size: ${(decryptedBytes.length / 1024).toStringAsFixed(1)} KB');
        }

        // Salva in memoria (DECRIPTATA)
        _cachedSelfieBytes = decryptedBytes;

        // Salva su disco (DECRIPTATA)
        _cacheFile = await _getCacheFile();
        await _cacheFile!.writeAsBytes(decryptedBytes);

        if (kDebugMode) print('✅ [COUPLE_SELFIE] Decrypted selfie cached successfully');
      } else {
        if (kDebugMode) print('❌ [COUPLE_SELFIE] Failed to download selfie: ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) print('❌ [COUPLE_SELFIE] Error downloading/decrypting selfie: $e');
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
        final encryptedKeysMap = data?['couple_selfie_encrypted_keys'] as Map<String, dynamic>?;
        final iv = data?['couple_selfie_iv'] as String?;

        _selfieUrl = url;
        _encryptedKeys = encryptedKeysMap?.map((key, value) => MapEntry(key, value as String));
        _iv = iv;

        if (kDebugMode) {
          print('🖼️ [COUPLE_SELFIE] Loaded selfie: ${_selfieUrl != null ? "YES" : "NO"}');
          print('   Encryption metadata: ${iv != null ? "YES" : "NO"}');
          print('   Encrypted keys count: ${_encryptedKeys?.length ?? 0}');
        }

        // Se c'è un URL e non abbiamo cache, scarica e decifra
        if (url != null && _cachedSelfieBytes == null && _encryptedKeys != null) {
          // Usa la chiave del proprio userId
          final myUserId = await pairingService.getMyUserId();
          if (myUserId != null) {
            final myEncryptedKey = _encryptedKeys![myUserId];
            if (myEncryptedKey != null) {
              if (kDebugMode) print('🔑 [COUPLE_SELFIE] Using my encrypted key for userId: $myUserId');
              await _downloadAndCacheSelfie(url, myEncryptedKey, iv);
            } else {
              if (kDebugMode) print('⚠️ [COUPLE_SELFIE] No encrypted key found for my userId: $myUserId');
            }
          }
        }

        notifyListeners();
      }

      // 🔥 IMPORTANTE: Attiva il listener real-time per sincronizzare tra dispositivi
      _selfieSubscription?.cancel(); // Cancella listener precedente se esiste
      _selfieSubscription = watchCoupleSelfie(familyChatId).listen((_) {
        if (kDebugMode) print('🔄 [COUPLE_SELFIE] Real-time update received');
      });

      if (kDebugMode) print('✅ [COUPLE_SELFIE] Real-time listener activated');
    } catch (e) {
      if (kDebugMode) print('❌ [COUPLE_SELFIE] Error loading selfie: $e');
    }
  }

  /// Carica una nuova foto di coppia (CRIPTATA)
  /// Questa funzione:
  /// 1. Elimina la vecchia foto da Storage se esiste
  /// 2. Cifra la foto con dual encryption (AES + RSA)
  /// 3. Carica la foto criptata con nome fisso 'couple_selfie.encrypted'
  /// 4. Salva URL e metadati di crittografia nel documento Firestore
  /// 5. Salva in cache locale (decriptata)
  /// 6. Notifica tutti i listener
  ///
  /// IMPORTANTE: C'è sempre e solo UNA foto sul server.
  /// Ogni nuovo upload sovrascrive la precedente.
  Future<bool> uploadCoupleSelfie(File imageFile, String familyChatId) async {
    if (_isLoading) return false;

    _isLoading = true;
    notifyListeners();

    try {
      if (kDebugMode) print('📤 [COUPLE_SELFIE] Uploading encrypted selfie for family: $familyChatId');

      // 1. Elimina la vecchia foto da Storage se esiste
      if (_selfieUrl != null && _selfieUrl!.isNotEmpty) {
        try {
          if (kDebugMode) print('🗑️ [COUPLE_SELFIE] Deleting old photo from Storage...');
          final oldRef = _storage.refFromURL(_selfieUrl!);
          await oldRef.delete();
          if (kDebugMode) print('✅ [COUPLE_SELFIE] Old photo deleted');
        } catch (e) {
          if (kDebugMode) print('⚠️ [COUPLE_SELFIE] Could not delete old photo: $e');
          // Non bloccare l'upload se la cancellazione fallisce
        }
      }

      // 2. Leggi i bytes dell'immagine ORIGINALE (per cache)
      final imageBytes = await imageFile.readAsBytes();

      // 3. Ottieni le chiavi pubbliche di entrambi i partner
      final myUserId = await pairingService.getMyUserId();
      final myPublicKey = await encryptionService.getPublicKey();
      final partnerPublicKey = pairingService.partnerPublicKey;

      if (myUserId == null || myPublicKey == null || partnerPublicKey == null) {
        throw Exception('Cannot encrypt: missing userId or public keys');
      }

      // Calcola l'userId del partner dalla sua chiave pubblica
      final partnerUserId = _getUserIdFromPublicKey(partnerPublicKey);

      if (kDebugMode) {
        print('🔐 [COUPLE_SELFIE] Encrypting photo with dual encryption...');
        print('   My userId: $myUserId');
        print('   Partner userId: $partnerUserId');
      }

      // 4. Cifra il file con dual encryption
      final encryptedData = encryptionService.encryptFileDual(
        imageBytes,
        myPublicKey,
        partnerPublicKey,
      );

      final Uint8List encryptedFileBytes = encryptedData['encryptedFileBytes'] as Uint8List;
      final String encryptedKeyRecipient = encryptedData['encryptedKeyRecipient'] as String;
      final String encryptedKeySender = encryptedData['encryptedKeySender'] as String;
      final String iv = encryptedData['iv'] as String;

      if (kDebugMode) {
        print('✅ [COUPLE_SELFIE] Photo encrypted successfully');
        print('   Original size: ${(imageBytes.length / 1024).toStringAsFixed(1)} KB');
        print('   Encrypted size: ${(encryptedFileBytes.length / 1024).toStringAsFixed(1)} KB');
      }

      // 5. Upload file CRIPTATO to Firebase Storage con NOME FISSO
      const fileName = 'couple_selfie.encrypted';
      final storageRef = _storage.ref().child('families/$familyChatId/$fileName');

      final uploadTask = await storageRef.putData(
        encryptedFileBytes,
        SettableMetadata(contentType: 'application/octet-stream'),
      );

      // 6. Get download URL
      final downloadUrl = await uploadTask.ref.getDownloadURL();

      if (kDebugMode) print('✅ [COUPLE_SELFIE] Encrypted upload complete: $downloadUrl');

      // 7. Crea mappa delle chiavi cifrate usando gli userId reali
      final encryptedKeysMap = {
        myUserId: encryptedKeySender,
        partnerUserId: encryptedKeyRecipient,
      };

      // 8. Save URL e metadati di crittografia to Firestore
      final docRef = _firestore.collection('families').doc(familyChatId);
      await docRef.set({
        'couple_selfie_url': downloadUrl,
        'couple_selfie_encrypted_keys': encryptedKeysMap,
        'couple_selfie_iv': iv,
        'couple_selfie_updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 9. Update local state and cache
      _selfieUrl = downloadUrl;
      _encryptedKeys = encryptedKeysMap;
      _iv = iv;
      _cachedSelfieBytes = imageBytes; // Cache DECRIPTATA

      // Salva in cache su disco (DECRIPTATA per visualizzazione veloce)
      _cacheFile = await _getCacheFile();
      await _cacheFile!.writeAsBytes(imageBytes);

      _isLoading = false;
      notifyListeners();

      if (kDebugMode) print('✅ [COUPLE_SELFIE] Encrypted selfie saved and cached successfully');

      return true;
    } catch (e) {
      if (kDebugMode) print('❌ [COUPLE_SELFIE] Error uploading selfie: $e');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Rimuove la foto di coppia
  ///
  /// Se [deleteFromServer] è true, elimina sia dal server che dalla cache locale.
  /// Se false, elimina solo dalla cache locale (utile per cambio telefono).
  /// Se [deleteStorageFile] è true, elimina anche il file da Firebase Storage.
  Future<bool> removeCoupleSelfie(
    String familyChatId, {
    bool deleteFromServer = true,
    bool deleteStorageFile = false,
  }) async {
    try {
      if (kDebugMode) {
        print('🗑️ [COUPLE_SELFIE] Removing selfie for family: $familyChatId');
        print('   deleteFromServer: $deleteFromServer, deleteStorageFile: $deleteStorageFile');
      }

      // 1. Elimina il file da Firebase Storage se richiesto
      if (deleteStorageFile && _selfieUrl != null) {
        try {
          final storageRef = _storage.refFromURL(_selfieUrl!);
          await storageRef.delete();
          if (kDebugMode) print('✅ [COUPLE_SELFIE] Storage file deleted');
        } catch (e) {
          if (kDebugMode) print('⚠️ [COUPLE_SELFIE] Could not delete storage file: $e');
          // Non lanciare errore - il file potrebbe già essere stato eliminato
        }
      }

      // 2. Remove from Firestore (solo se richiesto)
      if (deleteFromServer) {
        final docRef = _firestore.collection('families').doc(familyChatId);
        await docRef.update({
          'couple_selfie_url': FieldValue.delete(),
          'couple_selfie_encrypted_keys': FieldValue.delete(),
          'couple_selfie_iv': FieldValue.delete(),
          'couple_selfie_updated_at': FieldValue.delete(),
        });
        if (kDebugMode) print('✅ [COUPLE_SELFIE] Firestore metadata deleted');
      }

      // 3. Remove from local cache (sempre)
      _cachedSelfieBytes = null;
      _cacheFile = await _getCacheFile();
      if (await _cacheFile!.exists()) {
        await _cacheFile!.delete();
      }

      // 4. Update local state
      if (deleteFromServer) {
        _selfieUrl = null;
        _encryptedKeys = null;
        _iv = null;
      }
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
        .asyncMap((doc) async {
      if (doc.exists) {
        final data = doc.data();
        final url = data?['couple_selfie_url'] as String?;
        final encryptedKeysMap = data?['couple_selfie_encrypted_keys'] as Map<String, dynamic>?;
        final iv = data?['couple_selfie_iv'] as String?;

        // Update local state
        final oldUrl = _selfieUrl;
        _selfieUrl = url;
        _encryptedKeys = encryptedKeysMap?.map((key, value) => MapEntry(key, value as String));
        _iv = iv;

        // Se l'URL è cambiato
        if (url != oldUrl) {
          if (url != null && _encryptedKeys != null) {
            // Nuova foto - scaricala, decriptala e notifica solo quando finito
            // Usa la chiave del proprio userId
            final myUserId = await pairingService.getMyUserId();
            if (myUserId != null) {
              final myEncryptedKey = _encryptedKeys![myUserId];
              if (myEncryptedKey != null) {
                if (kDebugMode) print('🔑 [COUPLE_SELFIE] Using my encrypted key for userId: $myUserId');
                await _downloadAndCacheSelfie(url, myEncryptedKey, iv);
                notifyListeners();
                if (kDebugMode) print('🔄 [COUPLE_SELFIE] Photo updated, decrypted and UI notified');
              } else {
                if (kDebugMode) print('⚠️ [COUPLE_SELFIE] No encrypted key found for my userId: $myUserId');
              }
            }
          } else {
            // Foto eliminata - pulisci cache
            _cachedSelfieBytes = null;
            _encryptedKeys = null;
            _iv = null;
            final cacheFile = await _getCacheFile();
            if (await cacheFile.exists()) {
              await cacheFile.delete();
              if (kDebugMode) print('🗑️ [COUPLE_SELFIE] Cache cleared (photo deleted)');
            }
            notifyListeners();
          }
        } else {
          // URL non cambiato, notifica comunque per sicurezza
          notifyListeners();
        }

        return url;
      }
      return null;
    });
  }

  @override
  void dispose() {
    _selfieSubscription?.cancel();
    super.dispose();
  }
}
