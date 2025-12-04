// Database service - supporta sia Firestore che in-memory storage per sviluppo

const useFirestore = process.env.FIRESTORE_ENABLED === 'true';

let db, admin;

if (useFirestore) {
  console.log('🔥 Using Firestore database');
  admin = require('firebase-admin');

  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      projectId: process.env.GOOGLE_CLOUD_PROJECT_ID,
    });
  }

  db = admin.firestore();
} else {
  console.log('💾 Using in-memory database (development mode)');
  // In-memory database per sviluppo
  const inMemoryDB = {
    users: new Map(),
    messages: new Map(),
  };

  // Mock Firestore API per compatibilità
  db = {
    collection: (name) => ({
      doc: (id) => ({
        set: async (data) => {
          if (!inMemoryDB[name]) inMemoryDB[name] = new Map();
          inMemoryDB[name].set(id, data);
          return data;
        },
        get: async () => {
          const data = inMemoryDB[name]?.get(id);
          return {
            exists: !!data,
            data: () => data,
          };
        },
        update: async (updates) => {
          if (!inMemoryDB[name]) inMemoryDB[name] = new Map();
          const existing = inMemoryDB[name].get(id) || {};
          inMemoryDB[name].set(id, { ...existing, ...updates });
        },
      }),
      where: (field, op, value) => ({
        limit: (num) => ({
          get: async () => {
            const items = Array.from(inMemoryDB[name]?.values() || []);
            const filtered = items.filter(item => {
              if (op === '==') return item[field] === value;
              if (op === '!=') return item[field] !== value;
              return true;
            });
            return {
              empty: filtered.length === 0,
              docs: filtered.slice(0, num).map(data => ({ data: () => data })),
            };
          },
        }),
        get: async () => {
          const items = Array.from(inMemoryDB[name]?.values() || []);
          const filtered = items.filter(item => {
            if (op === '==') return item[field] === value;
            if (op === '!=') return item[field] !== value;
            return true;
          });
          return {
            empty: filtered.length === 0,
            docs: filtered.map(data => ({ data: () => data })),
          };
        },
      }),
      get: async () => {
        const items = Array.from(inMemoryDB[name]?.values() || []);
        return {
          empty: items.length === 0,
          docs: items.map(data => ({ data: () => data })),
        };
      },
    }),
  };

  // Mock admin per notifiche (opzionale)
  admin = {
    messaging: () => ({
      send: async (message) => {
        console.log('📱 [MOCK] Sending push notification:', message);
        return 'mock-message-id';
      },
      sendMulticast: async (message) => {
        console.log('📱 [MOCK] Sending multicast notification:', message);
        return { successCount: message.tokens.length, failureCount: 0 };
      },
    }),
  };
}

module.exports = { db, admin };
