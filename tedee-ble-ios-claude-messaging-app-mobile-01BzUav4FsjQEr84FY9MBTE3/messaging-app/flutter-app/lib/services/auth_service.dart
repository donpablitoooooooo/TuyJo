import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/message.dart';
import 'encryption_service.dart';

class AuthService extends ChangeNotifier {
  static const String baseUrl = 'https://private-messaging-backend-668509120760.europe-west1.run.app';
  final _storage = const FlutterSecureStorage();
  final _encryptionService = EncryptionService();

  User? _currentUser;
  String? _token;
  bool _isAuthenticated = false;

  User? get currentUser => _currentUser;
  String? get token => _token;
  bool get isAuthenticated => _isAuthenticated;
  EncryptionService get encryptionService => _encryptionService;

  // Inizializza il servizio controllando se c'è già un token salvato
  Future<void> initialize() async {
    try {
      _token = await _storage.read(key: 'jwt_token');
      if (_token != null) {
        final userJson = await _storage.read(key: 'user');
        if (userJson != null) {
          _currentUser = User.fromJson(json.decode(userJson));

          // Carica la chiave privata se presente (da sessione precedente)
          final privateKey = await _storage.read(key: 'private_key');
          if (privateKey != null) {
            try {
              _encryptionService.loadPrivateKey(privateKey);
              _isAuthenticated = true;
              if (kDebugMode) print('✅ Sessione ripristinata con chiave privata');
            } catch (e) {
              if (kDebugMode) {
                print('❌ Chiave privata corrotta: $e');
                print('💡 Richiesta nuova autenticazione con chiave valida');
              }
              // Chiave corrotta - cancella tutto e richiedi login
              await logout();
              return;
            }
          } else {
            // Token valido ma nessuna chiave privata - richiedi login con chiave
            if (kDebugMode) print('⚠️ Sessione incompleta - manca chiave privata');
            await logout();
            return;
          }

          notifyListeners();
        }
      }
    } catch (e) {
      if (kDebugMode) print('❌ Errore durante initialize: $e');
      await logout();
    }
  }

  // Registrazione - solo username, genera chiavi e restituisce la privata
  Future<String?> register(String username) async {
    try {
      if (kDebugMode) print('🔐 Inizio registrazione per: $username');

      // Genera coppia di chiavi RSA
      if (kDebugMode) print('🔑 Generazione chiavi RSA...');
      final keyPair = await _encryptionService.generateKeyPair();
      if (kDebugMode) print('✅ Chiavi RSA generate con successo');

      if (kDebugMode) print('📡 Invio richiesta di registrazione al server...');
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'publicKey': keyPair['publicKey'],
        }),
      );

      if (kDebugMode) {
        print('📥 Risposta server: ${response.statusCode}');
        print('📄 Body: ${response.body}');
      }

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        _token = data['token'];
        _currentUser = User.fromJson(data['user']);
        _isAuthenticated = true;

        // Salva token e user (MA NON la chiave privata - quella va gestita manualmente!)
        await _storage.write(key: 'jwt_token', value: _token);
        await _storage.write(key: 'user', value: json.encode(_currentUser!.toJson()));

        if (kDebugMode) print('✅ Registrazione completata - chiave privata da salvare manualmente!');

        notifyListeners();

        // Restituisci la chiave privata da mostrare all'utente
        return keyPair['privateKey'];
      }

      if (kDebugMode) print('❌ Registrazione fallita: status ${response.statusCode}');
      return null;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('❌ Errore registrazione: $e');
        print('📍 Stack trace: $stackTrace');
      }
      return null;
    }
  }

  // Login - solo username e chiave privata
  Future<bool> login(String username, String privateKey) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
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

        // Carica la chiave privata fornita dall'utente
        try {
          _encryptionService.loadPrivateKey(privateKey);
          // Salva la chiave privata per questa sessione
          await _storage.write(key: 'private_key', value: privateKey);
          if (kDebugMode) print('✅ Chiave privata caricata e salvata per la sessione');
        } catch (e) {
          if (kDebugMode) {
            print('❌ Errore caricamento chiave privata: $e');
            print('💡 La chiave privata fornita non è valida');
          }
          // Chiave invalida - cancella tutto
          await logout();
          throw Exception('Chiave privata non valida');
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
