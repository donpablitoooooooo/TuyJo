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

// Send a new message
router.post('/send', authenticateToken, async (req, res) => {
  try {
    const { receiverId, encryptedContent } = req.body;
    const senderId = req.user.userId;

    if (!receiverId || !encryptedContent) {
      return res.status(400).json({ error: 'receiverId and encryptedContent are required' });
    }

    const message = await messageService.saveMessage({
      senderId,
      receiverId,
      encryptedContent,
    });

    res.status(201).json(message);
  } catch (error) {
    console.error('Send message error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Mark message as read
router.put('/:messageId/read', authenticateToken, async (req, res) => {
  try {
    const { messageId } = req.params;
    await messageService.markAsRead(messageId);
    res.json({ success: true });
  } catch (error) {
    console.error('Mark as read error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Mark message as delivered
router.put('/:messageId/delivered', authenticateToken, async (req, res) => {
  try {
    const { messageId } = req.params;
    await messageService.markAsDelivered(messageId);
    res.json({ success: true });
  } catch (error) {
    console.error('Mark as delivered error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
