const cron = require('node-cron');
const admin = require('firebase-admin');

const getDb = () => {
    if (!admin.apps.length) return null;
    return admin.firestore();
};

const toMillis = (val) => {
    if (!val) return 0;
    if (typeof val === 'number') return val;
    if (val.toDate) return val.toDate().getTime(); // Firestore Timestamp
    if (val instanceof Date) return val.getTime();
    return 0;
};

const closeExpiredAuctions = async () => {
    const db = getDb();
    if (!db) return;

    try {
        console.log('Checking for expired auctions...');
        const now = Date.now();
        const activeAuctions = await db.collection('nfts')
            .where('isAuctionActive', '==', true)
            .get();

        if (activeAuctions.empty) return;

        const batch = db.batch();
        let updatedCount = 0;

        for (const doc of activeAuctions.docs) {
            const data = doc.data();
            const endTimeMs = toMillis(data.endTime);

            if (endTimeMs > 0 && now >= endTimeMs) {
                const highestBid = data.highestBid || 0;
                const auctionRef = db.collection('auctions').doc(doc.id);

                if (highestBid === 0 || !data.highestBidderWallet) {
                    // No bids -> EXPIRED_NO_BID
                    batch.update(doc.ref, {
                        auctionStatus: 'EXPIRED_NO_BID',
                        isAuctionActive: false,
                        isInAuction: false,
                        auctionWinner: '',
                        highestBid: 0,
                        highestBidderWallet: '',
                        paymentPending: false,
                        paymentExpired: false,
                        status: 'available',
                        updatedAt: admin.firestore.FieldValue.serverTimestamp()
                    });

                    batch.update(auctionRef, {
                        status: 'EXPIRED_NO_BID',
                        updatedAt: admin.firestore.FieldValue.serverTimestamp()
                    });
                } else {
                    // Has winner -> PAYMENT_PENDING (24 hours)
                    const paymentDeadline = now + (24 * 60 * 60 * 1000);
                    batch.update(doc.ref, {
                        auctionStatus: 'PAYMENT_PENDING',
                        isAuctionActive: false,
                        isInAuction: false,
                        auctionWinner: data.highestBidderWallet,
                        paymentPending: true,
                        paymentExpired: false,
                        paymentDeadline: paymentDeadline,
                        status: 'pending_payment',
                        updatedAt: admin.firestore.FieldValue.serverTimestamp()
                    });

                    batch.update(auctionRef, {
                        status: 'PAYMENT_PENDING',
                        auctionWinner: data.highestBidderWallet,
                        paymentDeadline: paymentDeadline,
                        updatedAt: admin.firestore.FieldValue.serverTimestamp()
                    });
                }
                updatedCount++;
            }
        }

        if (updatedCount > 0) {
            await batch.commit();
            console.log(`Closed ${updatedCount} expired auctions.`);
        }
    } catch (error) {
        console.error('Error closing expired auctions:', error);
    }
};

const expirePaymentDeadlines = async () => {
    const db = getDb();
    if (!db) return;

    try {
        console.log('Checking for expired payments...');
        const now = Date.now();
        const pendingPayments = await db.collection('nfts')
            .where('paymentPending', '==', true)
            .get();

        if (pendingPayments.empty) return;

        const batch = db.batch();
        let updatedCount = 0;

        for (const doc of pendingPayments.docs) {
            const data = doc.data();
            const paymentDeadline = data.paymentDeadline || 0;
            const isPaymentProcessing = data.isPaymentProcessing === true;

            if (paymentDeadline > 0 && now >= paymentDeadline && !isPaymentProcessing) {
                const auctionRef = db.collection('auctions').doc(doc.id);

                batch.update(doc.ref, {
                    paymentStatus: 'PAYMENT_EXPIRED',
                    paymentExpired: true,
                    paymentPending: false,
                    auctionStatus: 'PAYMENT_EXPIRED',
                    isAuctionActive: false,
                    isInAuction: false,
                    auctionWinner: '',
                    highestBidderWallet: '',
                    status: 'available',
                    updatedAt: admin.firestore.FieldValue.serverTimestamp()
                });

                batch.update(auctionRef, {
                    status: 'PAYMENT_EXPIRED',
                    paymentExpired: true,
                    updatedAt: admin.firestore.FieldValue.serverTimestamp()
                });
                updatedCount++;
            }
        }

        if (updatedCount > 0) {
            await batch.commit();
            console.log(`Expired ${updatedCount} pending payments.`);
        }
    } catch (error) {
        console.error('Error checking expired payments:', error);
    }
};

let isProcessing = false;

exports.startCronJobs = () => {
    // Run every minute
    cron.schedule('* * * * *', async () => {
        if (isProcessing) {
            console.log('Cron skipped: previous job still running');
            return;
        }

        try {
            isProcessing = true;
            await closeExpiredAuctions();
            await expirePaymentDeadlines();
        } catch (error) {
            console.error('Cron job error:', error);
        } finally {
            isProcessing = false;
        }
    });
    console.log('Cron jobs started');
};
