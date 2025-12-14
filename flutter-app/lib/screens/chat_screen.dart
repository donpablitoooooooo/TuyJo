import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/pairing_service.dart';
import '../services/chat_service.dart';
import '../services/encryption_service.dart';
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
  String? _lastFamilyChatId;

  @override
  void initState() {
    super.initState();
    // Non chiamiamo _initialize qui, aspettiamo didChangeDependencies
  }

  @override
  void didChangeDependencies() async {
    super.didChangeDependencies();

    // Controlla se lo stato del pairing è cambiato
    final pairingService = Provider.of<PairingService>(context);
    final currentPairingStatus = pairingService.isPaired;

    // FIX BUG CHAT DIVERSE: Calcola il familyChatId corrente
    final currentFamilyChatId = await pairingService.getFamilyChatId();

    // Re-inizializza se:
    // 1. Il pairing è diventato attivo (da false a true), OPPURE
    // 2. Il familyChatId è cambiato (nuovo partner o nuove chiavi del partner)
    final needsReinitialize =
        (currentPairingStatus && !_lastPairingStatus) ||  // Nuovo pairing
        (currentPairingStatus && currentFamilyChatId != null && currentFamilyChatId != _lastFamilyChatId);  // Chat ID cambiato

    if (needsReinitialize) {
      if (kDebugMode) {
        if (currentFamilyChatId != _lastFamilyChatId) {
          print('🔄 Family Chat ID changed! Old: ${_lastFamilyChatId?.substring(0, 10)}..., New: ${currentFamilyChatId?.substring(0, 10)}...');
        } else {
          print('🔄 Pairing detected, initializing chat...');
        }
      }

      // Ferma i vecchi listener prima di reinizializzare
      if (_lastFamilyChatId != null && currentFamilyChatId != _lastFamilyChatId) {
        final chatService = Provider.of<ChatService>(context, listen: false);
        chatService.stopListening();
        chatService.clearMessages();
        if (kDebugMode) print('🔇 Stopped old listeners for chat: ${_lastFamilyChatId?.substring(0, 10)}...');
      }

      _initialize();
    }

    _lastPairingStatus = currentPairingStatus;
    _lastFamilyChatId = currentFamilyChatId;
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
      // Imposta il device ID nel ChatService (per decryption)
      if (_myDeviceId != null) {
        chatService.setMyDeviceId(_myDeviceId!);
      }

      // Avvia listener per la chat
      chatService.startListening(_familyChatId!);
      print('✅ Firestore listener started for chat');

      // Salva il token FCM in Firestore
      if (_myDeviceId != null) {
        await notificationService.saveTokenToFirestore(_familyChatId!, _myDeviceId!);

        // UNPAIR SYNC: Avvia background listener DOPO aver salvato i token FCM
        // Questo evita race condition (listener che parte prima del salvataggio)
        pairingService.startBackgroundUnpairListener();
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

  void _completeTodo(String todoId) async {
    if (_familyChatId == null || _myDeviceId == null || _partnerPublicKey == null) {
      return;
    }

    final chatService = Provider.of<ChatService>(context, listen: false);
    final encryptionService = Provider.of<EncryptionService>(context, listen: false);
    final myPublicKey = await encryptionService.getPublicKey();

    if (myPublicKey == null) return;

    await chatService.sendTodoCompletion(
      todoId,
      _familyChatId!,
      _myDeviceId!,
      myPublicKey,
      _partnerPublicKey!,
    );

    if (kDebugMode) print('✅ Todo marked as completed: $todoId');
  }

  void _showCreateTodoDialog() {
    showDialog(
      context: context,
      builder: (context) => _CreateTodoDialog(
        onCreateTodo: _sendTodo,
      ),
    );
  }

  void _sendTodo(String content, DateTime dueDate) async {
    if (_familyChatId == null || _myDeviceId == null || _partnerPublicKey == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Errore: dati pairing mancanti'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final chatService = Provider.of<ChatService>(context, listen: false);
    final encryptionService = Provider.of<EncryptionService>(context, listen: false);
    final myPublicKey = await encryptionService.getPublicKey();

    if (myPublicKey == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Errore: chiave pubblica non trovata'), backgroundColor: Colors.red),
      );
      return;
    }

    final success = await chatService.sendTodo(
      content,
      dueDate,
      _familyChatId!,
      _myDeviceId!,
      myPublicKey,
      _partnerPublicKey!,
    );

    if (success) {
      if (kDebugMode) print('✅ Todo sent successfully');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Errore invio todo'), backgroundColor: Colors.red),
      );
    }
  }

  void _sendMessage() async {
    if (_messageController.text.trim().isEmpty) {
      print('❌ Message is empty');
      return;
    }

    // BLOCCO INVIO: Verifica che siamo in pairing
    final pairingService = Provider.of<PairingService>(context, listen: false);
    if (!pairingService.isPaired) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '⚠️ Non sei più in pairing!\n'
            'Vai nelle impostazioni e rifare il pairing per chattare.',
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    if (_familyChatId == null || _myDeviceId == null || _partnerPublicKey == null) {
      print('❌ Missing data - familyChatId: $_familyChatId, myDeviceId: $_myDeviceId, partnerPublicKey: ${_partnerPublicKey?.substring(0, 20)}');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Errore: dati pairing mancanti. Riprova il pairing.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    print('📤 Sending message...');
    print('   To family chat: $_familyChatId');
    print('   From device: $_myDeviceId');
    print('   Content: ${_messageController.text.trim()}');

    final chatService = Provider.of<ChatService>(context, listen: false);
    final encryptionService = Provider.of<EncryptionService>(context, listen: false);

    // Ottieni la propria chiave pubblica per la dual encryption
    final myPublicKey = await encryptionService.getPublicKey();
    if (myPublicKey == null) {
      print('❌ My public key is null');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Errore: chiave pubblica non trovata'), backgroundColor: Colors.red),
      );
      return;
    }

    final success = await chatService.sendMessage(
      _messageController.text.trim(),
      _familyChatId!,
      _myDeviceId!,
      myPublicKey, // Chiave pubblica del mittente (per dual encryption)
      _partnerPublicKey!, // Chiave pubblica del destinatario
    );

    if (success) {
      print('✅ Message sent successfully with dual encryption');
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

                      // Verifica se è un messaggio di completamento todo
                      if (message.messageType == 'todo_completed') {
                        // Non mostrare i messaggi di completamento
                        return const SizedBox.shrink();
                      }

                      // Verifica se il todo è stato completato
                      bool isTodoCompleted = false;
                      if (message.messageType == 'todo') {
                        isTodoCompleted = chatService.messages.any((m) =>
                            m.messageType == 'todo_completed' &&
                            m.originalTodoId == message.id);
                      }

                      // Renderizza il tipo di messaggio appropriato
                      if (message.messageType == 'todo') {
                        return _TodoMessageBubble(
                          message: message,
                          isMe: isMe,
                          isCompleted: isTodoCompleted,
                          onComplete: () => _completeTodo(message.id),
                        );
                      } else {
                        // Messaggio normale
                        final decryptedContent = message.decryptedContent ?? '[Messaggio non decifrabile]';

                        return _MessageBubble(
                          message: decryptedContent,
                          timestamp: message.timestamp,
                          isMe: isMe,
                        );
                      }
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
                IconButton(
                  onPressed: _showCreateTodoDialog,
                  icon: const Icon(Icons.calendar_today),
                  color: Colors.orange,
                  tooltip: 'Crea To Do',
                ),
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

class _TodoMessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;
  final bool isCompleted;
  final VoidCallback onComplete;

  const _TodoMessageBubble({
    required this.message,
    required this.isMe,
    required this.isCompleted,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    final bool isPastDue = message.dueDate != null && message.dueDate!.isBefore(DateTime.now());

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.85,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(
                color: isCompleted
                    ? Colors.green
                    : (isPastDue ? Colors.red : Colors.orange),
                width: 2,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.3),
                  spreadRadius: 1,
                  blurRadius: 3,
                ),
              ],
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.event,
                      color: isCompleted
                          ? Colors.green
                          : (isPastDue ? Colors.red : Colors.orange),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isCompleted ? 'To Do - Completato' : 'To Do',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isCompleted
                              ? Colors.green
                              : (isPastDue ? Colors.red : Colors.orange),
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (!isCompleted)
                      Text(
                        isMe ? 'Da te' : 'Dal partner',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[600],
                        ),
                      ),
                  ],
                ),
                const Divider(),
                Text(
                  message.decryptedContent ?? '',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    decoration: isCompleted ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 8),
                if (message.dueDate != null) ...[
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        DateFormat('dd/MM/yyyy HH:mm').format(message.dueDate!),
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.notifications, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        'Reminder: ${DateFormat('dd/MM/yyyy HH:mm').format(message.dueDate!.subtract(const Duration(hours: 1)))}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ],
                if (!isCompleted) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: onComplete,
                      icon: const Icon(Icons.check_circle, size: 18),
                      label: const Text('Segna come completato'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  DateFormat('HH:mm').format(message.timestamp),
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[500],
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

class _CreateTodoDialog extends StatefulWidget {
  final Function(String content, DateTime dueDate) onCreateTodo;

  const _CreateTodoDialog({required this.onCreateTodo});

  @override
  State<_CreateTodoDialog> createState() => _CreateTodoDialogState();
}

class _CreateTodoDialogState extends State<_CreateTodoDialog> {
  final _controller = TextEditingController();
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _selectedTime = const TimeOfDay(hour: 10, minute: 0);
  int _testReminderSeconds = 3600; // 1 ora in secondi per default
  bool _useTestMode = false; // Modalità test disattivata di default

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null) {
      setState(() => _selectedDate = date);
    }
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (time != null) {
      setState(() => _selectedTime = time);
    }
  }

  void _create() {
    if (_controller.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci un nome per il To Do')),
      );
      return;
    }

    DateTime actualDueDate;

    if (_useTestMode) {
      // MODALITÀ TEST: usa i secondi impostati
      // Il reminder arriva dopo i secondi impostati
      // Ma il dueDate deve essere 1 ora dopo il reminder (perché il sistema fa dueDate - 1h)
      actualDueDate = DateTime.now().add(Duration(
        seconds: _testReminderSeconds, // Quando arriva il reminder
        hours: 1, // + 1 ora per il dueDate effettivo
      ));
    } else {
      // MODALITÀ NORMALE: usa la data e ora selezionate dal calendario
      actualDueDate = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );
    }

    widget.onCreateTodo(_controller.text.trim(), actualDueDate);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuovo To Do'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'Cosa devo ricordare?',
                hintText: 'Es. Compleanno Helena',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Modalità Test (per debug)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Switch(
                  value: _useTestMode,
                  onChanged: (value) {
                    setState(() => _useTestMode = value);
                  },
                ),
              ],
            ),
            const Divider(),
            if (!_useTestMode) ...[
              const Text(
                'Data e ora evento:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today),
                      label: Text(DateFormat('dd/MM/yyyy').format(_selectedDate)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickTime,
                      icon: const Icon(Icons.access_time),
                      label: Text(_selectedTime.format(context)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Reminder: 1 ora prima dell\'evento',
                style: TextStyle(fontSize: 12, color: Colors.grey[600], fontStyle: FontStyle.italic),
              ),
            ] else ...[
              const Text(
                'Reminder tra (secondi):',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              Slider(
                value: _testReminderSeconds.toDouble(),
                min: 10,
                max: 3600,
                divisions: 50,
                label: '$_testReminderSeconds sec',
                onChanged: (value) {
                  setState(() => _testReminderSeconds = value.toInt());
                },
              ),
              Text(
                'Il reminder arriverà tra $_testReminderSeconds secondi (${(_testReminderSeconds / 60).toStringAsFixed(1)} min)\n'
                'L\'evento sarà schedulato 1 ora dopo il reminder',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annulla'),
        ),
        ElevatedButton(
          onPressed: _create,
          child: const Text('Crea'),
        ),
      ],
    );
  }
}
