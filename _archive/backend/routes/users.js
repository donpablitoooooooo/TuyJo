const express = require('express');
const { authenticateToken } = require('../middleware/auth');
const userService = require('../services/userService');

const router = express.Router();

// Get partner (the other user)
router.get('/partner', authenticateToken, async (req, res) => {
  try {
    const currentUserId = req.user.userId;
    const partner = await userService.getPartner(currentUserId);

    if (!partner) {
      return res.status(404).json({ error: 'Partner not found' });
    }

    res.json({
      id: partner.id,
      username: partner.username,
      publicKey: partner.publicKey,
    });
  } catch (error) {
    console.error('Get partner error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Update FCM token
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
