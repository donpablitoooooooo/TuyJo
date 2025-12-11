class Message {
  final String id;
  final String senderId;
  // Nuovi campi per architettura RSA-only
  final String? encryptedKey; // Chiave AES cifrata con RSA
  final String? iv; // IV per AES
  final String? encryptedMessage; // Messaggio cifrato con AES
  // Vecchi campi per retrocompatibilità
  final String? ciphertext;
  final String? nonce;
  final String? tag;
  final DateTime timestamp;

  Message({
    required this.id,
    required this.senderId,
    this.encryptedKey,
    this.iv,
    this.encryptedMessage,
    this.ciphertext,
    this.nonce,
    this.tag,
    required this.timestamp,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] ?? json['_id'] ?? '',
      senderId: json['sender_id'] ?? json['senderId'] ?? '',
      encryptedKey: json['encrypted_key'],
      iv: json['iv'],
      encryptedMessage: json['message'],
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
      encryptedKey: data['encrypted_key'],
      iv: data['iv'],
      encryptedMessage: data['message'],
      ciphertext: data['ciphertext'],
      nonce: data['nonce'],
      tag: data['tag'],
      timestamp: DateTime.parse(data['created_at'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender_id': senderId,
      if (encryptedKey != null) 'encrypted_key': encryptedKey,
      if (iv != null) 'iv': iv,
      if (encryptedMessage != null) 'message': encryptedMessage,
      if (ciphertext != null) 'ciphertext': ciphertext,
      if (nonce != null) 'nonce': nonce,
      if (tag != null) 'tag': tag,
      'created_at': timestamp.toIso8601String(),
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
