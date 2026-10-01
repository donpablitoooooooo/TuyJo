import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'encryption_service.dart';

/// Ingresso di questo telefono nella sua chat.
///
/// Le regole di Firestore e Storage lasciano entrare in `families/{id}` solo
/// i login anonimi registrati come membri. Per registrarsi il telefono firma
/// con la propria chiave privata un testo che contiene la chat, il proprio
/// uid e l'ora; la Cloud Function joinFamily verifica la firma con la chiave
/// pubblica e aggiunge l'uid (functions/membership.js).
///
/// Va fatto prima di ogni accesso alla chat: all'avvio ([ready]), dopo un
/// abbinamento e dopo un recupero ([ensureJoined] con `force`). Se il login
/// anonimo è lo stesso dell'ultima volta e la chat pure, non serve la rete.
class MembershipService {
  MembershipService._();
  static final MembershipService instance = MembershipService._();

  static const String _endpoint =
      'https://europe-west1-youandme-b3b4c.cloudfunctions.net/joinFamily';
  static const String _prefsKey = 'membership_joined';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  /// Stesso testo di joinMessage in functions/membership.js.
  static String joinMessage(String familyId, String uid, int timestamp) =>
      'tuijo-join|v1|$familyId|$uid|$timestamp';

  static String familyIdOf(String a, String b) {
    final keys = [a, b]..sort();
    return sha256.convert(utf8.encode(keys.join('|'))).toString();
  }

  Future<void>? _ready;
  Timer? _retry;

  /// Completa quando il login anonimo e l'ingresso nella chat sono stati
  /// tentati (riusciti o no: non lancia mai). Chi legge o scrive la chat
  /// all'avvio aspetta questo.
  Future<void> get ready => _ready ??= _prepare();

  /// Chiamato quando un ingresso riesce dopo un primo tentativo fallito
  /// (avvio senza rete): i listener partiti nel frattempo erano stati
  /// rifiutati e vanno riavviati.
  VoidCallback? onLateJoin;

  Future<void> _prepare() async {
    await ensureSignedIn();
    final ok = await ensureJoined();
    if (!ok) _scheduleRetry();
  }

  void _scheduleRetry() {
    _retry?.cancel();
    _retry = Timer.periodic(const Duration(seconds: 20), (timer) async {
      if (await ensureJoined()) {
        timer.cancel();
        onLateJoin?.call();
      }
    });
  }

  Future<User?> ensureSignedIn() async {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser != null) return auth.currentUser;
    try {
      final cred = await auth.signInAnonymously().timeout(const Duration(seconds: 10));
      if (kDebugMode) print('🔐 [MEMBERSHIP] anon sign-in ${cred.user?.uid.substring(0, 6)}');
      return cred.user;
    } catch (e) {
      if (kDebugMode) print('⚠️ [MEMBERSHIP] anon sign-in failed: $e');
      return null;
    }
  }

  /// Registra il login anonimo come membro della chat di questo telefono.
  /// true se è già membro o se lo è diventato; true anche se non c'è niente
  /// da fare (telefono non abbinato). [force] ignora la cache: da usare
  /// quando la chat è appena cambiata (abbinamento, recupero).
  Future<bool> ensureJoined({bool force = false}) async {
    try {
      final priv = await _storage.read(key: 'rsa_private_key');
      final pub = await _storage.read(key: 'rsa_public_key');
      final partner = await _storage.read(key: 'partner_public_key');
      if (priv == null || pub == null || partner == null) return true;

      final user = await ensureSignedIn();
      if (user == null) return false;
      final familyId = familyIdOf(pub, partner);
      final marker = '${user.uid}|$familyId';

      final prefs = await SharedPreferences.getInstance();
      if (!force && prefs.getString(_prefsKey) == marker) return true;

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final signature = EncryptionService().signSha256(
        joinMessage(familyId, user.uid, timestamp),
        privateKeyStr: priv,
      );
      final idToken = await user.getIdToken();
      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: json.encode({
              'publicKey': pub,
              'partnerPublicKey': partner,
              'timestamp': timestamp,
              'signature': signature,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        if (kDebugMode) {
          print('⚠️ [MEMBERSHIP] join refused: ${response.statusCode} ${response.body}');
        }
        return false;
      }
      await prefs.setString(_prefsKey, marker);
      if (kDebugMode) print('🔐 [MEMBERSHIP] joined ${familyId.substring(0, 8)}: ${response.body}');
      return true;
    } catch (e) {
      if (kDebugMode) print('⚠️ [MEMBERSHIP] join failed: $e');
      return false;
    }
  }

  /// Dopo un disabbinamento o una cancellazione: la prossima chat va
  /// registrata da capo.
  Future<void> forget() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}
