const admin = require('firebase-admin');
require('dotenv').config();

let serviceAccount;
let db;

try {
  if (process.env.FIREBASE_PROJECT_ID && process.env.FIREBASE_PRIVATE_KEY && process.env.FIREBASE_CLIENT_EMAIL) {
    admin.initializeApp({
      credential: admin.credential.cert({
        projectId: process.env.FIREBASE_PROJECT_ID,
        clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
        privateKey: process.env.FIREBASE_PRIVATE_KEY.replace(/\\n/g, '\n'),
      })
    });
    db = admin.firestore();
  } else {
    serviceAccount = require('../../firebase-admin.json');
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount)
    });
    db = admin.firestore();
  }
} catch (error) {
  console.error('Firebase admin initialization error:', error.message);
  console.log('Ensure firebase credentials are in .env or firebase-admin.json is placed in the backend root directory.');
}

module.exports = { admin, db };
