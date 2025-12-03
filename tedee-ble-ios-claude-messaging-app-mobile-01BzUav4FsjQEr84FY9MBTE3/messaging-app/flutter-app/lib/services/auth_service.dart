import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/message.dart';
import 'encryption_service.dart';

class AuthService extends ChangeNotifier {
  static const String baseUrl = 'YOUR_BACKEND_URL'; // Sostituire con l'URL del backend
  final _storage = const FlutterSecureStorage();
  final _encryptionService = EncryptionService();

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
        if (privateKey != null) {
          _encryptionService.loadPrivateKey(privateKey);
        }

        notifyListeners();
      }
    }
  }

  // Registrazione
  Future<bool> register(String username, String password) async {
    try {
      // Genera coppia di chiavi RSA
      final keyPair = await _encryptionService.generateKeyPair();

      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'password': password,
          'publicKey': keyPair['publicKey'],
        }),
      );

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        _token = data['token'];
        _currentUser = User.fromJson(data['user']);
        _isAuthenticated = true;

        // Salva token, user e chiave privata
        await _storage.write(key: 'jwt_token', value: _token);
        await _storage.write(key: 'user', value: json.encode(_currentUser!.toJson()));
        await _storage.write(key: 'private_key', value: keyPair['privateKey']!);

        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      if (kDebugMode) print('Register error: $e');
      return false;
    }
  }

  // Login
  Future<bool> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'password': password,
        }),
      );

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
        if (privateKey != null) {
          _encryptionService.loadPrivateKey(privateKey);
        }

        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      if (kDebugMode) print('Login error: $e');
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
