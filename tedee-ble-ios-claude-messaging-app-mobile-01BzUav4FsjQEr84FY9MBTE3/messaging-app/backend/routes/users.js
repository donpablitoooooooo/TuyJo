const express = require('express');
const { authenticateToken } = require('../middleware/auth');
const userService = require('../services/userService');

const router = express.Router();

/**
 * GET /api/users
 * Ottieni tutti gli utenti (per trovare destinatari)
 */
router.get('/', authenticateToken, async (req, res) => {
  try {
    const currentUserId = req.user.userId;
    const users = await userService.getAllUsers();

    // Filtra l'utente corrente
    const otherUsers = users.filter((u) => u.id !== currentUserId);

    res.json(otherUsers);
  } catch (error) {
    console.error('Get users error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

/**
 * GET /api/users/:userId
 * Ottieni un utente specifico
 */
router.get('/:userId', authenticateToken, async (req, res) => {
  try {
    const { userId } = req.params;
    const user = await userService.getUserById(userId);

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    res.json(user);
  } catch (error) {
    console.error('Get user error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

/**
 * POST /api/users/fcm-token
 * Aggiorna il token FCM per notifiche push
 */
router.post('/fcm-token', authenticateToken, async (req, res) => {
  try {
    const userId = req.user.userId;
    const { fcmToken } = req.body;

    if (!fcmToken) {
      return res.status(400).json({ error: 'FCM token is required' });
    }

    await userService.updateFcmToken(userId, fcmToken);
    res.json({ success: true });
  } catch (error) {
    console.error('Update FCM token error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
