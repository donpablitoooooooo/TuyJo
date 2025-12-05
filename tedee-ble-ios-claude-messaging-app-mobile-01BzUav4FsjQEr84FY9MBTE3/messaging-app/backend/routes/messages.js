const express = require('express');
const { authenticateToken } = require('../middleware/auth');
const messageService = require('../services/messageService');

const router = express.Router();

// POST /messages - Invia messaggio cifrato
router.post('/', authenticateToken, async (req, res) => {
  try {
    const { recipient_id, ciphertext, nonce, tag } = req.body;

    if (!recipient_id || !ciphertext || !nonce || !tag) {
      return res.status(400).json({
        error: 'recipient_id, ciphertext, nonce, and tag are required',
      });
    }

    // Salva messaggio
    const message = await messageService.saveMessage({
      recipient_id,
      ciphertext,
      nonce,
      tag,
    });

    // Notifica via WebSocket (gestito in server.js)
    const io = req.app.get('io');
    if (io) {
      io.to(recipient_id).emit('new_message', {
        message_id: message.message_id,
        ciphertext: message.ciphertext,
        nonce: message.nonce,
        tag: message.tag,
        created_at: message.created_at,
      });
    }

    res.status(201).json({
      message_id: message.message_id,
      created_at: message.created_at,
    });
  } catch (error) {
    console.error('Send message error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// GET /messages/inbox - Ottieni messaggi ricevuti
router.get('/inbox', authenticateToken, async (req, res) => {
  try {
    const userId = req.user.userId;
    const messages = await messageService.getInbox(userId);
    res.json(messages);
  } catch (error) {
    console.error('Get inbox error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
