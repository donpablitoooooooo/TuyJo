const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const userService = require('../services/userService');

const router = express.Router();

// Register
router.post('/register', async (req, res) => {
  try {
    console.log('📝 Richiesta registrazione ricevuta');
    const { username, password, publicKey } = req.body;
    console.log(`👤 Username: ${username}`);

    if (!username || !password || !publicKey) {
      console.log('❌ Parametri mancanti');
      return res.status(400).json({ error: 'Username, password and publicKey are required' });
    }

    // Check if user already exists
    console.log('🔍 Controllo se utente esiste...');
    const existingUser = await userService.getUserByUsername(username);
    if (existingUser) {
      console.log('⚠️ Username già esistente');
      return res.status(400).json({ error: 'Username already exists' });
    }

    // Hash password
    console.log('🔒 Hash password...');
    const hashedPassword = await bcrypt.hash(password, 10);

    // Create user
    console.log('💾 Creazione utente...');
    const user = await userService.createUser({
      username,
      password: hashedPassword,
      publicKey,
    });
    console.log(`✅ Utente creato con ID: ${user.id}`);

    // Generate JWT
    console.log('🎫 Generazione JWT token...');
    const token = jwt.sign(
      { userId: user.id, username: user.username },
      process.env.JWT_SECRET,
      { expiresIn: '30d' }
    );

    console.log('✅ Registrazione completata con successo!');
    res.status(201).json({
      token,
      user: {
        id: user.id,
        username: user.username,
        publicKey: user.publicKey,
      },
    });
  } catch (error) {
    console.error('❌ Register error:', error);
    res.status(500).json({ error: 'Internal server error', details: error.message });
  }
});

// Login
router.post('/login', async (req, res) => {
  try {
    console.log('🔐 Richiesta login ricevuta');
    const { username, password } = req.body;
    console.log(`👤 Username: ${username}`);

    if (!username || !password) {
      console.log('❌ Username o password mancanti');
      return res.status(400).json({ error: 'Username and password are required' });
    }

    // Get user
    console.log('🔍 Ricerca utente nel database...');
    const user = await userService.getUserByUsername(username);
    if (!user) {
      console.log('❌ Utente non trovato');
      return res.status(401).json({ error: 'Invalid credentials' });
    }
    console.log(`✅ Utente trovato: ${user.id}`);

    // Check password
    console.log('🔑 Verifica password...');
    const isValidPassword = await bcrypt.compare(password, user.password);
    if (!isValidPassword) {
      console.log('❌ Password non valida');
      return res.status(401).json({ error: 'Invalid credentials' });
    }
    console.log('✅ Password corretta');

    // Generate JWT
    console.log('🎫 Generazione JWT token...');
    const token = jwt.sign(
      { userId: user.id, username: user.username },
      process.env.JWT_SECRET,
      { expiresIn: '30d' }
    );

    console.log('✅ Login completato con successo!');
    res.json({
      token,
      user: {
        id: user.id,
        username: user.username,
        publicKey: user.publicKey,
      },
    });
  } catch (error) {
    console.error('❌ Login error:', error);
    res.status(500).json({ error: 'Internal server error', details: error.message });
  }
});

module.exports = router;
