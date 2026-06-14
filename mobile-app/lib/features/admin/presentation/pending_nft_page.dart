import 'package:flutter/material.dart';
import 'package:nft_logo_marketplace/core/utils/firestore_error_handler.dart';
import 'dart:convert';
import 'package:nft_logo_marketplace/core/services/firestore_service.dart';
import 'package:nft_logo_marketplace/core/services/auth_service.dart';
import 'package:nft_logo_marketplace/shared/models/logo_nft.dart';
import 'package:nft_logo_marketplace/shared/models/user_model.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/core/theme/app_spacing.dart';
import 'package:nft_logo_marketplace/core/theme/app_shadows.dart';
import 'package:nft_logo_marketplace/shared/widgets/primary_button.dart';
import 'package:nft_logo_marketplace/core/theme/app_radius.dart';
import 'package:nft_logo_marketplace/core/utils/notification_manager.dart';
import 'package:nft_logo_marketplace/shared/models/app_notification.dart';

class PendingNftPage extends StatefulWidget {
  const PendingNftPage({super.key});

  @override
  State<PendingNftPage> createState() => _PendingNftPageState();
}

class _PendingNftPageState extends State<PendingNftPage> {
  final Set<int> _processingTokens = {};

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LogoNFT>>(
      stream: FirestoreService.instance.getPendingNFTsStream(),
      builder: (context, snapshot) {
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

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          );
        }

        final pendingList = snapshot.data ?? [];

        if (pendingList.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
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
                    child: const Icon(Icons.check_circle_outline, size: 48, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('No pending NFTs', style: AppTextStyles.labelLarge.copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 320,
                  mainAxisExtent: 420,
                  crossAxisSpacing: AppSpacing.lg,
                  mainAxisSpacing: AppSpacing.lg,
                ),
                itemCount: pendingList.length,
                itemBuilder: (context, index) {
                  return _buildPendingNFTCard(context, pendingList[index]);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPendingNFTCard(BuildContext context, LogoNFT logo) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.soft,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showNFTDetailsModal(context, logo),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image placeholder with modern gradient
              Expanded(
                flex: 5,
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.surfaceLight, AppColors.surface],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: logo.imageUrl.isNotEmpty
                      ? Image.network(
                          logo.imageUrl, 
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => const Center(
                            child: Icon(Icons.image_outlined, size: 64, color: AppColors.textSecondary),
                          ),
                        )
                      : const Center(
                          child: Icon(Icons.image_outlined, size: 64, color: AppColors.textSecondary),
                        ),
                ),
              ),
              // Info Area
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              logo.name,
                              style: AppTextStyles.h3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.accentOrange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                              border: Border.all(color: AppColors.accentOrange.withValues(alpha: 0.5)),
                            ),
                            child: Text(
                              'Pending',
                              style: AppTextStyles.labelMedium.copyWith(color: AppColors.accentOrange),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Expanded(
                        child: FutureBuilder<UserModel?>(
                          future: logo.creatorId.isEmpty ? AuthService.instance.getUserData(logo.creatorWallet.toLowerCase()) : AuthService.instance.getUserData(logo.creatorId),
                          builder: (context, snapshot) {
                            final creatorUser = snapshot.data;
                            final displayName = creatorUser?.displayName ?? logo.creatorUsername;
                            final hasName = displayName != null && displayName.isNotEmpty;
                            
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    CircleAvatar(
                                      radius: 10,
                                      backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                                      backgroundImage: creatorUser?.profileImage != null && creatorUser!.profileImage!.startsWith('data:image')
                                          ? MemoryImage(base64Decode(creatorUser.profileImage!.split(',')[1]))
                                          : null,
                                      child: creatorUser?.profileImage == null || !creatorUser!.profileImage!.startsWith('data:image')
                                          ? const Icon(Icons.person, size: 12, color: AppColors.primary)
                                          : null,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Creator: ${hasName ? displayName : logo.creatorShort}',
                                        style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.bold),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                if (creatorUser?.country?.isNotEmpty == true)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 28, top: 2),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.public, size: 10, color: AppColors.textSecondary),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            creatorUser?.country ?? '',
                                            style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else if (hasName)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 28, top: 2),
                                    child: Text(
                                      'Wallet: ${logo.creatorShort}',
                                      style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                            );
                          }
                        ),
                      ),
                      // Auction Duration Badge
                      if (logo.auctionDuration != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Icon(Icons.timer_outlined, size: 14, color: AppColors.accentOrange),
                              const SizedBox(width: 6),
                              Text(
                                'Duration: ${_formatDuration(logo.auctionDuration!)}',
                                style: AppTextStyles.labelSmall.copyWith(color: AppColors.accentOrange),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 12),
                      // Actions buttons
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _processingTokens.contains(logo.tokenId) ? null : () async {
                                final confirm = await _showConfirmDialog(context, 'Approve NFT', 'Are you sure you want to approve this NFT?');
                                if (confirm != true) return;
                                setState(() => _processingTokens.add(logo.tokenId));
                                try {
                                  await FirestoreService.instance.approveNFT(logo.tokenId, 'admin');
                                  if (!context.mounted) return;
                                  NotificationManager.show(
                                    context: context,
                                    title: 'Success',
                                    message: 'NFT Approved!',
                                    type: NotificationType.success,
                                  );
                                } catch (e) {
                                  if (!context.mounted) return;
                                  NotificationManager.show(
                                    context: context,
                                    title: 'Error',
                                    message: e.toString().replaceFirst("Exception: ", ""),
                                    type: NotificationType.error,
                                  );
                                } finally {
                                  if (mounted) setState(() => _processingTokens.remove(logo.tokenId));
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.success,
                                foregroundColor: AppColors.textPrimary,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppRadius.md),
                                ),
                              ),
                              child: _processingTokens.contains(logo.tokenId)
                                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
                                  : const FittedBox(child: Text('Approve', style: TextStyle(fontWeight: FontWeight.bold))),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _processingTokens.contains(logo.tokenId) ? null : () async {
                                final confirm = await _showConfirmDialog(context, 'Reject NFT', 'Are you sure you want to reject this NFT?');
                                if (confirm != true) return;
                                setState(() => _processingTokens.add(logo.tokenId));
                                try {
                                  await FirestoreService.instance.rejectNFT(logo.tokenId);
                                  if (!context.mounted) return;
                                  NotificationManager.show(
                                    context: context,
                                    title: 'Rejected',
                                    message: 'NFT Rejected!',
                                    type: NotificationType.info,
                                  );
                                } catch (e) {
                                  if (!context.mounted) return;
                                  NotificationManager.show(
                                    context: context,
                                    title: 'Error',
                                    message: e.toString().replaceFirst("Exception: ", ""),
                                    type: NotificationType.error,
                                  );
                                } finally {
                                  if (mounted) setState(() => _processingTokens.remove(logo.tokenId));
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                foregroundColor: AppColors.danger,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppRadius.md),
                                  side: const BorderSide(color: AppColors.danger, width: 1.5),
                                ),
                                elevation: 0,
                              ),
                              child: const FittedBox(child: Text('Reject', style: TextStyle(fontWeight: FontWeight.bold))),
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNFTDetailsModal(BuildContext context, LogoNFT logo) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xxl)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Image Header
                  Stack(
                    alignment: Alignment.topRight,
                    children: [
                      Container(
                        width: double.infinity,
                        height: 250,
                        clipBehavior: Clip.antiAlias,
                        decoration: const BoxDecoration(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
                          gradient: LinearGradient(
                            colors: [AppColors.surfaceLight, AppColors.surface],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: logo.imageUrl.isNotEmpty
                            ? Image.network(
                                logo.imageUrl, 
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) => const Center(
                                  child: Icon(Icons.image_outlined, size: 80, color: AppColors.textSecondary),
                                )
                              )
                            : const Center(
                                child: Icon(Icons.image_outlined, size: 80, color: AppColors.textSecondary),
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, color: AppColors.textPrimary),
                          style: IconButton.styleFrom(backgroundColor: Colors.black45),
                        ),
                      )
                    ],
                  ),
                  // Body content
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                logo.name,
                                style: AppTextStyles.h1,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.accentOrange.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(AppRadius.sm),
                                border: Border.all(color: AppColors.accentOrange.withValues(alpha: 0.5)),
                              ),
                              child: Text('Pending', style: AppTextStyles.labelMedium.copyWith(color: AppColors.accentOrange)),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        const Text('Description', style: AppTextStyles.h3),
                        const SizedBox(height: 8),
                        Text(
                          logo.description.isNotEmpty ? logo.description : 'No description provided for this NFT.',
                          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary, height: 1.5),
                        ),
                        const SizedBox(height: AppSpacing.xxl),
                        // Metadata
                        _buildDetailRow('Creator:', logo.creatorUsername ?? logo.creatorShort),
                        if (logo.creatorUsername != null && logo.creatorUsername!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _buildDetailRow('Wallet:', logo.creatorShort),
                        ],
                        const SizedBox(height: 12),
                        _buildDetailRow('Category:', logo.category),
                        const SizedBox(height: 12),
                        _buildDetailRow('Estimated Price:', '${logo.price} ETH'),
                        const SizedBox(height: 12),
                        _buildDetailRow('Auction Duration:', _formatDuration(logo.auctionDuration ?? 86400)),
                        const SizedBox(height: AppSpacing.xxl),
                        // Actions
                        Row(
                          children: [
                            Expanded(
                              child: PrimaryButton(
                                text: 'Approve NFT',
                                icon: Icons.check,
                                backgroundColor: AppColors.success,
                                onPressed: () async {
                                  final confirm = await _showConfirmDialog(context, 'Approve NFT', 'Are you sure you want to approve this NFT?');
                                  if (confirm != true) return;
                                  try {
                                    await FirestoreService.instance.approveNFT(logo.tokenId, 'admin');
                                    if (!context.mounted) return;
                                    Navigator.pop(context);
                                    NotificationManager.show(context: context, title: 'Success', message: 'NFT Approved!', type: NotificationType.success);
                                  } catch (e) {
                                    if (!context.mounted) return;
                                    NotificationManager.show(context: context, title: 'Error', message: e.toString().replaceFirst("Exception: ", ""), type: NotificationType.error);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () async {
                                  final confirm = await _showConfirmDialog(context, 'Reject NFT', 'Are you sure you want to reject this NFT?');
                                  if (confirm != true) return;
                                  try {
                                    await FirestoreService.instance.rejectNFT(logo.tokenId);
                                    if (!context.mounted) return;
                                    Navigator.pop(context);
                                    NotificationManager.show(context: context, title: 'Rejected', message: 'NFT Rejected!', type: NotificationType.info);
                                  } catch (e) {
                                    if (!context.mounted) return;
                                    NotificationManager.show(context: context, title: 'Error', message: e.toString().replaceFirst("Exception: ", ""), type: NotificationType.error);
                                  }
                                },
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: AppColors.danger, width: 1.5),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                ),
                                child: Text('Reject', style: AppTextStyles.labelLarge.copyWith(color: AppColors.danger)),
                              ),
                            ),
                          ],
                        )
                      ],
                    ),
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value, 
            style: AppTextStyles.labelLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }

  String _formatDuration(int seconds) {
    int h = seconds ~/ 3600;
    int m = (seconds % 3600) ~/ 60;
    int s = seconds % 60;
    String hh = h.toString().padLeft(2, '0');
    String mm = m.toString().padLeft(2, '0');
    String ss = s.toString().padLeft(2, '0');
    return '$hh.$mm,$ss';
  }

  Future<bool?> _showConfirmDialog(BuildContext context, String title, String content) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title, style: AppTextStyles.h3),
        content: Text(content, style: AppTextStyles.bodyMedium),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Confirm', style: TextStyle(color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}
