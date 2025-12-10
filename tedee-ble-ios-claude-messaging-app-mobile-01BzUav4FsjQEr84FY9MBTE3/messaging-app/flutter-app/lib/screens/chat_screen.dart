import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/pairing_service.dart';
import '../services/chat_service.dart';
import '../models/message.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  bool _isLoading = true;
  String? _myUserId;
  String? _partnerUserId;
  String? _kFamily;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final pairingService = Provider.of<PairingService>(context, listen: false);
    final chatService = Provider.of<ChatService>(context, listen: false);

    // Ottieni K_family e partner ID
    _kFamily = await pairingService.getKFamily();
    _partnerUserId = await pairingService.getPartnerId();
    _myUserId = await pairingService.getMyUserId();

    print('🔍 Chat initialization:');
    print('   My User ID: $_myUserId');
    print('   Partner User ID: $_partnerUserId');
    print('   K_family: ${_kFamily != null ? "${_kFamily!.substring(0, 10)}..." : "null"}');

    if (_myUserId != null) {
      // Avvia il listener Firestore
      chatService.startListening(_myUserId!);
      print('✅ Firestore listener started for user: $_myUserId');
    } else {
      print('❌ Cannot start listener - myUserId is null');
    }

    setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _sendMessage() async {
    if (_messageController.text.trim().isEmpty) {
      print('❌ Message is empty');
      return;
    }

    if (_partnerUserId == null || _myUserId == null || _kFamily == null) {
      print('❌ Missing data - myUserId: $_myUserId, partnerUserId: $_partnerUserId, kFamily: ${_kFamily?.substring(0, 10)}');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Errore: dati pairing mancanti. Riprova il pairing.')),
      );
      return;
    }

    print('📤 Sending message...');
    print('   From: $_myUserId');
    print('   To: $_partnerUserId');
    print('   Content: ${_messageController.text.trim()}');

    final chatService = Provider.of<ChatService>(context, listen: false);

    final success = await chatService.sendMessage(
      _messageController.text.trim(),
      _myUserId!,
      _partnerUserId!,
      '', // backendToken non più necessario
      _kFamily!,
    );

    if (success) {
      print('✅ Message sent successfully');
      _messageController.clear();
    } else {
      print('❌ Message send failed');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Errore invio messaggio'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatService = Provider.of<ChatService>(context);
    final pairingService = Provider.of<PairingService>(context);

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
              chatService.isConnected ? Icons.cloud_done : Icons.cloud_off,
              color: chatService.isConnected ? Colors.green : Colors.red,
            ),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Reset pairing',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Reset Pairing'),
                  content: const Text('Vuoi eliminare il pairing? Dovrai scansionare di nuovo il QR code.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Annulla'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Reset'),
                    ),
                  ],
                ),
              );

              if (confirmed == true) {
                chatService.stopListening();
                await pairingService.clearPairing();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: chatService.messages.isEmpty
                ? const Center(
                    child: Text(
                      'Nessun messaggio.\nInvia il primo!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: chatService.messages.length,
                    itemBuilder: (context, index) {
                      final message = chatService.messages[index];
                      final isMe = message.senderId == _myUserId;

                      String decryptedContent = '[Errore decifratura]';
                      if (_kFamily != null) {
                        decryptedContent = chatService.decryptMessage(message, _kFamily!);
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.7,
            ),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isMe
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey[300],
              borderRadius: BorderRadius.circular(16),
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
        ],
      ),
    );
  }
}
