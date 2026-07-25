import 'package:flutter/material.dart';
import 'package:nft_logo_marketplace/core/utils/firestore_error_handler.dart';
import 'package:nft_logo_marketplace/shared/models/user_model.dart';
import 'package:nft_logo_marketplace/core/services/firestore_service.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/core/theme/app_spacing.dart';
import 'package:nft_logo_marketplace/core/theme/app_shadows.dart';
import 'package:nft_logo_marketplace/core/theme/app_radius.dart';
import 'package:nft_logo_marketplace/core/utils/notification_manager.dart';
import 'package:nft_logo_marketplace/shared/models/app_notification.dart';

class UserManagementPage extends StatefulWidget {
  const UserManagementPage({super.key});

  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> {

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<UserModel>>(
      stream: FirestoreService.instance.getAllUsersStream(),
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

        final users = snapshot.data ?? [];

        if (users.isEmpty) {
          return RefreshIndicator(
            onRefresh: () async { if (mounted) setState(() {}); },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.border),
                          ),
                          child: const Icon(Icons.people_outline, size: 48, color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          'No users found',
                          style: AppTextStyles.labelLarge.copyWith(color: AppColors.textSecondary),
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
      child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.xl),
          itemCount: users.length,
          itemBuilder: (context, index) {
            final user = users[index];
            final isAdmin = user.role == 'admin';

            return Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(
                  color: isAdmin
                      ? AppColors.primary.withValues(alpha: 0.3)
                      : AppColors.border,
                ),
                boxShadow: AppShadows.soft,
              ),
              child: Row(
                children: [
                  // Avatar
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: isAdmin ? AppColors.primaryGradient : null,
                      color: isAdmin ? null : AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: isAdmin ? Colors.transparent : AppColors.border),
                    ),
                    child: Icon(
                      isAdmin ? Icons.shield : Icons.person,
                      color: isAdmin ? AppColors.textPrimary : AppColors.textSecondary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),

                  // User Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                user.fullName.isNotEmpty ? user.fullName : 'Unknown',
                                style: AppTextStyles.h3,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isAdmin
                                    ? AppColors.primary.withValues(alpha: 0.1)
                                    : AppColors.frozenBlue.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(AppRadius.sm),
                                border: Border.all(color: isAdmin ? AppColors.primary.withValues(alpha: 0.3) : AppColors.frozenBlue.withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                user.role.toUpperCase(),
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: isAdmin ? AppColors.primary : AppColors.frozenBlue,
                                  fontSize: 9,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          user.email,
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (user.walletAddress != null && user.walletAddress!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.account_balance_wallet, size: 12, color: AppColors.textSecondary),
                              const SizedBox(width: 4),
                              Text(
                                user.walletAddressShort ?? '',
                                style: AppTextStyles.mono.copyWith(
                                  color: AppColors.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Actions
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
                    color: AppColors.surfaceLight,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                    onSelected: (action) {
                      _handleAction(context, action, user);
                    },
                    itemBuilder: (context) => [
                      if (!isAdmin)
                        PopupMenuItem(
                          value: 'promote',
                          child: Row(
                            children: [
                              const Icon(Icons.arrow_upward, color: AppColors.primary, size: 18),
                              const SizedBox(width: 8),
                              Text('Promote to Admin', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary)),
                            ],
                          ),
                        ),
                      if (isAdmin)
                        PopupMenuItem(
                          value: 'demote',
                          child: Row(
                            children: [
                              const Icon(Icons.arrow_downward, color: AppColors.accentOrange, size: 18),
                              const SizedBox(width: 8),
                              Text('Demote to User', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
    );
      },
    );
  }

  void _handleAction(BuildContext context, String action, UserModel user) async {
    try {
      switch (action) {
        case 'promote':
          await FirestoreService.instance.updateUserRole(user.uid, 'admin');
          if (!context.mounted) return;
          NotificationManager.show(
            context: context,
            title: 'Success',
            message: '${user.fullName} promoted to admin',
            type: NotificationType.success,
          );
          break;
        case 'demote':
          await FirestoreService.instance.updateUserRole(user.uid, 'user');
          if (!context.mounted) return;
          NotificationManager.show(
            context: context,
            title: 'Success',
            message: '${user.fullName} demoted to user',
            type: NotificationType.warning,
          );
          break;
      }
    } catch (e) {
      if (!context.mounted) return;
      NotificationManager.show(
        context: context,
        title: 'Error',
        message: e.toString().replaceFirst("Exception: ", ""),
        type: NotificationType.error,
      );
    }
  }
}

