import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/pairing_service.dart';
import '../models/message.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  String? _partnerPublicKey;
  String? _kFamily;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final chatService = Provider.of<ChatService>(context, listen: false);
    final pairingService = Provider.of<PairingService>(context, listen: false);

    // Ottieni K_family e chiave pubblica del partner
    _kFamily = await pairingService.getFamilyKey();
    _partnerPublicKey = pairingService.partnerPublicKey;

    // Avvia il listener Firestore per i messaggi in arrivo
    chatService.startListening(authService.currentUser!.id);

    setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _messageController.dispose();
    final chatService = Provider.of<ChatService>(context, listen: false);
    chatService.stopListening();
    super.dispose();
  }

  void _sendMessage() async {
    if (_messageController.text.trim().isEmpty || _partnerPublicKey == null || _kFamily == null) {
      if (kDebugMode) {
        print('⚠️ Cannot send message:');
        print('  - Text empty: ${_messageController.text.trim().isEmpty}');
        print('  - Partner key null: ${_partnerPublicKey == null}');
        print('  - K_family null: ${_kFamily == null}');
      }
      return;
    }

    final authService = Provider.of<AuthService>(context, listen: false);
    final chatService = Provider.of<ChatService>(context, listen: false);
    final pairingService = Provider.of<PairingService>(context, listen: false);

    // Calcola l'ID del partner (SHA-256 della chiave pubblica)
    final partnerId = pairingService.getPartnerId();
    if (partnerId == null) {
      if (kDebugMode) print('❌ Partner ID is null!');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Errore: partner non trovato')),
        );
      }
      return;
    }

    if (kDebugMode) print('📤 Sending message to partner: $partnerId');

    final success = await chatService.sendMessage(
      _messageController.text.trim(),
      authService.currentUser!.id,
      partnerId, // Usa l'ID del partner, non la chiave pubblica!
      authService.token!,
      _kFamily!,
    );

    if (success) {
      _messageController.clear();
      if (kDebugMode) print('✅ Message sent successfully');
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Errore nell\'invio del messaggio')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final chatService = Provider.of<ChatService>(context);

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Family Chat'),
        actions: [
          IconButton(
            icon: Icon(
              _kFamily != null ? Icons.lock : Icons.lock_open,
              color: _kFamily != null ? Colors.green : Colors.orange,
            ),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              chatService.stopListening();
              await authService.logout();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: chatService.messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 80,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Nessun messaggio',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Invia il primo messaggio crittografato!',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: chatService.messages.length,
                    itemBuilder: (context, index) {
                      final message = chatService.messages[index];

                      // Decripta il messaggio
                      String decryptedContent = '[Messaggio crittografato]';
                      bool isMe = false;

                      try {
                        if (_kFamily != null) {
                          final plaintext = chatService.decryptMessage(
                            message,
                            _kFamily!,
                          );

                          // Estrai il sender dal JSON decriptato
                          final payload = json.decode(plaintext);
                          final senderId = payload['sender'] as String?;
                          isMe = senderId == authService.currentUser!.id;
                          decryptedContent = payload['body'] as String? ?? plaintext;
                        }
                      } catch (e) {
                        decryptedContent = '[Errore decrittazione]';
                      }

                      return _MessageBubble(
                        message: decryptedContent,
                        timestamp: message.timestamp,
                        isMe: isMe,
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
                  spreadRadius: 1,
                  blurRadius: 5,
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: 'Scrivi un messaggio...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    maxLines: null,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _sendMessage,
                  icon: const Icon(Icons.send),
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final String message;
  final DateTime timestamp;
  final bool isMe;

  const _MessageBubble({
    required this.message,
    required this.timestamp,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isMe
              ? Theme.of(context).colorScheme.primary
              : Colors.grey[300],
          borderRadius: BorderRadius.circular(20),
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: TextStyle(
                color: isMe ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat('HH:mm').format(timestamp),
              style: TextStyle(
                fontSize: 10,
                color: isMe ? Colors.white70 : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
