const { db } = require('./database');
const { v4: uuidv4 } = require('crypto');

const MESSAGES_COLLECTION = 'messages';

class MessageService {
  // Salva un nuovo messaggio
  async saveMessage({ senderId, receiverId, encryptedContent }) {
    const messageId = uuidv4();
    const message = {
      id: messageId,
      senderId,
      receiverId,
      encryptedContent,
      timestamp: new Date().toISOString(),
      isDelivered: false,
      isRead: false,
    };

    await db.collection(MESSAGES_COLLECTION).doc(messageId).set(message);
    return message;
  }

  // Ottieni tutti i messaggi per un utente
  async getMessagesForUser(userId) {
    const sentSnapshot = await db
      .collection(MESSAGES_COLLECTION)
      .where('senderId', '==', userId)
      .get();

    const receivedSnapshot = await db
      .collection(MESSAGES_COLLECTION)
      .where('receiverId', '==', userId)
      .get();

    const messages = [
      ...sentSnapshot.docs.map((doc) => doc.data()),
      ...receivedSnapshot.docs.map((doc) => doc.data()),
    ];

    // Ordina per timestamp
    messages.sort((a, b) => new Date(a.timestamp) - new Date(b.timestamp));

    return messages;
  }

  // Ottieni un messaggio per ID
  async getMessageById(messageId) {
    const doc = await db.collection(MESSAGES_COLLECTION).doc(messageId).get();

    if (!doc.exists) {
      return null;
    }

    return doc.data();
  }

  // Marca un messaggio come consegnato
  async markAsDelivered(messageId) {
    await db.collection(MESSAGES_COLLECTION).doc(messageId).update({
      isDelivered: true,
    });
  }

  // Marca un messaggio come letto
  async markAsRead(messageId) {
    await db.collection(MESSAGES_COLLECTION).doc(messageId).update({
      isRead: true,
      readAt: new Date().toISOString(),
    });
  }
}

module.exports = new MessageService();
