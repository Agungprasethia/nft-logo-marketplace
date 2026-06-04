import 'package:flutter/material.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/core/theme/app_radius.dart';
import 'package:nft_logo_marketplace/core/theme/app_spacing.dart';
import 'package:nft_logo_marketplace/shared/models/auction.dart';
import 'package:nft_logo_marketplace/shared/models/logo_nft.dart';
import 'package:nft_logo_marketplace/features/profile/presentation/widgets/live_auction_countdown.dart';
import 'package:nft_logo_marketplace/features/profile/presentation/widgets/leaderboard_modal.dart';
import 'package:nft_logo_marketplace/features/auction/presentation/auction_page.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:nft_logo_marketplace/core/services/web3_service.dart';

import 'package:nft_logo_marketplace/shared/widgets/custom_loading_indicator.dart';

class LiveAuctionCard extends StatelessWidget {
  final Auction auction;
  final LogoNFT? logo;

  const LiveAuctionCard({
    super.key,
    required this.auction,
    this.logo,
  });

  String _shortenAddress(String address) {
    if (address.length <= 10) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    final bool isLive = auction.isOngoing;
    
    String statusText;
    Color statusColor;
    Color glowColor;

    if (isLive) {
      statusText = 'LIVE';
      statusColor = AppColors.primary;
      glowColor = AppColors.primary.withValues(alpha: 0.2);
    } else {
      switch (auction.status) {
        case AuctionStatus.paymentPending:
          statusText = 'PAYMENT PENDING';
          statusColor = AppColors.accentOrange;
          glowColor = AppColors.accentOrange.withValues(alpha: 0.1);
          break;
        case AuctionStatus.ended:
        case AuctionStatus.endedNoBids:
          if (auction.totalBids == 0 || auction.status == AuctionStatus.endedNoBids) {
            statusText = 'NO BIDS';
            statusColor = AppColors.danger;
            glowColor = Colors.transparent;
          } else {
            statusText = 'ENDED';
            statusColor = AppColors.textSecondary;
            glowColor = Colors.transparent;
          }
          break;
        default:
          statusText = auction.status.name.toUpperCase();
          statusColor = AppColors.textSecondary;
          glowColor = Colors.transparent;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
        boxShadow: glowColor != Colors.transparent ? [BoxShadow(color: glowColor, blurRadius: 15, spreadRadius: 1)] : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: SizedBox(
                    width: 80,
                    height: 80,
                    child: logo != null && logo!.imageUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: logo!.imageUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: 200,
                            memCacheHeight: 200,
                            filterQuality: FilterQuality.low,
                            errorWidget: (_, __, ___) => Container(color: AppColors.surfaceLight, child: const Icon(Icons.image_outlined, color: AppColors.textSecondary)),
                            placeholder: (_, __) => Container(color: AppColors.surfaceLight, child: const CustomLoadingIndicator(size: 20)),
                          )
                        : Container(color: AppColors.surfaceLight, child: const Icon(Icons.image_outlined, color: AppColors.textSecondary)),
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              logo?.name ?? 'Token #${auction.tokenId}',
                              style: AppTextStyles.h3,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                              border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                            ),
                            child: Text(statusText, style: AppTextStyles.labelSmall.copyWith(color: statusColor, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Highest Bid', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                                Text('${auction.highestBid.toStringAsFixed(4)} ETH', style: AppTextStyles.labelMedium, overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('Highest Bidder', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                                Text(
                                  auction.highestBidderWallet != null && auction.highestBidderWallet!.isNotEmpty 
                                      ? _shortenAddress(auction.highestBidderWallet!) 
                                      : '-',
                                  style: AppTextStyles.labelMedium,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 8),
                      
                      // Countdown and Bids count
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${auction.totalBids} bids', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                          if (isLive || auction.status == AuctionStatus.active)
                            LiveAuctionCountdown(endTime: auction.endTime),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const Divider(color: AppColors.border),
            const SizedBox(height: AppSpacing.sm),
            
            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    final l = logo ?? Web3Service.instance.allLogos.cast<LogoNFT?>().firstWhere((l) => l?.tokenId == auction.tokenId, orElse: () => null);
                    if (l != null) {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => AuctionPage(logo: l)));
                    }
                  },
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Open Page'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                ElevatedButton.icon(
                  onPressed: () {
                    LeaderboardModal.show(
                      context,
                      tokenId: auction.tokenId,
                      status: auction.status,
                      isLive: isLive,
                    );
                  },
                  icon: const Icon(Icons.leaderboard_outlined, size: 16),
                  label: const Text('Leaderboard'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
