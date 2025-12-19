class Message {
  final String id;
  final String senderId;
  // Dual encryption: due versioni dell'encrypted_key
  final String? encryptedKeyRecipient; // Chiave AES cifrata per il destinatario
  final String? encryptedKeySender; // Chiave AES cifrata per il mittente
  final String? iv; // IV per AES
  final String? encryptedMessage; // Messaggio cifrato con AES
  // Vecchi campi per retrocompatibilità
  final String? encryptedKey; // Singola chiave (vecchia architettura)
  final String? ciphertext;
  final String? nonce;
  final String? tag;
  final DateTime timestamp;

  // Campi dopo decryption (popolati da ChatService)
  String? decryptedContent;
  String? messageType; // 'text', 'todo', 'todo_completed'

  // Campi specifici per todo
  DateTime? dueDate;
  bool? completed;
  String? originalTodoId; // Per messaggi di tipo 'todo_completed'
  bool? isReminder; // true se questo è un messaggio di reminder (icona campanello)

  // Campi per stato del messaggio (read receipts)
  bool? delivered; // true quando il messaggio è stato salvato in Firestore
  bool? read; // true quando il destinatario ha visualizzato il messaggio
  DateTime? readAt; // timestamp di quando è stato letto

  Message({
    required this.id,
    required this.senderId,
    this.encryptedKeyRecipient,
    this.encryptedKeySender,
    this.iv,
    this.encryptedMessage,
    this.encryptedKey,
    this.ciphertext,
    this.nonce,
    this.tag,
    required this.timestamp,
    this.decryptedContent,
    this.messageType,
    this.dueDate,
    this.completed,
    this.originalTodoId,
    this.isReminder,
    this.delivered,
    this.read,
    this.readAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] ?? json['_id'] ?? '',
      senderId: json['sender_id'] ?? json['senderId'] ?? '',
      encryptedKeyRecipient: json['encrypted_key_recipient'],
      encryptedKeySender: json['encrypted_key_sender'],
      iv: json['iv'],
      encryptedMessage: json['message'],
      encryptedKey: json['encrypted_key'], // Vecchia architettura
      ciphertext: json['ciphertext'],
      nonce: json['nonce'],
      tag: json['tag'],
      timestamp: DateTime.parse(json['created_at'] ?? json['timestamp'] ?? DateTime.now().toIso8601String()),
    );
  }

  factory Message.fromFirestore(String docId, Map<String, dynamic> data) {
    return Message(
      id: docId,
      senderId: data['sender_id'] ?? '',
      encryptedKeyRecipient: data['encrypted_key_recipient'],
      encryptedKeySender: data['encrypted_key_sender'],
      iv: data['iv'],
      encryptedMessage: data['message'],
      encryptedKey: data['encrypted_key'], // Vecchia architettura
      ciphertext: data['ciphertext'],
      nonce: data['nonce'],
      tag: data['tag'],
      timestamp: DateTime.parse(data['created_at'] ?? DateTime.now().toIso8601String()),
      delivered: data['delivered'],
      read: data['read'],
      readAt: data['read_at'] != null ? DateTime.parse(data['read_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender_id': senderId,
      if (encryptedKeyRecipient != null) 'encrypted_key_recipient': encryptedKeyRecipient,
      if (encryptedKeySender != null) 'encrypted_key_sender': encryptedKeySender,
      if (iv != null) 'iv': iv,
      if (encryptedMessage != null) 'message': encryptedMessage,
      if (encryptedKey != null) 'encrypted_key': encryptedKey, // Vecchia architettura
      if (ciphertext != null) 'ciphertext': ciphertext,
      if (nonce != null) 'nonce': nonce,
      if (tag != null) 'tag': tag,
      'created_at': timestamp.toIso8601String(),
      if (delivered != null) 'delivered': delivered,
      if (read != null) 'read': read,
      if (readAt != null) 'read_at': readAt!.toIso8601String(),
    };
  }
}

class User {
  final String id;
  final String username;
  final String publicKey;

  User({
    required this.id,
    required this.username,
    required this.publicKey,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? json['_id'] ?? '',
      username: json['username'] ?? '',
      publicKey: json['publicKey'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'publicKey': publicKey,
    };
  }
}
