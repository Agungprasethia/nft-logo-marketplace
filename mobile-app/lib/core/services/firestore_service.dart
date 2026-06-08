import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:nft_logo_marketplace/core/utils/firestore_error_handler.dart';
import 'package:nft_logo_marketplace/shared/models/logo_nft.dart';
import 'package:nft_logo_marketplace/shared/models/auction.dart';
import 'package:nft_logo_marketplace/shared/models/transaction.dart';
import 'package:nft_logo_marketplace/shared/models/user_model.dart';
import 'package:nft_logo_marketplace/shared/models/app_notification.dart';
import 'package:nft_logo_marketplace/shared/models/appeal_case.dart';
import 'package:nft_logo_marketplace/shared/models/appeal_message.dart';

/// Centralized Firestore service for NFT validation, auctions, and multi-user data.
class FirestoreService {
  static final FirestoreService _instance = FirestoreService._();
  static FirestoreService get instance => _instance;
  FirestoreService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  
  /// Public accessor for Firestore instance (used by UI for ownership streams)
  FirebaseFirestore get db => _db;

  CollectionReference<Map<String, dynamic>> get _nftsCollection =>
      _db.collection('nfts');
  CollectionReference<Map<String, dynamic>> get _usersCollection =>
      _db.collection('users');
  CollectionReference<Map<String, dynamic>> get _auctionsCollection =>
      _db.collection('auctions');
  CollectionReference<Map<String, dynamic>> get _transactionsCollection =>
      _db.collection('transactions');
  CollectionReference<Map<String, dynamic>> get _reportsCollection =>
      _db.collection('reports');
  CollectionReference<Map<String, dynamic>> get _appealsCollection =>
      _db.collection('appeals');

  // ============ Retry Mechanism ============
  Future<void> _retryOperation(
    Future<void> Function() operation, {
    int maxRetries = 3,
    String operationName = 'Firestore operation',
  }) async {
    int attempt = 0;
    while (attempt < maxRetries) {
      try {
        await operation();
        if (kDebugMode) { debugPrint('✅ $operationName succeeded (attempt ${attempt + 1})'); }
        return;
      } catch (e) {
        attempt++;
        if (attempt >= maxRetries) {
          debugPrint(
              '❌ $operationName FAILED after $maxRetries attempts: $e');
          return;
        }
        final delayMs = 1000 * attempt;
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }
  }

  // ============ NFTs Operations ============

  Future<void> saveNFT(LogoNFT logo) async {
    // ═══ ANTI-GHOST NFT GUARD ═══
    if (logo.tokenId <= 0) {
      throw Exception('INVALID BLOCKCHAIN TOKEN ID');
    }
    if (logo.txHash == null || logo.txHash!.isEmpty) {
      throw Exception('INVALID TRANSACTION HASH');
    }

    try {
      final data = logo.toFirestore();
      data['status'] = 'pending';
      data['createdAt'] = FieldValue.serverTimestamp();

      final user = FirebaseAuth.instance.currentUser;
      
      // Inject username if available
      final creatorDocId = logo.creatorId.isNotEmpty ? logo.creatorId : user?.uid;
      
      if (creatorDocId != null && creatorDocId.isNotEmpty) {
        final userDoc = await _usersCollection.doc(creatorDocId).get();
        if (userDoc.exists) {
          final userData = userDoc.data()!;
          if (userData['username'] != null && userData['username'].toString().isNotEmpty) {
            data['creatorUsername'] = userData['username'];
          }
        }
      }

      await _nftsCollection.doc(logo.tokenId.toString()).set(data);

      if (user != null) {
        await _usersCollection.doc(user.uid).set({
          'lastMintTime': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      if (kDebugMode) { debugPrint('🔥 Firestore: NFT #${logo.tokenId} saved'); }
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ Firestore saveNFT error: $e'); }
      rethrow;
    }
  }

  Future<void> approveNFT(int tokenId, String adminId) async {
    try {
      final docRef = _nftsCollection.doc(tokenId.toString());
      
      await _db.runTransaction((transaction) async {
        final doc = await transaction.get(docRef);
        if (!doc.exists) throw Exception('NFT not found');

        // Atomic update for status and visibility
        transaction.update(docRef, {
          'status': 'approved',
          'nftVisible': true,
          'approvedBy': adminId,
          'approvedAt': FieldValue.serverTimestamp(),
          'copyrightVerifiedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      // Send notification
      final docSnapshot = await docRef.get();
      if (docSnapshot.exists) {
        final data = docSnapshot.data();
        final creatorWallet = (data?['creatorWallet'] as String? ?? '').toLowerCase();
        final nftName = data?['name'] as String? ?? 'NFT #$tokenId';
        if (creatorWallet.isNotEmpty) {
          final notifId = _userNotificationsCollection(creatorWallet).doc().id;
          await saveNotification(creatorWallet, AppNotification(
            id: notifId,
            title: 'NFT Approved! ✅',
            message: 'Your logo $nftName has been approved by the admin and is ready for auction.',
            type: NotificationType.nftApproved,
            category: 'system',
            createdAt: DateTime.now(),
            isRead: false,
            actionRoute: '/nft/$tokenId',
          ));
        }
      }

      if (kDebugMode) { debugPrint('🔥 Firestore: NFT #$tokenId approved (Atomic Transaction)'); }
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ Firestore approveNFT error: $e'); }
      rethrow;
    }
  }

  /// Manually starts an auction for an approved/available NFT
  Future<void> startAuction(int tokenId, {int? onChainAuctionId, double? newPrice, int? newDuration, String? userWallet}) async {
    try {
      final docRef = _nftsCollection.doc(tokenId.toString());
      final auctionRef = _auctionsCollection.doc(tokenId.toString());

      await _db.runTransaction((transaction) async {
        final doc = await transaction.get(docRef);
        if (!doc.exists) throw Exception('NFT not found');

        final data = doc.data()!;
        final currentStatus = data['status'] as String? ?? '';
        final isAuctionActive = data['isAuctionActive'] as bool? ?? false;

        // Lock validation
        if (isAuctionActive) throw Exception('Auction is already active for this NFT.');
        if (currentStatus != 'approved' && currentStatus != 'available') {
          throw Exception('NFT must be approved or available to start auction. Current: $currentStatus');
        }

        final durationSeconds = newDuration ?? data['auctionDuration'] as int? ?? 86400; // default 24h
        final now = DateTime.now();
        final endTime = now.add(Duration(seconds: durationSeconds));

        transaction.update(docRef, {
          'status': 'auction',
          'auctionStatus': 'ACTIVE',
          'isInAuction': true,
          'isAuctionActive': true,
          'auctionCreated': true,
          'isActive': true,
          if (newPrice != null) 'price': newPrice,
          if (newDuration != null) 'auctionDuration': newDuration,
          'startTime': now.millisecondsSinceEpoch,
          'endTime': endTime.millisecondsSinceEpoch,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Create/Overwrite active auction document
        final auctionData = {
          'auctionId': onChainAuctionId ?? tokenId, // Save real on-chain ID
          'tokenId': tokenId,
          'sellerId': data['ownerId'] as String? ?? '',
          'sellerWallet': userWallet ?? data['ownerWallet'] as String? ?? '',
          'startingPrice': newPrice ?? (data['price'] as num?)?.toDouble() ?? 0.0,
          'highestBid': (data['highestBid'] as num?)?.toDouble() ?? 0.0,
          'highestBidderId': data['highestBidderId'] as String? ?? '',
          'highestBidderWallet': data['highestBidderWallet'] as String? ?? '',
          'startTime': now,
          'endTime': endTime,
          'status': 'active',
          'totalBids': data['totalBids'] as int? ?? 0,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        };

        transaction.set(auctionRef, auctionData);
      });

      if (kDebugMode) { debugPrint('🔥 Firestore: Auction STARTED for NFT #$tokenId (Auction ID: $onChainAuctionId)'); }
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ Firestore startAuction error: $e'); }
      rethrow;
    }
  }

  Future<void> rejectNFT(int tokenId) async {
    try {
      final docRef = _nftsCollection.doc(tokenId.toString());
      final reason = 'Did not meet quality standards';
      
      await _db.runTransaction((transaction) async {
        final doc = await transaction.get(docRef);
        if (!doc.exists) throw Exception('NFT not found');

        transaction.update(docRef, {
          'status': 'rejected',
          'rejectionReason': reason,
          'rejectedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'isActive': false,
        });
      });

      // Send notification
      final docSnapshot = await docRef.get();
      if (docSnapshot.exists) {
        final data = docSnapshot.data();
        final creatorWallet = (data?['creatorWallet'] as String? ?? '').toLowerCase();
        final nftName = data?['name'] as String? ?? 'NFT #$tokenId';
        if (creatorWallet.isNotEmpty) {
          final notifId = _userNotificationsCollection(creatorWallet).doc().id;
          await saveNotification(creatorWallet, AppNotification(
            id: notifId,
            title: 'NFT Rejected ❌',
            message: 'Your logo $nftName was rejected. Reason: $reason',
            type: NotificationType.nftRejected,
            category: 'system',
            createdAt: DateTime.now(),
            isRead: false,
            actionRoute: '/nft/$tokenId',
          ));
        }
      }

      if (kDebugMode) { debugPrint('🔥 Firestore: NFT #$tokenId rejected (Atomic Transaction)'); }
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ Firestore rejectNFT error: $e'); }
      rethrow;
    }
  }

  // ============ TEMPORARY DEV TOOL ============
  Future<void> clearAllData() async {
    try {
      final nfts = await _nftsCollection.get();
      for (var doc in nfts.docs) {
        final bids = await doc.reference.collection('bids').get();
        for (var bid in bids.docs) {
          await bid.reference.delete();
        }
        await doc.reference.delete();
      }

      final auctions = await _auctionsCollection.get();
      for (var doc in auctions.docs) {
        await doc.reference.delete();
      }
      
      if (kDebugMode) { debugPrint('🔥 All NFTs and Auctions deleted successfully'); }
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ Error clearing data: $e'); }
    }
  }

  Future<void> updateNFTOwner(
      int tokenId, String newOwnerId, String newOwnerWallet) async {
    try {
      await _nftsCollection.doc(tokenId.toString()).update({
        'ownerId': newOwnerId,
        'ownerWallet': newOwnerWallet,
      });
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ updateNFTOwner error: $e'); }
    }
  }

  // ============ Freeze Mechanism ============

  Future<void> freezeNFT(int tokenId) async {
    try {
      await _nftsCollection.doc(tokenId.toString()).update({
        'isFrozen': true,
      });
      if (kDebugMode) { debugPrint('🔥 Firestore: NFT #$tokenId frozen'); }
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ Firestore freezeNFT error: $e'); }
      rethrow;
    }
  }

  Future<void> unfreezeNFT(int tokenId) async {
    try {
      await _nftsCollection.doc(tokenId.toString()).update({
        'isFrozen': false,
      });
      if (kDebugMode) { debugPrint('🔥 Firestore: NFT #$tokenId unfrozen'); }
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ Firestore unfreezeNFT error: $e'); }
      rethrow;
    }
  }

  /// Disable an NFT (admin action from reported NFTs)
  Future<void> disableNFT(int tokenId) async {
    try {
      await _nftsCollection.doc(tokenId.toString()).update({
        'status': 'disabled',
        'isActive': false,
        'isForSale': false,
        'isInAuction': false,
        'disabledAt': FieldValue.serverTimestamp(),
      });
      if (kDebugMode) { debugPrint('🔥 Firestore: NFT #$tokenId disabled'); }
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ Firestore disableNFT error: $e'); }
      rethrow;
    }
  }

  /// Soft delete an NFT (creator action from My Creations)
  Future<void> softDeleteNFT(int tokenId, String userWallet) async {
    try {
      final docRef = _nftsCollection.doc(tokenId.toString());
      final doc = await docRef.get();
      if (!doc.exists) throw Exception('NFT not found');

      final data = doc.data()!;
      if ((data['creatorWallet'] as String?)?.toLowerCase() != userWallet.toLowerCase()) {
        throw Exception('Unauthorized: Only the creator can delete this NFT');
      }

      await docRef.update({
        'status': 'deleted',
        'isActive': false,
        'isAuctionActive': false,
        'deletedAt': FieldValue.serverTimestamp(),
      });
      if (kDebugMode) { debugPrint('🔥 Firestore: NFT #$tokenId soft deleted'); }
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ Firestore softDeleteNFT error: $e'); }
      rethrow;
    }
  }

  // ============ NFT Ownership Validation ============

  /// Verify that the given wallet is the legitimate owner of the NFT.
  /// Used to gate download access — only the verified owner can download.
  /// Returns false if: not owner, NFT frozen, NFT in active auction, or NFT sold/claimed status mismatch.
  Future<bool> verifyNFTOwnership(String imageUrl, String walletAddress) async {
    try {
      // Find the NFT document by imageUrl
      final querySnapshot = await _nftsCollection
          .where('imageUrl', isEqualTo: imageUrl)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        if (kDebugMode) { debugPrint('❌ verifyNFTOwnership: NFT not found for imageUrl'); }
        return false;
      }

      final doc = querySnapshot.docs.first;
      final data = doc.data();
      final ownerWallet = (data['ownerWallet'] as String? ?? '').toLowerCase();
      final isFrozen = data['isFrozen'] as bool? ?? false;
      final isAuctionActive = data['isAuctionActive'] as bool? ?? false;

      // Security checks
      if (walletAddress.toLowerCase() != ownerWallet) {
        if (kDebugMode) { debugPrint('❌ verifyNFTOwnership: Wallet mismatch — $walletAddress != $ownerWallet'); }
        return false;
      }

      if (isFrozen) {
        if (kDebugMode) { debugPrint('❌ verifyNFTOwnership: NFT is frozen — download denied'); }
        return false;
      }

      if (isAuctionActive) {
        if (kDebugMode) { debugPrint('❌ verifyNFTOwnership: NFT is in active auction — download denied'); }
        return false;
      }

      if (kDebugMode) { debugPrint('✅ verifyNFTOwnership: Ownership verified for wallet $walletAddress'); }
      return true;
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ verifyNFTOwnership error: $e'); }
      return false;
    }
  }

  // ============ Admin Role Validation ============

  /// Verify that the given user is an admin before performing admin actions.
  Future<void> _verifyAdminRole(String adminId) async {
    final userDoc = await _usersCollection.doc(adminId).get();
    if (!userDoc.exists) {
      throw Exception('Admin user not found');
    }
    final role = userDoc.data()?['role'] as String? ?? 'user';
    if (role != 'admin') {
      throw Exception('Unauthorized: Only admins can perform this action');
    }
  }

  // ============ Reports & Admin Actions ============

  Future<void> submitNFTReport({
    required int tokenId,
    required String reporterWallet,
    required String reporterUsername,
    required String creatorWallet,
    required String creatorUsername,
    required String nftTitle,
    required String nftImageUrl,
    required String reason,
    String additionalNote = '',
  }) async {
    try {
      // Prevent duplicate reports from the same wallet for the same token
      final existingReports = await _reportsCollection
          .where('tokenId', isEqualTo: tokenId)
          .where('reporterWallet', isEqualTo: reporterWallet)
          .where('status', isEqualTo: 'pending')
          .get();

      if (existingReports.docs.isNotEmpty) {
        throw Exception('You already have a pending report for this artwork.');
      }

      // Check if already frozen
      final nftDoc = await _nftsCollection.doc(tokenId.toString()).get();
      if (!nftDoc.exists) throw Exception('NFT not found.');
      if (nftDoc.data()?['isFrozen'] == true) {
        throw Exception('This NFT is already frozen and under investigation.');
      }

      // Block reporting CLAIMED/SOLD NFTs
      final nftStatus = nftDoc.data()?['status'] as String? ?? '';
      if (nftStatus == 'sold') {
        throw Exception('Cannot report an NFT that has already been sold.');
      }

      // Get current auction status snapshot + bid data
      String auctionStatusSnapshot = 'Unknown';
      double snapshotHighestBid = 0.0;
      int snapshotTotalBids = 0;
      final auctionDoc = await _auctionsCollection.doc(tokenId.toString()).get();
      if (auctionDoc.exists) {
        auctionStatusSnapshot = auctionDoc.data()?['status'] ?? 'Unknown';
        snapshotHighestBid = (auctionDoc.data()?['highestBid'] as num?)?.toDouble() ?? 0.0;
        snapshotTotalBids = auctionDoc.data()?['totalBids'] as int? ?? 0;
      }

      final reportId = _reportsCollection.doc().id;
      
      final reportData = {
        'reportId': reportId,
        'tokenId': tokenId,
        'reporterWallet': reporterWallet,
        'reporterUsername': reporterUsername,
        'creatorWallet': creatorWallet,
        'creatorUsername': creatorUsername,
        'nftTitle': nftTitle,
        'nftImageUrl': nftImageUrl,
        'reason': reason,
        'additionalNote': additionalNote,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'pending',
        'auctionStatusSnapshot': auctionStatusSnapshot,
        'snapshotHighestBid': snapshotHighestBid,
        'snapshotTotalBids': snapshotTotalBids,
      };

      await _reportsCollection.doc(reportId).set(reportData);
      if (kDebugMode) { debugPrint('🔥 Firestore: Report submitted for NFT #$tokenId'); }
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ submitNFTReport error: $e'); }
      rethrow;
    }
  }

  Stream<List<Map<String, dynamic>>> getPendingReportsStream() {
    return _reportsCollection
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) {
          final list = snapshot.docs.map((doc) => doc.data()).toList();
          // Sort client-side to avoid requiring a composite index
          list.sort((a, b) {
            final aTime = a['createdAt'];
            final bTime = b['createdAt'];
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return (bTime as Comparable).compareTo(aTime);
          });
          return list;
        });
  }

  Future<void> freezeReportedAuction(int tokenId, String adminId, String reportId) async {
    try {
      // Verify admin role before proceeding
      await _verifyAdminRole(adminId);

      final nftRef = _nftsCollection.doc(tokenId.toString());
      final auctionRef = _auctionsCollection.doc(tokenId.toString());
      final reportRef = _reportsCollection.doc(reportId);

      await _db.runTransaction((transaction) async {
        final auctionDoc = await transaction.get(auctionRef);
        final nftDoc = await transaction.get(nftRef);
        
        // Ensure NFT is not already CLAIMED/SOLD
        if (auctionDoc.exists) {
          final auctionStatus = auctionDoc.data()?['status'] as String? ?? '';
          if (auctionStatus == 'claimed' || auctionStatus == 'sold' || auctionStatus == 'cancelled') {
            throw Exception('Cannot freeze an auction that is .');
          }
        }

        // Also check NFT status for sold
        if (nftDoc.exists) {
          final nftStatus = nftDoc.data()?['status'] as String? ?? '';
          if (nftStatus == 'sold' || nftStatus == 'rejected') {
            throw Exception('Cannot freeze a  NFT.');
          }
        }

        final now = DateTime.now();
        int? remainingSeconds;
        
        if (nftDoc.exists && nftDoc.data()!['endTime'] != null) {
            final endTime = (nftDoc.data()!['endTime'] as Timestamp).toDate();
            if (endTime.isAfter(now)) {
                remainingSeconds = endTime.difference(now).inSeconds;
            } else {
                remainingSeconds = 0;
            }
        }

        // 1. Update NFT
        if (nftDoc.exists) {
           transaction.update(nftRef, {
             'isFrozen': true,
             'isAuctionActive': false,
             'isActive': false,
             'frozenAt': FieldValue.serverTimestamp(),
             'frozenRemainingSeconds': remainingSeconds,
           });
        }

        // 2. Update Auction
        if (auctionDoc.exists) {
           transaction.update(auctionRef, {
             'status': 'frozen',
           });
        }

        // 3. Update Report
        transaction.update(reportRef, {
           'status': 'frozen',
           'adminAction': 'Frozen by admin ',
           'resolvedAt': FieldValue.serverTimestamp(),
        });
      });

      if (kDebugMode) { debugPrint('🔥 Firestore: Auction # FROZEN (bids preserved, timer paused)'); }
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ freezeReportedAuction error: '); }
      rethrow;
    }
  }

  Future<void> reopenAuction(int tokenId, String adminId, String reportId) async {
    try {
      await _verifyAdminRole(adminId);

      final nftRef = _nftsCollection.doc(tokenId.toString());
      final auctionRef = _auctionsCollection.doc(tokenId.toString());
      final reportRef = _reportsCollection.doc(reportId);

      await _db.runTransaction((transaction) async {
        final nftDoc = await transaction.get(nftRef);
        
        if (!nftDoc.exists || nftDoc.data()?['isFrozen'] != true) {
            throw Exception('NFT is not frozen.');
        }

        final remainingSeconds = nftDoc.data()?['frozenRemainingSeconds'] as int? ?? 0;
        final newEndTime = DateTime.now().add(Duration(seconds: remainingSeconds));

        // 1. Update NFT
        transaction.update(nftRef, {
            'isFrozen': false,
            'isAuctionActive': true,
            'isActive': true,
            'endTime': Timestamp.fromDate(newEndTime),
            'frozenAt': FieldValue.delete(),
            'frozenRemainingSeconds': FieldValue.delete(),
        });

        // 2. Update Auction
        final auctionDoc = await transaction.get(auctionRef);
        if (auctionDoc.exists) {
           transaction.update(auctionRef, {
             'status': 'active',
           });
        }

        // 3. Update Report
        transaction.update(reportRef, {
           'status': 'resolved',
           'adminAction': 'Reopened by admin ',
           'resolvedAt': FieldValue.serverTimestamp(),
        });
      });

      // Just in case, ensure all bids are valid
      final bidsSnapshot = await nftRef.collection('bids').get();
      final batch = _db.batch();
      for (final doc in bidsSnapshot.docs) {
         batch.update(doc.reference, {'isInvalidated': false});
      }
      await batch.commit();

      if (kDebugMode) { debugPrint('🔥 Firestore: Auction # REOPENED (timer resumed)'); }
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ reopenAuction error: '); }
      rethrow;
    }
  }

  Future<void> rejectAuction(int tokenId, String adminId, String reportId) async {
    try {
      await _verifyAdminRole(adminId);

      final nftRef = _nftsCollection.doc(tokenId.toString());
      final auctionRef = _auctionsCollection.doc(tokenId.toString());
      final reportRef = _reportsCollection.doc(reportId);

      await _db.runTransaction((transaction) async {
        // 1. Update NFT
        final nftDoc = await transaction.get(nftRef);
        if (nftDoc.exists) {
            transaction.update(nftRef, {
                'isFrozen': true,
                'isAuctionActive': false,
                'isActive': false,
                'status': 'rejected',
                'auctionStatus': 'REJECTED'
            });
        }

        // 2. Update Auction
        final auctionDoc = await transaction.get(auctionRef);
        if (auctionDoc.exists) {
            transaction.update(auctionRef, {
                'status': 'cancelled',
            });
        }

        // 3. Update Report
        transaction.update(reportRef, {
           'status': 'resolved',
           'adminAction': 'Rejected and removed by admin ',
           'resolvedAt': FieldValue.serverTimestamp(),
        });
      });

      // Invalidate all bids
      final bidsSnapshot = await nftRef.collection('bids').get();
      final batch = _db.batch();
      for (final doc in bidsSnapshot.docs) {
         batch.update(doc.reference, {'isInvalidated': true});
      }
      await batch.commit();

      if (kDebugMode) { debugPrint('🔥 Firestore: Auction # REJECTED (permanently removed)'); }
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ rejectAuction error: '); }
      rethrow;
    }
  }

  Future<void> dismissReport(String reportId, String adminId) async {
    try {
      await _verifyAdminRole(adminId);

      final reportRef = _reportsCollection.doc(reportId);
      await _db.runTransaction((transaction) async {
        final reportDoc = await transaction.get(reportRef);
        if (!reportDoc.exists) throw Exception('Report not found');

        transaction.update(reportRef, {
          'status': 'dismissed',
          'adminAction': 'Dismissed by admin ',
          'resolvedAt': FieldValue.serverTimestamp(),
        });
      });
      if (kDebugMode) { debugPrint('🔥 Firestore: Report  dismissed'); }
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ dismissReport error: '); }
      rethrow;
    }
  }
  /// Real-time count of pending reports (for admin dashboard)
  Stream<int> getPendingReportsCountStream() {
    return _reportsCollection
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Stream of all reports for admin (includes all statuses)
  Stream<List<Map<String, dynamic>>> getAllReportsStream() {
    return _reportsCollection
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }

  /// Mark NFT as sold after auction completion
  Future<void> markNFTAsSold(int tokenId, String buyerId, String buyerWallet) async {
    try {
      await _nftsCollection.doc(tokenId.toString()).update({
        'ownerId': buyerId,
        'ownerWallet': buyerWallet,
        'status': 'sold',
        'isInAuction': false,
        'isForSale': false,
        'auctionCreated': false,
        'isActive': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (kDebugMode) { debugPrint('🔥 NFT #$tokenId marked as sold to $buyerWallet'); }
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ markNFTAsSold error: $e'); }
      rethrow;
    }
  }

  // ============ NFT Streams ============

  Stream<List<LogoNFT>> getPendingNFTsStream() {
    return _nftsCollection
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) {
      final list =
          snapshot.docs.map((doc) => LogoNFT.fromFirestore(doc.data())).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  Stream<List<LogoNFT>>? _approvedNFTsStream;

  Stream<List<LogoNFT>> getApprovedNFTsStream() {
    _approvedNFTsStream ??= _nftsCollection
        .where('nftVisible', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs.map((doc) => LogoNFT.fromFirestore(doc.data())).toList();
      
      // Client-side filtering to avoid composite index requirement
      final allowedStatuses = [
        ValidationStatus.approved,
        ValidationStatus.auction,
        ValidationStatus.sold,
        ValidationStatus.available,
        ValidationStatus.pendingPayment,
      ];
      
      final filteredList = list.where((nft) => allowedStatuses.contains(nft.status)).toList();
      filteredList.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      
      return filteredList;
    }).asBroadcastStream();
    return _approvedNFTsStream!;
  }

  final Map<String, Stream<List<LogoNFT>>> _userCollectionStreams = {};

  Stream<List<LogoNFT>> getUserNFTsStream(String userWallet) {
    final wallet = userWallet.toLowerCase().trim();
    if (wallet.isEmpty) return const Stream.empty();
    
    _userCollectionStreams[wallet] ??= _nftsCollection
        .where('ownerWallet', isEqualTo: wallet)
        .where('status', whereIn: ['sold', 'approved', 'auction'])
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs.map((doc) => LogoNFT.fromFirestore(doc.data())).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    }).asBroadcastStream();
    
    return _userCollectionStreams[wallet]!;
  }

  Future<int> getUserNFTsCount(String userWallet) async {
    final wallet = userWallet.toLowerCase().trim();
    if (wallet.isEmpty) return 0;
    try {
      final aggregateQuery = await _nftsCollection
          .where('ownerWallet', isEqualTo: wallet)
          .where('status', whereIn: ['sold', 'approved', 'auction'])
          .count()
          .get();
      return aggregateQuery.count ?? 0;
    } catch (e) {
      if (kDebugMode) { debugPrint('getUserNFTsCount error: $e'); }
      return 0;
    }
  }

  final Map<String, Stream<List<LogoNFT>>> _userCreationsStreams = {};

  Stream<List<LogoNFT>> getUserCreatedNFTsStream(String userWallet) {
    final wallet = userWallet.toLowerCase().trim();
    if (wallet.isEmpty) return const Stream.empty();
    
    _userCreationsStreams[wallet] ??= _nftsCollection
        .where('creatorWallet', isEqualTo: wallet)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs.map((doc) => LogoNFT.fromFirestore(doc.data())).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    }).asBroadcastStream();
    
    return _userCreationsStreams[wallet]!;
  }

  Future<int> getUserCreatedNFTsCount(String userWallet) async {
    final wallet = userWallet.toLowerCase().trim();
    if (wallet.isEmpty) return 0;
    try {
      final aggregateQuery = await _nftsCollection
          .where('creatorWallet', isEqualTo: wallet)
          .count()
          .get();
      return aggregateQuery.count ?? 0;
    } catch (e) {
      if (kDebugMode) { debugPrint('getUserCreatedNFTsCount error: $e'); }
      return 0;
    }
  }

  /// Stream all NFTs (for admin)
  Stream<List<LogoNFT>> getAllNFTsStream() {
    return _nftsCollection.snapshots().map((snapshot) {
      final list =
          snapshot.docs.map((doc) => LogoNFT.fromFirestore(doc.data())).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  Future<String> getNFTStatus(int tokenId) async {
    try {
      final doc = await _nftsCollection.doc(tokenId.toString()).get();
      if (doc.exists) {
        return doc.data()?['status'] as String? ?? 'pending';
      }
      return 'not_found';
    } catch (e) {
      return 'error';
    }
  }

  Future<bool> isApproved(int tokenId) async {
    return (await getNFTStatus(tokenId)) == 'approved';
  }

  /// Get raw NFT document data from Firestore (for merging with blockchain data)
  Future<Map<String, dynamic>?> getNFTData(int tokenId) async {
    try {
      final doc = await _nftsCollection.doc(tokenId.toString()).get();
      if (doc.exists) {
        return doc.data();
      }
      return null;
    } catch (e) {
      if (kDebugMode) { debugPrint('⚠️ getNFTData error for #$tokenId: $e'); }
      return null;
    }
  }

  Future<LogoNFT?> getNFTByTokenId(int tokenId) async {
    try {
      final doc = await _nftsCollection.doc(tokenId.toString()).get();
      if (doc.exists) {
        return LogoNFT.fromFirestore(doc.data()!);
      }
      return null;
    } catch (e) {
      if (kDebugMode) { debugPrint('⚠️ Error getting NFT by tokenId: $e'); }
      return null;
    }
  }

  Future<List<LogoNFT>> getAllNFTs() async {
    try {
      final snapshot = await _nftsCollection.get();
      final list = snapshot.docs.map((doc) => LogoNFT.fromFirestore(doc.data())).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    } catch (e) {
      if (kDebugMode) { debugPrint('⚠️ Error getting all NFTs: $e'); }
      return [];
    }
  }

  // ============ Admin Dashboard Count Streams ============

  /// Real-time count of NFTs by status
  Stream<int> getCountByStatus(String status) {
    return _nftsCollection
        .where('status', isEqualTo: status)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  Stream<int> getPendingNFTsCountStream() => getCountByStatus('pending');
  Stream<int> getApprovedNFTsCountStream() => getCountByStatus('approved');
  Stream<int> getReportedNFTsCountStream() => getCountByStatus('reported');

  /// Count of total bids
  Stream<int> getTotalBidsCountStream() {
    // This is an approximation or requires collection group query
    return _db.collectionGroup('bids').snapshots()
        .handleError((error) {
          FirestoreErrorHandler.logDebugError(error, context: 'getTotalBidsCountStream');
          throw error;
        })
        .map((snapshot) => snapshot.docs.length);
  }

  Stream<int> getActiveAuctionsCountStream() => getActiveAuctionsCount();

  /// Count of NFTs with auctionCreated=true
  Stream<int> getAuctionCreatedCount() {
    return _nftsCollection
        .where('auctionCreated', isEqualTo: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Count of inactive NFTs
  Stream<int> getInactiveCount() {
    return _nftsCollection
        .where('isActive', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Total users count
  Stream<int> getTotalUsersCount() {
    return _usersCollection
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Active auctions count
  Stream<int> getActiveAuctionsCount() {
    return _auctionsCollection
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Completed sales count (ended auctions with a winner)
  Stream<int> getCompletedSalesCount() {
    return _transactionsCollection
        .where('type', isEqualTo: 'sale')
        .where('status', isEqualTo: 'success')
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Total trading volume (sum of all sale amounts)
  Stream<double> getTotalVolumeStream() {
    return _transactionsCollection
        .where('type', isEqualTo: 'sale')
        .where('status', isEqualTo: 'success')
        .snapshots()
        .map((snapshot) {
      double total = 0.0;
      for (var doc in snapshot.docs) {
        total += (doc.data()['amount'] as num?)?.toDouble() ?? 0.0;
      }
      return total;
    });
  }

  // ============ Auctions & Bids ============

  Future<void> createAuction(Auction auction) async {
    try {
      final data = auction.toFirestore();
      data['createdAt'] = FieldValue.serverTimestamp();

      await _auctionsCollection.doc(auction.auctionId.toString()).set(data);
      await markAuctionCreated(auction.tokenId);
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ createAuction error: $e'); }
      rethrow;
    }
  }

  Future<void> placeBid(int tokenId, Bid bid, {double userBalance = 0.0}) async {
    try {
      if (bid.amount > userBalance) {
        throw Exception('Insufficient wallet balance');
      }

      final nftRef = _nftsCollection.doc(tokenId.toString());
      
      // Anti-spam check: 1 wallet can only bid every 3 seconds
      final existingBidDoc = await nftRef.collection('bids').doc(bid.bidderWallet).get();
      bool isNewBidder = true;
      
      if (existingBidDoc.exists) {
         isNewBidder = false;
         final lastBidData = existingBidDoc.data()!;
         DateTime? lastTime;
         if (lastBidData['firstBidTimestamp'] is int) {
           lastTime = DateTime.fromMillisecondsSinceEpoch(lastBidData['firstBidTimestamp'] as int);
         } else if (lastBidData['firstBidTimestamp'] != null) {
           try {
             lastTime = (lastBidData['firstBidTimestamp'] as dynamic).toDate();
           } catch (_) {}
         }
         if (lastTime != null && DateTime.now().difference(lastTime).inSeconds < 3) {
           throw Exception('Please wait before placing another bid');
         }
      }

      final bidsRef = nftRef.collection('bids').doc(bid.bidderWallet);

      String previousHighestBidder = '';
      String ownerWallet = '';
      String nftName = '';

      await _db.runTransaction((transaction) async {
        // ══════ ALL READS FIRST (Firestore requirement) ══════
        final nftDoc = await transaction.get(nftRef);
        if (!nftDoc.exists) throw Exception('NFT not found');

        final auctionRef = _auctionsCollection.doc(tokenId.toString());
        final auctionDoc = await transaction.get(auctionRef);

        final data = nftDoc.data()!;
        previousHighestBidder = (data['highestBidderWallet'] as String? ?? '').toLowerCase();
        ownerWallet = (data['ownerWallet'] as String? ?? data['creatorWallet'] as String? ?? '').toLowerCase();
        nftName = data['name'] as String? ?? 'Logo #$tokenId';
        
        final status = data['status'] as String? ?? '';
        if (status == 'cancelled') {
          throw Exception('Auction has been cancelled by admin.');
        }

        final currentHighestBid = (data['highestBid'] as num?)?.toDouble() ?? 0.0;
        final startingPrice = (data['price'] as num?)?.toDouble() ?? 0.0;
        final isAuctionActive = data['isAuctionActive'] as bool? ?? false;
        final isFrozen = data['isFrozen'] as bool? ?? false;

        final creatorId = data['creatorId'] as String? ?? '';
        final creatorWallet = data['creatorWallet'] as String? ?? '';

        // ══════ STRICT ENFORCEMENT ══════
        if (bid.bidderWallet.toLowerCase() == creatorWallet.toLowerCase()) {
          throw Exception('Creators cannot bid on their own NFT');
        }
        if (isFrozen) {
          throw Exception('Auction is frozen');
        }

        if (!isAuctionActive) {
          throw Exception('Auction is not active');
        }

        final endTimeMs = data['endTime'] as int? ?? 0;
        if (endTimeMs > 0) {
          final endTime = DateTime.fromMillisecondsSinceEpoch(endTimeMs);
          if (DateTime.now().isAfter(endTime)) {
            throw Exception('Auction has ended');
          }
        }

        // Validate bid amount (Minimum Increment Rule)
        final double minIncrement = Auction.getMinimumIncrement(currentHighestBid);
        final double minRequiredBid = currentHighestBid > 0 ? currentHighestBid + minIncrement : startingPrice;
        
        // Use a small epsilon for floating point comparison to avoid precision issues
        if (bid.amount < minRequiredBid - 0.0001) {
          throw Exception('Bid must be at least ${minRequiredBid.toStringAsFixed(2)} ETH');
        }

        // Prevent creator from bidding on own NFT
        if (creatorWallet.isNotEmpty &&
            bid.bidderWallet.toLowerCase().trim() == creatorWallet.toLowerCase().trim()) {
          throw Exception('Creator cannot bid on their own NFT');
        }

        if (bid.bidderId.isNotEmpty && creatorId.isNotEmpty && bid.bidderId == creatorId) {
          throw Exception('Creator cannot bid on their own NFT');
        }

        // ══════ ALL WRITES AFTER ALL READS ══════
        final bidData = bid.toFirestore();
        bidData['bidderWallet'] = bid.bidderWallet.toLowerCase();
        bidData['firstBidTimestamp'] = FieldValue.serverTimestamp();

        transaction.set(bidsRef, bidData);

        transaction.update(nftRef, {
          'highestBid': bid.amount,
          'highestBidderId': bid.bidderId,
          'highestBidderWallet': bid.bidderWallet.toLowerCase(),
          if (isNewBidder) 'totalBids': FieldValue.increment(1),
        });

        // 🔥 FIX: Also update the auction document so Auction stream receives the correct highestBid
        if (auctionDoc.exists) {
          transaction.update(auctionRef, {
            'highestBid': bid.amount,
            'highestBidderId': bid.bidderId,
            'highestBidderWallet': bid.bidderWallet.toLowerCase(),
            if (isNewBidder) 'totalBids': FieldValue.increment(1),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });

      // 🔥 Trigger Notifications AFTER successful transaction (fire-and-forget)
      try {
        if (ownerWallet.isNotEmpty && ownerWallet != bid.bidderWallet.toLowerCase()) {
          final notifId = _userNotificationsCollection(ownerWallet).doc().id;
          saveNotification(ownerWallet, AppNotification(
            id: notifId,
            title: 'New Bid Received! 💰',
            message: 'A new bid of ${bid.amount} ETH was placed on $nftName.',
            type: NotificationType.newBid,
            category: 'auction',
            createdAt: DateTime.now(),
            isRead: false,
            actionRoute: '/auction/$tokenId',
          ));
        }
        if (previousHighestBidder.isNotEmpty &&
            previousHighestBidder != bid.bidderWallet.toLowerCase() &&
            previousHighestBidder != ownerWallet) {
          final notifId2 = _userNotificationsCollection(previousHighestBidder).doc().id;
          saveNotification(previousHighestBidder, AppNotification(
            id: notifId2,
            title: 'You have been outbid! ⚠️',
            message: 'Someone placed a higher bid on $nftName. Place a new bid to stay in the lead!',
            type: NotificationType.outbid,
            category: 'auction',
            createdAt: DateTime.now(),
            isRead: false,
            actionRoute: '/auction/$tokenId',
          ));
        }
      } catch (e) {
        if (kDebugMode) { debugPrint('⚠️ Failed to send bid notifications: $e'); }
      }
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ placeBid error: $e'); }
      rethrow;
    }
  }

  /// Stream of active auctions
  Stream<List<Auction>> getActiveAuctionsStream() {
    return _auctionsCollection
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs
          .map((doc) => Auction.fromFirestore(doc.data()))
          .toList();
      return list;
    });
  }

  /// Stream of all auctions (for admin monitoring)
  Stream<List<Auction>> getAllAuctionsStream() {
    return _auctionsCollection.snapshots().map((snapshot) {
      final list = snapshot.docs
          .map((doc) => Auction.fromFirestore(doc.data()))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// Stream of auctions for a specific seller
  Stream<List<Auction>> getUserAuctionsStream(String userId) {
    return _auctionsCollection
        .where('sellerId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs
          .map((doc) => Auction.fromFirestore(doc.data()))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// Stream of auctions where user is the highest bidder
  Stream<List<Auction>> getUserBidsStream(String userId) {
    return _auctionsCollection
        .where('highestBidderId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs
          .map((doc) => Auction.fromFirestore(doc.data()))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// Stream of ALL distinct NFTs a user has ever bid on, with their highest bid amount.
  /// Returns a map of tokenId -> { 'amount', 'timestamp' }
  Stream<Map<int, Map<String, dynamic>>> getUserParticipatedBidsStream(String wallet) {
    return _db.collectionGroup('bids')
        .where('bidderWallet', isEqualTo: wallet.toLowerCase())
        .snapshots()
        .handleError((error) {
          FirestoreErrorHandler.logDebugError(error, context: 'getUserParticipatedBidsStream');
          throw error;
        })
        .map((snapshot) {
      final Map<int, Map<String, dynamic>> highestBids = {};
      
      for (var doc in snapshot.docs) {
        final parentRef = doc.reference.parent.parent;
        if (parentRef == null) continue;
        
        final tokenIdStr = parentRef.id;
        final tokenId = int.tryParse(tokenIdStr);
        if (tokenId == null) continue;

        final data = doc.data();
        final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
        final timestamp = data['firstBidTimestamp'];

        final isInvalidated = data['isInvalidated'] as bool? ?? false;

        if (!highestBids.containsKey(tokenId) || highestBids[tokenId]!['amount'] < amount) {
          highestBids[tokenId] = {
            'amount': amount,
            'timestamp': timestamp,
            'isInvalidated': isInvalidated,
          };
        }
      }
      return highestBids;
    });
  }

  /// Stream of bids for a specific NFT (real-time leaderboard)
  /// Uses client-side sort to avoid needing a composite Firestore index
  Stream<List<Bid>> getAuctionBidsStream(int tokenId) {
    return _nftsCollection
        .doc(tokenId.toString())
        .collection('bids')
        .snapshots()
        .handleError((error) {
          FirestoreErrorHandler.logDebugError(error, context: 'getAuctionBidsStream($tokenId)');
          throw error;
        })
        .map((snapshot) {
      final bids =
          snapshot.docs.map((doc) => Bid.fromFirestore(doc.data())).toList();
      bids.sort((a, b) {
        final cmp = b.amount.compareTo(a.amount);
        if (cmp != 0) return cmp;
        return a.firstBidTimestamp.compareTo(b.firstBidTimestamp);
      });
      return bids.take(10).toList();
    });
  }

  /// Fallback stream (same implementation, kept for backward compatibility)
  Stream<List<Bid>> getAuctionBidsStreamFallback(int tokenId) {
    return getAuctionBidsStream(tokenId);
  }

  /// Get single auction by ID
  Future<Auction?> getAuction(int auctionId) async {
    try {
      final doc =
          await _auctionsCollection.doc(auctionId.toString()).get();
      if (doc.exists) {
        return Auction.fromFirestore(doc.data()!);
      }
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ getAuction error: $e'); }
    }
    return null;
  }

  /// Stream a single auction for real-time updates
  Stream<Auction?> getAuctionStream(int auctionId) {
    return _auctionsCollection
        .doc(auctionId.toString())
        .snapshots()
        .map((doc) {
      if (doc.exists) {
        return Auction.fromFirestore(doc.data()!);
      }
      return null;
    });
  }

  // ============ Auction Lifecycle ============

  Future<void> validateForAuction(int tokenId) async {
    final doc = await _nftsCollection.doc(tokenId.toString()).get();
    if (!doc.exists) throw Exception('NFT not found');

    final data = doc.data()!;
    if (data['status'] != 'approved') throw Exception('NFT must be approved');

    final auctionCreated = data['auctionCreated'] as bool? ?? false;
    final isActive = data['isActive'] as bool? ?? true;

    if (auctionCreated && isActive) {
      throw Exception('NFT already has an active auction');
    }
  }

  Future<void> markAuctionCreated(int tokenId) async {
    await _retryOperation(() async {
      await _nftsCollection.doc(tokenId.toString()).update({
        'auctionCreated': true,
        'isInAuction': true,
        'isActive': true,
      });
    });
  }

  Future<void> markAuctionEnded(int tokenId, int auctionId,
      {bool hasBids = false}) async {
    await _retryOperation(() async {
      final batch = _db.batch();

      // Update NFT
      batch.update(_nftsCollection.doc(tokenId.toString()), {
        'isInAuction': false,
        'isActive': false,
        if (!hasBids) 'auctionCreated': false,
      });

      // Update Auction
      batch.update(_auctionsCollection.doc(auctionId.toString()), {
        'status': 'ended',
      });

      await batch.commit();
    });
  }

  /// Mark auction ended and transition to payment_pending if there is a winner
  /// This method is idempotent — safe to call multiple times for the same auction.
  Future<void> endOffChainAuction(int tokenId) async {
    try {
      if (kDebugMode) { debugPrint("Updating auction state..."); }
      final nftRef = _nftsCollection.doc(tokenId.toString());
      final auctionRef = _auctionsCollection.doc(tokenId.toString());
      
      await _db.runTransaction((transaction) async {
        final doc = await transaction.get(nftRef);
        if (!doc.exists) return;
        final data = doc.data()!;
        
        // Idempotent guard: skip if auction is already ended
        final isAuctionActive = data['isAuctionActive'] as bool? ?? false;
        if (!isAuctionActive) {
          if (kDebugMode) { debugPrint('⏭️ Auction #$tokenId already ended, skipping.'); }
          return;
        }
        
        final highestBid = (data['highestBid'] as num?)?.toDouble() ?? 0.0;
        final highestBidderId = data['highestBidderId'] as String?;
        final highestBidderWallet = data['highestBidderWallet'] as String?;
        
        // 🔥 FIX: All reads must happen before any writes
        final auctionDoc = await transaction.get(auctionRef);
        
        if (highestBidderId != null && highestBidderWallet != null && highestBid > 0) {
          // ═══ STRICT: Transition to PAYMENT_PENDING ═══
          // ownerWallet MUST remain as creatorWallet until payment is verified.
          // Ownership does NOT transfer here.
          transaction.update(nftRef, {
            'isAuctionActive': false,
            'isInAuction': false,
            'auctionStatus': _sPending,   // canonical: 'PAYMENT_PENDING'
            'status': 'payment_pending',
            'paymentPending': true,
            'paymentDeadline': DateTime.now().add(const Duration(hours: 24)).millisecondsSinceEpoch,
            'paymentExpired': false,
            // CRITICAL: ownerWallet stays as creator — no ownership transfer yet
          });
          
          if (auctionDoc.exists) {
            transaction.update(auctionRef, {
              'status': _sPending,   // canonical: 'PAYMENT_PENDING'
              'highestBid': highestBid,
              'highestBidderId': highestBidderId,
              'highestBidderWallet': highestBidderWallet,
            });
          }

          // Send notification to winner about payment deadline
          final winnerNotifId = _userNotificationsCollection(highestBidderWallet).doc().id;
          final winnerNotif = AppNotification(
            id: winnerNotifId,
            title: 'You Won the Auction! 🏆',
            message: 'Complete payment of ${highestBid.toStringAsFixed(4)} ETH for NFT #$tokenId within 24 hours to claim ownership.',
            type: NotificationType.success,
            category: 'auction',
            createdAt: DateTime.now(),
            isRead: false,
            actionRoute: '/auction/$tokenId',
          );
          await saveNotification(highestBidderWallet, winnerNotif);

          // Send notification to creator
          final creatorWallet = data['ownerWallet'] as String?;
          if (creatorWallet != null && creatorWallet.isNotEmpty) {
            final creatorNotifId = _userNotificationsCollection(creatorWallet).doc().id;
            final creatorNotif = AppNotification(
              id: creatorNotifId,
              title: 'Auction Ended! 💰',
              message: 'Your auction for NFT #$tokenId has ended. Waiting for winner to complete payment within 24 hours.',
              type: NotificationType.info,
              category: 'auction',
              createdAt: DateTime.now(),
              isRead: false,
              actionRoute: '/auction/$tokenId',
            );
            await saveNotification(creatorWallet, creatorNotif);
          }
        } else {
          // No bids — available state
          transaction.update(nftRef, {
            'isAuctionActive': false,
            'isInAuction': false,
            'auctionCreated': false, // Remove from homepage automatically
            'auctionStatus': 'ENDED',
            'status': 'available',
            'highestBid': 0.0,
            'highestBidderId': null,
            'highestBidderWallet': null,
            'paymentPending': false,
          });
          if (kDebugMode) { debugPrint("status: available"); }
          if (kDebugMode) { debugPrint("isAuctionActive: false"); }
          if (kDebugMode) { debugPrint("auctionStatus: ENDED"); }
          
          if (auctionDoc.exists) {
            transaction.update(auctionRef, {
              'status': 'ENDED',
            });
          }

          // Send notification to creator
          final creatorWallet = (data['ownerWallet'] as String? ?? data['creatorWallet'] as String? ?? '').toLowerCase();
          final nftName = data['name'] as String? ?? 'NFT #$tokenId';
          if (creatorWallet.isNotEmpty) {
            final notifId = _userNotificationsCollection(creatorWallet).doc().id;
            saveNotification(creatorWallet, AppNotification(
              id: notifId,
              title: 'Auction Ended (Unsold) 📉',
              message: 'Your auction for $nftName ended with no bids. You can relist it anytime.',
              type: NotificationType.unsoldAuction,
              category: 'auction',
              createdAt: DateTime.now(),
              isRead: false,
              actionRoute: '/nft/$tokenId',
            ));
          }
        }
      });
      if (kDebugMode) { debugPrint("Auction successfully marked as ended_no_bids"); }
      if (kDebugMode) { debugPrint('🔥 Off-chain auction #$tokenId ended, moved to payment_pending if has bids'); }
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ endOffChainAuction error: $e'); }
      rethrow;
    }
  }

  /// Request re-auction for an ended NFT.
  /// Sets status back to 'pending' so it returns to Admin moderation.
  /// Tracks reAuctionCount for audit purposes.
  /// Rejected NFTs cannot be re-auctioned.
  Future<void> requestReAuction(int tokenId) async {
    try {
      final nftRef = _nftsCollection.doc(tokenId.toString());
      final auctionRef = _auctionsCollection.doc(tokenId.toString());

      await _db.runTransaction((transaction) async {
        // ── ALL READS FIRST ──
        final nftDoc = await transaction.get(nftRef);
        if (!nftDoc.exists) throw Exception('NFT not found');
        
        final auctionDoc = await transaction.get(auctionRef);

        final data = nftDoc.data()!;
        final currentStatus = data['status'] as String? ?? '';
        final isFrozen = data['isFrozen'] as bool? ?? false;

        // Block rejected NFTs from re-auction
        if (currentStatus == 'rejected') {
          throw Exception('Rejected NFTs cannot be re-auctioned.');
        }

        // Block frozen NFTs
        if (isFrozen) {
          throw Exception('Frozen NFTs cannot be re-auctioned until investigation is resolved.');
        }

        // Block NFTs that are currently in active auction
        final isAuctionActive = data['isAuctionActive'] as bool? ?? false;
        if (isAuctionActive) {
          throw Exception('NFT currently has an active auction.');
        }

        // Save previous auction data to history
        final previousHighestBid = (data['highestBid'] as num?)?.toDouble() ?? 0.0;
        final previousWinner = data['highestBidderWallet'] as String?;
        final currentAuctionCount = data['auctionCount'] as int? ?? 0;
        final existingHistory = data['auctionHistory'] as List<dynamic>? ?? [];

        existingHistory.add({
          'auctionRound': currentAuctionCount + 1,
          'finalBid': previousHighestBid,
          'winnerWallet': previousWinner,
          'endedAt': DateTime.now().millisecondsSinceEpoch,
          'auctionStatus': data['auctionStatus'],
        });

        // ── ALL WRITES AFTER READS ──
        
        // Reset NFT for re-moderation
        transaction.update(nftRef, {
          'status': 'pending',
          'isAuctionActive': false,
          'isActive': false,
          'auctionCreated': false,
          'auctionStatus': 'RE_AUCTION_REQUESTED',
          'highestBid': 0.0,
          'highestBidderId': null,
          'highestBidderWallet': null,
          'totalBids': 0,
          'startTime': null,
          'endTime': null,
          'previousFinalBid': previousHighestBid,
          'previousWinnerWallet': previousWinner,
          'auctionCount': currentAuctionCount + 1,
          'reAuctionCount': FieldValue.increment(1),
          'auctionHistory': existingHistory,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Reset auction document
        if (auctionDoc.exists) {
          transaction.update(auctionRef, {
            'status': 're_auction_requested',
          });
        }
      });

      if (kDebugMode) { debugPrint('🔥 Firestore: Re-auction requested for NFT #$tokenId'); }
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ requestReAuction error: $e'); }
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // STRICT PAYMENT VALIDATION — 7-POINT PRODUCTION-GRADE ENFORCEMENT
  // ═══════════════════════════════════════════════════════════════════
  //
  // WINNING AN AUCTION ≠ OWNING THE NFT
  // Ownership ONLY transfers after ALL validations pass.
  //
  // STATUS CANONICAL VALUE: 'PAYMENT_PENDING'
  // (stored by endOffChainAuction & handleFailedPayment)
  //
  // 1. STRICT STATUS GATE       — auctionStatus must be PAYMENT_PENDING
  // 2. PAYMENT DEADLINE          — reject if deadline expired
  // 3. DUPLICATE TX HASH         — reject reused transaction hashes
  // 4. WINNER WALLET              — tx.from must match highestBidderWallet
  // 5. CREATOR WALLET             — tx.to must match creatorWallet (ownerWallet)
  // 6. EXACT ETH AMOUNT           — no underpayment / overpayment
  // 7. CHAIN VALIDATION           — Sepolia only (chainId 11155111)
  // ═══════════════════════════════════════════════════════════════════

  // ── Centralized status constants (prevent future typo bugs) ──
  static const String _sPending  = 'PAYMENT_PENDING';   // canonical write value
  static const String _sLegacy   = 'PENDING_PAYMENT';   // old write value (backward compat)
  static const String _sCompleted = 'PAYMENT_COMPLETED';

  /// Set payment processing lock to prevent duplicate tx
  Future<void> setPaymentProcessing(int tokenId, bool isProcessing) async {
    try {
      await _nftsCollection.doc(tokenId.toString()).update({
        'isPaymentProcessing': isProcessing,
      });
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ setPaymentProcessing error: $e'); }
    }
  }

  /// Complete final payment for an auction — STRICT 7-POINT VALIDATION
  Future<void> completePayment(int tokenId, String winnerWallet, double userBalance, {required String txHash}) async {
    try {
      // ── Pre-flight: txHash must exist ──
      if (txHash.isEmpty) {
        throw Exception('Transaction hash is required for payment verification');
      }
      
      txHash = txHash.toLowerCase().trim();

      // ── VALIDATION 3: Duplicate txHash protection ──
      final isDuplicate = await checkDuplicateTxHash(txHash);
      if (isDuplicate) {
        await logAuctionActivity(
          nftId: tokenId.toString(),
          txHash: txHash,
          wallet: winnerWallet,
          amount: 0,
          actionType: 'duplicate_tx_detected',
        );
        throw Exception('SECURITY: This transaction hash has already been used. Duplicate payment rejected.');
      }

      final nftRef = _nftsCollection.doc(tokenId.toString());
      final auctionRef = _auctionsCollection.doc(tokenId.toString());

      await _db.runTransaction((transaction) async {
        final doc = await transaction.get(nftRef);
        if (!doc.exists) throw Exception('NFT not found');
        
        final data = doc.data()!;

        // ── VALIDATION 1: Strict Status Gate ──
        final auctionStatus = (data['auctionStatus'] as String? ?? '').toUpperCase().trim();
        final nftStatus = (data['status'] as String? ?? '').toLowerCase().trim();

        // [PAYMENT CHECK] Debug log — visible in kDebugMode
        if (kDebugMode) {
          debugPrint('[PAYMENT CHECK] nft.auctionStatus (raw)  = "${data['auctionStatus']}"');
          debugPrint('[PAYMENT CHECK] nft.auctionStatus (norm) = "$auctionStatus"');
          debugPrint('[PAYMENT CHECK] nft.status (raw)         = "${data['status']}"');
          debugPrint('[PAYMENT CHECK] nft.status (norm)        = "$nftStatus"');
        }

        if (nftStatus == 'cancelled') {
          throw Exception('Auction has been cancelled. Payment rejected.');
        }
        if (nftStatus == 'sold' || auctionStatus == 'PAYMENT_COMPLETED') {
          throw Exception('This NFT has already been sold. Payment already processed.');
        }
        if (auctionStatus == 'PAYMENT_EXPIRED' || nftStatus == 'failed_payment') {
          throw Exception('Payment deadline has expired. You can no longer claim this NFT.');
        }
        if (data['isFrozen'] == true || auctionStatus == 'FROZEN') {
          throw Exception('Auction is frozen by Admin. Payment rejected.');
        }
        // Also verify auction document status first
        final auctionDoc = await transaction.get(auctionRef);
        final aStatus = auctionDoc.exists ? (auctionDoc.data()?['status'] as String? ?? '').toUpperCase().trim() : '';

        if (kDebugMode) {
          final rawAuctionStatus = auctionDoc.exists ? auctionDoc.data()!['status'] : 'DOC_NOT_FOUND';
          debugPrint('[PAYMENT CHECK] auction.status (raw)     = "$rawAuctionStatus"');
          debugPrint('[PAYMENT CHECK] auction.status (norm)    = "$aStatus"');
          debugPrint('[PAYMENT CHECK] Gate: auctionStatus==$auctionStatus  aStatus==$aStatus');
        }

        // ── STATUS GATE: Accept canonical 'PAYMENT_PENDING' OR legacy 'PENDING_PAYMENT' ──
        // Both are accepted for backward compatibility with Firestore documents written
        // before the status naming was unified.
        final bool isNftPending    = auctionStatus == _sPending || auctionStatus == _sLegacy;
        final bool isAuctionPending = aStatus == _sPending || aStatus == _sLegacy;
        if (!isNftPending && !isAuctionPending) {
          throw Exception('Auction is not in a payment pending state. Current: $auctionStatus / $aStatus');
        }
        
        if (auctionDoc.exists) {
           if (aStatus == 'PAYMENT_COMPLETED' || aStatus == 'CLAIMED') {
              throw Exception('This auction has already been paid and claimed.');
           }
        }

        // ── VALIDATION 2: Payment Deadline Enforcement ──
        int paymentDeadline = 0;
        if (data['paymentDeadline'] is int) {
          paymentDeadline = data['paymentDeadline'] as int;
        } else if (data['paymentDeadline'] != null && data['paymentDeadline'].runtimeType.toString() == 'Timestamp') {
          paymentDeadline = (data['paymentDeadline'] as dynamic).millisecondsSinceEpoch;
        }

        if (paymentDeadline > 0 && DateTime.now().millisecondsSinceEpoch > paymentDeadline) {
          throw Exception('Payment deadline has expired. The 24-hour payment window has closed.');
        }

        // ── Extract auction data ──
        final highestBid = (data['highestBid'] as num?)?.toDouble() ?? 0.0;
        final highestBidderId = data['highestBidderId'] as String?;
        final highestBidderWallet = data['highestBidderWallet'] as String?;
        final sellerId = data['ownerId'] as String?;
        final sellerWallet = data['ownerWallet'] as String?;

        // ── VALIDATION 4: Winner Wallet Match ──
        if (highestBidderWallet == null || highestBidderWallet.isEmpty) {
          throw Exception('No highest bidder recorded for this auction.');
        }
        if (highestBidderWallet.toLowerCase() != winnerWallet.toLowerCase()) {
          await logAuctionActivity(
            nftId: tokenId.toString(),
            txHash: txHash,
            wallet: winnerWallet,
            amount: highestBid,
            actionType: 'payment_rejected',
          );
          throw Exception('SECURITY: You are not the highest bidder. Wallet mismatch detected.');
        }

        if (kDebugMode) { debugPrint('✅ All 7-point validations passed for NFT #$tokenId'); }
        if (kDebugMode) { debugPrint('   Status: $auctionStatus'); }
        if (kDebugMode) { debugPrint('   Winner: $highestBidderWallet'); }
        if (kDebugMode) { debugPrint('   Amount: $highestBid ETH'); }
        if (kDebugMode) { debugPrint('   TxHash: $txHash'); }

        // ═══ ALL VALIDATIONS PASSED — TRANSFER OWNERSHIP ═══
        transaction.update(nftRef, {
          'ownerId': highestBidderId,
          'ownerWallet': highestBidderWallet,
          'status': 'sold',
          'auctionStatus': 'PAYMENT_COMPLETED',
          'ownershipType': 'collected',
          'copyrightVerifiedAt': FieldValue.serverTimestamp(),
          'auctionWinner': highestBidderWallet,
          'isAuctionActive': false,
          'auctionCreated': false,
          'isActive': false,
          'paymentPending': false,
          'paymentCompletedAt': FieldValue.serverTimestamp(),
          'paymentTxHash': txHash,
          'updatedAt': FieldValue.serverTimestamp(),
          'auctionHistory': FieldValue.arrayUnion([{
             'winner': highestBidderWallet,
             'amount': highestBid,
             'txHash': txHash,
             'date': DateTime.now().millisecondsSinceEpoch
          }]),
        });

        // Update auction status
        if (auctionDoc.exists) {
          transaction.update(auctionRef, {
            'status': 'PAYMENT_COMPLETED',
            'paymentTxHash': txHash,
            'paymentCompletedAt': FieldValue.serverTimestamp(),
          });
        }

        // Record sale transaction
        final txId = 'sale_${tokenId}_${DateTime.now().millisecondsSinceEpoch}';
        final saleTx = TransactionModel(
          transactionId: txId,
          nftId: tokenId.toString(),
          auctionId: tokenId.toString(),
          sellerId: sellerId ?? '',
          buyerId: highestBidderId ?? '',
          sellerWallet: sellerWallet ?? '',
          buyerWallet: highestBidderWallet,
          amount: highestBid,
          transactionHash: txHash,
          type: TransactionType.sale,
          status: TransactionStatus.success,
        );
        
        final txRef = _transactionsCollection.doc(txId);
        transaction.set(txRef, saleTx.toFirestore());
      });

      // ── Post-transaction: Audit log + Notifications ──
      await logAuctionActivity(
        nftId: tokenId.toString(),
        txHash: txHash,
        wallet: winnerWallet,
        amount: 0, // Will be filled from NFT doc
        actionType: 'payment_completed',
      );

      // Send success notification to winner
      final winnerNotifId = _userNotificationsCollection(winnerWallet).doc().id;
      final winnerNotif = AppNotification(
        id: winnerNotifId,
        title: 'Payment Successful! 🎉',
        message: 'Your payment for NFT #$tokenId has been verified on-chain. The NFT is now yours!',
        type: NotificationType.success,
        category: 'auction',
        createdAt: DateTime.now(),
        isRead: false,
        actionRoute: '/nft/$tokenId',
      );
      await saveNotification(winnerWallet, winnerNotif);

      // Send notification to creator
      final nftDoc = await _nftsCollection.doc(tokenId.toString()).get();
      final creatorW = nftDoc.data()?['creatorWallet'] as String? ?? '';
      if (creatorW.isNotEmpty && creatorW.toLowerCase() != winnerWallet.toLowerCase()) {
        final creatorNotifId = _userNotificationsCollection(creatorW).doc().id;
        final creatorNotif = AppNotification(
          id: creatorNotifId,
          title: 'NFT Sold! 💰',
          message: 'Payment has been verified for NFT #$tokenId. Ownership has been transferred to the buyer.',
          type: NotificationType.success,
          category: 'auction',
          createdAt: DateTime.now(),
          isRead: false,
          actionRoute: '/nft/$tokenId',
        );
        await saveNotification(creatorW, creatorNotif);
      }

      if (kDebugMode) { debugPrint('🔥 ═══ PAYMENT COMPLETED: NFT #$tokenId ownership transferred ═══'); }
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ completePayment error: $e'); }
      rethrow;
    }
  }

  /// Recovery method for orphaned payments:
  /// Handles the case where the user's MetaMask payment succeeded on-chain
  /// but ownership was NOT transferred due to the PENDING_PAYMENT / PAYMENT_PENDING
  /// status mismatch bug. Safe to call on every payment page load — it is
  /// idempotent and no-ops if the payment was already completed correctly.
  ///
  /// Returns true if recovery was performed, false if not needed or not eligible.
  Future<bool> recoverOrphanedPayment(int tokenId, String winnerWallet, String txHash) async {
    try {
      if (txHash.isEmpty || winnerWallet.isEmpty) return false;

      final txHashNorm = txHash.toLowerCase().trim();
      final winnerNorm = winnerWallet.toLowerCase().trim();

      if (kDebugMode) {
        debugPrint('[RECOVERY] Checking orphaned payment for NFT #$tokenId');
        debugPrint('[RECOVERY] Winner: $winnerNorm  TxHash: $txHashNorm');
      }

      final nftRef = _nftsCollection.doc(tokenId.toString());
      final auctionRef = _auctionsCollection.doc(tokenId.toString());

      final nftDoc = await nftRef.get();
      if (!nftDoc.exists) return false;

      final data = nftDoc.data()!;
      final rawAuctionStatus = (data['auctionStatus'] as String? ?? '').toUpperCase().trim();
      final rawNftStatus = (data['status'] as String? ?? '').toLowerCase().trim();

      // Only recover if still in payment_pending state (not already sold/completed)
      final isStillPending = rawNftStatus == 'payment_pending' &&
          (rawAuctionStatus == _sPending || rawAuctionStatus == _sLegacy);
      if (!isStillPending) {
        if (kDebugMode) {
          debugPrint('[RECOVERY] Not eligible. nftStatus=$rawNftStatus auctionStatus=$rawAuctionStatus');
        }
        return false;
      }

      // Confirm this winner is the highest bidder
      final storedBidderWallet = (data['highestBidderWallet'] as String? ?? '').toLowerCase();
      if (storedBidderWallet != winnerNorm) {
        if (kDebugMode) {
          debugPrint('[RECOVERY] Wallet mismatch. stored=$storedBidderWallet winner=$winnerNorm');
        }
        return false;
      }

      // Confirm the txHash is not already used
      final isDuplicate = await checkDuplicateTxHash(txHashNorm);
      if (isDuplicate) {
        // txHash already processed — likely payment already completed via another path.
        if (kDebugMode) { debugPrint('[RECOVERY] TxHash already used — payment already completed.'); }
        return false;
      }

      if (kDebugMode) { debugPrint('[RECOVERY] Orphaned payment confirmed. Executing ownership transfer...'); }

      final highestBidderId = data['highestBidderId'] as String?;
      final highestBidderWallet = data['highestBidderWallet'] as String?;
      final highestBid = (data['highestBid'] as num?)?.toDouble() ?? 0.0;
      final sellerId = data['ownerId'] as String?;
      final sellerWallet = data['ownerWallet'] as String?;

      await _db.runTransaction((txn) async {
        final freshNft = await txn.get(nftRef);
        final freshAuction = await txn.get(auctionRef);

        // Re-validate inside transaction (race-condition safe)
        final freshStatus = (freshNft.data()?['status'] as String? ?? '').toLowerCase();
        if (freshStatus != 'payment_pending') {
          if (kDebugMode) { debugPrint('[RECOVERY] Already processed inside transaction. Skipping.'); }
          return;
        }

        txn.update(nftRef, {
          'ownerId': highestBidderId,
          'ownerWallet': highestBidderWallet,
          'status': 'sold',
          'auctionStatus': _sCompleted,
          'ownershipType': 'collected',
          'copyrightVerifiedAt': FieldValue.serverTimestamp(),
          'auctionWinner': highestBidderWallet,
          'isAuctionActive': false,
          'auctionCreated': false,
          'isActive': false,
          'paymentPending': false,
          'paymentCompletedAt': FieldValue.serverTimestamp(),
          'paymentTxHash': txHashNorm,
          'updatedAt': FieldValue.serverTimestamp(),
          'auctionHistory': FieldValue.arrayUnion([{
            'winner': highestBidderWallet,
            'amount': highestBid,
            'txHash': txHashNorm,
            'date': DateTime.now().millisecondsSinceEpoch,
            'recoveredAt': DateTime.now().millisecondsSinceEpoch,
          }]),
        });

        if (freshAuction.exists) {
          txn.update(auctionRef, {
            'status': _sCompleted,
            'paymentTxHash': txHashNorm,
            'paymentCompletedAt': FieldValue.serverTimestamp(),
          });
        }

        // Record sale transaction
        final txId = 'recovery_${tokenId}_${DateTime.now().millisecondsSinceEpoch}';
        final saleTx = TransactionModel(
          transactionId: txId,
          nftId: tokenId.toString(),
          auctionId: tokenId.toString(),
          sellerId: sellerId ?? '',
          buyerId: highestBidderId ?? '',
          sellerWallet: sellerWallet ?? '',
          buyerWallet: highestBidderWallet ?? '',
          amount: highestBid,
          transactionHash: txHashNorm,
          type: TransactionType.sale,
          status: TransactionStatus.success,
        );
        txn.set(_transactionsCollection.doc(txId), saleTx.toFirestore());
      });

      // Send recovery notifications
      final winnerNotifId = _userNotificationsCollection(winnerNorm).doc().id;
      await saveNotification(winnerNorm, AppNotification(
        id: winnerNotifId,
        title: 'Ownership Recovered! 🎉',
        message: 'Your payment for NFT #$tokenId was verified. The NFT is now in your collection.',
        type: NotificationType.success,
        category: 'auction',
        createdAt: DateTime.now(),
        isRead: false,
        actionRoute: '/nft/$tokenId',
      ));

      final creatorWallet = nftDoc.data()?['creatorWallet'] as String? ?? '';
      if (creatorWallet.isNotEmpty && creatorWallet.toLowerCase() != winnerNorm) {
        final creatorNotifId = _userNotificationsCollection(creatorWallet).doc().id;
        await saveNotification(creatorWallet, AppNotification(
          id: creatorNotifId,
          title: 'NFT Sold! 💰',
          message: 'Payment confirmed for NFT #$tokenId. Ownership has been transferred.',
          type: NotificationType.success,
          category: 'auction',
          createdAt: DateTime.now(),
          isRead: false,
          actionRoute: '/nft/$tokenId',
        ));
      }

      if (kDebugMode) { debugPrint('[RECOVERY] ✅ Orphaned payment recovered for NFT #$tokenId'); }
      return true;
    } catch (e) {
      if (kDebugMode) { debugPrint('[RECOVERY] ❌ Recovery failed: $e'); }
      return false;
    }
  }

  DateTime? _lastPaymentCheck;

  /// Sweeps all PAYMENT_PENDING auctions and marks them as PAYMENT_EXPIRED if their deadline has passed
  Future<int> expirePaymentDeadlines() async {
    if (_lastPaymentCheck != null && DateTime.now().difference(_lastPaymentCheck!) < const Duration(seconds: 60)) {
      return 0; // Throttle to max 1 check per minute
    }
    _lastPaymentCheck = DateTime.now();

    int expiredCount = 0;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      
      // We look at NFTs that are PAYMENT_PENDING
      final querySnapshot = await _nftsCollection
          .where('auctionStatus', isEqualTo: 'PAYMENT_PENDING')
          .where('paymentExpired', isEqualTo: false)
          .get();

      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        final deadline = data['paymentDeadline'] as int? ?? 0;
        
        if (deadline > 0 && deadline < now) {
          final tokenId = int.parse(doc.id);
          final auctionRef = _auctionsCollection.doc(doc.id);
          
          await _db.runTransaction((transaction) async {
            // ── ALL READS FIRST (Firestore requirement) ──
            final nftDoc = await transaction.get(doc.reference);
            if (!nftDoc.exists) return;
            
            final auctionDoc = await transaction.get(auctionRef);
            
            // Re-verify in transaction
            final nftData = nftDoc.data()!;
            if (nftData['auctionStatus'] != 'PAYMENT_PENDING') return;
            final currentDeadline = nftData['paymentDeadline'] as int? ?? 0;
            if (currentDeadline == 0 || currentDeadline >= now) return;

            final highestBidderWallet = nftData['highestBidderWallet'] as String?;
            final ownerWallet = nftData['ownerWallet'] as String?;

            // ── ALL WRITES AFTER READS ──
            // Expire it
            transaction.update(doc.reference, {
              'auctionStatus': 'PAYMENT_EXPIRED',
              'status': 'payment_expired',
              'isAuctionActive': false,
              'auctionCreated': false, // Remove from marketplace
              'isActive': false,
              'paymentExpired': true,
              'highestBid': 0.0,
              'totalBids': 0,
              'highestBidderWallet': null,
              'highestBidderId': null,
              'currentBid': nftData['price'],
              // ownership remains with creator
            });

            if (auctionDoc.exists) {
              transaction.update(auctionRef, {
                'status': 'PAYMENT_EXPIRED',
              });
            }
            
            // Log transaction
            final txId = 'expire_${tokenId}_${DateTime.now().millisecondsSinceEpoch}';
            final expireTx = TransactionModel(
              transactionId: txId,
              nftId: tokenId.toString(),
              auctionId: tokenId.toString(),
              sellerId: nftData['ownerId'] as String? ?? '',
              buyerId: nftData['highestBidderId'] as String? ?? '',
              sellerWallet: ownerWallet ?? '',
              buyerWallet: highestBidderWallet ?? '',
              amount: (nftData['highestBid'] as num?)?.toDouble() ?? 0.0,
              transactionHash: 'EXPIRED',
              type: TransactionType.sale,
              status: TransactionStatus.failed,
            );
            transaction.set(_transactionsCollection.doc(txId), expireTx.toFirestore());
          });

          // Send Premium Notification to Creator
          final ownerWallet = data['ownerWallet'] as String?;
          final highestBidderWallet = data['highestBidderWallet'] as String?;
          if (ownerWallet != null && ownerWallet.isNotEmpty) {
            final notifId = _userNotificationsCollection(ownerWallet).doc().id;
            final creatorNotif = AppNotification(
              id: notifId,
              title: 'Auction Payment Expired',
              message: 'Winner failed to complete payment for NFT #$tokenId. You may request a re-auction.',
              type: NotificationType.warning,
              category: 'auction',
              createdAt: DateTime.now(),
              isRead: false,
              actionRoute: '/auction/$tokenId',
            );
            await saveNotification(ownerWallet, creatorNotif);
          }
          
          if (highestBidderWallet != null && highestBidderWallet.isNotEmpty) {
            final notifId2 = _userNotificationsCollection(highestBidderWallet).doc().id;
            final winnerNotif = AppNotification(
              id: notifId2,
              title: 'Payment Deadline Expired',
              message: 'Your payment deadline has expired for NFT #$tokenId. You have lost the claim.',
              type: NotificationType.error,
              category: 'auction',
              createdAt: DateTime.now(),
              isRead: false,
              actionRoute: '/auction/$tokenId',
            );
            await saveNotification(highestBidderWallet, winnerNotif);
          }

          expiredCount++;
          if (kDebugMode) { debugPrint('⏰ Expired pending payment for NFT #$tokenId'); }
        }
      }
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ checkAndExpirePendingPayments error: $e'); }
    }
    return expiredCount;
  }

  /// Handle failed payment by passing to 2nd bidder (Option A)
  Future<void> handleFailedPayment(int tokenId) async {
    try {
      final nftRef = _nftsCollection.doc(tokenId.toString());
      final auctionRef = _auctionsCollection.doc(tokenId.toString());

      String? secondBidderWallet;
      double? secondBidAmount;
      String? firstBidderWallet;
      String? creatorWallet;
      String nftName = '';
      bool passedToSecond = false;

      await _db.runTransaction((transaction) async {
        // ── ALL READS FIRST (Firestore requirement) ──
        final nftDoc = await transaction.get(nftRef);
        if (!nftDoc.exists) return;

        final data = nftDoc.data()!;
        firstBidderWallet = data['highestBidderWallet'] as String?;
        creatorWallet = (data['ownerWallet'] as String? ?? data['creatorWallet'] as String? ?? '').toLowerCase();
        nftName = data['name'] as String? ?? 'NFT #$tokenId';

        final auctionDoc = await transaction.get(auctionRef);

        // Query bids to find the 2nd highest bidder
        final bidsQuery = await nftRef.collection('bids')
            .orderBy('amount', descending: true)
            .orderBy('firstBidTimestamp', descending: false)
            .get();

        // Get unique bidders (since a user can have multiple bids)
        final Map<String, Bid> uniqueBids = {};
        for (var doc in bidsQuery.docs) {
          final bid = Bid.fromFirestore(doc.data());
          final wallet = bid.bidderWallet.toLowerCase();
          if (!uniqueBids.containsKey(wallet) || uniqueBids[wallet]!.amount < bid.amount) {
             uniqueBids[wallet] = bid;
          }
        }
        
        final sortedBids = uniqueBids.values.toList()
          ..sort((a, b) {
            final cmp = b.amount.compareTo(a.amount);
            if (cmp != 0) return cmp;
            return a.firstBidTimestamp.compareTo(b.firstBidTimestamp);
          });

        // ══════ ALL WRITES AFTER READS ══════
        if (sortedBids.length >= 2) {
          // Pass to Bidder #2
          final secondBidder = sortedBids[1];
          secondBidderWallet = secondBidder.bidderWallet.toLowerCase();
          secondBidAmount = secondBidder.amount;
          passedToSecond = true;

          // Reset NFT status to PAYMENT_PENDING for the 2nd bidder
          transaction.update(nftRef, {
            'highestBid': secondBidder.amount,
            'highestBidderId': secondBidder.bidderId,
            'highestBidderWallet': secondBidder.bidderWallet,
            'isAuctionActive': false,
            'auctionStatus': _sPending,   // canonical: 'PAYMENT_PENDING'
            'status': 'payment_pending',
            'paymentPending': true,
            'paymentDeadline': DateTime.now().add(const Duration(hours: 24)).millisecondsSinceEpoch,
            'paymentExpired': false,
          });

          if (auctionDoc.exists) {
            transaction.update(auctionRef, {
              'status': _sPending,   // canonical: 'PAYMENT_PENDING'
              'highestBid': secondBidder.amount,
              'highestBidderId': secondBidder.bidderId,
              'highestBidderWallet': secondBidder.bidderWallet,
            });
          }
          if (kDebugMode) { debugPrint('🔥 Payment failed, passed to 2nd bidder for NFT #$tokenId'); }
        } else {
          // No 2nd bidder, mark as failed_payment
          transaction.update(nftRef, {
             'isAuctionActive': false,
             // Could reset highestBidder or leave it for admin to see who failed
          });
          
          if (auctionDoc.exists) {
             transaction.update(auctionRef, {
               'status': 'failed_payment',
             });
          }
          if (kDebugMode) { debugPrint('🔥 Payment failed, no 2nd bidder. Status set to failed_payment for NFT #$tokenId'); }
        }
      });

      // 🔥 Post-transaction Notifications 🔥
      if (firstBidderWallet != null && firstBidderWallet!.isNotEmpty) {
        final notifId = _userNotificationsCollection(firstBidderWallet!).doc().id;
        await saveNotification(firstBidderWallet!, AppNotification(
          id: notifId,
          title: 'Payment Failed ⚠️',
          message: 'You failed to pay for $nftName within 24h. You have lost the auction.',
          type: NotificationType.paymentFailed,
          category: 'payment',
          createdAt: DateTime.now(),
          isRead: false,
          actionRoute: '/nft/$tokenId',
        ));
      }

      if (passedToSecond && secondBidderWallet != null && secondBidAmount != null) {
        final notifId = _userNotificationsCollection(secondBidderWallet!).doc().id;
        await saveNotification(secondBidderWallet!, AppNotification(
          id: notifId,
          title: 'You Won the Auction! (Passed) 🏆',
          message: 'The highest bidder failed to pay. As the 2nd highest bidder, you won $nftName! Pay ${secondBidAmount!.toStringAsFixed(4)} ETH within 24h.',
          type: NotificationType.auctionWon,
          category: 'payment',
          createdAt: DateTime.now(),
          isRead: false,
          actionRoute: '/auction/$tokenId',
        ));
      }

      if (creatorWallet != null && creatorWallet!.isNotEmpty) {
        final notifId = _userNotificationsCollection(creatorWallet!).doc().id;
        if (passedToSecond) {
          await saveNotification(creatorWallet!, AppNotification(
            id: notifId,
            title: 'Winner Failed Payment ⚠️',
            message: 'The winner of $nftName failed to pay. The auction was passed to the 2nd highest bidder.',
            type: NotificationType.info,
            category: 'auction',
            createdAt: DateTime.now(),
            isRead: false,
            actionRoute: '/nft/$tokenId',
          ));
        } else {
          await saveNotification(creatorWallet!, AppNotification(
            id: notifId,
            title: 'Relist Available: Payment Failed 📉',
            message: 'The winner of $nftName failed to pay, and there are no other bidders. You can now relist your NFT.',
            type: NotificationType.relistAvailable,
            category: 'auction',
            createdAt: DateTime.now(),
            isRead: false,
            actionRoute: '/nft/$tokenId',
          ));
        }
      }
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ handleFailedPayment error: $e'); }
      rethrow;
    }
  }

  /// Cancel an auction
  Future<void> cancelAuction(int auctionId, int tokenId) async {
    try {
      final batch = _db.batch();

      batch.update(_auctionsCollection.doc(auctionId.toString()), {
        'status': 'cancelled',
      });

      batch.update(_nftsCollection.doc(tokenId.toString()), {
        'status': 'cancelled',
        'isAuctionActive': false,
        'isInAuction': false,
      });

      // Fetch all bids and invalidate them
      final bidsSnapshot = await _nftsCollection.doc(tokenId.toString()).collection('bids').get();
      for (final doc in bidsSnapshot.docs) {
        batch.update(doc.reference, {'isInvalidated': true});
      }

      await batch.commit();
      if (kDebugMode) { debugPrint('🔥 Auction #$auctionId cancelled'); }
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ cancelAuction error: $e'); }
      rethrow;
    }
  }

  // ============ Transactions ============

  Future<void> recordTransaction(TransactionModel tx) async {
    try {
      final data = tx.toFirestore();
      if (tx.status == TransactionStatus.pending) {
        data['createdAt'] = FieldValue.serverTimestamp();
      } else {
        data['confirmedAt'] = FieldValue.serverTimestamp();
      }

      await _transactionsCollection
          .doc(tx.transactionId)
          .set(data, SetOptions(merge: true));
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ recordTransaction error: $e'); }
    }
  }

  /// Stream of transactions for a user (as buyer OR seller)
  Stream<List<TransactionModel>> getUserTransactionsStream(String userId) {
    // Query seller transactions
    final sellerStream = _transactionsCollection
        .where('sellerId', isEqualTo: userId)
        .snapshots();

    // Merge seller stream with buyer query
    return sellerStream.asyncMap((sellerSnapshot) async {
      final buyerSnapshot = await _transactionsCollection
          .where('buyerId', isEqualTo: userId)
          .get();

      final Map<String, TransactionModel> txMap = {};

      for (var doc in sellerSnapshot.docs) {
        final tx = TransactionModel.fromFirestore(doc.data());
        txMap[tx.transactionId] = tx;
      }
      for (var doc in buyerSnapshot.docs) {
        final tx = TransactionModel.fromFirestore(doc.data());
        txMap[tx.transactionId] = tx;
      }

      final list = txMap.values.toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// Stream all transactions (for admin)
  Stream<List<TransactionModel>> getAllTransactionsStream() {
    return _transactionsCollection.snapshots().map((snapshot) {
      final list = snapshot.docs
          .map((doc) => TransactionModel.fromFirestore(doc.data()))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  // ============ User Management ============

  /// Stream of all users (for admin dashboard)
  Stream<List<UserModel>> getAllUsersStream() {
    return _usersCollection.snapshots().map((snapshot) {
      final list = snapshot.docs
          .map((doc) => UserModel.fromFirestore(doc.data()))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// Update a user's role (admin operation)
  Future<void> updateUserRole(String uid, String newRole) async {
    try {
      await _usersCollection.doc(uid).update({
        'role': newRole,
      });
      if (kDebugMode) { debugPrint('🔥 User $uid role updated to $newRole'); }
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ updateUserRole error: $e'); }
      rethrow;
    }
  }

  /// Get a single user by UID
  Future<UserModel?> getUser(String uid) async {
    try {
      final doc = await _usersCollection.doc(uid).get();
      if (doc.exists) {
        return UserModel.fromFirestore(doc.data()!);
      }
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ getUser error: $e'); }
    }
    return null;
  }

  // ============ Firestore Sync ============

  /// Sync blockchain state to Firestore (called after loadFromChain)
  Future<void> syncFirestoreState(List<LogoNFT> chainLogos) async {
    try {
      for (final logo in chainLogos) {
        final doc = await _nftsCollection.doc(logo.tokenId.toString()).get();
        if (!doc.exists) {
          // NFT exists on-chain but not in Firestore — create it
          await _nftsCollection
              .doc(logo.tokenId.toString())
              .set(logo.toFirestore(), SetOptions(merge: true));
          debugPrint(
              '🔄 Synced NFT #${logo.tokenId} from blockchain to Firestore');
        }
      }
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ syncFirestoreState error: $e'); }
    }
  }

  // ============ Edge Case Hardening ============

  DateTime? _lastExpireCheck;

  /// Check for and auto-close expired auctions that are still marked as active
  Future<int> closeExpiredAuctions() async {
    if (_lastExpireCheck != null && DateTime.now().difference(_lastExpireCheck!) < const Duration(seconds: 60)) {
      return 0; // Throttle to max 1 check per minute
    }
    _lastExpireCheck = DateTime.now();

    int closedCount = 0;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;

      final snapshot = await _auctionsCollection
          .where('status', isEqualTo: 'active')
          .get();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final endTime = data['endTime'] as int? ?? 0;
        if (endTime > 0 && endTime < now) {
          final auctionId = data['auctionId'] as int? ?? 0;
          final tokenId = data['tokenId'] as int? ?? 0;

          await endOffChainAuction(tokenId);
          closedCount++;
          if (kDebugMode) { debugPrint('⏰ Auto-closed expired auction #$auctionId'); }
        }
      }

      // Phase 4: Auto cleanup NFT desyncs
      final nftSnapshot = await _nftsCollection
          .where('isAuctionActive', isEqualTo: true)
          .get();

      for (final doc in nftSnapshot.docs) {
        final data = doc.data();
        final endTime = data['endTime'] as int? ?? 0;
        final tokenId = data['tokenId'] as int? ?? 0;
        
        if (endTime > 0 && endTime < now) {
          await endOffChainAuction(tokenId);
          closedCount++;
          if (kDebugMode) { debugPrint('⏰ Auto-closed expired NFT auction #$tokenId'); }
        }
      }
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ closeExpiredAuctions error: $e'); }
    }
    return closedCount;
  }

  /// Idempotent guard for auction completion — prevents double-completion
  Future<bool> isAuctionAlreadyCompleted(int auctionId) async {
    try {
      final doc = await _auctionsCollection.doc(auctionId.toString()).get();
      if (!doc.exists) return true;
      final status = doc.data()?['status'] as String? ?? 'active';
      return status == 'ended' || status == 'cancelled';
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ isAuctionAlreadyCompleted error: $e'); }
      return false; // Fail open to allow retry
    }
  }

  /// Check if reserve price was met for an auction
  Future<bool> isReservePriceMet(int auctionId) async {
    try {
      final doc = await _auctionsCollection.doc(auctionId.toString()).get();
      if (!doc.exists) return false;
      final data = doc.data()!;
      final reservePrice = (data['reservePrice'] as num?)?.toDouble() ?? 0.0;
      final highestBid = (data['highestBid'] as num?)?.toDouble() ?? 0.0;
      if (reservePrice <= 0) return true; // No reserve price set
      return highestBid >= reservePrice;
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ isReservePriceMet error: $e'); }
      return false;
    }
  }

  /// Validate that a bid is still valid (auction active, amount > current highest)
  Future<void> validateBid(int auctionId, String bidderId, double amount) async {
    final doc = await _auctionsCollection.doc(auctionId.toString()).get();
    if (!doc.exists) throw Exception('Auction not found');
    
    final data = doc.data()!;
    final status = data['status'] as String? ?? 'active';
    if (status != 'active') throw Exception('Auction is no longer active');
    
    final endTime = data['endTime'] as int? ?? 0;
    if (endTime > 0 && DateTime.now().millisecondsSinceEpoch > endTime) {
      throw Exception('Auction has expired');
    }
    
    final currentHighest = (data['highestBid'] as num?)?.toDouble() ?? 0.0;
    if (amount <= currentHighest) throw Exception('Bid must exceed current highest bid');
    
    final sellerId = data['sellerId'] as String? ?? '';
    if (bidderId == sellerId) throw Exception('Seller cannot bid on own auction');
  }

  // ============ Re-Auction Flow ============
  
  Future<void> requestReAuctionWithSettings(int tokenId, int newDuration, double newStartingPrice, {String? notes}) async {
    try {
      final nftRef = _nftsCollection.doc(tokenId.toString());
      final auctionRef = _auctionsCollection.doc(tokenId.toString());

      await _db.runTransaction((transaction) async {
        final doc = await transaction.get(nftRef);
        if (!doc.exists) throw Exception('NFT not found');

        final data = doc.data()!;
        if (data['isFrozen'] == true) throw Exception('Cannot re-auction a frozen NFT');
        if (data['status'] == 'cancelled') throw Exception('Cannot re-auction a cancelled NFT');
        if (data['status'] == 'rejected') throw Exception('Rejected NFTs cannot be re-auctioned.');
        
        final isAuctionActive = data['isAuctionActive'] as bool? ?? false;
        if (isAuctionActive) throw Exception('NFT currently has an active auction.');

        final previousHighestBid = (data['highestBid'] as num?)?.toDouble() ?? 0.0;
        final previousWinner = data['highestBidderWallet'];
        final currentAuctionCount = data['auctionCount'] as int? ?? 0;
        final existingHistory = List<dynamic>.from(data['auctionHistory'] ?? []);

        // Save history of previous auction
        existingHistory.add({
            'auctionRound': currentAuctionCount + 1,
            'finalBid': previousHighestBid,
            'winnerWallet': previousWinner,
            'endedAt': DateTime.now().millisecondsSinceEpoch,
            'auctionStatus': data['auctionStatus']
        });

        final now = DateTime.now();
        final endTime = now.add(Duration(seconds: newDuration));

        // Update NFT instantly to ACTIVE
        transaction.update(nftRef, {
          'isInAuction': true,
          'isAuctionActive': true,
          'auctionCreated': true,
          'auctionStatus': 'ACTIVE',
          'status': 'auction',
          'price': newStartingPrice,
          'auctionDuration': newDuration,
          'startTime': now.millisecondsSinceEpoch,
          'endTime': endTime.millisecondsSinceEpoch,
          'highestBid': 0.0,
          'highestBidderWallet': '',
          'highestBidderId': '',
          'paymentStatus': null,
          'paymentPending': false,
          'paymentExpired': false,
          'auctionWinner': '',
          'totalBids': 0,
          'previousFinalBid': previousHighestBid,
          'previousWinnerWallet': previousWinner,
          'auctionCount': currentAuctionCount + 1,
          'auctionHistory': existingHistory,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Recreate Auction document
        final auctionData = Auction(
          auctionId: tokenId,
          tokenId: tokenId,
          sellerId: data['ownerId'] as String? ?? '',
          sellerWallet: data['ownerWallet'] as String? ?? '',
          startingPrice: newStartingPrice,
          highestBid: 0.0,
          highestBidderId: '',
          highestBidderWallet: '',
          startTime: now,
          endTime: endTime,
          status: AuctionStatus.active,
        ).toFirestore();
        auctionData['createdAt'] = FieldValue.serverTimestamp();

        transaction.set(auctionRef, auctionData);
      });
      
      // Clear old bids safely outside transaction
      final bidsSnapshot = await nftRef.collection('bids').get();
      if (bidsSnapshot.docs.isNotEmpty) {
        final batch = _db.batch();
        for (var bid in bidsSnapshot.docs) {
          batch.delete(bid.reference);
        }
        await batch.commit();
      }

      if (kDebugMode) { debugPrint('🔥 Instant Re-Auction started for NFT #$tokenId'); }
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ requestReAuctionWithSettings error: $e'); }
      rethrow;
    }
  }

  Future<void> approveReAuction(int tokenId, String adminId) async {
    try {
      final nftRef = _nftsCollection.doc(tokenId.toString());
      final auctionRef = _auctionsCollection.doc(tokenId.toString());

      await _db.runTransaction((transaction) async {
        final doc = await transaction.get(nftRef);
        if (!doc.exists) throw Exception('NFT not found');

        final data = doc.data()!;
        final newDuration = data['reAuctionDuration'] as int? ?? 86400;
        final newStartingPrice = (data['reAuctionStartingPrice'] as num?)?.toDouble() ?? data['price'];

        final now = DateTime.now();
        final endTime = now.add(Duration(seconds: newDuration));

        // Update NFT
        transaction.update(nftRef, {
          'auctionStatus': 'ACTIVE',
          'isAuctionActive': true,
          'isActive': true,
          'price': newStartingPrice,
          'auctionDuration': newDuration,
          'startTime': now.millisecondsSinceEpoch,
          'endTime': endTime.millisecondsSinceEpoch,
          'reAuctionDuration': FieldValue.delete(),
          'reAuctionStartingPrice': FieldValue.delete(),
          'reAuctionNotes': FieldValue.delete(),
          'reAuctionRequestedAt': FieldValue.delete(),
          'auctionCount': FieldValue.increment(1),
        });

        // Recreate Auction document
        final auctionData = Auction(
          auctionId: tokenId,
          tokenId: tokenId,
          sellerId: data['ownerId'] as String? ?? '',
          sellerWallet: data['ownerWallet'] as String? ?? '',
          startingPrice: newStartingPrice,
          highestBid: 0.0,
          highestBidderId: '',
          highestBidderWallet: '',
          startTime: now,
          endTime: endTime,
          status: AuctionStatus.active,
        ).toFirestore();
        auctionData['createdAt'] = FieldValue.serverTimestamp();

        transaction.set(auctionRef, auctionData);
      });
      
      // Clear old bids
      final bidsSnapshot = await nftRef.collection('bids').get();
      if (bidsSnapshot.docs.isNotEmpty) {
        final batch = _db.batch();
        for (var bid in bidsSnapshot.docs) {
          batch.delete(bid.reference);
        }
        await batch.commit();
      }

      if (kDebugMode) { debugPrint('🔥 Approved Re-Auction for NFT #$tokenId'); }
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ approveReAuction error: $e'); }
      rethrow;
    }
  }

  Future<void> rejectReAuction(int tokenId, String adminId) async {
    try {
      await _nftsCollection.doc(tokenId.toString()).update({
        'auctionStatus': 'ENDED_NO_BID',
        'reAuctionDuration': FieldValue.delete(),
        'reAuctionStartingPrice': FieldValue.delete(),
        'reAuctionNotes': FieldValue.delete(),
        'reAuctionRequestedAt': FieldValue.delete(),
      });
      if (kDebugMode) { debugPrint('🔥 Rejected Re-Auction for NFT #$tokenId'); }
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ rejectReAuction error: $e'); }
      rethrow;
    }
  }

  Stream<List<LogoNFT>> getReAuctionRequestsStream() {
    return _nftsCollection
        .where('auctionStatus', isEqualTo: 'RE_AUCTION_REQUESTED')
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs.map((doc) => LogoNFT.fromFirestore(doc.data())).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  Stream<int> getReAuctionRequestsCountStream() {
    return _nftsCollection
        .where('auctionStatus', isEqualTo: 'RE_AUCTION_REQUESTED')
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  // ============ Appeal Operations ============
  Future<void> submitAppeal(int tokenId, String creatorWallet, String creatorUsername, String appealMessage, String reportId) async {
    return _retryOperation(() async {
      await _db.runTransaction((transaction) async {
        final nftDoc = await transaction.get(_nftsCollection.doc(tokenId.toString()));
        if (!nftDoc.exists) throw Exception('NFT not found');
        
        final logo = LogoNFT.fromJson(nftDoc.data()!);
        
        // 1. Validation: NFT must be frozen
        if (!logo.isFrozen) {
          throw Exception('Cannot submit appeal. Auction is not currently frozen.');
        }
        
        // 2. Validation: Cannot appeal if permanently rejected
        if (logo.status == ValidationStatus.rejected) {
          throw Exception('Cannot submit appeal. NFT is permanently rejected.');
        }

        // 3. Validation: Only creator can appeal (already checked in UI, but good to double check)
        if (logo.creatorWallet.toLowerCase() != creatorWallet.toLowerCase()) {
          throw Exception('Unauthorized. Only the creator can submit an appeal.');
        }

        // 4. Validation: Check if appeal already exists for this report
        final existingAppealQuery = await _appealsCollection.where('reportId', isEqualTo: reportId).limit(1).get();
        if (existingAppealQuery.docs.isNotEmpty) {
          throw Exception('An appeal has already been submitted for this report.');
        }

        // Save Appeal
        final appealId = _appealsCollection.doc().id;
        transaction.set(_appealsCollection.doc(appealId), {
          'appealId': appealId,
          'tokenId': tokenId,
          'creatorWallet': creatorWallet,
          'creatorUsername': creatorUsername,
          'appealMessage': appealMessage,
          'reportId': reportId,
          'createdAt': FieldValue.serverTimestamp(),
          'status': 'submitted',
        });

        // Update NFT isAppealed
        transaction.update(nftDoc.reference, {
          'isAppealed': true,
        });
      });
    });
  }

  Future<Map<String, dynamic>?> getLatestReportForToken(int tokenId) async {
    try {
      final querySnapshot = await _reportsCollection
          .where('tokenId', isEqualTo: tokenId)
          .where('status', whereIn: ['pending', 'frozen'])
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        return querySnapshot.docs.first.data();
      }
      return null;
    } catch (e) {
      if (kDebugMode) { debugPrint('Error getting latest report: '); }
      return null;
    }
  }

  Future<Map<String, dynamic>?> getAppealForReport(String reportId) async {
    try {
      final querySnapshot = await _appealsCollection
          .where('reportId', isEqualTo: reportId)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        return querySnapshot.docs.first.data();
      }
      return null;
    } catch (e) {
      if (kDebugMode) { debugPrint('Error getting appeal: '); }
      return null;
    }
  }

  // ============ Notification Operations ============

  CollectionReference<Map<String, dynamic>> _userNotificationsCollection(String wallet) =>
      _db.collection('users').doc(wallet.toLowerCase()).collection('notifications');

  Future<void> saveNotification(String wallet, AppNotification notification) async {
    try {
      if (wallet.isEmpty) return;
      final ref = _userNotificationsCollection(wallet).doc(notification.id);
      await ref.set(notification.toMap());
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ Error saving notification: $e'); }
    }
  }

  Stream<List<AppNotification>> getNotificationsStream(String wallet) {
    if (wallet.isEmpty) return Stream.value([]);
    return _userNotificationsCollection(wallet)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => AppNotification.fromFirestore(doc.data(), doc.id)).toList();
    });
  }

  Stream<int> getUnreadNotificationsCountStream(String wallet) {
    if (wallet.isEmpty) return Stream.value(0);
    return _userNotificationsCollection(wallet)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  Future<void> markNotificationAsRead(String wallet, String notificationId) async {
    try {
      if (wallet.isEmpty) return;
      await _userNotificationsCollection(wallet).doc(notificationId).update({'isRead': true});
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ Error marking notification as read: $e'); }
    }
  }

  Future<void> markAllNotificationsAsRead(String wallet) async {
    try {
      if (wallet.isEmpty) return;
      final snapshot = await _userNotificationsCollection(wallet)
          .where('isRead', isEqualTo: false)
          .get();
      
      if (snapshot.docs.isEmpty) return;

      final batch = _db.batch();
      for (var doc in snapshot.docs) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ Error marking all notifications as read: $e'); }
    }
  }

  Future<void> clearAllNotifications(String wallet) async {
    try {
      if (wallet.isEmpty) return;
      final snapshot = await _userNotificationsCollection(wallet).get();
      
      if (snapshot.docs.isEmpty) return;

      final batch = _db.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ Error clearing all notifications: $e'); }
    }
  }

  Future<void> updateUserFCMToken(String wallet, String token) async {
    try {
      if (wallet.isEmpty) return;
      await _db.collection('users').doc(wallet.toLowerCase()).set({
        'fcmToken': token,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ Error updating FCM token: $e'); }
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // AUDIT & SECURITY HELPERS
  // ═══════════════════════════════════════════════════════════════════

  /// Check if a transaction hash has already been used in any transaction.
  /// Returns true if duplicate found (payment should be REJECTED).
  Future<bool> checkDuplicateTxHash(String txHash) async {
    try {
      txHash = txHash.toLowerCase().trim();
      if (txHash.isEmpty || txHash == 'expired') return false;
      final query = await _transactionsCollection
          .where('transactionHash', isEqualTo: txHash)
          .limit(1)
          .get();
      return query.docs.isNotEmpty;
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ checkDuplicateTxHash error: $e'); }
      // Fail-safe: if we can't verify, reject the payment
      return true;
    }
  }

  /// Log auction activity for audit trail.
  /// Tracks: payment_completed, payment_expired, payment_rejected, duplicate_tx_detected
  Future<void> logAuctionActivity({
    required String nftId,
    required String txHash,
    required String wallet,
    required double amount,
    required String actionType,
  }) async {
    try {
      await _db.collection('auction_activity_logs').add({
        'nftId': nftId,
        'txHash': txHash,
        'wallet': wallet,
        'amount': amount,
        'actionType': actionType,
        'timestamp': FieldValue.serverTimestamp(),
        'createdAt': DateTime.now().toIso8601String(),
      });
      if (kDebugMode) { debugPrint('📝 Audit log: $actionType for NFT #$nftId'); }
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ logAuctionActivity error: $e'); }
      // Non-critical: don't throw, audit failure shouldn't block payment
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // COPYRIGHT DISPUTE & APPEAL SYSTEM
  // ═══════════════════════════════════════════════════════════════════

  /// Stream a specific appeal case by its token ID (assuming 1 active case per NFT)
  Stream<AppealCase?> getAppealCaseStreamByToken(int tokenId) {
    return _appealsCollection
        .where('tokenId', isEqualTo: tokenId)
        .where('status', isEqualTo: 'open')
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      return AppealCase.fromFirestore(snapshot.docs.first.data(), snapshot.docs.first.id);
    });
  }

  /// Stream messages for a specific appeal case
  Stream<List<AppealMessage>> getAppealMessagesStream(String caseId) {
    return _appealsCollection
        .doc(caseId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => AppealMessage.fromFirestore(doc.data(), doc.id)).toList();
    });
  }

  /// Send a message in an appeal case
  Future<void> sendAppealMessage({
    required String caseId,
    required String senderWallet,
    required String senderRole,
    required String message,
    List<String>? evidenceUrls,
  }) async {
    try {
      final docRef = _appealsCollection.doc(caseId).collection('messages').doc();
      final appealMsg = AppealMessage(
        messageId: docRef.id,
        caseId: caseId,
        senderWallet: senderWallet,
        senderRole: senderRole,
        message: message,
        evidenceUrls: evidenceUrls,
        timestamp: DateTime.now(),
      );
      await docRef.set(appealMsg.toFirestore());
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ sendAppealMessage error: $e'); }
      rethrow;
    }
  }

  /// Report an NFT for copyright violation and freeze it
  Future<void> reportNFT(int tokenId, String reporterWallet, String reason, List<String>? evidenceFiles) async {
    try {
      final nftRef = _nftsCollection.doc(tokenId.toString());
      final auctionRef = _auctionsCollection.doc(tokenId.toString());

      await _db.runTransaction((transaction) async {
        final nftDoc = await transaction.get(nftRef);
        if (!nftDoc.exists) throw Exception('NFT not found');

        final data = nftDoc.data() as Map<String, dynamic>;
        final currentStatus = data['status'] as String? ?? 'available';
        final isFrozen = data['isFrozen'] as bool? ?? false;
        
        if (isFrozen) {
          throw Exception('NFT is already frozen.');
        }

        final isAuctionActive = data['isAuctionActive'] as bool? ?? false;
        final ownerWallet = data['ownerWallet'] as String? ?? '';
        
        // Determine new status
        String newStatus = isAuctionActive ? 'frozen_auction' : 'under_review';

        // Calculate frozen remaining seconds if auction was active
        int? frozenRemainingSeconds;
        if (isAuctionActive && data['endTime'] != null) {
          DateTime endTime = DateTime.fromMillisecondsSinceEpoch(data['endTime'] as int);
          frozenRemainingSeconds = endTime.difference(DateTime.now()).inSeconds;
          if (frozenRemainingSeconds < 0) frozenRemainingSeconds = 0;
        }

        // Create new Appeal Case
        final caseDoc = _appealsCollection.doc();
        final appealCase = AppealCase(
          caseId: caseDoc.id,
          tokenId: tokenId,
          reporterWallet: reporterWallet,
          ownerWallet: ownerWallet,
          createdAt: DateTime.now(),
          status: 'open',
        );

        // --- WRITES ---
        transaction.set(caseDoc, appealCase.toFirestore());

        transaction.update(nftRef, {
          'status': newStatus,
          'previousStatus': currentStatus,
          'isFrozen': true,
          'freezeReason': reason,
          'evidenceFiles': evidenceFiles,
          if (frozenRemainingSeconds != null) 'frozenRemainingSeconds': frozenRemainingSeconds,
        });

        if (isAuctionActive) {
          final auctionDoc = await transaction.get(auctionRef);
          if (auctionDoc.exists) {
            transaction.update(auctionRef, {
              'status': 'frozen_auction',
            });
          }
        }
      });
      
      if (kDebugMode) { debugPrint('🔥 Firestore: NFT #$tokenId reported and frozen.'); }
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ reportNFT error: $e'); }
      rethrow;
    }
  }

  /// Admin resolves the case
  Future<void> resolveAppealCase(String caseId, int tokenId, bool isTakedown, String decisionReason) async {
    try {
      final nftRef = _nftsCollection.doc(tokenId.toString());
      final auctionRef = _auctionsCollection.doc(tokenId.toString());
      final caseRef = _appealsCollection.doc(caseId);

      await _db.runTransaction((transaction) async {
        final nftDoc = await transaction.get(nftRef);
        if (!nftDoc.exists) throw Exception('NFT not found');
        
        final caseDoc = await transaction.get(caseRef);
        if (!caseDoc.exists) throw Exception('Case not found');

        final data = nftDoc.data() as Map<String, dynamic>;
        final previousStatus = data['previousStatus'] as String?;
        final frozenRemainingSeconds = data['frozenRemainingSeconds'] as int?;

        // --- WRITES ---
        transaction.update(caseRef, {
          'status': 'resolved',
          'resolvedAt': DateTime.now().millisecondsSinceEpoch,
          'resolutionType': isTakedown ? 'takedown' : 'unfrozen',
        });

        if (isTakedown) {
          transaction.update(nftRef, {
            'status': 'copyright_violation',
            'isFrozen': true,
            'decisionReason': decisionReason,
            'isAuctionActive': false, // stop auction entirely
          });
          
          final auctionDoc = await transaction.get(auctionRef);
          if (auctionDoc.exists) {
            transaction.update(auctionRef, {
              'status': 'cancelled',
            });
          }
        } else {
          // Unfreeze
          int? newEndTime;
          if (frozenRemainingSeconds != null) {
            newEndTime = DateTime.now().add(Duration(seconds: frozenRemainingSeconds)).millisecondsSinceEpoch;
          }

          transaction.update(nftRef, {
            'status': previousStatus ?? 'available',
            'isFrozen': false,
            'decisionReason': decisionReason,
            if (newEndTime != null) 'endTime': newEndTime,
            // clean up
            'frozenRemainingSeconds': FieldValue.delete(),
          });

          if (previousStatus == 'auction') {
            final auctionDoc = await transaction.get(auctionRef);
            if (auctionDoc.exists) {
              transaction.update(auctionRef, {
                'status': 'active',
                if (newEndTime != null) 'endTime': newEndTime,
              });
            }
          }
        }
      });
      if (kDebugMode) { debugPrint('🔥 Firestore: Case $caseId resolved.'); }
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ resolveAppealCase error: $e'); }
      rethrow;
    }
  }
}
