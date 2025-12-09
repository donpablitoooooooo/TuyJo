class Message {
  final String id;
  final String ciphertext;
  final String nonce;
  final String tag;
  final DateTime timestamp;
  final String? senderId; // Estratto dopo decifrazione

  Message({
    required this.id,
    required this.ciphertext,
    required this.nonce,
    required this.tag,
    required this.timestamp,
    this.senderId,
  });

  factory Message.fromFirestore(String docId, Map<String, dynamic> data) {
    return Message(
      id: docId,
      ciphertext: data['ciphertext'] ?? '',
      nonce: data['nonce'] ?? '',
      tag: data['tag'] ?? '',
      timestamp: data['created_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['created_at'] as int)
          : DateTime.now(),
      senderId: data['sender_id'], // Opzionale, estratto dal plaintext
    );
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] ?? '',
      ciphertext: json['ciphertext'] ?? '',
      nonce: json['nonce'] ?? '',
      tag: json['tag'] ?? '',
      timestamp: json['created_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['created_at'] as int)
          : DateTime.now(),
      senderId: json['sender_id'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ciphertext': ciphertext,
      'nonce': nonce,
      'tag': tag,
      'created_at': timestamp.millisecondsSinceEpoch,
      if (senderId != null) 'sender_id': senderId,
    };
  }
}

class User {
  final String id;
  final String publicKey;

  User({
    required this.id,
    required this.publicKey,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? '',
      publicKey: json['public_key'] ?? json['publicKey'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'public_key': publicKey,
    };
  }
}
