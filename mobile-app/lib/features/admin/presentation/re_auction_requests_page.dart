import 'package:flutter/material.dart';
import 'package:nft_logo_marketplace/core/utils/firestore_error_handler.dart';
import 'package:nft_logo_marketplace/core/services/firestore_service.dart';
import 'package:nft_logo_marketplace/core/services/auth_service.dart';
import 'package:nft_logo_marketplace/shared/models/logo_nft.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/core/theme/app_radius.dart';
import 'package:nft_logo_marketplace/core/theme/app_spacing.dart';
import 'package:nft_logo_marketplace/shared/widgets/primary_button.dart';
import 'package:nft_logo_marketplace/core/utils/notification_manager.dart';
import 'package:nft_logo_marketplace/shared/models/notification_model.dart';

class ReAuctionRequestsPage extends StatefulWidget {
  const ReAuctionRequestsPage({super.key});

  @override
  State<ReAuctionRequestsPage> createState() => _ReAuctionRequestsPageState();
}

class _ReAuctionRequestsPageState extends State<ReAuctionRequestsPage> {
  final _firestoreService = FirestoreService.instance;
  final Set<int> _processingTokens = {};

  Future<void> _handleApprove(LogoNFT request) async {
    setState(() => _processingTokens.add(request.tokenId));
    try {
      final adminId = AuthService.instance.currentUser?.uid ?? 'admin';
      await _firestoreService.approveReAuction(request.tokenId, adminId);
      if (mounted) {
        NotificationManager.show(
          context: context,
          title: 'Success',
          message: 'Re-Auction for #${request.tokenId} approved',
          type: NotificationType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        NotificationManager.show(
          context: context,
          title: 'Error',
          message: e.toString().replaceFirst("Exception: ", ""),
          type: NotificationType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _processingTokens.remove(request.tokenId));
      }
    }
  }

  Future<void> _handleReject(LogoNFT request) async {
    setState(() => _processingTokens.add(request.tokenId));
    try {
      final adminId = AuthService.instance.currentUser?.uid ?? 'admin';
      await _firestoreService.rejectReAuction(request.tokenId, adminId);
      if (mounted) {
        NotificationManager.show(
          context: context,
          title: 'Rejected',
          message: 'Re-Auction for #${request.tokenId} rejected',
          type: NotificationType.info,
        );
      }
    } catch (e) {
      if (mounted) {
        NotificationManager.show(
          context: context,
          title: 'Error',
          message: e.toString().replaceFirst("Exception: ", ""),
          type: NotificationType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _processingTokens.remove(request.tokenId));
      }
    }
  }

  String _formatDuration(int seconds) {
    if (seconds == 3600) return '1 Hour';
    if (seconds == 21600) return '6 Hours';
    if (seconds == 43200) return '12 Hours';
    if (seconds == 86400) return '24 Hours';
    if (seconds == 259200) return '3 Days';
    if (seconds == 604800) return '7 Days';
    return '${(seconds / 3600).round()} Hours';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LogoNFT>>(
      stream: _firestoreService.getReAuctionRequestsStream(),
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

        final requests = snapshot.data ?? [];

        if (requests.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline, size: 64, color: AppColors.textSecondary.withValues(alpha: 0.5)),
                const SizedBox(height: AppSpacing.md),
                Text('No Re-Auction Requests', style: AppTextStyles.h3.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: AppSpacing.sm),
                Text('All requests have been handled.', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(AppSpacing.xl),
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final request = requests[index];
            final isProcessing = _processingTokens.contains(request.tokenId);

            return Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.xl),
                border: Border.all(color: AppColors.border),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Image
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        child: request.imageUrl.startsWith('data:image')
                            ? Image.memory(
                                Uri.parse(request.imageUrl).data!.contentAsBytes(),
                                fit: BoxFit.cover,
                              )
                            : Image.network(
                                request.imageUrl.replaceFirst('ipfs://', 'https://ipfs.io/ipfs/'),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported, color: AppColors.textSecondary),
                              ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xl),
                    
                    // Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(request.name, style: AppTextStyles.h3),
                              const SizedBox(width: AppSpacing.md),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(AppRadius.pill),
                                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                                ),
                                child: Text('Token #${request.tokenId}', style: AppTextStyles.caption.copyWith(color: AppColors.primary)),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),
                          
                          // Requested Changes
                          Container(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('New Starting Price', style: AppTextStyles.caption),
                                          const SizedBox(height: 4),
                                          Text('${request.reAuctionStartingPrice ?? request.price} ETH', style: AppTextStyles.labelLarge.copyWith(color: AppColors.primary)),
                                        ],
                                      ),
                                    ),
                                    Container(width: 1, height: 40, color: AppColors.border),
                                    const SizedBox(width: AppSpacing.lg),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('New Duration', style: AppTextStyles.caption),
                                          const SizedBox(height: 4),
                                          Text(_formatDuration(request.reAuctionDuration ?? 86400), style: AppTextStyles.labelLarge),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                if (request.reAuctionNotes != null && request.reAuctionNotes!.isNotEmpty) ...[
                                  const SizedBox(height: AppSpacing.md),
                                  const Divider(color: AppColors.border),
                                  const SizedBox(height: AppSpacing.sm),
                                  Text('Creator Notes', style: AppTextStyles.caption),
                                  const SizedBox(height: 4),
                                  Text(request.reAuctionNotes!, style: AppTextStyles.bodyMedium.copyWith(fontStyle: FontStyle.italic)),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xl),
                    
                    // Actions
                    SizedBox(
                      width: 140,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: PrimaryButton(
                              text: 'Approve',
                              onPressed: isProcessing ? null : () => _handleApprove(request),
                              isLoading: isProcessing,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: isProcessing ? null : () => _handleReject(request),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.danger,
                                side: const BorderSide(color: AppColors.danger),
                              ),
                              child: const Text('Reject'),
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
        );
      },
    );
  }
}
