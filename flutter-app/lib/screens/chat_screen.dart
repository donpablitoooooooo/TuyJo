import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/pairing_service.dart';
import '../services/chat_service.dart';
import '../services/notification_service.dart';
import '../models/message.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  bool _isLoading = true;
  String? _familyChatId;
  String? _myDeviceId;
  String? _partnerPublicKey;
  bool _lastPairingStatus = false;

  @override
  void initState() {
    super.initState();
    // Non chiamiamo _initialize qui, aspettiamo didChangeDependencies
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Controlla se lo stato del pairing è cambiato
    final pairingService = Provider.of<PairingService>(context);
    final currentPairingStatus = pairingService.isPaired;

    // Inizializza o re-inizializza se il pairing è attivo e lo stato è cambiato
    if (currentPairingStatus && !_lastPairingStatus) {
      print('🔄 Pairing detected, initializing chat...');
      _initialize();
    }

    _lastPairingStatus = currentPairingStatus;
  }

  Future<void> _initialize() async {
    final pairingService = Provider.of<PairingService>(context, listen: false);
    final chatService = Provider.of<ChatService>(context, listen: false);
    final notificationService = Provider.of<NotificationService>(context, listen: false);

    // Ottieni il family_chat_id e le chiavi
    _familyChatId = await pairingService.getFamilyChatId();
    _myDeviceId = await pairingService.getMyUserId();
    _partnerPublicKey = pairingService.partnerPublicKey;

    print('🔍 Chat initialization:');
    print('   Family Chat ID: $_familyChatId');
    print('   My Device ID: $_myDeviceId');
    print('   Partner Public Key: ${_partnerPublicKey != null ? "${_partnerPublicKey!.substring(0, 20)}..." : "null"}');

    if (_familyChatId != null && _partnerPublicKey != null) {
      // Avvia listener per la chat
      chatService.startListening(_familyChatId!);
      print('✅ Firestore listener started for chat');

      // Salva il token FCM in Firestore
      if (_myDeviceId != null) {
        await notificationService.saveTokenToFirestore(_familyChatId!, _myDeviceId!);

        // Aggiorna il token anche quando cambia
        notificationService.onTokenRefresh((newToken) async {
          print('🔄 FCM token refreshed: $newToken');
          await notificationService.saveTokenToFirestore(_familyChatId!, _myDeviceId!);
        });
      }
    } else {
      print('❌ Cannot start listener - missing chat ID or partner public key');
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

    if (_familyChatId == null || _myDeviceId == null || _partnerPublicKey == null) {
      print('❌ Missing data - familyChatId: $_familyChatId, myDeviceId: $_myDeviceId, partnerPublicKey: ${_partnerPublicKey?.substring(0, 20)}');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Errore: dati pairing mancanti. Riprova il pairing.')),
      );
      return;
    }

    print('📤 Sending message...');
    print('   To family chat: $_familyChatId');
    print('   From device: $_myDeviceId');
    print('   Content: ${_messageController.text.trim()}');

    final chatService = Provider.of<ChatService>(context, listen: false);

    final success = await chatService.sendMessage(
      _messageController.text.trim(),
      _familyChatId!,
      _myDeviceId!,
      _partnerPublicKey!,
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
        title: const Text('Family Chat ❤️'),
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
                      final isMe = message.senderId == _myDeviceId;

                      // Decifra il messaggio con la propria chiave privata RSA
                      final decryptedContent = chatService.decryptMessage(message);

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
