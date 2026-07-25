import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:nft_logo_marketplace/shared/models/app_notification.dart';
import 'package:nft_logo_marketplace/core/services/firestore_service.dart';
import 'package:nft_logo_marketplace/core/widgets/premium_notification.dart';
import 'package:nft_logo_marketplace/core/services/web3_service.dart';
import 'package:uuid/uuid.dart';
import 'package:nft_logo_marketplace/main.dart';

class NotificationManager {
  static final NotificationManager _instance = NotificationManager._internal();
  static NotificationManager get instance => _instance;

  NotificationManager._internal();

  OverlayEntry? _currentOverlay;
  final Queue<_NotificationData> _queue = Queue<_NotificationData>();
  bool _isShowing = false;

  /// Show a premium Web3 notification
  /// Automatically saves to Firestore if [saveToHistory] is true and a wallet is connected.
  static void show({
    BuildContext? context,
    required String title,
    required String message,
    NotificationType type = NotificationType.info,
    String category = 'system',
    int? tokenId,
    String? imageUrl,
    String? actionRoute,
    bool saveToHistory = true,
  }) {
    // Generate notification ID
    final id = const Uuid().v4();
    final now = DateTime.now();

    final notification = AppNotification(
      id: id,
      title: title,
      message: message,
      type: type,
      category: category,
      relatedId: tokenId?.toString(),
      createdAt: now,
      actionRoute: actionRoute,
    );

    // Save to Firestore
    if (saveToHistory) {
      final currentWallet = Web3Service.instance.currentAddress;
      if (currentWallet != null && currentWallet.isNotEmpty) {
        FirestoreService.instance.saveNotification(currentWallet, notification);
      }
    }

    // Add to UI queue
    final ctx = context ?? navigatorKey.currentContext;
    if (ctx != null) {
      _instance._queue.add(_NotificationData(context: ctx, notification: notification));
      _instance._processQueue();
    } else {
      debugPrint('NotificationManager: Cannot show notification, no context available.');
    }
  }

  void _processQueue() {
    if (_isShowing || _queue.isEmpty) return;

    final data = _queue.removeFirst();
    _showOverlay(data.context, data.notification);
  }

  void _showOverlay(BuildContext context, AppNotification notification) {
    if (!context.mounted) {
      _processQueue(); // Context might be dead, skip and process next
      return;
    }

    _isShowing = true;

    final overlay = Overlay.of(context, rootOverlay: true);
    
    _currentOverlay = OverlayEntry(
      builder: (context) {
        return PremiumNotification(
          title: notification.title,
          message: notification.message,
          type: notification.type,
          onDismissed: () {
            _removeCurrent();
          },
          onTap: () {
            if (notification.actionRoute != null) {
              Navigator.pushNamed(context, notification.actionRoute!);
            }
          },
        );
      },
    );

    overlay.insert(_currentOverlay!);
  }

  void _removeCurrent() {
    if (_currentOverlay != null) {
      _currentOverlay!.remove();
      _currentOverlay = null;
    }
    _isShowing = false;
    _processQueue();
  }
}

class _NotificationData {
  final BuildContext context;
  final AppNotification notification;

  _NotificationData({required this.context, required this.notification});
}
