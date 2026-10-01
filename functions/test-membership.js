// node test-membership.js — controlli della firma usata da joinFamily
const assert = require('assert');
const crypto = require('crypto');
const m = require('./membership');

const pair = () => {
  const {publicKey, privateKey} = crypto.generateKeyPairSync('rsa', {modulusLength: 2048});
  return {pub: publicKey.export({type: 'spki', format: 'der'}).toString('base64'), privateKey};
};
const a = pair();
const b = pair();
const uid = 'anonUid123';
const now = Date.now();
const familyId = m.familyIdOf(a.pub, b.pub);
const sign = (who, text) => crypto.sign('sha256', Buffer.from(text), who.privateKey).toString('base64');

// firma giusta: entra
const ok = m.verifyJoin({publicKey: a.pub, partnerPublicKey: b.pub, timestamp: now,
  signature: sign(a, m.joinMessage(familyId, uid, now)), uid, now});
assert.strictEqual(ok.familyId, familyId);
assert.strictEqual(ok.userId, m.userIdOf(a.pub));
assert.strictEqual(m.familyIdOf(b.pub, a.pub), familyId);

const rejects = (args, status) => assert.throws(() => m.verifyJoin(args), (e) => e.status === status);
// firmata dall'altro telefono, ma presentata con la chiave di a
rejects({publicKey: a.pub, partnerPublicKey: b.pub, timestamp: now,
  signature: sign(b, m.joinMessage(familyId, uid, now)), uid, now}, 403);
// firma per un altro uid (replay da un altro login)
rejects({publicKey: a.pub, partnerPublicKey: b.pub, timestamp: now,
  signature: sign(a, m.joinMessage(familyId, 'otherUid', now)), uid, now}, 403);
// firma vecchia
const old = now - m.SIGNATURE_MAX_AGE_MS - 1000;
rejects({publicKey: a.pub, partnerPublicKey: b.pub, timestamp: old,
  signature: sign(a, m.joinMessage(familyId, uid, old)), uid, now}, 403);
// richiesta malformata
rejects({publicKey: a.pub, uid, now}, 400);
rejects({publicKey: 'not-a-key', partnerPublicKey: b.pub, timestamp: now, signature: 'x', uid, now}, 400);
// una firma fatta dall'app (Dart, EncryptionService.signSha256) si verifica qui
const fixture = require('./test-fixture-dart-signature.json');
const dartKey = crypto.createPublicKey({key: Buffer.from(fixture.publicKey, 'base64'), format: 'der', type: 'spki'});
assert.ok(crypto.verify('sha256', Buffer.from(fixture.message), dartKey, Buffer.from(fixture.signature, 'base64')));
console.log('membership: tutti i controlli passano');
