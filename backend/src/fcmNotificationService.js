const { db, admin } = require('./config/firebase');

function startFCMNotificationListener() {
  console.log('🔔 FCM Notification Listener started (collectionGroup mode)...');

  db.collectionGroup('notifications')
    .where('isPushSent', '==', false)
    .onSnapshot(async (snapshot) => {
      for (const change of snapshot.docChanges()) {
        if (change.type !== 'added') continue;

        const notifDoc = change.doc;
        const notif = notifDoc.data();

        try {
          // Ambil wallet address dari path dokumen: users/{walletAddress}/notifications/{notifId}
          const walletAddress = notifDoc.ref.parent.parent.id;
          if (!walletAddress) {
            await notifDoc.ref.update({ isPushSent: true });
            continue;
          }

          const userDoc = await db.collection('users').doc(walletAddress).get();
          const fcmToken = userDoc.exists ? userDoc.data().fcmToken : null;

          if (!fcmToken) {
            // Tidak ada token, tandai sudah diproses agar tidak dicek ulang terus
            await notifDoc.ref.update({ isPushSent: true });
            continue;
          }

          await admin.messaging().send({
            token: fcmToken,
            notification: {
              title: notif.title || 'LEO NFT',
              body: notif.message || 'You have a new notification',
            },
            android: {
              priority: 'high',
              notification: {
                channelId: 'high_importance_channel',
                icon: 'ic_launcher',
                sound: 'default',
              },
            },
            data: {
              type: notif.type || 'info',
              route: notif.actionRoute || '/',
              notifId: notifDoc.id,
            },
          });

          await notifDoc.ref.update({ isPushSent: true });
          console.log(`✅ Push sent to ${walletAddress}: ${notif.title}`);

        } catch (err) {
          if (err.code === 'messaging/registration-token-not-registered') {
            const walletAddress = notifDoc.ref.parent.parent.id;
            if (walletAddress) {
              await db.collection('users').doc(walletAddress).update({ fcmToken: null });
            }
            await notifDoc.ref.update({ isPushSent: true });
            console.log(`⚠️ Invalid FCM token removed for ${walletAddress}`);
          } else {
            console.error(`❌ FCM send error:`, err.message);
            // Tetap tandai isPushSent true supaya tidak retry infinite loop untuk error permanen
            await notifDoc.ref.update({ isPushSent: true }).catch(() => {});
          }
        }
      }
    }, (error) => {
      console.error('❌ FCM Listener snapshot error:', error.message);
    });
}

module.exports = { startFCMNotificationListener };
