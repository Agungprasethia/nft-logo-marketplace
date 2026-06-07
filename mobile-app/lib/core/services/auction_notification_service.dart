import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nft_logo_marketplace/shared/models/auction.dart';
import 'package:nft_logo_marketplace/shared/models/app_notification.dart';
import 'package:nft_logo_marketplace/core/services/firestore_service.dart';
import 'package:nft_logo_marketplace/core/services/web3_service.dart';
import 'package:nft_logo_marketplace/core/utils/notification_manager.dart';

/// Global realtime auction notification service.
/// Automatically starts when wallet connects and stops when it disconnects.
class AuctionNotificationService {
  static final AuctionNotificationService _instance =
      AuctionNotificationService._();
  static AuctionNotificationService get instance => _instance;

  AuctionNotificationService._();

  /// Holds per-token state for each monitored auction
  final Map<int, _AuctionNotifState> _states = {};

  bool _isMonitoring = false;
  String? _currentWallet;
  StreamSubscription? _myBidsSub;
  StreamSubscription? _myAuctionsSub;

  final Map<String, Set<int>> _sourceTokenIds = {'bids': {}, 'seller': {}};

  // ─── Public API ──────────────────────────────────────────────────────────

  /// Call this once in main() to initialize global monitoring.
  void startGlobalAuctionMonitoring() {
    if (_isMonitoring) return;
    _isMonitoring = true;
    Web3Service.instance.addListener(_onWeb3StateChanged);
    _onWeb3StateChanged();
  }

  /// Manually stops global monitoring (also called automatically on disconnect).
  void stopGlobalAuctionMonitoring() {
    if (!_isMonitoring) return;
    _isMonitoring = false;
    Web3Service.instance.removeListener(_onWeb3StateChanged);
    _stopMonitoring();
  }

  // ─── Internal Management ─────────────────────────────────────────────────

  void _onWeb3StateChanged() {
    final wallet = Web3Service.instance.currentAddress?.toLowerCase();

    // If wallet disconnected or missing, stop everything
    if (wallet == null || !Web3Service.instance.isConnected) {
      _stopMonitoring();
      return;
    }

    // If wallet changed (or just connected), build monitoring
    if (_currentWallet != wallet) {
      _currentWallet = wallet;
      _buildMonitoring(wallet);
    }
  }

  void _buildMonitoring(String wallet) {
    _myBidsSub?.cancel();
    _myAuctionsSub?.cancel();

    // 1. Monitor auctions where user placed bids (limit to 20 most recent tokens)
    _myBidsSub = FirestoreService.instance
        .getUserParticipatedBidsStream(wallet)
        .listen((bidsMap) {
      // Sort to get the most recent 20
      var entries = bidsMap.entries.toList();
      entries.sort((a, b) {
        final tA = a.value['timestamp'];
        final tB = b.value['timestamp'];
        if (tA == null && tB == null) return 0;
        if (tA == null) return 1;
        if (tB == null) return -1;
        
        // Handle both int (milliseconds) and Timestamp gracefully
        int msA = tA is Timestamp ? tA.millisecondsSinceEpoch : (tA is int ? tA : 0);
        int msB = tB is Timestamp ? tB.millisecondsSinceEpoch : (tB is int ? tB : 0);
        return msB.compareTo(msA);
      });
      final topTokens = entries.take(20).map((e) => e.key).toSet();
      _syncTokenIds(topTokens, 'bids');
    });

    // 2. Monitor active auctions where user is the seller (limit 20)
    _myAuctionsSub = FirebaseFirestore.instance
        .collection('auctions')
        .where('sellerWallet', isEqualTo: wallet)
        .where('status', isEqualTo: 'active')
        .limit(20)
        .snapshots()
        .listen((snapshot) {
      final tokenIds = snapshot.docs.map((doc) => int.parse(doc.id)).toSet();
      _syncTokenIds(tokenIds, 'seller');
    });
  }

  void _syncTokenIds(Set<int> tokenIds, String source) {
    _sourceTokenIds[source] = tokenIds;
    final allTokens = _sourceTokenIds.values.expand((e) => e).toSet();

    // Add new states
    for (final id in allTokens) {
      if (!_states.containsKey(id)) {
        final state = _AuctionNotifState(tokenId: id);
        _states[id] = state;
        state._subscribe();
      }
    }

    // Remove old/stale states
    final toRemove = _states.keys.where((id) => !allTokens.contains(id)).toList();
    for (final id in toRemove) {
      _states[id]?._dispose();
      _states.remove(id);
    }
  }

  void _stopMonitoring() {
    _myBidsSub?.cancel();
    _myAuctionsSub?.cancel();
    _myBidsSub = null;
    _myAuctionsSub = null;
    _currentWallet = null;
    _sourceTokenIds['bids']!.clear();
    _sourceTokenIds['seller']!.clear();

    for (final state in _states.values) {
      state._dispose();
    }
    _states.clear();
  }
}

// ─── Internal Per-Token State ─────────────────────────────────────────────────

class _AuctionNotifState {
  final int tokenId;

  StreamSubscription<List<Bid>>? _bidSub;
  StreamSubscription<Auction?>? _auctionSub;
  Timer? _timer;

  // Cached state
  List<Bid> _bids = [];
  Auction? _auction;

  // Cache for detecting changes
  String? _lastHighestBidderWallet;
  int _lastBidCount = 0;

  // Anti-spam cooldown map (key → last notification timestamp)
  final Map<String, DateTime> _cooldowns = {};

  // For one-time alerts (60s, 30s, 10s, winner, lost, payment_pending)
  final Map<String, DateTime> _shownAuctionEvents = {};

  _AuctionNotifState({required this.tokenId});

  // ── Subscribe ─────────────────────────────────────────────────────────────

  void _subscribe() {
    // 1. Subscribe to bids
    _bidSub = FirestoreService.instance
        .getAuctionBidsStream(tokenId)
        .listen(
          (bids) {
            _bids = bids;
            _onBidsUpdate(bids);
          },
          onError: (e) {
            debugPrint('⚠️ AuctionNotificationService bid stream error: $e');
            // Try fallback
            _bidSub?.cancel();
            _bidSub = FirestoreService.instance
                .getAuctionBidsStreamFallback(tokenId)
                .listen(
                  (bids) {
                    _bids = bids;
                    _onBidsUpdate(bids);
                  },
                  onError: (e2) => debugPrint(
                      '⚠️ AuctionNotificationService fallback error: $e2'),
                );
          },
        );

    // 2. Subscribe to auction
    _auctionSub = FirestoreService.instance.getAuctionStream(tokenId).listen(
      (auction) {
        _auction = auction;
      },
    );

    // 3. Periodic timer to check countdowns and statuses
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  // ── Periodic Tick (Time & Status Alerts) ──────────────────────────────────

  void _onTick() {
    final auction = _auction;
    if (auction == null) return;

    final currentWallet = Web3Service.instance.currentAddress?.toLowerCase();

    // PHASE 1-3: Countdown Alerts
    if (auction.status == AuctionStatus.active) {
      final remainingSeconds =
          auction.endTime.difference(DateTime.now()).inSeconds;

      if (remainingSeconds <= 60 && remainingSeconds > 30) {
        if (_canShowEvent('60s')) {
          NotificationManager.show(
            title: '⏰ Auction Ending Soon!',
            message: 'Less than 1 minute remaining.\nPlace your final bid now.',
            type: NotificationType.warning,
            category: 'auction',
            tokenId: tokenId,
            saveToHistory: false,
          );
        }
      } else if (remainingSeconds <= 30 && remainingSeconds > 10) {
        if (_canShowEvent('30s')) {
          NotificationManager.show(
            title: '🔥 Final 30 Seconds!',
            message: 'This auction is entering the final stage.',
            type: NotificationType.warning,
            category: 'auction',
            tokenId: tokenId,
            saveToHistory: false,
          );
        }
      } else if (remainingSeconds <= 10 && remainingSeconds > 0) {
        if (_canShowEvent('10s')) {
          NotificationManager.show(
            title: '⚠ Final Countdown!',
            message: 'Only a few seconds remain.',
            type: NotificationType.error,
            category: 'auction',
            tokenId: tokenId,
            saveToHistory: false,
          );
        }
      }
    }

    // PHASE 4-6: Post-Auction Alerts
    final isFinished = (auction.status != AuctionStatus.active &&
        auction.status != AuctionStatus.draft &&
        auction.status != AuctionStatus.frozen &&
        auction.status != AuctionStatus.rejected &&
        auction.status != AuctionStatus.cancelled &&
        auction.status != AuctionStatus.reAuctionRequested);

    if (isFinished && currentWallet != null) {
      final isWinner =
          auction.highestBidderWallet?.toLowerCase() == currentWallet;
      final participated =
          _bids.any((b) => b.bidderWallet.toLowerCase() == currentWallet);

      // Phase 4: Winner Alert
      if (isWinner) {
        if (_canShowEvent('winner')) {
          NotificationManager.show(
            title: '🏆 Congratulations!',
            message: 'You won this auction.\nProceed to payment to claim ownership.',
            type: NotificationType.success,
            category: 'auction',
            tokenId: tokenId,
            saveToHistory: true,
          );
        }
      }
      // Phase 5: Auction Lost Alert
      else if (participated && !isWinner) {
        if (_canShowEvent('lost')) {
          NotificationManager.show(
            title: 'Auction Finished',
            message: 'Another bidder won this auction.\nThank you for participating.',
            type: NotificationType.info,
            category: 'auction',
            tokenId: tokenId,
            saveToHistory: true,
          );
        }
      }

      // Phase 6: Payment Reminder
      if (auction.status == AuctionStatus.paymentPending && isWinner) {
        if (_canShowEvent('payment_reminder')) {
          NotificationManager.show(
            title: 'Payment Required',
            message: 'Complete your payment to receive ownership.',
            type: NotificationType.warning,
            category: 'auction',
            tokenId: tokenId,
            saveToHistory: true,
          );
        }
      }
    }
  }

  // ── Core Logic (Bid Events) ───────────────────────────────────────────────

  void _onBidsUpdate(List<Bid> bids) {
    if (bids.isEmpty) return;

    final currentWallet =
        Web3Service.instance.currentAddress?.toLowerCase();

    final currentHighestBidder = bids.first.bidderWallet.toLowerCase();
    final currentHighestBid = bids.first.amount;
    
    // Check if user is seller
    final isSeller = _auction?.sellerWallet.toLowerCase() == currentWallet;

    // ── TRIGGER 13: New Bid Received On Your Auction (For Seller) ─────────
    if (isSeller && _lastBidCount > 0 && bids.length > _lastBidCount) {
      if (_canShow('new_bid_seller')) {
         NotificationManager.show(
           title: '🔔 New Bid Received',
           message: 'Someone placed a bid on your logo.\nCurrent Highest Bid: ${currentHighestBid.toStringAsFixed(4)} ETH',
           type: NotificationType.info,
           category: 'auction',
           tokenId: tokenId,
           saveToHistory: true,
         );
      }
    }

    // ── TRIGGER 5: New Bidder Joined ──────────────────────────────────────
    if (_lastBidCount > 0 && bids.length > _lastBidCount) {
      if (_canShow('new_bidder')) {
        NotificationManager.show(
          title: 'New Bidder Joined',
          message:
              'A new participant entered the auction.\nCurrent Bidders: ${bids.length}',
          type: NotificationType.info,
          category: 'auction',
          tokenId: tokenId,
          saveToHistory: false,
        );
      }
    }
    _lastBidCount = bids.length;

    // ── TRIGGER 6: Highest Bidder Changed ────────────────────────────────
    if (_lastHighestBidderWallet != null &&
        _lastHighestBidderWallet != currentHighestBidder) {
      if (currentWallet != null) {
        // TRIGGER 1: Current user was outbid
        if (_lastHighestBidderWallet == currentWallet) {
          if (_canShow('outbid')) {
            NotificationManager.show(
              title: '⚠ You have been outbid!',
              message:
                  'Current Highest Bid: ${currentHighestBid.toStringAsFixed(4)} ETH\nPlace a higher bid now.',
              type: NotificationType.warning,
              category: 'auction',
              tokenId: tokenId,
              saveToHistory: true,
            );
          }
        }
        // TRIGGER 2: Current user just became the highest bidder
        else if (currentHighestBidder == currentWallet) {
          if (_canShow('you_are_top')) {
            NotificationManager.show(
              title: '🏆 You are now the highest bidder!',
              message:
                  'Current Bid: ${currentHighestBid.toStringAsFixed(4)} ETH\nKeep your lead!',
              type: NotificationType.success,
              category: 'auction',
              tokenId: tokenId,
              saveToHistory: true,
            );
          }
        }
        // A third-party outbid — show general "new highest bid"
        else {
          if (_canShow('new_highest_bid')) {
            NotificationManager.show(
              title: 'New Highest Bid',
              message:
                  'New highest bid: ${currentHighestBid.toStringAsFixed(4)} ETH',
              type: NotificationType.info,
              category: 'auction',
              tokenId: tokenId,
              saveToHistory: false,
            );
          }
        }
      }
    }
    _lastHighestBidderWallet = currentHighestBidder;

    // ── TRIGGER 3 & 4: Rank Drop / Increase ─────────────────────────────────────────────
    if (currentWallet == null) return;

    int currentRank = -1;
    for (int i = 0; i < bids.length; i++) {
      if (bids[i].bidderWallet.toLowerCase() == currentWallet) {
        currentRank = i + 1;
        break;
      }
    }

    if (currentRank != -1) {
      final prevRank = _prevRank;
      if (prevRank != null && currentRank > prevRank) {
        // Rank dropped (higher number)
        if (_canShow('rank_drop')) {
          NotificationManager.show(
            title: '📉 Your ranking dropped',
            message:
                'Current Rank: #$currentRank\nPlace a higher bid to regain the lead.',
            type: NotificationType.warning,
            category: 'auction',
            tokenId: tokenId,
            saveToHistory: false,
          );
        }
      } else if (prevRank != null && currentRank < prevRank) {
        // Rank improved (lower number)
        if (_canShow('rank_increase')) {
          NotificationManager.show(
            title: '📈 Your ranking improved',
            message:
                'Current Rank: #$currentRank\nGreat job moving up!',
            type: NotificationType.success,
            category: 'auction',
            tokenId: tokenId,
            saveToHistory: false,
          );
        }
      }
      _prevRank = currentRank;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  int? _prevRank;

  /// Returns true if [key] notification can fire (10s cooldown).
  bool _canShow(String key) {
    final now = DateTime.now();
    if (_cooldowns.containsKey(key)) {
      if (now.difference(_cooldowns[key]!).inSeconds < 10) return false;
    }
    _cooldowns[key] = now;
    return true;
  }

  /// Returns true if [key] event has never been shown.
  bool _canShowEvent(String key) {
    if (_shownAuctionEvents.containsKey(key)) return false;
    _shownAuctionEvents[key] = DateTime.now();
    return true;
  }

  void _dispose() {
    _timer?.cancel();
    _bidSub?.cancel();
    _auctionSub?.cancel();
    _bidSub = null;
    _auctionSub = null;
    _timer = null;
    
    // Clear state
    _cooldowns.clear();
    _shownAuctionEvents.clear();
    _bids.clear();
    _auction = null;
    _prevRank = null;
    _lastBidCount = 0;
    _lastHighestBidderWallet = null;
  }
}
