import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:nft_logo_marketplace/shared/models/logo_nft.dart';
import 'package:nft_logo_marketplace/shared/models/auction.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_radius.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/core/theme/app_shadows.dart';
import 'package:nft_logo_marketplace/shared/widgets/auction_badge.dart';
import 'package:nft_logo_marketplace/core/services/web3_service.dart';
class LogoCard extends StatefulWidget {
  final LogoNFT logo;
  final Auction? auction;
  final VoidCallback? onTap;
  final bool showPrice;
  final bool showOwner;

  const LogoCard({
    super.key,
    required this.logo,
    this.auction,
    this.onTap,
    this.showPrice = true,
    this.showOwner = false,
  });

  @override
  State<LogoCard> createState() => _LogoCardState();
}

class _LogoCardState extends State<LogoCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final bool isWonNft = widget.logo.ownershipType == 'collected' || widget.logo.auctionStatus == 'PAYMENT_COMPLETED' || widget.logo.auctionStatus == 'COMPLETED';
    final bool hasActiveAuction = widget.auction != null && widget.auction!.isOngoing;
    final bool isLive = hasActiveAuction || (widget.logo.isAuctionActive && widget.logo.endTime != null && DateTime.now().isBefore(widget.logo.endTime!));

    String formatStaticDuration(int seconds) {
      int h = seconds ~/ 3600;
      int m = (seconds % 3600) ~/ 60;
      int s = seconds % 60;
      String hh = h.toString().padLeft(2, '0');
      String mm = m.toString().padLeft(2, '0');
      String ss = s.toString().padLeft(2, '0');
      return '$hh.$mm,$ss';
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? 1.03 : 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            gradient: isWonNft 
                ? LinearGradient(
                    colors: [
                      AppColors.accentOrange.withValues(alpha: 0.1),
                      AppColors.card,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : AppColors.cardGradient,
            border: Border.all(
              color: isWonNft 
                  ? AppColors.accentOrange.withValues(alpha: 0.5)
                  : (hasActiveAuction ? AppColors.primary : AppColors.border),
              width: isWonNft || hasActiveAuction ? 1.5 : 1.0,
            ),
            boxShadow: isWonNft
                ? [BoxShadow(color: AppColors.accentOrange.withValues(alpha: 0.2), blurRadius: 12, spreadRadius: 2)]
                : (hasActiveAuction ? AppShadows.glowPrimary : AppShadows.soft),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image Section
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Container(
                          color: AppColors.surface,
                          child: () {
                            String imgUrl = widget.logo.imageUrl;
                            if (imgUrl.contains('dweb.link/ipfs/')) {
                              imgUrl = imgUrl.replaceAll('dweb.link/ipfs/', 'ipfs.io/ipfs/');
                            } else if (imgUrl.contains('gateway.pinata.cloud/ipfs/')) {
                              imgUrl = imgUrl.replaceAll('gateway.pinata.cloud/ipfs/', 'ipfs.io/ipfs/');
                            } else if (imgUrl.contains('ipfs://')) {
                              imgUrl = imgUrl.replaceAll('ipfs://', 'https://ipfs.io/ipfs/');
                            }
                            
                            return imgUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: imgUrl,
                                    fit: BoxFit.cover,
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
                                  )
                            : _buildPlaceholder();
                          }(),
                      ),
                      // Badges (Top Right)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Column(
                           crossAxisAlignment: CrossAxisAlignment.end,
                           children: [
                             if (isWonNft)
                               const AuctionBadge(text: '🏆 AUCTION WINNER', type: BadgeType.success)
                             else if (widget.logo.isFrozen)
                               const AuctionBadge(text: 'FROZEN', type: BadgeType.frozen)
                             else if (isLive && !widget.logo.isFrozen)
                               const AuctionBadge(text: 'LIVE', type: BadgeType.live),
                             if (!isLive && widget.logo.isInAuction)
                               const AuctionBadge(text: 'AUCTION', type: BadgeType.success),
                             if (widget.logo.isForSale && !widget.logo.isInAuction)
                               const AuctionBadge(text: 'FOR SALE', type: BadgeType.success),
                             // Payment pending badge
                             if (widget.logo.auctionCreated && !widget.logo.isActive && widget.logo.highestBidderWallet != null && !isLive)
                               const AuctionBadge(text: 'PAYMENT', type: BadgeType.neutral),
                             // Ended with no bids badge
                             if (widget.logo.auctionCreated && !widget.logo.isActive && widget.logo.highestBidderWallet == null && !widget.logo.isInAuction && !isLive)
                               const AuctionBadge(text: 'NO BIDS', type: BadgeType.ended),
                             if (!widget.logo.isInAuction && !widget.logo.isForSale && !widget.logo.auctionCreated &&
                                 widget.logo.status == ValidationStatus.approved)
                               const AuctionBadge(text: 'APPROVED', type: BadgeType.success),
                             if (widget.logo.status == ValidationStatus.rejected)
                               const AuctionBadge(text: 'REJECTED', type: BadgeType.ended),
                           ],
                        ),
                      ),
                      // Category Badge (Top Left)
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.background.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.category_outlined, size: 12, color: AppColors.primary),
                              const SizedBox(width: 4),
                              Text(
                                widget.logo.category,
                                style: AppTextStyles.caption.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Timer Badge
                      if (isLive)
                        Positioned(
                          bottom: 12,
                          right: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.background.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(AppRadius.pill),
                              border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withValues(alpha: 0.3),
                                  blurRadius: 8,
                                ),
                              ]
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.timer_outlined, color: AppColors.textPrimary, size: 14),
                                const SizedBox(width: 4),
                                _AuctionCountdown(endTime: widget.auction?.endTime ?? widget.logo.endTime!),
                              ],
                            ),
                          ),
                        )
                      else if (widget.logo.auctionCreated && !widget.logo.isAuctionActive && widget.logo.highestBidderWallet == null)
                        // Show static duration if auction has been created but hasn't gone live yet, or has ended with no bids
                        Positioned(
                          bottom: 12,
                          right: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.background.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(AppRadius.pill),
                              border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.timer_outlined, color: AppColors.textPrimary, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  formatStaticDuration(widget.logo.auctionDuration ?? 86400),
                                  style: AppTextStyles.labelMedium,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                ),
                // Info Section
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                           Text(
                             widget.logo.name,
                             style: AppTextStyles.subtitle1.copyWith(fontSize: 13),
                             maxLines: 1,
                             overflow: TextOverflow.ellipsis,
                           ),
                           if (isWonNft) ...[
                             const SizedBox(height: 2),
                             if (widget.logo.canViewCopyrightHash(currentWallet: Web3Service.instance.currentAddress ?? '')) ...[
                               Row(
                                 children: [
                                   const Icon(Icons.verified, size: 10, color: AppColors.success),
                                   const SizedBox(width: 4),
                                   Text('Copyright Verified', style: AppTextStyles.caption.copyWith(color: AppColors.success, fontWeight: FontWeight.w600, fontSize: 10)),
                                 ],
                               ),
                               const SizedBox(height: 2),
                             ],
                             Text('Collected via Auction', style: AppTextStyles.caption.copyWith(color: AppColors.accentOrange, fontSize: 10)),
                           ],
                          const SizedBox(height: 2),
                          if (widget.showOwner)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'By ${widget.logo.creatorUsername ?? 'Verified Creator'}',
                                  style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, fontSize: 10),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                        ],
                      ),
                      if (widget.showPrice) ...[
                        const SizedBox(height: 4),
                        _buildPriceRow(),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildPriceRow() {
    final bool hasActiveAuction = widget.auction != null && widget.auction!.isOngoing;
    final displayPrice = hasActiveAuction
        ? (widget.auction!.highestBid > 0 ? widget.auction!.highestBid : widget.auction!.startingPrice)
        : widget.logo.price;
    final label = hasActiveAuction
        ? (widget.auction!.highestBid > 0 ? 'Highest Bid' : 'Starting Bid')
        : 'Price';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary, fontSize: 9),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Row(
                  children: [
                    Image.asset('assets/images/logo.png', width: 12, height: 12, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${displayPrice.toStringAsFixed(2)} ETH',
                        style: AppTextStyles.labelLarge.copyWith(color: AppColors.accent, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
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

class _AuctionCountdown extends StatefulWidget {
  final DateTime endTime;
  const _AuctionCountdown({required this.endTime});

  @override
  State<_AuctionCountdown> createState() => _AuctionCountdownState();
}

class _AuctionCountdownState extends State<_AuctionCountdown> {
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

  String _format(Duration d) {
    if (d == Duration.zero || d.isNegative) return '00.00,00';
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
    int totalHours = d.inDays * 24 + d.inHours.remainder(24);
    return '${twoDigits(totalHours)}.$twoDigitMinutes,$twoDigitSeconds';
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.endTime.difference(DateTime.now());
    final d = remaining.isNegative ? Duration.zero : remaining;
    return Text(
      _format(d),
      style: AppTextStyles.labelMedium,
    );
  }
}
