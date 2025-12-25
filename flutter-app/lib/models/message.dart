import 'package:flutter/foundation.dart';

// Modello per gli allegati (con cifratura E2E dual encryption)
class Attachment {
  final String id;
  final String type; // 'photo', 'video', 'document'
  final String url; // URL Firebase Storage (contiene file CIFRATO)
  final String fileName;
  final int fileSize; // Dimensione file ORIGINALE (prima cifratura) in bytes
  final String? thumbnailUrl; // URL thumbnail per video/documenti
  final String? mimeType; // es. 'image/jpeg', 'video/mp4', 'application/pdf'

  // ========== Optimistic UI support ==========
  final String? localPath; // Path del file locale (solo per pending messages)

  // ========== Encryption metadata (dual encryption) ==========
  // Opzionali per supportare placeholder durante optimistic UI
  final String? encryptedKeyRecipient; // Chiave AES cifrata con chiave pubblica destinatario
  final String? encryptedKeySender; // Chiave AES cifrata con chiave pubblica mittente
  final String? iv; // Initialization vector per AES (base64)

  Attachment({
    required this.id,
    required this.type,
    required this.url,
    required this.fileName,
    required this.fileSize,
    this.thumbnailUrl,
    this.mimeType,
    this.localPath,
    this.encryptedKeyRecipient,
    this.encryptedKeySender,
    this.iv,
  });

  factory Attachment.fromJson(Map<String, dynamic> json) {
    return Attachment(
      id: json['id'] ?? '',
      type: json['type'] ?? '',
      url: json['url'] ?? '',
      fileName: json['fileName'] ?? '',
      fileSize: json['fileSize'] ?? 0,
      thumbnailUrl: json['thumbnailUrl'],
      mimeType: json['mimeType'],
      localPath: json['localPath'], // Solo per pending messages locali
      encryptedKeyRecipient: json['encryptedKeyRecipient'],
      encryptedKeySender: json['encryptedKeySender'],
      iv: json['iv'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'url': url,
      'fileName': fileName,
      'fileSize': fileSize,
      if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
      if (mimeType != null) 'mimeType': mimeType,
      if (localPath != null) 'localPath': localPath,
      if (encryptedKeyRecipient != null) 'encryptedKeyRecipient': encryptedKeyRecipient,
      if (encryptedKeySender != null) 'encryptedKeySender': encryptedKeySender,
      if (iv != null) 'iv': iv,
    };
  }
}

class Message {
  final String id;
  final String senderId;

  // 🎯 STABLE ID: Identificatore client-side che segue il messaggio durante tutto il ciclo di vita
  // Generato quando creiamo pending message, preservato quando diventa real.
  // Usato per ValueKey per evitare ricreazione widget durante pending→real transition.
  // NON salvato in Firestore (solo client-side per UI tracking).
  final String? stableId;

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
  bool isPending; // true quando il messaggio è ancora in fase di invio (ottimistico)

  // Allegati (foto, video, documenti)
  List<Attachment>? attachments;

  Message({
    required this.id,
    required this.senderId,
    this.stableId, // Opzionale: solo per pending/tracked messages
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
    this.isPending = false,
    this.attachments,
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
    // Parse attachments se presenti
    List<Attachment>? attachments;
    if (data['attachments'] != null && data['attachments'] is List) {
      try {
        attachments = (data['attachments'] as List)
            .map((a) => Attachment.fromJson(a as Map<String, dynamic>))
            .toList();
        if (kDebugMode) print('✅ Parsed ${attachments.length} attachments for message $docId');
      } catch (e) {
        if (kDebugMode) print('❌ Error parsing attachments for message $docId: $e');
        // Se c'è un errore, lascia attachments = null invece di crashare il messaggio
        attachments = null;
      }
    }

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
      attachments: attachments,
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
      if (attachments != null) 'attachments': attachments!.map((a) => a.toJson()).toList(),
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
