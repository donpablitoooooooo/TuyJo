import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/message.dart';
import 'encryption_service.dart';

class ChatService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final EncryptionService _encryptionService = EncryptionService();
  
  final List<Message> _messages = [];
  StreamSubscription<QuerySnapshot>? _messagesSubscription;
  String? _currentUserId;

  List<Message> get messages => _messages;
  bool get isConnected => _messagesSubscription != null;

  // Inizializza il listener Firestore per i messaggi
  void connect(String token, String userId) {
    _currentUserId = userId;
    
    // Listener per messaggi inviati dall'utente corrente
    final sentQuery = _firestore
        .collection('messages')
        .where('senderId', isEqualTo: userId)
        .orderBy('timestamp', descending: false);
    
    // Listener per messaggi ricevuti dall'utente corrente
    final receivedQuery = _firestore
        .collection('messages')
        .where('receiverId', isEqualTo: userId)
        .orderBy('timestamp', descending: false);

    // Ascolta entrambe le query e combina i risultati
    _setupMessageListener(userId);
    
    if (kDebugMode) print('Connected to Firestore - listening for messages');
  }

  void _setupMessageListener(String userId) {
    // Ascolta tutti i messaggi dove l'utente è sender O receiver
    _messagesSubscription = _firestore
        .collection('messages')
        .where('senderId', isEqualTo: userId)
        .snapshots()
        .listen((snapshot) {
      _updateMessages(snapshot);
    });

    // Seconda subscription per i messaggi ricevuti
    _firestore
        .collection('messages')
        .where('receiverId', isEqualTo: userId)
        .snapshots()
        .listen((snapshot) {
      _updateMessages(snapshot);
    });
  }

  void _updateMessages(QuerySnapshot snapshot) {
    for (var change in snapshot.docChanges) {
      final message = Message.fromJson(change.doc.data() as Map<String, dynamic>);
      
      switch (change.type) {
        case DocumentChangeType.added:
          // Aggiungi solo se non esiste già
          if (!_messages.any((m) => m.id == message.id)) {
            _messages.add(message);
          }
          break;
        case DocumentChangeType.modified:
          // Aggiorna il messaggio esistente
          final index = _messages.indexWhere((m) => m.id == message.id);
          if (index != -1) {
            _messages[index] = message;
          }
          break;
        case DocumentChangeType.removed:
          // Rimuovi il messaggio
          _messages.removeWhere((m) => m.id == message.id);
          break;
      }
    }

    // Ordina per timestamp
    _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    notifyListeners();
  }

  // Disconnetti dal listener
  void disconnect() {
    _messagesSubscription?.cancel();
    _messagesSubscription = null;
    _currentUserId = null;
  }

  // Carica la cronologia messaggi (opzionale con listener)
  Future<void> loadMessages(String token) async {
    // Con i listener Firestore, questo metodo è opzionale
    // I messaggi verranno caricati automaticamente dal listener
    if (kDebugMode) print('Messages will be loaded via Firestore listener');
  }

  // Invia un messaggio scrivendo direttamente su Firestore
  Future<void> sendMessage(
    String content,
    String receiverId,
    String receiverPublicKey,
    String senderId,
  ) async {
    try {
      // Cripta il messaggio con la chiave pubblica del destinatario
      final encryptedContent = _encryptionService.encryptMessage(
        content,
        receiverPublicKey,
      );

      // Crea un nuovo documento con ID auto-generato
      final docRef = _firestore.collection('messages').doc();
      
      final message = {
        'id': docRef.id,
        'senderId': senderId,
        'receiverId': receiverId,
        'encryptedContent': encryptedContent,
        'timestamp': DateTime.now().toIso8601String(),
        'isDelivered': false,
        'isRead': false,
      };

      // Scrivi direttamente su Firestore
      await docRef.set(message);
      
      if (kDebugMode) print('Message sent to Firestore: ${docRef.id}');
    } catch (e) {
      if (kDebugMode) print('Send message error: $e');
      rethrow;
    }
  }

  // Decripta un messaggio
  String decryptMessage(String encryptedContent) {
    try {
      return _encryptionService.decryptMessage(encryptedContent);
    } catch (e) {
      if (kDebugMode) print('Decrypt error: $e');
      return '[Messaggio non decifrabile]';
    }
  }

  // Marca un messaggio come letto
  Future<void> markAsRead(String messageId) async {
    try {
      await _firestore.collection('messages').doc(messageId).update({
        'isRead': true,
        'readAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      if (kDebugMode) print('Mark as read error: $e');
    }
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
