import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:private_messaging/generated/l10n/app_localizations.dart';
import '../services/pairing_service.dart';
import '../services/chat_service.dart';
import '../services/encryption_service.dart';
import '../services/notification_service.dart';
import '../services/attachment_service.dart';
import '../services/location_service.dart';
import '../models/message.dart';
import '../widgets/todo_bubble.dart';
import '../widgets/attachment_widgets.dart';
import '../widgets/reaction_picker.dart';
import '../widgets/reaction_overlay.dart';
import 'chat_screen_dismissible.dart';
import 'pdf_viewer_screen.dart';
import 'location_sharing_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  AttachmentService? _attachmentService;
  bool _isLoading = true;
  bool _hasText = false;
  String? _familyChatId;

  // Computed property per determinare se il pulsante send è abilitato
  bool get _canSend =>
      _hasText ||
      _selectedTodoDate != null ||
      _selectedAttachments.isNotEmpty;

  String? _myDeviceId;
  String? _partnerPublicKey;
  bool _lastPairingStatus = false;
  String? _lastFamilyChatId;
  Timer? _typingTimer;
  int _lastMessageCount = 0;
  bool _isLoadingOlderMessages = false; // Track se stiamo caricando messaggi vecchi
  DateTime? _selectedTodoDate; // Data/ora selezionata per todo (null = messaggio normale)
  bool _isRangeSelection = false; // True se è selezionato un range di date
  DateTime? _selectedRangeStart; // Data inizio range
  DateTime? _selectedRangeEnd; // Data fine range
  int? _selectedReminderHours; // Ore prima del todo per l'alert (null = nessun alert)
  List<File> _selectedAttachments = []; // Lista di file selezionati da inviare
  bool _isUploadingAttachments = false; // Stato di upload allegati
  Set<String> _iosSharedFiles = {}; // Traccia i file temporanei copiati su iOS per pulizia
  String? _editingMessageId; // ID del messaggio che stiamo modificando (null = nuovo messaggio)
  List<Attachment> _editingAttachments = []; // Allegati esistenti del messaggio in modifica
  String? _editingMessageSenderId; // SenderId del messaggio in modifica (per decriptare allegati)

  // Method Channel per condivisione file da altre app (iOS)
  static const platform = MethodChannel('com.privatemessaging.tuyjo/shared_media');

  @override
  void initState() {
    super.initState();
    // Non chiamiamo _initialize qui, aspettiamo didChangeDependencies

    // 🔔 Aggiungi observer per lifecycle events (foreground/background)
    WidgetsBinding.instance.addObserver(this);

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

    // 📤 CONDIVISIONE: Listen per file condivisi da altre app
    _initSharedFiles();
  }

  /// Inizializza listener per file condivisi da altre app
  void _initSharedFiles() {
    if (kDebugMode) {
      print("🔧 Inizializzazione Method Channel per condivisione media...");
    }

    // Configura listener per file condivisi mentre l'app è aperta
    platform.setMethodCallHandler((call) async {
      if (call.method == 'onMediaShared') {
        if (kDebugMode) {
          print("📥 onMediaShared ricevuto: ${call.arguments}");
        }
        if (call.arguments is List) {
          final paths = (call.arguments as List).cast<String>();
          await _handleSharedFilePaths(paths);
        }
      } else if (call.method == 'onTextShared') {
        if (kDebugMode) {
          print("📥 onTextShared ricevuto: ${call.arguments}");
        }
        if (call.arguments is String) {
          await _handleSharedText(call.arguments as String);
        }
      }
    });

    // Ritarda il controllo dei dati condivisi fino a quando il widget è completamente costruito
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Controlla se ci sono file/testo condivisi all'avvio (app era chiusa)
      _getInitialMedia();
      _getInitialSharedText();
    });

    if (kDebugMode) {
      print("✅ Method Channel configurato");
    }
  }

  /// Recupera file condivisi quando l'app era chiusa
  Future<void> _getInitialMedia() async {
    try {
      final result = await platform.invokeMethod('getInitialMedia');
      if (kDebugMode) {
        print("📥 getInitialMedia() restituito: $result");
      }

      if (result != null && result is List && result.isNotEmpty) {
        final paths = result.cast<String>();
        if (kDebugMode) {
          print("📥 File ricevuti: ${paths.length}");
          for (var filePath in paths) {
            print("   - Path: $filePath");
          }
        }
        await _handleSharedFilePaths(paths);
      } else {
        if (kDebugMode) print("⚠️ getInitialMedia() ha restituito lista vuota o null");
      }
    } catch (e) {
      if (kDebugMode) print("❌ Errore in getInitialMedia(): $e");
    }
  }

  /// Recupera testo condiviso quando l'app era chiusa
  Future<void> _getInitialSharedText() async {
    try {
      final result = await platform.invokeMethod('getInitialSharedText');
      if (kDebugMode) {
        print("📥 getInitialSharedText() restituito: $result");
      }

      if (result != null && result is String && result.isNotEmpty) {
        if (kDebugMode) {
          print("📥 Testo ricevuto: $result");
        }
        await _handleSharedText(result);
      } else {
        if (kDebugMode) print("⚠️ getInitialSharedText() ha restituito null o stringa vuota");
      }
    } catch (e) {
      if (kDebugMode) print("❌ Errore in getInitialSharedText(): $e");
    }
  }

  /// Gestisce il testo condiviso da altre app
  Future<void> _handleSharedText(String text) async {
    if (kDebugMode) {
      print("📝 Gestendo testo condiviso: $text");
    }

    // Usa addPostFrameCallback per assicurarsi che il widget sia completamente inizializzato
    // (stesso pattern di _handleSharedFilePaths che funziona per le foto)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        if (kDebugMode) print("⚠️ Widget non montato, impossibile inserire testo");
        return;
      }

      setState(() {
        // Inserisci il testo nel controller del messaggio
        final currentText = _messageController.text;
        if (currentText.isEmpty) {
          _messageController.text = text;
        } else {
          // Aggiungi su nuova riga se c'è già del testo
          _messageController.text = '$currentText\n$text';
        }

        // Posiziona il cursore alla fine
        _messageController.selection = TextSelection.fromPosition(
          TextPosition(offset: _messageController.text.length),
        );

        if (kDebugMode) {
          print("✅ Testo inserito nel messaggio: ${_messageController.text}");
        }
      });
    });
  }

  /// Gestisce i path dei file condivisi (già copiati dall'AppDelegate)
  Future<void> _handleSharedFilePaths(List<String> filePaths) async {
    if (kDebugMode) {
      print("📤 Gestendo ${filePaths.length} file condivisi");
    }

    final List<File> processedFiles = [];

    for (var filePath in filePaths) {
      try {
        if (kDebugMode) {
          print("📎 Processando file: $filePath");
        }

        final file = File(filePath);

        // Verifica che il file esista
        if (!await file.exists()) {
          if (kDebugMode) {
            print("⚠️ File non trovato: $filePath");
          }
          continue;
        }

        // Il file è già stato copiato dall'AppDelegate iOS
        // quindi possiamo usarlo direttamente
        processedFiles.add(file);
        _iosSharedFiles.add(filePath); // Traccia per pulizia successiva

        if (kDebugMode) {
          print("✅ File aggiunto: $filePath");
        }

      } catch (e) {
        if (kDebugMode) {
          print("❌ Errore processando file $filePath: $e");
        }
      }
    }

    // Usa addPostFrameCallback per assicurarsi che il widget sia completamente inizializzato
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      setState(() {
        for (var file in processedFiles) {
          if (!_selectedAttachments.any((f) => f.path == file.path)) {
            _selectedAttachments.add(file);
            if (kDebugMode) {
              print("✅ File aggiunto agli allegati: ${file.path}");
            }
          }
        }
      });
    });
  }

  /// Elimina un singolo file temporaneo iOS
  Future<void> _cleanupIOSFile(String filePath) async {
    if (Platform.isIOS && _iosSharedFiles.contains(filePath)) {
      try {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
          if (kDebugMode) {
            print("🗑️ File iOS temporaneo eliminato: $filePath");
          }
        }
        _iosSharedFiles.remove(filePath);
      } catch (e) {
        if (kDebugMode) {
          print("⚠️ Errore eliminazione file iOS: $e");
        }
      }
    }
  }

  /// Elimina tutti i file temporanei iOS copiati
  Future<void> _cleanupAllIOSFiles() async {
    if (Platform.isIOS && _iosSharedFiles.isNotEmpty) {
      final filesToClean = List<String>.from(_iosSharedFiles);
      for (var filePath in filesToClean) {
        await _cleanupIOSFile(filePath);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Quando l'app torna in foreground, marca i messaggi come letti
    if (state == AppLifecycleState.resumed) {
      if (_familyChatId != null && _myDeviceId != null) {
        final chatService = Provider.of<ChatService>(context, listen: false);
        final notificationService = Provider.of<NotificationService>(context, listen: false);
        chatService.markAllMessagesAsRead(_familyChatId!, _myDeviceId!);
        // 🔴 Azzera badge notifiche
        notificationService.clearBadge();
        if (kDebugMode) print('📱 App resumed - marking messages as read');
      }
    }
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

    // Inizializza AttachmentService con EncryptionService condiviso
    _attachmentService = AttachmentService(encryptionService: chatService.encryptionService);

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

      // 📜 Scrolla al primo messaggio non letto dopo il primo build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scrollToFirstUnreadMessage();
        }
      });

      // ✅ Marca tutti i messaggi ricevuti come letti quando l'utente apre la chat
      if (_myDeviceId != null) {
        chatService.markAllMessagesAsRead(_familyChatId!, _myDeviceId!);
        // 🔴 Azzera badge notifiche
        notificationService.clearBadge();
      }

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
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    // Pulisci eventuali file temporanei iOS rimasti
    _cleanupAllIOSFiles();
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

  /// Scrolla al primo messaggio non letto
  /// Se tutti i messaggi sono letti, rimane in fondo
  void _scrollToFirstUnreadMessage() async {
    // Aspetta che il layout sia completo
    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted || !_scrollController.hasClients) return;

    final chatService = Provider.of<ChatService>(context, listen: false);

    // Conta i messaggi visibili (esclusi todo_completed e TODO futuri)
    final visibleMessages = chatService.messages.where((m) {
      if (m.messageType == 'todo_completed') return false;
      if (m.messageType == 'todo' && m.timestamp.isAfter(DateTime.now())) return false;
      return true;
    }).toList();

    // Trova il primo messaggio non letto tra i visibili
    int unreadCount = 0;
    for (var m in visibleMessages) {
      if (m.senderId != _myDeviceId && !(m.read ?? false)) {
        unreadCount++;
      } else {
        break; // Trovato il primo non letto
      }
    }

    if (unreadCount == 0) {
      // Tutti i messaggi sono letti, rimani in fondo
      if (kDebugMode) print('📜 [SCROLL] All messages read, staying at bottom');
      return;
    }

    // Con reverse: true, i messaggi recenti sono in basso (indice 0)
    // I messaggi non letti sono "sopra" (indice più alto)
    // Stimiamo l'altezza: messaggi normali ~100px, TODO ~120px
    double estimatedPosition = 0;
    for (int i = 0; i < unreadCount && i < visibleMessages.length; i++) {
      final msg = visibleMessages[i];
      // Stima altezza in base al tipo
      if (msg.messageType == 'todo') {
        estimatedPosition += 140; // TODO sono più alti
      } else if (msg.attachments != null && msg.attachments!.isNotEmpty) {
        estimatedPosition += 250; // Messaggi con allegati
      } else {
        estimatedPosition += 100; // Messaggi normali
      }
    }

    // Aggiungi spazio per i separatori di data (~60px ognuno)
    // Stima: un separatore ogni 3-4 messaggi
    final estimatedSeparators = (unreadCount / 3.5).ceil();
    estimatedPosition += estimatedSeparators * 60;

    // Limita al massimo scrollabile
    final maxScroll = _scrollController.position.maxScrollExtent;
    final targetPosition = estimatedPosition > maxScroll ? maxScroll : estimatedPosition;

    if (kDebugMode) {
      print('📜 [SCROLL] Scrolling to first unread: $unreadCount unread messages');
      print('📜 [SCROLL] Target position: $targetPosition (max: $maxScroll)');
    }

    // Scrolla con animazione fluida
    _scrollController.animateTo(
      targetPosition,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
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

  /// Aggiunge una reaction a un messaggio (solo visiva)
  void _addReaction(String messageId, String reactionType) async {
    if (_familyChatId == null || _myDeviceId == null) {
      return;
    }

    final chatService = Provider.of<ChatService>(context, listen: false);

    await chatService.addReaction(
      messageId,
      _familyChatId!,
      _myDeviceId!,
      reactionType,
    );

    if (kDebugMode) print('✅ Reaction $reactionType added to message: $messageId');
  }

  /// Aggiunge un'azione a un messaggio (con effetti logici)
  void _addAction(String messageId, String actionType, Message message) async {
    if (_familyChatId == null || _myDeviceId == null) {
      return;
    }

    final chatService = Provider.of<ChatService>(context, listen: false);

    // Gestisci effetti logici delle azioni
    if (actionType == 'stop_sharing' && message.messageType == 'location_share') {
      await chatService.addAction(
        messageId,
        _familyChatId!,
        _myDeviceId!,
        actionType,
      );
      final locationService = Provider.of<LocationService>(context, listen: false);
      await locationService.stopSharingLocation();
      if (kDebugMode) print('🛑 Location sharing stopped via action');
    } else if (actionType == 'complete' && message.messageType == 'todo') {
      await chatService.addAction(
        messageId,
        _familyChatId!,
        _myDeviceId!,
        actionType,
      );
      if (kDebugMode) print('✅ Todo marked as completed via action');
    } else if (actionType == 'edit') {
      // Modifica: popola i campi (per tutti i messaggi tranne location_share)
      if (kDebugMode) print('✏️ Editing message: $messageId');

      final isPending = messageId.startsWith('pending_');

      setState(() {
        // Per i pending, non settiamo _editingMessageId perché non esiste in Firestore
        // Il messaggio pending verrà rimosso e l'utente invierà un nuovo messaggio
        _editingMessageId = isPending ? null : messageId;
        _editingMessageSenderId = isPending ? null : message.senderId;
        _messageController.text = message.decryptedContent ?? '';

        // Popola gli allegati esistenti (solo quelli caricati con successo)
        _editingAttachments = message.attachments != null
            ? message.attachments!.where((a) => a.url.isNotEmpty).toList()
            : [];

        // Se è un todo, popola anche le date
        if (message.messageType == 'todo') {
          _selectedTodoDate = message.dueDate;
          _selectedRangeStart = message.dueDate;
          _selectedRangeEnd = message.rangeEnd;
          _isRangeSelection = message.rangeEnd != null;
        } else {
          // Resetta le date per messaggi normali
          _selectedTodoDate = null;
          _selectedRangeStart = null;
          _selectedRangeEnd = null;
          _isRangeSelection = false;
        }
      });

      // Se è pending, rimuovilo dalla lista (verrà ricreato al nuovo invio)
      if (isPending) {
        if (kDebugMode) print('🗑️ Removing pending message to allow re-send');
        chatService.removePendingMessage(messageId);
      }

      // Se è un todo, apri anche il calendario
      if (message.messageType == 'todo') {
        _showDateTimePicker();
      }
    } else if (actionType == 'delete') {
      // Elimina: marca come deleted
      if (kDebugMode) print('🗑️ Deleting message: $messageId');

      // Check if this is a pending message (still uploading)
      final isPending = messageId.startsWith('pending_');

      // Elimina prima gli allegati se presenti
      if (message.attachments != null && message.attachments!.isNotEmpty && _attachmentService != null) {
        for (final attachment in message.attachments!) {
          // Skip attachment deletion if URL is empty (still uploading)
          if (attachment.url.isEmpty) {
            if (kDebugMode) print('⏭️ Skipping empty attachment URL (still uploading)');
            continue;
          }

          try {
            await _attachmentService!.deleteAttachment(attachment.url);
            if (kDebugMode) print('🗑️ Deleted attachment: ${attachment.url}');
          } catch (e) {
            if (kDebugMode) print('❌ Failed to delete attachment: $e');
          }
        }
      }

      // Handle pending vs normal messages differently
      if (isPending) {
        // Pending message - just remove from local list, don't try to update Firestore
        if (kDebugMode) print('🗑️ Removing pending message locally');
        chatService.removePendingMessage(messageId);
      } else {
        // Normal message - mark as deleted in Firestore
        await chatService.deleteMessage(messageId, _familyChatId!);
      }
    } else {
      // Azione generica
      await chatService.addAction(
        messageId,
        _familyChatId!,
        _myDeviceId!,
        actionType,
      );
      if (kDebugMode) print('✅ Action $actionType added to message: $messageId');
    }
  }

  /// Formatta la data in modo colloquiale per il separatore
  /// Ritorna: "Oggi", "Ieri", "Domani", nome giorno, o data senza anno
  String _formatDateSeparator(DateTime date) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final tomorrow = today.add(const Duration(days: 1));
    final messageDate = DateTime(date.year, date.month, date.day);

    // Oggi
    if (messageDate == today) {
      return l10n.dateSeparatorToday;
    }

    // Ieri
    if (messageDate == yesterday) {
      return l10n.dateSeparatorYesterday;
    }

    // Domani
    if (messageDate == tomorrow) {
      return l10n.dateSeparatorTomorrow;
    }

    // Giorni della settimana (passati dalla domenica scorsa, futuri fino alla domenica prossima)
    final startOfWeek = today.subtract(Duration(days: today.weekday % 7));
    final endOfWeek = today.add(Duration(days: 7 - (today.weekday % 7)));

    if (messageDate.isAfter(startOfWeek.subtract(const Duration(days: 1))) &&
        messageDate.isBefore(endOfWeek.add(const Duration(days: 1))) &&
        messageDate != today && messageDate != yesterday && messageDate != tomorrow) {
      // Ritorna il nome del giorno
      switch (messageDate.weekday) {
        case DateTime.monday:
          return l10n.dateSeparatorMonday;
        case DateTime.tuesday:
          return l10n.dateSeparatorTuesday;
        case DateTime.wednesday:
          return l10n.dateSeparatorWednesday;
        case DateTime.thursday:
          return l10n.dateSeparatorThursday;
        case DateTime.friday:
          return l10n.dateSeparatorFriday;
        case DateTime.saturday:
          return l10n.dateSeparatorSaturday;
        case DateTime.sunday:
          return l10n.dateSeparatorSunday;
        default:
          return DateFormat('d MMMM', locale).format(date);
      }
    }

    // Data senza anno per messaggi più vecchi o futuri oltre la settimana
    return DateFormat('d MMMM', locale).format(date);
  }

  /// Formatta una data in modo colloquiale (oggi, domani, giorno settimana, data)
  /// con ora opzionale
  String _formatTodoDate(DateTime date, {bool includeTime = true}) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final tomorrow = today.add(const Duration(days: 1));
    final messageDate = DateTime(date.year, date.month, date.day);

    String dateLabel;

    // Oggi
    if (messageDate == today) {
      dateLabel = l10n.dateSeparatorToday;
    }
    // Ieri
    else if (messageDate == yesterday) {
      dateLabel = l10n.dateSeparatorYesterday;
    }
    // Domani
    else if (messageDate == tomorrow) {
      dateLabel = l10n.dateSeparatorTomorrow;
    }
    // Giorni della settimana
    else {
      final startOfWeek = today.subtract(Duration(days: today.weekday % 7));
      final endOfWeek = today.add(Duration(days: 7 - (today.weekday % 7)));

      if (messageDate.isAfter(startOfWeek.subtract(const Duration(days: 1))) &&
          messageDate.isBefore(endOfWeek.add(const Duration(days: 1)))) {
        // Ritorna il nome del giorno
        switch (messageDate.weekday) {
          case DateTime.monday:
            dateLabel = l10n.dateSeparatorMonday;
            break;
          case DateTime.tuesday:
            dateLabel = l10n.dateSeparatorTuesday;
            break;
          case DateTime.wednesday:
            dateLabel = l10n.dateSeparatorWednesday;
            break;
          case DateTime.thursday:
            dateLabel = l10n.dateSeparatorThursday;
            break;
          case DateTime.friday:
            dateLabel = l10n.dateSeparatorFriday;
            break;
          case DateTime.saturday:
            dateLabel = l10n.dateSeparatorSaturday;
            break;
          case DateTime.sunday:
            dateLabel = l10n.dateSeparatorSunday;
            break;
          default:
            dateLabel = DateFormat('d MMMM', locale).format(date);
        }
      } else {
        // Data senza anno per date oltre la settimana
        dateLabel = DateFormat('d MMMM', locale).format(date);
      }
    }

    if (includeTime) {
      final timeFormat = DateFormat('HH:mm');
      return '$dateLabel ${timeFormat.format(date)}';
    }

    return dateLabel;
  }

  /// Formatta un range di date in modo intelligente
  /// - Stesso mese: "dal 25 al 31 gennaio"
  /// - Mesi consecutivi: "dal 25 dicembre al 3"
  /// - Distanza > 1 mese: "dal 25 dicembre al 3 febbraio"
  String _formatDateRange(DateTime start, DateTime end) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();

    // Calcola differenza in mesi
    final monthsDiff = (end.year - start.year) * 12 + (end.month - start.month);

    if (monthsDiff == 0) {
      // Stesso mese: "dal 25 al 31 gennaio"
      final startDay = DateFormat('d', locale).format(start);
      final endDay = DateFormat('d', locale).format(end);
      final month = DateFormat('MMMM', locale).format(start);
      return '${l10n.dateRangeFrom} $startDay ${l10n.dateRangeTo} $endDay $month';
    } else if (monthsDiff == 1) {
      // Mesi consecutivi: "dal 25 dicembre al 3"
      final startFormatted = DateFormat('d MMMM', locale).format(start);
      final endDay = DateFormat('d', locale).format(end);
      return '${l10n.dateRangeFrom} $startFormatted ${l10n.dateRangeTo} $endDay';
    } else {
      // Distanza > 1 mese: "dal 25 dicembre al 3 febbraio"
      final startFormatted = DateFormat('d MMMM', locale).format(start);
      final endFormatted = DateFormat('d MMMM', locale).format(end);
      return '${l10n.dateRangeFrom} $startFormatted ${l10n.dateRangeTo} $endFormatted';
    }
  }

  /// Determina se mostrare un separatore di data tra due messaggi
  /// Confronta le date dei messaggi (ignorando l'ora)
  bool _shouldShowDateSeparator(Message currentMessage, Message? nextMessage) {
    if (nextMessage == null) return true; // Mostra sempre separatore per l'ultimo messaggio

    final currentDate = DateTime(
      currentMessage.timestamp.year,
      currentMessage.timestamp.month,
      currentMessage.timestamp.day,
    );

    final nextDate = DateTime(
      nextMessage.timestamp.year,
      nextMessage.timestamp.month,
      nextMessage.timestamp.day,
    );

    return currentDate != nextDate;
  }

  /// Mostra il bottom sheet per selezionare il tipo di allegato
  void _showAttachmentPicker() async {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF3BA8B0), Color(0xFF145A60)],
            ),
          ),
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).padding.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header con X
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 8),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white, size: 28),
                      ),
                      Expanded(
                        child: Text(
                          l10n.chatAttachmentPickerTitle,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 48), // Spacer per centrare il titolo
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              _AttachmentOption(
                icon: Icons.photo_library,
                label: l10n.chatAttachmentPhotoFromGallery,
                color: Colors.blue,
                onTap: () async {
                  Navigator.pop(context);
                  final files = await _attachmentService!.pickImageFromGallery();
                  if (files.isNotEmpty) {
                    setState(() {
                      _selectedAttachments.addAll(files);
                    });
                  }
                },
              ),
              _AttachmentOption(
                icon: Icons.camera_alt,
                label: l10n.chatAttachmentTakePhoto,
                color: Colors.purple,
                onTap: () async {
                  Navigator.pop(context);
                  final file = await _attachmentService!.pickImageFromCamera();
                  if (file != null) {
                    setState(() {
                      _selectedAttachments.add(file);
                    });
                  }
                },
              ),
              _AttachmentOption(
                icon: Icons.insert_drive_file,
                label: l10n.chatAttachmentDocument,
                color: Colors.green,
                onTap: () async {
                  Navigator.pop(context);
                  final file = await _attachmentService!.pickDocument();
                  if (file != null) {
                    setState(() {
                      _selectedAttachments.add(file);
                    });
                  }
                },
              ),
              _AttachmentOption(
                icon: Icons.location_on,
                label: l10n.locationShareButton,
                color: Colors.orange,
                onTap: () {
                  Navigator.pop(context);
                  _showLocationSharingDialog();
                },
              ),
              const SizedBox(height: 16),
            ],
          ), // Chiude Column
        ), // Chiude Padding
      ), // Chiude Container
    ), // Chiude ClipRRect
    ); // Chiude showModalBottomSheet
  } // Chiude _showAttachmentPicker

  /// Mostra dialog per scegliere durata condivisione posizione
  void _showLocationSharingDialog() async {
    final l10n = AppLocalizations.of(context)!;
    final result = await showDialog<Duration>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.locationShareDialogTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.locationShareDialogQuestion),
            const SizedBox(height: 8),
            Text(
              l10n.locationShareDialogDescription,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton(
                onPressed: () => Navigator.pop(context, const Duration(hours: 1)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3BA8B0),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(l10n.locationShareDuration1Hour, style: const TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, const Duration(hours: 8)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3BA8B0),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(l10n.locationShareDuration8Hours, style: const TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.locationShareCancel),
              ),
            ],
          ),
        ],
      ),
    );

    if (result != null && mounted) {
      // Avvia condivisione posizione
      final locationService = Provider.of<LocationService>(context, listen: false);
      final success = await locationService.startSharingLocation(result);

      if (success) {
        // Calcola expiresAt
        final expiresAt = DateTime.now().add(result);

        // Invia messaggio di condivisione posizione
        final chatService = Provider.of<ChatService>(context, listen: false);
        final pairingService = Provider.of<PairingService>(context, listen: false);
        final encryptionService = Provider.of<EncryptionService>(context, listen: false);

        final familyChatId = await pairingService.getFamilyChatId();
        final myDeviceId = await pairingService.getMyUserId();
        final myPublicKey = await encryptionService.getPublicKey();
        final partnerPublicKey = pairingService.partnerPublicKey;

        if (familyChatId != null &&
            myDeviceId != null &&
            myPublicKey != null &&
            partnerPublicKey != null &&
            locationService.currentSessionId != null) {
          final messageId = await chatService.sendLocationShare(
            expiresAt,
            locationService.currentSessionId!, // Session ID univoco
            familyChatId,
            myDeviceId,
            myPublicKey,
            partnerPublicKey,
          );

          if (messageId != null) {
            // Salva il messageId nel LocationService per poterlo usare quando si ferma la condivisione
            locationService.setLocationShareMessageId(messageId);
          }
        }
      } else {
        // Errore - controlla se è un problema di pairing o permessi
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          String errorMessage = l10n.locationShareErrorGeneric;

          // Controlla se l'utente è paired
          if (_partnerPublicKey == null) {
            errorMessage = l10n.locationShareErrorPairing;
          } else {
            errorMessage = l10n.locationShareErrorPermissions;
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              duration: const Duration(seconds: 5),
              backgroundColor: Colors.red[700],
            ),
          );
        }
      }
    }
  }

  /// Costruisce un'opzione per il menu di selezione alert
  Widget _buildAlertOption(BuildContext context, int? hours, String label) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.pop(context, hours),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          child: Row(
            children: [
              Icon(
                hours == null ? Icons.notifications_off : Icons.notifications_outlined,
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(width: 16),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Costruisce un'opzione per il menu di selezione alert con stato selezionato (inline version)
  Widget _buildAlertOptionInline(
    BuildContext context,
    int? hours,
    String label,
    int? currentSelection,
    Function(int?) onSelect,
  ) {
    final isSelected = hours == currentSelection;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onSelect(hours),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                hours == null ? Icons.notifications_off : Icons.notifications_outlined,
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ),
              if (isSelected)
                const Icon(Icons.check, color: Colors.white, size: 24),
            ],
          ),
        ),
      ),
    );
  }

  /// Recupera i todo per un giorno specifico per mostrare i marker nel calendario
  List<Message> _getTodosForDayInCalendar(DateTime day) {
    final chatService = Provider.of<ChatService>(context, listen: false);
    final normalizedDay = DateTime(day.year, day.month, day.day);

    return chatService.messages.where((message) {
      if (message.messageType != 'todo') return false;
      if (message.dueDate == null) return false;
      if (message.isReminder == true) return false; // Escludi gli alert

      final todoDay = DateTime(
        message.dueDate!.year,
        message.dueDate!.month,
        message.dueDate!.day,
      );

      // Check if todo is on this day or if this day is in the range
      if (message.rangeEnd != null) {
        final rangeEndDay = DateTime(
          message.rangeEnd!.year,
          message.rangeEnd!.month,
          message.rangeEnd!.day,
        );
        return (normalizedDay.isAtSameMomentAs(todoDay) ||
                normalizedDay.isAtSameMomentAs(rangeEndDay) ||
                (normalizedDay.isAfter(todoDay) && normalizedDay.isBefore(rangeEndDay)));
      } else {
        return normalizedDay.isAtSameMomentAs(todoDay);
      }
    }).toList();
  }

  /// Recupera i todo per un range di date
  List<Message> _getTodosForRange(DateTime rangeStart, DateTime rangeEnd) {
    final chatService = Provider.of<ChatService>(context, listen: false);
    final normalizedStart = DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
    final normalizedEnd = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day);

    return chatService.messages.where((message) {
      if (message.messageType != 'todo') return false;
      if (message.dueDate == null) return false;
      if (message.isReminder == true) return false; // Escludi gli alert

      final todoDay = DateTime(
        message.dueDate!.year,
        message.dueDate!.month,
        message.dueDate!.day,
      );

      // Check if todo is in the selected range
      if (message.rangeEnd != null) {
        final todoRangeEnd = DateTime(
          message.rangeEnd!.year,
          message.rangeEnd!.month,
          message.rangeEnd!.day,
        );
        // Include todo if it overlaps with selected range
        return !(todoRangeEnd.isBefore(normalizedStart) || todoDay.isAfter(normalizedEnd));
      } else {
        // Single day todo: check if it's within the selected range
        return !todoDay.isBefore(normalizedStart) && !todoDay.isAfter(normalizedEnd);
      }
    }).toList();
  }

  void _showDateTimePicker() async {
    final l10n = AppLocalizations.of(context)!;
    // Sentinella per segnalare cancellazione
    final clearResult = {'clear': true};

    DateTime selectedDate = DateTime.now().add(const Duration(days: 1));
    DateTime? rangeStart;
    DateTime? rangeEnd;
    int? selectedReminderHours = _selectedReminderHours; // Mantieni l'alert precedente
    DateTime? dayToShowTodos; // Giorno selezionato per mostrare i todo
    final chatService = Provider.of<ChatService>(context, listen: false);

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          // Recupera i todo per il giorno/range selezionato
          final todosForDay = (rangeStart != null && rangeEnd != null)
              ? _getTodosForRange(rangeStart!, rangeEnd!)
              : (dayToShowTodos != null
                  ? _getTodosForDayInCalendar(dayToShowTodos!)
                  : <Message>[]);

          return DismissiblePane(
            onDismissed: () => Navigator.pop(context),
            child: Container(
              height: MediaQuery.of(context).size.height,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF3BA8B0), Color(0xFF145A60)],
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    // Header with close button
                    Padding(
                      padding: const EdgeInsets.only(right: 8, top: 8),
                      child: Align(
                        alignment: Alignment.topRight,
                        child: IconButton(
                          icon: const Icon(Icons.close, color: Colors.white, size: 28),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                    ),

                    // Calendario con sfondo verde trasparente e altezza fissa
                    SizedBox(
                      height: 380,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TableCalendar(
                      locale: Localizations.localeOf(context).toString(),
                      firstDay: DateTime.now(),
                      lastDay: DateTime.now().add(const Duration(days: 365)),
                      focusedDay: selectedDate,
                      rangeStartDay: rangeStart,
                      rangeEndDay: rangeEnd,
                      rangeSelectionMode: RangeSelectionMode.toggledOn,
                      eventLoader: _getTodosForDayInCalendar,
                      calendarStyle: CalendarStyle(
                        defaultTextStyle: const TextStyle(color: Colors.white),
                        weekendTextStyle: const TextStyle(color: Colors.white70),
                        outsideTextStyle: const TextStyle(color: Colors.white30),
                        selectedDecoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          shape: BoxShape.circle,
                        ),
                        selectedTextStyle: const TextStyle(color: Color(0xFF3BA8B0), fontWeight: FontWeight.bold),
                        todayDecoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.3),
                          shape: BoxShape.circle,
                        ),
                        todayTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        rangeStartDecoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          shape: BoxShape.circle,
                        ),
                        rangeStartTextStyle: const TextStyle(color: Color(0xFF3BA8B0), fontWeight: FontWeight.bold),
                        rangeEndDecoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          shape: BoxShape.circle,
                        ),
                        rangeEndTextStyle: const TextStyle(color: Color(0xFF3BA8B0), fontWeight: FontWeight.bold),
                        rangeHighlightColor: Colors.white.withOpacity(0.2),
                        withinRangeDecoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        withinRangeTextStyle: const TextStyle(color: Colors.white),
                        markerDecoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.8),
                          shape: BoxShape.circle,
                        ),
                        markersAlignment: Alignment.bottomCenter,
                        markersMaxCount: 3,
                      ),
                      headerStyle: HeaderStyle(
                        formatButtonVisible: false,
                        titleCentered: true,
                        titleTextStyle: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        leftChevronIcon: const Icon(Icons.chevron_left, color: Colors.white),
                        rightChevronIcon: const Icon(Icons.chevron_right, color: Colors.white),
                      ),
                      daysOfWeekStyle: const DaysOfWeekStyle(
                        weekdayStyle: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
                        weekendStyle: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
                      ),
                      onDaySelected: (selectedDay, focusedDay) {
                        setModalState(() {
                          // Mostra i todo per il giorno selezionato
                          dayToShowTodos = selectedDay;

                          if (rangeStart == null) {
                            // Prima selezione: imposta range start
                            rangeStart = selectedDay;
                            rangeEnd = null;
                            selectedDate = selectedDay;
                          } else if (rangeEnd == null) {
                            // Seconda selezione: imposta range end
                            if (selectedDay.isAfter(rangeStart!) || selectedDay.isAtSameMomentAs(rangeStart!)) {
                              rangeEnd = selectedDay;
                            } else {
                              // Se la data è prima di start, reset e ricomincia
                              rangeStart = selectedDay;
                              rangeEnd = null;
                            }
                            selectedDate = selectedDay;
                          } else {
                            // Range già completo: reset e ricomincia
                            rangeStart = selectedDay;
                            rangeEnd = null;
                            selectedDate = selectedDay;
                          }
                        });
                      },
                    ),
                        ),
                      ),

                    const SizedBox(height: 16),

                  // Lista TODO in container bianco Expanded
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // Titolo lista
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.event_note,
                                  color: Color(0xFF3BA8B0),
                                  size: 24,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    (rangeStart != null && rangeEnd != null)
                                        ? l10n.todoTitleWithRange(_formatDateRange(rangeStart!, rangeEnd!))
                                        : (dayToShowTodos != null
                                            ? l10n.todoTitleWithDate(_formatTodoDate(dayToShowTodos!, includeTime: false))
                                            : l10n.todoSelectDay),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF3BA8B0),
                                    ),
                                  ),
                                ),
                                if (rangeStart != null)
                                  IconButton(
                                    onPressed: () async {
                                      // Mostra menu per selezionare alert e orario inline
                                      int? alertHours = selectedReminderHours ?? 1; // Default 1h
                                      int selectedHour = 10;
                                      int selectedMinute = 0;

                                      final result = await showModalBottomSheet<Map<String, dynamic>?>(
                                        context: context,
                                        isScrollControlled: true,
                                        backgroundColor: Colors.transparent,
                                        builder: (context) => StatefulBuilder(
                                          builder: (context, setAlertState) => Container(
                                            height: MediaQuery.of(context).size.height * 0.7,
                                            decoration: const BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                                colors: [Color(0xFF3BA8B0), Color(0xFF145A60)],
                                              ),
                                              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                                            ),
                                            child: SafeArea(
                                              child: Column(
                                                children: [
                                                  // Data bella grossa
                                                  Padding(
                                                    padding: const EdgeInsets.only(top: 20, bottom: 12),
                                                    child: Text(
                                                      (rangeStart != null && rangeEnd != null)
                                                          ? _formatDateRange(rangeStart!, rangeEnd!)
                                                          : (dayToShowTodos != null
                                                              ? _formatTodoDate(dayToShowTodos!, includeTime: false)
                                                              : ''),
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 28,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                      textAlign: TextAlign.center,
                                                    ),
                                                  ),

                                                  // Orario e Alert affiancati
                                                  Expanded(
                                                    child: Padding(
                                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                                      child: Row(
                                                        crossAxisAlignment: CrossAxisAlignment.center,
                                                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                                        children: [
                                                          // Sezione Orario (sinistra)
                                                          Column(
                                                            mainAxisAlignment: MainAxisAlignment.center,
                                                            children: [
                                                              Text(
                                                                l10n.timePickerLabel,
                                                                style: const TextStyle(
                                                                  color: Colors.white,
                                                                  fontSize: 18,
                                                                  fontWeight: FontWeight.bold,
                                                                ),
                                                              ),
                                                              const SizedBox(height: 12),
                                                              Row(
                                                                mainAxisAlignment: MainAxisAlignment.center,
                                                                children: [
                                                                  SizedBox(
                                                                    width: 70,
                                                                    height: 240,
                                                                    child: CupertinoPicker(
                                                                      scrollController: FixedExtentScrollController(initialItem: selectedHour),
                                                                      itemExtent: 50,
                                                                      onSelectedItemChanged: (index) {
                                                                        selectedHour = index;
                                                                      },
                                                                      children: List.generate(24, (index) => Center(
                                                                        child: Text(
                                                                          index.toString().padLeft(2, '0'),
                                                                          style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w500),
                                                                        ),
                                                                      )),
                                                                    ),
                                                                  ),
                                                                  const Padding(
                                                                    padding: EdgeInsets.symmetric(horizontal: 4),
                                                                    child: Text(':', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                                                                  ),
                                                                  SizedBox(
                                                                    width: 70,
                                                                    height: 240,
                                                                    child: CupertinoPicker(
                                                                      scrollController: FixedExtentScrollController(initialItem: selectedMinute),
                                                                      itemExtent: 50,
                                                                      onSelectedItemChanged: (index) {
                                                                        selectedMinute = index;
                                                                      },
                                                                      children: List.generate(60, (index) => Center(
                                                                        child: Text(
                                                                          index.toString().padLeft(2, '0'),
                                                                          style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w500),
                                                                        ),
                                                                      )),
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ],
                                                          ),

                                                          const SizedBox(width: 20),

                                                          // Sezione Alert (destra) - Picker rotellina
                                                          Column(
                                                            mainAxisAlignment: MainAxisAlignment.center,
                                                            children: [
                                                              Text(
                                                                l10n.alertPickerLabel,
                                                                style: const TextStyle(
                                                                  color: Colors.white,
                                                                  fontSize: 18,
                                                                  fontWeight: FontWeight.bold,
                                                                ),
                                                              ),
                                                              const SizedBox(height: 12),
                                                              SizedBox(
                                                                width: 160,
                                                                height: 240,
                                                                child: CupertinoPicker(
                                                                  scrollController: FixedExtentScrollController(
                                                                    initialItem: () {
                                                                      // Mappa alertHours all'indice corretto
                                                                      // Nuovo ordine: null, 1, 2, 8, 24, 48
                                                                      final alertOptions = [null, 1, 2, 8, 24, 48];
                                                                      final index = alertOptions.indexOf(alertHours);
                                                                      return index == -1 ? 1 : index; // Default "1 ora prima"
                                                                    }(),
                                                                  ),
                                                                  itemExtent: 50,
                                                                  onSelectedItemChanged: (index) {
                                                                    // Mappa indice a ore
                                                                    const alertOptions = [null, 1, 2, 8, 24, 48];
                                                                    setAlertState(() => alertHours = alertOptions[index]);
                                                                  },
                                                                  children: [
                                                                    Center(child: Text(l10n.alertNone, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w500))),
                                                                    Center(child: Text(l10n.alert1HourBefore, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w500))),
                                                                    Center(child: Text(l10n.alert2HoursBefore, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w500))),
                                                                    Center(child: Text(l10n.alert8HoursBefore, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w500))),
                                                                    Center(child: Text(l10n.alert1DayBefore, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w500))),
                                                                    Center(child: Text(l10n.alert2DaysBefore, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w500))),
                                                                  ],
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                  // Bottone conferma
                                                  Padding(
                                                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                                                    child: Material(
                                                      color: Colors.white.withOpacity(0.15),
                                                      borderRadius: BorderRadius.circular(12),
                                                      child: InkWell(
                                                        onTap: () {
                                                          Navigator.pop(context, {
                                                            'alertHours': alertHours,
                                                            'hour': selectedHour,
                                                            'minute': selectedMinute,
                                                          });
                                                        },
                                                        borderRadius: BorderRadius.circular(12),
                                                        splashColor: Colors.white.withOpacity(0.2),
                                                        child: Padding(
                                                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                                          child: Center(
                                                            child: Text(
                                                              l10n.todoConfirm,
                                                              style: const TextStyle(
                                                                color: Colors.white,
                                                                fontSize: 16,
                                                                fontWeight: FontWeight.w500,
                                                                letterSpacing: 0.3,
                                                              ),
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
                                        ),
                                      );

                                      if (result != null) {
                                        // Conferma e chiudi con i dati selezionati
                                        if (rangeStart != null && rangeEnd != null) {
                                          // Range selezionato: ritorna range senza ora
                                          Navigator.pop(context, {
                                            'isRange': true,
                                            'rangeStart': rangeStart,
                                            'rangeEnd': rangeEnd,
                                            'reminderHours': result['alertHours'],
                                          });
                                        } else if (rangeStart != null) {
                                          // Data singola: ritorna con ora selezionata
                                          final dueDate = DateTime(
                                            selectedDate.year,
                                            selectedDate.month,
                                            selectedDate.day,
                                            result['hour'] ?? 10,
                                            result['minute'] ?? 0,
                                          );
                                          Navigator.pop(context, {
                                            'isRange': false,
                                            'date': dueDate,
                                            'reminderHours': result['alertHours'],
                                          });
                                        }
                                      }
                                    },
                                    icon: const Icon(Icons.add_circle, color: Color(0xFF3BA8B0), size: 32),
                                    tooltip: l10n.todoAddAlertAndConfirm,
                                  ),
                              ],
                            ),
                          ),

                          const Divider(height: 1),

                          // Lista TODO
                          Expanded(
                            child: todosForDay.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.event_available,
                                          size: 64,
                                          color: Colors.grey[300],
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          (rangeStart == null && dayToShowTodos == null)
                                              ? l10n.todoSelectDayToView
                                              : ((rangeStart != null && rangeEnd != null)
                                                  ? l10n.todoNoTodosInRange
                                                  : l10n.todoNoTodosForDay),
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView.separated(
                                    padding: const EdgeInsets.all(16),
                                    itemCount: todosForDay.length,
                                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                                    itemBuilder: (context, index) {
                                      final todo = todosForDay[index];

                                      // Verifica se è completato
                                      final isCompleted = todo.action?.type == 'complete' ||
                                          chatService.messages.any((m) =>
                                              m.messageType == 'todo_completed' &&
                                              m.originalTodoId == todo.id);

                                      // Determina se è stato creato da me
                                      final isMe = todo.senderId == _myDeviceId;

                                      // Formatta la data come in chat
                                      String? formattedDate;
                                      if (todo.dueDate != null) {
                                        if (todo.rangeEnd != null) {
                                          // È un range: formatta in modo intelligente
                                          formattedDate = _formatDateRange(todo.dueDate!, todo.rangeEnd!);
                                        } else {
                                          // Data singola con ora in formato colloquiale
                                          formattedDate = _formatTodoDate(todo.dueDate!, includeTime: true);
                                        }
                                      }

                                      return TodoMessageBubble(
                                        message: todo,
                                        isMe: isMe,
                                        isCompleted: isCompleted,
                                        onReact: (reactionType) => _addReaction(todo.id, reactionType),
                                        onAction: (actionType) => _addAction(todo.id, actionType, todo),
                                        formattedDate: formattedDate,
                                        attachmentService: _attachmentService,
                                        senderId: todo.senderId,
                                        currentUserId: _myDeviceId,
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
        },  // Fine builder function dello StatefulBuilder
      ),  // Fine StatefulBuilder
    );  // Fine showModalBottomSheet

    if (result != null && result['clear'] == true) {
      // X premuto per cancellare
      setState(() {
        _selectedTodoDate = null;
        _isRangeSelection = false;
        _selectedRangeStart = null;
        _selectedRangeEnd = null;
        _selectedReminderHours = null;
      });
    } else if (result != null) {
      // Data/range selezionato e confermato
      setState(() {
        if (result['isRange'] == true) {
          // Range selezionato
          _isRangeSelection = true;
          _selectedRangeStart = result['rangeStart'];
          _selectedRangeEnd = result['rangeEnd'];
          _selectedTodoDate = result['rangeStart']; // Per mostrare indicatore
        } else {
          // Data singola
          _isRangeSelection = false;
          _selectedTodoDate = result['date'];
          _selectedRangeStart = null;
          _selectedRangeEnd = null;
        }
        _selectedReminderHours = result['reminderHours'];
      });
    }
    // Se result è null, l'utente ha chiuso senza azione (non cambiare niente)
  }

  Future<void> _updateExistingMessage() async {
    final messageText = _messageController.text.trim();
    final messageId = _editingMessageId!;
    final todoDate = _selectedTodoDate;
    final rangeEnd = _selectedRangeEnd;

    // Salva gli allegati rimasti prima di resettare
    final remainingAttachments = List<Attachment>.from(_editingAttachments);

    if (messageText.isEmpty) {
      print('❌ Cannot update with empty message');
      return;
    }

    _messageController.clear();

    setState(() {
      _editingMessageId = null;
      _editingMessageSenderId = null;
      _editingAttachments = [];
      _selectedTodoDate = null;
      _isRangeSelection = false;
      _selectedRangeStart = null;
      _selectedRangeEnd = null;
      _selectedReminderHours = null;
    });

    // Verifica dati necessari
    if (_familyChatId == null || _myDeviceId == null || _partnerPublicKey == null) {
      print('❌ Missing data for update');
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.chatPairingDataMissingError),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final chatService = Provider.of<ChatService>(context, listen: false);
    final encryptionService = Provider.of<EncryptionService>(context, listen: false);

    // Ottieni il messaggio originale per vedere quali allegati aveva
    final originalMessage = chatService.messages.firstWhere((m) => m.id == messageId);
    final originalAttachments = originalMessage.attachments ?? [];

    // Trova gli allegati da eliminare (quelli che erano nell'originale ma non sono più in remainingAttachments)
    final attachmentsToDelete = originalAttachments.where((original) {
      return !remainingAttachments.any((remaining) => remaining.id == original.id);
    }).toList();

    // Elimina gli allegati rimossi da Firebase Storage
    if (attachmentsToDelete.isNotEmpty && _attachmentService != null) {
      for (final attachment in attachmentsToDelete) {
        try {
          await _attachmentService!.deleteAttachment(attachment.url);
          if (kDebugMode) print('🗑️ Deleted removed attachment: ${attachment.url}');
        } catch (e) {
          if (kDebugMode) print('❌ Failed to delete attachment: $e');
        }
      }
    }

    // Ottieni la propria chiave pubblica
    final myPublicKey = await encryptionService.getPublicKey();
    if (myPublicKey == null) {
      print('❌ My public key is null');
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.chatPublicKeyNotFoundError), backgroundColor: Colors.red),
      );
      return;
    }

    // Chiama updateMessage con gli allegati rimanenti
    // Passa sempre remainingAttachments (anche se vuota) per aggiornare correttamente
    final success = await chatService.updateMessage(
      messageId,
      _familyChatId!,
      messageText,
      _myDeviceId!,
      myPublicKey,
      _partnerPublicKey!,
      dueDate: todoDate,
      rangeEnd: rangeEnd,
      attachments: remainingAttachments,
    );

    if (success) {
      if (kDebugMode) print('✅ Message updated successfully');
    } else {
      if (kDebugMode) print('❌ Failed to update message');
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.chatUpdateMessageError),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _sendMessage() async {
    // Se stiamo modificando un messaggio esistente, chiama updateMessage
    if (_editingMessageId != null) {
      await _updateExistingMessage();
      return;
    }

    final todoDate = _selectedTodoDate;
    final isRange = _isRangeSelection;
    final rangeStart = _selectedRangeStart;
    final rangeEnd = _selectedRangeEnd;
    final attachments = List<File>.from(_selectedAttachments);

    // Permetti invio se c'è testo, una data selezionata o allegati
    if (_messageController.text.trim().isEmpty && todoDate == null && attachments.isEmpty) {
      print('❌ Message is empty, no date selected, and no attachments');
      return;
    }

    final messageText = _messageController.text.trim();
    _messageController.clear(); // Clear subito per UX migliore

    // Crea allegati placeholder per invio ottimistico
    List<Attachment>? placeholderAttachments;
    if (attachments.isNotEmpty) {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      placeholderAttachments = attachments.asMap().entries.map((entry) {
        final index = entry.key;
        final file = entry.value;
        final fileName = file.path.split('/').last;
        return Attachment(
          id: 'uploading_${timestamp}_$index', // Aggiunge index per evitare duplicate keys
          type: file.path.endsWith('.pdf') ? 'document' :
                file.path.contains('video') ? 'video' : 'photo',
          url: '', // URL vuoto indica che è in upload
          fileName: fileName,
          fileSize: 0,
          encryptedKeyRecipient: '',
          encryptedKeySender: '',
          iv: '',
        );
      }).toList();
    }

    // Salva reminderHours prima di resettare
    final reminderHours = _selectedReminderHours;

    setState(() {
      _selectedTodoDate = null; // Reset todo date
      _isRangeSelection = false; // Reset range flag
      _selectedRangeStart = null; // Reset range start
      _selectedRangeEnd = null; // Reset range end
      _selectedReminderHours = null; // Reset reminder hours
      _selectedAttachments.clear(); // Clear attachments
      _isUploadingAttachments = true; // Mostra loader
    });

    // BLOCCO INVIO: Verifica che siamo in pairing
    final pairingService = Provider.of<PairingService>(context, listen: false);
    if (!pairingService.isPaired) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.chatNotPairedWarning),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    if (_familyChatId == null || _myDeviceId == null || _partnerPublicKey == null) {
      print('❌ Missing data - familyChatId: $_familyChatId, myDeviceId: $_myDeviceId, partnerPublicKey: ${_partnerPublicKey?.substring(0, 20)}');
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.chatPairingDataMissingError),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final chatService = Provider.of<ChatService>(context, listen: false);
    final encryptionService = Provider.of<EncryptionService>(context, listen: false);

    // Ottieni la propria chiave pubblica per la dual encryption
    final myPublicKey = await encryptionService.getPublicKey();
    if (myPublicKey == null) {
      print('❌ My public key is null');
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.chatPublicKeyNotFoundError), backgroundColor: Colors.red),
      );
      return;
    }

    bool success = true;

    // Se c'è una data/range selezionato, invia come todo
    if (todoDate != null) {
      // Upload allegati se presenti (con cifratura E2E dual)
      List<Attachment>? uploadedAttachments;
      if (attachments.isNotEmpty) {
        try {
          uploadedAttachments = await _attachmentService!.uploadMultipleAttachments(
            attachments,
            _familyChatId!,
            _myDeviceId!,
            myPublicKey, // Chiave pubblica mittente
            _partnerPublicKey!, // Chiave pubblica destinatario
          );

          if (uploadedAttachments.isEmpty) {
            throw Exception('No attachments uploaded');
          }

          if (kDebugMode) {
            print('✅ ${uploadedAttachments.length} attachments uploaded successfully for TODO');
          }
        } catch (e) {
          if (kDebugMode) print('❌ Error uploading TODO attachments: $e');
          setState(() => _isUploadingAttachments = false);
          final l10n = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.chatAttachmentUploadError),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }

      if (isRange && rangeStart != null && rangeEnd != null) {
        // RANGE DI DATE: crea UN SOLO TODO con rangeEnd salvato nel database
        print('📅 Sending TODO with range...');
        print('   Range: ${rangeStart.toString()} to ${rangeEnd.toString()}');
        print('   Content: $messageText');
        print('   Attachments: ${uploadedAttachments?.length ?? 0}');

        // Crea TODO con data = primo giorno del range alle 10:00
        final todoDueDate = DateTime(
          rangeStart.year,
          rangeStart.month,
          rangeStart.day,
          10, // Default 10:00
          0,
        );

        // Salva rangeEnd come parametro separato (NON nel testo)
        success = await chatService.sendTodo(
          messageText, // Solo il testo dell'utente, NO range
          todoDueDate,
          _familyChatId!,
          _myDeviceId!,
          myPublicKey,
          _partnerPublicKey!,
          rangeEnd: rangeEnd, // Passa rangeEnd come parametro
          attachments: uploadedAttachments, // Passa attachments
        );

        if (success && reminderHours != null && reminderHours > 0) {
          final reminderDate = todoDueDate.subtract(Duration(hours: reminderHours));
          await chatService.sendTodoReminder(
            messageText, // Solo il testo dell'utente, NO range
            reminderDate,
            todoDueDate,
            _familyChatId!,
            _myDeviceId!,
            myPublicKey,
            _partnerPublicKey!,
            rangeEnd: rangeEnd, // Passa rangeEnd anche al reminder
            attachments: uploadedAttachments, // Passa attachments anche al reminder
          );
        }

        print('✅ Sent TODO with range: $messageText (range: $rangeStart - $rangeEnd)');
      } else {
        // DATA SINGOLA CON ORA SPECIFICA
        print('📅 Sending single todo...');
        print('   Due date: ${todoDate.toIso8601String()}');
        print('   Content: $messageText');
        print('   Attachments: ${uploadedAttachments?.length ?? 0}');

        success = await chatService.sendTodo(
          messageText,
          todoDate,
          _familyChatId!,
          _myDeviceId!,
          myPublicKey,
          _partnerPublicKey!,
          attachments: uploadedAttachments, // Passa attachments
        );

        if (success && reminderHours != null && reminderHours > 0) {
          final reminderDate = todoDate.subtract(Duration(hours: reminderHours));
          await chatService.sendTodoReminder(
            messageText,
            reminderDate,
            todoDate,
            _familyChatId!,
            _myDeviceId!,
            myPublicKey,
            _partnerPublicKey!,
            attachments: uploadedAttachments, // Passa attachments anche al reminder
          );
          print('✅ Todo sent with reminder ($reminderHours hours before)');
        } else {
          print('✅ Todo sent without reminder');
        }
      }
    } else {
      print('📤 Sending message...');
      print('   To family chat: $_familyChatId');
      print('   From device: $_myDeviceId');
      print('   Content: $messageText');
      print('   Attachments: ${attachments.length}');

      // Aggiungi messaggio pending subito (invio ottimistico)
      String? pendingMessageId;
      if (messageText.isNotEmpty || placeholderAttachments != null) {
        pendingMessageId = chatService.addPendingMessage(
          messageText,
          _myDeviceId!,
          placeholderAttachments,
        );
      }

      // Upload allegati se presenti (con cifratura E2E dual)
      List<Attachment>? uploadedAttachments;
      if (attachments.isNotEmpty) {
        try {
          uploadedAttachments = await _attachmentService!.uploadMultipleAttachments(
            attachments,
            _familyChatId!,
            _myDeviceId!,
            myPublicKey, // Chiave pubblica mittente
            _partnerPublicKey!, // Chiave pubblica destinatario
          );

          if (uploadedAttachments.isEmpty) {
            throw Exception('No attachments uploaded');
          }

          if (kDebugMode) {
            print('✅ ${uploadedAttachments.length} attachments uploaded successfully');
          }
        } catch (e) {
          if (kDebugMode) print('❌ Error uploading attachments: $e');
          // Rimuovi messaggio pending in caso di errore
          if (pendingMessageId != null) {
            chatService.removePendingMessage(pendingMessageId);
          }
          setState(() => _isUploadingAttachments = false);
          final l10n = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.chatAttachmentUploadError),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }

      success = await chatService.sendMessage(
        messageText,
        _familyChatId!,
        _myDeviceId!,
        myPublicKey,
        _partnerPublicKey!,
        attachments: uploadedAttachments,
      );

      // Rimuovi messaggio pending dopo invio (successo o fallimento)
      if (pendingMessageId != null) {
        chatService.removePendingMessage(pendingMessageId);
      }

      if (success) {
        print('✅ Message sent successfully with dual encryption');
        if (uploadedAttachments != null) {
          print('   With ${uploadedAttachments.length} attachments');
        }
      }
    }

    // Reset loading state
    setState(() => _isUploadingAttachments = false);

    if (success) {
      // Scrolla in fondo dopo l'invio
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } else {
      print('❌ Send failed');
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(todoDate != null ? l10n.chatSendTodoError : l10n.chatSendMessageError),
          backgroundColor: Colors.red,
        ),
      );
    }

    // Pulisci i file temporanei iOS DOPO l'upload
    _cleanupAllIOSFiles();
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
    // MA non scrollare per messaggi di completamento todo (per evitare scroll indesiderato dopo long press)
    if (isSingleNewMessage && chatService.messages.isNotEmpty) {
      _lastMessageCount = currentCount;

      // Controlla se l'ultimo messaggio è un todo_completed (primo perché reverse: true)
      final lastMessage = chatService.messages.first;
      final shouldScroll = lastMessage.messageType != 'todo_completed';

      // ✅ REAL-TIME READ RECEIPTS: Marca come letti i messaggi ricevuti quando la chat è aperta
      // Questo fa sì che il mittente veda immediatamente le doppie spunte blu
      if (_myDeviceId != null && _familyChatId != null) {
        // Marca solo se il nuovo messaggio NON è stato inviato da me
        if (lastMessage.senderId != _myDeviceId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            chatService.markAllMessagesAsRead(_familyChatId!, _myDeviceId!);
            if (kDebugMode) print('✅ [READ_RECEIPTS] Auto-marked messages as read (new message received)');
          });
        }
      }

      if (shouldScroll) {
        if (kDebugMode) print('📜 [SCROLL] New message - smooth scroll to bottom');

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scrollController.hasClients) {
            _scrollToBottom(animated: true);
            if (kDebugMode) print('✅ [SCROLL] Scrolled to bottom (new message)');
          }
        });
      } else {
        if (kDebugMode) print('📜 [SCROLL] Todo completed - no auto-scroll');
      }
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

    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: chatService.messages.isEmpty
                ? Center(
                    child: Text(
                      l10n.chatEmptyMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  )
                : Column(
                    children: [
                      // 📜 Indicatore caricamento messaggi vecchi
                      if (_isLoadingOlderMessages)
                        Container(
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                l10n.chatLoadingMessages,
                                style: const TextStyle(color: Colors.grey, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      Expanded(
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(12, 60, 12, 2),
                          itemCount: chatService.messages.length,
                          reverse: true, // 🔧 FIX: reverse per mostrare nuovi messaggi in basso
                          itemBuilder: (context, index) {
                            final message = chatService.messages[index];
                            final isMe = message.senderId == _myDeviceId;

                            if (kDebugMode && message.isPending == true) {
                              print('🎨 [RENDER] Building pending message at index $index, id: ${message.id}');
                            }

                            // Verifica se è un messaggio di completamento todo
                            if (message.messageType == 'todo_completed') {
                              // Non mostrare i messaggi di completamento
                              return const SizedBox.shrink();
                            }

                            // Nascondi TODO/reminder futuri (timestamp futuro)
                            if (message.messageType == 'todo') {
                              if (message.timestamp.isAfter(DateTime.now())) {
                                // TODO futuro, nascondilo
                                return const SizedBox.shrink();
                              }
                            }

                            // Verifica se il todo è stato completato
                            bool isTodoCompleted = false;
                            if (message.messageType == 'todo') {
                              // TODO completato se ha action COMPLETE oppure messaggio todo_completed
                              isTodoCompleted = message.action?.type == 'complete' ||
                                  chatService.messages.any((m) =>
                                      m.messageType == 'todo_completed' &&
                                      m.originalTodoId == message.id);
                            }

                            // Determina se mostrare il separatore di data
                            // Trova il prossimo messaggio VISIBILE (salta todo_completed e TODO futuri)
                            Message? nextVisibleMessage;
                            for (int i = index + 1; i < chatService.messages.length; i++) {
                              final candidateMessage = chatService.messages[i];

                              // Salta todo_completed
                              if (candidateMessage.messageType == 'todo_completed') {
                                continue;
                              }

                              // Salta TODO futuri
                              if (candidateMessage.messageType == 'todo' &&
                                  candidateMessage.timestamp.isAfter(DateTime.now())) {
                                continue;
                              }

                              // Trovato il prossimo messaggio visibile
                              nextVisibleMessage = candidateMessage;
                              break;
                            }

                            final showDateSeparator = _shouldShowDateSeparator(message, nextVisibleMessage);

                            // Widget del messaggio
                            Widget messageWidget;
                            if (message.messageType == 'todo') {
                              // Formatta la data del TODO
                              String? formattedDate;
                              if (message.dueDate != null) {
                                final l10n = AppLocalizations.of(context)!;

                                if (message.rangeEnd != null) {
                                  // È un range: formatta in modo intelligente
                                  formattedDate = _formatDateRange(message.dueDate!, message.rangeEnd!);
                                } else {
                                  // Data singola con ora in formato colloquiale
                                  formattedDate = _formatTodoDate(message.dueDate!, includeTime: true);
                                }
                              }

                              messageWidget = TodoMessageBubble(
                                key: ValueKey(message.id), // Key stabile basata solo sull'ID
                                message: message,
                                isMe: isMe,
                                isCompleted: isTodoCompleted,
                                onReact: (reactionType) => _addReaction(message.id, reactionType),
                                onAction: (actionType) => _addAction(message.id, actionType, message),
                                formattedDate: formattedDate,
                                attachmentService: _attachmentService,
                                senderId: message.senderId,
                                currentUserId: _myDeviceId,
                              );
                            } else {
                              // Messaggio normale
                              final decryptedContent = message.decryptedContent ?? '[Messaggio non decifrabile]';

                              messageWidget = _MessageBubble(
                                key: ValueKey(message.id), // Key stabile basata solo sull'ID
                                message: decryptedContent,
                                timestamp: message.timestamp,
                                isMe: isMe,
                                delivered: message.delivered ?? false,
                                read: message.read ?? false,
                                attachments: message.attachments,
                                senderId: message.senderId,
                                currentUserId: _myDeviceId,
                                attachmentService: _attachmentService,
                                reaction: message.reaction,
                                onReact: (reactionType) => _addReaction(message.id, reactionType),
                                messageObject: message,
                              );
                            }

                            // Se serve un separatore, avvolgi il messaggio in una Column
                            if (showDateSeparator) {
                              return Column(
                                children: [
                                  _DateSeparator(
                                    dateLabel: _formatDateSeparator(message.timestamp),
                                  ),
                                  messageWidget,
                                ],
                              );
                            }

                            return messageWidget;
                          },
                        ),
                      ),
                      // 💬 Indicatore "Sta scrivendo..."
                      if (chatService.partnerIsTyping)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.grey[400]!),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                l10n.chatTypingIndicator,
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 13,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(
              8,
              12,
              8,
              12 + MediaQuery.of(context).padding.bottom,
            ),
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
            child: Column(
                children: [
                  // Mostra allegati selezionati
                  // Preview data/range/alert selezionata per todo
                  if (_selectedTodoDate != null || _selectedRangeStart != null)
                    Container(
                      padding: const EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 13),
                      decoration: const BoxDecoration(
                        color: Colors.transparent,
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: _TodoDatePreview(
                          date: _selectedTodoDate,
                          rangeStart: _selectedRangeStart,
                          rangeEnd: _selectedRangeEnd,
                          reminderHours: _selectedReminderHours,
                          onRemove: () {
                            setState(() {
                              _selectedTodoDate = null;
                              _isRangeSelection = false;
                              _selectedRangeStart = null;
                              _selectedRangeEnd = null;
                              _selectedReminderHours = null;
                            });
                          },
                        ),
                      ),
                    ),
                  // Preview allegati selezionati
                  if (_selectedAttachments.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        border: Border(
                          bottom: BorderSide(color: Colors.grey[300]!),
                        ),
                      ),
                      child: SizedBox(
                        height: 80,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _selectedAttachments.length,
                          itemBuilder: (context, index) {
                            final file = _selectedAttachments[index];
                            return _AttachmentPreview(
                              file: file,
                              onRemove: () {
                                // Pulisci il file iOS prima di rimuoverlo
                                _cleanupIOSFile(file.path);
                                setState(() {
                                  _selectedAttachments.removeAt(index);
                                });
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  // Preview allegati esistenti (durante modifica)
                  if (_editingAttachments.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        border: Border(
                          bottom: BorderSide(color: Colors.grey[300]!),
                        ),
                      ),
                      child: SizedBox(
                        height: 80,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _editingAttachments.length,
                          itemBuilder: (context, index) {
                            final attachment = _editingAttachments[index];
                            return _ExistingAttachmentPreview(
                              attachment: attachment,
                              attachmentService: _attachmentService,
                              currentUserId: _myDeviceId,
                              messageSenderId: _editingMessageSenderId,
                              onRemove: () {
                                setState(() {
                                  _editingAttachments.removeAt(index);
                                });
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: _editingMessageId != null
                            ? null // Disabilita l'aggiunta di nuovi allegati durante la modifica
                            : _showAttachmentPicker,
                        icon: const Icon(Icons.add_circle_outline),
                        color: _selectedAttachments.isNotEmpty
                            ? const Color(0xFF3BA8B0)
                            : Colors.grey[600],
                        tooltip: l10n.chatAttachmentsTooltip,
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
                          hintText: _selectedTodoDate != null
                              ? l10n.chatTodoPlaceholder
                              : l10n.chatWritePlaceholder,
                          hintStyle: TextStyle(color: Colors.grey[500]),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _selectedTodoDate != null
                                  ? Icons.calendar_month
                                  : Icons.calendar_month_outlined,
                              color: _selectedTodoDate != null
                                  ? const Color(0xFF3BA8B0)
                                  : Colors.grey[600],
                            ),
                            onPressed: _showDateTimePicker,
                            tooltip: l10n.chatSetDateTimeTooltip,
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
                    scale: _canSend ? 1.0 : 0.8,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutBack,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        gradient: _canSend
                            ? const LinearGradient(
                                colors: [
                                  Color(0xFF3BA8B0),
                                  Color(0xFF145A60),
                                ],
                              )
                            : LinearGradient(
                                colors: [
                                  Colors.grey[300]!,
                                  Colors.grey[400]!,
                                ],
                              ),
                        shape: BoxShape.circle,
                        boxShadow: _canSend
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF3BA8B0).withOpacity(0.4),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : [],
                      ),
                      child: IconButton(
                        onPressed: _canSend ? _sendMessage : null,
                        icon: const Icon(Icons.send_rounded),
                        color: Colors.white,
                        iconSize: 22,
                      ),
                    ),
                      ),
                    ],
                  ),
                ],
              ),
          ),
        ],
      ),
    );
  }
}

/// Widget per le opzioni di selezione allegati nel bottom sheet
class _AttachmentOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _AttachmentOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white70, size: 24),
          ],
        ),
      ),
    );
  }
}

/// Widget per mostrare preview degli allegati selezionati
class _AttachmentPreview extends StatelessWidget {
  final File file;
  final VoidCallback onRemove;

  const _AttachmentPreview({
    required this.file,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final fileName = file.path.split('/').last;
    final isImage = fileName.toLowerCase().endsWith('.jpg') ||
        fileName.toLowerCase().endsWith('.jpeg') ||
        fileName.toLowerCase().endsWith('.png');

    return Container(
      width: 80,
      margin: const EdgeInsets.only(right: 8),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Colors.grey[300],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: isImage
                  ? Image.file(
                      file,
                      fit: BoxFit.cover,
                      width: 80,
                      height: 80,
                    )
                  : Center(
                      child: Icon(
                        Icons.insert_drive_file,
                        size: 32,
                        color: Colors.grey[600],
                      ),
                    ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close,
                  size: 16,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

}

/// Widget per mostrare allegati esistenti durante la modifica
class _ExistingAttachmentPreview extends StatelessWidget {
  final Attachment attachment;
  final VoidCallback onRemove;
  final AttachmentService? attachmentService;
  final String? currentUserId;
  final String? messageSenderId;

  const _ExistingAttachmentPreview({
    required this.attachment,
    required this.onRemove,
    this.attachmentService,
    this.currentUserId,
    this.messageSenderId,
  });

  @override
  Widget build(BuildContext context) {
    final isImage = attachment.type == 'photo';
    final isVideo = attachment.type == 'video';

    return Container(
      width: 80,
      margin: const EdgeInsets.only(right: 8),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Colors.grey[300],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: isImage && attachmentService != null && currentUserId != null && messageSenderId != null
                  ? FutureBuilder<Uint8List?>(
                      future: attachmentService!.downloadAndDecryptAttachment(
                        attachment,
                        currentUserId!,
                        messageSenderId!,
                      ),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const SizedBox(
                            width: 80,
                            height: 80,
                            child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        }
                        if (snapshot.hasData && snapshot.data != null) {
                          return Image.memory(
                            snapshot.data!,
                            fit: BoxFit.cover,
                            width: 80,
                            height: 80,
                          );
                        }
                        // Fallback su icona se caricamento fallisce
                        return Center(
                          child: Icon(
                            Icons.image,
                            size: 40,
                            color: Colors.grey[600],
                          ),
                        );
                      },
                    )
                  : Center(
                      child: Icon(
                        isImage
                            ? Icons.image
                            : isVideo
                                ? Icons.videocam
                                : Icons.insert_drive_file,
                        size: 40,
                        color: Colors.grey[600],
                      ),
                    ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close,
                  size: 16,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Widget per mostrare preview data/range/alert selezionata per todo
class _TodoDatePreview extends StatelessWidget {
  final DateTime? date;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final int? reminderHours;
  final VoidCallback onRemove;

  const _TodoDatePreview({
    this.date,
    this.rangeStart,
    this.rangeEnd,
    this.reminderHours,
    required this.onRemove,
  });

  String _formatDate(BuildContext context, DateTime date) {
    final l10n = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final dateDay = DateTime(date.year, date.month, date.day);

    if (dateDay == DateTime(now.year, now.month, now.day)) {
      return l10n.todayAt(DateFormat('HH:mm').format(date));
    } else if (dateDay == tomorrow) {
      return l10n.tomorrowAt(DateFormat('HH:mm').format(date));
    } else {
      return DateFormat('dd/MM HH:mm').format(date);
    }
  }

  String _formatRange(DateTime start, DateTime end) {
    return '${DateFormat('dd/MM').format(start)} - ${DateFormat('dd/MM').format(end)}';
  }

  String _formatReminder(BuildContext context, int hours) {
    final l10n = AppLocalizations.of(context)!;
    if (hours == 1) return l10n.alertOneHourBefore;
    if (hours == 48) return l10n.alertTwoDaysBefore;
    if (hours == 24) return l10n.alertOneDayBefore;
    return l10n.alertHoursBefore(hours);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    String dateText;
    if (rangeStart != null && rangeEnd != null) {
      dateText = _formatRange(rangeStart!, rangeEnd!);
    } else if (date != null) {
      dateText = _formatDate(context, date!);
    } else {
      dateText = 'Data non selezionata';
    }

    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF3BA8B0),
            Color(0xFF145A60),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(4),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3BA8B0).withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            rangeStart != null && rangeEnd != null
                ? Icons.date_range
                : Icons.calendar_today_outlined,
            color: Colors.white.withOpacity(0.9),
            size: 14,
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                dateText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
              if (reminderHours != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.notifications_outlined,
                      size: 14,
                      color: Colors.white.withOpacity(0.9),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatReminder(context, reminderHours!),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close,
                size: 16,
                color: Colors.red,
              ),
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
  final bool delivered;
  final bool read;
  final List<Attachment>? attachments;
  final String? senderId; // ID del mittente del messaggio
  final String? currentUserId; // ID dell'utente corrente
  final AttachmentService? attachmentService;
  final Reaction? reaction; // Reaction al messaggio
  final Function(String reactionType)? onReact; // Callback per aggiungere reaction
  final Message? messageObject; // Oggetto Message completo per il ReactionPicker

  const _MessageBubble({
    super.key,
    required this.message,
    required this.timestamp,
    required this.isMe,
    this.delivered = false,
    this.read = false,
    this.attachments,
    this.senderId,
    this.currentUserId,
    this.attachmentService,
    this.reaction,
    this.onReact,
    this.messageObject,
  });

  /// Estrae i link dal testo del messaggio
  List<String> _extractLinks(String text) {
    final urlRegex = RegExp(
      r'https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)',
      caseSensitive: false,
    );
    final matches = urlRegex.allMatches(text);
    return matches.map((match) => match.group(0)!).toList();
  }

  /// Verifica se il messaggio contiene solo un link (senza altro testo)
  bool _isOnlyLink() {
    if (message.isEmpty) return false;
    final links = _extractLinks(message);
    if (links.isEmpty) return false;
    // Se c'è esattamente 1 link e il messaggio trimmed è uguale al link, è solo link
    return links.length == 1 && message.trim() == links.first;
  }

  /// Costruisce i widget per le anteprime dei link
  List<Widget> _buildLinkPreviews() {
    // Non mostrare link preview se il messaggio è vuoto, eliminato, o è un tipo speciale
    if (message.isEmpty ||
        messageObject?.deleted == true ||
        messageObject?.messageType == 'location_share') {
      return [];
    }

    final links = _extractLinks(message);
    if (links.isEmpty) return [];

    return links.map((link) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: AttachmentLinkPreview(
        url: link,
        isMe: isMe,
      ),
    )).toList();
  }

  /// Costruisce i widget per mostrare gli allegati (decifrati)
  List<Widget> _buildAttachments(BuildContext context) {
    // Caso speciale: location_share
    if (messageObject?.messageType == 'location_share') {
      return [
        AttachmentLocationShare(
          message: messageObject!,
          isMe: isMe,
          onTap: () {
            // Estrai sessionId dal body del messaggio
            // Formato: "location_share|expiresAt|sessionId"
            String sessionId = '';
            if (messageObject?.decryptedContent != null) {
              final parts = messageObject?.decryptedContent?.split('|') ?? [];
              if (parts.length >= 3) {
                sessionId = parts[2]; // sessionId è il terzo elemento
              }
            }

            // Apri schermata di navigazione con sessionId
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => LocationSharingScreen(
                  expectedSessionId: sessionId,
                  isSender: isMe, // Passa se l'utente è il mittente
                ),
              ),
            );
          },
        ),
      ];
    }

    if (attachments == null || attachments!.isEmpty) {
      return [];
    }

    // Se attachmentService non è disponibile, non mostrare allegati
    if (attachmentService == null) {
      return [];
    }

    return [
      ...attachments!.map((attachment) {
        if (attachment.type == 'photo') {
          return AttachmentImage(
            key: ValueKey(attachment.id), // Key stabile per mantenere lo State
            attachment: attachment,
            isMe: isMe,
            currentUserId: currentUserId,
            senderId: senderId,
            attachmentService: attachmentService!,
          );
        } else if (attachment.type == 'video') {
          return AttachmentVideo(
            key: ValueKey(attachment.id), // Key stabile per mantenere lo State
            attachment: attachment,
            isMe: isMe,
            currentUserId: currentUserId,
            senderId: senderId,
          );
        } else {
          return AttachmentDocument(
            key: ValueKey(attachment.id), // Key stabile per mantenere lo State
            attachment: attachment,
            isMe: isMe,
            currentUserId: currentUserId,
            senderId: senderId,
            attachmentService: attachmentService!,
          );
        }
      }),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 8, right: 8),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                onLongPress: onReact != null && messageObject != null
                    ? () {
                        ReactionPicker.show(
                          context,
                          onReactionSelected: (reactionType) => onReact!(reactionType),
                          onActionSelected: (actionType) {
                            // Chiama _addAction con l'oggetto messaggio completo per gestire logica
                            final chatScreenState = context.findAncestorStateOfType<_ChatScreenState>();
                            chatScreenState?._addAction(messageObject!.id, actionType, messageObject!);
                          },
                          message: messageObject!,
                          attachmentService: attachmentService,
                          currentUserId: currentUserId,
                          senderId: senderId,
                        );
                      }
                    : null,
                child: Container(
            constraints: BoxConstraints(
              maxWidth: (attachments != null && attachments!.any((a) => a.type == 'photo'))
                  ? 200 // Larghezza fissa quando c'è una foto
                  : MediaQuery.of(context).size.width * 0.75, // Larghezza variabile senza foto
            ),
            decoration: BoxDecoration(
              gradient: isMe
                  ? const LinearGradient(
                      colors: [
                        Color(0xFF3BA8B0), // Purple
                        Color(0xFF145A60), // Deep purple
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
                      ? const Color(0xFF3BA8B0).withOpacity(0.3)
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
                bottomLeft: isMe
                    ? const Radius.circular(20)
                    : const Radius.circular(4),
                bottomRight: isMe
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Allegati (se presenti) - senza padding per occupare tutta la larghezza
                      if (attachments != null && attachments!.isNotEmpty || messageObject?.messageType == 'location_share')
                        ..._buildAttachments(context),
                      // Testo e timestamp con padding (nascondi testo per location_share)
                      if (messageObject?.messageType != 'location_share')
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Mostra "Messaggio eliminato" se deleted == true
                              if (messageObject?.deleted == true) ...[
                                Text(
                                  l10n.messageDeleted,
                                  style: TextStyle(
                                    color: isMe ? Colors.white.withOpacity(0.7) : Colors.black54,
                                    fontSize: 15,
                                    height: 1.4,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                                const SizedBox(height: 4),
                              ]
                              // Testo del messaggio (se presente e non eliminato)
                              // Se il messaggio contiene SOLO un link, mostra solo la preview (non il testo)
                              else if (message.isNotEmpty && !_isOnlyLink()) ...[
                                Linkify(
                                  onOpen: (link) async {
                                    try {
                                      final uri = Uri.parse(link.url);
                                      await launchUrl(
                                        uri,
                                        mode: LaunchMode.externalApplication,
                                      );
                                    } catch (e) {
                                      if (kDebugMode) {
                                        print('Errore apertura URL: $e');
                                      }
                                    }
                                  },
                                  text: message,
                                  style: TextStyle(
                                    color: isMe ? Colors.white : Colors.black87,
                                    fontSize: 15,
                                    height: 1.4,
                                  ),
                                  linkStyle: TextStyle(
                                    color: isMe ? Colors.white : Colors.blue,
                                    fontSize: 15,
                                    height: 1.4,
                                    decoration: TextDecoration.underline,
                                  ),
                                  options: const LinkifyOptions(
                                    humanize: false,
                                    looseUrl: true,
                                  ),
                                ),
                              ],
                              // Anteprime dei link (sempre mostrate se ci sono link)
                              ..._buildLinkPreviews(),
                              const SizedBox(height: 4),
                            ],
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  DateFormat('HH:mm').format(timestamp),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isMe
                                        ? Colors.white.withOpacity(0.8)
                                        : Colors.black54,
                                  ),
                                ),
                                // Mostra le spunte solo per i messaggi inviati da me
                                if (isMe) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    read ? Icons.done_all : Icons.done,
                                    size: 14,
                                    color: read
                                        ? Colors.blue[300]
                                        : Colors.white.withOpacity(0.8),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
                ),
              ),
              // Reaction overlay se presente
              if (reaction != null) ReactionOverlay(reaction: reaction!),
            ],
          ),
        ],
      ),
    );
  }
}
class _DateSeparator extends StatelessWidget {
  final String dateLabel;

  const _DateSeparator({
    required this.dateLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Colors.grey[300]!,
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF3BA8B0),
                    Color(0xFF145A60),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF3BA8B0).withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.flag_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    dateLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.grey[300]!,
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

