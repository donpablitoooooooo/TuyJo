import 'dart:async';
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
  final _scrollController = ScrollController();
  bool _isLoading = true;
  bool _hasText = false;
  String? _familyChatId;
  String? _myDeviceId;
  String? _partnerPublicKey;
  bool _lastPairingStatus = false;
  String? _lastFamilyChatId;
  Timer? _typingTimer;
  int _lastMessageCount = 0;
  bool _isLoadingOlderMessages = false; // Track se stiamo caricando messaggi vecchi

  @override
  void initState() {
    super.initState();
    // Non chiamiamo _initialize qui, aspettiamo didChangeDependencies

    // Listen per cambiamenti nel text field
    _messageController.addListener(() {
      final hasText = _messageController.text.trim().isNotEmpty;
      if (hasText != _hasText) {
        setState(() {
          _hasText = hasText;
        });
      }

      // Typing indicator logic
      if (hasText) {
        _onUserTyping();
      }
    });

    // 📜 INFINITE SCROLL: Listen per scroll verso l'alto (messaggi vecchi)
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    // Con reverse: true, i messaggi vecchi sono in ALTO (maxScrollExtent)
    // Carica quando scrolliamo vicino alla fine (verso l'alto = messaggi vecchi)
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 100 &&
        !_isLoadingOlderMessages) {
      if (kDebugMode) print('📜 User scrolled to top - loading older messages...');
      _loadOlderMessages();
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_isLoadingOlderMessages) return;

    setState(() => _isLoadingOlderMessages = true);

    final chatService = Provider.of<ChatService>(context, listen: false);
    await chatService.loadOlderMessages(limit: 50);

    if (mounted) {
      setState(() => _isLoadingOlderMessages = false);
    }
  }

  void _onUserTyping() {
    // Invia typing status
    if (_familyChatId != null && _myDeviceId != null) {
      final chatService = Provider.of<ChatService>(context, listen: false);
      chatService.setTypingStatus(_familyChatId!, _myDeviceId!, true);

      // Reset timer - dopo 2 secondi di inattività, imposta typing = false
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 2), () {
        chatService.setTypingStatus(_familyChatId!, _myDeviceId!, false);
      });
    }
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

      // Reset message count per nuovo caricamento
      _lastMessageCount = 0;

      _initialize();
    }

    _lastPairingStatus = currentPairingStatus;
    _lastFamilyChatId = currentFamilyChatId;
  }

  Future<void> _initialize() async {
    if (kDebugMode) print('⏱️ [CHAT_SCREEN] Starting chat initialization...');
    final startTime = DateTime.now();

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

      // Avvia listener per la chat (carica cache e connette Firestore in background)
      if (kDebugMode) print('⏱️ [CHAT_SCREEN] Starting Firestore listener...');
      final listenerStart = DateTime.now();
      await chatService.startListening(_familyChatId!); // AWAIT per garantire che cache sia caricata
      final listenerDuration = DateTime.now().difference(listenerStart);
      if (kDebugMode) print('⏱️ [CHAT_SCREEN] Listener started in ${listenerDuration.inMilliseconds}ms');

      // 🔧 FIX: Nascondi loader DOPO che la cache è stata caricata
      // Questo garantisce che il prossimo build avrà già i messaggi pronti per lo scroll
      setState(() => _isLoading = false);

      final totalDuration = DateTime.now().difference(startTime);
      if (kDebugMode) print('⏱️ [CHAT_SCREEN] Chat initialization complete in ${totalDuration.inMilliseconds}ms');

      // Salva il token FCM in Firestore (in background, non blocca la UI)
      if (_myDeviceId != null) {
        // Non await - lascia che succeda in background
        notificationService.saveTokenToFirestore(_familyChatId!, _myDeviceId!).catchError((e) {
          if (kDebugMode) print('⚠️ Error saving FCM token (probably offline): $e');
        });

        // UNPAIR SYNC: Avvia background listener
        pairingService.startBackgroundUnpairListener();
      }
    } else {
      print('❌ Cannot start listener - missing chat ID or partner public key');
      setState(() => _isLoading = false);

      final totalDuration = DateTime.now().difference(startTime);
      if (kDebugMode) print('⏱️ [CHAT_SCREEN] Chat initialization failed in ${totalDuration.inMilliseconds}ms');
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    super.dispose();
  }

  /// Scrolla automaticamente in fondo alla lista (messaggi più recenti)
  /// Con reverse: true, pixels = 0 è in BASSO (messaggi nuovi)
  void _scrollToBottom({bool animated = true}) {
    if (!_scrollController.hasClients) return;

    if (animated) {
      _scrollController.animateTo(
        0, // Con reverse: true, 0 è in basso (messaggi nuovi)
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(0);
    }
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

    final messageText = _messageController.text.trim();
    _messageController.clear(); // Clear subito per UX migliore

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
    print('   Content: $messageText');

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
      messageText,
      _familyChatId!,
      _myDeviceId!,
      myPublicKey, // Chiave pubblica del mittente (per dual encryption)
      _partnerPublicKey!, // Chiave pubblica del destinatario
    );

    if (success) {
      print('✅ Message sent successfully with dual encryption');
      // Scrolla in fondo dopo l'invio
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
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

    // 🔧 FIX: Con reverse: true, il ListView inizia automaticamente in basso (messaggi nuovi)
    // Non serve più auto-scroll al caricamento iniziale!
    // Scrolliamo SOLO quando arriva un singolo nuovo messaggio (chat attiva)
    final currentCount = chatService.messages.length;
    final isSingleNewMessage = currentCount == _lastMessageCount + 1;
    final hasNewMessages = currentCount != _lastMessageCount;

    // Scroll SOLO per nuovi messaggi singoli (quando qualcuno invia un messaggio)
    if (isSingleNewMessage && chatService.messages.isNotEmpty) {
      _lastMessageCount = currentCount;

      if (kDebugMode) print('📜 [SCROLL] New message - smooth scroll to bottom');

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollToBottom(animated: true);
          if (kDebugMode) print('✅ [SCROLL] Scrolled to bottom (new message)');
        }
      });
    }
    // Aggiorna count senza scrollare (caricamento iniziale o bulk updates)
    else if (hasNewMessages) {
      _lastMessageCount = currentCount;
      if (kDebugMode) print('📜 [SCROLL] Count updated: $_lastMessageCount → $currentCount (no auto-scroll needed)');
    }

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
                : Column(
                    children: [
                      // 📜 Indicatore caricamento messaggi vecchi
                      if (_isLoadingOlderMessages)
                        Container(
                          padding: const EdgeInsets.all(8),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Caricamento messaggi...',
                                style: TextStyle(color: Colors.grey, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      Expanded(
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: chatService.messages.length,
                          reverse: true, // 🔧 FIX: reverse per mostrare nuovi messaggi in basso
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
                                key: ValueKey(message.id),
                                message: message,
                                isMe: isMe,
                                isCompleted: isTodoCompleted,
                                onComplete: () => _completeTodo(message.id),
                              );
                            } else {
                              // Messaggio normale
                              final decryptedContent = message.decryptedContent ?? '[Messaggio non decifrabile]';

                              return _MessageBubble(
                                key: ValueKey(message.id),
                                message: decryptedContent,
                                timestamp: message.timestamp,
                                isMe: isMe,
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  spreadRadius: 1,
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    onPressed: _showCreateTodoDialog,
                    icon: const Icon(Icons.add_circle_outline),
                    color: const Color(0xFF667eea),
                    tooltip: 'Crea To Do',
                    iconSize: 28,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _messageController,
                        decoration: InputDecoration(
                          hintText: 'Scrivi un messaggio...',
                          hintStyle: TextStyle(color: Colors.grey[500]),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                        maxLines: null,
                        textCapitalization: TextCapitalization.sentences,
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedScale(
                    scale: _hasText ? 1.0 : 0.8,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutBack,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        gradient: _hasText
                            ? const LinearGradient(
                                colors: [
                                  Color(0xFF667eea),
                                  Color(0xFF764ba2),
                                ],
                              )
                            : LinearGradient(
                                colors: [
                                  Colors.grey[300]!,
                                  Colors.grey[400]!,
                                ],
                              ),
                        shape: BoxShape.circle,
                        boxShadow: _hasText
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF667eea).withOpacity(0.4),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : [],
                      ),
                      child: IconButton(
                        onPressed: _hasText ? _sendMessage : null,
                        icon: const Icon(Icons.send_rounded),
                        color: Colors.white,
                        iconSize: 22,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatefulWidget {
  final String message;
  final DateTime timestamp;
  final bool isMe;

  const _MessageBubble({
    super.key,
    required this.message,
    required this.timestamp,
    required this.isMe,
  });

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: widget.isMe ? const Offset(0.3, 0) : const Offset(-0.3, 0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12, left: 8, right: 8),
          child: Row(
            mainAxisAlignment:
                widget.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                decoration: BoxDecoration(
                  gradient: widget.isMe
                      ? const LinearGradient(
                          colors: [
                            Color(0xFF667eea), // Purple
                            Color(0xFF764ba2), // Deep purple
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : LinearGradient(
                          colors: [
                            Colors.grey[200]!,
                            Colors.grey[100]!,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(20),
                    topRight: const Radius.circular(20),
                    bottomLeft: widget.isMe
                        ? const Radius.circular(20)
                        : const Radius.circular(4),
                    bottomRight: widget.isMe
                        ? const Radius.circular(4)
                        : const Radius.circular(20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: widget.isMe
                          ? const Color(0xFF667eea).withOpacity(0.3)
                          : Colors.black.withOpacity(0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(20),
                    topRight: const Radius.circular(20),
                    bottomLeft: widget.isMe
                        ? const Radius.circular(20)
                        : const Radius.circular(4),
                    bottomRight: widget.isMe
                        ? const Radius.circular(4)
                        : const Radius.circular(20),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        // Future: show message details or reactions
                      },
                      splashColor: Colors.white.withOpacity(0.2),
                      highlightColor: Colors.white.withOpacity(0.1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.message,
                              style: TextStyle(
                                color: widget.isMe ? Colors.white : Colors.black87,
                                fontSize: 15,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  DateFormat('HH:mm').format(widget.timestamp),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: widget.isMe
                                        ? Colors.white.withOpacity(0.8)
                                        : Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
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
    super.key,
    required this.message,
    required this.isMe,
    required this.isCompleted,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    final bool isPastDue = message.dueDate != null && message.dueDate!.isBefore(DateTime.now());

    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 8, right: 8),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            decoration: BoxDecoration(
              gradient: isMe
                  ? const LinearGradient(
                      colors: [
                        Color(0xFF667eea), // Purple
                        Color(0xFF764ba2), // Deep purple
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : LinearGradient(
                      colors: [
                        Colors.grey[200]!,
                        Colors.grey[100]!,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: isMe
                    ? const Radius.circular(20)
                    : const Radius.circular(4),
                bottomRight: isMe
                    ? const Radius.circular(4)
                    : const Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: isMe
                      ? const Color(0xFF667eea).withOpacity(0.3)
                      : Colors.black.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Testo del todo
                  Text(
                    message.decryptedContent ?? '',
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.black87,
                      fontSize: 15,
                      height: 1.4,
                      decoration: isCompleted ? TextDecoration.lineThrough : null,
                    ),
                  ),

                  // Data e ora (icona campanello per notifica)
                  if (message.dueDate != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.notifications_outlined,
                          size: 14,
                          color: isMe
                              ? Colors.white.withOpacity(0.9)
                              : Colors.black54,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat('dd/MM/yyyy HH:mm').format(message.dueDate!.subtract(const Duration(hours: 1))),
                          style: TextStyle(
                            fontSize: 12,
                            color: isMe
                                ? Colors.white.withOpacity(0.9)
                                : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ],

                  // Timestamp del messaggio
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        DateFormat('HH:mm').format(message.timestamp),
                        style: TextStyle(
                          fontSize: 11,
                          color: isMe
                              ? Colors.white.withOpacity(0.8)
                              : Colors.black54,
                        ),
                      ),
                      if (isCompleted) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.check_circle,
                          size: 12,
                          color: isMe
                              ? Colors.white.withOpacity(0.8)
                              : Colors.green,
                        ),
                      ],
                    ],
                  ),

                  // Pulsante per completare (solo se non completato)
                  if (!isCompleted) ...[
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: onComplete,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(isMe ? 0.2 : 0.3),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 14,
                              color: isMe ? Colors.white : Colors.black54,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Completa',
                              style: TextStyle(
                                fontSize: 12,
                                color: isMe ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
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
