const { db } = require('./database');
const crypto = require('crypto');

const USERS_COLLECTION = 'users';
const CHALLENGES_COLLECTION = 'challenges';

class UserService {
  // Genera user_id da publicKey (SHA-256)
  generateUserId(publicKey) {
    return crypto.createHash('sha256').update(publicKey).digest('hex');
  }

  // Crea un nuovo utente (solo publicKey - niente username!)
  async createUser({ publicKey }) {
    const userId = this.generateUserId(publicKey);

    // Verifica se utente già esiste
    const existingUser = await this.getUserById(userId);
    if (existingUser) {
      throw new Error('User already exists');
    }

    const user = {
      user_id: userId,
      public_key: publicKey,
      created_at: new Date().toISOString(),
    };

    await db.collection(USERS_COLLECTION).doc(userId).set(user);
    return user;
  }

  // Ottieni utente per ID
  async getUserById(userId) {
    const doc = await db.collection(USERS_COLLECTION).doc(userId).get();

    if (!doc.exists) {
      return null;
    }

    return doc.data();
  }

  // Salva challenge per autenticazione (scadenza 2 minuti)
  async saveChallenge(userId, challenge) {
    const expiresAt = new Date(Date.now() + 2 * 60 * 1000); // 2 minuti
    await db.collection(CHALLENGES_COLLECTION).doc(userId).set({
      challenge,
      expires_at: expiresAt.toISOString(),
      created_at: new Date().toISOString(),
    });
  }

  // Ottieni e verifica challenge
  async getChallenge(userId) {
    const doc = await db.collection(CHALLENGES_COLLECTION).doc(userId).get();

    if (!doc.exists) {
      return null;
    }

    const data = doc.data();
    const now = new Date();
    const expiresAt = new Date(data.expires_at);

    // Verifica scadenza
    if (now > expiresAt) {
      // Challenge scaduto, elimina
      await db.collection(CHALLENGES_COLLECTION).doc(userId).delete();
      return null;
    }

    return data.challenge;
  }

  // Elimina challenge dopo verifica
  async deleteChallenge(userId) {
    await db.collection(CHALLENGES_COLLECTION).doc(userId).delete();
  }
}

module.exports = new UserService();
