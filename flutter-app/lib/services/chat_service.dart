import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/message.dart';
import 'encryption_service.dart';

class ChatService extends ChangeNotifier {
  static const String baseUrl = 'https://private-messaging-backend-668509120760.europe-west1.run.app';
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final List<Message> _messages = [];
  late final EncryptionService _encryptionService;
  StreamSubscription<QuerySnapshot>? _subscription;

  // Cache per i plaintext dei messaggi che inviamo (messageId -> plaintext)
  final Map<String, String> _sentMessagesCache = {};

  ChatService(this._encryptionService);

  List<Message> get messages => _messages;
  bool get isConnected => _subscription != null;

  // Connetti al Firestore listener per la chat
  void startListening(String familyChatId) {
    if (_subscription != null) {
      if (kDebugMode) print('Already listening to chat');
      return;
    }

    if (kDebugMode) print('🎧 Starting listener for chat: ${familyChatId.substring(0, 10)}...');

    _subscription = _firestore
        .collection('families')
        .doc(familyChatId)
        .collection('messages')
        .orderBy('created_at', descending: false)
        .snapshots()
        .listen(
      (snapshot) {
        for (var change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            final message = Message.fromFirestore(
              change.doc.id,
              change.doc.data()!,
            );

            // Aggiungi solo se non esiste già
            if (!_messages.any((m) => m.id == message.id)) {
              _messages.add(message);
              _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

              if (kDebugMode) {
                print('📨 New message: ${message.id}');
              }
            }
          }
        }
        notifyListeners();
      },
      onError: (error) {
        if (kDebugMode) print('Firestore listener error: $error');
      },
    );

    notifyListeners();
  }

  // Disconnetti dal listener
  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
    if (kDebugMode) print('🔇 Stopped listening to chat');
    notifyListeners();
  }

  // Carica la cronologia dei messaggi dall'API (per retrocompatibilità)
  Future<void> loadMessages(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/messages'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        _messages.clear();
        _messages.addAll(data.map((m) => Message.fromJson(m)).toList());
        _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        notifyListeners();

        if (kDebugMode) print('Loaded ${_messages.length} messages from API');
      }
    } catch (e) {
      if (kDebugMode) print('Load messages error: $e');
    }
  }

  /// Invia un messaggio cifrato con RSA hybrid encryption
  /// Ogni messaggio ha una chiave AES univoca, cifrata con la public key del destinatario
  Future<bool> sendMessage(
    String content,
    String familyChatId,
    String senderId,
    String recipientPublicKey,
  ) async {
    try {
      final timestamp = DateTime.now();

      // Costruisci il plaintext con sender, timestamp, type, body
      final plaintext = json.encode({
        'sender': senderId,
        'timestamp': timestamp.millisecondsSinceEpoch ~/ 1000,
        'type': 'text',
        'body': content,
      });

      // Cifra con hybrid RSA encryption (RSA per chiave AES, AES per messaggio)
      final encryptedPayload = _encryptionService.encryptMessage(
        plaintext,
        recipientPublicKey,
      );

      // Il payload è già un base64 che contiene {encryptedKey, iv, message}
      // Lo decodifichiamo per separare i componenti in Firestore
      final payloadBytes = base64Decode(encryptedPayload);
      final payloadJson = json.decode(utf8.decode(payloadBytes));

      // Scrivi nella chat condivisa
      final messageRef = _firestore
          .collection('families')
          .doc(familyChatId)
          .collection('messages')
          .doc();

      await messageRef.set({
        'sender_id': senderId,
        'encrypted_key': payloadJson['encryptedKey'], // Chiave AES cifrata con RSA
        'iv': payloadJson['iv'], // IV per AES
        'message': payloadJson['message'], // Messaggio cifrato con AES
        'created_at': timestamp.toIso8601String(),
      });

      // Salva il plaintext nella cache (così possiamo mostrarlo senza decifrarlo)
      _sentMessagesCache[messageRef.id] = content;

      if (kDebugMode) {
        print('✅ Message sent to chat: ${messageRef.id}');
        print('   Saved plaintext in cache for display');
      }
      return true;
    } catch (e) {
      if (kDebugMode) print('❌ Send message error: $e');
      return false;
    }
  }

  /// Decripta un messaggio usando la propria chiave privata RSA
  String decryptMessage(Message message) {
    try {
      // Se abbiamo il plaintext in cache (messaggio che abbiamo inviato noi),
      // usalo direttamente invece di provare a decifrarlo
      if (_sentMessagesCache.containsKey(message.id)) {
        final cachedPlaintext = _sentMessagesCache[message.id]!;
        if (kDebugMode) {
          print('✅ Using cached plaintext for sent message: ${message.id}');
        }
        return cachedPlaintext;
      }

      if (kDebugMode) {
        print('🔓 Decrypting message:');
        print('   Message ID: ${message.id}');
        print('   Encrypted key: ${message.encryptedKey?.substring(0, 20) ?? 'null'}...');
        print('   IV: ${message.iv}');
        print('   Message: ${message.encryptedMessage?.substring(0, 20) ?? 'null'}...');
      }

      // Ricostruisci il payload per decryptMessage
      final payload = {
        'encryptedKey': message.encryptedKey,
        'iv': message.iv,
        'message': message.encryptedMessage,
      };

      final encryptedPayload = base64Encode(utf8.encode(json.encode(payload)));

      // Decifra con la propria chiave privata RSA
      final plaintext = _encryptionService.decryptMessage(encryptedPayload);

      if (kDebugMode) print('✅ Decrypted plaintext: $plaintext');

      // Parse del plaintext JSON
      final data = json.decode(plaintext);
      return data['body'] ?? plaintext;
    } catch (e) {
      if (kDebugMode) print('❌ Decrypt error: $e');
      return '[Messaggio non decifrabile]';
    }
  }

  // Pulisci i messaggi
  void clearMessages() {
    _messages.clear();
    _sentMessagesCache.clear(); // Pulisci anche la cache
    notifyListeners();
  }

  // Elimina tutti i messaggi da Firestore per una famiglia
  Future<void> deleteAllMessages(String familyChatId) async {
    try {
      if (kDebugMode) print('🗑️ Deleting all messages for family: $familyChatId');

      final messagesRef = _firestore
          .collection('families')
          .doc(familyChatId)
          .collection('messages');

      // Ottieni tutti i messaggi
      final snapshot = await messagesRef.get();

      if (kDebugMode) print('Found ${snapshot.docs.length} messages to delete');

      // Elimina tutti i messaggi in batch
      final batch = _firestore.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (kDebugMode) print('✅ All messages deleted from Firestore');
    } catch (e) {
      if (kDebugMode) print('❌ Error deleting messages: $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    stopListening();
    super.dispose();
  }
}
