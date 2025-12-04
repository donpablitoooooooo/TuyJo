import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:http/http.dart' as http;
import '../models/message.dart';
import 'auth_service.dart';
import 'encryption_service.dart';

class ChatService extends ChangeNotifier {
  static const String baseUrl = 'https://private-messaging-backend-668509120760.europe-west1.run.app';
  IO.Socket? _socket;
  final List<Message> _messages = [];
  EncryptionService? _encryptionService;

  List<Message> get messages => _messages;
  bool get isConnected => _socket?.connected ?? false;

  // Imposta il servizio di crittografia (deve essere chiamato dopo il login)
  void setEncryptionService(EncryptionService encryptionService) {
    _encryptionService = encryptionService;
  }

  // Connetti al server Socket.io
  void connect(String token, String userId) {
    _socket = IO.io(
      baseUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .enableAutoConnect()
          .build(),
    );

    _socket!.on('connect', (_) {
      if (kDebugMode) print('Connected to chat server');
      notifyListeners();
    });

    _socket!.on('disconnect', (_) {
      if (kDebugMode) print('Disconnected from chat server');
      notifyListeners();
    });

    _socket!.on('new_message', (data) {
      final message = Message.fromJson(data);
      _messages.add(message);
      _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      notifyListeners();
    });

    _socket!.on('message_delivered', (data) {
      final messageId = data['messageId'];
      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        _messages[index] = Message(
          id: _messages[index].id,
          senderId: _messages[index].senderId,
          receiverId: _messages[index].receiverId,
          encryptedContent: _messages[index].encryptedContent,
          timestamp: _messages[index].timestamp,
          isDelivered: true,
          isRead: _messages[index].isRead,
        );
        notifyListeners();
      }
    });

    _socket!.on('message_read', (data) {
      final messageId = data['messageId'];
      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        _messages[index] = Message(
          id: _messages[index].id,
          senderId: _messages[index].senderId,
          receiverId: _messages[index].receiverId,
          encryptedContent: _messages[index].encryptedContent,
          timestamp: _messages[index].timestamp,
          isDelivered: _messages[index].isDelivered,
          isRead: true,
        );
        notifyListeners();
      }
    });
  }

  // Disconnetti dal server
  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }

  // Carica la cronologia dei messaggi
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
      }
    } catch (e) {
      if (kDebugMode) print('Load messages error: $e');
    }
  }

  // Invia un messaggio
  Future<void> sendMessage(
    String content,
    String receiverId,
    String receiverPublicKey,
    String senderId,
  ) async {
    try {
      if (_encryptionService == null) {
        throw Exception('EncryptionService not initialized');
      }
      // Cripta il messaggio con la chiave pubblica del destinatario
      final encryptedContent = _encryptionService!.encryptMessage(
        content,
        receiverPublicKey,
      );

      final message = {
        'receiverId': receiverId,
        'encryptedContent': encryptedContent,
      };

      _socket?.emit('send_message', message);
    } catch (e) {
      if (kDebugMode) print('Send message error: $e');
    }
  }

  // Decripta un messaggio
  String decryptMessage(String encryptedContent) {
    try {
      if (_encryptionService == null) {
        throw Exception('EncryptionService not initialized');
      }
      return _encryptionService!.decryptMessage(encryptedContent);
    } catch (e) {
      if (kDebugMode) print('Decrypt error: $e');
      return '[Messaggio non decifrabile]';
    }
  }

  // Marca un messaggio come letto
  void markAsRead(String messageId) {
    _socket?.emit('mark_read', {'messageId': messageId});
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
