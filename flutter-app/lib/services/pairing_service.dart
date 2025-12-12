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

  bool get isPaired => _isPaired;
  String? get partnerPublicKey => _partnerPublicKey;

  /// Inizializza il servizio verificando se esiste già un pairing
  /// Il pairing è considerato valido se esiste partner_public_key
  Future<void> initialize() async {
    final partnerPubKey = await _storage.read(key: 'partner_public_key');

    if (partnerPubKey != null) {
      _isPaired = true;
      _partnerPublicKey = partnerPubKey;
      notifyListeners();

      if (kDebugMode) {
        print('✅ Pairing initialized');
        print('   Partner public key: ${partnerPubKey.substring(0, 20)}...');
      }

      // UNPAIR SYNC: Avvia listener SEMPRE quando c'è un pairing
      // Non aspettare che ChatScreen venga aperta
      _startBackgroundUnpairListener();
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
      await _storage.write(key: 'partner_public_key', value: partnerPublicKey);

      _isPaired = true;
      _partnerPublicKey = partnerPublicKey;
      notifyListeners();

      if (kDebugMode) {
        print('✅ Partner public key imported: ${partnerPublicKey.substring(0, 20)}...');
      }

      // UNPAIR SYNC: Avvia background listener per il nuovo pairing
      _startBackgroundUnpairListener();

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

  /// Notifica al partner che abbiamo fatto unpair
  /// Scrive su Firestore che il pairing è stato interrotto
  Future<void> notifyUnpair() async {
    try {
      final chatId = await getFamilyChatId();
      if (chatId == null) {
        if (kDebugMode) print('⚠️ No chatId, cannot notify unpair');
        return;
      }

      final myUserId = await getMyUserId();
      if (myUserId == null) {
        if (kDebugMode) print('⚠️ No userId, cannot notify unpair');
        return;
      }

      // Scrivi su Firestore che hai fatto unpair
      await _firestore.collection('families').doc(chatId).set({
        'pairing_status': 'unpaired',
        'unpaired_by': myUserId,
        'unpaired_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (kDebugMode) print('✅ Unpair notificato al partner su Firestore');
    } catch (e) {
      if (kDebugMode) print('❌ Errore notifica unpair: $e');
    }
  }


  /// Ferma il listener del pairing status
  void stopListeningToPairingStatus() {
    _pairingStatusSubscription?.cancel();
    _pairingStatusSubscription = null;
    if (kDebugMode) print('🔇 Stopped listening to pairing status');
  }

  /// Ripristina il pairing status su Firestore quando si rifare pairing
  Future<void> resetPairingStatus() async {
    try {
      final chatId = await getFamilyChatId();
      if (chatId == null) return;

      await _firestore.collection('families').doc(chatId).set({
        'pairing_status': 'paired',
        'paired_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (kDebugMode) print('✅ Pairing status ripristinato su Firestore');
    } catch (e) {
      if (kDebugMode) print('❌ Errore reset pairing status: $e');
    }
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
        .listen((snapshot) async {
      final userCount = snapshot.docs.length;

      if (kDebugMode) print('👥 Family users count: $userCount');

      // Se ci sono meno di 2 utenti e io sono ancora in pairing → partner ha fatto unpair
      if (userCount < 2 && _isPaired) {
        // Verifica che IO sia ancora presente (potrei essere l'unico rimasto)
        final iAmPresent = snapshot.docs.any((doc) => doc.id == myUserId);

        if (iAmPresent && userCount == 1) {
          // Solo io presente → partner ha fatto unpair
          if (kDebugMode) print('⚠️ Partner ha fatto unpair (stato: solo 1 user), facciamo unpair automatico');

          // Fai unpair locale
          await _storage.delete(key: 'partner_public_key');
          _isPaired = false;
          _partnerPublicKey = null;

          // Ferma il listener
          stopListeningToPairingStatus();

          // Notifica i listener (Provider)
          notifyListeners();

          if (kDebugMode) print('✅ Unpair automatico completato');
        } else if (!iAmPresent && userCount == 0) {
          // Nessuno presente → famiglia vuota
          if (kDebugMode) print('⚠️ Famiglia vuota, facciamo unpair automatico');

          await _storage.delete(key: 'partner_public_key');
          _isPaired = false;
          _partnerPublicKey = null;
          stopListeningToPairingStatus();
          notifyListeners();
        }
      } else if (userCount == 2 && kDebugMode) {
        // Entrambi presenti → famiglia completa
        print('✅ Famiglia completa: 2 utenti presenti');
      }
    });
  }

  @override
  void dispose() {
    stopListeningToPairingStatus();
    super.dispose();
  }
}
