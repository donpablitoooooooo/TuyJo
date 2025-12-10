const { admin } = require('./database');

class NotificationService {
  // Invia una notifica push tramite Firebase Cloud Messaging
  async sendPushNotification(fcmToken, title, body) {
    try {
      const message = {
        notification: {
          title,
          body,
        },
        token: fcmToken,
      };

      const response = await admin.messaging().send(message);
      console.log('Push notification sent:', response);
      return response;
    } catch (error) {
      console.error('Error sending push notification:', error);
      throw error;
    }
  }

  // Invia notifica a più dispositivi
  async sendMulticastNotification(fcmTokens, title, body) {
    try {
      const message = {
        notification: {
          title,
          body,
        },
        tokens: fcmTokens,
      };

      const response = await admin.messaging().sendMulticast(message);
      console.log(`${response.successCount} notifications sent successfully`);
      return response;
    } catch (error) {
      console.error('Error sending multicast notification:', error);
      throw error;
    }
  }
}

module.exports = new NotificationService();
