import 'package:cloud_firestore/cloud_firestore.dart';

/// Logo NFT Validation Status mapping to Smart Contract Enum
enum ValidationStatus { pending, approvedPendingMint, approved, rejected, disabled, auction, available, pendingPayment, sold, underReview, frozenAuction, copyrightViolation }

/// Available NFT categories
class NFTCategory {
  static const String all = 'All';
  static const String technology = 'Technology';
  static const String foodBeverage = 'Food & Beverage';
  static const String fashion = 'Fashion';
  static const String gaming = 'Gaming';
  static const String education = 'Education';
  static const String corporate = 'Corporate';

  static const List<String> values = [
    technology,
    foodBeverage,
    fashion,
    gaming,
    education,
    corporate,
  ];

  /// All categories including "All" for filter UI
  static const List<String> filterValues = [
    all,
    technology,
    foodBeverage,
    fashion,
    gaming,
    education,
    corporate,
  ];
}

/// Logo NFT model
class LogoNFT {
  final int tokenId;
  final String name;
  final String description;
  final String imageUrl;
  final String imageHash;
  final String creatorId;
  final String creatorWallet;
  final String? creatorUsername;
  final String ownerId;
  final String ownerWallet;
  final DateTime createdAt;
  final double price;
  final bool isForSale;
  final bool isInAuction;
  final ValidationStatus status;
  final String? txHash;
  final String? metadataUrl;
  final String category;
  final bool auctionCreated;
  final bool isActive;
  final int? auctionDuration; // Duration in seconds, set by creator during mint
  final String? approvedBy;
  final DateTime? approvedAt;
  final DateTime? startTime;
  final DateTime? endTime;
  final DateTime? paymentDeadline;
  final DateTime? paymentCompletedAt;
  final DateTime? paymentExpiredAt;
  final bool isAuctionActive;
  final bool isFrozen;
  final DateTime? frozenAt;
  final int? frozenRemainingSeconds;
  final double highestBid;
  final String? highestBidderId;
  final String? highestBidderWallet;
  final int totalBids;
  final String? auctionStatus; // e.g., 'ENDED_NO_BID', 'PAYMENT_PENDING', 'CLAIMED', 'SOLD', 'RE_AUCTION_REQUESTED'
  final int auctionCount;
  final double? previousFinalBid;
  final String? previousWinnerWallet;
  final List<dynamic>? auctionHistory;
  final String? copyrightHash;
  final String? hashAlgorithm;
  final DateTime? copyrightVerifiedAt;
  final bool isAppealed;
  final double? reAuctionStartingPrice;
  final String? reAuctionNotes;
  final String? ownershipType;
  final int? reAuctionDuration;
  final bool nftVisible;
  final bool isPaymentProcessing;
  final bool isMetadataLocked;
  final String? rejectedReason;
  
  // Dispute & Appeal fields
  final String? previousStatus;
  final String? freezeReason;
  final String? decisionReason;
  final List<String>? evidenceFiles;

  LogoNFT({
    required this.tokenId,
    required this.name,
    required this.description,
    required this.imageUrl,
    required this.imageHash,
    required this.creatorId,
    required String creatorWallet,
    this.creatorUsername,
    required this.ownerId,
    required String ownerWallet,
    required this.createdAt,
    required this.price,
    this.isForSale = false,
    this.isInAuction = false,
    this.status = ValidationStatus.pending,
    this.txHash,
    this.metadataUrl,
    this.category = 'Technology',
    this.auctionCreated = false,
    this.isActive = true,
    this.auctionDuration,
    this.approvedBy,
    this.approvedAt,
    this.startTime,
    this.endTime,
    this.paymentDeadline,
    this.paymentCompletedAt,
    this.paymentExpiredAt,
    this.isAuctionActive = false,
    this.isFrozen = false,
    this.frozenAt,
    this.frozenRemainingSeconds,
    this.highestBid = 0.0,
    this.highestBidderId,
    this.highestBidderWallet,
    this.totalBids = 0,
    this.auctionStatus,
    this.auctionCount = 0,
    this.previousFinalBid,
    this.previousWinnerWallet,
    this.auctionHistory,
    this.copyrightHash,
    this.hashAlgorithm,
    this.copyrightVerifiedAt,
    this.isAppealed = false,
    this.reAuctionStartingPrice,
    this.reAuctionDuration,
    this.reAuctionNotes,
    this.ownershipType,
    this.nftVisible = false,
    this.isPaymentProcessing = false,
    this.isMetadataLocked = false,
    this.rejectedReason,
    this.previousStatus,
    this.freezeReason,
    this.decisionReason,
    this.evidenceFiles,
  }) : creatorWallet = creatorWallet.toLowerCase().trim(),
       ownerWallet = ownerWallet.toLowerCase().trim();

  LogoNFT copyWith({
    int? tokenId,
    String? name,
    String? description,
    String? imageUrl,
    String? imageHash,
    String? creatorId,
    String? creatorWallet,
    String? creatorUsername,
    String? ownerId,
    String? ownerWallet,
    DateTime? createdAt,
    double? price,
    bool? isForSale,
    bool? isInAuction,
    ValidationStatus? status,
    String? txHash,
    String? metadataUrl,
    String? category,
    bool? auctionCreated,
    bool? isActive,
    int? auctionDuration,
    String? approvedBy,
    DateTime? approvedAt,
    DateTime? startTime,
    DateTime? endTime,
    DateTime? paymentDeadline,
    DateTime? paymentCompletedAt,
    DateTime? paymentExpiredAt,
    bool? isAuctionActive,
    bool? isFrozen,
    DateTime? frozenAt,
    int? frozenRemainingSeconds,
    double? highestBid,
    String? highestBidderId,
    String? highestBidderWallet,
    int? totalBids,
    String? auctionStatus,
    int? auctionCount,
    double? previousFinalBid,
    String? previousWinnerWallet,
    List<dynamic>? auctionHistory,
    String? copyrightHash,
    String? hashAlgorithm,
    DateTime? copyrightVerifiedAt,
    bool? isAppealed,
    double? reAuctionStartingPrice,
    int? reAuctionDuration,
    String? reAuctionNotes,
    String? ownershipType,
    bool? nftVisible,
    bool? isPaymentProcessing,
    bool? isMetadataLocked,
    String? rejectedReason,
    String? previousStatus,
    String? freezeReason,
    String? decisionReason,
    List<String>? evidenceFiles,
  }) {
    return LogoNFT(
      tokenId: tokenId ?? this.tokenId,
      name: name ?? this.name,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      imageHash: imageHash ?? this.imageHash,
      creatorId: creatorId ?? this.creatorId,
      creatorWallet: creatorWallet ?? this.creatorWallet,
      creatorUsername: creatorUsername ?? this.creatorUsername,
      ownerId: ownerId ?? this.ownerId,
      ownerWallet: ownerWallet ?? this.ownerWallet,
      createdAt: createdAt ?? this.createdAt,
      price: price ?? this.price,
      isForSale: isForSale ?? this.isForSale,
      isInAuction: isInAuction ?? this.isInAuction,
      status: status ?? this.status,
      txHash: txHash ?? this.txHash,
      metadataUrl: metadataUrl ?? this.metadataUrl,
      category: category ?? this.category,
      auctionCreated: auctionCreated ?? this.auctionCreated,
      isActive: isActive ?? this.isActive,
      auctionDuration: auctionDuration ?? this.auctionDuration,
      approvedBy: approvedBy ?? this.approvedBy,
      approvedAt: approvedAt ?? this.approvedAt,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      paymentDeadline: paymentDeadline ?? this.paymentDeadline,
      paymentCompletedAt: paymentCompletedAt ?? this.paymentCompletedAt,
      paymentExpiredAt: paymentExpiredAt ?? this.paymentExpiredAt,
      isAuctionActive: isAuctionActive ?? this.isAuctionActive,
      isFrozen: isFrozen ?? this.isFrozen,
      frozenAt: frozenAt ?? this.frozenAt,
      frozenRemainingSeconds: frozenRemainingSeconds ?? this.frozenRemainingSeconds,
      highestBid: highestBid ?? this.highestBid,
      highestBidderId: highestBidderId ?? this.highestBidderId,
      highestBidderWallet: highestBidderWallet ?? this.highestBidderWallet,
      totalBids: totalBids ?? this.totalBids,
      auctionStatus: auctionStatus ?? this.auctionStatus,
      auctionCount: auctionCount ?? this.auctionCount,
      previousFinalBid: previousFinalBid ?? this.previousFinalBid,
      previousWinnerWallet: previousWinnerWallet ?? this.previousWinnerWallet,
      auctionHistory: auctionHistory ?? this.auctionHistory,
      copyrightHash: copyrightHash ?? this.copyrightHash,
      hashAlgorithm: hashAlgorithm ?? this.hashAlgorithm,
      copyrightVerifiedAt: copyrightVerifiedAt ?? this.copyrightVerifiedAt,
      isAppealed: isAppealed ?? this.isAppealed,
      reAuctionStartingPrice: reAuctionStartingPrice ?? this.reAuctionStartingPrice,
      reAuctionDuration: reAuctionDuration ?? this.reAuctionDuration,
      reAuctionNotes: reAuctionNotes ?? this.reAuctionNotes,
      ownershipType: ownershipType ?? this.ownershipType,
      nftVisible: nftVisible ?? this.nftVisible,
      isPaymentProcessing: isPaymentProcessing ?? this.isPaymentProcessing,
      isMetadataLocked: isMetadataLocked ?? this.isMetadataLocked,
      rejectedReason: rejectedReason ?? this.rejectedReason,
      previousStatus: previousStatus ?? this.previousStatus,
      freezeReason: freezeReason ?? this.freezeReason,
      decisionReason: decisionReason ?? this.decisionReason,
      evidenceFiles: evidenceFiles ?? this.evidenceFiles,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tokenId': tokenId,
      'name': name,
      'description': description,
      'imageUrl': imageUrl,
      'imageHash': imageHash,
      'creatorId': creatorId,
      'creatorWallet': creatorWallet,
      if (creatorUsername != null) 'creatorUsername': creatorUsername,
      'ownerId': ownerId,
      'ownerWallet': ownerWallet,
      'createdAt': createdAt.toIso8601String(),
      'price': price,
      'isForSale': isForSale,
      'isInAuction': isInAuction,
      'status': status.index,
      'txHash': txHash,
      'metadataUrl': metadataUrl,
      'category': category,
      'auctionCreated': auctionCreated,
      'isActive': isActive,
      'auctionDuration': auctionDuration,
      'approvedBy': approvedBy,
      'approvedAt': approvedAt?.toIso8601String(),
      'startTime': startTime?.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      if (paymentDeadline != null) 'paymentDeadline': paymentDeadline!.toIso8601String(),
      if (paymentCompletedAt != null) 'paymentCompletedAt': paymentCompletedAt!.toIso8601String(),
      if (paymentExpiredAt != null) 'paymentExpiredAt': paymentExpiredAt!.toIso8601String(),
      'isAuctionActive': isAuctionActive,
      'isFrozen': isFrozen,
      'frozenAt': frozenAt?.toIso8601String(),
      'frozenRemainingSeconds': frozenRemainingSeconds,
      'highestBid': highestBid,
      'highestBidderId': highestBidderId,
      'highestBidderWallet': highestBidderWallet,
      'totalBids': totalBids,
      'auctionStatus': auctionStatus,
      'auctionCount': auctionCount,
      'previousFinalBid': previousFinalBid,
      'previousWinnerWallet': previousWinnerWallet,
      'auctionHistory': auctionHistory,
      if (copyrightHash != null) 'copyrightHash': copyrightHash,
      if (hashAlgorithm != null) 'hashAlgorithm': hashAlgorithm,
      if (copyrightVerifiedAt != null) 'copyrightVerifiedAt': copyrightVerifiedAt!.toIso8601String(),
      'isAppealed': isAppealed,
      'reAuctionStartingPrice': reAuctionStartingPrice,
      'reAuctionDuration': reAuctionDuration,
      'reAuctionNotes': reAuctionNotes,
      'ownershipType': ownershipType,
      'nftVisible': nftVisible,
      'isPaymentProcessing': isPaymentProcessing,
      'isMetadataLocked': isMetadataLocked,
      if (rejectedReason != null) 'rejectedReason': rejectedReason,
    };
  }

  /// Parse status from either int (toJson format) or String (toFirestore format)
  static ValidationStatus _parseValidationStatus(dynamic value) {
    if (value == null) return ValidationStatus.pending;
    if (value is int) {
      return (value >= 0 && value < ValidationStatus.values.length)
          ? ValidationStatus.values[value]
          : ValidationStatus.pending;
    }
    if (value is String) return statusFromString(value);
    return ValidationStatus.pending;
  }

  /// Parse DateTime from either int (milliseconds) or String (ISO8601)
  static DateTime _parseDateTimeFlex(dynamic value, {DateTime? fallback}) {
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(
        value < 10000000000 ? value * 1000 : value,
      );
    }
    if (value is String) return DateTime.parse(value);
    if (value is Map) {
      final seconds = value['_seconds'] as int?;
      if (seconds != null) {
        return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
      }
    }
    return fallback ?? DateTime.now();
  }

  static DateTime? _parseDateTimeFlexNullable(dynamic value) {
    if (value == null) return null;
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(
        value < 10000000000 ? value * 1000 : value,
      );
    }
    if (value is String) return DateTime.parse(value);
    if (value is Map) {
      final seconds = value['_seconds'] as int?;
      if (seconds != null) {
        return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
      }
    }
    return null;
  }

  factory LogoNFT.fromJson(Map<String, dynamic> json) {
    return LogoNFT(
      tokenId: json['tokenId'] as int? ?? 0,
      name: json['name'] as String? ?? 'Unnamed NFT',
      description: json['description'] as String? ?? '',
      imageUrl: json['imageUrl'] as String? ?? '',
      imageHash: json['imageHash'] as String? ?? '',
      creatorId: json['creatorId'] as String? ?? '',
      creatorWallet: json['creatorWallet'] as String? ?? json['creator'] as String? ?? '',
      creatorUsername: json['creatorUsername'] as String?,
      ownerId: json['ownerId'] as String? ?? '',
      ownerWallet: json['ownerWallet'] as String? ?? json['owner'] as String? ?? '',
      createdAt: _parseDateTimeFlex(json['createdAt']),
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      isForSale: json['isForSale'] as bool? ?? false,
      isInAuction: json['isInAuction'] as bool? ?? false,
      status: _parseValidationStatus(json['status']),
      txHash: json['txHash'] as String?,
      metadataUrl: json['metadataUrl'] as String?,
      category: json['category'] as String? ?? 'Technology',
      auctionCreated: json['auctionCreated'] as bool? ?? false,
      isActive: json['isActive'] as bool? ?? true,
      auctionDuration: json['auctionDuration'] as int?,
      approvedBy: json['approvedBy'] as String?,
      approvedAt: _parseDateTimeFlexNullable(json['approvedAt']),
      startTime: _parseDateTimeFlexNullable(json['startTime']),
      endTime: _parseDateTimeFlexNullable(json['endTime']),
      paymentDeadline: _parseDateTimeFlexNullable(json['paymentDeadline']),
      paymentCompletedAt: _parseDateTimeFlexNullable(json['paymentCompletedAt']),
      paymentExpiredAt: _parseDateTimeFlexNullable(json['paymentExpiredAt']),
      isAuctionActive: json['isAuctionActive'] as bool? ?? false,
      isFrozen: json['isFrozen'] as bool? ?? false,
      frozenAt: _parseDateTimeFlexNullable(json['frozenAt']),
      frozenRemainingSeconds: json['frozenRemainingSeconds'] as int?,
      highestBid: (json['highestBid'] as num?)?.toDouble() ?? 0.0,
      highestBidderId: json['highestBidderId'] as String?,
      highestBidderWallet: json['highestBidderWallet'] as String?,
      totalBids: json['totalBids'] as int? ?? 0,
      auctionStatus: json['auctionStatus'] as String?,
      auctionCount: json['auctionCount'] as int? ?? 0,
      previousFinalBid: (json['previousFinalBid'] as num?)?.toDouble(),
      previousWinnerWallet: json['previousWinnerWallet'] as String?,
      auctionHistory: json['auctionHistory'] as List<dynamic>?,
      copyrightHash: json['copyrightHash'] as String?,
      hashAlgorithm: json['hashAlgorithm'] as String?,
      copyrightVerifiedAt: _parseDateTimeFlexNullable(json['copyrightVerifiedAt']),
      isAppealed: json['isAppealed'] as bool? ?? false,
      reAuctionStartingPrice: (json['reAuctionStartingPrice'] as num?)?.toDouble(),
      reAuctionDuration: json['reAuctionDuration'] as int?,
      reAuctionNotes: json['reAuctionNotes'] as String?,
      ownershipType: json['ownershipType'] as String?,
      nftVisible: json['nftVisible'] as bool? ?? true,
      isPaymentProcessing: json['isPaymentProcessing'] as bool? ?? false,
      isMetadataLocked: json['isMetadataLocked'] as bool? ?? false,
      rejectedReason: json['rejectedReason'] as String?,
      previousStatus: json['previousStatus'] as String?,
      freezeReason: json['freezeReason'] as String?,
      decisionReason: json['decisionReason'] as String?,
      evidenceFiles: (json['evidenceFiles'] as List<dynamic>?)?.map((e) => e.toString()).toList(),
    );
  }


  // ============ Backward-Compatible Getters ============
  /// Legacy getter: logo.creator → creatorWallet
  String get creator => creatorWallet;

  /// Legacy getter: logo.owner → ownerWallet
  String get owner => ownerWallet;

  /// Format address for display (0x1234...5678)
  String get creatorShort => _shortenAddress(creatorWallet);
  String get ownerShort => _shortenAddress(ownerWallet);

  String _shortenAddress(String address) {
    if (address.length <= 10) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
  }

  /// STRICT ACCESS CONTROL HELPERS
  bool canViewCopyrightHash({
    required String currentWallet,
  }) {
    final normalizedCurrent = currentWallet.toLowerCase().trim();

    final isCreator =
        creatorWallet.toLowerCase().trim() == normalizedCurrent;

    final isOwner =
        ownerWallet.toLowerCase().trim() == normalizedCurrent;

    final hasCompletedPayment =
        auctionStatus == 'PAYMENT_COMPLETED';

    return isCreator || (isOwner && hasCompletedPayment);
  }

  bool canViewCurrentOwner({
    required String currentWallet,
  }) {
    final normalizedCurrent = currentWallet.toLowerCase().trim();

    final isCreator = creatorWallet.toLowerCase().trim() == normalizedCurrent;
    final isOwner = ownerWallet.toLowerCase().trim() == normalizedCurrent;
    final isCompleted = auctionStatus == 'PAYMENT_COMPLETED' || auctionStatus == 'CLAIMED' || ownershipType == 'collected' || (ownerWallet.isNotEmpty && ownerWallet.toLowerCase().trim() != creatorWallet.toLowerCase().trim());

    return isCreator || isOwner || isCompleted;
  }

  // ============ Firestore Serialization ============

  /// Convert ValidationStatus enum to Firestore-friendly string
  static String statusToString(ValidationStatus status) {
    switch (status) {
      case ValidationStatus.pending: return 'pending';
      case ValidationStatus.approvedPendingMint: return 'approved_pending_mint';
      case ValidationStatus.approved: return 'approved';
      case ValidationStatus.rejected: return 'rejected';
      case ValidationStatus.disabled: return 'disabled';
      case ValidationStatus.auction: return 'auction';
      case ValidationStatus.available: return 'available';
      case ValidationStatus.pendingPayment: return 'payment_pending';
      case ValidationStatus.sold: return 'sold';
      case ValidationStatus.underReview: return 'under_review';
      case ValidationStatus.frozenAuction: return 'frozen_auction';
      case ValidationStatus.copyrightViolation: return 'copyright_violation';
    }
  }

  /// Convert Firestore string back to ValidationStatus enum
  static ValidationStatus statusFromString(String status) {
    switch (status.toLowerCase()) {
      case 'approved_pending_mint': return ValidationStatus.approvedPendingMint;
      case 'approved': return ValidationStatus.approved;
      case 'rejected': return ValidationStatus.rejected;
      case 'disabled': return ValidationStatus.disabled;
      case 'auction': return ValidationStatus.auction;
      case 'available': return ValidationStatus.available;
      case 'payment_pending': return ValidationStatus.pendingPayment;
      case 'pending_payment': return ValidationStatus.pendingPayment;
      case 'sold': return ValidationStatus.sold;
      case 'under_review': return ValidationStatus.underReview;
      case 'frozen_auction': return ValidationStatus.frozenAuction;
      case 'copyright_violation': return ValidationStatus.copyrightViolation;
      default: return ValidationStatus.pending;
    }
  }

  /// Serialize to Firestore document fields
  Map<String, dynamic> toFirestore() {
    return {
      'tokenId': tokenId,
      'name': name,
      'description': description,
      'imageUrl': imageUrl,
      'imageHash': imageHash,
      'creatorId': creatorId,
      'creatorWallet': creatorWallet,
      if (creatorUsername != null) 'creatorUsername': creatorUsername,
      'ownerId': ownerId,
      'ownerWallet': ownerWallet,
      'price': price,
      'category': category,
      'status': statusToString(status),
      'txHash': txHash,
      'metadataUrl': metadataUrl,
      'isForSale': isForSale,
      'isInAuction': isInAuction,
      'auctionCreated': auctionCreated,
      'isActive': isActive,
      'auctionDuration': auctionDuration,
      'approvedBy': approvedBy,
      'approvedAt': approvedAt?.millisecondsSinceEpoch,
      'startTime': startTime?.millisecondsSinceEpoch,
      'endTime': endTime?.millisecondsSinceEpoch,
      if (paymentDeadline != null) 'paymentDeadline': paymentDeadline!.millisecondsSinceEpoch,
      if (paymentCompletedAt != null) 'paymentCompletedAt': paymentCompletedAt!.millisecondsSinceEpoch,
      if (paymentExpiredAt != null) 'paymentExpiredAt': paymentExpiredAt!.millisecondsSinceEpoch,
      'isAuctionActive': isAuctionActive,
      'isFrozen': isFrozen,
      'frozenAt': frozenAt?.millisecondsSinceEpoch,
      'frozenRemainingSeconds': frozenRemainingSeconds,
      'highestBid': highestBid,
      'highestBidderId': highestBidderId,
      'highestBidderWallet': highestBidderWallet,
      'totalBids': totalBids,
      'auctionStatus': auctionStatus,
      'auctionCount': auctionCount,
      'previousFinalBid': previousFinalBid,
      'previousWinnerWallet': previousWinnerWallet,
      'auctionHistory': auctionHistory,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'copyrightHash': copyrightHash,
      'hashAlgorithm': hashAlgorithm,
      'copyrightVerifiedAt': copyrightVerifiedAt?.millisecondsSinceEpoch,
      'reAuctionStartingPrice': reAuctionStartingPrice,
      'reAuctionDuration': reAuctionDuration,
      'reAuctionNotes': reAuctionNotes,
      'ownershipType': ownershipType,
      'nftVisible': nftVisible,
      'isPaymentProcessing': isPaymentProcessing,
      'isMetadataLocked': isMetadataLocked,
      if (rejectedReason != null) 'rejectedReason': rejectedReason,
    };
  }

  /// Create LogoNFT from Firestore document data
  factory LogoNFT.fromFirestore(Map<String, dynamic> data) {
    DateTime parsedCreatedAt = DateTime.now();
    if (data['createdAt'] is int) {
      parsedCreatedAt = DateTime.fromMillisecondsSinceEpoch(data['createdAt'] as int);
    } else if (data['createdAt'] is Timestamp) {
      parsedCreatedAt = (data['createdAt'] as Timestamp).toDate();
    }
    
    DateTime? parsedApprovedAt;
    if (data['approvedAt'] is int) {
      parsedApprovedAt = DateTime.fromMillisecondsSinceEpoch(data['approvedAt'] as int);
    } else if (data['approvedAt'] is Timestamp) {
      parsedApprovedAt = (data['approvedAt'] as Timestamp).toDate();
    }

    DateTime? parsedStartTime;
    if (data['startTime'] is int) {
      parsedStartTime = DateTime.fromMillisecondsSinceEpoch(data['startTime'] as int);
    } else if (data['startTime'] is Timestamp) {
      parsedStartTime = (data['startTime'] as Timestamp).toDate();
    }

    DateTime? parsedEndTime;
    if (data['endTime'] is int) {
      final raw = data['endTime'] as int;
      parsedEndTime = DateTime.fromMillisecondsSinceEpoch(raw < 10000000000 ? raw * 1000 : raw);
    } else if (data['endTime'] is Timestamp) {
      parsedEndTime = (data['endTime'] as Timestamp).toDate();
    } else if (data['endTime'] is Map) {
      final seconds = data['endTime']['_seconds'] as int?;
      if (seconds != null) {
        parsedEndTime = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
      }
    }

    DateTime? parsedPaymentDeadline;
    if (data['paymentDeadline'] is int) {
      parsedPaymentDeadline = DateTime.fromMillisecondsSinceEpoch(data['paymentDeadline'] as int);
    } else if (data['paymentDeadline'] is Timestamp) {
      parsedPaymentDeadline = (data['paymentDeadline'] as Timestamp).toDate();
    }

    DateTime? parsedPaymentCompletedAt;
    if (data['paymentCompletedAt'] is int) {
      parsedPaymentCompletedAt = DateTime.fromMillisecondsSinceEpoch(data['paymentCompletedAt'] as int);
    } else if (data['paymentCompletedAt'] is Timestamp) {
      parsedPaymentCompletedAt = (data['paymentCompletedAt'] as Timestamp).toDate();
    }

    DateTime? parsedPaymentExpiredAt;
    if (data['paymentExpiredAt'] is int) {
      parsedPaymentExpiredAt = DateTime.fromMillisecondsSinceEpoch(data['paymentExpiredAt'] as int);
    } else if (data['paymentExpiredAt'] is Timestamp) {
      parsedPaymentExpiredAt = (data['paymentExpiredAt'] as Timestamp).toDate();
    }

    DateTime? parsedCopyrightVerifiedAt;
    if (data['copyrightVerifiedAt'] is int) {
      parsedCopyrightVerifiedAt = DateTime.fromMillisecondsSinceEpoch(data['copyrightVerifiedAt'] as int);
    } else if (data['copyrightVerifiedAt'] is Timestamp) {
      parsedCopyrightVerifiedAt = (data['copyrightVerifiedAt'] as Timestamp).toDate();
    }

    DateTime? parsedFrozenAt;
    if (data['frozenAt'] is int) {
      parsedFrozenAt = DateTime.fromMillisecondsSinceEpoch(data['frozenAt'] as int);
    } else if (data['frozenAt'] is Timestamp) {
      parsedFrozenAt = (data['frozenAt'] as Timestamp).toDate();
    }


    final String name = data['name'] as String? ?? 'Unnamed NFT';
    final String imageUrl = data['imageUrl'] as String? ?? '';
    final String creatorWallet = data['creatorWallet'] as String? ?? data['creator'] as String? ?? '';
    final String? creatorUsername = data['creatorUsername'] as String?;
    final String ownerWallet = data['ownerWallet'] as String? ?? data['owner'] as String? ?? '';
    final String creatorId = data['creatorId'] as String? ?? '';
    final String ownerId = data['ownerId'] as String? ?? '';
    final String statusStr = data['status'] as String? ?? 'pending';

    return LogoNFT(
      tokenId: data['tokenId'] as int? ?? 0,
      name: name,
      description: data['description'] as String? ?? '',
      imageUrl: imageUrl,
      imageHash: data['imageHash'] as String? ?? '',
      creatorId: creatorId,
      creatorWallet: creatorWallet.toLowerCase().trim(),
      creatorUsername: creatorUsername,
      ownerId: ownerId,
      ownerWallet: ownerWallet.toLowerCase().trim(),
      createdAt: parsedCreatedAt,
      price: (data['price'] as num?)?.toDouble() ?? 0.0,
      isForSale: data['isForSale'] as bool? ?? false,
      isInAuction: data['isInAuction'] as bool? ?? false,
      status: statusFromString(statusStr),
      txHash: data['txHash'] as String?,
      metadataUrl: data['metadataUrl'] as String?,
      category: data['category'] as String? ?? 'Technology',
      auctionCreated: data['auctionCreated'] as bool? ?? false,
      isActive: data['isActive'] as bool? ?? true,
      auctionDuration: data['auctionDuration'] as int?,
      approvedBy: data['approvedBy'] as String?,
      approvedAt: parsedApprovedAt,
      startTime: parsedStartTime,
      endTime: parsedEndTime,
      paymentDeadline: parsedPaymentDeadline,
      paymentCompletedAt: parsedPaymentCompletedAt,
      paymentExpiredAt: parsedPaymentExpiredAt,
      isAuctionActive: data['isAuctionActive'] as bool? ?? false,
      isFrozen: data['isFrozen'] as bool? ?? false,
      frozenAt: parsedFrozenAt,
      frozenRemainingSeconds: data['frozenRemainingSeconds'] as int?,
      highestBid: (data['highestBid'] as num?)?.toDouble() ?? 0.0,
      highestBidderId: data['highestBidderId'] as String?,
      highestBidderWallet: data['highestBidderWallet'] as String?,
      totalBids: data['totalBids'] as int? ?? 0,
      auctionStatus: data['auctionStatus'] as String?,
      auctionCount: data['auctionCount'] as int? ?? 0,
      previousFinalBid: (data['previousFinalBid'] as num?)?.toDouble(),
      previousWinnerWallet: data['previousWinnerWallet'] as String?,
      auctionHistory: data['auctionHistory'] as List<dynamic>?,
      copyrightHash: data['copyrightHash'] as String?,
      hashAlgorithm: data['hashAlgorithm'] as String?,
      copyrightVerifiedAt: parsedCopyrightVerifiedAt,
      reAuctionStartingPrice: (data['reAuctionStartingPrice'] as num?)?.toDouble(),
      reAuctionDuration: data['reAuctionDuration'] as int?,
      reAuctionNotes: data['reAuctionNotes'] as String?,
      ownershipType: data['ownershipType'] as String?,
      nftVisible: data['nftVisible'] as bool? ?? true, // Legacy visible fallback
      isPaymentProcessing: data['isPaymentProcessing'] as bool? ?? false,
      isMetadataLocked: data['isMetadataLocked'] as bool? ?? false,
      rejectedReason: data['rejectedReason'] as String?,
      previousStatus: data['previousStatus'] as String?,
      freezeReason: data['freezeReason'] as String?,
      decisionReason: data['decisionReason'] as String?,
      evidenceFiles: (data['evidenceFiles'] as List<dynamic>?)?.map((e) => e.toString()).toList(),
    );
  }
}
