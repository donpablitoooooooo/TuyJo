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
  StreamSubscription<QuerySnapshot>? _inboxSubscription;

  List<Message> get messages => _messages;
  bool get isConnected => _inboxSubscription != null;

  // Connetti al Firestore listener per la chat famiglia
  void startListening(String familyChatId) {
    if (_inboxSubscription != null) {
      if (kDebugMode) print('Already listening to family chat');
      return;
    }

    if (kDebugMode) print('Starting Firestore listener for family: $familyChatId');

    // Ascolta i messaggi nella chat famiglia
    _inboxSubscription = _firestore
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
                print('New message received: ${message.id}');
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
    _inboxSubscription?.cancel();
    _inboxSubscription = null;
    if (kDebugMode) print('Stopped listening to inbox');
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

  // Decripta un messaggio con K_family
  String decryptMessage(Message message, String kFamilyBase64) {
    try {
      // Decifra con K_family usando AES-GCM
      final plaintext = _encryptionService.decryptWithFamilyKey(
        message.ciphertext,
        message.nonce,
        message.tag,
        kFamilyBase64,
      );

      // Parse del plaintext JSON
      final data = json.decode(plaintext);
      return data['body'] ?? plaintext;
    } catch (e) {
      if (kDebugMode) print('Decrypt error: $e');
      return '[Messaggio non decifrabile]';
    }
  }

  // Pulisci i messaggi
  void clearMessages() {
    _messages.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    stopListening();
    super.dispose();
  }
}
