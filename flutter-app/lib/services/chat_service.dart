import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/message.dart';
import 'encryption_service.dart';
import 'notification_service.dart';
import 'message_cache_service.dart';

class ChatService extends ChangeNotifier {
  static const String baseUrl = 'https://private-messaging-backend-668509120760.europe-west1.run.app';
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final List<Message> _messages = [];
  late final EncryptionService _encryptionService;
  late final NotificationService _notificationService;
  final MessageCacheService _cacheService = MessageCacheService();
  StreamSubscription<QuerySnapshot>? _subscription;
  StreamSubscription<QuerySnapshot>? _typingSubscription;
  StreamSubscription<QuerySnapshot>? _readReceiptsSubscription; // Listener per status updates
  String? _myDeviceId; // Per sapere se sono il sender
  String? _currentFamilyChatId; // Per gestire la cache
  bool _isLoadingFromCache = false;
  bool _partnerIsTyping = false;
  Timer? _typingTimer;

  ChatService(this._encryptionService, this._notificationService);

  // Setter per il device ID
  void setMyDeviceId(String deviceId) {
    _myDeviceId = deviceId;
  }

  List<Message> get messages => _messages;
  bool get isConnected => _subscription != null;
  bool get isLoadingFromCache => _isLoadingFromCache;
  bool get partnerIsTyping => _partnerIsTyping;
  EncryptionService get encryptionService => _encryptionService;

  /// Carica messaggi più vecchi (per infinite scroll)
  Future<void> loadOlderMessages({int limit = 50}) async {
    if (_currentFamilyChatId == null) return;
    if (_messages.isEmpty) return;

    try {
      // Con ordine DESC (nuovi->vecchi), il messaggio più vecchio è l'ULTIMO
      final oldestTimestamp = _messages.last.timestamp;

      if (kDebugMode) print('📜 Loading $limit older messages before ${oldestTimestamp.toIso8601String()}...');

      // Carica messaggi più vecchi di quello più vecchio attuale
      final olderMessages = await _cacheService.loadMessagesBeforeTimestamp(
        _currentFamilyChatId!,
        oldestTimestamp,
        limit: limit,
      );

      if (olderMessages.isNotEmpty) {
        // Inserisci alla FINE (perché ordine DESC)
        // Ma prima invertiamo per mantenere ordine DESC
        _messages.addAll(olderMessages.reversed);
        notifyListeners();
        if (kDebugMode) print('✅ Loaded ${olderMessages.length} older messages');
      } else {
        if (kDebugMode) print('ℹ️ No more older messages to load');
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error loading older messages: $e');
    }
  }

  /// Carica i messaggi dalla cache locale (instant load)
  /// Carica solo gli ultimi N messaggi per performance (lazy loading)
  Future<void> loadFromCache(String familyChatId, {int limit = 100}) async {
    if (kDebugMode) print('🔍 [CACHE] loadFromCache called for family: ${familyChatId.substring(0, 10)}...');

    try {
      _isLoadingFromCache = true;
      notifyListeners();

      if (kDebugMode) print('🔍 [CACHE] Loading last $limit messages from SQLite...');

      // Carica solo gli ultimi N messaggi (ordinati DESC, poi reversati per ASC)
      final cachedMessages = await _cacheService.loadRecentMessages(familyChatId, limit: limit);

      if (kDebugMode) print('🔍 [CACHE] Loaded ${cachedMessages.length} messages from DB');

      if (cachedMessages.isNotEmpty) {
        _messages.clear();
        // 🔧 FIX: Invertiamo l'ordine per DESC (nuovi->vecchi) per ListView.reverse: true
        _messages.addAll(cachedMessages.reversed);

        // ✅ NON ri-decriptare! I messaggi in cache sono GIÀ decriptati
        // Il database contiene già: decryptedContent, messageType, dueDate, ecc.

        if (kDebugMode) {
          print('💾 [CACHE] Loaded ${cachedMessages.length} messages from SQLite cache');

          // Safe substring per evitare RangeError
          final firstMsg = cachedMessages.first.decryptedContent ?? '';
          final lastMsg = cachedMessages.last.decryptedContent ?? '';
          final firstPreview = firstMsg.length > 20 ? firstMsg.substring(0, 20) : firstMsg;
          final lastPreview = lastMsg.length > 20 ? lastMsg.substring(0, 20) : lastMsg;

          print('   First message: $firstPreview...');
          print('   Last message: $lastPreview...');
          print('   Calling notifyListeners() to update UI...');
        }

        notifyListeners();

        if (kDebugMode) print('✅ [CACHE] UI should be updated now with ${_messages.length} messages');
      } else {
        if (kDebugMode) {
          print('⚠️ [CACHE] Cache is empty for family: ${familyChatId.substring(0, 10)}...');
        }
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('❌ [CACHE] Error loading from cache: $e');
        print('   Stack trace: $stackTrace');
      }
    } finally {
      _isLoadingFromCache = false;
      notifyListeners();
      if (kDebugMode) print('🔍 [CACHE] loadFromCache completed');
    }
  }

  /// Aggiorna il timestamp di un messaggio reminder quando diventa visibile
  /// Questo fa sì che il reminder appaia sempre "fresco" in cima alla chat
  Future<void> _updateReminderTimestamp(String messageId, String familyChatId) async {
    try {
      final now = DateTime.now();
      await _firestore
          .collection('families')
          .doc(familyChatId)
          .collection('messages')
          .doc(messageId)
          .update({
        'created_at': now.toIso8601String(),
      });

      if (kDebugMode) {
        print('🔔 Updated reminder timestamp to now: $messageId');
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error updating reminder timestamp: $e');
    }
  }

  // Connetti al Firestore listener per la chat
  Future<void> startListening(String familyChatId) async {
    if (kDebugMode) print('⏱️ [CHAT_SERVICE] startListening called');
    final startTime = DateTime.now();

    if (_subscription != null) {
      if (kDebugMode) print('Already listening to chat');
      return;
    }

    // Se cambia la famiglia, chiudi la vecchia cache e carica la nuova
    if (_currentFamilyChatId != familyChatId) {
      _currentFamilyChatId = familyChatId;

      // 🐛 DEBUG: Ispeziona database prima di caricare
      if (kDebugMode) {
        final dbStatus = await _cacheService.debugDatabaseStatus(familyChatId);
        print('🐛 === DATABASE DEBUG INFO ===');
        print('   Path: ${dbStatus['database_path']}');
        print('   DB exists: ${dbStatus['database_exists']}');
        print('   Total messages in DB: ${dbStatus['total_messages']}');
        print('   Messages for this family: ${dbStatus['family_messages']}');
        print('   Sample messages:');
        final sampleMessages = dbStatus['sample_messages'];
        if (sampleMessages != null && sampleMessages is List && sampleMessages.isNotEmpty) {
          for (var msg in sampleMessages) {
            print('     - ID: ${msg['id'].toString().substring(0, 8)}...');
            print('       Type: ${msg['message_type']}');
            print('       Has content: ${msg['has_decrypted_content']}');
            print('       Preview: ${msg['decrypted_preview']}');
          }
        } else {
          print('     (no sample messages)');
        }
        print('🐛 ========================');
      }

      // Carica prima dalla cache (instant load)
      if (kDebugMode) print('⏱️ [CHAT_SERVICE] Loading from cache...');
      final cacheStart = DateTime.now();
      await loadFromCache(familyChatId);
      final cacheDuration = DateTime.now().difference(cacheStart);
      if (kDebugMode) print('⏱️ [CHAT_SERVICE] Cache loaded in ${cacheDuration.inMilliseconds}ms');
    }

    if (kDebugMode) print('🎧 Starting listener for chat: ${familyChatId.substring(0, 10)}...');

    // Avvia listener per typing indicator
    if (_myDeviceId != null) {
      _listenToPartnerTyping(familyChatId, _myDeviceId!);
    }

    // ⚡ LISTENER READ RECEIPTS: Avvia SUBITO per non perdere update iniziali
    if (_myDeviceId != null) {
      _startReadReceiptsListener(familyChatId, _myDeviceId!);
    }

    bool isFirstSnapshot = true; // Flag per il primo snapshot

    _subscription = _firestore
        .collection('families')
        .doc(familyChatId)
        .collection('messages')
        .orderBy('created_at', descending: false)
        .limitToLast(100) // Ripristinato per evitare sovraccarico
        .snapshots()
        .listen(
      (snapshot) async {
        if (kDebugMode) {
          print('📡 Firestore snapshot received: ${snapshot.docChanges.length} changes, isFirstSnapshot: $isFirstSnapshot');
        }

        // PRIMO SNAPSHOT: Fai batch sync di tutti i messaggi esistenti
        if (isFirstSnapshot) {
          isFirstSnapshot = false;

          final List<Message> newMessages = [];

          for (var change in snapshot.docChanges) {
            if (change.type == DocumentChangeType.added) {
              final message = Message.fromFirestore(
                change.doc.id,
                change.doc.data()!,
              );

              // Log se il messaggio ha attachments
              if (kDebugMode && message.attachments != null && message.attachments!.isNotEmpty) {
                print('📎 Message ${message.id.substring(0, 8)} has ${message.attachments!.length} attachments');
              }

              // Log se il messaggio ha reaction
              if (kDebugMode && message.reaction != null) {
                print('⭐ Message ${message.id.substring(0, 8)} has reaction: ${message.reaction!.type}');
              }

              // Decrypt e popola i campi
              if (_myDeviceId != null) {
                _decryptAndPopulateMessage(message, _myDeviceId!);
              }

              // Controlla se il messaggio esiste già in memoria (caricato dalla cache)
              final existingIndex = _messages.indexWhere((m) => m.id == message.id);

              if (existingIndex != -1) {
                // Messaggio esiste: SOSTITUISCILO con quello da Firestore
                // Firestore è la fonte di verità e ha reactions/attachments aggiornati
                if (kDebugMode) {
                  print('🔄 Updating existing message ${message.id.substring(0, 8)} from Firestore');
                }
                _messages[existingIndex] = message;
                newMessages.add(message); // Aggiungilo per batch save cache
              } else {
                // Messaggio nuovo: aggiungilo
                _messages.add(message);
                newMessages.add(message);
              }
            }
          }

          // 🔧 FIX: Riordina SOLO se abbiamo aggiunto nuovi messaggi
          // Questo evita il "salto" visivo quando la cache ha già i messaggi ordinati
          if (newMessages.isNotEmpty) {
            if (kDebugMode) print('📜 Sorting ${newMessages.length} new messages from Firestore initial sync');
            // Ordina DESC (nuovi->vecchi) per ListView.reverse: true
            _messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));

            // 💾 BATCH SAVE nella cache SQLite (molto più efficiente)
            try {
              await _cacheService.saveMessages(newMessages, familyChatId);
              if (kDebugMode) {
                print('💾 Initial sync: ${newMessages.length} messages saved to SQLite cache');
              }
            } catch (e) {
              if (kDebugMode) print('❌ Error batch caching messages: $e');
            }

            notifyListeners();
          } else {
            // Nessun nuovo messaggio - la cache era già aggiornata
            if (kDebugMode) print('✅ Initial sync: no new messages (cache was up-to-date)');
          }
        } else {
          // SNAPSHOTS SUCCESSIVI: Gestisci i nuovi messaggi normalmente
          for (var change in snapshot.docChanges) {
            if (change.type == DocumentChangeType.added) {
              final message = Message.fromFirestore(
                change.doc.id,
                change.doc.data()!,
              );

              // Decrypt SUBITO per poter confrontare il contenuto
              if (_myDeviceId != null) {
                _decryptAndPopulateMessage(message, _myDeviceId!);
              }

              if (!_messages.any((m) => m.id == message.id)) {

                // 🔔 REMINDER TIMESTAMP UPDATE
                // Se questo è un reminder appena diventato visibile, aggiorna il timestamp
                if (message.messageType == 'todo' &&
                    message.isReminder == true &&
                    message.senderId == _myDeviceId) { // Solo il mittente aggiorna
                  final now = DateTime.now();
                  // Se il reminder è appena scattato (entro 5 minuti)
                  if (message.timestamp.isBefore(now) &&
                      message.timestamp.isAfter(now.subtract(const Duration(minutes: 5)))) {
                    // Aggiorna il timestamp a now() per farlo apparire fresco
                    _updateReminderTimestamp(message.id, familyChatId);
                  }
                }

                _messages.add(message);
                // Ordina DESC (nuovi->vecchi) per ListView.reverse: true
                _messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));

                // 💾 SALVA NELLA CACHE SQLITE
                try {
                  await _cacheService.saveMessage(message, familyChatId);
                  if (kDebugMode) {
                    print('📨 New message cached: ${message.id} (type: ${message.messageType})');
                  }
                } catch (e) {
                  if (kDebugMode) print('❌ Error caching message: $e');
                }

                // ✅ AUTO-MARK AS READ: Se ricevo un messaggio, marcalo subito come letto
                if (_myDeviceId != null && message.senderId != _myDeviceId) {
                  // Messaggio ricevuto da qualcun altro, marcalo come letto
                  markAllMessagesAsRead(familyChatId, _myDeviceId!);
                  if (kDebugMode) {
                    print('✅ [AUTO-READ] Marked message as read: ${message.id.substring(0, 8)}...');
                  }
                }
              }
            } else if (change.type == DocumentChangeType.modified) {
              // Gestisci modifiche ai messaggi esistenti (es. timestamp update per reminder o read status)
              if (kDebugMode) {
                print('📝 [MODIFIED EVENT] Received for message: ${change.doc.id.substring(0, 8)}');
              }

              final updatedMessage = Message.fromFirestore(
                change.doc.id,
                change.doc.data()!,
              );

              // Trova e aggiorna il messaggio esistente
              final index = _messages.indexWhere((m) => m.id == updatedMessage.id);
              if (index != -1) {
                if (kDebugMode) {
                  print('   Old status: delivered=${_messages[index].delivered}, read=${_messages[index].read}');
                  print('   New status: delivered=${updatedMessage.delivered}, read=${updatedMessage.read}');
                }

                // Decrypt e popola i campi
                if (_myDeviceId != null) {
                  _decryptAndPopulateMessage(updatedMessage, _myDeviceId!);
                }

                // Sostituisci il messaggio vecchio con quello aggiornato
                _messages[index] = updatedMessage;

                // Riordina perché il timestamp potrebbe essere cambiato
                _messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));

                // 💾 AGGIORNA NELLA CACHE SQLITE
                try {
                  await _cacheService.saveMessage(updatedMessage, familyChatId);
                  if (kDebugMode) {
                    print('   ✅ Message status updated successfully');
                  }
                } catch (e) {
                  if (kDebugMode) print('   ❌ Error updating message in cache: $e');
                }
              } else {
                if (kDebugMode) print('   ⚠️ Message not found in local list!');
              }
            }
          }
          notifyListeners();
        }
      },
      onError: (error) {
        if (kDebugMode) print('Firestore listener error: $error');
      },
    );

    final totalDuration = DateTime.now().difference(startTime);
    if (kDebugMode) print('⏱️ [CHAT_SERVICE] startListening completed in ${totalDuration.inMilliseconds}ms');

    notifyListeners();
  }

  /// ⚡ Listener DOCUMENTO read_receipts (come typing indicator)
  /// Ascolta /families/{id}/read_receipts per aggiornamenti istantanei
  void _startReadReceiptsListener(String familyChatId, String myDeviceId) {
    _readReceiptsSubscription?.cancel();

    if (kDebugMode) {
      print('⚡ [READ_RECEIPTS] Starting listener');
      print('   Family: ${familyChatId.substring(0, 10)}...');
      print('   My ID: ${myDeviceId.substring(0, 10)}...');
    }

    _readReceiptsSubscription = _firestore
        .collection('families')
        .doc(familyChatId)
        .collection('read_receipts')
        .snapshots(includeMetadataChanges: false)
        .listen(
      (snapshot) {
        if (kDebugMode) {
          print('⚡ [READ_RECEIPTS] Snapshot received!');
          print('   Docs count: ${snapshot.docs.length}');
          print('   Changes: ${snapshot.docChanges.length}');
        }

        for (var doc in snapshot.docs) {
          final userId = doc.id;
          final data = doc.data();

          if (kDebugMode) {
            print('   Doc ID: ${userId.substring(0, 10)}...');
          }

          // Ignora i miei read receipts, interessano solo quelli del partner
          if (userId == myDeviceId) {
            if (kDebugMode) print('   -> Skipping (my own receipts)');
            continue;
          }

          final readMessageIds = List<String>.from(data['messageIds'] ?? []);
          final lastReadAt = data['lastReadAt'] as Timestamp?;

          if (kDebugMode) {
            print('✓✓ Partner read ${readMessageIds.length} messages');
          }

          // Aggiorna i messaggi nella lista locale
          int updatedCount = 0;
          for (final messageId in readMessageIds) {
            final index = _messages.indexWhere((m) => m.id == messageId);
            if (index != -1 && _messages[index].read != true) {
              _messages[index].read = true;
              _messages[index].readAt = lastReadAt?.toDate();
              updatedCount++;
            }
          }

          if (updatedCount > 0) {
            if (kDebugMode) {
              print('✅ Updated $updatedCount messages to read=true');
            }

            // Notifica UI immediatamente (non aspettare il salvataggio cache)
            notifyListeners();

            // Aggiorna cache in background
            _cacheService.saveMessages(_messages, familyChatId).catchError((e) {
              if (kDebugMode) print('❌ Error updating cache: $e');
            });
          }
        }
      },
      onError: (error) {
        if (kDebugMode) print('❌ Read receipts listener error: $error');
      },
    );
  }

  // Disconnetti dal listener
  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
    _typingSubscription?.cancel();
    _typingSubscription = null;
    _readReceiptsSubscription?.cancel();
    _readReceiptsSubscription = null;
    _typingTimer?.cancel();
    _typingTimer = null;
    if (kDebugMode) print('🔇 Stopped listening to chat');
    notifyListeners();
  }

  /// Imposta lo stato di digitazione per l'utente corrente
  Future<void> setTypingStatus(String familyChatId, String myDeviceId, bool isTyping) async {
    try {
      await _firestore
          .collection('families')
          .doc(familyChatId)
          .collection('users')
          .doc(myDeviceId)
          .update({'isTyping': isTyping, 'lastTypingUpdate': FieldValue.serverTimestamp()});

      if (kDebugMode) print('⌨️ Set typing status: $isTyping');
    } catch (e) {
      if (kDebugMode) print('❌ Error setting typing status: $e');
    }
  }

  /// Avvia listener per lo stato di digitazione del partner
  void _listenToPartnerTyping(String familyChatId, String myDeviceId) {
    _typingSubscription?.cancel();

    _typingSubscription = _firestore
        .collection('families')
        .doc(familyChatId)
        .collection('users')
        .snapshots(includeMetadataChanges: false)
        .listen((snapshot) {
      bool partnerTyping = false;

      for (var doc in snapshot.docs) {
        // Ignora il mio documento
        if (doc.id == myDeviceId) continue;

        final data = doc.data();
        final isTyping = data['isTyping'] as bool? ?? false;
        final lastUpdate = data['lastTypingUpdate'] as Timestamp?;

        // Considera "typing" solo se l'update è recente (< 5 secondi fa)
        if (isTyping && lastUpdate != null) {
          final updateTime = lastUpdate.toDate();
          final now = DateTime.now();
          final diff = now.difference(updateTime).inSeconds;

          if (diff < 5) {
            partnerTyping = true;
            break;
          }
        }
      }

      if (_partnerIsTyping != partnerTyping) {
        _partnerIsTyping = partnerTyping;
        notifyListeners();
        if (kDebugMode) print('⌨️ Partner typing status changed: $partnerTyping');
      }
    });
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

  /// Invia un To Do cifrato con RSA hybrid encryption e dual encryption
  Future<bool> sendTodo(
    String content,
    DateTime dueDate,
    String familyChatId,
    String senderId,
    String senderPublicKey,
    String recipientPublicKey, {
    DateTime? rangeEnd, // Parametro opzionale per TODO con range
    List<Attachment>? attachments, // Allegati opzionali per TODO
    int? alertHours, // Ore di preavviso per l'alert
  }) async {
    try {
      final timestamp = DateTime.now();

      // Costruisci il plaintext con type='todo' e due_date
      final Map<String, dynamic> todoData = {
        'sender': senderId,
        'timestamp': timestamp.millisecondsSinceEpoch ~/ 1000,
        'type': 'todo',
        'body': content,
        'due_date': dueDate.toIso8601String(),
        'is_reminder': false,
      };

      // Aggiungi range_end se presente
      if (rangeEnd != null) {
        todoData['range_end'] = rangeEnd.toIso8601String();
      }

      // Aggiungi alert_hours se presente
      if (alertHours != null) {
        todoData['alert_hours'] = alertHours;
      }

      final plaintext = json.encode(todoData);

      // Cifra con dual encryption
      final encryptedPayload = _encryptionService.encryptMessageDual(
        plaintext,
        senderPublicKey,
        recipientPublicKey,
      );

      // Scrivi nella chat condivisa
      final messageRef = _firestore
          .collection('families')
          .doc(familyChatId)
          .collection('messages')
          .doc();

      await messageRef.set({
        'sender_id': senderId,
        'encrypted_key_recipient': encryptedPayload['encryptedKeyRecipient'],
        'encrypted_key_sender': encryptedPayload['encryptedKeySender'],
        'iv': encryptedPayload['iv'],
        'message': encryptedPayload['message'],
        'created_at': timestamp.toIso8601String(),
        'message_type': 'todo', // Campo non criptato per la Cloud Function
        'delivered': true, // Messaggio consegnato al server
        'read': false, // Non ancora letto dal destinatario
        if (attachments != null && attachments.isNotEmpty)
          'attachments': attachments.map((a) => a.toJson()).toList(),
      });

      if (kDebugMode) {
        print('✅ Todo sent to chat: ${messageRef.id}');
        print('   Due date: ${dueDate.toIso8601String()}');
        print('   Status: delivered=true, read=false');
      }
      return true;
    } catch (e) {
      if (kDebugMode) print('❌ Send todo error: $e');
      return false;
    }
  }

  /// Invia un messaggio di reminder per un todo (con icona campanello)
  /// Questo messaggio viene inviato insieme al todo originale, ma nascosto fino al reminder time
  Future<bool> sendTodoReminder(
    String content,
    DateTime reminderDate,
    DateTime originalTodoDate,
    String familyChatId,
    String senderId,
    String senderPublicKey,
    String recipientPublicKey, {
    DateTime? rangeEnd, // Parametro opzionale per TODO con range
    List<Attachment>? attachments, // Allegati opzionali per TODO
    int? alertHours, // Ore di preavviso per l'alert
  }) async {
    try {
      // IMPORTANTE:
      // - reminderDate: quando appare il reminder nella chat (timestamp/created_at)
      // - originalTodoDate: la data effettiva del TODO (due_date)
      final Map<String, dynamic> reminderData = {
        'sender': senderId,
        'timestamp': reminderDate.millisecondsSinceEpoch ~/ 1000,
        'type': 'todo',
        'body': content,
        'due_date': originalTodoDate.toIso8601String(), // Data del TODO originale!
        'is_reminder': true,
      };

      // Aggiungi range_end se presente
      if (rangeEnd != null) {
        reminderData['range_end'] = rangeEnd.toIso8601String();
      }

      // Aggiungi alert_hours se presente
      if (alertHours != null) {
        reminderData['alert_hours'] = alertHours;
      }

      final plaintext = json.encode(reminderData);

      // Cifra con dual encryption
      final encryptedPayload = _encryptionService.encryptMessageDual(
        plaintext,
        senderPublicKey,
        recipientPublicKey,
      );

      // Scrivi nella chat condivisa
      final messageRef = _firestore
          .collection('families')
          .doc(familyChatId)
          .collection('messages')
          .doc();

      await messageRef.set({
        'sender_id': senderId,
        'encrypted_key_recipient': encryptedPayload['encryptedKeyRecipient'],
        'encrypted_key_sender': encryptedPayload['encryptedKeySender'],
        'iv': encryptedPayload['iv'],
        'message': encryptedPayload['message'],
        'created_at': reminderDate.toIso8601String(), // Usa reminderDate per cronologia
        'message_type': 'todo', // Campo non criptato per la Cloud Function
        'delivered': true, // Messaggio consegnato al server
        'read': false, // Non ancora letto dal destinatario
        if (attachments != null && attachments.isNotEmpty)
          'attachments': attachments.map((a) => a.toJson()).toList(),
      });

      if (kDebugMode) {
        print('🔔 Todo reminder sent to chat: ${messageRef.id}');
        print('   Reminder appears at (created_at): ${reminderDate.toIso8601String()}');
        print('   Original TODO date (due_date): ${originalTodoDate.toIso8601String()}');
        print('   Status: delivered=true, read=false');
      }
      return true;
    } catch (e) {
      if (kDebugMode) print('❌ Send todo reminder error: $e');
      return false;
    }
  }

  /// Invia un messaggio di completamento todo
  Future<bool> sendTodoCompletion(
    String originalTodoId,
    String familyChatId,
    String senderId,
    String senderPublicKey,
    String recipientPublicKey,
  ) async {
    try {
      final timestamp = DateTime.now();

      // Costruisci il plaintext con type='todo_completed'
      final plaintext = json.encode({
        'sender': senderId,
        'timestamp': timestamp.millisecondsSinceEpoch ~/ 1000,
        'type': 'todo_completed',
        'body': originalTodoId,
      });

      // Cifra con dual encryption
      final encryptedPayload = _encryptionService.encryptMessageDual(
        plaintext,
        senderPublicKey,
        recipientPublicKey,
      );

      // Scrivi nella chat condivisa
      final messageRef = _firestore
          .collection('families')
          .doc(familyChatId)
          .collection('messages')
          .doc();

      await messageRef.set({
        'sender_id': senderId,
        'encrypted_key_recipient': encryptedPayload['encryptedKeyRecipient'],
        'encrypted_key_sender': encryptedPayload['encryptedKeySender'],
        'iv': encryptedPayload['iv'],
        'message': encryptedPayload['message'],
        'created_at': timestamp.toIso8601String(),
        'message_type': 'todo_completed', // Campo non criptato per la Cloud Function
        'delivered': true, // Messaggio consegnato al server
        'read': false, // Non ancora letto dal destinatario
      });

      if (kDebugMode) {
        print('✅ Todo completion sent: $originalTodoId');
        print('   Status: delivered=true, read=false');
      }
      return true;
    } catch (e) {
      if (kDebugMode) print('❌ Send todo completion error: $e');
      return false;
    }
  }

  /// Invia messaggio di condivisione posizione
  /// Restituisce una mappa con 'messageId' e 'locationKey' (chiave AES per cifrare le coordinate)
  Future<Map<String, String>?> sendLocationShare(
    DateTime expiresAt,
    String sessionId,
    String familyChatId,
    String senderId,
    String senderPublicKey,
    String recipientPublicKey, {
    String mode = 'live',
    double? latitude,
    double? longitude,
  }) async {
    try {
      final timestamp = DateTime.now();

      // Genera chiave AES-256 per cifrare le coordinate GPS in real-time
      final locationKey = _encryptionService.generateLocationKey();

      // Coordinate iniziali di chi condivide (cifrate nel messaggio E2E)
      final coords = (latitude != null && longitude != null)
          ? '$latitude,$longitude'
          : '';

      // Formato body: location_share|expiresAt|sessionId|locationKey|mode|lat,lng
      final locationData = {
        'sender': senderId,
        'timestamp': timestamp.millisecondsSinceEpoch ~/ 1000,
        'type': 'location_share',
        'body': 'location_share|${expiresAt.toIso8601String()}|$sessionId|$locationKey|$mode|$coords',
        'expires_at': expiresAt.toIso8601String(),
        'session_id': sessionId,
      };

      final plaintext = json.encode(locationData);

      // Cifra con dual encryption
      final encryptedPayload = _encryptionService.encryptMessageDual(
        plaintext,
        senderPublicKey,
        recipientPublicKey,
      );

      // Scrivi nella chat condivisa
      final messageRef = _firestore
          .collection('families')
          .doc(familyChatId)
          .collection('messages')
          .doc();

      await messageRef.set({
        'sender_id': senderId,
        'encrypted_key_recipient': encryptedPayload['encryptedKeyRecipient'],
        'encrypted_key_sender': encryptedPayload['encryptedKeySender'],
        'iv': encryptedPayload['iv'],
        'message': encryptedPayload['message'],
        'created_at': timestamp.toIso8601String(),
        'message_type': 'location_share',
        'delivered': true,
        'read': false,
      });

      if (kDebugMode) {
        print('✅ Location share message sent');
        print('   Expires at: $expiresAt');
        print('   Message ID: ${messageRef.id}');
        print('   Location key generated for E2E coordinate encryption');
      }
      return {
        'messageId': messageRef.id,
        'locationKey': locationKey,
      };
    } catch (e) {
      if (kDebugMode) print('❌ Send location share error: $e');
      return null;
    }
  }

  /// Invia un messaggio cifrato con RSA hybrid encryption e dual encryption
  /// Ogni messaggio ha una chiave AES univoca, cifrata con ENTRAMBE le public key
  /// Restituisce il messageId se il messaggio è stato inviato con successo, null altrimenti
  /// Genera un message ID client-side per un dato family chat.
  /// Usato per salvare il PendingUpload PRIMA di chiamare sendMessage,
  /// così il PendingUpload sopravvive a un kill dell'app.
  String generateMessageId(String familyChatId) {
    return _firestore
        .collection('families')
        .doc(familyChatId)
        .collection('messages')
        .doc()
        .id;
  }

  /// Invia un messaggio cifrato con RSA hybrid encryption e dual encryption
  /// Ogni messaggio ha una chiave AES univoca, cifrata con ENTRAMBE le public key
  /// Restituisce il messageId se il messaggio è stato inviato con successo, null altrimenti
  ///
  /// Se [messageId] è fornito, usa quell'ID per il documento Firestore
  /// (pre-generato con [generateMessageId] per garantire PendingUpload persistence).
  Future<String?> sendMessage(
    String content,
    String familyChatId,
    String senderId,
    String senderPublicKey, // Nuova! Per cifrare anche per noi stessi
    String recipientPublicKey, {
    List<Attachment>? attachments, // Allegati opzionali
    String? messageId, // ID pre-generato (opzionale)
  }) async {
    try {
      final timestamp = DateTime.now();

      // Costruisci il plaintext con sender, timestamp, type, body
      final plaintext = json.encode({
        'sender': senderId,
        'timestamp': timestamp.millisecondsSinceEpoch ~/ 1000,
        'type': 'text',
        'body': content,
      });

      // Cifra con dual encryption: UNA chiave AES, cifrata DUE volte con RSA
      final encryptedPayload = _encryptionService.encryptMessageDual(
        plaintext,
        senderPublicKey,   // Per il mittente
        recipientPublicKey, // Per il destinatario
      );

      // Scrivi nella chat condivisa (usa messageId pre-generato se disponibile)
      final messagesCollection = _firestore
          .collection('families')
          .doc(familyChatId)
          .collection('messages');
      final messageRef = messageId != null
          ? messagesCollection.doc(messageId)
          : messagesCollection.doc();

      await messageRef.set({
        'sender_id': senderId,
        // Dual encryption: la STESSA chiave AES cifrata con DUE chiavi pubbliche RSA
        'encrypted_key_recipient': encryptedPayload['encryptedKeyRecipient'], // Per il destinatario
        'encrypted_key_sender': encryptedPayload['encryptedKeySender'], // Per il mittente
        'iv': encryptedPayload['iv'], // IV
        'message': encryptedPayload['message'], // Messaggio cifrato con AES
        'created_at': timestamp.toIso8601String(),
        'message_type': 'text', // Campo non criptato per la Cloud Function
        'delivered': true, // Messaggio consegnato al server
        'read': false, // Non ancora letto dal destinatario
        if (attachments != null && attachments.isNotEmpty)
          'attachments': attachments.map((a) => a.toJson()).toList(),
      });

      if (kDebugMode) {
        print('✅ Message sent to chat: ${messageRef.id}');
        print('   Dual encryption: encrypted_key_recipient + encrypted_key_sender');
        print('   Status: delivered=true, read=false');
      }
      return messageRef.id; // Restituisci il messageId
    } catch (e) {
      if (kDebugMode) print('❌ Send message error: $e');
      return null;
    }
  }

  /// Aggiorna un messaggio esistente aggiungendo gli allegati.
  /// Usato quando l'upload su Storage avviene dopo l'invio del messaggio.
  Future<bool> updateMessageAttachments(
    String messageId,
    String familyChatId,
    List<Attachment> attachments,
  ) async {
    try {
      await _firestore
          .collection('families')
          .doc(familyChatId)
          .collection('messages')
          .doc(messageId)
          .update({
        'attachments': attachments.map((a) => a.toJson()).toList(),
      });
      if (kDebugMode) {
        print('✅ Updated message $messageId with ${attachments.length} attachments');
      }
      return true;
    } catch (e) {
      if (kDebugMode) print('❌ Update message attachments error: $e');
      return false;
    }
  }

  /// Aggiunge o aggiorna una reaction a un messaggio
  Future<bool> addReaction(
    String messageId,
    String familyChatId,
    String userId,
    String reactionType, // 'love', 'ok', 'shit' (SOLO VISIVE)
  ) async {
    try {
      if (kDebugMode) {
        print('🔄 [addReaction] Starting...');
        print('   messageId: $messageId');
        print('   familyChatId: $familyChatId');
        print('   userId: $userId');
        print('   reactionType: $reactionType');
      }

      // Crea l'oggetto reaction
      final reaction = Reaction(
        type: reactionType,
        userId: userId,
        timestamp: DateTime.now(),
      );

      // Aggiorna il messaggio in Firestore
      final messageRef = _firestore
          .collection('families')
          .doc(familyChatId)
          .collection('messages')
          .doc(messageId);

      if (kDebugMode) {
        print('📤 [addReaction] Updating Firestore...');
      }

      await messageRef.update({
        'reaction': reaction.toJson(),
      });

      if (kDebugMode) {
        print('✅ [addReaction] Firestore updated successfully');
      }

      // Aggiorna il messaggio locale nella lista
      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        _messages[index].reaction = reaction;

        // Aggiorna anche la cache SQLite
        await _cacheService.saveMessage(_messages[index], familyChatId);

        if (kDebugMode) {
          print('✅ [addReaction] Local cache updated successfully');
        }
      } else {
        if (kDebugMode) {
          print('⚠️ [addReaction] Message not found in local list, will be updated by Firestore listener');
        }
      }

      // IMPORTANTE: chiama sempre notifyListeners() per forzare rebuild
      // Il listener Firestore aggiornerà il messaggio quando riceve l'evento modified
      notifyListeners();

      if (kDebugMode) {
        print('✅ [addReaction] Reaction $reactionType added to message $messageId');
      }
      return true;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('❌ [addReaction] Error: $e');
        print('Stack trace: $stackTrace');
      }
      return false;
    }
  }

  /// Aggiunge un'azione a un messaggio (con effetti logici)
  /// actionType: 'complete' (todo), 'stop_sharing' (location)
  Future<bool> addAction(
    String messageId,
    String familyChatId,
    String userId,
    String actionType, // 'complete', 'stop_sharing'
  ) async {
    try {
      if (kDebugMode) {
        print('🔄 [addAction] Starting...');
        print('   messageId: $messageId');
        print('   familyChatId: $familyChatId');
        print('   userId: $userId');
        print('   actionType: $actionType');
      }

      // Crea l'oggetto action
      final action = MessageAction(
        type: actionType,
        userId: userId,
        timestamp: DateTime.now(),
      );

      // Aggiorna il messaggio in Firestore
      final messageRef = _firestore
          .collection('families')
          .doc(familyChatId)
          .collection('messages')
          .doc(messageId);

      if (kDebugMode) {
        print('📤 [addAction] Updating Firestore...');
      }

      await messageRef.update({
        'action': action.toJson(),
      });

      if (kDebugMode) {
        print('✅ [addAction] Firestore updated successfully');
      }

      // Aggiorna il messaggio locale nella lista
      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        _messages[index].action = action;

        // Aggiorna anche la cache SQLite
        await _cacheService.saveMessage(_messages[index], familyChatId);

        if (kDebugMode) {
          print('✅ [addAction] Local cache updated successfully');
        }
      } else {
        if (kDebugMode) {
          print('⚠️ [addAction] Message not found in local list, will be updated by Firestore listener');
        }
      }

      // IMPORTANTE: chiama sempre notifyListeners() per forzare rebuild
      // Il listener Firestore aggiornerà il messaggio quando riceve l'evento modified
      notifyListeners();

      if (kDebugMode) {
        print('✅ [addAction] Action $actionType added to message $messageId');
      }
      return true;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('❌ [addAction] Error: $e');
        print('Stack trace: $stackTrace');
      }
      return false;
    }
  }

  /// Marca un messaggio come eliminato e rimuove gli allegati da Firebase Storage
  Future<bool> deleteMessage(
    String messageId,
    String familyChatId,
  ) async {
    try {
      if (kDebugMode) {
        print('🗑️ [deleteMessage] Starting...');
        print('   messageId: $messageId');
        print('   familyChatId: $familyChatId');
      }

      // Prima cerca il messaggio per ottenere gli allegati e il tipo
      List<Attachment>? attachmentsToDelete;
      String? messageType;

      // Cerca prima nella lista locale
      final localIndex = _messages.indexWhere((m) => m.id == messageId);
      if (localIndex != -1) {
        attachmentsToDelete = _messages[localIndex].attachments;
        messageType = _messages[localIndex].messageType;
      } else {
        // Se non è nella lista locale, leggi da Firestore
        final messageDoc = await _firestore
            .collection('families')
            .doc(familyChatId)
            .collection('messages')
            .doc(messageId)
            .get();

        if (messageDoc.exists && messageDoc.data() != null) {
          final data = messageDoc.data()!;
          messageType = data['message_type'] as String?;
          if (data['attachments'] != null && data['attachments'] is List) {
            try {
              attachmentsToDelete = (data['attachments'] as List)
                  .map((a) => Attachment.fromJson(a as Map<String, dynamic>))
                  .toList();
            } catch (e) {
              if (kDebugMode) print('⚠️ [deleteMessage] Error parsing attachments: $e');
            }
          }
        }
      }

      // Se è un TODO, cancella la notifica schedulata
      if (messageType == 'todo') {
        _cancelReminderNotification(messageId);
        if (kDebugMode) {
          print('🔕 [deleteMessage] Cancelled scheduled notification for TODO');
        }
      }

      // Elimina gli allegati da Firebase Storage
      if (attachmentsToDelete != null && attachmentsToDelete.isNotEmpty) {
        if (kDebugMode) {
          print('🗑️ [deleteMessage] Deleting ${attachmentsToDelete.length} attachment(s) from Storage...');
        }

        for (final attachment in attachmentsToDelete) {
          try {
            if (attachment.url.isNotEmpty) {
              final ref = FirebaseStorage.instance.refFromURL(attachment.url);
              await ref.delete();
              if (kDebugMode) {
                print('✅ [deleteMessage] Deleted attachment: ${attachment.fileName}');
              }
            }

            // Elimina anche la thumbnail se presente
            if (attachment.thumbnailUrl != null && attachment.thumbnailUrl!.isNotEmpty) {
              try {
                final thumbRef = FirebaseStorage.instance.refFromURL(attachment.thumbnailUrl!);
                await thumbRef.delete();
                if (kDebugMode) {
                  print('✅ [deleteMessage] Deleted thumbnail for: ${attachment.fileName}');
                }
              } catch (e) {
                if (kDebugMode) print('⚠️ [deleteMessage] Could not delete thumbnail: $e');
              }
            }
          } catch (e) {
            if (kDebugMode) {
              print('⚠️ [deleteMessage] Could not delete attachment ${attachment.fileName}: $e');
            }
            // Continua comunque - il file potrebbe già essere stato eliminato
          }
        }
      }

      // Aggiorna il messaggio in Firestore con il flag deleted
      final messageRef = _firestore
          .collection('families')
          .doc(familyChatId)
          .collection('messages')
          .doc(messageId);

      if (kDebugMode) {
        print('📤 [deleteMessage] Updating Firestore...');
      }

      await messageRef.update({
        'deleted': true,
        // Rimuovi i metadati degli allegati e link per non mostrarli più nella sezione media
        'attachments': FieldValue.delete(),
        'link_url': FieldValue.delete(),
        'link_title': FieldValue.delete(),
        'link_description': FieldValue.delete(),
      });

      if (kDebugMode) {
        print('✅ [deleteMessage] Firestore updated successfully');
      }

      // Aggiorna il messaggio locale nella lista
      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        _messages[index].deleted = true;
        // Rimuovi anche i metadati degli allegati e link
        _messages[index].attachments = null;
        _messages[index].linkUrl = null;
        _messages[index].linkTitle = null;
        _messages[index].linkDescription = null;

        // Aggiorna anche la cache SQLite
        await _cacheService.saveMessage(_messages[index], familyChatId);

        if (kDebugMode) {
          print('✅ [deleteMessage] Local cache updated successfully');
        }
      } else {
        if (kDebugMode) {
          print('⚠️ [deleteMessage] Message not found in local list, will be updated by Firestore listener');
        }
      }

      // Chiama notifyListeners per forzare rebuild
      notifyListeners();

      if (kDebugMode) {
        print('✅ [deleteMessage] Message $messageId marked as deleted');
      }
      return true;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('❌ [deleteMessage] Error: $e');
        print('Stack trace: $stackTrace');
      }
      return false;
    }
  }

  /// Modifica un messaggio esistente
  Future<bool> updateMessage(
    String messageId,
    String familyChatId,
    String newContent,
    String myDeviceId,
    String myPublicKey,
    String partnerPublicKey, {
    DateTime? dueDate,
    DateTime? rangeEnd,
    List<Attachment>? attachments,
    int? alertHours,
  }) async {
    try {
      if (kDebugMode) {
        print('✏️ [updateMessage] Starting...');
        print('   messageId: $messageId');
        print('   familyChatId: $familyChatId');
        print('   newContent: $newContent');
        print('   dueDate: $dueDate');
        print('   rangeEnd: $rangeEnd');
      }

      // Prepara il contenuto da cifrare
      String contentToEncrypt;
      if (dueDate != null) {
        // È un todo - crea JSON con tipo e data
        final Map<String, dynamic> todoData = {
          'type': 'todo',
          'body': newContent,
          'due_date': dueDate.toIso8601String(),
        };
        if (rangeEnd != null) {
          todoData['range_end'] = rangeEnd.toIso8601String();
        }
        if (alertHours != null) {
          todoData['alert_hours'] = alertHours;
        }
        contentToEncrypt = json.encode(todoData);
      } else {
        // Messaggio normale - crea JSON semplice (usa 'body' per coerenza)
        contentToEncrypt = json.encode({'type': 'text', 'body': newContent});
      }

      if (kDebugMode) {
        print('📝 [updateMessage] Content to encrypt: $contentToEncrypt');
      }

      // Cifra il messaggio con dual encryption
      final encrypted = _encryptionService.encryptMessageDual(
        contentToEncrypt,
        myPublicKey,
        partnerPublicKey,
      );

      if (kDebugMode) {
        print('🔐 [updateMessage] Message encrypted successfully');
      }

      // Aggiorna il messaggio in Firestore
      final messageRef = _firestore
          .collection('families')
          .doc(familyChatId)
          .collection('messages')
          .doc(messageId);

      final Map<String, dynamic> updateData = {
        'message': encrypted['message'],
        'encrypted_key_recipient': encrypted['encryptedKeyRecipient'],
        'encrypted_key_sender': encrypted['encryptedKeySender'],
        'iv': encrypted['iv'],
      };

      // Aggiorna gli allegati solo se forniti (null = non toccare gli allegati esistenti)
      if (attachments != null) {
        if (attachments.isEmpty) {
          updateData['attachments'] = []; // Lista vuota = rimuovi tutti gli allegati
        } else {
          updateData['attachments'] = attachments.map((a) => a.toJson()).toList();
        }
      }
      // Se attachments è null, non includiamo il campo quindi Firestore non lo modifica

      await messageRef.update(updateData);

      if (kDebugMode) {
        print('✅ [updateMessage] Firestore updated successfully');
        print('   Il listener Firestore aggiornerà il messaggio locale automaticamente');
      }

      // Il listener Firestore aggiornerà automaticamente il messaggio locale
      // Non è necessario modificare _messages manualmente poiché i campi sono final

      if (kDebugMode) {
        print('✅ [updateMessage] Message $messageId updated successfully');
      }
      return true;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('❌ [updateMessage] Error: $e');
        print('Stack trace: $stackTrace');
      }
      return false;
    }
  }

  /// Decripta un messaggio e popola i campi aggiuntivi (messageType, dueDate, ecc.)
  /// Schedula notifiche per i todo
  void _decryptAndPopulateMessage(Message message, String myDeviceId) {
    try {
      final decryptedContent = decryptMessage(message, myDeviceId);
      message.decryptedContent = decryptedContent;

      // Prova a parsare come JSON per ottenere il tipo e altri campi
      try {
        final plaintext = _getFullPlaintext(message, myDeviceId);
        final data = json.decode(plaintext);

        message.messageType = data['type'] ?? 'text';

        if (message.messageType == 'todo') {
          // Popola i campi del todo
          message.dueDate = DateTime.parse(data['due_date']);
          message.completed = false;

          // Parse range_end se presente
          if (data['range_end'] != null) {
            message.rangeEnd = DateTime.parse(data['range_end']);
          }

          // Parse is_reminder con logging per debug
          final isReminderRaw = data['is_reminder'];
          message.isReminder = isReminderRaw == true;

          // Parse alert_hours se presente
          if (data['alert_hours'] != null) {
            message.alertHours = data['alert_hours'] as int;
          }

          if (kDebugMode) {
            print('📅 Todo message detected: ${message.decryptedContent}');
            print('   Due date: ${message.dueDate}');
            if (message.alertHours != null) {
              print('   Alert: ${message.alertHours}h before');
            }
            if (message.rangeEnd != null) {
              print('   Range end: ${message.rangeEnd}');
            }
            print('   is_reminder (raw): $isReminderRaw (type: ${isReminderRaw.runtimeType})');
            print('   isReminder (parsed): ${message.isReminder}');
          }

          // Schedula la notifica solo per i todo normali (non per i reminder)
          if (!message.isReminder!) {
            _scheduleReminderNotification(message);
          }
        } else if (message.messageType == 'todo_completed') {
          // Messaggio di completamento
          message.originalTodoId = data['body'];

          // Cancella la notifica del todo originale
          _cancelReminderNotification(message.originalTodoId!);

          if (kDebugMode) {
            print('✅ Todo completed: ${message.originalTodoId}');
          }
        }
      } catch (e) {
        // Se non è JSON o non ha il formato atteso, è un messaggio normale
        message.messageType = 'text';
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error decrypting/populating message: $e');
      message.decryptedContent = '[Messaggio non decifrabile]';
      message.messageType = 'text';
    }
  }

  /// Ottiene il plaintext completo (non solo il body)
  String _getFullPlaintext(Message message, String myDeviceId) {
    try {
      final bool iAmSender = message.senderId == myDeviceId;
      final String? encryptedKeyToUse = iAmSender
          ? message.encryptedKeySender
          : message.encryptedKeyRecipient;

      String? finalEncryptedKey = encryptedKeyToUse;

      if (!iAmSender && finalEncryptedKey == null) {
        finalEncryptedKey = message.encryptedKey;
      }

      if (finalEncryptedKey == null) {
        throw Exception('No encrypted key available');
      }

      final payload = {
        'encryptedKey': finalEncryptedKey,
        'iv': message.iv,
        'message': message.encryptedMessage,
      };

      final encryptedPayload = base64Encode(utf8.encode(json.encode(payload)));
      return _encryptionService.decryptMessage(encryptedPayload);
    } catch (e) {
      throw Exception('Failed to decrypt: $e');
    }
  }

  /// Schedula una notifica per un todo
  void _scheduleReminderNotification(Message todoMessage) {
    if (todoMessage.dueDate == null) return;

    // Calcola reminder time (1 ora prima)
    final reminderTime = todoMessage.dueDate!.subtract(const Duration(hours: 1));

    // Verifica che sia nel futuro
    if (reminderTime.isAfter(DateTime.now())) {
      _notificationService.scheduleNotification(
        id: todoMessage.id.hashCode,
        title: '🔔 Nuovo To Do',
        body: todoMessage.decryptedContent ?? 'Evento imminente',
        scheduledDate: reminderTime,
      );

      if (kDebugMode) {
        print('🔔 Reminder scheduled for: ${reminderTime.toIso8601String()}');
      }
    } else {
      if (kDebugMode) {
        print('⚠️ Todo is in the past, not scheduling reminder');
      }
    }
  }

  /// Cancella la notifica di un todo
  void _cancelReminderNotification(String todoId) {
    _notificationService.cancelNotification(todoId.hashCode);

    if (kDebugMode) {
      print('🗑️ Reminder cancelled for todo: $todoId');
    }
  }

  /// Decripta un messaggio usando la propria chiave privata RSA
  /// Con dual encryption, usa encrypted_key_sender se siamo il mittente,
  /// altrimenti encrypted_key_recipient
  String decryptMessage(Message message, String myDeviceId) {
    try {
      // Determina quale chiave AES usare in base a chi siamo
      final bool iAmSender = message.senderId == myDeviceId;
      final String? encryptedKeyToUse = iAmSender
          ? message.encryptedKeySender
          : message.encryptedKeyRecipient;

      // Fallback per messaggi vecchi (pre-dual-encryption)
      String? finalEncryptedKey = encryptedKeyToUse;

      // Se sono il DESTINATARIO e non c'è encrypted_key_recipient, usa il vecchio campo
      if (!iAmSender && finalEncryptedKey == null) {
        finalEncryptedKey = message.encryptedKey;
      }

      // Se sono il MITTENTE e non c'è encrypted_key_sender, il messaggio è vecchio
      // e non è decifrabile (era cifrato solo per il destinatario)
      if (iAmSender && finalEncryptedKey == null) {
        if (kDebugMode) print('⚠️ Old message sent by me - cannot decrypt (was only encrypted for recipient)');
        return '[Vecchio messaggio non decifrabile]';
      }

      if (kDebugMode) {
        print('🔓 Decrypting message:');
        print('   Message ID: ${message.id}');
        print('   I am: ${iAmSender ? "SENDER" : "RECIPIENT"}');
        print('   Using: ${iAmSender ? "encrypted_key_sender" : "encrypted_key_recipient"}');
        print('   Encrypted key: ${finalEncryptedKey?.substring(0, 20) ?? 'null'}...');
        print('   IV: ${message.iv}');
        print('   Message: ${message.encryptedMessage?.substring(0, 20) ?? 'null'}...');
      }

      if (finalEncryptedKey == null) {
        throw Exception('No encrypted key available');
      }

      // Ricostruisci il payload per decryptMessage
      final payload = {
        'encryptedKey': finalEncryptedKey,
        'iv': message.iv,
        'message': message.encryptedMessage,
      };

      final encryptedPayload = base64Encode(utf8.encode(json.encode(payload)));

      // Decifra con la propria chiave privata RSA
      final plaintext = _encryptionService.decryptMessage(encryptedPayload);

      if (kDebugMode) print('✅ Decrypted plaintext: $plaintext');

      // Parse del plaintext JSON
      final data = json.decode(plaintext);
      return data['body'] ?? plaintext;
    } catch (e) {
      if (kDebugMode) print('❌ Decrypt error: $e');
      return '[Messaggio non decifrabile]';
    }
  }

  // Pulisci i messaggi
  Future<void> clearMessages() async {
    _messages.clear();

    // 💾 Pulisci anche la cache SQLite
    if (_currentFamilyChatId != null) {
      try {
        await _cacheService.clearCache(_currentFamilyChatId!);
        if (kDebugMode) print('💾 SQLite cache cleared');
      } catch (e) {
        if (kDebugMode) print('❌ Error clearing cache: $e');
      }
    }

    notifyListeners();
  }

  // Elimina tutti i messaggi da Firestore per una famiglia
  Future<void> deleteAllMessages(String familyChatId) async {
    try {
      if (kDebugMode) print('🗑️ Deleting all messages for family: $familyChatId');

      final messagesRef = _firestore
          .collection('families')
          .doc(familyChatId)
          .collection('messages');

      // Ottieni tutti i messaggi
      final snapshot = await messagesRef.get();

      if (kDebugMode) print('Found ${snapshot.docs.length} messages to delete');

      // Elimina tutti i messaggi in batch
      final batch = _firestore.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      // 💾 Elimina anche la cache SQLite
      await _cacheService.clearCache(familyChatId);

      if (kDebugMode) print('✅ All messages deleted from Firestore and SQLite cache');
    } catch (e) {
      if (kDebugMode) print('❌ Error deleting messages: $e');
      rethrow;
    }
  }

  /// Elimina messaggi + foto di coppia (NON users - quello è gestito da unpair)
  /// Usato quando si fa "unpair + elimina messaggi"
  Future<void> deleteMessagesAndCoupleSelfie(String familyChatId) async {
    try {
      if (kDebugMode) print('🗑️ Deleting messages and couple selfie: $familyChatId');

      // STEP 1: Elimina tutti i messaggi (subcollection) + cache
      await deleteAllMessages(familyChatId);

      // STEP 2: Leggi l'URL della foto prima di eliminarla
      String? selfieUrl;
      try {
        final familyDoc = await _firestore.collection('families').doc(familyChatId).get();
        if (familyDoc.exists) {
          final data = familyDoc.data();
          selfieUrl = data?['couple_selfie_url'] as String?;
        }
      } catch (e) {
        if (kDebugMode) print('⚠️ Could not read couple selfie URL: $e');
      }

      // STEP 3: Elimina il file da Firebase Storage (se esiste)
      if (selfieUrl != null && selfieUrl.isNotEmpty) {
        try {
          final storageRef = FirebaseStorage.instance.refFromURL(selfieUrl);
          await storageRef.delete();
          if (kDebugMode) print('✅ Couple selfie file deleted from Storage');
        } catch (e) {
          if (kDebugMode) print('⚠️ Could not delete storage file: $e');
          // Non lanciare errore - il file potrebbe già essere stato eliminato
        }
      }

      // STEP 4: Elimina i metadati della foto dal documento famiglia
      try {
        await _firestore.collection('families').doc(familyChatId).update({
          'couple_selfie_url': FieldValue.delete(),
          'couple_selfie_updated_at': FieldValue.delete(),
        });
        if (kDebugMode) print('✅ Couple selfie fields deleted from family document');
      } on FirebaseException catch (e) {
        // Se il documento non esiste, non è un problema (lo scopo è raggiunto)
        if (e.code == 'not-found') {
          if (kDebugMode) print('ℹ️ Family document not found (already deleted or never existed)');
        } else {
          rethrow;
        }
      }

      if (kDebugMode) print('✅ Messages and couple selfie cleanup complete');
    } catch (e) {
      if (kDebugMode) print('❌ Error deleting messages and selfie: $e');
      rethrow;
    }
  }

  /// Elimina completamente la famiglia da Firestore (messaggi + documento)
  /// Usato quando si vuole fare un reset completo (pairing + messaggi)
  Future<void> deleteFamily(String familyChatId) async {
    try {
      if (kDebugMode) print('🗑️ Deleting family completely: $familyChatId');

      // STEP 1: Elimina tutti i messaggi (subcollection) + cache
      await deleteAllMessages(familyChatId);

      // STEP 2: Elimina tutti gli user tokens (subcollection /users/)
      final usersSnapshot = await _firestore
          .collection('families')
          .doc(familyChatId)
          .collection('users')
          .get();

      for (var doc in usersSnapshot.docs) {
        await doc.reference.delete();
      }

      if (kDebugMode) print('✅ Family subcollections deleted from Firestore (messages + users + cache)');
    } catch (e) {
      if (kDebugMode) print('❌ Error deleting family: $e');
      rethrow;
    }
  }

  /// Marca un messaggio come letto dal destinatario
  /// Aggiorna sia Firestore che la cache SQLite locale
  Future<void> markMessageAsRead(String messageId, String familyChatId) async {
    try {
      final now = DateTime.now();

      // Aggiorna in Firestore
      await _firestore
          .collection('families')
          .doc(familyChatId)
          .collection('messages')
          .doc(messageId)
          .update({
        'read': true,
        'read_at': now.toIso8601String(),
      });

      // Aggiorna anche nella lista locale in memoria
      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        _messages[index].read = true;
        _messages[index].readAt = now;

        // Aggiorna nella cache SQLite
        await _cacheService.saveMessage(_messages[index], familyChatId);

        notifyListeners();
      }

      if (kDebugMode) {
        print('✅ Message marked as read: $messageId');
        print('   Read at: ${now.toIso8601String()}');
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error marking message as read: $e');
    }
  }

  /// Marca tutti i messaggi non letti del mittente come letti
  /// Utile quando l'utente visualizza la chat
  /// ⚡ Marca messaggi come letti scrivendo nel documento read_receipts
  /// Approccio "razzo": 1 scrittura invece di N update
  Future<void> markAllMessagesAsRead(String familyChatId, String recipientDeviceId) async {
    try {
      final now = DateTime.now();

      // Trova tutti i messaggi ricevuti (non inviati da me)
      final receivedMessageIds = _messages
          .where((m) => m.senderId != recipientDeviceId)
          .map((m) => m.id)
          .toList();

      if (receivedMessageIds.isEmpty) {
        if (kDebugMode) print('⚠️ No messages to mark as read');
        return;
      }

      // ⚡ Scrivi nel documento read_receipts (come typing indicator)
      await _firestore
          .collection('families')
          .doc(familyChatId)
          .collection('read_receipts')
          .doc(recipientDeviceId)
          .set({
        'messageIds': receivedMessageIds,
        'lastReadAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Aggiorna anche localmente
      for (final message in _messages) {
        if (message.senderId != recipientDeviceId) {
          message.read = true;
          message.readAt = now;
        }
      }

      // Aggiorna cache
      await _cacheService.saveMessages(_messages, familyChatId);
      notifyListeners();

      if (kDebugMode) {
        print('⚡ Marked ${receivedMessageIds.length} messages as read in read_receipts document');
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error marking all messages as read: $e');
    }
  }

  @override
  void dispose() {
    stopListening();
    _cacheService.dispose();
    super.dispose();
  }
}
