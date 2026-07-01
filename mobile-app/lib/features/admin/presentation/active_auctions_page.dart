import 'package:flutter/material.dart';
import 'package:nft_logo_marketplace/core/utils/firestore_error_handler.dart';
import 'package:nft_logo_marketplace/shared/models/auction.dart';
import 'package:nft_logo_marketplace/core/services/firestore_service.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/core/theme/app_spacing.dart';
import 'package:nft_logo_marketplace/core/theme/app_shadows.dart';
import 'package:nft_logo_marketplace/core/theme/app_radius.dart';
import 'package:nft_logo_marketplace/core/utils/notification_manager.dart';
import 'package:nft_logo_marketplace/shared/models/app_notification.dart';

class ActiveAuctionsPage extends StatefulWidget {
  const ActiveAuctionsPage({super.key});

  @override
  State<ActiveAuctionsPage> createState() => _ActiveAuctionsPageState();
}

class _ActiveAuctionsPageState extends State<ActiveAuctionsPage> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Auction>>(
      stream: FirestoreService.instance.getAllAuctionsStream(),
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

        final auctions = snapshot.data ?? [];

        if (auctions.isEmpty) {
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
                  child: const Icon(Icons.gavel_outlined, size: 48, color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'No auctions found',
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
          itemCount: auctions.length,
          itemBuilder: (context, index) {
            final auction = auctions[index];
            final isActive = auction.status == AuctionStatus.active;

            Color statusColor;
            String statusText;
            switch (auction.status) {
              case AuctionStatus.active:
                statusColor = AppColors.success;
                statusText = 'Active';
                break;
              case AuctionStatus.ended:
                statusColor = AppColors.danger;
                statusText = 'Ended';
                break;
              case AuctionStatus.paymentPending:
                statusColor = AppColors.accentOrange;
                statusText = 'Payment Pending';
                break;
              case AuctionStatus.claimed:
                statusColor = AppColors.success;
                statusText = 'Claimed';
                break;
              case AuctionStatus.failedPayment:
                statusColor = AppColors.danger;
                statusText = 'Payment Failed';
                break;
              case AuctionStatus.frozen:
                statusColor = AppColors.frozenBlue;
                statusText = 'Frozen';
                break;
              case AuctionStatus.cancelled:
                statusColor = AppColors.textSecondary;
                statusText = 'Cancelled';
                break;
              case AuctionStatus.draft:
                statusColor = AppColors.accentOrange;
                statusText = 'Draft';
                break;
              case AuctionStatus.endedNoBids:
                statusColor = AppColors.textSecondary;
                statusText = 'Ended - No Bids';
                break;
              case AuctionStatus.paymentExpired:
                statusColor = AppColors.danger;
                statusText = 'Payment Expired';
                break;
              case AuctionStatus.paymentCompleted:
                statusColor = AppColors.success;
                statusText = 'Payment Completed';
                break;
              case AuctionStatus.reAuctionRequested:
                statusColor = AppColors.accentOrange;
                statusText = 'Re-Auction Requested';
                break;
              case AuctionStatus.rejected:
                statusColor = AppColors.danger;
                statusText = 'Rejected';
                break;
            }

            return Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                boxShadow: AppShadows.soft,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Auction ID
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          'Auction #${auction.auctionId}',
                          style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary),
                        ),
                      ),
                      const Spacer(),
                      // Status badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          statusText,
                          style: AppTextStyles.labelSmall.copyWith(color: statusColor),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      // Actions Menu
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, color: AppColors.textSecondary, size: 20),
                        color: AppColors.surfaceLight,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                        onSelected: (value) async {
                          if (value == 'leaderboard') {
                            _showLeaderboardDialog(context, auction);
                          } else if (value == 'freeze') {
                            await FirestoreService.instance.freezeNFT(auction.tokenId);
                            if (context.mounted) {
                              NotificationManager.show(context: context, title: 'Frozen', message: 'Auction Frozen (Bidding Disabled)', type: NotificationType.warning);
                            }
                          } else if (value == 'unfreeze') {
                            await FirestoreService.instance.unfreezeNFT(auction.tokenId);
                            if (context.mounted) {
                              NotificationManager.show(context: context, title: 'Unfrozen', message: 'Auction Unfrozen (Bidding Enabled)', type: NotificationType.success);
                            }
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'leaderboard',
                            child: Row(
                              children: [
                                const Icon(Icons.leaderboard_outlined, color: AppColors.primary, size: 18),
                                const SizedBox(width: 8),
                                Text('View Leaderboard', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary)),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'freeze',
                            child: Row(
                              children: [
                                const Icon(Icons.ac_unit, color: AppColors.frozenBlue, size: 18),
                                const SizedBox(width: 8),
                                Text('Freeze Auction', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary)),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'unfreeze',
                            child: Row(
                              children: [
                                const Icon(Icons.local_fire_department, color: AppColors.accentOrange, size: 18),
                                const SizedBox(width: 8),
                                Text('Unfreeze Auction', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Token & Seller
                  Row(
                    children: [
                      const Icon(Icons.token, size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 8),
                      Text(
                        'Token #${auction.tokenId}',
                        style: AppTextStyles.bodyMedium,
                      ),
                      const Spacer(),
                      const Icon(Icons.person, size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        _shortenAddress(auction.sellerWallet),
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  // Bid info
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        // Highest bid
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Highest Bid',
                                style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary),
                              ),
                              Text(
                                auction.highestBid > 0
                                    ? '${auction.highestBid.toStringAsFixed(4)} ETH'
                                    : '${auction.startingPrice.toStringAsFixed(4)} ETH',
                                style: AppTextStyles.h3,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        // Total bids
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                'Total Bids',
                                style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary),
                              ),
                              Text(
                                '${auction.totalBids}',
                                style: AppTextStyles.h3,
                              ),
                            ],
                          ),
                        ),
                        // Time
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                isActive ? 'Time Left' : 'Status',
                                style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary),
                              ),
                              Text(
                                isActive ? auction.timeRemainingFormatted : statusText,
                                style: AppTextStyles.labelLarge.copyWith(color: isActive ? AppColors.accentOrange : AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Leaderboard Button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _showLeaderboardDialog(context, auction),
                      icon: const Icon(Icons.leaderboard_outlined, size: 18),
                      label: Text('View Leaderboard (${auction.totalBids} bids)'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
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

  void _showLeaderboardDialog(BuildContext context, Auction auction) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xxl)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(AppSpacing.xl),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.15),
                      AppColors.surface,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.emoji_events, color: AppColors.primary, size: 24),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Leaderboard', style: AppTextStyles.h2),
                          const SizedBox(height: 2),
                          Text(
                            'Auction #${auction.auctionId} â€¢ Token #${auction.tokenId}',
                            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.textSecondary),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),

              // Bids Stream
              Expanded(
                child: StreamBuilder<List<Bid>>(
                  stream: FirestoreService.instance.getAuctionBidsStream(auction.tokenId),
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
                            Icon(Icons.gavel_outlined, size: 56, color: AppColors.textSecondary.withValues(alpha: 0.4)),
                            const SizedBox(height: AppSpacing.md),
                            Text('No bids yet', style: AppTextStyles.labelLarge.copyWith(color: AppColors.textSecondary)),
                            const SizedBox(height: AppSpacing.sm),
                            Text('Waiting for bidders...', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      itemCount: bids.length,
                      itemBuilder: (context, index) {
                        final bid = bids[index];
                        final isFirst = index == 0;

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
                                width: 32,
                                height: 32,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: isFirst ? AppColors.primary.withValues(alpha: 0.2) : AppColors.surfaceLight,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '#${index + 1}',
                                  style: AppTextStyles.labelMedium.copyWith(
                                    color: isFirst ? AppColors.primary : AppColors.textSecondary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),

                              // Bidder info
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _shortenAddress(bid.bidderWallet),
                                      style: AppTextStyles.labelMedium.copyWith(
                                        fontWeight: isFirst ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                    if (isFirst)
                                      Text('👑 Highest Bidder', style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),

                              // Amount
                              Text(
                                '${bid.amount.toStringAsFixed(4)} ETH',
                                style: AppTextStyles.labelLarge.copyWith(
                                  color: isFirst ? AppColors.primary : AppColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _shortenAddress(String address) {
    if (address.length <= 10) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
  }
}
