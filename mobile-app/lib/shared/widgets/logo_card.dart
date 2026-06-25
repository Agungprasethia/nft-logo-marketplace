import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:nft_logo_marketplace/shared/models/logo_nft.dart';
import 'package:nft_logo_marketplace/shared/models/auction.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_radius.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/core/theme/app_shadows.dart';
import 'package:nft_logo_marketplace/shared/models/user_model.dart';
import 'package:nft_logo_marketplace/core/utils/user_display_utils.dart';
import 'package:nft_logo_marketplace/core/services/firestore_service.dart';

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

class _LogoCardState extends State<LogoCard> with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  Future<UserModel?>? _highestBidderFuture;

  @override
  void initState() {
    super.initState();
    _initHighestBidder();
  }

  @override
  void didUpdateWidget(LogoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.auction?.highestBidderWallet != oldWidget.auction?.highestBidderWallet) {
      _initHighestBidder();
    }
  }

  void _initHighestBidder() {
    if (widget.auction != null && widget.auction!.highestBidderWallet?.isNotEmpty == true) {
      _highestBidderFuture = FirestoreService.instance.db.collection('users')
          .where('walletAddress', isEqualTo: widget.auction!.highestBidderWallet)
          .limit(1).get()
          .then((q) => q.docs.isNotEmpty ? UserModel.fromFirestore(q.docs.first.data()) : null)
          .catchError((_) => null);
    } else {
      _highestBidderFuture = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isWonNft = widget.logo.ownershipType == 'collected' || widget.logo.auctionStatus == 'PAYMENT_COMPLETED' || widget.logo.auctionStatus == 'COMPLETED';
    final bool hasActiveAuction = widget.auction != null && widget.auction!.isOngoing;
    final bool isLive = hasActiveAuction || (widget.logo.isAuctionActive && widget.logo.endTime != null && DateTime.now().isBefore(widget.logo.endTime!));

    // Determine badge type and text
    String? badgeText;
    Color? badgeColor;
    if (isWonNft) {
      badgeText = 'WON';
      badgeColor = AppColors.accentOrange;
    } else if (widget.logo.isFrozen) {
      badgeText = 'Copyright Review';
      badgeColor = Colors.lightBlue;
    } else if (isLive && widget.logo.totalBids > 3) {
      badgeText = 'HOT';
      badgeColor = AppColors.danger;
    } else if (isLive) {
      badgeText = 'NEW';
      badgeColor = AppColors.primary;
    }

    // Price calculation
    final displayPrice = hasActiveAuction
        ? (widget.auction!.highestBid > 0 ? widget.auction!.highestBid : widget.auction!.startingPrice)
        : widget.logo.price;

    final bool isAuctionItem = widget.auction != null || 
                               widget.logo.isInAuction || 
                               widget.logo.isAuctionActive || 
                               widget.logo.status == ValidationStatus.auction;
    final DateTime? auctionEndTime = widget.logo.endTime;

    return RepaintBoundary(
      child: MouseRegion(
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
              borderRadius: BorderRadius.circular(AppRadius.lg),
              gradient: isWonNft
                  ? LinearGradient(
                      colors: [
                        AppColors.accentOrange.withValues(alpha: 0.08),
                        AppColors.card,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : AppColors.cardGradient,
              border: Border.all(
                color: isWonNft
                    ? AppColors.accentOrange.withValues(alpha: 0.4)
                    : (_isHovered ? AppColors.primary.withValues(alpha: 0.5) : AppColors.border),
                width: isWonNft ? 1.5 : 1.0,
              ),
              boxShadow: _isHovered ? AppShadows.glowPrimary : AppShadows.soft,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ═══ IMAGE SECTION with badges ═══
                  Expanded(
                    flex: 6,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Image
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
                          child: Container(
                            color: AppColors.surface,
                            child: _buildImage(),
                          ),
                        ),
                        // Top-left: Badge (NEW / HOT / WON / FROZEN)
                        if (badgeText != null)
                          Positioned(
                            top: 8,
                            left: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: badgeColor,
                                borderRadius: BorderRadius.circular(AppRadius.sm),
                              ),
                              child: Text(
                                badgeText,
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 9,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                          ),
                        // ❄️ Icon for Frozen
                        if (widget.logo.isFrozen)
                          Positioned(
                            top: 8,
                            right: 42,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.lightBlue.withValues(alpha: 0.8),
                                shape: BoxShape.circle,
                              ),
                              child: const Text('❄️', style: TextStyle(fontSize: 12)),
                            ),
                          ),

                      ],
                    ),
                  ),

                  // ═══ INFO SECTION ═══
                  Expanded(
                    flex: 4,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Verified Original + Menu ──
                          Row(
                            children: [
                              Icon(Icons.verified, size: 12, color: AppColors.primary),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'Verified Original',
                                  style: AppTextStyles.caption.copyWith(
                                    color: AppColors.textSecondary,
                                    fontSize: 9,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Icon(Icons.more_horiz, size: 16, color: AppColors.textSecondary),
                            ],
                          ),
                          const SizedBox(height: 6),

                          // ── NFT Name ──
                          Text(
                            widget.logo.name,
                            style: AppTextStyles.subtitle1.copyWith(fontSize: 13, fontWeight: FontWeight.w700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),

                          // ── Creator address ──
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'by ${widget.logo.creatorUsername ?? widget.logo.creatorShort}',
                                  style: AppTextStyles.caption.copyWith(
                                    color: AppColors.textSecondary,
                                    fontSize: 10,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (widget.logo.creatorUsername != null)
                                Icon(Icons.verified, size: 10, color: AppColors.primary),
                            ],
                          ),
                          // ── Highest Bidder ──
                          if (hasActiveAuction && (widget.auction!.highestBidderWallet?.isNotEmpty ?? false)) ...[
                            const SizedBox(height: 2),
                            FutureBuilder<UserModel?>(
                              future: _highestBidderFuture,
                              builder: (context, snapshot) {
                                final displayName = UserDisplayUtils.getDisplayName(snapshot.data, widget.auction!.highestBidderWallet!);
                                return Row(
                                  children: [
                                    Icon(Icons.emoji_events, size: 10, color: AppColors.accentOrange),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        'Top Bidder: $displayName',
                                        style: AppTextStyles.caption.copyWith(
                                          color: AppColors.accentOrange,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                );
                              }
                            ),
                          ],

                          // Won NFT extra info
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

                          const Spacer(),

                          // ── Bottom row: Price + Timer ──
                          if (widget.showPrice)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Price
                                Flexible(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Image.asset('assets/images/logo.png', width: 11, height: 11, color: AppColors.primary),
                                      const SizedBox(width: 3),
                                      Flexible(
                                        child: Text(
                                          '${displayPrice.toStringAsFixed(2)} ETH',
                                          style: AppTextStyles.labelMedium.copyWith(
                                            color: AppColors.textPrimary,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 11,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 4),
                                // Timer
                                if (isAuctionItem && auctionEndTime != null)
                                  Flexible(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        Icon(Icons.access_time_rounded, size: 11, color: AppColors.textSecondary),
                                        const SizedBox(width: 3),
                                        Flexible(
                                          child: _AuctionCountdownCompact(endTime: auctionEndTime),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ));
  }

  Widget _buildImage() {
    String imgUrl = widget.logo.imageUrl;
    if (imgUrl.contains('dweb.link/ipfs/')) {
      imgUrl = imgUrl.replaceAll('dweb.link/ipfs/', 'ipfs.io/ipfs/');
    } else if (imgUrl.contains('gateway.pinata.cloud/ipfs/')) {
      imgUrl = imgUrl.replaceAll('gateway.pinata.cloud/ipfs/', 'ipfs.io/ipfs/');
    } else if (imgUrl.contains('ipfs://')) {
      imgUrl = imgUrl.replaceAll('ipfs://', 'https://ipfs.io/ipfs/');
    }

    final Widget imgWidget = imgUrl.isNotEmpty
        ? CachedNetworkImage(
            imageUrl: imgUrl,
            fit: BoxFit.cover,
            memCacheWidth: 400,
            memCacheHeight: 400,
            filterQuality: FilterQuality.low,
            placeholder: (context, url) => Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.surface,
                    AppColors.card,
                    AppColors.surface,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                  begin: const Alignment(-1.0, -0.5),
                  end: const Alignment(1.0, 0.5),
                ),
              ),
            ),
            errorWidget: (context, url, error) => _buildPlaceholder(),
          )
        : _buildPlaceholder();
        
    if (widget.logo.isFrozen) {
      return Stack(
        fit: StackFit.expand,
        children: [
          imgWidget,
          Container(
            color: Colors.lightBlue.withValues(alpha: 0.3),
          ),
        ],
      );
    }
    
    return imgWidget;
  }

  Widget _buildPlaceholder() {
    return Shimmer.fromColors(
      baseColor: AppColors.surface,
      highlightColor: AppColors.border,
      child: const Center(
        child: Icon(
          Icons.image_outlined,
          size: 40,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

// ═══ Compact countdown for the bottom row ═══
class _AuctionCountdownCompact extends StatefulWidget {
  final DateTime endTime;
  const _AuctionCountdownCompact({required this.endTime});

  @override
  State<_AuctionCountdownCompact> createState() => _AuctionCountdownCompactState();
}

class _AuctionCountdownCompactState extends State<_AuctionCountdownCompact> {
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
    if (d.isNegative || d.inSeconds <= 0) return 'Auction Ended';
    final days = d.inDays;
    final hours = d.inHours.remainder(24);
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    
    if (days > 0) return 'Ends in ${days}d ${hours}h';
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m ${seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.endTime.difference(DateTime.now());
    return Text(
      _format(remaining),
      style: AppTextStyles.caption.copyWith(
        color: AppColors.textSecondary,
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

// ─── Keep the original _AuctionCountdown for other uses ───
class AuctionCountdown extends StatefulWidget {
  final DateTime endTime;
  const AuctionCountdown({super.key, required this.endTime});

  @override
  State<AuctionCountdown> createState() => _AuctionCountdownState();
}

class _AuctionCountdownState extends State<AuctionCountdown> {
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
