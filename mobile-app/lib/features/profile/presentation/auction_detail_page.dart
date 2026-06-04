import 'package:flutter/material.dart';
import '../../../core/services/firestore_service.dart';

import '../../../shared/models/auction.dart';
import '../../../shared/models/logo_nft.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/core/theme/app_radius.dart';
import 'package:nft_logo_marketplace/core/theme/app_spacing.dart';
import '../../../shared/widgets/auction_badge.dart';

class AuctionDetailPage extends StatefulWidget {
  final Auction auction;
  final LogoNFT logo;

  const AuctionDetailPage({super.key, required this.auction, required this.logo});

  @override
  State<AuctionDetailPage> createState() => _AuctionDetailPageState();
}

class _AuctionDetailPageState extends State<AuctionDetailPage> {
  final _firestore = FirestoreService.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Auction Details', style: TextStyle(color: AppColors.textPrimary)),
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildNFTCard(),
              const SizedBox(height: AppSpacing.lg),
              _buildStatusSection(),
              const SizedBox(height: AppSpacing.lg),
              _buildStatsSection(),
              const SizedBox(height: AppSpacing.lg),
              if (widget.auction.status == AuctionStatus.paymentPending) _buildPaymentMonitoring(),
              if (widget.auction.status == AuctionStatus.paymentPending) const SizedBox(height: AppSpacing.lg),
              _buildLeaderboard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNFTCard() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Image.network(
              widget.logo.imageUrl,
              width: 80,
              height: 80,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(width: 80, height: 80, color: AppColors.border),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.logo.name, style: AppTextStyles.h3),
                const SizedBox(height: 4),
                Text('Token ID: #${widget.logo.tokenId}', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary)),
                const SizedBox(height: 8),
                Text('Owner: ${_shortenWallet(widget.logo.ownerWallet)}', style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
                Text('Creator: ${_shortenWallet(widget.logo.creatorWallet)}', style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Status', style: AppTextStyles.h3),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            _buildStatusBadge(),
            const Spacer(),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusBadge() {
    switch (widget.auction.status) {
      case AuctionStatus.active:
        return const AuctionBadge(text: 'LIVE', type: BadgeType.success);
      case AuctionStatus.paymentPending:
        return const AuctionBadge(text: 'PAYMENT PENDING', type: BadgeType.neutral);
      case AuctionStatus.paymentCompleted:
      case AuctionStatus.claimed:
        return const AuctionBadge(text: 'SOLD', type: BadgeType.success);
      case AuctionStatus.failedPayment:
      case AuctionStatus.paymentExpired:
        return const AuctionBadge(text: 'PAYMENT FAILED', type: BadgeType.ended);
      case AuctionStatus.endedNoBids:
        return const AuctionBadge(text: 'UNSOLD', type: BadgeType.ended);
      case AuctionStatus.cancelled:
        return const AuctionBadge(text: 'CANCELLED', type: BadgeType.ended);
      default:
        return const AuctionBadge(text: 'ENDED', type: BadgeType.ended);
    }
  }

  Widget _buildStatsSection() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Auction Details', style: AppTextStyles.h3),
          const SizedBox(height: AppSpacing.md),
          _buildStatRow('Starting Price', '${widget.auction.startingPrice} ETH'),
          _buildStatRow('Highest Bid', '${widget.auction.highestBid} ETH', highlight: true),
          _buildStatRow('Total Bids', '${widget.auction.totalBids}'),
          _buildStatRow('Start Time', _formatDate(widget.auction.startTime)),
          _buildStatRow('End Time', _formatDate(widget.auction.endTime)),
          if (widget.auction.status == AuctionStatus.paymentCompleted || widget.auction.status == AuctionStatus.claimed)
            _buildStatRow('Winner', _shortenWallet(widget.auction.highestBidderWallet)),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
          Text(
            value,
            style: AppTextStyles.bodyLarge.copyWith(
              color: highlight ? AppColors.primary : AppColors.textPrimary,
              fontWeight: highlight ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMonitoring() {
    final now = DateTime.now();
    final deadline = widget.auction.endTime.add(const Duration(hours: 24));
    final duration = deadline.difference(now);
    
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.warning),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.payment, color: AppColors.warning),
              const SizedBox(width: AppSpacing.sm),
              Text('Waiting for Payment', style: AppTextStyles.h3.copyWith(color: AppColors.warning)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Winner: ${_shortenWallet(widget.auction.highestBidderWallet)}', style: AppTextStyles.bodyMedium),
          const SizedBox(height: 4),
          Text('Amount Due: ${widget.auction.highestBid} ETH', style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Time Remaining: ${duration.inHours}h ${duration.inMinutes.remainder(60)}m',
            style: AppTextStyles.labelLarge.copyWith(color: AppColors.danger),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderboard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Leaderboard', style: AppTextStyles.h3),
        const SizedBox(height: AppSpacing.sm),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.border),
          ),
          child: StreamBuilder<List<Bid>>(
            stream: _firestore.getAuctionBidsStream(widget.logo.tokenId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
              }
              final bids = snapshot.data ?? [];
              if (bids.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('No bids were placed', style: TextStyle(color: AppColors.textSecondary))),
                );
              }
              
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: bids.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
                itemBuilder: (context, index) {
                  final bid = bids[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: index == 0 ? AppColors.warning : AppColors.surface,
                      child: Text('${index + 1}', style: TextStyle(color: index == 0 ? Colors.white : AppColors.textPrimary)),
                    ),
                    title: Text(_shortenWallet(bid.bidderWallet), style: AppTextStyles.bodyMedium),
                    subtitle: Text(_formatDate(bid.firstBidTimestamp), style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
                    trailing: Text('${bid.amount} ETH', style: AppTextStyles.labelLarge.copyWith(color: AppColors.primary)),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  String _shortenWallet(String? wallet) {
    if (wallet == null || wallet.length < 10) return 'Unknown';
    return '${wallet.substring(0, 6)}...${wallet.substring(wallet.length - 4)}';
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
