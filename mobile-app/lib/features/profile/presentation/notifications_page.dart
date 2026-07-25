import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nft_logo_marketplace/core/services/firestore_service.dart';
import 'package:nft_logo_marketplace/shared/models/app_notification.dart';
import 'package:timeago/timeago.dart' as timeago;

class _NotificationColors {
  static const Color background = Color(0xFF0F172A);
  static const Color surface = Color(0xFF1E293B);
  static const Color primary = Color(0xFF38BDF8);
  static const Color text = Color(0xFFF8FAFC);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color divider = Color(0xFF334155);
  static const Color unreadBg = Color(0xFF0C4A6E);
}

class NotificationsPage extends StatefulWidget {
  final String userWallet;

  const NotificationsPage({super.key, required this.userWallet});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {

  IconData _getIconForType(NotificationType type) {
    switch (type) {
      case NotificationType.auctionWon:
        return Icons.emoji_events;
      case NotificationType.auctionLost:
        return Icons.cancel_outlined;
      case NotificationType.newBid:
        return Icons.gavel;
      case NotificationType.outbid:
        return Icons.warning_amber_rounded;
      case NotificationType.paymentSuccess:
        return Icons.check_circle;
      case NotificationType.paymentFailed:
        return Icons.error_outline;
      case NotificationType.paymentPending:
        return Icons.hourglass_bottom;
      case NotificationType.nftApproved:
        return Icons.verified;
      case NotificationType.nftRejected:
        return Icons.block;
      case NotificationType.unsoldAuction:
        return Icons.storefront;
      case NotificationType.relistAvailable:
        return Icons.restore;
      case NotificationType.info:
      default:
        return Icons.info_outline;
    }
  }

  Color _getColorForType(NotificationType type) {
    switch (type) {
      case NotificationType.auctionWon:
      case NotificationType.paymentSuccess:
      case NotificationType.nftApproved:
        return Colors.greenAccent;
      case NotificationType.auctionLost:
      case NotificationType.paymentFailed:
      case NotificationType.nftRejected:
        return Colors.redAccent;
      case NotificationType.outbid:
      case NotificationType.paymentPending:
      case NotificationType.unsoldAuction:
      case NotificationType.relistAvailable:
        return Colors.orangeAccent;
      case NotificationType.newBid:
      case NotificationType.info:
      default:
        return _NotificationColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _NotificationColors.background,
      appBar: AppBar(
        backgroundColor: _NotificationColors.background,
        elevation: 0,
        title: Text(
          'Notifications',
          style: GoogleFonts.outfit(
            color: _NotificationColors.text,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: _NotificationColors.text),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: 'Mark all as read',
            onPressed: () {
              FirestoreService.instance.markAllNotificationsAsRead(widget.userWallet);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('All notifications marked as read')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear all',
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: _NotificationColors.surface,
                  title: Text('Clear Notifications', style: GoogleFonts.outfit(color: _NotificationColors.text)),
                  content: Text('Are you sure you want to clear all notifications?', style: GoogleFonts.inter(color: _NotificationColors.textMuted)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Cancel', style: GoogleFonts.inter(color: _NotificationColors.textMuted)),
                    ),
                    TextButton(
                      onPressed: () {
                        FirestoreService.instance.clearAllNotifications(widget.userWallet);
                        Navigator.pop(context);
                      },
                      child: Text('Clear', style: GoogleFonts.inter(color: Colors.redAccent)),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<List<AppNotification>>(
        stream: FirestoreService.instance.getNotificationsStream(widget.userWallet),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _NotificationColors.primary),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error loading notifications',
                style: GoogleFonts.inter(color: Colors.redAccent),
              ),
            );
          }

          final notifications = snapshot.data ?? [];

          if (notifications.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async { if (mounted) setState(() {}); },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.7,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.notifications_off_outlined,
                            size: 64,
                            color: _NotificationColors.textMuted.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No notifications yet',
                            style: GoogleFonts.outfit(
                              color: _NotificationColors.textMuted,
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
      onRefresh: () async { if (mounted) setState(() {}); },
      child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: notifications.length,
            separatorBuilder: (context, index) => const Divider(
              color: _NotificationColors.divider,
              height: 1,
            ),
            itemBuilder: (context, index) {
              final notification = notifications[index];
              return InkWell(
                onTap: () {
                  if (!notification.isRead) {
                    FirestoreService.instance.markNotificationAsRead(widget.userWallet, notification.id);
                  }
                  // Optionally navigate to specific page based on notification type / relatedId
                },
                child: Container(
                  color: notification.isRead
                      ? Colors.transparent
                      : _NotificationColors.unreadBg.withValues(alpha: 0.3),
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _NotificationColors.surface,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _getColorForType(notification.type).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Icon(
                          _getIconForType(notification.type),
                          color: _getColorForType(notification.type),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
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
                                    style: GoogleFonts.inter(
                                      color: _NotificationColors.text,
                                      fontWeight: notification.isRead
                                          ? FontWeight.normal
                                          : FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                if (!notification.isRead)
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: _NotificationColors.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              notification.message,
                              style: GoogleFonts.inter(
                                color: _NotificationColors.textMuted,
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              timeago.format(notification.createdAt),
                              style: GoogleFonts.inter(
                                color: _NotificationColors.textMuted.withValues(alpha: 0.7),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
    );
        },
      ),
    );
  }
}
