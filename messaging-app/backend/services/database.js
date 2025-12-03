const admin = require('firebase-admin');

// Inizializza Firebase Admin SDK
const serviceAccount = process.env.GOOGLE_APPLICATION_CREDENTIALS;

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: process.env.GOOGLE_CLOUD_PROJECT_ID,
  });
}

const db = admin.firestore();

module.exports = { db, admin };
