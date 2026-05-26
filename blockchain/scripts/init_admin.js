// Admin Account Initialization Script
// Run with: node scripts/init_admin.js
//
// This script promotes an existing user to admin in Firestore.
// The user must have already registered through the app.
//
// Usage:
//   node scripts/init_admin.js <user-email>
//
// Prerequisites:
//   npm install firebase-admin

const admin = require('firebase-admin');

// Initialize with default credentials (uses GOOGLE_APPLICATION_CREDENTIALS env var)
// Or download service account key from Firebase Console → Project Settings → Service Accounts
require('dotenv').config({ path: '../backend/.env' }); // load from backend env
let serviceAccount;

try {
  if (process.env.FIREBASE_PROJECT_ID && process.env.FIREBASE_PRIVATE_KEY && process.env.FIREBASE_CLIENT_EMAIL) {
    admin.initializeApp({
      credential: admin.credential.cert({
        projectId: process.env.FIREBASE_PROJECT_ID,
        clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
        privateKey: process.env.FIREBASE_PRIVATE_KEY.replace(/\\n/g, '\n'),
      })
    });
  } else {
    serviceAccount = require('../../service-account-key.json');
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      projectId: 'leo-nft-marketplace',
    });
  }
} catch (e) {
  // Fallback: use application default credentials
  admin.initializeApp({
    projectId: 'leo-nft-marketplace',
  });
}

const db = admin.firestore();

async function promoteToAdmin(email) {
  console.log(`\n🔍 Looking up user with email: ${email}`);
  
  // Find user by email
  const usersRef = db.collection('users');
  const snapshot = await usersRef.where('email', '==', email).limit(1).get();
  
  if (snapshot.empty) {
    console.error(`❌ No user found with email: ${email}`);
    console.log('\nAvailable users:');
    const allUsers = await usersRef.get();
    allUsers.forEach(doc => {
      const data = doc.data();
      console.log(`  - ${data.email} (${data.fullName}) [${data.role}] uid: ${doc.id}`);
    });
    process.exit(1);
  }

  const userDoc = snapshot.docs[0];
  const userData = userDoc.data();
  
  console.log(`📋 Found user: ${userData.fullName} (${userData.email})`);
  console.log(`   Current role: ${userData.role}`);
  console.log(`   UID: ${userDoc.id}`);

  if (userData.role === 'admin') {
    console.log(`✅ User is already an admin!`);
    process.exit(0);
  }

  // Promote to admin
  await usersRef.doc(userDoc.id).update({
    role: 'admin',
  });

  console.log(`\n✅ Successfully promoted ${userData.fullName} to admin!`);
  console.log(`\n📝 Next steps:`);
  console.log(`   1. User logs out and logs back in`);
  console.log(`   2. Open web browser → Admin Dashboard will appear`);
  console.log(`   3. Or reload the app if already logged in`);
}

// Parse command line args
const email = process.argv[2];
if (!email) {
  console.log('Usage: node scripts/init_admin.js <user-email>');
  console.log('Example: node scripts/init_admin.js admin@example.com');
  console.log('\nThis promotes an existing registered user to admin role.');
  
  // List all users if no email provided
  (async () => {
    try {
      const allUsers = await db.collection('users').get();
      if (allUsers.empty) {
        console.log('\n⚠️  No users registered yet. Register a user through the app first.');
      } else {
        console.log('\nRegistered users:');
        allUsers.forEach(doc => {
          const data = doc.data();
          console.log(`  - ${data.email || 'no-email'} (${data.fullName || 'unnamed'}) [${data.role || 'user'}]`);
        });
      }
    } catch (e) {
      console.log('\n⚠️  Could not connect to Firestore. Make sure you have credentials configured.');
      console.log('   Set GOOGLE_APPLICATION_CREDENTIALS env var or place service-account-key.json in project root.');
    }
    process.exit(0);
  })();
} else {
  promoteToAdmin(email).catch(err => {
    console.error('❌ Error:', err.message);
    process.exit(1);
  });
}
