const { db } = require('./database');

const USERS_COLLECTION = 'users';

class UserService {
  // Crea un nuovo utente
  async createUser({ username, password, publicKey }) {
    // Genera automaticamente un ID usando Firestore
    const userRef = db.collection(USERS_COLLECTION).doc();
    const userId = userRef.id;

    const user = {
      id: userId,
      username,
      password,
      publicKey,
      fcmToken: null,
      createdAt: new Date().toISOString(),
    };

    await userRef.set(user);
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
