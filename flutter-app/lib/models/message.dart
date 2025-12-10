class Message {
  final String id;
  final String senderId;
  final String ciphertext;
  final String nonce;
  final String tag;
  final DateTime timestamp;

  Message({
    required this.id,
    required this.senderId,
    required this.ciphertext,
    required this.nonce,
    required this.tag,
    required this.timestamp,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] ?? json['_id'] ?? '',
      senderId: json['sender_id'] ?? json['senderId'] ?? '',
      ciphertext: json['ciphertext'] ?? '',
      nonce: json['nonce'] ?? '',
      tag: json['tag'] ?? '',
      timestamp: DateTime.parse(json['created_at'] ?? json['timestamp'] ?? DateTime.now().toIso8601String()),
    );
  }

  factory Message.fromFirestore(String docId, Map<String, dynamic> data) {
    return Message(
      id: docId,
      senderId: data['sender_id'] ?? '',
      ciphertext: data['ciphertext'] ?? '',
      nonce: data['nonce'] ?? '',
      tag: data['tag'] ?? '',
      timestamp: DateTime.parse(data['created_at'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender_id': senderId,
      'ciphertext': ciphertext,
      'nonce': nonce,
      'tag': tag,
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
