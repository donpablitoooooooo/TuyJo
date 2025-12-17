import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Servizio per gestire il pairing tra dispositivi tramite RSA public keys
/// Architettura RSA-only: ogni dispositivo condivide solo la propria chiave pubblica
class PairingService extends ChangeNotifier {
  final _storage = const FlutterSecureStorage();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _pairingStatusSubscription;

  bool _isPaired = false;
  String? _partnerPublicKey;
  bool _familyWasComplete = false; // Traccia se abbiamo mai visto 2 users

  bool get isPaired => _isPaired;
  String? get partnerPublicKey => _partnerPublicKey;

  /// Inizializza il servizio verificando se esiste già un pairing
  /// Il pairing è considerato valido se esiste partner_public_key
  Future<void> initialize() async {
    if (kDebugMode) print('🔍 [PAIRING] initialize() called');

    final partnerPubKey = await _storage.read(key: 'partner_public_key');

    if (kDebugMode) {
      print('🔍 [PAIRING] partner_public_key from storage: ${partnerPubKey != null ? "${partnerPubKey.substring(0, 20)}..." : "NULL (not paired)"}');
    }

    if (partnerPubKey != null) {
      _isPaired = true;
      _partnerPublicKey = partnerPubKey;
      notifyListeners();

      if (kDebugMode) {
        print('✅ [PAIRING] Pairing initialized successfully');
        print('   Partner public key: ${partnerPubKey.substring(0, 20)}...');
        print('   _isPaired = true');
      }

      // UNPAIR SYNC: Avvia listener SEMPRE quando c'è un pairing
      // Non aspettare che ChatScreen venga aperta
      _startBackgroundUnpairListener();
    } else {
      if (kDebugMode) {
        print('❌ [PAIRING] No pairing found in storage');
        print('   _isPaired = false');
        print('   Show QR code screen to pair');
      }
    }
  }

  /// Ottiene i dati da codificare nel QR code
  /// Include solo la chiave pubblica RSA (SICURO!)
  Future<String> getMyPublicKeyQRData(String myPublicKey) async {
    final qrData = {
      'public_key': myPublicKey,
      'version': '2.0', // Nuova versione architettura RSA-only
    };

    return json.encode(qrData);
  }

  /// Importa la chiave pubblica del partner da QR code scansionato
  Future<bool> importPartnerPublicKeyFromQR(String qrData) async {
    try {
      if (kDebugMode) {
        print('🔍 DEBUG QR Data:');
        print('   QR Length: ${qrData.length}');
        print('   QR First 100: ${qrData.substring(0, qrData.length > 100 ? 100 : qrData.length)}');
      }

      final data = json.decode(qrData) as Map<String, dynamic>;

      final partnerPublicKey = data['public_key'] as String?;

      if (partnerPublicKey == null) {
        if (kDebugMode) print('Invalid QR data: missing public_key');
        return false;
      }

      if (kDebugMode) {
        print('🔍 DEBUG Partner Public Key from QR:');
        print('   Length: ${partnerPublicKey.length}');
        print('   First 50: ${partnerPublicKey.substring(0, partnerPublicKey.length > 50 ? 50 : partnerPublicKey.length)}');
        print('   Last 50: ${partnerPublicKey.substring(partnerPublicKey.length > 50 ? partnerPublicKey.length - 50 : 0)}');
      }

      // Salva chiave pubblica del partner
      if (kDebugMode) print('💾 [PAIRING] Saving partner_public_key to secure storage...');
      await _storage.write(key: 'partner_public_key', value: partnerPublicKey);

      // Verifica che sia stata salvata correttamente
      final savedKey = await _storage.read(key: 'partner_public_key');
      if (kDebugMode) {
        print('✅ [PAIRING] Verification: key saved = ${savedKey != null}');
        if (savedKey != null) {
          print('   Saved key matches: ${savedKey == partnerPublicKey}');
        }
      }

      // IMPORTANTE: Ferma il vecchio listener prima di cambiare familyChatId
      // Altrimenti rimane un listener attivo sulla vecchia famiglia che può causare unpair
      stopListeningToPairingStatus();
      _familyWasComplete = false; // Reset per il nuovo pairing

      _isPaired = true;
      _partnerPublicKey = partnerPublicKey;
      notifyListeners();

      if (kDebugMode) {
        print('✅ [PAIRING] Partner public key imported successfully');
        print('   Partner key: ${partnerPublicKey.substring(0, 20)}...');
        print('   _isPaired = true');
        print('   UI should now show chat screen');
      }

      return true;
    } catch (e) {
      if (kDebugMode) print('Error importing partner public key: $e');
      return false;
    }
  }

  /// Reset del pairing (elimina partner)
  Future<void> resetPairing() async {
    await _storage.delete(key: 'partner_public_key');

    _isPaired = false;
    _partnerPublicKey = null;
    notifyListeners();

    if (kDebugMode) print('Pairing reset');
  }

  /// Calcola l'ID utente del partner basato sulla sua chiave pubblica
  Future<String?> getPartnerId() async {
    if (_partnerPublicKey == null) return null;

    // userId = SHA-256(publicKey)
    final bytes = utf8.encode(_partnerPublicKey!);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Ottiene l'ID dell'utente corrente basato sulla propria chiave pubblica
  Future<String?> getMyUserId() async {
    final myPublicKey = await _storage.read(key: 'rsa_public_key');
    if (myPublicKey == null) return null;

    // userId = SHA-256(publicKey)
    final bytes = utf8.encode(myPublicKey);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Salva la chiave pubblica dell'utente corrente
  Future<void> saveMyPublicKey(String publicKey) async {
    await _storage.write(key: 'rsa_public_key', value: publicKey);
  }

  /// Alias per resetPairing (per compatibilità)
  Future<void> clearPairing() async {
    await resetPairing();
  }

  /// Calcola l'ID della chat condivisa tra i due utenti
  /// family_chat_id = SHA-256(sorted([myPublicKey, partnerPublicKey]))
  /// Questo garantisce che entrambi gli utenti calcolino lo stesso ID
  Future<String?> getFamilyChatId() async {
    final myPublicKey = await _storage.read(key: 'rsa_public_key');
    final partnerPublicKey = _partnerPublicKey;

    if (myPublicKey == null || partnerPublicKey == null) return null;

    // Sort per garantire stesso ID da entrambe le parti
    final keys = [myPublicKey, partnerPublicKey]..sort();
    final combined = keys.join('|');

    // family_chat_id = SHA-256(combined sorted keys)
    final bytes = utf8.encode(combined);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Avvia manualmente il background listener
  /// Da chiamare DOPO che i token FCM sono stati salvati su Firestore
  void startBackgroundUnpairListener() {
    _startBackgroundUnpairListener();
  }

  /// Ferma il listener del pairing status
  void stopListeningToPairingStatus() {
    _pairingStatusSubscription?.cancel();
    _pairingStatusSubscription = null;
    if (kDebugMode) print('🔇 Stopped listening to pairing status');
  }

  /// Background listener che ascolta SEMPRE unpair del partner
  /// Basato sullo STATO della famiglia (collezione users) invece che su eventi
  void _startBackgroundUnpairListener() async {
    final chatId = await getFamilyChatId();
    if (chatId == null) {
      if (kDebugMode) print('⚠️ No chatId, cannot listen to pairing status');
      return;
    }

    final myUserId = await getMyUserId();
    if (myUserId == null) {
      if (kDebugMode) print('⚠️ No userId, cannot listen to pairing status');
      return;
    }

    if (kDebugMode) print('🎧 Background unpair listener (state-based) started for chat: ${chatId.substring(0, 10)}...');

    // STATE-BASED: Ascolta la collezione /users invece di pairing_status
    _pairingStatusSubscription = _firestore
        .collection('families')
        .doc(chatId)
        .collection('users')
        .snapshots()
        .listen(
      (snapshot) async {
      final userCount = snapshot.docs.length;

      if (kDebugMode) print('👥 Family users count: $userCount');

      // Traccia quando la famiglia diventa completa (2 users)
      if (userCount == 2) {
        if (!_familyWasComplete) {
          _familyWasComplete = true;
          if (kDebugMode) print('✅ Famiglia completa: 2 utenti presenti');
        }
      }

      // Fai unpair SOLO se la famiglia era completa (2 users) e ora non lo è più
      if (userCount < 2 && _isPaired && _familyWasComplete) {
        // Verifica che IO sia ancora presente (potrei essere l'unico rimasto)
        final iAmPresent = snapshot.docs.any((doc) => doc.id == myUserId);

        if (iAmPresent && userCount == 1) {
          // Solo io presente → partner ha fatto unpair
          if (kDebugMode) {
            print('⚠️ [PAIRING] Partner unpaired detected!');
            print('   User count: $userCount (only me)');
            print('   Family was complete: $_familyWasComplete');
            print('   Triggering auto-unpair...');
          }

          // Fai unpair locale
          await _storage.delete(key: 'partner_public_key');
          _isPaired = false;
          _partnerPublicKey = null;
          _familyWasComplete = false; // Reset per il prossimo pairing

          // Ferma il listener
          stopListeningToPairingStatus();

          // Notifica i listener (Provider)
          notifyListeners();

          if (kDebugMode) print('✅ [PAIRING] Auto-unpair completed (partner left)');
        } else if (!iAmPresent && userCount == 0) {
          // Nessuno presente → famiglia vuota
          if (kDebugMode) {
            print('⚠️ [PAIRING] Family empty detected!');
            print('   User count: 0');
            print('   Triggering auto-unpair...');
          }

          await _storage.delete(key: 'partner_public_key');
          _isPaired = false;
          _partnerPublicKey = null;
          _familyWasComplete = false; // Reset per il prossimo pairing
          stopListeningToPairingStatus();
          notifyListeners();

          if (kDebugMode) print('✅ [PAIRING] Auto-unpair completed (family empty)');
        }
      } else if (userCount < 2 && !_familyWasComplete && kDebugMode) {
        // Pairing iniziale in corso - aspettiamo il partner
        print('⏳ Pairing in corso, aspettando il partner... ($userCount/2 users)');
      }
    },
    onError: (error) {
      // 🔧 FIX: NON fare unpair in caso di errori di connessione!
      // Gli errori sono normali quando l'app è offline
      if (kDebugMode) {
        print('⚠️ [PAIRING] Listener error (probably offline): $error');
        print('   Keeping paired status unchanged (offline resilience)');
        print('   _isPaired still = $_isPaired');
      }
      // Mantieni _isPaired e _partnerPublicKey invariati
    },
  );
  }

  @override
  void dispose() {
    stopListeningToPairingStatus();
    super.dispose();
  }
}
