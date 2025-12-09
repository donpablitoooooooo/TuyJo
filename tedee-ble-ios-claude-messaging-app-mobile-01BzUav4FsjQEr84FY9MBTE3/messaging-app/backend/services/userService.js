const { db } = require('./database');
const { generateUserId } = require('../utils/crypto');

const USERS_COLLECTION = 'users';

class UserService {
  // Crea un nuovo utente
  async createUser({ publicKey }) {
    // userId = SHA-256(publicKey)
    const userId = generateUserId(publicKey);

    const user = {
      public_key: publicKey,
      created_at: Date.now(),
    };

    await db.collection(USERS_COLLECTION).doc(userId).set(user);

    return {
      id: userId,
      ...user,
    };
  }

  // Ottieni utente per chiave pubblica
  async getUserByPublicKey(publicKey) {
    const userId = generateUserId(publicKey);
    return this.getUserById(userId);
  }

  // Ottieni utente per ID
  async getUserById(userId) {
    const doc = await db.collection(USERS_COLLECTION).doc(userId).get();

    if (!doc.exists) {
      return null;
    }

    return {
      id: doc.id,
      ...doc.data(),
    };
  }

  // Verifica se un utente esiste
  async userExists(publicKey) {
    const userId = generateUserId(publicKey);
    const doc = await db.collection(USERS_COLLECTION).doc(userId).get();
    return doc.exists;
  }

  // Ottieni tutti gli utenti (per test)
  async getAllUsers() {
    const snapshot = await db.collection(USERS_COLLECTION).get();
    return snapshot.docs.map((doc) => ({
      id: doc.id,
      ...doc.data(),
    }));
  }

  // Aggiorna FCM token
  async updateFcmToken(userId, fcmToken) {
    await db.collection(USERS_COLLECTION).doc(userId).update({
      fcmToken,
      updated_at: Date.now(),
    });
  }
}

module.exports = new UserService();
