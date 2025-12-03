const express = require('express');
const { authenticateToken } = require('../middleware/auth');
const messageService = require('../services/messageService');

const router = express.Router();

// Get all messages for the authenticated user
router.get('/', authenticateToken, async (req, res) => {
  try {
    const userId = req.user.userId;
    const messages = await messageService.getMessagesForUser(userId);
    res.json(messages);
  } catch (error) {
    console.error('Get messages error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
