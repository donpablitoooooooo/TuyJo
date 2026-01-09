import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:private_messaging/generated/l10n/app_localizations.dart';
import '../services/pairing_service.dart';
import '../services/chat_service.dart';
import '../services/encryption_service.dart';
import '../services/notification_service.dart';
import '../services/attachment_service.dart';
import '../models/message.dart';
import 'pdf_viewer_screen.dart';

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

  // Stream subscription per condivisione file da altre app
  StreamSubscription? _intentMediaStreamSubscription;

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
    // Per file media (immagini, video, documenti) condivisi mentre l'app è chiusa
    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
      if (value.isNotEmpty) {
        _handleSharedFiles(value);
      }
    });

    // Per file media condivisi mentre l'app è aperta
    _intentMediaStreamSubscription = ReceiveSharingIntent.instance.getMediaStream().listen(
      (List<SharedMediaFile> value) {
        if (value.isNotEmpty) {
          _handleSharedFiles(value);
        }
      },
      onError: (err) {
        if (kDebugMode) print("Errore ricezione file condivisi: $err");
      },
    );
  }

  /// Gestisce file media condivisi da altre app
  void _handleSharedFiles(List<SharedMediaFile> sharedFiles) {
    if (kDebugMode) {
      print("📤 Ricevuti ${sharedFiles.length} file condivisi");
    }

    // Usa addPostFrameCallback per assicurarsi che il widget sia completamente inizializzato
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      setState(() {
        for (var sharedFile in sharedFiles) {
          final file = File(sharedFile.path);
          if (!_selectedAttachments.any((f) => f.path == file.path)) {
            _selectedAttachments.add(file);
          }
        }
      });

      // Reset condivisione intent per evitare duplicati
      ReceiveSharingIntent.instance.reset();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Quando l'app torna in foreground, marca i messaggi come letti
    if (state == AppLifecycleState.resumed) {
      if (_familyChatId != null && _myDeviceId != null) {
        final chatService = Provider.of<ChatService>(context, listen: false);
        chatService.markAllMessagesAsRead(_familyChatId!, _myDeviceId!);
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
    _intentMediaStreamSubscription?.cancel();
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
              colors: [Color(0xFF667eea), Color(0xFF764ba2)],
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
                  final file = await _attachmentService!.pickImageFromGallery();
                  if (file != null) {
                    setState(() {
                      _selectedAttachments.add(file);
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
              const SizedBox(height: 16),
            ],
          ), // Chiude Column
        ), // Chiude Padding
      ), // Chiude Container
    ), // Chiude ClipRRect
    ); // Chiude showModalBottomSheet
  } // Chiude _showAttachmentPicker

  void _showDateTimePicker() async {
    final l10n = AppLocalizations.of(context)!;
    // Sentinella per segnalare cancellazione
    final clearResult = {'clear': true};

    DateTime selectedDate = DateTime.now().add(const Duration(days: 1));
    DateTime? rangeStart;
    DateTime? rangeEnd;
    int selectedHour = 10;
    int selectedMinute = 0;
    int? selectedReminderHours = _selectedReminderHours ?? 1; // Default: 1 ora prima

    final hourController = FixedExtentScrollController(initialItem: selectedHour);
    final minuteController = FixedExtentScrollController(initialItem: selectedMinute);

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: Container(
            height: MediaQuery.of(context).size.height * 0.80,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF667eea), Color(0xFF764ba2)],
              ),
            ),
            child: Column(
              children: [
                // Header con X a sinistra e check a destra
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          onPressed: () {
                            // Se c'è una data selezionata, cancellala
                            if (_selectedTodoDate != null) {
                              Navigator.pop(context, clearResult);
                            } else {
                              Navigator.pop(context);
                            }
                          },
                          icon: const Icon(Icons.close, color: Colors.white, size: 28),
                        ),
                        IconButton(
                          onPressed: () {
                            if (rangeStart != null && rangeEnd != null) {
                              // Range selezionato: ritorna range senza ora
                              Navigator.pop(context, {
                                'isRange': true,
                                'rangeStart': rangeStart,
                                'rangeEnd': rangeEnd,
                                'reminderHours': selectedReminderHours,
                              });
                            } else if (rangeStart != null && rangeEnd == null) {
                              // Data singola: ritorna con ora
                              final dueDate = DateTime(
                                selectedDate.year,
                                selectedDate.month,
                                selectedDate.day,
                                selectedHour,
                                selectedMinute,
                              );
                              Navigator.pop(context, {
                                'isRange': false,
                                'date': dueDate,
                                'reminderHours': selectedReminderHours,
                              });
                            }
                          },
                          icon: const Icon(Icons.check_circle, color: Colors.white, size: 32),
                          tooltip: l10n.chatConfirm,
                        ),
                      ],
                    ),
                  ),
                ),
                // Calendar con theme viola
                Expanded(
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
                      calendarStyle: CalendarStyle(
                        defaultTextStyle: const TextStyle(color: Colors.white),
                        weekendTextStyle: const TextStyle(color: Colors.white70),
                        outsideTextStyle: const TextStyle(color: Colors.white30),
                        selectedDecoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          shape: BoxShape.circle,
                        ),
                        selectedTextStyle: const TextStyle(color: Color(0xFF667eea), fontWeight: FontWeight.bold),
                        todayDecoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.3),
                          shape: BoxShape.circle,
                        ),
                        todayTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        rangeStartDecoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          shape: BoxShape.circle,
                        ),
                        rangeStartTextStyle: const TextStyle(color: Color(0xFF667eea), fontWeight: FontWeight.bold),
                        rangeEndDecoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          shape: BoxShape.circle,
                        ),
                        rangeEndTextStyle: const TextStyle(color: Color(0xFF667eea), fontWeight: FontWeight.bold),
                        rangeHighlightColor: Colors.white.withOpacity(0.2),
                        withinRangeDecoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        withinRangeTextStyle: const TextStyle(color: Colors.white),
                      ),
                      daysOfWeekStyle: const DaysOfWeekStyle(
                        weekdayStyle: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
                        weekendStyle: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
                      ),
                      onDaySelected: (selectedDay, focusedDay) {
                        setModalState(() {
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
                // Time picker con dropdown alert (time picker nascosto se range selezionato)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF764ba2).withOpacity(0.3),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Time picker (nascosto se range completo)
                      if (rangeStart == null || rangeEnd == null) ...[
                      // Hour picker
                      SizedBox(
                        width: 70,
                        height: 140,
                        child: CupertinoPicker(
                          scrollController: hourController,
                          itemExtent: 40,
                          onSelectedItemChanged: (index) {
                            setModalState(() => selectedHour = index);
                          },
                          selectionOverlay: Container(
                            decoration: BoxDecoration(
                              border: Border.symmetric(
                                horizontal: BorderSide(
                                  color: Colors.white.withOpacity(0.5),
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                          children: List.generate(
                            24,
                            (index) => Center(
                              child: Text(
                                index.toString().padLeft(2, '0'),
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          ':',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      // Minute picker
                      SizedBox(
                        width: 70,
                        height: 140,
                        child: CupertinoPicker(
                          scrollController: minuteController,
                          itemExtent: 40,
                          onSelectedItemChanged: (index) {
                            setModalState(() => selectedMinute = index);
                          },
                          selectionOverlay: Container(
                            decoration: BoxDecoration(
                              border: Border.symmetric(
                                horizontal: BorderSide(
                                  color: Colors.white.withOpacity(0.5),
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                          children: List.generate(
                            60,
                            (index) => Center(
                              child: Text(
                                index.toString().padLeft(2, '0'),
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      ], // Fine time picker condizionale
                      // Dropdown alert compatto (sempre visibile)
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.notifications_outlined, color: Colors.white.withOpacity(0.7), size: 18),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<int?>(
                                value: selectedReminderHours,
                                dropdownColor: const Color(0xFF764ba2),
                                icon: Icon(Icons.arrow_drop_down, color: Colors.white.withOpacity(0.7), size: 16),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                                items: [
                                  DropdownMenuItem(value: null, child: Text(l10n.reminderNone)),
                                  DropdownMenuItem(value: 1, child: Text(l10n.reminder1Hour)),
                                  ...List.generate(23, (i) => i + 2).map((h) =>
                                    DropdownMenuItem(
                                      value: h,
                                      child: Text(l10n.reminderHours(h)),
                                    )
                                  ),
                                  DropdownMenuItem(value: 48, child: Text(l10n.reminder2Days)),
                                ],
                                onChanged: (value) {
                                  setModalState(() => selectedReminderHours = value);
                                },
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
          ),
        ),
      ),
    );

    hourController.dispose();
    minuteController.dispose();

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

  void _sendMessage() async {
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
      placeholderAttachments = attachments.map((file) {
        final fileName = file.path.split('/').last;
        return Attachment(
          id: 'uploading_${DateTime.now().millisecondsSinceEpoch}',
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
                              isTodoCompleted = chatService.messages.any((m) =>
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

                              messageWidget = _TodoMessageBubble(
                                key: ValueKey('${message.id}_${message.read}'),
                                message: message,
                                isMe: isMe,
                                isCompleted: isTodoCompleted,
                                onComplete: () => _completeTodo(message.id),
                                formattedDate: formattedDate,
                                attachmentService: _attachmentService,
                                senderId: message.senderId,
                                currentUserId: _myDeviceId,
                              );
                            } else {
                              // Messaggio normale
                              final decryptedContent = message.decryptedContent ?? '[Messaggio non decifrabile]';

                              messageWidget = _MessageBubble(
                                key: ValueKey('${message.senderId}_${message.timestamp.millisecondsSinceEpoch}_${message.read}'),
                                message: decryptedContent,
                                timestamp: message.timestamp,
                                isMe: isMe,
                                delivered: message.delivered ?? false,
                                read: message.read ?? false,
                                attachments: message.attachments,
                                senderId: message.senderId,
                                currentUserId: _myDeviceId,
                                attachmentService: _attachmentService,
                              );
                            }

                            // Se serve un separatore, avvolgi il messaggio in una Column
                            if (showDateSeparator) {
                              return Column(
                                children: [
                                  messageWidget,
                                  _DateSeparator(
                                    dateLabel: _formatDateSeparator(message.timestamp),
                                  ),
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
                                setState(() {
                                  _selectedAttachments.removeAt(index);
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
                        onPressed: _showAttachmentPicker,
                        icon: const Icon(Icons.add_circle_outline),
                        color: _selectedAttachments.isNotEmpty
                            ? const Color(0xFF667eea)
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
                                  ? const Color(0xFF667eea)
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
                        boxShadow: _canSend
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

class _MessageBubble extends StatefulWidget {
  final String message;
  final DateTime timestamp;
  final bool isMe;
  final bool delivered;
  final bool read;
  final List<Attachment>? attachments;
  final String? senderId; // ID del mittente del messaggio
  final String? currentUserId; // ID dell'utente corrente
  final AttachmentService? attachmentService;

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

  /// Costruisce i widget per mostrare gli allegati (decifrati)
  List<Widget> _buildAttachments() {
    if (widget.attachments == null || widget.attachments!.isEmpty) {
      return [];
    }

    // Se attachmentService non è disponibile, non mostrare allegati
    if (widget.attachmentService == null) {
      return [];
    }

    return [
      ...widget.attachments!.map((attachment) {
        if (attachment.type == 'photo') {
          return _AttachmentImage(
            attachment: attachment,
            isMe: widget.isMe,
            currentUserId: widget.currentUserId,
            senderId: widget.senderId,
            attachmentService: widget.attachmentService!,
          );
        } else if (attachment.type == 'video') {
          return _AttachmentVideo(
            attachment: attachment,
            isMe: widget.isMe,
            currentUserId: widget.currentUserId,
            senderId: widget.senderId,
          );
        } else {
          return _AttachmentDocument(
            attachment: attachment,
            isMe: widget.isMe,
            currentUserId: widget.currentUserId,
            senderId: widget.senderId,
            attachmentService: widget.attachmentService!,
          );
        }
      }),
    ];
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Allegati (se presenti) - senza padding per occupare tutta la larghezza
                          if (widget.attachments != null && widget.attachments!.isNotEmpty)
                            ..._buildAttachments(),
                          // Testo e timestamp con padding
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Testo del messaggio (se presente)
                                if (widget.message.isNotEmpty) ...[
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
                                    text: widget.message,
                                    style: TextStyle(
                                      color: widget.isMe ? Colors.white : Colors.black87,
                                      fontSize: 15,
                                      height: 1.4,
                                    ),
                                    linkStyle: TextStyle(
                                      color: widget.isMe ? Colors.white : Colors.blue,
                                      fontSize: 15,
                                      height: 1.4,
                                      decoration: TextDecoration.underline,
                                    ),
                                    options: const LinkifyOptions(
                                      humanize: false,
                                      looseUrl: true,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                ],
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
                                    // Mostra le spunte solo per i messaggi inviati da me
                                    if (widget.isMe) ...[
                                      const SizedBox(width: 4),
                                      Icon(
                                        widget.read ? Icons.done_all : Icons.done,
                                        size: 14,
                                        color: widget.read
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
            ],
          ),
        ),
      ),
    );
  }
}

/// Widget per visualizzare allegati immagine (decifrato)
class _AttachmentImage extends StatelessWidget {
  final Attachment attachment;
  final bool isMe;
  final String? currentUserId;
  final String? senderId;
  final AttachmentService attachmentService;

  const _AttachmentImage({
    required this.attachment,
    required this.isMe,
    this.currentUserId,
    this.senderId,
    required this.attachmentService,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Se URL è vuoto, l'allegato è in upload - mostra placeholder
    if (attachment.url.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: double.infinity,
          height: 200,
          child: Container(
            color: isMe ? Colors.white.withOpacity(0.1) : Colors.grey[200],
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(
                    l10n.chatLoadingAttachment,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        // Apri fullscreen image viewer
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => _FullscreenImageViewer(
              attachment: attachment,
              attachmentService: attachmentService,
              currentUserId: currentUserId,
              senderId: senderId,
            ),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FutureBuilder<Uint8List?>(
          future: attachmentService.downloadAndDecryptAttachment(
            attachment,
            currentUserId ?? '',
            senderId ?? '',
            useThumbnail: true, // Usa thumbnail per performance
          ),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              // Caricamento
              return SizedBox(
                width: double.infinity,
                height: 200,
                child: Container(
                  color: isMe ? Colors.white.withOpacity(0.1) : Colors.grey[200],
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
              );
            }

            if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
              // Errore decifratura
              return SizedBox(
                width: double.infinity,
                height: 200,
                child: Container(
                  color: Colors.red.withOpacity(0.1),
                  child: const Center(
                    child: Icon(Icons.error, color: Colors.red),
                  ),
                ),
              );
            }

            // Immagine decifrata visualizzata - usa tutta la larghezza della bubble
            return SizedBox(
              width: double.infinity,
              height: 200,
              child: Image.memory(
                snapshot.data!,
                fit: BoxFit.cover, // Taglia per riempire tutta l'area
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Widget per visualizzare allegati video (cifrato - placeholder)
class _AttachmentVideo extends StatelessWidget {
  final Attachment attachment;
  final bool isMe;
  final String? currentUserId;
  final String? senderId;

  const _AttachmentVideo({
    required this.attachment,
    required this.isMe,
    this.currentUserId,
    this.senderId,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Per i video cifrati, mostriamo solo un placeholder
    // TODO: Implementare video player per video cifrati
    return GestureDetector(
      onTap: () {
        // TODO: Scaricare, decifrare e aprire video player
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.chatVideoPlayerInDevelopment),
          ),
        );
      },
      child: Container(
        width: 200,
        height: 150,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isMe ? Colors.white.withOpacity(0.1) : Colors.grey[200],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow,
                color: Colors.white,
                size: 32,
              ),
            ),
            Positioned(
              bottom: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.videocam, color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      attachment.fileName,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget per visualizzare allegati documento (cifrato - placeholder)
class _AttachmentDocument extends StatefulWidget {
  final Attachment attachment;
  final bool isMe;
  final String? currentUserId;
  final String? senderId;
  final AttachmentService attachmentService;

  const _AttachmentDocument({
    required this.attachment,
    required this.isMe,
    this.currentUserId,
    this.senderId,
    required this.attachmentService,
  });

  @override
  State<_AttachmentDocument> createState() => _AttachmentDocumentState();
}

class _AttachmentDocumentState extends State<_AttachmentDocument> {
  bool _isDownloading = false;

  Future<void> _openDocument() async {
    if (_isDownloading) return;

    // Se URL è vuoto, il documento è ancora in upload - non fare nulla
    if (widget.attachment.url.isEmpty) return;

    // Check if it's a PDF - open with integrated viewer
    final isPdf = widget.attachment.fileName.toLowerCase().endsWith('.pdf');

    if (isPdf) {
      // Open PDF with integrated viewer
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => PdfViewerScreen(
              attachment: widget.attachment,
              attachmentService: widget.attachmentService,
              currentUserId: widget.currentUserId,
              senderId: widget.senderId,
            ),
          ),
        );
      }
      return;
    }

    // For non-PDF documents, download and open with external app
    setState(() => _isDownloading = true);

    try {
      // 1. Download and decrypt document
      final decryptedBytes = await widget.attachmentService.downloadAndDecryptAttachment(
        widget.attachment,
        widget.currentUserId ?? '',
        widget.senderId ?? '',
        useThumbnail: false,
      );

      if (decryptedBytes == null) {
        throw Exception('Failed to download document');
      }

      // 2. Save to temporary directory
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/${widget.attachment.fileName}');
      await file.writeAsBytes(decryptedBytes);

      // 3. Open with external app
      final result = await OpenFilex.open(file.path);

      if (result.type != ResultType.done && mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.chatFileOpenError(result.message)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error opening document: $e');
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.error(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return GestureDetector(
      onTap: _openDocument,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: widget.isMe ? Colors.white.withOpacity(0.1) : Colors.grey[200],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: widget.isMe ? Colors.white.withOpacity(0.2) : Colors.grey[300],
                borderRadius: BorderRadius.circular(8),
              ),
              child: (_isDownloading || widget.attachment.url.isEmpty)
                  ? Padding(
                      padding: const EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          widget.isMe ? Colors.white : Colors.grey[700]!,
                        ),
                      ),
                    )
                  : Icon(
                      Icons.insert_drive_file,
                      color: widget.isMe ? Colors.white : Colors.grey[700],
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.attachment.fileName,
                    style: TextStyle(
                      color: widget.isMe ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    widget.attachment.url.isEmpty
                        ? l10n.chatLoadingAttachment
                        : widget.attachmentService.formatFileSize(widget.attachment.fileSize),
                    style: TextStyle(
                      color: widget.isMe ? Colors.white70 : Colors.black54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.lock_outline,
              size: 16,
              color: widget.isMe ? Colors.white70 : Colors.black54,
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget per visualizzare immagine a schermo intero con zoom
class _FullscreenImageViewer extends StatefulWidget {
  final Attachment attachment;
  final AttachmentService attachmentService;
  final String? currentUserId;
  final String? senderId;

  const _FullscreenImageViewer({
    required this.attachment,
    required this.attachmentService,
    this.currentUserId,
    this.senderId,
  });

  @override
  State<_FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<_FullscreenImageViewer> {
  bool _showOverlay = true;

  void _toggleOverlay() {
    setState(() {
      _showOverlay = !_showOverlay;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleOverlay,
        child: Stack(
          children: [
            // Immagine full screen con zoom
            Center(
              child: FutureBuilder<Uint8List?>(
                future: widget.attachmentService.downloadAndDecryptAttachment(
                  widget.attachment,
                  widget.currentUserId ?? '',
                  widget.senderId ?? '',
                  useThumbnail: false, // Carica immagine FULL RESOLUTION
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    // Loading
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(color: Colors.white),
                        const SizedBox(height: 16),
                        Text(
                          l10n.chatLoadingImage,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    );
                  }

                  if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
                    // Errore
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error, color: Colors.red, size: 64),
                        const SizedBox(height: 16),
                        Text(
                          l10n.chatImageLoadError,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    );
                  }

                  // Immagine decifrata con zoom
                  return InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Image.memory(
                      snapshot.data!,
                      fit: BoxFit.contain,
                    ),
                  );
                },
              ),
            ),

            // Overlay con animazione fade (pulsante chiudi in alto a destra)
            AnimatedOpacity(
              opacity: _showOverlay ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 32),
                      onPressed: () => Navigator.of(context).pop(),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black.withOpacity(0.5),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Overlay con animazione fade (info file in basso)
            AnimatedOpacity(
              opacity: _showOverlay ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: SafeArea(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withOpacity(0.7),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.attachment.fileName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.lock, color: Colors.white70, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              'Cifrato E2E • ${widget.attachmentService.formatFileSize(widget.attachment.fileSize)}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
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
          ],
        ),
      ),
    );
  }
}

/// Widget separatore per raggruppare i messaggi per data
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
                    Color(0xFF667eea),
                    Color(0xFF764ba2),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF667eea).withOpacity(0.3),
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

class _TodoMessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;
  final bool isCompleted;
  final VoidCallback onComplete;
  final String? formattedDate;
  final AttachmentService? attachmentService;
  final String? senderId;
  final String? currentUserId;

  const _TodoMessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.isCompleted,
    required this.onComplete,
    this.formattedDate,
    this.attachmentService,
    this.senderId,
    this.currentUserId,
  });

  /// Costruisce i widget per mostrare gli allegati (decifrati)
  List<Widget> _buildAttachments() {
    if (message.attachments == null || message.attachments!.isEmpty) {
      return [];
    }

    // Se attachmentService non è disponibile, non mostrare allegati
    if (attachmentService == null) {
      return [];
    }

    return [
      ...message.attachments!.map((attachment) {
        if (attachment.type == 'photo') {
          return _AttachmentImage(
            attachment: attachment,
            isMe: isMe,
            currentUserId: currentUserId,
            senderId: senderId,
            attachmentService: attachmentService!,
          );
        } else if (attachment.type == 'video') {
          return _AttachmentVideo(
            attachment: attachment,
            isMe: isMe,
            currentUserId: currentUserId,
            senderId: senderId,
          );
        } else {
          return _AttachmentDocument(
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
    final bool isPastDue = message.dueDate != null && message.dueDate!.isBefore(DateTime.now());

    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 8, right: 8),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: isCompleted ? null : onComplete, // Long press per completare
            child: Container(
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Allegati (se presenti) - senza padding per occupare tutta la larghezza
                    if (message.attachments != null && message.attachments!.isNotEmpty)
                      ..._buildAttachments(),
                    // Testo e altre info con padding
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Testo del todo (mostra "Todo" se vuoto)
                          (message.decryptedContent?.isEmpty ?? true)
                              ? Text(
                                  l10n.chatTodoDefault,
                                  style: TextStyle(
                                    color: isMe ? Colors.white : Colors.black87,
                                    fontSize: 15,
                                    height: 1.4,
                                    decoration: isCompleted ? TextDecoration.lineThrough : null,
                                    fontStyle: FontStyle.italic,
                                  ),
                                )
                              : Linkify(
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
                                  text: message.decryptedContent!,
                                  style: TextStyle(
                                    color: isMe ? Colors.white : Colors.black87,
                                    fontSize: 15,
                                    height: 1.4,
                                    decoration: isCompleted ? TextDecoration.lineThrough : null,
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

                          // Data e ora (icona campanello per reminder, calendario per evento)
                          if (formattedDate != null) ...[
                            const SizedBox(height: 8),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  message.isReminder == true
                                      ? Icons.notifications_outlined  // Campanello per reminder
                                      : Icons.calendar_today_outlined, // Calendario per evento
                                  size: 14,
                                  color: isMe
                                      ? Colors.white.withOpacity(0.9)
                                      : Colors.black54,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    formattedDate!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isMe
                                          ? Colors.white.withOpacity(0.9)
                                          : Colors.black54,
                                    ),
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
                              // Mostra le spunte solo per i messaggi inviati da me
                              if (isMe && !isCompleted) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  (message.read ?? false) ? Icons.done_all : Icons.done,
                                  size: 14,
                                  color: (message.read ?? false)
                                      ? Colors.blue[300]
                                      : Colors.white.withOpacity(0.8),
                                ),
                              ],
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

                          // Hint per long press (solo se non completato)
                          if (!isCompleted) ...[
                            const SizedBox(height: 6),
                            Text(
                              l10n.chatLongPressToComplete,
                              style: TextStyle(
                                fontSize: 10,
                                color: isMe
                                    ? Colors.white.withOpacity(0.6)
                                    : Colors.black38,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
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

