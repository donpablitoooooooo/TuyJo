const { db } = require('./database');
const { v4: uuidv4 } = require('uuid');

const USERS_COLLECTION = 'users';
const INBOX_COLLECTION = 'inbox';

class MessageService {
  /**
   * Salva un nuovo messaggio cifrato nell'inbox del destinatario
   * Struttura: users/{recipientId}/inbox/{messageId}
   * @param {string} recipientId - ID dell'utente destinatario
   * @param {string} ciphertext - Testo cifrato in base64
   * @param {string} nonce - Nonce in base64
   * @param {string} tag - Tag di autenticazione in base64
   * @returns {object} - Il messaggio salvato
   */
  async saveMessage({ recipientId, ciphertext, nonce, tag }) {
    const messageId = uuidv4();
    const message = {
      ciphertext,
      nonce,
      tag,
      created_at: Date.now(),
    };

    // Salva in users/{recipientId}/inbox/{messageId}
    await db
      .collection(USERS_COLLECTION)
      .doc(recipientId)
      .collection(INBOX_COLLECTION)
      .doc(messageId)
      .set(message);

    return {
      id: messageId,
      recipient_id: recipientId,
      ...message,
    };
  }

  /**
   * Ottieni tutti i messaggi dall'inbox di un utente
   * @param {string} userId - ID dell'utente
   * @returns {Array} - Lista di messaggi
   */
  async getInboxMessages(userId) {
    const snapshot = await db
      .collection(USERS_COLLECTION)
      .doc(userId)
      .collection(INBOX_COLLECTION)
      .orderBy('created_at', 'asc')
      .get();

    return snapshot.docs.map((doc) => ({
      id: doc.id,
      ...doc.data(),
    }));
  }

  /**
   * Ottieni un singolo messaggio dall'inbox
   * @param {string} userId - ID dell'utente proprietario dell'inbox
   * @param {string} messageId - ID del messaggio
   * @returns {object|null} - Il messaggio o null
   */
  async getMessageById(userId, messageId) {
    const doc = await db
      .collection(USERS_COLLECTION)
      .doc(userId)
      .collection(INBOX_COLLECTION)
      .doc(messageId)
      .get();

    if (!doc.exists) {
      return null;
    }

    return {
      id: doc.id,
      ...doc.data(),
    };
  }

  /**
   * Elimina un messaggio dall'inbox
   * @param {string} userId - ID dell'utente proprietario dell'inbox
   * @param {string} messageId - ID del messaggio
   */
  async deleteMessage(userId, messageId) {
    await db
      .collection(USERS_COLLECTION)
      .doc(userId)
      .collection(INBOX_COLLECTION)
      .doc(messageId)
      .delete();
  }
}

module.exports = new MessageService();
