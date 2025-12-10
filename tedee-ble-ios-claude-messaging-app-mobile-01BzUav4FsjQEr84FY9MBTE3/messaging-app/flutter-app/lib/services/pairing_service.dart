import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';
import 'dart:math';

/// Servizio per gestire il pairing tra dispositivi tramite K_family
/// K_family è una chiave simmetrica AES-256 condivisa tra i membri della famiglia
class PairingService extends ChangeNotifier {
  final _storage = const FlutterSecureStorage();

  bool _isPaired = false;
  String? _partnerPublicKey;

  bool get isPaired => _isPaired;
  String? get partnerPublicKey => _partnerPublicKey;

  /// Inizializza il servizio verificando se esiste già un pairing
  Future<void> initialize() async {
    final kFamily = await _storage.read(key: 'k_family');
    final partnerPubKey = await _storage.read(key: 'partner_public_key');

    if (kFamily != null && partnerPubKey != null) {
      _isPaired = true;
      _partnerPublicKey = partnerPubKey;
      notifyListeners();
    }
  }

  /// Genera una nuova K_family (chiave AES-256)
  /// Questa funzione viene chiamata dall'utente che MOSTRA il QR code
  Future<String> generateFamilyKey() async {
    // Genera 32 byte random per AES-256
    final random = Random.secure();
    final keyBytes = Uint8List.fromList(
      List<int>.generate(32, (i) => random.nextInt(256))
    );

    // Converti in base64 per storage e trasferimento
    final kFamilyBase64 = base64Encode(keyBytes);

    // Salva in secure storage
    await _storage.write(key: 'k_family', value: kFamilyBase64);

    if (kDebugMode) print('K_family generated: ${kFamilyBase64.substring(0, 10)}...');

    return kFamilyBase64;
  }

  /// Ottiene i dati da codificare nel QR code
  /// Include K_family + chiave pubblica del creatore
  Future<String> getFamilyKeyQRData(String myPublicKey) async {
    String? kFamily = await _storage.read(key: 'k_family');

    // Se non esiste, generala
    kFamily ??= await generateFamilyKey();

    // Crea payload JSON
    final qrData = {
      'k_family': kFamily,
      'creator_public_key': myPublicKey,
    };

    return json.encode(qrData);
  }

  /// Importa K_family da QR code scansionato
  /// Questa funzione viene chiamata dall'utente che SCANSIONA il QR code
  Future<bool> importFamilyKeyFromQR(String qrData) async {
    try {
      final data = json.decode(qrData) as Map<String, dynamic>;

      final kFamily = data['k_family'] as String?;
      final creatorPublicKey = data['creator_public_key'] as String?;

      if (kFamily == null || creatorPublicKey == null) {
        if (kDebugMode) print('Invalid QR data: missing fields');
        return false;
      }

      // Salva K_family
      await _storage.write(key: 'k_family', value: kFamily);

      // Salva chiave pubblica del partner (creatore)
      await _storage.write(key: 'partner_public_key', value: creatorPublicKey);

      _isPaired = true;
      _partnerPublicKey = creatorPublicKey;
      notifyListeners();

      if (kDebugMode) {
        print('K_family imported: ${kFamily.substring(0, 10)}...');
        print('Partner public key: ${creatorPublicKey.substring(0, 20)}...');
      }

      return true;
    } catch (e) {
      if (kDebugMode) print('Error importing family key: $e');
      return false;
    }
  }

  /// Completa il pairing per chi ha CREATO il QR
  /// Salva la chiave pubblica del partner dopo che ha scansionato
  Future<void> completePairing(String partnerPublicKey) async {
    await _storage.write(key: 'partner_public_key', value: partnerPublicKey);

    _isPaired = true;
    _partnerPublicKey = partnerPublicKey;
    notifyListeners();

    if (kDebugMode) print('Pairing completed with partner: ${partnerPublicKey.substring(0, 20)}...');
  }

  /// Ottiene K_family dal secure storage
  Future<String?> getFamilyKey() async {
    return await _storage.read(key: 'k_family');
  }

  /// Verifica se K_family esiste
  Future<bool> hasFamilyKey() async {
    final kFamily = await _storage.read(key: 'k_family');
    return kFamily != null;
  }

  /// Reset del pairing (elimina K_family e partner)
  Future<void> resetPairing() async {
    await _storage.delete(key: 'k_family');
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
    final myPublicKey = await _storage.read(key: 'my_public_key');
    if (myPublicKey == null) return null;

    // userId = SHA-256(publicKey)
    final bytes = utf8.encode(myPublicKey);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Salva la chiave pubblica dell'utente corrente
  Future<void> saveMyPublicKey(String publicKey) async {
    await _storage.write(key: 'my_public_key', value: publicKey);
  }

  /// Alias per getFamilyKey (per compatibilità)
  Future<String?> getKFamily() async {
    return await getFamilyKey();
  }

  /// Alias per resetPairing (per compatibilità)
  Future<void> clearPairing() async {
    await resetPairing();
  }

  /// Calcola l'ID della chat famiglia basato su K_family
  /// Questo è l'ID condiviso da entrambi gli utenti
  Future<String?> getFamilyChatId() async {
    final kFamily = await getFamilyKey();
    if (kFamily == null) return null;

    // family_chat_id = SHA-256(K_family)
    final bytes = utf8.encode(kFamily);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
