import 'package:flutter/material.dart';
import 'package:nft_logo_marketplace/core/utils/firestore_error_handler.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/core/theme/app_radius.dart';
import 'package:nft_logo_marketplace/core/theme/app_spacing.dart';
import 'package:nft_logo_marketplace/shared/models/auction.dart';
import 'package:nft_logo_marketplace/shared/models/user_model.dart';
import 'package:nft_logo_marketplace/core/services/firestore_service.dart';
import 'package:nft_logo_marketplace/core/utils/user_display_utils.dart';

class LeaderboardModal extends StatefulWidget {
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
  State<LeaderboardModal> createState() => _LeaderboardModalState();
}

class _LeaderboardModalState extends State<LeaderboardModal> {
  final Map<String, UserModel> _userCache = {};

  Future<UserModel?> _getUserProfile(String bidderId, String walletAddress) async {
    final lowerWallet = walletAddress.toLowerCase();
    if (_userCache.containsKey(lowerWallet)) return _userCache[lowerWallet];

    try {
      if (bidderId.isNotEmpty) {
        final doc = await FirestoreService.instance.db.collection('users').doc(bidderId).get();
        if (doc.exists) {
          final user = UserModel.fromFirestore(doc.data()!);
          _userCache[lowerWallet] = user;
          return user;
        }
      }
      final q = await FirestoreService.instance.db.collection('users').where('walletAddress', isEqualTo: walletAddress).limit(1).get();
      if (q.docs.isNotEmpty) {
        final user = UserModel.fromFirestore(q.docs.first.data());
        _userCache[lowerWallet] = user;
        return user;
      }
    } catch (_) {}
    return null;
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
              stream: FirestoreService.instance.getAuctionBidsStream(widget.tokenId),
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
                          !widget.isLive ? 'No one participated in this auction' : 'No bids yet',
                          style: AppTextStyles.labelLarge.copyWith(color: AppColors.textSecondary),
                        ),
                        if (widget.isLive) ...[
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

                    return _BidderItem(
                      bid: bid, 
                      index: index, 
                      isFirst: isFirst,
                      fetchUser: _getUserProfile,
                    );
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
  final Future<UserModel?> Function(String, String) fetchUser;

  const _BidderItem({
    required this.bid,
    required this.index,
    required this.isFirst,
    required this.fetchUser,
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
    return FutureBuilder<UserModel?>(
      future: fetchUser(bid.bidderId, bid.bidderWallet),
      builder: (context, snapshot) {
        final userProfile = snapshot.data;
        
        final displayName = UserDisplayUtils.getDisplayName(userProfile, bid.bidderWallet);
        final country = userProfile?.country ?? 'Unknown';
        
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
              UserDisplayUtils.buildAvatar(userProfile, bid.bidderWallet, radius: 23, isFirst: isFirst),
              const SizedBox(width: AppSpacing.md),
              
              // Identity & Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName, 
                      style: AppTextStyles.labelMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (country != 'Unknown')
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '${_getCountryFlag(country)} $country',
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
