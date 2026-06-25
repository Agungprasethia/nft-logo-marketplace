const { db } = require('../config/firebase');

const getDb = () => {
    return db;
};

exports.testFirestore = async (req, res) => {
    try {
        const db = getDb();
        if(!db) return res.status(500).json({ error: 'Firestore not initialized' });

        const snapshot = await db.collection('nfts').limit(1).get();
        res.status(200).json({
            success: true,
            connected: true,
            foundDocs: snapshot.size
        });
    } catch (error) {
        console.error(error);
        res.status(500).json({ success: false, error: error.message });
    }
};

const convertTimestamps = (data) => {
    const result = { ...data };
    for (const [key, value] of Object.entries(result)) {
        if (value && typeof value === 'object' && value._seconds !== undefined) {
            result[key] = value.toDate().getTime(); // Convert to milliseconds
        }
    }
    return result;
};

exports.getAllNFTs = async (req, res) => {
    try {
        const db = getDb();
        if(!db) return res.status(500).json({ error: 'Firestore not initialized' });

        const nftsSnapshot = await db.collection('nfts').get();
        const nfts = nftsSnapshot.docs.map(doc => ({ id: doc.id, ...convertTimestamps(doc.data()) }));

        res.status(200).json(nfts);
    } catch (error) {
        console.error(error);
        res.status(500).json({ error: error.message });
    }
};

exports.getNFTById = async (req, res) => {
    try {
        const db = getDb();
        if(!db) return res.status(500).json({ error: 'Firestore not initialized' });

        const doc = await db.collection('nfts').doc(req.params.id).get();
        if (!doc.exists) {
            return res.status(404).json({ error: 'NFT not found' });
        }

        res.status(200).json({ id: doc.id, ...doc.data() });
    } catch (error) {
        console.error(error);
        res.status(500).json({ error: error.message });
    }
};

exports.getMyCreations = async (req, res) => {
    try {
        const db = getDb();
        if(!db) return res.status(500).json({ error: 'Firestore not initialized' });

        const wallet = req.params.wallet.toLowerCase();
        const nftsSnapshot = await db.collection('nfts')
            .where('creatorWallet', '==', wallet)
            .get();
        
        const nfts = nftsSnapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
        res.status(200).json(nfts);
    } catch (error) {
        console.error(error);
        res.status(500).json({ error: error.message });
    }
};

exports.getMyCollection = async (req, res) => {
    try {
        const db = getDb();
        if(!db) return res.status(500).json({ error: 'Firestore not initialized' });

        const wallet = req.params.wallet.toLowerCase();
        const nftsSnapshot = await db.collection('nfts')
            .where('ownerWallet', '==', wallet)
            .get();
        
        const nfts = nftsSnapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
        res.status(200).json(nfts);
    } catch (error) {
        console.error(error);
        res.status(500).json({ error: error.message });
    }
};

exports.mintNFT = async (req, res) => {
    try {
        const db = getDb();
        if(!db) return res.status(500).json({ error: 'Firestore not initialized' });

        const { tokenId, owner, logoName, logoUrl, createdAt, metadata } = req.body;
        
        if (tokenId === undefined || !owner || !logoName) {
            return res.status(400).json({ error: 'Missing required fields' });
        }

        const nftData = {
            tokenId: Number(tokenId),
            ownerWallet: owner.toLowerCase(),
            name: logoName,
            imageUrl: logoUrl || '',
            createdAt: createdAt || new Date().toISOString(),
            metadata: metadata || {},
            status: 'pending'
        };

        await db.collection('nfts').doc(tokenId.toString()).set(nftData, { merge: true });

        res.status(200).json({ success: true, message: 'NFT saved to Firestore successfully', data: nftData });
    } catch (error) {
        console.error(error);
        res.status(500).json({ success: false, error: error.message });
    }
};
