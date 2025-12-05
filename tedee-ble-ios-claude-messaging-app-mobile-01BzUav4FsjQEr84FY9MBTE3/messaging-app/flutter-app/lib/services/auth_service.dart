import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'encryption_service.dart';

/// Servizio di autenticazione con challenge/response
class AuthService extends ChangeNotifier {
  static const String baseUrl = 'https://private-messaging-backend-668509120760.europe-west1.run.app';
  final _storage = const FlutterSecureStorage();
  final _encryptionService = EncryptionService();

  String? _userId;
  String? _token;
  bool _isAuthenticated = false;

  String? get userId => _userId;
  String? get token => _token;
  bool get isAuthenticated => _isAuthenticated;
  EncryptionService get encryptionService => _encryptionService;

  /// Inizializza il servizio controllando se c'è già un token salvato
  Future<void> initialize() async {
    try {
      _token = await _storage.read(key: 'jwt_token');
      _userId = await _storage.read(key: 'user_id');

      if (_token != null && _userId != null) {
        // Carica chiave privata
        final privateKey = await _storage.read(key: 'private_key');
        if (privateKey != null) {
          try {
            _encryptionService.loadPrivateKey(privateKey);
            _isAuthenticated = true;
            if (kDebugMode) {
              print('✅ Sessione ripristinata');
              print('   User ID: $_userId');
            }
          } catch (e) {
            if (kDebugMode) print('❌ Chiave privata corrotta: $e');
            await logout();
            return;
          }
        } else {
          if (kDebugMode) print('⚠️ Manca chiave privata');
          await logout();
          return;
        }

        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) print('❌ Errore initialize: $e');
      await logout();
    }
  }

  /// Registrazione - genera RSA keypair e registra sul server
  /// Ritorna: {user_id, private_key} da mostrare all'utente
  Future<Map<String, String>?> register() async {
    try {
      if (kDebugMode) print('🔐 Inizio registrazione');

      // Genera coppia di chiavi RSA
      if (kDebugMode) print('🔑 Generazione chiavi RSA...');
      final keyPair = await _encryptionService.generateKeyPair();
      final publicKey = keyPair['publicKey']!;
      final privateKey = keyPair['privateKey']!;

      if (kDebugMode) print('✅ Chiavi RSA generate');

      // Calcola user_id = SHA-256(publicKey)
      final calculatedUserId = _encryptionService.getUserId(publicKey);
      if (kDebugMode) print('🆔 User ID: $calculatedUserId');

      // Registra sul server
      if (kDebugMode) print('📡 Invio richiesta di registrazione...');
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'publicKey': publicKey}),
      );

      if (kDebugMode) {
        print('📥 Risposta server: ${response.statusCode}');
        print('📄 Body: ${response.body}');
      }

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        _token = data['token'];
        _userId = data['user_id'];
        _isAuthenticated = true;

        // Verifica che user_id del server corrisponda
        if (_userId != calculatedUserId) {
          if (kDebugMode) {
            print('⚠️ User ID mismatch!');
            print('   Calcolato: $calculatedUserId');
            print('   Server: $_userId');
          }
        }

        // Salva token, user_id, chiave privata
        await _storage.write(key: 'jwt_token', value: _token);
        await _storage.write(key: 'user_id', value: _userId);
        await _storage.write(key: 'private_key', value: privateKey);

        if (kDebugMode) print('✅ Registrazione completata!');

        notifyListeners();

        return {
          'user_id': _userId!,
          'private_key': privateKey,
        };
      } else {
        final error = json.decode(response.body)['error'] ?? 'Unknown error';
        throw Exception(error);
      }
    } catch (e) {
      if (kDebugMode) print('❌ Errore registrazione: $e');
      return null;
    }
  }

  /// Login con challenge/response
  Future<bool> login(String privateKey) async {
    try {
      if (kDebugMode) print('🔐 Inizio login');

      // Carica chiave privata
      _encryptionService.loadPrivateKey(privateKey);

      // Ricava publicKey e user_id
      final publicKey = _encryptionService.getPublicKey();
      final calculatedUserId = _encryptionService.getUserId(publicKey);

      if (kDebugMode) print('🆔 User ID: $calculatedUserId');

      // Step 1: Richiedi challenge
      if (kDebugMode) print('📡 Richiesta challenge...');
      final challengeResponse = await http.post(
        Uri.parse('$baseUrl/api/auth/request'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'user_id': calculatedUserId}),
      );

      if (challengeResponse.statusCode != 200) {
        final error =
            json.decode(challengeResponse.body)['error'] ?? 'Challenge failed';
        throw Exception(error);
      }

      final challengeData = json.decode(challengeResponse.body);
      final challenge = challengeData['challenge'] as String;

      if (kDebugMode) print('✅ Challenge ricevuto');

      // Step 2: Firma challenge
      if (kDebugMode) print('🔏 Firma challenge...');
      final signature = _encryptionService.signChallenge(challenge);

      // Step 3: Verifica firma e ottieni JWT
      if (kDebugMode) print('📡 Verifica firma...');
      final verifyResponse = await http.post(
        Uri.parse('$baseUrl/api/auth/verify'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'user_id': calculatedUserId,
          'signature': signature,
        }),
      );

      if (verifyResponse.statusCode != 200) {
        final error =
            json.decode(verifyResponse.body)['error'] ?? 'Verification failed';
        throw Exception(error);
      }

      final verifyData = json.decode(verifyResponse.body);
      _token = verifyData['token'];
      _userId = verifyData['user_id'];
      _isAuthenticated = true;

      // Salva tutto
      await _storage.write(key: 'jwt_token', value: _token);
      await _storage.write(key: 'user_id', value: _userId);
      await _storage.write(key: 'private_key', value: privateKey);

      if (kDebugMode) print('✅ Login completato!');

      notifyListeners();
      return true;
    } catch (e) {
      if (kDebugMode) print('❌ Errore login: $e');
      return false;
    }
  }

  /// Logout
  Future<void> logout() async {
    _token = null;
    _userId = null;
    _isAuthenticated = false;

    await _storage.delete(key: 'jwt_token');
    await _storage.delete(key: 'user_id');
    await _storage.delete(key: 'private_key');

    if (kDebugMode) print('👋 Logout completato');

    notifyListeners();
  }
}
