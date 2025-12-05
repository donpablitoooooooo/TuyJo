const express = require('express');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const userService = require('../services/userService');

const router = express.Router();

// POST /register - Registra nuovo utente (solo publicKey)
router.post('/register', async (req, res) => {
  try {
    const { publicKey } = req.body;

    if (!publicKey) {
      return res.status(400).json({ error: 'publicKey is required' });
    }

    // Crea utente con user_id = SHA-256(publicKey)
    const user = await userService.createUser({ publicKey });

    // Generate JWT
    const token = jwt.sign(
      { userId: user.user_id },
      process.env.JWT_SECRET,
      { expiresIn: '30d' }
    );

    res.status(201).json({
      token,
      user_id: user.user_id,
    });
  } catch (error) {
    console.error('Register error:', error);
    if (error.message === 'User already exists') {
      return res.status(400).json({ error: 'User already exists' });
    }
    res.status(500).json({ error: 'Internal server error' });
  }
});

// POST /auth/request - Richiedi challenge per autenticazione
router.post('/auth/request', async (req, res) => {
  try {
    const { user_id } = req.body;

    if (!user_id) {
      return res.status(400).json({ error: 'user_id is required' });
    }

    // Verifica che l'utente esista
    const user = await userService.getUserById(user_id);
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Genera challenge (32 byte random)
    const challenge = crypto.randomBytes(32).toString('base64');

    // Salva challenge con scadenza 2 minuti
    await userService.saveChallenge(user_id, challenge);

    res.json({ challenge });
  } catch (error) {
    console.error('Challenge request error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// POST /auth/verify - Verifica firma challenge e rilascia JWT
router.post('/auth/verify', async (req, res) => {
  try {
    const { user_id, signature } = req.body;

    if (!user_id || !signature) {
      return res.status(400).json({ error: 'user_id and signature are required' });
    }

    // Ottieni utente
    const user = await userService.getUserById(user_id);
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Ottieni challenge salvato
    const challenge = await userService.getChallenge(user_id);
    if (!challenge) {
      return res.status(401).json({ error: 'Challenge expired or not found' });
    }

    // Verifica firma RSA-SHA256
    const publicKey = user.public_key;
    const verify = crypto.createVerify('RSA-SHA256');
    verify.update(challenge);
    verify.end();

    const isValid = verify.verify(publicKey, signature, 'base64');

    if (!isValid) {
      return res.status(401).json({ error: 'Invalid signature' });
    }

    // Elimina challenge (usa e getta)
    await userService.deleteChallenge(user_id);

    // Genera JWT (30 giorni)
    const token = jwt.sign(
      { userId: user_id },
      process.env.JWT_SECRET,
      { expiresIn: '30d' }
    );

    res.json({
      token,
      user_id,
      public_key: publicKey,
    });
  } catch (error) {
    console.error('Verify error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
