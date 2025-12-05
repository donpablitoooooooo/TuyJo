const { db } = require('./database');
const { v4: uuidv4 } = require('uuid');

const MESSAGES_COLLECTION = 'messages';

class MessageService {
  // Salva un nuovo messaggio cifrato (formato Family Chat)
  async saveMessage({ recipient_id, ciphertext, nonce, tag }) {
    const message_id = uuidv4();
    const message = {
      message_id,
      recipient_id,
      ciphertext,
      nonce,
      tag,
      created_at: new Date().toISOString(),
    };

    await db.collection(MESSAGES_COLLECTION).doc(message_id).set(message);
    return message;
  }

  // Ottieni inbox messaggi per un utente (solo ricevuti)
  async getInbox(recipient_id) {
    const snapshot = await db
      .collection(MESSAGES_COLLECTION)
      .where('recipient_id', '==', recipient_id)
      .orderBy('created_at', 'desc')
      .get();

    if (snapshot.empty) {
      return [];
    }

    return snapshot.docs.map((doc) => doc.data());
  }

  // Ottieni un messaggio per ID
  async getMessageById(message_id) {
    const doc = await db.collection(MESSAGES_COLLECTION).doc(message_id).get();

    if (!doc.exists) {
      return null;
    }

    return doc.data();
  }

  // Elimina messaggio (opzionale, per pulizia)
  async deleteMessage(message_id) {
    await db.collection(MESSAGES_COLLECTION).doc(message_id).delete();
  }
}

module.exports = new MessageService();
