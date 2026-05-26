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

exports.getAllNFTs = async (req, res) => {
    try {
        const db = getDb();
        if(!db) return res.status(500).json({ error: 'Firestore not initialized' });

        const nftsSnapshot = await db.collection('nfts').get();
        const nfts = nftsSnapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));

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
