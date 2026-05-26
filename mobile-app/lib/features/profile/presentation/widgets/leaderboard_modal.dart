import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:nft_logo_marketplace/core/utils/firestore_error_handler.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/core/theme/app_radius.dart';
import 'package:nft_logo_marketplace/core/theme/app_spacing.dart';
import 'package:nft_logo_marketplace/shared/models/auction.dart';
import 'package:nft_logo_marketplace/shared/models/user_model.dart';
import 'package:nft_logo_marketplace/core/services/firestore_service.dart';

class LeaderboardModal extends StatelessWidget {
  final int tokenId;
  final AuctionStatus status;
  final bool isLive;

  const LeaderboardModal({
    super.key,
    required this.tokenId,
    required this.status,
    required this.isLive,
  });

  static Future<void> show(BuildContext context, {required int tokenId, required AuctionStatus status, required bool isLive}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => LeaderboardModal(tokenId: tokenId, status: status, isLive: isLive),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.1),
            blurRadius: 20,
            spreadRadius: 2,
          )
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.md),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textSecondary.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Live Leaderboard', style: AppTextStyles.h2),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          
          const Divider(color: AppColors.border),
          
          // Stream of bids
          Expanded(
            child: StreamBuilder<List<Bid>>(
              stream: FirestoreService.instance.getAuctionBidsStream(tokenId),
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

                final bids = snapshot.data ?? [];

                if (bids.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.gavel_outlined, size: 64, color: AppColors.textSecondary.withValues(alpha: 0.5)),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          !isLive ? 'No one participated in this auction' : 'No bids yet',
                          style: AppTextStyles.labelLarge.copyWith(color: AppColors.textSecondary),
                        ),
                        if (isLive) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text('Wait for the community to bid', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                        ],
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                  itemCount: bids.length,
                  itemBuilder: (context, index) {
                    final bid = bids[index];
                    final isFirst = index == 0;

                    return _BidderItem(bid: bid, index: index, isFirst: isFirst);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

class _BidderItem extends StatelessWidget {
  final Bid bid;
  final int index;
  final bool isFirst;

  const _BidderItem({
    required this.bid,
    required this.index,
    required this.isFirst,
  });

  String _getCountryFlag(String country) {
    switch (country.toLowerCase()) {
      case 'indonesia': return '🇮🇩';
      case 'united states': return '🇺🇸';
      case 'japan': return '🇯🇵';
      case 'south korea': return '🇰🇷';
      case 'united kingdom': return '🇬🇧';
      case 'singapore': return '🇸🇬';
      case 'malaysia': return '🇲🇾';
      case 'australia': return '🇦🇺';
      default: return '🏳️';
    }
  }

  @override
  Widget build(BuildContext context) {
    final future = bid.bidderId.isNotEmpty 
        ? FirestoreService.instance.db.collection('users').doc(bid.bidderId).get().then((doc) => doc.exists ? UserModel.fromFirestore(doc.data()!) : null)
        : FirestoreService.instance.db.collection('users').where('walletAddress', isEqualTo: bid.bidderWallet).limit(1).get().then((q) => q.docs.isNotEmpty ? UserModel.fromFirestore(q.docs.first.data()) : null);

    return FutureBuilder<UserModel?>(
      future: future,
      builder: (context, snapshot) {
        final userProfile = snapshot.data;
        
        final username = userProfile?.username ?? 'Anonymous Bidder';
        final country = userProfile?.country ?? 'Unknown';
        final profileImageUrl = userProfile?.profileImage;
        
        final hasImage = profileImageUrl != null && profileImageUrl.isNotEmpty;
        final isBase64 = hasImage && profileImageUrl.startsWith('data:image');
        
        return Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          decoration: BoxDecoration(
            color: isFirst ? AppColors.primary.withValues(alpha: 0.1) : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: isFirst ? AppColors.primary.withValues(alpha: 0.5) : AppColors.border),
          ),
          child: Row(
            children: [
              // Rank
              Container(
                width: 30,
                alignment: Alignment.center,
                child: Text(
                  '#${index + 1}',
                  style: AppTextStyles.h3.copyWith(
                    color: isFirst ? AppColors.primary : AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              
              // Avatar
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: hasImage ? null : (isFirst ? AppColors.primaryGradient : null),
                  color: hasImage ? null : (isFirst ? null : AppColors.surfaceLight),
                  border: Border.all(color: isFirst ? AppColors.primary : AppColors.border, width: 2),
                  image: hasImage 
                    ? DecorationImage(
                        image: isBase64 
                            ? MemoryImage(base64Decode(profileImageUrl.split(',')[1])) as ImageProvider
                            : NetworkImage(profileImageUrl),
                        fit: BoxFit.cover,
                      )
                    : null,
                ),
                child: !hasImage 
                    ? (isFirst 
                        ? const Icon(Icons.emoji_events, size: 22, color: Colors.white) 
                        : const Icon(Icons.person, size: 22, color: AppColors.textSecondary))
                    : null,
              ),
              const SizedBox(width: AppSpacing.md),
              
              // Identity & Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      username, 
                      style: AppTextStyles.labelMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        country != 'Unknown' ? '${_getCountryFlag(country)} $country' : country,
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isFirst)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('Current Leader', style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
              ),
              
              // Bid Amount
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${bid.amount.toStringAsFixed(4)} ETH', style: AppTextStyles.labelLarge.copyWith(color: isFirst ? AppColors.primary : AppColors.textPrimary)),
                ],
              ),
            ],
          ),
        );
      }
    );
  }
}
