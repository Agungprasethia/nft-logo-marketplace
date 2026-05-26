import 'package:flutter/material.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/core/theme/app_radius.dart';
import 'package:nft_logo_marketplace/core/theme/app_spacing.dart';

import 'package:nft_logo_marketplace/shared/models/logo_nft.dart';
import 'package:nft_logo_marketplace/core/services/web3_service.dart';
import 'package:nft_logo_marketplace/features/profile/presentation/widgets/live_auction_card.dart';

class LiveAuctionMonitoring extends StatelessWidget {
  const LiveAuctionMonitoring({super.key});

  @override
  Widget build(BuildContext context) {
    final web3 = Web3Service.instance;
    final myCreatedLogos = web3.getMyCreatedLogos();
    
    // Filter active/ended auctions associated with my creations
    final creatorAuctions = web3.allAuctions.where((a) {
      // Check if we are the creator of this auction's NFT
      return myCreatedLogos.any((l) => l.tokenId == a.tokenId);
    }).toList();

    // Sort by: Active first, then ended payment pending, etc.
    creatorAuctions.sort((a, b) {
      if (a.isOngoing && !b.isOngoing) return -1;
      if (!a.isOngoing && b.isOngoing) return 1;
      return b.createdAt.compareTo(a.createdAt);
    });

    if (creatorAuctions.isEmpty) {
      return SliverToBoxAdapter(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: AppColors.border),
          ),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.monitor_heart_outlined, size: 48, color: AppColors.textSecondary.withValues(alpha: 0.5)),
                const SizedBox(height: AppSpacing.md),
                Text('No Active Auctions', style: AppTextStyles.labelLarge.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: AppSpacing.sm),
                Text('Auctions you create will appear here for monitoring.', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary), textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final auction = creatorAuctions[index];
            LogoNFT? logo;
            try {
              logo = web3.allLogos.firstWhere((l) => l.tokenId == auction.tokenId);
            } catch (_) {}

            return LiveAuctionCard(auction: auction, logo: logo);
          },
          childCount: creatorAuctions.length,
        ),
      ),
    );
  }
}

