const express = require('express');
const jwt = require('jsonwebtoken');
const userService = require('../services/userService');
const { admin } = require('../services/database');

const router = express.Router();

/**
 * POST /api/auth/register
 * Registra un nuovo utente con la sua chiave pubblica
 * Body: { "publicKey": "PEM_or_base64" }
 */
router.post('/register', async (req, res) => {
  try {
    const { publicKey } = req.body;

    if (!publicKey) {
      return res.status(400).json({ error: 'publicKey is required' });
    }

    // Verifica se l'utente esiste già
    const exists = await userService.userExists(publicKey);
    if (exists) {
      return res.status(400).json({ error: 'User already exists with this public key' });
    }

    // Crea l'utente (userId = SHA-256(publicKey))
    const user = await userService.createUser({ publicKey });

    // Genera JWT per il backend (sessione temporanea)
    const backendToken = jwt.sign(
      { userId: user.id },
      process.env.JWT_SECRET,
      { expiresIn: '30d' }
    );

    // Genera Firebase Custom Token
    const firebaseToken = await admin.auth().createCustomToken(user.id);

    res.status(201).json({
      backend_token: backendToken,
      firebase_token: firebaseToken,
      user: {
        id: user.id,
        public_key: user.public_key,
      },
    });
  } catch (error) {
    console.error('Register error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

/**
 * POST /api/auth/login
 * Login con chiave pubblica (versione semplificata)
 * Body: { "publicKey": "PEM_or_base64" }
 *
 * TODO: Implementare challenge/response con firma RSA per sicurezza completa
 */
router.post('/login', async (req, res) => {
  try {
    const { publicKey } = req.body;

    if (!publicKey) {
      return res.status(400).json({ error: 'publicKey is required' });
    }

    // Verifica che l'utente esista
    const user = await userService.getUserByPublicKey(publicKey);
    if (!user) {
      return res.status(401).json({ error: 'User not found' });
    }

    // Genera JWT per il backend
    const backendToken = jwt.sign(
      { userId: user.id },
      process.env.JWT_SECRET,
      { expiresIn: '30d' }
    );

    // Genera Firebase Custom Token
    const firebaseToken = await admin.auth().createCustomToken(user.id);

    res.json({
      backend_token: backendToken,
      firebase_token: firebaseToken,
      user: {
        id: user.id,
        public_key: user.public_key,
      },
    });
  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
