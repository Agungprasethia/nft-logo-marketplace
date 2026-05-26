import 'package:cloud_firestore/cloud_firestore.dart';

enum NotificationType { success, error, warning, info, web3 }

class AppNotification {
  final String id;
  final String title;
  final String message;
  final NotificationType type;
  final String category;
  final int? tokenId;
  final String? imageUrl;
  final bool isRead;
  final DateTime createdAt;
  final String? actionRoute;

  AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.category,
    this.tokenId,
    this.imageUrl,
    this.isRead = false,
    required this.createdAt,
    this.actionRoute,
  });

  factory AppNotification.fromFirestore(Map<String, dynamic> data, String id) {
    NotificationType parsedType;
    switch (data['type']) {
      case 'success':
        parsedType = NotificationType.success;
        break;
      case 'error':
        parsedType = NotificationType.error;
        break;
      case 'warning':
        parsedType = NotificationType.warning;
        break;
      case 'info':
        parsedType = NotificationType.info;
        break;
      case 'web3':
        parsedType = NotificationType.web3;
        break;
      default:
        parsedType = NotificationType.info;
    }

    return AppNotification(
      id: id,
      title: data['title'] ?? '',
      message: data['message'] ?? '',
      type: parsedType,
      category: data['category'] ?? 'system',
      tokenId: data['tokenId'],
      imageUrl: data['imageUrl'],
      isRead: data['isRead'] ?? false,
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      actionRoute: data['actionRoute'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'message': message,
      'type': type.name,
      'category': category,
      'tokenId': tokenId,
      'imageUrl': imageUrl,
      'isRead': isRead,
      'createdAt': FieldValue.serverTimestamp(),
      'actionRoute': actionRoute,
    };
  }
}
