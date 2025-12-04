import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/message.dart';
import 'encryption_service.dart';

class AuthService extends ChangeNotifier {
  static const String baseUrl = 'https://private-messaging-backend-668509120760.europe-west1.run.app';
  final _storage = const FlutterSecureStorage();
  EncryptionService? _encryptionService;

  // Getter per accedere al servizio di crittografia
  EncryptionService? get encryptionService => _encryptionService;

  // Imposta il servizio di crittografia (deve essere chiamato all'inizio)
  void setEncryptionService(EncryptionService service) {
    _encryptionService = service;
  }

  User? _currentUser;
  String? _token;
  bool _isAuthenticated = false;

  User? get currentUser => _currentUser;
  String? get token => _token;
  bool get isAuthenticated => _isAuthenticated;

  // Inizializza il servizio controllando se c'è già un token salvato
  Future<void> initialize() async {
    _token = await _storage.read(key: 'jwt_token');
    if (_token != null) {
      final userJson = await _storage.read(key: 'user');
      if (userJson != null) {
        _currentUser = User.fromJson(json.decode(userJson));
        _isAuthenticated = true;

        // Carica la chiave privata
        final privateKey = await _storage.read(key: 'private_key');
        if (privateKey != null && _encryptionService != null) {
          _encryptionService!.loadPrivateKey(privateKey);
        }

        notifyListeners();
      }
    }
  }

  // Registrazione
  Future<bool> register(String username, String password) async {
    try {
      if (_encryptionService == null) {
        throw Exception('EncryptionService not initialized');
      }

      if (kDebugMode) print('🔐 Registrazione in corso per: $username');

      // Genera coppia di chiavi RSA
      if (kDebugMode) print('🔑 Generazione chiavi RSA...');
      final keyPair = await _encryptionService!.generateKeyPair();
      if (kDebugMode) print('✅ Chiavi RSA generate');

      if (kDebugMode) print('📡 Chiamata API: $baseUrl/api/auth/register');
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'password': password,
          'publicKey': keyPair['publicKey'],
        }),
      );

      if (kDebugMode) print('📥 Risposta server: ${response.statusCode}');
      if (kDebugMode) print('📄 Body: ${response.body}');

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        _token = data['token'];
        _currentUser = User.fromJson(data['user']);
        _isAuthenticated = true;

        // Salva token, user e chiave privata
        await _storage.write(key: 'jwt_token', value: _token);
        await _storage.write(key: 'user', value: json.encode(_currentUser!.toJson()));
        await _storage.write(key: 'private_key', value: keyPair['privateKey']!);

        if (kDebugMode) print('✅ Registrazione completata con successo!');
        notifyListeners();
        return true;
      }
      if (kDebugMode) print('❌ Registrazione fallita: status ${response.statusCode}');
      return false;
    } catch (e) {
      if (kDebugMode) print('❌ Register error: $e');
      return false;
    }
  }

  // Login
  Future<bool> login(String username, String password) async {
    try {
      if (kDebugMode) print('🔐 Login in corso per: $username');
      if (kDebugMode) print('📡 Chiamata API: $baseUrl/api/auth/login');

      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'password': password,
        }),
      );

      if (kDebugMode) print('📥 Risposta server: ${response.statusCode}');
      if (kDebugMode) print('📄 Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _token = data['token'];
        _currentUser = User.fromJson(data['user']);
        _isAuthenticated = true;

        // Salva token e user
        await _storage.write(key: 'jwt_token', value: _token);
        await _storage.write(key: 'user', value: json.encode(_currentUser!.toJson()));

        // La chiave privata dovrebbe essere già salvata dalla registrazione
        final privateKey = await _storage.read(key: 'private_key');
        if (privateKey != null && _encryptionService != null) {
          if (kDebugMode) print('🔑 Chiave privata caricata');
          _encryptionService!.loadPrivateKey(privateKey);
        } else {
          if (kDebugMode) print('⚠️ Chiave privata non trovata (normale per primo login)');
        }

        if (kDebugMode) print('✅ Login completato con successo!');
        notifyListeners();
        return true;
      }
      if (kDebugMode) print('❌ Login fallito: status ${response.statusCode}');
      return false;
    } catch (e) {
      if (kDebugMode) print('❌ Login error: $e');
      return false;
    }
  }

  // Logout
  Future<void> logout() async {
    _token = null;
    _currentUser = null;
    _isAuthenticated = false;

    await _storage.deleteAll();
    notifyListeners();
  }

  // Ottieni l'altro utente (il partner)
  Future<User?> getPartner() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/users/partner'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
      );

      if (response.statusCode == 200) {
        return User.fromJson(json.decode(response.body));
      }
      return null;
    } catch (e) {
      if (kDebugMode) print('Get partner error: $e');
      return null;
    }
  }
}
