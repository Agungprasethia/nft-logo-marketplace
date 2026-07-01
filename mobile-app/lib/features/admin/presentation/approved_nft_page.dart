import 'package:flutter/material.dart';
import 'package:nft_logo_marketplace/core/utils/firestore_error_handler.dart';
import 'package:nft_logo_marketplace/shared/models/logo_nft.dart';
import 'package:nft_logo_marketplace/core/services/firestore_service.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/core/theme/app_spacing.dart';
import 'package:nft_logo_marketplace/core/theme/app_shadows.dart';
import 'package:nft_logo_marketplace/core/theme/app_radius.dart';

class ApprovedNftPage extends StatefulWidget {
  const ApprovedNftPage({super.key});

  @override
  State<ApprovedNftPage> createState() => _ApprovedNftPageState();
}

class _ApprovedNftPageState extends State<ApprovedNftPage> {

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LogoNFT>>(
      stream: FirestoreService.instance.getApprovedNFTsStream(),
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

        final nfts = snapshot.data ?? [];

        if (nfts.isEmpty) {
          return Center(
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
                  child: const Icon(Icons.check_circle_outline, size: 48, color: AppColors.success),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'No approved NFTs yet',
                  style: AppTextStyles.labelLarge.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
      onRefresh: () async { if (mounted) setState(() {}); },
      child: ListView.builder(
          padding: const EdgeInsets.all(AppSpacing.xl),
          itemCount: nfts.length,
          itemBuilder: (context, index) {
            final nft = nfts[index];
            return Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                boxShadow: AppShadows.soft,
              ),
              child: Row(
                children: [
                  // NFT Image
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      color: AppColors.surfaceLight,
                      border: Border.all(color: AppColors.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: nft.imageUrl.isNotEmpty
                        ? Image.network(
                            nft.imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Center(
                              child: Icon(Icons.image, color: AppColors.textSecondary),
                            ),
                          )
                        : const Center(
                            child: Icon(Icons.image, color: AppColors.textSecondary),
                          ),
                  ),
                  const SizedBox(width: AppSpacing.lg),

                  // NFT Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nft.name,
                          style: AppTextStyles.h3,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Token #${nft.tokenId}',
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Creator: ${nft.creatorUsername ?? nft.creatorShort}',
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (nft.creatorUsername != null && nft.creatorUsername!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Wallet: ${nft.creatorShort}',
                            style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              nft.auctionCreated ? Icons.gavel : Icons.check_circle,
                              size: 14,
                              color: nft.auctionCreated ? AppColors.accentOrange : AppColors.success,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              nft.auctionCreated ? 'In Auction' : 'Available',
                              style: AppTextStyles.labelSmall.copyWith(
                                color: nft.auctionCreated ? AppColors.accentOrange : AppColors.success,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Category badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      nft.category,
                      style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary),
                    ),
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
}

