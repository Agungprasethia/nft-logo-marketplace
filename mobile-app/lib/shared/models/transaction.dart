enum TransactionType { mint, bid, sale, transfer, approval }
enum TransactionStatus { pending, success, failed }

class TransactionModel {
  final String transactionId;
  final String nftId; // string representation of tokenId, or actual string ID if applicable
  final String? auctionId;
  final String? sellerId;
  final String? buyerId;
  final String? sellerWallet;
  final String? buyerWallet;
  final double amount;
  final String? transactionHash;
  final TransactionType type;
  final TransactionStatus status;
  final String? failureReason;
  final DateTime createdAt;
  final DateTime? confirmedAt;
  final int? blockNumber;

  TransactionModel({
    required this.transactionId,
    required this.nftId,
    this.auctionId,
    this.sellerId,
    this.buyerId,
    this.sellerWallet,
    this.buyerWallet,
    required this.amount,
    this.transactionHash,
    required this.type,
    this.status = TransactionStatus.pending,
    this.failureReason,
    DateTime? createdAt,
    this.confirmedAt,
    this.blockNumber,
  }) : createdAt = createdAt ?? DateTime.now();

  static String typeToString(TransactionType type) {
    switch (type) {
      case TransactionType.mint: return 'mint';
      case TransactionType.bid: return 'bid';
      case TransactionType.sale: return 'sale';
      case TransactionType.transfer: return 'transfer';
      case TransactionType.approval: return 'approval';
    }
  }

  static TransactionType typeFromString(String type) {
    switch (type) {
      case 'mint': return TransactionType.mint;
      case 'bid': return TransactionType.bid;
      case 'sale': return TransactionType.sale;
      case 'transfer': return TransactionType.transfer;
      case 'approval': return TransactionType.approval;
      default: return TransactionType.transfer;
    }
  }

  static String statusToString(TransactionStatus status) {
    switch (status) {
      case TransactionStatus.pending: return 'pending';
      case TransactionStatus.success: return 'success';
      case TransactionStatus.failed: return 'failed';
    }
  }

  static TransactionStatus statusFromString(String status) {
    switch (status) {
      case 'success': return TransactionStatus.success;
      case 'failed': return TransactionStatus.failed;
      default: return TransactionStatus.pending;
    }
  }

  Map<String, dynamic> toFirestore() {
    return {
      'transactionId': transactionId,
      'nftId': nftId,
      'auctionId': auctionId,
      'sellerId': sellerId,
      'buyerId': buyerId,
      'sellerWallet': sellerWallet,
      'buyerWallet': buyerWallet,
      'amount': amount,
      'transactionHash': transactionHash,
      'type': typeToString(type),
      'status': statusToString(status),
      'failureReason': failureReason,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'confirmedAt': confirmedAt?.millisecondsSinceEpoch,
      'blockNumber': blockNumber,
    };
  }

  factory TransactionModel.fromFirestore(Map<String, dynamic> data) {
    DateTime parsedCreatedAt = DateTime.now();
    if (data['createdAt'] is int) {
      parsedCreatedAt = DateTime.fromMillisecondsSinceEpoch(data['createdAt'] as int);
    }

    DateTime? parsedConfirmedAt;
    if (data['confirmedAt'] is int) {
      parsedConfirmedAt = DateTime.fromMillisecondsSinceEpoch(data['confirmedAt'] as int);
    }

    return TransactionModel(
      transactionId: data['transactionId'] as String? ?? '',
      nftId: data['nftId'] as String? ?? '',
      auctionId: data['auctionId'] as String?,
      sellerId: data['sellerId'] as String?,
      buyerId: data['buyerId'] as String?,
      sellerWallet: data['sellerWallet'] as String?,
      buyerWallet: data['buyerWallet'] as String?,
      amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
      transactionHash: data['transactionHash'] as String?,
      type: typeFromString(data['type'] as String? ?? 'transfer'),
      status: statusFromString(data['status'] as String? ?? 'pending'),
      failureReason: data['failureReason'] as String?,
      createdAt: parsedCreatedAt,
      confirmedAt: parsedConfirmedAt,
      blockNumber: data['blockNumber'] as int?,
    );
  }
}
