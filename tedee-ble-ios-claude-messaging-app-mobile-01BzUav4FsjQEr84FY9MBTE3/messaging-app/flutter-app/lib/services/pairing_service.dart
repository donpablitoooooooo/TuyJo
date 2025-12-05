import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Servizio per pairing via QR code e storage K_family
class PairingService extends ChangeNotifier {
  final _storage = const FlutterSecureStorage();

  String? _kFamily;
  String? _partnerUserId;
  String? _partnerNickname;
  bool _isPaired = false;

  String? get kFamily => _kFamily;
  String? get partnerUserId => _partnerUserId;
  String? get partnerNickname => _partnerNickname;
  bool get isPaired => _isPaired;

  /// Inizializza caricando dati salvati
  Future<void> initialize() async {
    try {
      _kFamily = await _storage.read(key: 'k_family');
      _partnerUserId = await _storage.read(key: 'partner_user_id');
      _partnerNickname = await _storage.read(key: 'partner_nickname');

      _isPaired = _kFamily != null && _partnerUserId != null;

      if (_isPaired) {
        if (kDebugMode) {
          print('✅ Pairing trovato:');
          print('   Partner: ${_partnerNickname ?? _partnerUserId}');
        }
      }

      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('❌ Errore caricamento pairing: $e');
    }
  }

  /// Genera dati QR per primo utente (contiene user_id + K_family)
  String generateQRData(String userId, String kFamily) {
    final data = {
      'user_id': userId,
      'k_family': kFamily,
    };
    return jsonEncode(data);
  }

  /// Genera dati QR per secondo utente (solo user_id)
  String generatePartnerQRData(String userId) {
    final data = {
      'user_id': userId,
    };
    return jsonEncode(data);
  }

  /// Scansiona QR del primo utente e salva K_family + partner_user_id
  Future<void> scanFirstUserQR(String qrData) async {
    try {
      final data = jsonDecode(qrData) as Map<String, dynamic>;
      final userId = data['user_id'] as String?;
      final kFamily = data['k_family'] as String?;

      if (userId == null || kFamily == null) {
        throw Exception('QR code invalido: mancano user_id o k_family');
      }

      // Salva K_family e partner_user_id
      await _storage.write(key: 'k_family', value: kFamily);
      await _storage.write(key: 'partner_user_id', value: userId);

      _kFamily = kFamily;
      _partnerUserId = userId;
      _isPaired = true;

      if (kDebugMode) {
        print('✅ QR primo utente scansionato:');
        print('   Partner ID: $userId');
        print('   K_family ricevuta');
      }

      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('❌ Errore scansione QR: $e');
      rethrow;
    }
  }

  /// Scansiona QR del secondo utente (solo user_id)
  Future<void> scanPartnerQR(String qrData) async {
    try {
      final data = jsonDecode(qrData) as Map<String, dynamic>;
      final userId = data['user_id'] as String?;

      if (userId == null) {
        throw Exception('QR code invalido: manca user_id');
      }

      // Salva partner_user_id
      await _storage.write(key: 'partner_user_id', value: userId);

      _partnerUserId = userId;
      _isPaired = _kFamily != null && _partnerUserId != null;

      if (kDebugMode) {
        print('✅ QR partner scansionato:');
        print('   Partner ID: $userId');
      }

      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('❌ Errore scansione QR partner: $e');
      rethrow;
    }
  }

  /// Salva K_family (per primo utente che la genera)
  Future<void> saveKFamily(String kFamily) async {
    await _storage.write(key: 'k_family', value: kFamily);
    _kFamily = kFamily;
    notifyListeners();

    if (kDebugMode) print('✅ K_family salvata');
  }

  /// Salva nickname locale per il partner
  Future<void> savePartnerNickname(String nickname) async {
    await _storage.write(key: 'partner_nickname', value: nickname);
    _partnerNickname = nickname;
    notifyListeners();

    if (kDebugMode) print('✅ Nickname partner salvato: $nickname');
  }

  /// Reset pairing (per debug/logout)
  Future<void> reset() async {
    await _storage.delete(key: 'k_family');
    await _storage.delete(key: 'partner_user_id');
    await _storage.delete(key: 'partner_nickname');

    _kFamily = null;
    _partnerUserId = null;
    _partnerNickname = null;
    _isPaired = false;

    notifyListeners();

    if (kDebugMode) print('🔄 Pairing reset');
  }
}
