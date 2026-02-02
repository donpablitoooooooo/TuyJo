const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

// 🌍 Localizzazione notifiche push (IT, EN, ES, CA)
const NOTIFICATION_TEXTS = {
  it: {
    newMessage: {
      title: '💬 Nuovo messaggio',
      body: 'Hai ricevuto un nuovo messaggio crittografato',
    },
    newTodo: {
      title: '📅 Nuovo To Do',
      body: 'Il tuo partner ha creato un nuovo promemoria',
    },
    incomingCall: {
      title: '📞 Chiamata in arrivo',
      body: 'Il tuo partner ti sta chiamando',
    },
  },
  en: {
    newMessage: {
      title: '💬 New message',
      body: 'You have received a new encrypted message',
    },
    newTodo: {
      title: '📅 New To Do',
      body: 'Your partner has created a new reminder',
    },
    incomingCall: {
      title: '📞 Incoming call',
      body: 'Your partner is calling you',
    },
  },
  es: {
    newMessage: {
      title: '💬 Nuevo mensaje',
      body: 'Has recibido un nuevo mensaje cifrado',
    },
    newTodo: {
      title: '📅 Nuevo To Do',
      body: 'Tu pareja ha creado un nuevo recordatorio',
    },
    incomingCall: {
      title: '📞 Llamada entrante',
      body: 'Tu pareja te está llamando',
    },
  },
  ca: {
    newMessage: {
      title: '💬 Nou missatge',
      body: 'Has rebut un nou missatge xifrat',
    },
    newTodo: {
      title: '📅 Nou To Do',
      body: 'La teva parella ha creat un nou recordatori',
    },
    incomingCall: {
      title: '📞 Trucada entrant',
      body: 'La teva parella et truca',
    },
  },
};

// Funzione helper per ottenere i testi localizzati (default: italiano)
function getLocalizedText(language, messageType) {
  const lang = NOTIFICATION_TEXTS[language] || NOTIFICATION_TEXTS.it;
  if (messageType === 'incoming_call') return lang.incomingCall;
  return messageType === 'todo' ? lang.newTodo : lang.newMessage;
}

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
            language: userData.language || 'it', // Default: italiano
          });
        }
      });

      if (recipients.length === 0) {
        console.log('⚠️ No recipients with FCM tokens found');
        return null;
      }

      console.log(`📤 Sending notifications to ${recipients.length} recipients`);

      // 3. Determina il tipo di notifica in base al message_type
      const messageType = messageData.message_type || 'text';

      // Salta le notifiche per i completamenti
      if (messageType === 'todo_completed') {
        console.log('⏭️  Skipping notification for todo_completed message');
        return null;
      }

      // 4. Invia la notifica a ciascun destinatario (con testo localizzato)
      const notifications = recipients.map((recipient) => {
        // Ottieni testi localizzati per la lingua del destinatario
        const localizedText = getLocalizedText(recipient.language, messageType);

        const message = {
          notification: {
            title: localizedText.title,
            body: localizedText.body,
          },
          data: {
            familyChatId: familyChatId,
            messageId: messageId,
            senderId: senderId,
            messageType: messageType,
          },
          token: recipient.token,
          // Configurazioni Android (stesse per tutti - FCM funziona con default)
          android: {
            notification: {
              channelId: 'messages_channel',
              priority: 'default',
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
 * Cloud Function che invia una notifica push ad alta priorità quando viene avviata una chiamata
 * Triggered da: Firestore onWrite su /families/{familyChatId}/calls/current
 * Region: europe-west1 (Belgio - EU)
 *
 * La notifica è ad alta priorità per svegliare il dispositivo anche in Doze mode
 */
exports.sendCallNotification = functions
  .region('europe-west1')
  .firestore
  .document('families/{familyChatId}/calls/current')
  .onWrite(async (change, context) => {
    try {
      const familyChatId = context.params.familyChatId;

      // Se il documento è stato eliminato, non fare nulla
      if (!change.after.exists) {
        console.log('📞 Call document deleted, skipping');
        return null;
      }

      const callData = change.after.data();
      const callerId = callData.caller_id;
      const status = callData.status;

      console.log('📞 Call signal detected:', {familyChatId, callerId, status});

      // Invia notifica solo quando lo stato è "ringing" (nuova chiamata)
      if (status !== 'ringing') {
        console.log(`⏭️ Skipping notification for call status: ${status}`);
        return null;
      }

      // Se il documento esisteva già con status ringing, non reinviare
      if (change.before.exists) {
        const prevData = change.before.data();
        if (prevData.status === 'ringing') {
          console.log('⏭️ Call was already ringing, skipping duplicate notification');
          return null;
        }
      }

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

      // 2. Trova il destinatario (chi NON è il caller)
      const recipients = [];
      usersSnapshot.forEach((doc) => {
        const userId = doc.id;
        const userData = doc.data();
        if (userId !== callerId && userData.fcm_token) {
          recipients.push({
            userId,
            token: userData.fcm_token,
            language: userData.language || 'it',
          });
        }
      });

      if (recipients.length === 0) {
        console.log('⚠️ No recipients with FCM tokens found for call');
        return null;
      }

      console.log(`📤 Sending HIGH PRIORITY call notifications to ${recipients.length} recipients`);

      // 3. Invia notifica DATA-ONLY ad alta priorità a ciascun destinatario
      // NOTA: Data-only (senza notification payload) permette al background handler
      // di processare il messaggio e mostrare la UI nativa CallKit
      const notifications = recipients.map((recipient) => {
        const localizedText = getLocalizedText(recipient.language, 'incoming_call');

        const message = {
          // Solo data payload — NO notification payload!
          // Questo è fondamentale per CallKit: il background handler Flutter
          // riceve il data message e chiama FlutterCallkitIncoming.showCallkitIncoming()
          data: {
            type: 'incoming_call',
            familyChatId: familyChatId,
            callerId: callerId,
            callerName: localizedText.body, // "Il tuo partner ti sta chiamando"
            status: status,
          },
          token: recipient.token,
          // Android: alta priorità per svegliare l'app in Doze mode
          android: {
            priority: 'high',
            ttl: '30s',
          },
          // iOS: alta priorità + content-available per svegliare l'app in background
          apns: {
            headers: {
              'apns-priority': '10',
              'apns-push-type': 'background',
            },
            payload: {
              aps: {
                'content-available': 1,
              },
            },
          },
        };

        return admin
          .messaging()
          .send(message)
          .then((response) => {
            console.log('✅ Call notification sent to:', recipient.userId, response);
            return response;
          })
          .catch((error) => {
            console.error('❌ Error sending call notification to:', recipient.userId, error);
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
      console.log('✅ All call notifications processed');
      return null;
    } catch (error) {
      console.error('❌ Error in sendCallNotification:', error);
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
