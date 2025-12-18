import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/message.dart';

/// Service per il caching locale dei messaggi usando SQLite
/// Permette caricamento istantaneo, ricerca con LIKE, e lazy loading
class MessageCacheService {
  static const String _dbName = 'messages_cache.db';
  static const int _dbVersion = 2;
  static const String _messagesTable = 'messages';

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
      onUpgrade: _upgradeDatabase,
      onConfigure: (db) async {
        // Abilita foreign keys
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );

    return _database!;
  }

  /// Crea lo schema del database
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
        original_todo_id TEXT,
        delivered INTEGER DEFAULT 0,
        read INTEGER DEFAULT 0,
        read_at INTEGER
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

    // ⚠️ FTS5 RIMOSSO: non disponibile su tutte le build Android SQLite
    // Usiamo ricerca LIKE invece (vedi metodo searchMessages)
  }

  /// Migra il database da una versione precedente
  Future<void> _upgradeDatabase(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Aggiungi colonne per stato messaggio (delivered, read, read_at)
      await db.execute('ALTER TABLE $_messagesTable ADD COLUMN delivered INTEGER DEFAULT 0');
      await db.execute('ALTER TABLE $_messagesTable ADD COLUMN read INTEGER DEFAULT 0');
      await db.execute('ALTER TABLE $_messagesTable ADD COLUMN read_at INTEGER');
    }
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
      'delivered': message.delivered == true ? 1 : 0,
      'read': message.read == true ? 1 : 0,
      'read_at': message.readAt?.millisecondsSinceEpoch,
    };

    // Inserisci o aggiorna il messaggio
    await db.insert(
      _messagesTable,
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
        'delivered': message.delivered == true ? 1 : 0,
        'read': message.read == true ? 1 : 0,
        'read_at': message.readAt?.millisecondsSinceEpoch,
      };

      batch.insert(_messagesTable, data, conflictAlgorithm: ConflictAlgorithm.replace);
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

  /// Carica messaggi più vecchi di un certo timestamp (per infinite scroll)
  Future<List<Message>> loadMessagesBeforeTimestamp(
    String familyChatId,
    DateTime timestamp,
    {int limit = 50}
  ) async {
    final db = await _getDatabase();

    final List<Map<String, dynamic>> maps = await db.query(
      _messagesTable,
      where: 'family_chat_id = ? AND timestamp < ?',
      whereArgs: [familyChatId, timestamp.millisecondsSinceEpoch],
      orderBy: 'timestamp DESC',
      limit: limit,
    );

    // Inverti l'ordine per avere dal più vecchio al più recente
    return maps.reversed.map((map) => _messageFromMap(map)).toList();
  }

  /// Cerca messaggi usando LIKE (case-insensitive)
  /// query: testo da cercare (simple text search)
  Future<List<Message>> searchMessages(String familyChatId, String query) async {
    final db = await _getDatabase();

    // Usa LIKE per ricerca semplice (funziona senza FTS5)
    final List<Map<String, dynamic>> maps = await db.query(
      _messagesTable,
      where: 'family_chat_id = ? AND decrypted_content LIKE ?',
      whereArgs: [familyChatId, '%$query%'],
      orderBy: 'timestamp DESC',
    );

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
  }

  /// Pulisce tutti i messaggi per una specifica famiglia
  Future<void> clearCache(String familyChatId) async {
    final db = await _getDatabase();

    // Elimina tutti i messaggi per questa famiglia
    await db.delete(
      _messagesTable,
      where: 'family_chat_id = ?',
      whereArgs: [familyChatId],
    );
  }

  /// Elimina completamente tutti i dati (per tutte le famiglie)
  Future<void> deleteAllData() async {
    final db = await _getDatabase();

    await db.delete(_messagesTable);
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
      delivered: map['delivered'] == 1,
      read: map['read'] == 1,
      readAt: map['read_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['read_at'] as int)
          : null,
    );
  }

  /// 🐛 DEBUG: Ispeziona lo stato del database
  Future<Map<String, dynamic>> debugDatabaseStatus(String familyChatId) async {
    try {
      final db = await _getDatabase();
      final dbPath = await getDatabasesPath();

      // Conta messaggi totali
      final totalCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $_messagesTable'),
      );

      // Conta messaggi per questa famiglia
      final familyCount = Sqflite.firstIntValue(
        await db.rawQuery(
          'SELECT COUNT(*) FROM $_messagesTable WHERE family_chat_id = ?',
          [familyChatId],
        ),
      );

      // Prendi i primi 3 messaggi per questa famiglia
      final sampleMessages = await db.query(
        _messagesTable,
        where: 'family_chat_id = ?',
        whereArgs: [familyChatId],
        orderBy: 'timestamp DESC',
        limit: 3,
      );

      return {
        'database_path': join(dbPath, _dbName),
        'database_exists': _database != null && _database!.isOpen,
        'total_messages': totalCount ?? 0,
        'family_messages': familyCount ?? 0,
        'sample_messages': sampleMessages.map((m) => {
          'id': m['id'],
          'timestamp': DateTime.fromMillisecondsSinceEpoch(m['timestamp'] as int).toString(),
          'message_type': m['message_type'],
          'has_decrypted_content': (m['decrypted_content'] as String?)?.isNotEmpty ?? false,
          'decrypted_preview': (m['decrypted_content'] as String?)?.substring(0, 30) ?? 'null',
        }).toList(),
      };
    } catch (e) {
      return {
        'error': e.toString(),
      };
    }
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
