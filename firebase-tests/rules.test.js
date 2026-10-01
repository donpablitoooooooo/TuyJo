// Test delle regole di Firestore e Storage sull'emulatore.
//
//   cd firebase-tests && npm install
//   npx firebase emulators:exec --only firestore,storage --project demo-tuijo \
//     --config ../firebase.json "npx mocha rules.test.js"
const fs = require('fs');
const path = require('path');
const assert = require('assert');
const {
  initializeTestEnvironment, assertSucceeds, assertFails,
} = require('@firebase/rules-unit-testing');
const {doc, getDoc, setDoc, updateDoc, deleteDoc} = require('firebase/firestore');
const {ref, uploadBytes, getBytes} = require('firebase/storage');

const ROOT = path.join(__dirname, '..');
let env;

// Una chat chiusa (tutti e due i telefoni entrati con joinFamily), una
// vecchia ancora aperta (1.37), una inesistente.
const LOCKED = 'fam-locked';
const LEGACY = 'fam-legacy';

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-tuijo',
    firestore: {rules: fs.readFileSync(path.join(ROOT, 'firestore.rules'), 'utf8')},
    storage: {rules: fs.readFileSync(path.join(ROOT, 'storage.rules'), 'utf8')},
  });
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, `families/${LOCKED}`), {
      member_uids: {alice: true, bob: true},
      uid_by_user: {ua: 'alice', ub: 'bob'},
      locked: true,
    });
    await setDoc(doc(db, `families/${LOCKED}/messages/m1`), {message: 'cifrato'});
    await setDoc(doc(db, `families/${LEGACY}`), {created_at: 'x'});
    await setDoc(doc(db, `families/${LEGACY}/messages/m1`), {message: 'cifrato'});
    const st = ctx.storage();
    await uploadBytes(ref(st, `families/${LOCKED}/attachments/photo/a1`), Buffer.from('x'));
  });
});

after(async () => env && env.cleanup());

const as = (uid) => (uid ? env.authenticatedContext(uid) : env.unauthenticatedContext());

describe('chat chiusa', () => {
  it('i membri leggono e scrivono i messaggi', async () => {
    const db = as('alice').firestore();
    await assertSucceeds(getDoc(doc(db, `families/${LOCKED}/messages/m1`)));
    await assertSucceeds(setDoc(doc(db, `families/${LOCKED}/messages/m2`), {message: 'y'}));
    await assertSucceeds(getDoc(doc(db, `families/${LOCKED}`)));
  });

  it('un altro login non legge, non scrive, non cancella', async () => {
    const db = as('mallory').firestore();
    await assertFails(getDoc(doc(db, `families/${LOCKED}`)));
    await assertFails(getDoc(doc(db, `families/${LOCKED}/messages/m1`)));
    await assertFails(setDoc(doc(db, `families/${LOCKED}/messages/m2`), {message: 'falso'}));
    await assertFails(deleteDoc(doc(db, `families/${LOCKED}/messages/m1`)));
    await assertFails(setDoc(doc(db, `families/${LOCKED}/escrow/ua`), {payload: 'x'}));
    await assertFails(deleteDoc(doc(db, `families/${LOCKED}`)));
  });

  it('senza login non si entra', async () => {
    const db = as(null).firestore();
    await assertFails(getDoc(doc(db, `families/${LOCKED}/messages/m1`)));
  });

  it('nessuno può aggiungersi ai membri o riaprire la chat', async () => {
    await assertFails(updateDoc(doc(as('mallory').firestore(), `families/${LOCKED}`),
      {'member_uids.mallory': true}));
    await assertFails(updateDoc(doc(as('alice').firestore(), `families/${LOCKED}`),
      {'member_uids.mallory': true}));
    await assertFails(updateDoc(doc(as('alice').firestore(), `families/${LOCKED}`),
      {locked: false}));
    await assertSucceeds(updateDoc(doc(as('alice').firestore(), `families/${LOCKED}`),
      {couple_selfie_url: 'u'}));
  });

  it('Storage: solo i membri', async () => {
    const path_ = `families/${LOCKED}/attachments/photo/a1`;
    await assertSucceeds(getBytes(ref(as('bob').storage(), path_)));
    await assertFails(getBytes(ref(as('mallory').storage(), path_)));
    await assertFails(uploadBytes(ref(as('mallory').storage(), `families/${LOCKED}/attachments/photo/a2`), Buffer.from('x')));
    await assertSucceeds(uploadBytes(ref(as('alice').storage(), `families/${LOCKED}/attachments/photo/a2`), Buffer.from('x')));
  });
});

describe('chat vecchia (1.37), ancora aperta', () => {
  it('funziona come prima', async () => {
    const db = as('chiunque').firestore();
    await assertSucceeds(getDoc(doc(db, `families/${LEGACY}/messages/m1`)));
    await assertSucceeds(setDoc(doc(db, `families/${LEGACY}/messages/m2`), {message: 'y'}));
  });

  it('ma nessuno può scriverne i membri', async () => {
    await assertFails(updateDoc(doc(as('chiunque').firestore(), `families/${LEGACY}`),
      {member_uids: {chiunque: true}, locked: true}));
  });
});

describe('chat senza documento (com\'erano quelle della 1.37)', () => {
  it('durante la transizione funziona come prima', async () => {
    const db = as('chiunque').firestore();
    await assertSucceeds(getDoc(doc(db, 'families/nuova')));
    await assertSucceeds(setDoc(doc(db, 'families/nuova/messages/m1'), {message: 'x'}));
    await assertSucceeds(uploadBytes(ref(as('chiunque').storage(), 'families/nuova/attachments/photo/a1'), Buffer.from('x')));
  });

  it('un client non può crearla dichiarandosi membro', async () => {
    await assertFails(setDoc(doc(as('mallory').firestore(), 'families/nuova'),
      {member_uids: {mallory: true}, locked: true}));
  });
});

describe('recupero e abbinamento', () => {
  it('servono un login', async () => {
    await assertSucceeds(setDoc(doc(as('nuovo').firestore(), 'recovery_requests/r1'), {pub: 'x'}));
    await assertFails(setDoc(doc(as(null).firestore(), 'recovery_requests/r2'), {pub: 'x'}));
    await assertSucceeds(setDoc(doc(as('nuovo').firestore(), 'pairing_signals/s1'), {scanned: true}));
  });
});

// Fase finale: quando la 1.37 non è più in giro LEGACY_OPEN va a false.
// Stesse regole con quell'interruttore spento, su un progetto separato.
describe('dopo la transizione (LEGACY_OPEN = false)', () => {
  let fin;
  const closed = (file) => fs.readFileSync(path.join(ROOT, file), 'utf8')
    .replace(/return true; \/\/ LEGACY_OPEN/, 'return false; // LEGACY_OPEN');

  before(async () => {
    fin = await initializeTestEnvironment({
      projectId: 'demo-tuijo-final',
      firestore: {rules: closed('firestore.rules')},
      storage: {rules: closed('storage.rules')},
    });
    await fin.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'families/aperta/messages/m1'), {message: 'x'});
      await setDoc(doc(ctx.firestore(), 'families/mezza'), {member_uids: {alice: true}, uid_by_user: {ua: 'alice'}});
    });
  });
  after(async () => fin && fin.cleanup());

  it('le chat senza documento o non chiuse non sono più aperte', async () => {
    const db = fin.authenticatedContext('chiunque').firestore();
    await assertFails(getDoc(doc(db, 'families/aperta/messages/m1')));
    await assertFails(setDoc(doc(db, 'families/nuova/messages/m1'), {message: 'x'}));
    await assertFails(setDoc(doc(db, 'families/nuova'), {couple_selfie_url: 'u'}));
    await assertFails(getDoc(doc(db, 'families/mezza')));
  });

  it('il membro già entrato continua a lavorare mentre aspetta il partner', async () => {
    const db = fin.authenticatedContext('alice').firestore();
    await assertSucceeds(setDoc(doc(db, 'families/mezza/messages/m1'), {message: 'x'}));
  });
});
