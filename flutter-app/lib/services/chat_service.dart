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
  final EncryptionService _encryptionService = EncryptionService();
  final List<StreamSubscription<QuerySnapshot>> _subscriptions = [];
  final Map<String, String> _chatIdToKFamily = {}; // Mappa family_chat_id -> K_family
  final Map<String, String> _messageIdToChatId = {}; // Mappa message_id -> family_chat_id

  List<Message> get messages => _messages;
  bool get isConnected => _subscriptions.isNotEmpty;

  // Connetti al Firestore listener per multiple chat (corrente + storiche)
  void startListeningMultiple(List<String> familyChatIds, List<String> kFamilies) {
    if (_subscriptions.isNotEmpty) {
      if (kDebugMode) print('Already listening to chats');
      return;
    }

    if (familyChatIds.length != kFamilies.length) {
      if (kDebugMode) print('❌ Mismatch between chat IDs and K_families');
      return;
    }

    if (kDebugMode) print('🎧 Starting listeners for ${familyChatIds.length} chat(s)');

    // Crea mappa chat_id -> k_family per decifratura
    for (var i = 0; i < familyChatIds.length; i++) {
      _chatIdToKFamily[familyChatIds[i]] = kFamilies[i];
    }

    // Crea un listener per ogni chat
    for (var familyChatId in familyChatIds) {
      if (kDebugMode) print('   📡 Listening to chat: ${familyChatId.substring(0, 10)}...');

      final subscription = _firestore
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

                // Salva il mapping message_id -> family_chat_id per la decifratura
                _messageIdToChatId[message.id] = familyChatId;

                if (kDebugMode) {
                  print('📨 New message from chat ${familyChatId.substring(0, 8)}: ${message.id}');
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

      _subscriptions.add(subscription);
    }

    notifyListeners();
  }

  // Connetti al Firestore listener per una singola chat (retrocompatibilità)
  // Deprecato: usa startListeningMultiple per supportare storico
  void startListening(String familyChatId) {
    if (kDebugMode) print('⚠️ startListening is deprecated, use startListeningMultiple');
    // Per retrocompatibilità, crea una lista con solo questa chat
    // Ma non abbiamo la K_family qui, quindi questo non funzionerà bene
    // Manteniamo solo per non rompere il codice esistente
  }

  // Disconnetti da tutti i listener
  void stopListening() {
    for (var subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    _chatIdToKFamily.clear();
    _messageIdToChatId.clear();
    if (kDebugMode) print('🔇 Stopped listening to all chats');
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

  // Invia un messaggio cifrato con K_family alla chat famiglia
  Future<bool> sendMessage(
    String content,
    String familyChatId,
    String senderId,
    String kFamilyBase64,
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

      // Cifra con K_family usando AES-GCM
      final encrypted = _encryptionService.encryptWithFamilyKey(
        plaintext,
        kFamilyBase64,
      );

      // Scrivi nella chat famiglia condivisa
      final messageRef = _firestore
          .collection('families')
          .doc(familyChatId)
          .collection('messages')
          .doc();

      await messageRef.set({
        'sender_id': senderId,
        'ciphertext': encrypted['ciphertext'],
        'nonce': encrypted['nonce'],
        'tag': encrypted['tag'],
        'created_at': timestamp.toIso8601String(),
      });

      if (kDebugMode) print('✅ Message sent to family chat: ${messageRef.id}');
      return true;
    } catch (e) {
      if (kDebugMode) print('❌ Send message error: $e');
      return false;
    }
  }

  // Decripta un messaggio usando automaticamente la K_family corretta
  String decryptMessageAuto(Message message) {
    try {
      // Trova il family_chat_id per questo messaggio
      final familyChatId = _messageIdToChatId[message.id];
      if (familyChatId == null) {
        if (kDebugMode) print('❌ No chat ID found for message ${message.id}');
        return '[Messaggio non decifrabile]';
      }

      // Trova la K_family per questa chat
      final kFamily = _chatIdToKFamily[familyChatId];
      if (kFamily == null) {
        if (kDebugMode) print('❌ No K_family found for chat $familyChatId');
        return '[Messaggio non decifrabile]';
      }

      // Decifra usando la K_family corretta
      return decryptMessage(message, kFamily);
    } catch (e) {
      if (kDebugMode) print('❌ Auto-decrypt error: $e');
      return '[Messaggio non decifrabile]';
    }
  }

  // Decripta un messaggio con K_family specifica (per retrocompatibilità)
  String decryptMessage(Message message, String kFamilyBase64) {
    try {
      if (kDebugMode) {
        print('🔓 Decrypting message:');
        print('   Message ID: ${message.id}');
        print('   Ciphertext: ${message.ciphertext.substring(0, 20)}...');
        print('   Nonce: ${message.nonce}');
        print('   Tag: ${message.tag}');
        print('   K_family: ${kFamilyBase64.substring(0, 10)}...');
      }

      // Decifra con K_family usando AES-GCM
      final plaintext = _encryptionService.decryptWithFamilyKey(
        message.ciphertext,
        message.nonce,
        message.tag,
        kFamilyBase64,
      );

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
