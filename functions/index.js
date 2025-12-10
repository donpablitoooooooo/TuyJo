const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

/**
 * Cloud Function che invia una notifica push quando viene creato un nuovo messaggio
 * Triggered da: Firestore onCreate su /families/{familyChatId}/messages/{messageId}
 * Region: europe-west1 (Belgio - EU)
 */
exports.sendMessageNotification = functions
  .region('europe-west1')
  .firestore
  .document('families/{familyChatId}/messages/{messageId}')
  .onCreate(async (snapshot, context) => {
    try {
      const familyChatId = context.params.familyChatId;
      const messageId = context.params.messageId;
      const messageData = snapshot.data();

      console.log('📨 New message detected:', {
        familyChatId,
        messageId,
        senderId: messageData.sender_id,
      });

      // 1. Ottieni tutti gli utenti della famiglia
      const usersSnapshot = await admin
        .firestore()
        .collection('families')
        .doc(familyChatId)
        .collection('users')
        .get();

      if (usersSnapshot.empty) {
        console.log('⚠️ No users found in this family');
        return null;
      }

      // 2. Trova il destinatario (l'utente che NON è il sender)
      const senderId = messageData.sender_id;
      const recipients = [];

      usersSnapshot.forEach((doc) => {
        const userId = doc.id;
        const userData = doc.data();

        // Invia solo agli utenti che NON sono il sender
        if (userId !== senderId && userData.fcm_token) {
          recipients.push({
            userId,
            token: userData.fcm_token,
          });
        }
      });

      if (recipients.length === 0) {
        console.log('⚠️ No recipients with FCM tokens found');
        return null;
      }

      console.log(`📤 Sending notifications to ${recipients.length} recipients`);

      // 3. Invia la notifica a ciascun destinatario
      const notifications = recipients.map((recipient) => {
        const message = {
          notification: {
            title: '💬 Nuovo messaggio',
            body: 'Hai ricevuto un nuovo messaggio crittografato',
          },
          data: {
            familyChatId: familyChatId,
            messageId: messageId,
            senderId: senderId,
          },
          token: recipient.token,
          // Configurazioni Android
          android: {
            notification: {
              channelId: 'high_importance_channel',
              priority: 'high',
              sound: 'default',
            },
          },
          // Configurazioni iOS
          apns: {
            payload: {
              aps: {
                sound: 'default',
                badge: 1,
              },
            },
          },
        };

        return admin
          .messaging()
          .send(message)
          .then((response) => {
            console.log('✅ Notification sent successfully to:', recipient.userId, response);
            return response;
          })
          .catch((error) => {
            console.error('❌ Error sending notification to:', recipient.userId, error);

            // Se il token è invalido, rimuovilo dal database
            if (error.code === 'messaging/invalid-registration-token' ||
                error.code === 'messaging/registration-token-not-registered') {
              console.log('🗑️ Removing invalid token for user:', recipient.userId);
              return admin
                .firestore()
                .collection('families')
                .doc(familyChatId)
                .collection('users')
                .doc(recipient.userId)
                .update({
                  fcm_token: admin.firestore.FieldValue.delete(),
                });
            }
            return null;
          });
      });

      await Promise.all(notifications);
      console.log('✅ All notifications processed');
      return null;
    } catch (error) {
      console.error('❌ Error in sendMessageNotification:', error);
      return null;
    }
  });

/**
 * Cloud Function per pulire i token FCM scaduti (opzionale)
 * Può essere chiamata periodicamente con Cloud Scheduler
 * Region: europe-west1 (Belgio - EU)
 */
exports.cleanupExpiredTokens = functions
  .region('europe-west1')
  .https.onRequest(async (req, res) => {
  try {
    console.log('🧹 Starting token cleanup...');

    // Questa funzione può essere espansa per pulire token più vecchi di X giorni
    // Per ora è un placeholder

    res.status(200).send('Token cleanup completed');
  } catch (error) {
    console.error('❌ Error in cleanupExpiredTokens:', error);
    res.status(500).send('Error cleaning up tokens');
  }
});
