const functions = require('firebase-functions/v1');
const {defineSecret} = require('firebase-functions/params');
const admin = require('firebase-admin');
const http2 = require('http2');
const crypto = require('crypto');

admin.initializeApp();

// ═══════════════════════════════════════════════════════════════════
// APNs VoIP (PushKit) — chiamate in arrivo su iOS
// ═══════════════════════════════════════════════════════════════════
// FCM non può inviare push VoIP: per far squillare un iPhone con app in
// background o terminata serve un push PushKit inviato direttamente ad APNs.
// Configurazione (una volta sola):
//   firebase functions:secrets:set APNS_AUTH_KEY   # contenuto del file .p8
//   firebase functions:secrets:set APNS_KEY_ID     # es. ABC123DEFG
//   firebase functions:secrets:set APNS_TEAM_ID    # PW2GC2RTH2
// La chiave .p8 si crea in Apple Developer → Keys → "Apple Push Notifications
// service (APNs)". Se i secret mancano, la funzione ripiega su FCM.
const APNS_AUTH_KEY = defineSecret('APNS_AUTH_KEY');
const APNS_KEY_ID = defineSecret('APNS_KEY_ID');
const APNS_TEAM_ID = defineSecret('APNS_TEAM_ID');
const IOS_BUNDLE_ID = 'com.privatemessaging.tuyjo';

let cachedApnsJwt = null;
let cachedApnsJwtAt = 0;

/** JWT ES256 per APNs (valido 1h, Apple accetta fino a 60 min). Cache 50 min. */
function apnsJwt(keyId, teamId, p8) {
  const now = Math.floor(Date.now() / 1000);
  if (cachedApnsJwt && now - cachedApnsJwtAt < 50 * 60) return cachedApnsJwt;
  const b64 = (obj) => Buffer.from(JSON.stringify(obj)).toString('base64url');
  const header = b64({alg: 'ES256', kid: keyId});
  const claims = b64({iss: teamId, iat: now});
  const input = `${header}.${claims}`;
  const signature = crypto
    .sign('sha256', Buffer.from(input), {key: p8, dsaEncoding: 'ieee-p1363'})
    .toString('base64url');
  cachedApnsJwt = `${input}.${signature}`;
  cachedApnsJwtAt = now;
  return cachedApnsJwt;
}

/**
 * Invia un push VoIP ad APNs via HTTP/2.
 * Prova prima production; se il token è di un build di sviluppo (Xcode)
 * APNs risponde BadDeviceToken e riproviamo su sandbox.
 * @return {Promise<{ok: boolean, status: number, reason?: string, env: string}>}
 */
async function sendApnsVoip(deviceToken, payload, creds) {
  const attempt = (host, env) => new Promise((resolve) => {
    const client = http2.connect(`https://${host}`);
    let settled = false;
    const finish = (r) => {
      if (settled) return;
      settled = true;
      client.close();
      resolve(r);
    };
    client.on('error', (e) => finish({ok: false, status: 0, reason: String(e), env}));
    const req = client.request({
      ':method': 'POST',
      ':path': `/3/device/${deviceToken}`,
      'authorization': `bearer ${apnsJwt(creds.keyId, creds.teamId, creds.p8)}`,
      'apns-topic': `${IOS_BUNDLE_ID}.voip`,
      'apns-push-type': 'voip',
      'apns-priority': '10',
      'apns-expiration': String(Math.floor(Date.now() / 1000) + 30),
      'content-type': 'application/json',
    });
    let status = 0;
    let body = '';
    req.on('response', (headers) => {
      status = headers[':status'];
    });
    req.on('data', (chunk) => {
      body += chunk;
    });
    req.on('end', () => {
      let reason;
      try {
        reason = body ? JSON.parse(body).reason : undefined;
      } catch (e) {
        reason = body;
      }
      finish({ok: status === 200, status, reason, env});
    });
    req.on('error', (e) => finish({ok: false, status: 0, reason: String(e), env}));
    req.setTimeout(8000, () => {
      req.close();
      finish({ok: false, status: 0, reason: 'timeout', env});
    });
    req.end(JSON.stringify(payload));
  });

  let res = await attempt('api.push.apple.com', 'production');
  if (!res.ok && res.reason === 'BadDeviceToken') {
    res = await attempt('api.sandbox.push.apple.com', 'sandbox');
  }
  return res;
}

function apnsCredentials() {
  try {
    const p8 = APNS_AUTH_KEY.value();
    const keyId = APNS_KEY_ID.value();
    const teamId = APNS_TEAM_ID.value();
    if (p8 && keyId && teamId) return {p8, keyId, teamId};
  } catch (e) {
    console.log('⚠️ APNs secrets not available:', e.message);
  }
  return null;
}

/** UUID v4 per CallKit (iOS lo richiede in formato RFC 4122) */
function callKitUuid() {
  return crypto.randomUUID().toUpperCase();
}

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

// Testi della UI nativa CallKit (nome chiamante, pulsanti, chiamata persa)
// nella lingua del destinatario. L'app li usa se presenti, altrimenti
// ripiega sulla lingua del dispositivo.
const CALLKIT_TEXTS = {
  it: {nameCaller: 'Partner', textAccept: 'Accetta', textDecline: 'Rifiuta',
    incomingChannel: 'Chiamate in arrivo', missedChannel: 'Chiamate perse',
    missedSubtitle: 'Chiamata persa', callback: 'Richiama'},
  en: {nameCaller: 'Partner', textAccept: 'Accept', textDecline: 'Decline',
    incomingChannel: 'Incoming calls', missedChannel: 'Missed calls',
    missedSubtitle: 'Missed call', callback: 'Call back'},
  es: {nameCaller: 'Pareja', textAccept: 'Aceptar', textDecline: 'Rechazar',
    incomingChannel: 'Llamadas entrantes', missedChannel: 'Llamadas perdidas',
    missedSubtitle: 'Llamada perdida', callback: 'Devolver llamada'},
  ca: {nameCaller: 'Parella', textAccept: 'Accepta', textDecline: 'Rebutja',
    incomingChannel: 'Trucades entrants', missedChannel: 'Trucades perdudes',
    missedSubtitle: 'Trucada perduda', callback: 'Torna la trucada'},
};
function getCallKitTexts(language) {
  return CALLKIT_TEXTS[language] || CALLKIT_TEXTS.it;
}

// Funzione helper per ottenere i testi localizzati (default: italiano)
function getLocalizedText(language, messageType) {
  const lang = NOTIFICATION_TEXTS[language] || NOTIFICATION_TEXTS.it;
  if (messageType === 'incoming_call') return lang.incomingCall;
  return messageType === 'todo' ? lang.newTodo : lang.newMessage;
}

/**
 * Conta i messaggi del partner non ancora letti dal destinatario.
 *
 * La lettura è tracciata in read_receipts/{userId}.messageIds (gli id dei
 * messaggi ricevuti che il client aveva caricati quando ha marcato come
 * letto). Il client tiene una finestra live di 100 messaggi: scansioniamo
 * gli ultimi 60, così ogni messaggio "letto" in quella finestra è
 * sicuramente nella lista. `created_at` è una stringa ISO locale, quindi
 * non è confrontabile con un timestamp server: per questo si ragiona per id.
 * Minimo 1 (c'è almeno il messaggio appena arrivato), massimo 99.
 */
async function countUnreadForRecipient(familyChatId, recipientId, partnerId) {
  try {
    const family = admin.firestore().collection('families').doc(familyChatId);
    const receiptSnap = await family.collection('read_receipts').doc(recipientId).get();
    const readIds = new Set(
      receiptSnap.exists && Array.isArray(receiptSnap.data().messageIds)
        ? receiptSnap.data().messageIds
        : [],
    );
    const recent = await family
      .collection('messages')
      .orderBy('created_at', 'desc')
      .limit(60)
      .select('sender_id')
      .get();
    let unread = 0;
    recent.forEach((doc) => {
      if (doc.data().sender_id === partnerId && !readIds.has(doc.id)) unread++;
    });
    return Math.min(Math.max(unread, 1), 99);
  } catch (e) {
    console.log('⚠️ countUnreadForRecipient failed, defaulting to 1:', e.message);
    return 1;
  }
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
      const notifications = recipients.map(async (recipient) => {
        // Ottieni testi localizzati per la lingua del destinatario
        const localizedText = getLocalizedText(recipient.language, messageType);

        // Badge iOS = messaggi del partner non ancora letti dal destinatario
        // (prima era un "1" fisso, mai azzerato: per questo restava sempre 1)
        const unread = await countUnreadForRecipient(familyChatId, recipient.userId, senderId);

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
              // Stesso tag → la nuova notifica SOSTITUISCE la precedente:
              // una sola notifica con il conteggio giusto, invece di N
              // notifiche i cui conteggi alcuni launcher (Samsung) sommano.
              // Il testo è comunque generico (E2E), non si perde nulla.
              tag: messageType === 'todo' ? 'tuyjo_todo' : 'tuyjo_messages',
              notificationCount: unread,
            },
          },
          // Configurazioni iOS
          apns: {
            payload: {
              aps: {
                sound: 'default',
                badge: unread,
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
 * Notifica di chiamata in arrivo (+ annullamento).
 * Triggered da: Firestore onWrite su /families/{familyChatId}/calls/current
 * Region: europe-west1 (Belgio - EU)
 *
 * - status → 'ringing': notifica il partner.
 *     iOS con voip_token: push VoIP PushKit via APNs (unico canale
 *     affidabile a app chiusa; CallKit squilla nativamente).
 *     Android / fallback: FCM data-only ad alta priorità → background
 *     handler Flutter → UI CallKit.
 * - 'ringing' → 'ended'/'declined' scritto dal caller (ended_by == caller_id)
 *   o documento eliminato: push 'call_cancelled' così il telefono del
 *   partner smette di squillare subito invece di aspettare il timeout.
 */
exports.sendCallNotification = functions
  .region('europe-west1')
  .runWith({secrets: [APNS_AUTH_KEY, APNS_KEY_ID, APNS_TEAM_ID]})
  .firestore
  .document('families/{familyChatId}/calls/current')
  .onWrite(async (change, context) => {
    try {
      const familyChatId = context.params.familyChatId;
      const before = change.before.exists ? change.before.data() : null;
      const after = change.after.exists ? change.after.data() : null;

      // ── Annullamento: il caller ha riagganciato mentre squillava ──
      const wasRinging = before && before.status === 'ringing';
      // (un 'declined' senza ended_by è il callee che rifiuta: non è un
      // annullamento, il callee ha già chiuso la sua UI da solo)
      const cancelledByCaller = wasRinging && (
        !after ||
        ((after.status === 'ended' || after.status === 'declined') &&
          !!after.ended_by && after.ended_by === before.caller_id)
      );
      if (cancelledByCaller) {
        console.log('📞 Call cancelled by caller while ringing → notify callee');
        const recipients = await callRecipients(familyChatId, before.caller_id);
        await Promise.all(recipients.map((r) => sendFcmData(familyChatId, r, {
          type: 'call_cancelled',
          familyChatId,
          callerId: before.caller_id || '',
          callId: before.callId || '',
        }, 20)));
        return null;
      }

      if (!after) {
        console.log('📞 Call document deleted, skipping');
        return null;
      }

      const callerId = after.caller_id;
      const status = after.status;
      console.log('📞 Call signal detected:', {familyChatId, callerId, status});

      // Invia notifica solo quando lo stato è "ringing" (nuova chiamata)
      if (status !== 'ringing') {
        console.log(`⏭️ Skipping notification for call status: ${status}`);
        return null;
      }
      if (wasRinging && before.callId === after.callId) {
        console.log('⏭️ Call was already ringing, skipping duplicate notification');
        return null;
      }

      const recipients = await callRecipients(familyChatId, callerId);
      if (recipients.length === 0) {
        console.log('⚠️ No recipients with push tokens found for call');
        return null;
      }

      console.log(`📤 Sending call notifications to ${recipients.length} recipient(s)`);
      const creds = apnsCredentials();

      await Promise.all(recipients.map(async (recipient) => {
        const localizedText = getLocalizedText(recipient.language, 'incoming_call');
        const ck = getCallKitTexts(recipient.language);

        // ── iOS: VoIP push via APNs ──
        if (recipient.platform === 'ios' && recipient.voipToken && creds) {
          const payload = {
            id: callKitUuid(),
            nameCaller: ck.nameCaller,
            appName: 'TuyJo',
            handle: 'TuyJo',
            type: 0,
            duration: 30000,
            extra: {familyChatId, callerId, callId: after.callId || ''},
            ios: {
              iconName: 'AppIcon',
              handleType: 'generic',
              supportsVideo: false,
              maximumCallGroups: 1,
              maximumCallsPerCallGroup: 1,
              supportsDTMF: false,
              supportsHolding: false,
              supportsGrouping: false,
              supportsUngrouping: false,
              includesCallsInRecents: true,
              configureAudioSession: true,
              audioSessionMode: 'voiceChat',
              audioSessionActive: true,
              audioSessionPreferredSampleRate: 48000.0,
              audioSessionPreferredIOBufferDuration: 0.02,
              ringtonePath: 'system_ringtone_default',
            },
            missedCallNotification: {
              showNotification: true,
              isShowCallback: true,
              subtitle: ck.missedSubtitle,
              callbackText: ck.callback,
            },
          };
          const res = await sendApnsVoip(recipient.voipToken, payload, creds);
          if (res.ok) {
            console.log(`✅ VoIP push sent (${res.env}) to:`, recipient.userId);
            return;
          }
          console.error('❌ VoIP push failed:', recipient.userId, res);
          if (res.reason === 'BadDeviceToken' || res.reason === 'Unregistered') {
            await admin.firestore()
              .collection('families').doc(familyChatId)
              .collection('users').doc(recipient.userId)
              .update({voip_token: admin.firestore.FieldValue.delete()});
          }
          // fallthrough → FCM come ultima spiaggia
        }

        // ── Android / fallback: FCM data-only alta priorità ──
        if (!recipient.token) {
          console.log('⚠️ Recipient has no FCM token:', recipient.userId);
          return;
        }
        await sendFcmData(familyChatId, recipient, {
          type: 'incoming_call',
          familyChatId,
          callerId: callerId || '',
          callId: after.callId || '',
          callerName: localizedText.body,
          status: status,
          // Testi UI CallKit nella lingua del destinatario
          nameCaller: ck.nameCaller,
          textAccept: ck.textAccept,
          textDecline: ck.textDecline,
          incomingChannel: ck.incomingChannel,
          missedChannel: ck.missedChannel,
          missedSubtitle: ck.missedSubtitle,
          callback: ck.callback,
        }, 30);
      }));

      console.log('✅ All call notifications processed');
      return null;
    } catch (error) {
      console.error('❌ Error in sendCallNotification:', error);
      return null;
    }
  });

/** Utenti della famiglia diversi dal caller, con i loro token */
async function callRecipients(familyChatId, callerId) {
  const usersSnapshot = await admin
    .firestore()
    .collection('families')
    .doc(familyChatId)
    .collection('users')
    .get();
  const recipients = [];
  usersSnapshot.forEach((doc) => {
    const userId = doc.id;
    const userData = doc.data();
    if (userId === callerId) return;
    if (!userData.fcm_token && !userData.voip_token) return;
    recipients.push({
      userId,
      token: userData.fcm_token,
      voipToken: userData.voip_token,
      platform: userData.platform || (userData.voip_token ? 'ios' : 'android'),
      language: userData.language || 'it',
    });
  });
  return recipients;
}

/**
 * Push FCM data-only ad alta priorità (sveglia il device anche in Doze).
 * Data-only: il background handler Flutter riceve il messaggio e mostra la
 * UI CallKit (o la chiude, per call_cancelled).
 */
async function sendFcmData(familyChatId, recipient, data, ttlSeconds) {
  if (!recipient.token) return null;
  const message = {
    data,
    token: recipient.token,
    android: {
      priority: 'high',
      ttl: ttlSeconds * 1000,
    },
    apns: {
      headers: {
        'apns-priority': '10',
        'apns-push-type': 'background',
        'apns-expiration': String(Math.floor(Date.now() / 1000) + ttlSeconds),
      },
      payload: {
        aps: {
          'content-available': 1,
        },
      },
    },
  };
  try {
    const response = await admin.messaging().send(message);
    console.log(`✅ FCM ${data.type} sent to:`, recipient.userId, response);
    return response;
  } catch (error) {
    console.error(`❌ Error sending FCM ${data.type} to:`, recipient.userId, error);
    if (error.code === 'messaging/invalid-registration-token' ||
        error.code === 'messaging/registration-token-not-registered') {
      console.log('🗑️ Removing invalid token for user:', recipient.userId);
      await admin.firestore()
        .collection('families').doc(familyChatId)
        .collection('users').doc(recipient.userId)
        .update({fcm_token: admin.firestore.FieldValue.delete()});
    }
    return null;
  }
}

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
