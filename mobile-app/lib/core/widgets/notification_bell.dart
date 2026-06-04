import 'package:flutter/material.dart';
import 'package:nft_logo_marketplace/core/services/firestore_service.dart';
import 'package:nft_logo_marketplace/core/services/web3_service.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/features/profile/presentation/notifications_page.dart';

class NotificationBell extends StatelessWidget {
  final Color iconColor;
  const NotificationBell({super.key, this.iconColor = AppColors.textPrimary});

  @override
  Widget build(BuildContext context) {
    final currentWallet = Web3Service.instance.currentAddress?.toLowerCase() ?? '';

    if (currentWallet.isEmpty) {
      return IconButton(
        icon: Icon(Icons.notifications_none, color: iconColor),
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsPage(userWallet: currentWallet)));
        },
      );
    }

    return StreamBuilder<int>(
      stream: FirestoreService.instance.getUnreadNotificationsCountStream(currentWallet),
      builder: (context, snapshot) {
        final unreadCount = snapshot.data ?? 0;

        return Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: Icon(unreadCount > 0 ? Icons.notifications_active : Icons.notifications_none, color: iconColor),
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsPage(userWallet: currentWallet)));
              },
            ),
            if (unreadCount > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: AppColors.danger,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: Center(
                    child: Text(
                      unreadCount > 9 ? '9+' : unreadCount.toString(),
                      style: AppTextStyles.labelSmall.copyWith(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
