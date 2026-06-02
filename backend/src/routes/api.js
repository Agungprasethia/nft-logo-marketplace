const express = require('express');
const router = express.Router();
const auctionController = require('../controllers/auctionController');
const nftController = require('../controllers/nftController');

// Health Route
router.get('/health', (req, res) => {
  res.json({
    success: true,
    message: 'Backend running successfully'
  });
});

// Test Firestore
router.get('/test-firestore', nftController.testFirestore);

// NFT Routes
router.post('/nft/mint', nftController.mintNFT);
router.get('/nft/all', nftController.getAllNFTs);
router.get('/nft/:id', nftController.getNFTById);
router.get('/profile/my-creations/:wallet', nftController.getMyCreations);
router.get('/profile/my-collection/:wallet', nftController.getMyCollection);

// Auction Routes
router.post('/auction/placeBid', auctionController.placeBid);
router.post('/auction/completePayment', auctionController.completePayment);
router.post('/auction/requestReAuction', auctionController.requestReAuction);
router.post('/auction/approveReAuction', auctionController.approveReAuction);

module.exports = router;
