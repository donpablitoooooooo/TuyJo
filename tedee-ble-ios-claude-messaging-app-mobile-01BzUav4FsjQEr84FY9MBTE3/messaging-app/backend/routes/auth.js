const express = require('express');
const jwt = require('jsonwebtoken');
const userService = require('../services/userService');

const router = express.Router();

// Register - solo username e publicKey
router.post('/register', async (req, res) => {
  try {
    const { username, publicKey } = req.body;

    if (!username || !publicKey) {
      return res.status(400).json({ error: 'Username and publicKey are required' });
    }

    // Check if user already exists
    const existingUser = await userService.getUserByUsername(username);
    if (existingUser) {
      return res.status(400).json({ error: 'Username already exists' });
    }

    // Create user (senza password!)
    const user = await userService.createUser({
      username,
      publicKey,
    });

    // Generate JWT
    const token = jwt.sign(
      { userId: user.id, username: user.username },
      process.env.JWT_SECRET,
      { expiresIn: '30d' }
    );

    // Notify all connected users that a new user registered
    const io = req.app.get('io');
    if (io) {
      io.emit('user_registered', {
        userId: user.id,
        username: user.username,
      });
      console.log(`📢 Broadcast: user_registered for ${user.username}`);
    }

    res.status(201).json({
      token,
      user: {
        id: user.id,
        username: user.username,
        publicKey: user.publicKey,
      },
    });
  } catch (error) {
    console.error('Register error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Login - solo username (la chiave privata è lato client)
router.post('/login', async (req, res) => {
  try {
    const { username } = req.body;

    if (!username) {
      return res.status(400).json({ error: 'Username is required' });
    }

    // Get user
    const user = await userService.getUserByUsername(username);
    if (!user) {
      return res.status(401).json({ error: 'User not found' });
    }

    // Generate JWT
    const token = jwt.sign(
      { userId: user.id, username: user.username },
      process.env.JWT_SECRET,
      { expiresIn: '30d' }
    );

    res.json({
      token,
      user: {
        id: user.id,
        username: user.username,
        publicKey: user.publicKey,
      },
    });
  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
