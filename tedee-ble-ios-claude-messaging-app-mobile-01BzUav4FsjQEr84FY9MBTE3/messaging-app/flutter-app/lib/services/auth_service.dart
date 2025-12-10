import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import '../models/message.dart';
import 'encryption_service.dart';

class AuthService extends ChangeNotifier {
  static const String baseUrl = 'https://private-messaging-backend-668509120760.europe-west1.run.app';
  final _storage = const FlutterSecureStorage();
  final _encryptionService = EncryptionService();
  final _firebaseAuth = firebase_auth.FirebaseAuth.instance;

  User? _currentUser;
  String? _backendToken;
  bool _isAuthenticated = false;
  String? _lastError;

  User? get currentUser => _currentUser;
  String? get backendToken => _backendToken;
  String? get token => _backendToken; // Compatibilità backward
  bool get isAuthenticated => _isAuthenticated;
  String? get firebaseUid => _firebaseAuth.currentUser?.uid;
  String? get lastError => _lastError;

  // Inizializza il servizio controllando se c'è già un token salvato
  Future<void> initialize() async {
    _backendToken = await _storage.read(key: 'backend_token');
    if (_backendToken != null) {
      final userJson = await _storage.read(key: 'user');
      if (userJson != null) {
        _currentUser = User.fromJson(json.decode(userJson));
        _isAuthenticated = true;

        // Carica la chiave privata
        final privateKey = await _storage.read(key: 'private_key');
        if (privateKey != null) {
          _encryptionService.loadPrivateKey(privateKey);
        }

        // Verifica se Firebase è autenticato
        if (_firebaseAuth.currentUser == null) {
          // Se non è autenticato, prova a rifare il login
          await _reAuthenticateFirebase();
        }

        notifyListeners();
      }
    }
  }

  // Re-autentica Firebase se la sessione è scaduta
  Future<void> _reAuthenticateFirebase() async {
    try {
      final publicKey = await _storage.read(key: 'public_key');
      if (publicKey != null) {
        await login(publicKey);
      }
    } catch (e) {
      if (kDebugMode) print('Firebase re-authentication failed: $e');
    }
  }

  // Registrazione con chiave pubblica
  Future<bool> register() async {
    try {
      if (kDebugMode) print('🔑 Generating RSA key pair...');

      // Genera coppia di chiavi RSA
      final keyPair = await _encryptionService.generateKeyPair();
      final publicKey = keyPair['publicKey']!;

      if (kDebugMode) print('🌐 Calling backend API: $baseUrl/api/auth/register');

      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'publicKey': publicKey,
        }),
      ).timeout(const Duration(seconds: 10));

      if (kDebugMode) print('📡 Backend response status: ${response.statusCode}');

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        _backendToken = data['backend_token'];
        final firebaseToken = data['firebase_token'];
        _currentUser = User.fromJson(data['user']);

        if (kDebugMode) print('🔥 Authenticating with Firebase...');

        // TEMPORARY: Test with Anonymous Auth instead of Custom Token
        try {
          await _firebaseAuth.signInAnonymously();
          if (kDebugMode) print('✅ Anonymous auth successful!');
        } catch (e) {
          if (kDebugMode) print('❌ Anonymous auth failed: $e');
          // Fallback to Custom Token
          if (kDebugMode) print('🔥 Trying Custom Token...');
          await _firebaseAuth.signInWithCustomToken(firebaseToken);
        }

        _isAuthenticated = true;

        // Salva token, user, chiave privata e pubblica
        await _storage.write(key: 'backend_token', value: _backendToken);
        await _storage.write(key: 'user', value: json.encode(_currentUser!.toJson()));
        await _storage.write(key: 'private_key', value: keyPair['privateKey']!);
        await _storage.write(key: 'public_key', value: publicKey);

        if (kDebugMode) print('✅ Registration successful! User ID: ${_currentUser!.id}');

        _lastError = null;
        notifyListeners();
        return true;
      } else {
        _lastError = 'Backend error: ${response.statusCode} - ${response.body}';
        if (kDebugMode) print('❌ $_lastError');
        return false;
      }
    } catch (e) {
      _lastError = e.toString();
      if (kDebugMode) print('❌ Register error: $e');
      return false;
    }
  }

  // Login con chiave pubblica
  Future<bool> login(String publicKey) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'publicKey': publicKey,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _backendToken = data['backend_token'];
        final firebaseToken = data['firebase_token'];
        _currentUser = User.fromJson(data['user']);

        // Autentica a Firebase con Custom Token
        await _firebaseAuth.signInWithCustomToken(firebaseToken);
        _isAuthenticated = true;

        // Salva token e user
        await _storage.write(key: 'backend_token', value: _backendToken);
        await _storage.write(key: 'user', value: json.encode(_currentUser!.toJson()));

        // Carica la chiave privata (dovrebbe essere già salvata dalla registrazione)
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
    _backendToken = null;
    _currentUser = null;
    _isAuthenticated = false;

    // Logout da Firebase
    await _firebaseAuth.signOut();

    await _storage.deleteAll();
    notifyListeners();
  }

  // Ottieni lista utenti (escluso se stesso)
  Future<List<User>> getUsers() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/users'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_backendToken',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((u) => User.fromJson(u)).toList();
      }
      return [];
    } catch (e) {
      if (kDebugMode) print('Get users error: $e');
      return [];
    }
  }

  // Ottieni un utente specifico
  Future<User?> getUserById(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/users/$userId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_backendToken',
        },
      );

      if (response.statusCode == 200) {
        return User.fromJson(json.decode(response.body));
      }
      return null;
    } catch (e) {
      if (kDebugMode) print('Get user error: $e');
      return null;
    }
  }
}
