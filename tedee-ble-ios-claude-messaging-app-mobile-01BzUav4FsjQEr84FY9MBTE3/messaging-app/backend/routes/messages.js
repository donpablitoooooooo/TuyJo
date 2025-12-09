const express = require('express');
const { authenticateToken } = require('../middleware/auth');
const messageService = require('../services/messageService');
const notificationService = require('../services/notificationService');
const userService = require('../services/userService');

const router = express.Router();

/**
 * POST /api/messages
 * Invia un messaggio cifrato ad un destinatario
 * Body:
 * {
 *   "recipient_id": "hash_sha256_pubkey_destinatario",
 *   "ciphertext": "base64...",
 *   "nonce": "base64...",
 *   "tag": "base64..."
 * }
 */
router.post('/', authenticateToken, async (req, res) => {
  try {
    const { recipient_id, ciphertext, nonce, tag } = req.body;

    // Validazione input
    if (!recipient_id || !ciphertext || !nonce || !tag) {
      return res.status(400).json({
        error: 'recipient_id, ciphertext, nonce, and tag are required',
      });
    }

    // Verifica che il destinatario esista
    const recipient = await userService.getUserById(recipient_id);
    if (!recipient) {
      return res.status(404).json({ error: 'Recipient not found' });
    }

    // Salva il messaggio nell'inbox del destinatario
    const message = await messageService.saveMessage({
      recipientId: recipient_id,
      ciphertext,
      nonce,
      tag,
    });

    // Invia notifica push se il destinatario ha un FCM token
    if (recipient.fcmToken) {
      try {
        await notificationService.sendPushNotification(
          recipient.fcmToken,
          'Nuovo messaggio',
          'Hai ricevuto un nuovo messaggio'
        );
      } catch (notifError) {
        console.error('Error sending push notification:', notifError);
        // Non bloccare la risposta se la notifica fallisce
      }
    }

    res.status(201).json({
      success: true,
      message_id: message.id,
      created_at: message.created_at,
    });
  } catch (error) {
    console.error('Send message error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

/**
 * GET /api/messages
 * Ottieni tutti i messaggi dell'inbox dell'utente autenticato
 */
router.get('/', authenticateToken, async (req, res) => {
  try {
    const userId = req.user.userId;
    const messages = await messageService.getInboxMessages(userId);
    res.json(messages);
  } catch (error) {
    console.error('Get messages error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

/**
 * DELETE /api/messages/:messageId
 * Elimina un messaggio dalla propria inbox
 */
router.delete('/:messageId', authenticateToken, async (req, res) => {
  try {
    const userId = req.user.userId;
    const { messageId } = req.params;

    await messageService.deleteMessage(userId, messageId);

    res.json({ success: true });
  } catch (error) {
    console.error('Delete message error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
