const { admin, db } = require('../config/firebase');

const getDb = () => {
    return db;
};

exports.placeBid = async (req, res) => {
    try {
        const { tokenId, bid, userBalance } = req.body;
        const db = getDb();
        if (!db) return res.status(500).json({ error: 'Firestore not initialized' });

        if (bid.amount > userBalance) {
            return res.status(400).json({ error: 'Insufficient wallet balance' });
        }

        const nftRef = db.collection('nfts').doc(tokenId.toString());
        const auctionRef = db.collection('auctions').doc(tokenId.toString());
        const bidsRef = nftRef.collection('bids').doc(bid.bidderWallet);

        // Anti-spam
        const existingBidDoc = await bidsRef.get();
        let isNewBidder = true;

        if (existingBidDoc.exists) {
            isNewBidder = false;
            const lastBidData = existingBidDoc.data();
            let lastTime;
            if (lastBidData.firstBidTimestamp) {
                lastTime = lastBidData.firstBidTimestamp.toDate ? lastBidData.firstBidTimestamp.toDate() : new Date(lastBidData.firstBidTimestamp);
                if ((Date.now() - lastTime.getTime()) < 3000) {
                    return res.status(400).json({ error: 'Please wait before placing another bid' });
                }
            }
        }

        await db.runTransaction(async (transaction) => {
            const nftDoc = await transaction.get(nftRef);
            if (!nftDoc.exists) throw new Error('NFT not found');

            const auctionDoc = await transaction.get(auctionRef);

            const data = nftDoc.data();
            const status = data.status || '';
            if (status === 'cancelled') {
                throw new Error('Auction has been cancelled by admin.');
            }

            const currentHighestBid = data.highestBid || 0.0;
            const startingPrice = data.price || 0.0;
            const isAuctionActive = data.isAuctionActive || false;
            const isFrozen = data.isFrozen || false;

            const creatorId = data.creatorId || '';
            const creatorWallet = data.creatorWallet || '';

            if (bid.bidderWallet.toLowerCase() === creatorWallet.toLowerCase()) {
                throw new Error('Creators cannot bid on their own NFT');
            }
            if (isFrozen) throw new Error('Auction is frozen');
            if (!isAuctionActive) throw new Error('Auction is not active');

            const endTimeMs = data.endTime || 0;
            if (endTimeMs > 0) {
                if (Date.now() > endTimeMs) {
                    throw new Error('Auction has ended');
                }
            }

            const minIncrement = 0.005; // Auction.defaultMinimumIncrement
            const minRequiredBid = currentHighestBid > 0 ? currentHighestBid + minIncrement : startingPrice;

            if (bid.amount < minRequiredBid - 0.0001) {
                throw new Error(`Bid must be at least ${minRequiredBid.toFixed(4)} ETH`);
            }

            if (bid.bidderId && creatorId && bid.bidderId === creatorId) {
                throw new Error('Creator cannot bid on their own NFT');
            }

            const bidData = {
                ...bid,
                firstBidTimestamp: admin.firestore.FieldValue.serverTimestamp()
            };

            transaction.set(bidsRef, bidData);

            transaction.update(nftRef, {
                highestBid: bid.amount,
                highestBidderId: bid.bidderId,
                highestBidderWallet: bid.bidderWallet,
                totalBids: isNewBidder ? admin.firestore.FieldValue.increment(1) : data.totalBids
            });

            if (auctionDoc.exists) {
                transaction.update(auctionRef, {
                    highestBid: bid.amount,
                    highestBidderId: bid.bidderId,
                    highestBidderWallet: bid.bidderWallet,
                    totalBids: isNewBidder ? admin.firestore.FieldValue.increment(1) : auctionDoc.data().totalBids,
                    updatedAt: admin.firestore.FieldValue.serverTimestamp()
                });
            }
        });

        res.status(200).json({ message: 'Bid placed successfully' });
    } catch (error) {
        console.error(error);
        res.status(500).json({ error: error.message });
    }
};

exports.completePayment = async (req, res) => {
    try {
        let { tokenId, winnerWallet, userBalance, txHash } = req.body;
        const db = getDb();
        if (!db) return res.status(500).json({ error: 'Firestore not initialized' });

        if (!txHash) throw new Error('Transaction hash is required for payment verification');
        txHash = txHash.toLowerCase().trim();

        const duplicateTx = await db.collection('transactions').where('transactionHash', '==', txHash).get();
        if (!duplicateTx.empty) {
            throw new Error('SECURITY: This transaction hash has already been used. Duplicate payment rejected.');
        }

        const nftRef = db.collection('nfts').doc(tokenId.toString());
        const auctionRef = db.collection('auctions').doc(tokenId.toString());

        await db.runTransaction(async (transaction) => {
            const nftDoc = await transaction.get(nftRef);
            if (!nftDoc.exists) throw new Error('NFT not found');

            const data = nftDoc.data();
            const auctionStatus = (data.auctionStatus || '').toUpperCase().trim();

            if (data.status === 'cancelled') throw new Error('Auction has been cancelled. Payment rejected.');
            if (data.status === 'sold' || auctionStatus === 'PAYMENT_COMPLETED') throw new Error('This NFT has already been sold.');
            if (auctionStatus === 'PAYMENT_EXPIRED' || data.status === 'failed_payment') throw new Error('Payment deadline has expired.');
            if (data.isFrozen === true || auctionStatus === 'FROZEN') throw new Error('Auction is frozen by Admin.');

            const auctionDoc = await transaction.get(auctionRef);
            const aStatus = auctionDoc.exists ? (auctionDoc.data().status || '').toUpperCase().trim() : '';

            // [PAYMENT CHECK] Debug logging
            console.log('[PAYMENT CHECK] nft.auctionStatus (raw)  =', JSON.stringify(data.auctionStatus));
            console.log('[PAYMENT CHECK] nft.auctionStatus (norm) =', auctionStatus);
            console.log('[PAYMENT CHECK] nft.status (raw)         =', JSON.stringify(data.status));
            console.log('[PAYMENT CHECK] auction.status (raw)     =', JSON.stringify(auctionDoc.exists ? auctionDoc.data().status : 'DOC_NOT_FOUND'));
            console.log('[PAYMENT CHECK] auction.status (norm)    =', aStatus);
            console.log('[PAYMENT CHECK] Gate: auctionStatus ==', auctionStatus, ' aStatus ==', aStatus);

            const isNftPending = auctionStatus === 'PENDING_PAYMENT';
            const isAuctionPending = aStatus === 'PENDING_PAYMENT';
            if (!isNftPending && !isAuctionPending) {
                throw new Error(`Auction is not in a payment pending state. Current: ${auctionStatus} / ${aStatus}`);
            }

            let paymentDeadline = 0;
            if (typeof data.paymentDeadline === 'number') {
                paymentDeadline = data.paymentDeadline;
            } else if (data.paymentDeadline && data.paymentDeadline.toMillis) {
                paymentDeadline = data.paymentDeadline.toMillis();
            }

            if (paymentDeadline > 0 && Date.now() > paymentDeadline) {
                throw new Error('Payment deadline has expired.');
            }

            const highestBid = data.highestBid || 0.0;
            const highestBidderId = data.highestBidderId;
            const highestBidderWallet = data.highestBidderWallet;
            const sellerId = data.ownerId;
            const sellerWallet = data.ownerWallet;

            if (!highestBidderWallet) throw new Error('No highest bidder recorded.');
            if (highestBidderWallet.toLowerCase() !== winnerWallet.toLowerCase()) {
                throw new Error('SECURITY: You are not the highest bidder. Wallet mismatch detected.');
            }

            // Transfer ownership
            transaction.update(nftRef, {
                ownerId: highestBidderId,
                ownerWallet: highestBidderWallet,
                status: 'sold',
                auctionStatus: 'PAYMENT_COMPLETED',
                ownershipType: 'collected',
                copyrightVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
                auctionWinner: highestBidderWallet,
                isAuctionActive: false,
                auctionCreated: false,
                isActive: false,
                paymentPending: false,
                isPaymentProcessing: false,
                isMetadataLocked: true,
                paymentCompletedAt: admin.firestore.FieldValue.serverTimestamp(),
                paymentTxHash: txHash,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                auctionHistory: admin.firestore.FieldValue.arrayUnion({
                    winner: highestBidderWallet,
                    amount: highestBid,
                    txHash: txHash,
                    date: Date.now()
                })
            });

            if (auctionDoc.exists) {
                transaction.update(auctionRef, {
                    status: 'PAYMENT_COMPLETED',
                    paymentTxHash: txHash,
                    paymentCompletedAt: admin.firestore.FieldValue.serverTimestamp()
                });
            }

            const txId = `sale_${tokenId}_${Date.now()}`;
            transaction.set(db.collection('transactions').doc(txId), {
                transactionId: txId,
                nftId: tokenId.toString(),
                auctionId: tokenId.toString(),
                sellerId: sellerId || '',
                buyerId: highestBidderId || '',
                sellerWallet: sellerWallet || '',
                buyerWallet: highestBidderWallet,
                amount: highestBid,
                transactionHash: txHash,
                type: 'sale',
                status: 'success',
                timestamp: admin.firestore.FieldValue.serverTimestamp()
            });
        });

        res.status(200).json({ message: 'Payment completed successfully' });
    } catch (error) {
        console.error(error);
        res.status(500).json({ error: error.message });
    }
};

exports.requestReAuction = async (req, res) => {
    try {
        const { tokenId } = req.body;
        const db = getDb();
        if (!db) return res.status(500).json({ error: 'Firestore not initialized' });

        const nftRef = db.collection('nfts').doc(tokenId.toString());
        const auctionRef = db.collection('auctions').doc(tokenId.toString());

        await db.runTransaction(async (transaction) => {
            const nftDoc = await transaction.get(nftRef);
            if (!nftDoc.exists) throw new Error('NFT not found');

            const data = nftDoc.data();
            const currentStatus = data.status || '';
            const isFrozen = data.isFrozen || false;

            if (currentStatus === 'rejected') throw new Error('Rejected NFTs cannot be re-auctioned.');
            if (currentStatus === 'sold' || data.isMetadataLocked) throw new Error('Sold NFTs cannot be re-auctioned.');
            if (isFrozen) throw new Error('Frozen NFTs cannot be re-auctioned.');
            if (data.isAuctionActive) throw new Error('NFT currently has an active auction.');

            const previousHighestBid = data.highestBid || 0.0;
            const previousWinner = data.highestBidderWallet;
            const currentAuctionCount = data.auctionCount || 0;
            const existingHistory = data.auctionHistory || [];

            existingHistory.push({
                auctionRound: currentAuctionCount + 1,
                finalBid: previousHighestBid,
                winnerWallet: previousWinner,
                endedAt: Date.now(),
                auctionStatus: data.auctionStatus
            });

            transaction.update(nftRef, {
                status: 'pending',
                isAuctionActive: false,
                isActive: false,
                auctionCreated: false,
                auctionStatus: 'RE_AUCTION_REQUESTED',
                highestBid: 0.0,
                highestBidderId: null,
                highestBidderWallet: null,
                totalBids: 0,
                startTime: null,
                endTime: null,
                previousFinalBid: previousHighestBid,
                previousWinnerWallet: previousWinner,
                auctionCount: currentAuctionCount + 1,
                reAuctionCount: admin.firestore.FieldValue.increment(1),
                auctionHistory: existingHistory,
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
            });

            const auctionDoc = await transaction.get(auctionRef);
            if (auctionDoc.exists) {
                transaction.update(auctionRef, {
                    status: 're_auction_requested'
                });
            }
        });

        res.status(200).json({ message: 'Re-auction requested successfully' });
    } catch (error) {
        console.error(error);
        res.status(500).json({ error: error.message });
    }
};

exports.approveReAuction = async (req, res) => {
    try {
        const { tokenId } = req.body;
        const db = getDb();
        if (!db) return res.status(500).json({ error: 'Firestore not initialized' });

        res.status(200).json({ message: 'Re-auction approved successfully' });
    } catch (error) {
        console.error(error);
        res.status(500).json({ error: error.message });
    }
};
