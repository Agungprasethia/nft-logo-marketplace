import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:nft_logo_marketplace/shared/models/auction.dart';
import 'package:nft_logo_marketplace/shared/models/logo_nft.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_radius.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/shared/widgets/auction_badge.dart';

class AuctionCard extends StatefulWidget {
  final Auction auction;
  final LogoNFT? logo;
  final VoidCallback? onTap;

  const AuctionCard({
    super.key,
    required this.auction,
    this.logo,
    this.onTap,
  });

  @override
  State<AuctionCard> createState() => _AuctionCardState();
}

class _AuctionCardState extends State<AuctionCard> {
  @override
  Widget build(BuildContext context) {
    final auction = widget.auction;
    final logo = widget.logo;
    
    String imageUrl = logo?.imageUrl ?? '';
    if (imageUrl.contains('dweb.link/ipfs/')) {
       imageUrl = imageUrl.replaceAll('dweb.link/ipfs/', 'ipfs.io/ipfs/');
    } else if (imageUrl.contains('ipfs://')) {
       imageUrl = imageUrl.replaceAll('ipfs://', 'https://ipfs.io/ipfs/');
    }

    final isLive = auction.isOngoing && logo?.isFrozen != true;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          color: AppColors.card,
          border: Border.all(
            color: isLive ? AppColors.primary : AppColors.border,
            width: isLive ? 1.5 : 1.0,
          ),
          boxShadow: isLive
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  )
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image Section
              AspectRatio(
                aspectRatio: 1.0,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      color: AppColors.surface,
                      child: logo != null && logo.imageUrl.isNotEmpty
                          ? (imageUrl.startsWith('data:image')
                              ? Image.memory(
                                  base64Decode(imageUrl.split(',').last),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _buildPlaceholder(),
                                )
                              : CachedNetworkImage(
                                  imageUrl: imageUrl,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 400,
                                  memCacheHeight: 400,
                                  filterQuality: FilterQuality.low,
                                  placeholder: (context, url) => Container(
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [AppColors.surface, AppColors.card, AppColors.surface],
                                        stops: [0.0, 0.5, 1.0],
                                        begin: Alignment(-1.0, -0.5),
                                        end: Alignment(1.0, 0.5),
                                      ),
                                    ),
                                  ),
                                  errorWidget: (context, url, error) => _buildPlaceholder(),
                                ))
                          : _buildPlaceholder(),
                    ),
                    // Live/Frozen Badge
                    Positioned(
                      top: 12,
                      left: 12,
                      child: logo?.isFrozen == true
                          ? const AuctionBadge(text: 'FROZEN', type: BadgeType.frozen)
                          : (logo?.auctionStatus == 'RE_AUCTION_REQUESTED'
                              ? const AuctionBadge(text: 'RE-AUCTION REQUESTED', type: BadgeType.neutral)
                              : (logo?.auctionStatus == 'ENDED_NO_BID' || logo?.auctionStatus == 'ended_no_bids'
                                  ? const AuctionBadge(text: 'NO BIDS', type: BadgeType.ended)
                                  : (auction.isOngoing
                                      ? const AuctionBadge(text: 'LIVE', type: BadgeType.live)
                                      : const AuctionBadge(text: 'ENDED', type: BadgeType.ended)))),
                    ),
                    // Timer
                    if (auction.isOngoing)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.surface.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.timer_outlined, color: AppColors.textPrimary, size: 14),
                              const SizedBox(width: 4),
                              _CardCountdownWidget(auction: auction),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Info Section
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          logo?.name ?? 'Logo #${auction.tokenId}',
                          style: AppTextStyles.subtitle1,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  auction.highestBid > 0 ? 'Highest Bid' : 'Starting Price',
                                  style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary, fontSize: 10),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${(auction.highestBid > 0 ? auction.highestBid : auction.startingPrice).toStringAsFixed(2)} ETH',
                                  style: AppTextStyles.labelLarge.copyWith(color: AppColors.accent),
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Bids',
                                  style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary, fontSize: 10),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${auction.totalBids}',
                                  style: AppTextStyles.labelLarge.copyWith(color: AppColors.textPrimary),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
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

  Widget _buildPlaceholder() {
    return const Center(
      child: Icon(
        Icons.image_outlined,
        size: 40,
        color: AppColors.textSecondary,
      ),
    );
  }
}

class _CardCountdownWidget extends StatefulWidget {
  final Auction auction;
  const _CardCountdownWidget({required this.auction});

  @override
  State<_CardCountdownWidget> createState() => _CardCountdownWidgetState();
}

class _CardCountdownWidgetState extends State<_CardCountdownWidget> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      widget.auction.timeRemainingFormatted,
      style: AppTextStyles.labelMedium,
    );
  }
}
