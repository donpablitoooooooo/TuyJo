import 'dart:convert';

import 'encryption_service.dart';

/// Anteprima di un link (URL, titolo, descrizione) cifrata per entrambi i
/// telefoni, con lo stesso schema dual dei messaggi: una chiave AES nuova,
/// avvolta con RSA per il mittente e per il destinatario. Su Firestore sta
/// nel campo `link_preview` del messaggio; prima della 1.38 i tre campi
/// `link_url`, `link_title` e `link_description` erano in chiaro.
class LinkPreviewCrypto {
  static Map<String, String> encrypt(
    EncryptionService encryption, {
    required String url,
    String? title,
    String? description,
    required String myPublicKey,
    required String partnerPublicKey,
  }) {
    final encrypted = encryption.encryptMessageDual(
      json.encode({
        'url': url,
        if (title != null) 'title': title,
        if (description != null) 'description': description,
      }),
      myPublicKey,
      partnerPublicKey,
    );
    return {
      'message': encrypted['message']!,
      'iv': encrypted['iv']!,
      'encrypted_key_sender': encrypted['encryptedKeySender']!,
      'encrypted_key_recipient': encrypted['encryptedKeyRecipient']!,
    };
  }

  /// Payload per [EncryptionService.decryptMessage], o null se il campo
  /// manca o è incompleto.
  static String? payload(Map<String, dynamic>? encrypted, {required bool iAmSender}) {
    if (encrypted == null) return null;
    final key = iAmSender
        ? encrypted['encrypted_key_sender']
        : encrypted['encrypted_key_recipient'];
    if (key == null || encrypted['iv'] == null || encrypted['message'] == null) {
      return null;
    }
    return base64Encode(utf8.encode(json.encode({
      'encryptedKey': key,
      'iv': encrypted['iv'],
      'message': encrypted['message'],
    })));
  }

  /// Il contenuto decifrato, o null se non è un'anteprima valida.
  static ({String? url, String? title, String? description})? decode(String? plaintext) {
    if (plaintext == null) return null;
    try {
      final data = json.decode(plaintext) as Map<String, dynamic>;
      return (
        url: data['url'] as String?,
        title: data['title'] as String?,
        description: data['description'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}
