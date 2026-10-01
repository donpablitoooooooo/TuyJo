// ═══════════════════════════════════════════════════════════════════
// Membri di una chat
// ═══════════════════════════════════════════════════════════════════
// Le regole di Firestore e Storage lasciano entrare in families/{id} solo i
// login anonimi registrati come membri (member_uids). Un login anonimo
// diventa membro dimostrando di avere la chiave privata di uno dei due
// telefoni: firma un messaggio che contiene la chat, il proprio uid e l'ora.
// Le regole non sanno verificare una firma RSA, questa funzione sì.
//
// Funziona allo stesso modo dopo un abbinamento, un recupero o una
// reinstallazione (quando il login anonimo cambia): chi ha il certificato
// giusto rientra, gli altri no.

const crypto = require('crypto');

const SIGNATURE_MAX_AGE_MS = 10 * 60 * 1000;

/** Stesso calcolo dell'app (RecoveryService.userIdOf). */
function userIdOf(publicKey) {
  return crypto.createHash('sha256').update(publicKey, 'utf8').digest('hex');
}

/** Stesso calcolo dell'app (RecoveryService.familyIdOf). */
function familyIdOf(a, b) {
  const keys = [a, b].sort();
  return crypto.createHash('sha256').update(keys.join('|'), 'utf8').digest('hex');
}

/** Il testo che il telefono firma con la propria chiave privata. */
function joinMessage(familyId, uid, timestamp) {
  return `tuijo-join|v1|${familyId}|${uid}|${timestamp}`;
}

/**
 * Controlla una richiesta di ingresso. Restituisce gli id della chat e dei
 * due utenti, oppure lancia un errore con `status` (400/403).
 */
function verifyJoin({publicKey, partnerPublicKey, timestamp, signature, uid, now = Date.now()}) {
  const fail = (status, message) => Object.assign(new Error(message), {status});
  if (typeof publicKey !== 'string' || typeof partnerPublicKey !== 'string' ||
      typeof signature !== 'string' || typeof timestamp !== 'number') {
    throw fail(400, 'bad request');
  }
  if (publicKey === partnerPublicKey) throw fail(400, 'same key');
  if (Math.abs(now - timestamp) > SIGNATURE_MAX_AGE_MS) throw fail(403, 'stale signature');

  let key;
  try {
    key = crypto.createPublicKey({key: Buffer.from(publicKey, 'base64'), format: 'der', type: 'spki'});
  } catch (_) {
    throw fail(400, 'bad public key');
  }
  const familyId = familyIdOf(publicKey, partnerPublicKey);
  const ok = crypto.verify(
    'sha256',
    Buffer.from(joinMessage(familyId, uid, timestamp), 'utf8'),
    key,
    Buffer.from(signature, 'base64'),
  );
  if (!ok) throw fail(403, 'bad signature');

  return {familyId, userId: userIdOf(publicKey), partnerUserId: userIdOf(partnerPublicKey)};
}

/**
 * Registra `uid` come membro della chat in una transazione: un utente ha un
 * solo login valido alla volta (quello vecchio esce), e quando sono entrati
 * tutti e due la chat si chiude (`locked`): da lì valgono solo i membri.
 */
async function addMember(db, {familyId, userId, partnerUserId, uid}) {
  const ref = db.collection('families').doc(familyId);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? snap.data() : {};
    const memberUids = {...(data.member_uids || {})};
    const uidByUser = {...(data.uid_by_user || {})};

    const previous = uidByUser[userId];
    if (previous && previous !== uid) delete memberUids[previous];
    memberUids[uid] = true;
    uidByUser[userId] = uid;

    const locked = data.locked === true || Boolean(uidByUser[userId] && uidByUser[partnerUserId]);
    // update sostituisce le mappe intere (così il login vecchio sparisce);
    // set con merge le fonderebbe e il login vecchio resterebbe.
    const fields = {member_uids: memberUids, uid_by_user: uidByUser, locked};
    if (snap.exists) tx.update(ref, fields);
    else tx.set(ref, fields);
    return {locked};
  });
}

module.exports = {userIdOf, familyIdOf, joinMessage, verifyJoin, addMember, SIGNATURE_MAX_AGE_MS};
