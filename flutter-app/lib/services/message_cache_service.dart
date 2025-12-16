import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/message.dart';

/// Service per il caching locale dei messaggi usando SQLite + FTS5
/// Permette caricamento istantaneo, ricerca full-text, e lazy loading
class MessageCacheService {
  static const String _dbName = 'messages_cache.db';
  static const int _dbVersion = 1;
  static const String _messagesTable = 'messages';
  static const String _ftsTable = 'messages_fts';

  Database? _database;

  /// Inizializza il database SQLite
  static Future<void> initialize() async {
    // Il database verrà aperto lazy quando necessario
  }

  /// Apre (o crea) il database
  Future<Database> _getDatabase() async {
    if (_database != null && _database!.isOpen) {
      return _database!;
    }

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    _database = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _createDatabase,
      onConfigure: (db) async {
        // Abilita foreign keys
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );

    return _database!;
  }

  /// Crea lo schema del database con FTS5 per ricerca full-text
  Future<void> _createDatabase(Database db, int version) async {
    // Tabella principale messaggi
    await db.execute('''
      CREATE TABLE $_messagesTable (
        id TEXT PRIMARY KEY,
        family_chat_id TEXT NOT NULL,
        sender_id TEXT NOT NULL,
        encrypted_key_recipient TEXT,
        encrypted_key_sender TEXT,
        iv TEXT,
        encrypted_message TEXT,
        encrypted_key TEXT,
        ciphertext TEXT,
        nonce TEXT,
        tag TEXT,
        timestamp INTEGER NOT NULL,
        message_type TEXT,
        decrypted_content TEXT,
        due_date INTEGER,
        completed INTEGER DEFAULT 0,
        original_todo_id TEXT
      )
    ''');

    // Indici per performance
    await db.execute('''
      CREATE INDEX idx_messages_family_timestamp
      ON $_messagesTable(family_chat_id, timestamp)
    ''');

    await db.execute('''
      CREATE INDEX idx_messages_type
      ON $_messagesTable(message_type)
    ''');

    // Tabella FTS5 per ricerca full-text sul contenuto decriptato
    await db.execute('''
      CREATE VIRTUAL TABLE $_ftsTable USING fts5(
        message_id UNINDEXED,
        decrypted_content,
        tokenize='porter unicode61'
      )
    ''');
  }

  /// Salva un messaggio nella cache
  Future<void> saveMessage(Message message, String familyChatId) async {
    final db = await _getDatabase();

    final data = {
      'id': message.id,
      'family_chat_id': familyChatId,
      'sender_id': message.senderId,
      'encrypted_key_recipient': message.encryptedKeyRecipient,
      'encrypted_key_sender': message.encryptedKeySender,
      'iv': message.iv,
      'encrypted_message': message.encryptedMessage,
      'encrypted_key': message.encryptedKey,
      'ciphertext': message.ciphertext,
      'nonce': message.nonce,
      'tag': message.tag,
      'timestamp': message.timestamp.millisecondsSinceEpoch,
      'message_type': message.messageType,
      'decrypted_content': message.decryptedContent,
      'due_date': message.dueDate?.millisecondsSinceEpoch,
      'completed': message.completed == true ? 1 : 0,
      'original_todo_id': message.originalTodoId,
    };

    // Inserisci o aggiorna il messaggio
    await db.insert(
      _messagesTable,
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Aggiorna la tabella FTS per la ricerca
    if (message.decryptedContent != null && message.decryptedContent!.isNotEmpty) {
      await db.insert(
        _ftsTable,
        {
          'message_id': message.id,
          'decrypted_content': message.decryptedContent,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// Salva una lista di messaggi in batch (molto più efficiente)
  Future<void> saveMessages(List<Message> messages, String familyChatId) async {
    final db = await _getDatabase();
    final batch = db.batch();

    for (final message in messages) {
      final data = {
        'id': message.id,
        'family_chat_id': familyChatId,
        'sender_id': message.senderId,
        'encrypted_key_recipient': message.encryptedKeyRecipient,
        'encrypted_key_sender': message.encryptedKeySender,
        'iv': message.iv,
        'encrypted_message': message.encryptedMessage,
        'encrypted_key': message.encryptedKey,
        'ciphertext': message.ciphertext,
        'nonce': message.nonce,
        'tag': message.tag,
        'timestamp': message.timestamp.millisecondsSinceEpoch,
        'message_type': message.messageType,
        'decrypted_content': message.decryptedContent,
        'due_date': message.dueDate?.millisecondsSinceEpoch,
        'completed': message.completed == true ? 1 : 0,
        'original_todo_id': message.originalTodoId,
      };

      batch.insert(_messagesTable, data, conflictAlgorithm: ConflictAlgorithm.replace);

      // FTS
      if (message.decryptedContent != null && message.decryptedContent!.isNotEmpty) {
        batch.insert(
          _ftsTable,
          {
            'message_id': message.id,
            'decrypted_content': message.decryptedContent,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }

    await batch.commit(noResult: true);
  }

  /// Carica tutti i messaggi per una famiglia (ordinati per timestamp)
  Future<List<Message>> loadMessages(String familyChatId) async {
    final db = await _getDatabase();

    final List<Map<String, dynamic>> maps = await db.query(
      _messagesTable,
      where: 'family_chat_id = ?',
      whereArgs: [familyChatId],
      orderBy: 'timestamp ASC',
    );

    return maps.map((map) => _messageFromMap(map)).toList();
  }

  /// Carica messaggi con lazy loading (paginazione)
  /// offset: numero di messaggi da saltare
  /// limit: numero massimo di messaggi da caricare
  Future<List<Message>> loadMessagesWithPagination({
    required String familyChatId,
    int offset = 0,
    int limit = 50,
  }) async {
    final db = await _getDatabase();

    final List<Map<String, dynamic>> maps = await db.query(
      _messagesTable,
      where: 'family_chat_id = ?',
      whereArgs: [familyChatId],
      orderBy: 'timestamp ASC',
      limit: limit,
      offset: offset,
    );

    return maps.map((map) => _messageFromMap(map)).toList();
  }

  /// Carica i messaggi più recenti (utile per l'init)
  Future<List<Message>> loadRecentMessages(String familyChatId, {int limit = 50}) async {
    final db = await _getDatabase();

    final List<Map<String, dynamic>> maps = await db.query(
      _messagesTable,
      where: 'family_chat_id = ?',
      whereArgs: [familyChatId],
      orderBy: 'timestamp DESC',
      limit: limit,
    );

    // Inverti l'ordine per avere dal più vecchio al più recente
    return maps.reversed.map((map) => _messageFromMap(map)).toList();
  }

  /// Cerca messaggi usando FTS5 (Full-Text Search)
  /// query: testo da cercare (supporta operatori FTS come "hello AND world")
  Future<List<Message>> searchMessages(String familyChatId, String query) async {
    final db = await _getDatabase();

    // Query FTS con join alla tabella principale
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT m.*
      FROM $_messagesTable m
      INNER JOIN $_ftsTable fts ON m.id = fts.message_id
      WHERE fts.decrypted_content MATCH ?
        AND m.family_chat_id = ?
      ORDER BY m.timestamp DESC
    ''', [query, familyChatId]);

    return maps.map((map) => _messageFromMap(map)).toList();
  }

  /// Verifica se un messaggio esiste nella cache
  Future<bool> hasMessage(String messageId) async {
    final db = await _getDatabase();

    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM $_messagesTable WHERE id = ?', [messageId]),
    );

    return count != null && count > 0;
  }

  /// Elimina un messaggio dalla cache
  Future<void> deleteMessage(String messageId) async {
    final db = await _getDatabase();

    await db.delete(
      _messagesTable,
      where: 'id = ?',
      whereArgs: [messageId],
    );

    // Rimuovi anche dall'FTS
    await db.delete(
      _ftsTable,
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
  }

  /// Pulisce tutti i messaggi per una specifica famiglia
  Future<void> clearCache(String familyChatId) async {
    final db = await _getDatabase();

    // Ottieni gli ID dei messaggi da eliminare
    final List<Map<String, dynamic>> messages = await db.query(
      _messagesTable,
      columns: ['id'],
      where: 'family_chat_id = ?',
      whereArgs: [familyChatId],
    );

    final messageIds = messages.map((m) => m['id'] as String).toList();

    // Elimina dalla tabella principale
    await db.delete(
      _messagesTable,
      where: 'family_chat_id = ?',
      whereArgs: [familyChatId],
    );

    // Elimina dall'FTS
    if (messageIds.isNotEmpty) {
      final placeholders = messageIds.map((_) => '?').join(',');
      await db.delete(
        _ftsTable,
        where: 'message_id IN ($placeholders)',
        whereArgs: messageIds,
      );
    }
  }

  /// Elimina completamente tutti i dati (per tutte le famiglie)
  Future<void> deleteAllData() async {
    final db = await _getDatabase();

    await db.delete(_messagesTable);
    await db.delete(_ftsTable);
  }

  /// Ritorna il numero di messaggi in cache per una famiglia
  Future<int> getMessageCount(String familyChatId) async {
    final db = await _getDatabase();

    final count = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM $_messagesTable WHERE family_chat_id = ?',
        [familyChatId],
      ),
    );

    return count ?? 0;
  }

  /// Ritorna il timestamp del messaggio più recente (per sync incrementale)
  Future<DateTime?> getLastMessageTimestamp(String familyChatId) async {
    final db = await _getDatabase();

    final List<Map<String, dynamic>> result = await db.query(
      _messagesTable,
      columns: ['timestamp'],
      where: 'family_chat_id = ?',
      whereArgs: [familyChatId],
      orderBy: 'timestamp DESC',
      limit: 1,
    );

    if (result.isEmpty) return null;

    final timestamp = result.first['timestamp'] as int;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  /// Converti Map SQL a Message model
  Message _messageFromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id'] as String,
      senderId: map['sender_id'] as String,
      encryptedKeyRecipient: map['encrypted_key_recipient'] as String?,
      encryptedKeySender: map['encrypted_key_sender'] as String?,
      iv: map['iv'] as String?,
      encryptedMessage: map['encrypted_message'] as String?,
      encryptedKey: map['encrypted_key'] as String?,
      ciphertext: map['ciphertext'] as String?,
      nonce: map['nonce'] as String?,
      tag: map['tag'] as String?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      decryptedContent: map['decrypted_content'] as String?,
      messageType: map['message_type'] as String?,
      dueDate: map['due_date'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['due_date'] as int)
          : null,
      completed: map['completed'] == 1,
      originalTodoId: map['original_todo_id'] as String?,
    );
  }

  /// Chiude il database
  Future<void> dispose() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null;
    }
  }

  // Metodi deprecati per compatibilità con l'API precedente (Hive)
  @Deprecated('Use loadMessages(familyChatId) instead')
  Future<void> openBox(String familyChatId) async {
    // No-op: sqflite non ha bisogno di aprire "box"
  }

  @Deprecated('Use dispose() instead')
  Future<void> closeBox() async {
    // No-op
  }

  @Deprecated('Use clearCache(familyChatId) instead')
  static Future<void> deleteBox(String familyChatId) async {
    final service = MessageCacheService();
    await service.clearCache(familyChatId);
    await service.dispose();
  }
}
