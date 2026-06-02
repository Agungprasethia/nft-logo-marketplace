
/// Auction Status enum
enum AuctionStatus { draft, active, ended, endedNoBids, paymentPending, paymentCompleted, paymentExpired, claimed, failedPayment, frozen, cancelled, reAuctionRequested, rejected }

/// Auction model
class Auction {
  static const double defaultMinimumIncrement = 0.1;
  
  final int auctionId;
  final int tokenId;
  final String sellerId;
  final String sellerWallet;
  final double startingPrice;
  final double reservePrice;
  final double highestBid;
  final String? highestBidderId;
  final String? highestBidderWallet;
  final int totalBids;
  final DateTime startTime;
  final DateTime endTime;
  final AuctionStatus status;
  final DateTime createdAt;
  final DateTime? paymentDeadline;
  final DateTime? paymentCompletedAt;
  final DateTime? paymentExpiredAt;

  // In-memory bids list (populated from blockchain or Firestore)
  List<Bid> _bids;

  Auction({
    required this.auctionId,
    required this.tokenId,
    required this.sellerId,
    required this.sellerWallet,
    required this.startingPrice,
    this.reservePrice = 0.0,
    this.highestBid = 0.0,
    this.highestBidderId,
    this.highestBidderWallet,
    this.totalBids = 0,
    required this.startTime,
    required this.endTime,
    this.status = AuctionStatus.active,
    DateTime? createdAt,
    this.paymentDeadline,
    this.paymentCompletedAt,
    this.paymentExpiredAt,
    List<Bid>? bids,
    // Legacy parameters for backward compatibility
    String? seller,
    String? highestBidder,
    bool? isActive,
    bool? isEnded,
  })  : createdAt = createdAt ?? DateTime.now(),
        _bids = bids ?? [] {
    // If legacy 'seller' param is provided but sellerWallet is empty, use it
    // This handles construction from blockchain data
  }

  // ============ Backward-Compatible Getters ============
  // These allow pages/services using old property names to continue working

  /// Legacy getter: auction.seller → sellerWallet
  String get seller => sellerWallet;

  /// Legacy getter: auction.highestBidder → highestBidderWallet
  String? get highestBidder => highestBidderWallet;

  /// Legacy getter: auction.isEnded → status == ended
  bool get isEnded => status == AuctionStatus.ended;

  /// In-memory bids list (for blockchain-loaded bids)
  // ignore: unnecessary_getters_setters
  List<Bid> get bids => _bids;
  // ignore: unnecessary_getters_setters
  set bids(List<Bid> value) => _bids = value;

  // ============ Computed Properties ============

  /// Check if auction is still ongoing
  bool get isOngoing =>
      status == AuctionStatus.active && DateTime.now().isBefore(endTime);

  /// Time remaining
  Duration get timeRemaining {
    if (status != AuctionStatus.active) return Duration.zero;
    final remaining = endTime.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Format time remaining
  String get timeRemainingFormatted {
    final d = timeRemaining;
    if (d == Duration.zero) return 'Ended';
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    return '${d.inMinutes}m ${d.inSeconds % 60}s';
  }

  // ============ CopyWith ============

  Auction copyWith({
    int? auctionId,
    int? tokenId,
    String? sellerId,
    String? sellerWallet,
    double? startingPrice,
    double? reservePrice,
    double? highestBid,
    String? highestBidderId,
    String? highestBidderWallet,
    int? totalBids,
    DateTime? startTime,
    DateTime? endTime,
    AuctionStatus? status,
    DateTime? createdAt,
    DateTime? paymentDeadline,
    DateTime? paymentCompletedAt,
    DateTime? paymentExpiredAt,
    List<Bid>? bids,
  }) {
    return Auction(
      auctionId: auctionId ?? this.auctionId,
      tokenId: tokenId ?? this.tokenId,
      sellerId: sellerId ?? this.sellerId,
      sellerWallet: sellerWallet ?? this.sellerWallet,
      startingPrice: startingPrice ?? this.startingPrice,
      reservePrice: reservePrice ?? this.reservePrice,
      highestBid: highestBid ?? this.highestBid,
      highestBidderId: highestBidderId ?? this.highestBidderId,
      highestBidderWallet: highestBidderWallet ?? this.highestBidderWallet,
      totalBids: totalBids ?? this.totalBids,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      paymentDeadline: paymentDeadline ?? this.paymentDeadline,
      paymentCompletedAt: paymentCompletedAt ?? this.paymentCompletedAt,
      paymentExpiredAt: paymentExpiredAt ?? this.paymentExpiredAt,
      bids: bids ?? List<Bid>.from(_bids),
    );
  }

  // ============ Serialization ============

  static String statusToString(AuctionStatus status) {
    switch (status) {
      case AuctionStatus.draft:
        return 'draft';
      case AuctionStatus.active:
        return 'active';
      case AuctionStatus.ended:
        return 'ended';
      case AuctionStatus.endedNoBids:
        return 'ended_no_bids';
      case AuctionStatus.paymentPending:
        return 'payment_pending';
      case AuctionStatus.paymentCompleted:
        return 'payment_completed';
      case AuctionStatus.paymentExpired:
        return 'payment_expired';
      case AuctionStatus.claimed:
        return 'claimed';
      case AuctionStatus.failedPayment:
        return 'failed_payment';
      case AuctionStatus.frozen:
        return 'frozen';
      case AuctionStatus.cancelled:
        return 'cancelled';
      case AuctionStatus.reAuctionRequested:
        return 're_auction_requested';
      case AuctionStatus.rejected:
        return 'rejected';
    }
  }

  static AuctionStatus statusFromString(String status) {
    // Normalize to lowercase to handle Firestore uppercase values
    // (e.g., PAYMENT_PENDING, PAYMENT_COMPLETED, ENDED_NO_BIDS)
    final normalized = status.toLowerCase().trim();
    switch (normalized) {
      case 'draft':
        return AuctionStatus.draft;
      case 'ended':
        return AuctionStatus.ended;
      case 'ended_no_bids':
        return AuctionStatus.endedNoBids;
      case 'payment_pending':
        return AuctionStatus.paymentPending;
      case 'payment_completed':
        return AuctionStatus.paymentCompleted;
      case 'payment_expired':
        return AuctionStatus.paymentExpired;
      case 'claimed':
        return AuctionStatus.claimed;
      case 'failed_payment':
        return AuctionStatus.failedPayment;
      case 'frozen':
        return AuctionStatus.frozen;
      case 'cancelled':
        return AuctionStatus.cancelled;
      case 're_auction_requested':
        return AuctionStatus.reAuctionRequested;
      case 'rejected':
        return AuctionStatus.rejected;
      default:
        return AuctionStatus.active;
    }
  }

  Map<String, dynamic> toFirestore() {
    return {
      'auctionId': auctionId,
      'tokenId': tokenId,
      'sellerId': sellerId,
      'sellerWallet': sellerWallet,
      'startingPrice': startingPrice,
      'reservePrice': reservePrice,
      'highestBid': highestBid,
      'highestBidderId': highestBidderId,
      'highestBidderWallet': highestBidderWallet,
      'totalBids': totalBids,
      'startTime': startTime.millisecondsSinceEpoch,
      'endTime': endTime.millisecondsSinceEpoch,
      'status': statusToString(status),
      'createdAt': createdAt.millisecondsSinceEpoch,
      if (paymentDeadline != null) 'paymentDeadline': paymentDeadline!.millisecondsSinceEpoch,
      if (paymentCompletedAt != null) 'paymentCompletedAt': paymentCompletedAt!.millisecondsSinceEpoch,
      if (paymentExpiredAt != null) 'paymentExpiredAt': paymentExpiredAt!.millisecondsSinceEpoch,
    };
  }

  factory Auction.fromFirestore(Map<String, dynamic> data) {
    DateTime parsedStartTime = DateTime.now();
    if (data['startTime'] is int) {
      parsedStartTime =
          DateTime.fromMillisecondsSinceEpoch(data['startTime'] as int);
    } else if (data['startTime'] != null &&
        data['startTime'].runtimeType.toString() == 'Timestamp') {
      parsedStartTime = (data['startTime'] as dynamic).toDate();
    } else if (data['startTime'] is String) {
      parsedStartTime = DateTime.parse(data['startTime'] as String);
    }

    DateTime parsedEndTime = DateTime.now();
    if (data['endTime'] is int) {
      parsedEndTime =
          DateTime.fromMillisecondsSinceEpoch(data['endTime'] as int);
    } else if (data['endTime'] != null &&
        data['endTime'].runtimeType.toString() == 'Timestamp') {
      parsedEndTime = (data['endTime'] as dynamic).toDate();
    } else if (data['endTime'] is String) {
      parsedEndTime = DateTime.parse(data['endTime'] as String);
    }

    DateTime parsedCreatedAt = DateTime.now();
    if (data['createdAt'] is int) {
      parsedCreatedAt =
          DateTime.fromMillisecondsSinceEpoch(data['createdAt'] as int);
    } else if (data['createdAt'] != null &&
        data['createdAt'].runtimeType.toString() == 'Timestamp') {
      parsedCreatedAt = (data['createdAt'] as dynamic).toDate();
    } else if (data['createdAt'] is String) {
      parsedCreatedAt = DateTime.parse(data['createdAt'] as String);
    }

    DateTime? parsedPaymentDeadline;
    if (data['paymentDeadline'] is int) {
      parsedPaymentDeadline = DateTime.fromMillisecondsSinceEpoch(data['paymentDeadline'] as int);
    } else if (data['paymentDeadline'] != null && data['paymentDeadline'].runtimeType.toString() == 'Timestamp') {
      parsedPaymentDeadline = (data['paymentDeadline'] as dynamic).toDate();
    } else if (data['paymentDeadline'] is String) {
      parsedPaymentDeadline = DateTime.parse(data['paymentDeadline'] as String);
    }

    DateTime? parsedPaymentCompletedAt;
    if (data['paymentCompletedAt'] is int) {
      parsedPaymentCompletedAt = DateTime.fromMillisecondsSinceEpoch(data['paymentCompletedAt'] as int);
    } else if (data['paymentCompletedAt'] != null && data['paymentCompletedAt'].runtimeType.toString() == 'Timestamp') {
      parsedPaymentCompletedAt = (data['paymentCompletedAt'] as dynamic).toDate();
    } else if (data['paymentCompletedAt'] is String) {
      parsedPaymentCompletedAt = DateTime.parse(data['paymentCompletedAt'] as String);
    }

    DateTime? parsedPaymentExpiredAt;
    if (data['paymentExpiredAt'] is int) {
      parsedPaymentExpiredAt = DateTime.fromMillisecondsSinceEpoch(data['paymentExpiredAt'] as int);
    } else if (data['paymentExpiredAt'] != null && data['paymentExpiredAt'].runtimeType.toString() == 'Timestamp') {
      parsedPaymentExpiredAt = (data['paymentExpiredAt'] as dynamic).toDate();
    } else if (data['paymentExpiredAt'] is String) {
      parsedPaymentExpiredAt = DateTime.parse(data['paymentExpiredAt'] as String);
    }




    return Auction(
      auctionId: data['auctionId'] as int? ?? 0,
      tokenId: data['tokenId'] as int? ?? 0,
      sellerId: data['sellerId'] as String? ?? '',
      sellerWallet: data['sellerWallet'] as String? ??
          data['seller'] as String? ??
          '',
      startingPrice: (data['startingPrice'] as num?)?.toDouble() ?? 0.0,
      reservePrice: (data['reservePrice'] as num?)?.toDouble() ?? 0.0,
      highestBid: (data['highestBid'] as num?)?.toDouble() ?? 0.0,
      highestBidderId: data['highestBidderId'] as String?,
      highestBidderWallet: data['highestBidderWallet'] as String? ??
          data['highestBidder'] as String?,
      totalBids: data['totalBids'] as int? ?? 0,
      startTime: parsedStartTime,
      endTime: parsedEndTime,
      status: statusFromString(data['status'] as String? ?? 'active'),
      createdAt: parsedCreatedAt,
      paymentDeadline: parsedPaymentDeadline,
      paymentCompletedAt: parsedPaymentCompletedAt,
      paymentExpiredAt: parsedPaymentExpiredAt,
    );
  }

  /// Create Auction from blockchain data (legacy field names)
  factory Auction.fromBlockchain({
    required int auctionId,
    required int tokenId,
    required String seller,
    required double startingPrice,
    required double highestBid,
    String? highestBidder,
    required DateTime startTime,
    required DateTime endTime,
    required bool isActive,
    required bool isEnded,
    List<Bid>? bids,
    double reservePrice = 0.0,
  }) {
    AuctionStatus status;
    if (isEnded) {
      status = AuctionStatus.ended;
    } else if (isActive) {
      status = AuctionStatus.active;
    } else {
      status = AuctionStatus.cancelled;
    }

    return Auction(
      auctionId: auctionId,
      tokenId: tokenId,
      sellerId: '', // Not available from blockchain
      sellerWallet: seller,
      startingPrice: startingPrice,
      reservePrice: reservePrice,
      highestBid: highestBid,
      highestBidderId: null,
      highestBidderWallet: highestBidder,
      totalBids: bids?.length ?? 0,
      startTime: startTime,
      endTime: endTime,
      status: status,
      bids: bids,
    );
  }
}

/// Bid model for subcollection
///
/// Each bidder has ONE document per auction (keyed by wallet address).
/// - [firstBidTimestamp] is set once on the first bid and never changes (tie-breaker).
/// - [lastBidTimestamp] is updated every time the user rebids.
/// - [amount] always reflects the user's current (highest) bid.
class Bid {
  final String bidId;
  final String bidderId;
  final String bidderWallet;
  final double amount;
  final String? transactionHash;
  final DateTime firstBidTimestamp;
  final DateTime lastBidTimestamp;
  final bool isInvalidated;

  Bid({
    String? bidId,
    String? bidderId,
    required this.bidderWallet,
    required this.amount,
    this.transactionHash,
    DateTime? firstBidTimestamp,
    DateTime? lastBidTimestamp,
    // Legacy parameters for backward compat
    String? bidder,
    DateTime? timestamp,
    DateTime? createdAt,
    this.isInvalidated = false,
  })  : bidId = bidId ?? bidderWallet.toLowerCase(),
        bidderId = bidderId ?? '',
        firstBidTimestamp = firstBidTimestamp ?? createdAt ?? timestamp ?? DateTime.now(),
        lastBidTimestamp = lastBidTimestamp ?? DateTime.now();

  // ============ Backward-Compatible Getters ============

  /// Legacy getter: bid.bidder → bidderWallet
  String get bidder => bidderWallet;

  /// Legacy getter: bid.timestamp → firstBidTimestamp
  DateTime get timestamp => firstBidTimestamp;

  /// Legacy getter: bid.createdAt → firstBidTimestamp
  DateTime get createdAt => firstBidTimestamp;

  // ============ Computed Properties ============

  String get bidderShort {
    if (bidderWallet.length <= 10) return bidderWallet;
    return '${bidderWallet.substring(0, 6)}...${bidderWallet.substring(bidderWallet.length - 4)}';
  }

  // ============ CopyWith ============

  Bid copyWith({
    String? bidId,
    String? bidderId,
    String? bidderWallet,
    double? amount,
    String? transactionHash,
    DateTime? firstBidTimestamp,
    DateTime? lastBidTimestamp,
    bool? isInvalidated,
  }) {
    return Bid(
      bidId: bidId ?? this.bidId,
      bidderId: bidderId ?? this.bidderId,
      bidderWallet: bidderWallet ?? this.bidderWallet,
      amount: amount ?? this.amount,
      transactionHash: transactionHash ?? this.transactionHash,
      firstBidTimestamp: firstBidTimestamp ?? this.firstBidTimestamp,
      lastBidTimestamp: lastBidTimestamp ?? this.lastBidTimestamp,
      isInvalidated: isInvalidated ?? this.isInvalidated,
    );
  }

  // ============ Serialization ============

  Map<String, dynamic> toFirestore() {
    return {
      'bidId': bidId,
      'bidderId': bidderId,
      'bidderWallet': bidderWallet,
      'amount': amount,
      'transactionHash': transactionHash,
      'firstBidTimestamp': firstBidTimestamp.millisecondsSinceEpoch,
      'lastBidTimestamp': lastBidTimestamp.millisecondsSinceEpoch,
      'isInvalidated': isInvalidated,
      // Keep 'createdAt' for backward compat with existing data
      'createdAt': firstBidTimestamp.millisecondsSinceEpoch,
    };
  }

  factory Bid.fromFirestore(Map<String, dynamic> data) {
    // Parse firstBidTimestamp (fallback to legacy 'createdAt')
    DateTime parsedFirstBid = DateTime.now();
    if (data['firstBidTimestamp'] is int) {
      parsedFirstBid =
          DateTime.fromMillisecondsSinceEpoch(data['firstBidTimestamp'] as int);
    } else if (data['firstBidTimestamp'] != null &&
        data['firstBidTimestamp'].runtimeType.toString() == 'Timestamp') {
      parsedFirstBid = (data['firstBidTimestamp'] as dynamic).toDate();
    } else if (data['createdAt'] is int) {
      parsedFirstBid =
          DateTime.fromMillisecondsSinceEpoch(data['createdAt'] as int);
    } else if (data['createdAt'] != null &&
        data['createdAt'].runtimeType.toString() == 'Timestamp') {
      parsedFirstBid = (data['createdAt'] as dynamic).toDate();
    } else if (data['createdAt'] is String) {
      parsedFirstBid = DateTime.parse(data['createdAt'] as String);
    }

    // Parse lastBidTimestamp (fallback to firstBidTimestamp)
    DateTime parsedLastBid = parsedFirstBid;
    if (data['lastBidTimestamp'] is int) {
      parsedLastBid =
          DateTime.fromMillisecondsSinceEpoch(data['lastBidTimestamp'] as int);
    } else if (data['lastBidTimestamp'] != null &&
        data['lastBidTimestamp'].runtimeType.toString() == 'Timestamp') {
      parsedLastBid = (data['lastBidTimestamp'] as dynamic).toDate();
    }

    return Bid(
      bidId: data['bidId'] as String? ?? '',
      bidderId: data['bidderId'] as String? ?? '',
      bidderWallet: data['bidderWallet'] as String? ??
          data['bidder'] as String? ??
          '',
      amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
      transactionHash: data['transactionHash'] as String?,
      firstBidTimestamp: parsedFirstBid,
      lastBidTimestamp: parsedLastBid,
      isInvalidated: data['isInvalidated'] as bool? ?? false,
    );
  }

  /// Create Bid from blockchain tuple data
  factory Bid.fromBlockchain({
    required String bidder,
    required double amount,
    required DateTime timestamp,
  }) {
    return Bid(
      bidId: bidder.toLowerCase(),
      bidderId: '',
      bidderWallet: bidder,
      amount: amount,
      firstBidTimestamp: timestamp,
      lastBidTimestamp: timestamp,
    );
  }
}
