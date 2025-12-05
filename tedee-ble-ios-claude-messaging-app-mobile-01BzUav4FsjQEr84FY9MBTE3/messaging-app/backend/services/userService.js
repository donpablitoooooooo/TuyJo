const { db } = require('./database');
const { v4: uuidv4 } = require('uuid');

const USERS_COLLECTION = 'users';

class UserService {
  // Crea un nuovo utente (solo username e publicKey - niente password!)
  async createUser({ username, publicKey }) {
    const userId = uuidv4();
    const user = {
      id: userId,
      username,
      publicKey,
      fcmToken: null,
      createdAt: new Date().toISOString(),
    };

    await db.collection(USERS_COLLECTION).doc(userId).set(user);
    return user;
  }

  // Ottieni utente per username
  async getUserByUsername(username) {
    const snapshot = await db
      .collection(USERS_COLLECTION)
      .where('username', '==', username)
      .limit(1)
      .get();

    if (snapshot.empty) {
      return null;
    }

    return snapshot.docs[0].data();
  }

  // Ottieni utente per ID
  async getUserById(userId) {
    const doc = await db.collection(USERS_COLLECTION).doc(userId).get();

    if (!doc.exists) {
      return null;
    }

    return doc.data();
  }

  // Ottieni il partner (l'altro utente, non quello corrente)
  async getPartner(currentUserId) {
    const snapshot = await db
      .collection(USERS_COLLECTION)
      .where('id', '!=', currentUserId)
      .limit(1)
      .get();

    if (snapshot.empty) {
      return null;
    }

    return snapshot.docs[0].data();
  }

  // Aggiorna FCM token
  async updateFcmToken(userId, fcmToken) {
    await db.collection(USERS_COLLECTION).doc(userId).update({
      fcmToken,
      updatedAt: new Date().toISOString(),
    });
  }
}

module.exports = new UserService();
