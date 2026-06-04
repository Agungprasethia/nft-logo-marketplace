import 'package:cloud_firestore/cloud_firestore.dart';

enum NotificationType {
  info,
  success,
  warning,
  error,
  auctionWon,
  auctionLost,
  newBid,
  outbid,
  paymentSuccess,
  paymentFailed,
  paymentPending,
  nftApproved,
  nftRejected,
  unsoldAuction,
  relistAvailable,
  web3
}

class AppNotification {
  final String id;
  final String userWallet;
  final String title;
  final String message;
  final NotificationType type;
  final bool isRead;
  final DateTime createdAt;
  final String? relatedId;   // e.g., tokenId or auctionId
  final String? category;    // e.g., 'auction', 'system'
  final String? actionRoute; // e.g., '/auction/42'

  AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.createdAt,
    String? userWallet,
    this.isRead = false,
    this.relatedId,
    this.category,
    this.actionRoute,
  }) : userWallet = userWallet ?? '';

  factory AppNotification.fromFirestore(Map<String, dynamic> json, String id) {
    return AppNotification(
      id: id,
      userWallet: json['userWallet'] ?? '',
      title: json['title'] ?? '',
      message: json['message'] ?? '',
      type: _parseNotificationType(json['type'] ?? 'info'),
      isRead: json['isRead'] ?? false,
      createdAt: (json['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      relatedId: json['relatedId'],
      category: json['category'],
      actionRoute: json['actionRoute'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userWallet': userWallet,
      'title': title,
      'message': message,
      'type': type.name,
      'isRead': isRead,
      'createdAt': Timestamp.fromDate(createdAt),
      if (relatedId != null) 'relatedId': relatedId,
      if (category != null) 'category': category,
      if (actionRoute != null) 'actionRoute': actionRoute,
    };
  }

  // Alias so legacy code calling toMap() still works
  Map<String, dynamic> toMap() => toFirestore();

  AppNotification copyWith({
    String? id,
    String? userWallet,
    String? title,
    String? message,
    NotificationType? type,
    bool? isRead,
    DateTime? createdAt,
    String? relatedId,
    String? category,
    String? actionRoute,
  }) {
    return AppNotification(
      id: id ?? this.id,
      userWallet: userWallet ?? this.userWallet,
      title: title ?? this.title,
      message: message ?? this.message,
      type: type ?? this.type,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
      relatedId: relatedId ?? this.relatedId,
      category: category ?? this.category,
      actionRoute: actionRoute ?? this.actionRoute,
    );
  }

  static NotificationType _parseNotificationType(String typeStr) {
    return NotificationType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => NotificationType.info,
    );
  }
}
