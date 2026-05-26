import 'package:flutter/material.dart';
import 'package:nft_logo_marketplace/core/utils/firestore_error_handler.dart';
import 'package:nft_logo_marketplace/shared/models/notification_model.dart';
import 'package:nft_logo_marketplace/core/services/firestore_service.dart';
import 'package:nft_logo_marketplace/core/services/web3_service.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/core/theme/app_radius.dart';
import 'package:nft_logo_marketplace/core/theme/app_spacing.dart';
import 'package:nft_logo_marketplace/core/utils/notification_manager.dart';
import 'package:timeago/timeago.dart' as timeago;

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final String _currentWallet = Web3Service.instance.currentAddress?.toLowerCase() ?? '';

  @override
  void initState() {
    super.initState();
    if (_currentWallet.isNotEmpty) {
      FirestoreService.instance.markAllNotificationsAsRead(_currentWallet);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentWallet.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Notifications', style: AppTextStyles.h3),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.notifications_off_outlined, size: 64, color: AppColors.textSecondary.withValues(alpha: 0.5)),
              const SizedBox(height: AppSpacing.md),
              Text('Wallet Not Connected', style: AppTextStyles.h3.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: AppSpacing.sm),
              Text('Connect your wallet to view notifications', style: AppTextStyles.bodyMedium),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Notifications', style: AppTextStyles.h3),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all, color: AppColors.primary),
            onPressed: () {
              FirestoreService.instance.markAllNotificationsAsRead(_currentWallet);
              NotificationManager.show(
                context: context,
                title: 'Success',
                message: 'Marked all as read',
                type: NotificationType.success,
              );
            },
            tooltip: 'Mark all as read',
          ),
        ],
      ),
      body: StreamBuilder<List<AppNotification>>(
        stream: FirestoreService.instance.getNotificationsStream(_currentWallet),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }

          if (snapshot.hasError) {
          return FirestoreErrorHandler.buildErrorWidget(
            snapshot.error,
            onRetry: () {
              if (context is Element) {
                context.markNeedsBuild();
              }
            },
          );
        }

          final notifications = snapshot.data ?? [];

          if (notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_none, size: 64, color: AppColors.textSecondary.withValues(alpha: 0.5)),
                  const SizedBox(height: AppSpacing.md),
                  Text('No Notifications Yet', style: AppTextStyles.h3.copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: AppSpacing.sm),
                  Text('You will see activity updates here', style: AppTextStyles.bodyMedium),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              final notification = notifications[index];
              return _buildNotificationCard(notification);
            },
          );
        },
      ),
    );
  }

  Widget _buildNotificationCard(AppNotification notification) {
    Color primaryColor;
    IconData iconData;

    switch (notification.type) {
      case NotificationType.success:
        primaryColor = AppColors.success;
        iconData = Icons.check_circle_outline;
        break;
      case NotificationType.error:
        primaryColor = AppColors.danger;
        iconData = Icons.error_outline;
        break;
      case NotificationType.warning:
        primaryColor = AppColors.accentOrange;
        iconData = Icons.warning_amber_rounded;
        break;
      case NotificationType.info:
        primaryColor = AppColors.primary;
        iconData = Icons.info_outline;
        break;
      case NotificationType.web3:
        primaryColor = const Color(0xFF00E5FF); // Cyan
        iconData = Icons.account_balance_wallet_outlined;
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: notification.isRead ? AppColors.surface : primaryColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: notification.isRead ? AppColors.border : primaryColor.withValues(alpha: 0.3),
          width: notification.isRead ? 1 : 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: () {
            FirestoreService.instance.markNotificationAsRead(_currentWallet, notification.id);
            if (notification.actionRoute != null) {
              Navigator.pushNamed(context, notification.actionRoute!);
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(iconData, color: primaryColor, size: 24),
                ),
                const SizedBox(width: AppSpacing.md),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              notification.title,
                              style: AppTextStyles.h3.copyWith(
                                fontSize: 16,
                                color: notification.isRead ? AppColors.textPrimary : primaryColor,
                              ),
                            ),
                          ),
                          Text(
                            timeago.format(notification.createdAt),
                            style: AppTextStyles.caption,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        notification.message,
                        style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                      ),
                      if (notification.actionRoute != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Tap to view details',
                          style: AppTextStyles.labelSmall.copyWith(color: primaryColor),
                        ),
                      ],
                    ],
                  ),
                ),
                // Unread Dot
                if (!notification.isRead) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: primaryColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
