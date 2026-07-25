import 'dart:async';
import 'dart:convert';
import 'package:shimmer/shimmer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:nft_logo_marketplace/shared/models/auction.dart';
import 'package:nft_logo_marketplace/shared/models/logo_nft.dart';
import 'package:nft_logo_marketplace/shared/models/user_model.dart';
import 'package:nft_logo_marketplace/core/utils/notification_manager.dart';
import 'package:nft_logo_marketplace/shared/models/app_notification.dart';
import 'package:nft_logo_marketplace/core/services/web3_service.dart';
import 'package:nft_logo_marketplace/core/services/firestore_service.dart';
import 'package:nft_logo_marketplace/core/services/auth_service.dart';
import 'package:nft_logo_marketplace/shared/dialogs/bid_dialog.dart';
import 'package:nft_logo_marketplace/shared/dialogs/report_dialog.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/core/theme/app_radius.dart';
import 'package:nft_logo_marketplace/core/theme/app_spacing.dart';
import 'package:nft_logo_marketplace/shared/widgets/primary_button.dart';
import 'package:nft_logo_marketplace/core/theme/app_shadows.dart';
import 'package:nft_logo_marketplace/features/auction/presentation/auction_payment_page.dart';
import 'package:nft_logo_marketplace/shared/widgets/auction_step_indicator.dart';
import 'package:nft_logo_marketplace/core/utils/user_display_utils.dart';
import 'package:nft_logo_marketplace/core/utils/wallet_utils.dart';

class AuctionPage extends StatefulWidget {
  final LogoNFT logo;

  const AuctionPage({super.key, required this.logo});

  @override
  State<AuctionPage> createState() => _AuctionPageState();
}

class _AuctionPageState extends State<AuctionPage> {
  final _web3 = Web3Service.instance;
  Timer? _timer;
  Timer? _notificationResetTimer;
  StreamSubscription? _bidStreamSub;
  StreamSubscription? _auctionStreamSub;
  List<Bid> _firestoreBids = [];
  Auction? _liveAuction;
  DateTime? _lastBidAttempt;
  bool _hasEndedAuction = false; // Idempotent guard for auto-end
  bool _hasTimedOut = false;
  Timer? _timeoutTimer;
  final Map<String, UserModel> _userCache = {};

  Future<UserModel?> _resolveUser(String? wallet, String? userId) async {
    if (wallet == null || wallet.isEmpty) return null;
    final lowerWallet = wallet.toLowerCase();
    if (_userCache.containsKey(lowerWallet)) {
      return _userCache[lowerWallet];
    }
    try {
      if (userId != null && userId.isNotEmpty) {
        final doc = await FirestoreService.instance.db.collection('users').doc(userId).get();
        if (doc.exists) {
          final user = UserModel.fromFirestore(doc.data()!);
          _userCache[lowerWallet] = user;
          return user;
        }
      }
      final q = await FirestoreService.instance.db.collection('users')
          .where('walletAddress', isEqualTo: wallet)
          .limit(1).get();
      if (q.docs.isNotEmpty) {
        final user = UserModel.fromFirestore(q.docs.first.data());
        _userCache[lowerWallet] = user;
        return user;
      }
    } catch (_) {}
    return null;
  }

  // NOTE: Bid-level realtime notifications are now delegated to
  // AuctionNotificationService which is attached in initState.


  @override
  void initState() {
    super.initState();
    _timeoutTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) {
        setState(() => _hasTimedOut = true);
      }
    });
    _web3.addListener(_refresh);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
    _subscribeToBidStream();
    _subscribeToAuctionStream();
  }

  void _retryLoading() {
    setState(() => _hasTimedOut = false);
    
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => _hasTimedOut = true);
    });

    _bidStreamSub?.cancel();
    _auctionStreamSub?.cancel();
    
    _subscribeToBidStream();
    _subscribeToAuctionStream();
  }

  bool _shouldHideOwner(LogoNFT logo, Auction? auction) {
    if (auction == null && !logo.isInAuction) return false;
    
    final bool isAuctionActiveOrPending = logo.isInAuction || 
      (auction != null && (auction.status == AuctionStatus.active || auction.status == AuctionStatus.paymentPending));
      
    if (!isAuctionActiveOrPending) return false;
    
    final bool isCurrentUserOwner = _web3.currentAddress?.toLowerCase() == logo.ownerWallet.toLowerCase();
    return !isCurrentUserOwner;
  }


  void _subscribeToBidStream() {
    _bidStreamSub = FirestoreService.instance
        .getAuctionBidsStream(widget.logo.tokenId)
        .listen(
          (bids) {
            if (mounted) {
              setState(() => _firestoreBids = bids);
              // AuctionNotificationService handles notification logic
            }
          },
          onError: (e) {
            debugPrint('⚠️ Bid stream error, trying fallback: $e');
            _bidStreamSub?.cancel();
            _bidStreamSub = FirestoreService.instance
                .getAuctionBidsStreamFallback(widget.logo.tokenId)
                .listen(
                  (bids) {
                    if (mounted) {
                      setState(() => _firestoreBids = bids);
                    }
                  },
                  onError: (e2) =>
                      debugPrint('⚠️ Fallback bid stream also failed: $e2'),
                );
          },
        );
  }

  void _subscribeToAuctionStream() {
    _auctionStreamSub = FirestoreService.instance
        .getAuctionStream(widget.logo.tokenId)
        .listen(
          (liveAuction) {
            if (mounted && liveAuction != null) {
              setState(() => _liveAuction = liveAuction);
            }
          },
          onError: (e) => debugPrint('⚠️ Auction stream error: $e'),
        );
  }





  @override
  void dispose() {
    _timer?.cancel();
    _timeoutTimer?.cancel();
    _notificationResetTimer?.cancel();
    _bidStreamSub?.cancel();
    _auctionStreamSub?.cancel();
    _web3.removeListener(_refresh);
    super.dispose();
  }


  List<Bid> get _mergedBids {
    final Map<String, Bid> bidMap = {};

    // 1. Prioritaskan Firestore sebagai source of truth utama
    // Untuk setiap wallet, simpan HANYA bid dengan amount TERBESAR
    if (_firestoreBids.isNotEmpty) {
      for (final bid in _firestoreBids) {
        final walletKey = bid.bidderWallet.toLowerCase();
        final existing = bidMap[walletKey];
        if (existing == null || bid.amount > existing.amount) {
          bidMap[walletKey] = bid;
        }
      }
    }

    // 2. Web3 bids sebagai tambahan jika tidak ada di Firestore
    final auction = _web3.allAuctions.cast<Auction?>().firstWhere(
      (a) => a != null && (a.tokenId == widget.logo.tokenId || a.auctionId == widget.logo.tokenId),
      orElse: () => null,
    );

    if (auction != null && auction.bids.isNotEmpty) {
      for (final bid in auction.bids) {
        final wallet = bid.bidderWallet.toLowerCase();
        if (!bidMap.containsKey(wallet) || bidMap[wallet]!.amount < bid.amount) {
          bidMap[wallet] = bid;
        }
      }
    }

    final sorted = bidMap.values.toList()
      ..sort((a, b) {
        final cmp = b.amount.compareTo(a.amount);
        if (cmp != 0) return cmp;
        return a.firstBidTimestamp.compareTo(b.firstBidTimestamp);
      });

    return sorted;
  }

  void _refresh() {
    if (mounted) setState(() {});

    try {
      final logo = widget.logo;

      // Auto-end auction when countdown reaches zero (idempotent)
      if (!_hasEndedAuction &&
          logo.isAuctionActive &&
          !logo.isFrozen &&
          logo.status != ValidationStatus.rejected &&
          logo.endTime != null &&
          DateTime.now().isAfter(logo.endTime!)) {
        if (kDebugMode) { debugPrint("Auction expired → calling endOffChainAuction()"); }
        if (kDebugMode) { debugPrint("Token ID: ${logo.tokenId}"); }
        if (kDebugMode) { debugPrint("Total bids: ${logo.totalBids}"); }
        _hasEndedAuction = true;
        if (kDebugMode) { debugPrint('⏱ Auto-ending auction #${widget.logo.tokenId}'); }
        FirestoreService.instance
            .endOffChainAuction(widget.logo.tokenId)
            .then((_) {
              if (kDebugMode) { debugPrint('✅ Auto-end completed for auction #${widget.logo.tokenId}'); }
            })
            .catchError((e) {
              if (kDebugMode) { debugPrint('❌ Auto-end failed: $e'); }
              // Reset guard so it can retry
              _hasEndedAuction = false;
            });
      }
    } catch (_) {}
  }

  String _formatTimeRemaining(LogoNFT logo) {
    if (logo.status == ValidationStatus.rejected) return '-- : -- : --';

    int remainingSeconds = 0;

    if (logo.isFrozen && logo.frozenRemainingSeconds != null) {
      remainingSeconds = logo.frozenRemainingSeconds!;
    } else if ((logo.auctionStatus == 'PAYMENT_PENDING' || logo.auctionStatus == 'PENDING_PAYMENT' || logo.auctionStatus == 'payment_pending' || logo.auctionStatus == 'pending_payment') && logo.paymentDeadline != null) {
      final now = DateTime.now();
      if (logo.paymentDeadline!.isAfter(now)) {
        remainingSeconds = logo.paymentDeadline!.difference(now).inSeconds;
      }
    } else if (logo.endTime != null) {
      final now = DateTime.now();
      if (logo.endTime!.isAfter(now)) {
        remainingSeconds = logo.endTime!.difference(now).inSeconds;
      }
    } else {
      return '-- : -- : --';
    }

    if (remainingSeconds <= 0 && !logo.isFrozen) return '00 : 00 : 00';

    final hours = (remainingSeconds ~/ 3600).toString().padLeft(2, '0');
    final mins = ((remainingSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final secs = (remainingSeconds % 60).toString().padLeft(2, '0');
    return '$hours : $mins : $secs';
  }

  @override
  Widget build(BuildContext context) {
    final logo = widget.logo;

    final auction = _liveAuction ?? 
      _web3.allAuctions.cast<Auction?>().firstWhere(
        (a) => a!.tokenId == widget.logo.tokenId || a.auctionId == widget.logo.tokenId,
        orElse: () => null,
      ) ??
      (widget.logo.isAuctionActive == true ? Auction(
        auctionId: widget.logo.tokenId,
        tokenId: widget.logo.tokenId,
        sellerId: widget.logo.creatorId,
        sellerWallet: widget.logo.creatorWallet,
        startingPrice: widget.logo.price,
        highestBid: widget.logo.highestBid,
        status: AuctionStatus.active,
        bids: [],
        startTime: widget.logo.startTime ?? widget.logo.createdAt,
        endTime: widget.logo.endTime ?? DateTime.now().add(const Duration(days: 1)),
      ) : null);

    debugPrint('🔥 [AUCTION PAGE DEBUG] TokenID: ${logo.tokenId} | logo.highestBid: ${logo.highestBid} | auction.highestBid: ${auction?.highestBid}');
    debugPrint("Auction NFT: ${logo.tokenId}");
    debugPrint("Status: ${logo.status}");
    debugPrint("Auction Status: ${logo.auctionStatus}");

    if (auction == null) {
      if (_hasTimedOut) {
        String displayImageUrl = logo.imageUrl;
        if (displayImageUrl.contains('dweb.link/ipfs/')) {
          displayImageUrl = displayImageUrl.replaceAll('dweb.link/ipfs/', 'ipfs.io/ipfs/');
        } else if (displayImageUrl.contains('ipfs://')) {
          displayImageUrl = displayImageUrl.replaceAll('ipfs://', 'https://ipfs.io/ipfs/');
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            title: const Text('Live Auction', style: AppTextStyles.h3),
            centerTitle: true,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: displayImageUrl.isNotEmpty 
                      ? Image.network(
                          displayImageUrl, 
                          width: 120, 
                          height: 120, 
                          fit: BoxFit.cover,
                          errorBuilder: (ctx, err, stack) => const Icon(Icons.image, size: 120, color: AppColors.textSecondary),
                        )
                      : const Icon(Icons.image, size: 120, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                Text(logo.name, style: AppTextStyles.h3),
                const SizedBox(height: 8),
                Text(
                  'Failed to load auction. Please try again.',
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.danger),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                PrimaryButton(
                  text: 'Retry',
                  onPressed: _retryLoading,
                  icon: Icons.refresh,
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        );
      }

      // Show loading before timeout
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('Live Auction', style: AppTextStyles.h3),
          centerTitle: true,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(height: 16),
              Text(
                'Loading Auction #${widget.logo.tokenId}...',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    final currentWallet = _web3.currentAddress;
    final effectiveOwner = (logo.ownerWallet.isNotEmpty) ? logo.ownerWallet : logo.creatorWallet;
    final isOwner =
        currentWallet != null &&
        currentWallet.toLowerCase().trim() ==
            effectiveOwner.toLowerCase().trim();

    String displayImageUrl = logo.imageUrl;
    if (displayImageUrl.contains('dweb.link/ipfs/')) {
      displayImageUrl = displayImageUrl.replaceAll(
        'dweb.link/ipfs/',
        'ipfs.io/ipfs/',
      );
    } else if (displayImageUrl.contains('ipfs://')) {
      displayImageUrl = displayImageUrl.replaceAll(
        'ipfs://',
        'https://ipfs.io/ipfs/',
      );
    }

    final bool isLive =
        logo.isAuctionActive &&
        logo.endTime != null &&
        DateTime.now().isBefore(logo.endTime!);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Live Auction', style: AppTextStyles.h3),
        centerTitle: true,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth > 900;

          if (isDesktop) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: RefreshIndicator(
                  onRefresh: () async { _retryLoading(); },
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sectionPadding,
                    vertical: AppSpacing.lg,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left side - Image & Details
                      Expanded(
                        flex: 5,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildImageHero(displayImageUrl),
                            const SizedBox(height: AppSpacing.xxl),
                            _buildAuctionInfo(logo, isLive, isOwner, auction),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sectionPadding),
                      // Right side - Leaderboard & Actions
                      Expanded(
                        flex: 4,
                        child: _buildLeaderboardAndActions(
                          logo,
                          isLive,
                          isOwner,
                          auction,
                        ),
                      ),
                    ],
                  ),
                ),
    ),
              ),
            );
          } else {
            return RefreshIndicator(
              onRefresh: () async { _retryLoading(); },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(
                left: AppSpacing.screenPadding,
                right: AppSpacing.screenPadding,
                top: AppSpacing.screenPadding,
                bottom: 40,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildImageHero(displayImageUrl),
                  const SizedBox(height: AppSpacing.xxl),
                  _buildAuctionInfo(logo, isLive, isOwner, auction),
                  const SizedBox(height: AppSpacing.xxl),
                  _buildLeaderboardAndActions(logo, isLive, isOwner, auction),
                ],
              ),
            ));
          }
        },
      ),
    );
  }

  Widget _buildImageHero(String displayImageUrl) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxHeight: 500),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.xxl),
          border: Border.all(color: AppColors.border, width: 2),
          boxShadow: AppShadows.glowPrimary,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.xxl),
          child: displayImageUrl.isNotEmpty
              ? (displayImageUrl.startsWith('data:image')
                    ? Image.memory(
                        base64Decode(displayImageUrl.split(',').last),
                        fit: BoxFit.contain,
                      )
                    : Image.network(
                        displayImageUrl,
                        fit: BoxFit.contain,
                        errorBuilder: (ctx, err, stack) => _placeholder(),
                      ))
              : _placeholder(),
        ),
      ),
    );
  }

  Widget _buildAuctionInfo(logo, bool isLive, bool isOwner, auction) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // â”€â”€â”€ Status Banners â”€â”€â”€
        if (auction.status == AuctionStatus.cancelled)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.lg),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: AppColors.danger.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.cancel, color: AppColors.danger, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Auction Cancelled',
                        style: AppTextStyles.labelLarge.copyWith(
                          color: AppColors.danger,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'This NFT violated marketplace policy. All bids have been automatically invalidated.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.danger,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Bids on this marketplace are processed off-chain. No cryptocurrency was deducted before final payment.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.danger.withValues(alpha: 0.8),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // â”€â”€â”€ Frozen Banner (LARGE) â”€â”€â”€
        if (logo.isFrozen && auction.status != AuctionStatus.cancelled)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.lg),
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.frozenBlue.withValues(alpha: 0.2),
                  AppColors.frozenBlue.withValues(alpha: 0.08),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppRadius.xl),
              border: Border.all(
                color: AppColors.frozenBlue.withValues(alpha: 0.5),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.frozenBlue.withValues(alpha: 0.15),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.frozenBlue.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.frozenBlue.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Icon(
                    Icons.ac_unit,
                    color: AppColors.frozenBlue,
                    size: 36,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'AUCTION FROZEN',
                  style: AppTextStyles.h2.copyWith(
                    color: AppColors.frozenBlue,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Auction Frozen by Marketplace Admin',
                  style: AppTextStyles.labelLarge.copyWith(
                    color: AppColors.frozenBlue,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.frozenBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(
                      color: AppColors.frozenBlue.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'This auction has been temporarily frozen pending investigation. '
                        'All bidding activity is suspended and existing bids have been invalidated.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.frozenBlue,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Bids on this marketplace are processed off-chain. '
                        'No cryptocurrency was deducted during the bidding process.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.frozenBlue.withValues(alpha: 0.8),
                          fontStyle: FontStyle.italic,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // â”€â”€â”€ Status Banners â”€â”€â”€
        if (auction.status == AuctionStatus.ended &&
            (logo.highestBidderWallet == null ||
                logo.highestBidderWallet!.isEmpty))
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.lg),
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(
              color: AppColors.textSecondary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: AppColors.textSecondary.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.timer_off_outlined,
                  color: AppColors.textSecondary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ENDED',
                        style: AppTextStyles.labelLarge.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'No bids were placed during this auction.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        if (auction.status == AuctionStatus.paymentPending)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.lg),
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(
              gradient:
                  _web3.currentAddress?.toLowerCase() ==
                      logo.highestBidderWallet?.toLowerCase()
                  ? const LinearGradient(
                      colors: [Color(0xFFFFFBE6), Color(0xFFFFF1B8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color:
                  _web3.currentAddress?.toLowerCase() ==
                      logo.highestBidderWallet?.toLowerCase()
                  ? null
                  : AppColors.accentOrange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color:
                    _web3.currentAddress?.toLowerCase() ==
                        logo.highestBidderWallet?.toLowerCase()
                    ? Colors.amber
                    : AppColors.accentOrange.withValues(alpha: 0.3),
                width:
                    _web3.currentAddress?.toLowerCase() ==
                        logo.highestBidderWallet?.toLowerCase()
                    ? 2
                    : 1,
              ),
              boxShadow:
                  _web3.currentAddress?.toLowerCase() ==
                      logo.highestBidderWallet?.toLowerCase()
                  ? [
                      BoxShadow(
                        color: Colors.amber.withValues(alpha: 0.2),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                if (_web3.currentAddress?.toLowerCase() ==
                    logo.highestBidderWallet?.toLowerCase())
                  const Text('🎉', style: TextStyle(fontSize: 32))
                else
                  const Icon(
                    Icons.payment,
                    color: AppColors.accentOrange,
                    size: 24,
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _web3.currentAddress?.toLowerCase() ==
                                logo.highestBidderWallet?.toLowerCase()
                            ? 'You Won the Auction!'
                            : 'Payment Pending',
                        style: AppTextStyles.labelLarge.copyWith(
                          color:
                              _web3.currentAddress?.toLowerCase() ==
                                  logo.highestBidderWallet?.toLowerCase()
                              ? Colors.orange[800]
                              : AppColors.accentOrange,
                          fontSize:
                              _web3.currentAddress?.toLowerCase() ==
                                  logo.highestBidderWallet?.toLowerCase()
                              ? 18
                              : null,
                          fontWeight:
                              _web3.currentAddress?.toLowerCase() ==
                                  logo.highestBidderWallet?.toLowerCase()
                              ? FontWeight.w900
                              : FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _web3.currentAddress?.toLowerCase() ==
                                logo.highestBidderWallet?.toLowerCase()
                            ? 'Complete payment before deadline to claim ownership. Expected: ${auction.highestBid.toStringAsFixed(4)} ETH'
                            : 'Waiting for winner payment settlement.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color:
                              _web3.currentAddress?.toLowerCase() ==
                                  logo.highestBidderWallet?.toLowerCase()
                              ? Colors.orange[900]
                              : AppColors.accentOrange,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        if (auction.status == AuctionStatus.paymentExpired)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.lg),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: AppColors.danger.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  color: AppColors.danger,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Payment Expired',
                        style: AppTextStyles.labelLarge.copyWith(
                          color: AppColors.danger,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isOwner ? 'Winner failed to pay. You may request a re-auction.' : 'The winner failed to complete the payment before the deadline.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.danger,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        if (auction.status == AuctionStatus.claimed)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.lg),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: AppColors.success.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: AppColors.success,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Auction Claimed',
                        style: AppTextStyles.labelLarge.copyWith(
                          color: AppColors.success,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'The winner has successfully claimed this NFT.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        if (auction.status == AuctionStatus.failedPayment)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.lg),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: AppColors.danger.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  color: AppColors.danger,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Payment Failed',
                        style: AppTextStyles.labelLarge.copyWith(
                          color: AppColors.danger,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'The winner failed to complete the payment.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.danger,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // â”€â”€â”€ View Only Mode Banner â”€â”€â”€
        if (!_web3.isConnected)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.lg),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.accentOrange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: AppColors.accentOrange.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.visibility_outlined,
                  color: AppColors.accentOrange,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'View Only Mode',
                        style: AppTextStyles.labelLarge.copyWith(
                          color: AppColors.accentOrange,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Connect your wallet to place bids.',
                        style: AppTextStyles.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // â”€â”€â”€ Info â”€â”€â”€
        Text(
          logo.name,
          style: AppTextStyles.display.copyWith(fontSize: 28),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text('Token #${logo.tokenId}', style: AppTextStyles.subtitle2),
        const SizedBox(height: AppSpacing.lg),

        if (logo.description.isNotEmpty) ...[
          Text('Description', style: AppTextStyles.h3),
          const SizedBox(height: AppSpacing.sm),
          Text(
            logo.description,
            style: AppTextStyles.bodyLarge.copyWith(
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],

        // Details Card
        FutureBuilder<UserModel?>(
          future: logo.creatorId.isEmpty
              ? AuthService.instance.getUserData(
                  logo.creatorWallet.toLowerCase(),
                )
              : AuthService.instance.getUserData(logo.creatorId),
          builder: (context, snapshot) {
            final creatorUser = snapshot.data;
            return Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.xl),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: AppColors.primary.withValues(
                          alpha: 0.2,
                        ),
                        backgroundImage:
                            creatorUser?.profileImage != null &&
                                creatorUser!.profileImage!.startsWith(
                                  'data:image',
                                )
                            ? MemoryImage(
                                base64Decode(
                                  creatorUser.profileImage!.split(',')[1],
                                ),
                              )
                            : null,
                        child:
                            creatorUser?.profileImage == null ||
                                !creatorUser!.profileImage!.startsWith(
                                  'data:image',
                                )
                            ? const Icon(
                                Icons.person,
                                color: AppColors.primary,
                                size: 18,
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Creator', style: AppTextStyles.caption),
                            Text(
                              creatorUser?.displayName ??
                                  logo.creatorUsername ??
                                  'Verified Creator',
                              style: AppTextStyles.labelMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (creatorUser?.country?.isNotEmpty == true)
                              Row(
                                children: [
                                  const Icon(
                                    Icons.public,
                                    size: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      creatorUser?.country ?? '',
                                      style: AppTextStyles.caption,
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
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Divider(color: AppColors.border, height: 1),
                  ),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: AppColors.accentOrange.withValues(
                          alpha: 0.2,
                        ),
                        child: const Icon(
                          Icons.person_outline,
                          color: AppColors.accentOrange,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!_shouldHideOwner(logo, auction)) Text('Current Owner', style: AppTextStyles.caption),
                            Text(
                              _shouldHideOwner(logo, auction) ? 'Owner Hidden for Privacy' : _shortenAddress(logo.ownerWallet),
                              style: _shouldHideOwner(logo, auction) ? AppTextStyles.labelMedium.copyWith(fontStyle: FontStyle.italic, color: AppColors.textSecondary) : AppTextStyles.labelMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Divider(color: AppColors.border, height: 1),
                  ),
                  _buildInfoRow(
                    Icons.category_outlined,
                    'Category',
                    logo.category,
                  ),
                  const Divider(color: AppColors.border, height: 1),
                  _buildInfoRow(
                    Icons.timer_outlined,
                    'Auction Duration',
                    _formatAuctionDuration(logo.auctionDuration ?? 86400),
                  ),
                  const Divider(color: AppColors.border, height: 1),
                  _buildInfoRow(Icons.language, 'Network', 'Sepolia Testnet'),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildLeaderboardAndActions(
    logo,
    bool isLive,
    bool isOwner,
    auction,
  ) {
    Color statusColor;
    if (auction.status == AuctionStatus.cancelled) {
      statusColor = AppColors.danger;
    } else if (auction.status == AuctionStatus.frozen || logo.isFrozen) {
      statusColor = AppColors.frozenBlue;
    } else if (auction.status == AuctionStatus.paymentPending) {
      statusColor = AppColors.accentOrange;
    } else if (auction.status == AuctionStatus.claimed) {
      statusColor = AppColors.success;
    } else if (auction.status == AuctionStatus.failedPayment) {
      statusColor = AppColors.danger;
    } else if (isLive) {
      statusColor = const Color(0xFF9B51E0); // Purple glow for LIVE
    } else {
      statusColor = AppColors.textSecondary;
    }

    final bool isFrozen =
        auction.status == AuctionStatus.frozen || logo.isFrozen;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // â”€â”€â”€ Creator Mode Banner â”€â”€â”€
        if (isOwner)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.lg),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.storefront,
                  color: AppColors.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'OWNER VIEW',
                            style: AppTextStyles.labelLarge.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: Text(
                              'OWNER',
                              style: AppTextStyles.labelSmall.copyWith(
                                color: AppColors.background,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'You are monitoring this live auction as the owner.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // â”€â”€â”€ Auction Stats Card â”€â”€â”€
        Container(
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                statusColor.withValues(alpha: 0.15),
                statusColor.withValues(alpha: 0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(AppRadius.xxl),
            border: Border.all(
              color: statusColor.withValues(alpha: 0.4),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: statusColor.withValues(alpha: 0.1),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          auction.highestBid > 0
                              ? 'Highest Bid'
                              : 'Starting Price',
                          style: AppTextStyles.labelMedium.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Image.asset(
                                'assets/images/logo.png',
                                width: 20,
                                height: 20,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${(auction.highestBid > 0 ? auction.highestBid : auction.startingPrice).toStringAsFixed(4)} ETH',
                                style: AppTextStyles.display.copyWith(
                                  fontSize: 24,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isLive
                                ? statusColor.withValues(alpha: 0.2)
                                : AppColors.surface,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            border: Border.all(
                              color: isLive ? statusColor : AppColors.border,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isFrozen
                                    ? Icons.ac_unit
                                    : (isLive
                                          ? Icons.timer_outlined
                                          : Icons.timer_off_outlined),
                                color: isLive || isFrozen
                                    ? statusColor
                                    : AppColors.textSecondary,
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isFrozen
                                    ? 'Frozen'
                                    : (isLive ? 'Ends in' : 'Ended'),
                                style: AppTextStyles.labelMedium.copyWith(
                                  color: isLive || isFrozen
                                      ? statusColor
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Builder(
                            builder: (context) {
                              bool isUrgent = false;
                              if (isLive && logo.endTime != null) {
                                final diff = logo.endTime!.difference(
                                  DateTime.now(),
                                );
                                if (diff.inSeconds <= 10 && diff.inSeconds > 0) {
                                  isUrgent = true;
                                }
                              } else if (auction.status == AuctionStatus.paymentPending && logo.paymentDeadline != null) {
                                final diff = logo.paymentDeadline!.difference(
                                  DateTime.now(),
                                );
                                if (diff.inHours < 1 && diff.inSeconds > 0) {
                                  isUrgent = true;
                                }
                              }

                              return AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                                style: AppTextStyles.h3.copyWith(
                                  color: isFrozen
                                      ? AppColors.textSecondary
                                      : isUrgent &&
                                            DateTime.now().second % 2 == 0
                                      ? AppColors.danger
                                      : isUrgent
                                      ? AppColors.accentOrange
                                      : isLive
                                      ? AppColors.textPrimary
                                      : AppColors.textSecondary,
                                  fontFamily: 'monospace',
                                  fontWeight: isUrgent
                                      ? FontWeight.w900
                                      : FontWeight.bold,
                                  fontSize: isUrgent
                                      ? 26
                                      : 24, // subtle pulse effect
                                  letterSpacing: 2,
                                ),
                                child: Text(_formatTimeRemaining(logo)),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (logo.highestBidderWallet != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Divider(
                    color: AppColors.accentOrange.withValues(alpha: 0.3),
                    height: 1,
                  ),
                ),
                Row(
                  children: [
                    const Icon(
                      Icons.emoji_events,
                      color: Colors.amber,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Top Bidder: ',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Flexible(
                      child: FutureBuilder<UserModel?>(
                        future: _resolveUser(logo.highestBidderWallet, null),
                        builder: (context, snap) {
                          final displayName = UserDisplayUtils.getDisplayName(snap.data, logo.highestBidderWallet!);
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              UserDisplayUtils.buildAvatar(snap.data, logo.highestBidderWallet!, radius: 12),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  displayName,
                                  style: AppTextStyles.labelLarge,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Divider(
                  color: AppColors.accentOrange.withValues(alpha: 0.3),
                  height: 1,
                ),
              ),
              Row(
                children: [
                  const Icon(
                    Icons.how_to_vote_outlined,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Total Bids: ',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    '${_mergedBids.length}',
                    style: AppTextStyles.labelLarge,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),

        const AuctionStepIndicator(currentStep: 0),
        const SizedBox(height: AppSpacing.lg),

        // â”€â”€â”€ Auction Pricing Info â”€â”€â”€
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Starting Price',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    '${logo.price.toStringAsFixed(2)} ETH',
                    style: AppTextStyles.labelLarge,
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Divider(color: AppColors.border),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Highest Bid',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    '${auction.highestBid.toStringAsFixed(2)} ETH',
                    style: AppTextStyles.h3.copyWith(
                      color: AppColors.accentOrange,
                    ),
                  ),
                ],
              ),
              if (!isOwner) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Divider(color: AppColors.border),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Minimum Next Bid',
                      style: AppTextStyles.labelMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      '${(auction.highestBid > 0 ? auction.highestBid + Auction.getMinimumIncrement(auction.highestBid) : auction.startingPrice).toStringAsFixed(2)} ETH',
                      style: AppTextStyles.labelLarge.copyWith(
                        color: AppColors.frozenBlue,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),

        // â”€â”€â”€ Actions â”€â”€â”€
        // â”€â”€â”€ Ended Auction Status Messages â”€â”€â”€
        // No bids message
        if (!isLive &&
            !logo.isFrozen &&
            auction.status != AuctionStatus.cancelled &&
            auction.status != AuctionStatus.claimed &&
            (auction.status == AuctionStatus.ended || auction.status == AuctionStatus.endedNoBids || logo.auctionStatus == 'ENDED_NO_BID' || logo.auctionStatus == 'ended_no_bids') &&
            auction.totalBids == 0 &&
            (logo.highestBidderWallet == null || logo.highestBidderWallet!.isEmpty))
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.lg),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.textSecondary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.textSecondary.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: AppColors.textSecondary, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Auction Ended â€” No Bids', style: AppTextStyles.labelLarge.copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      Text('No bids were placed during this auction.', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // â•â•â• PAYMENT PENDING â€” Winner View with Countdown â•â•â•
        if (!isLive &&
            auction.status == AuctionStatus.paymentPending &&
            _web3.currentAddress?.toLowerCase() == logo.highestBidderWallet?.toLowerCase())
          Builder(
            builder: (_) {
              final deadline = logo.paymentDeadline;
              final now = DateTime.now().millisecondsSinceEpoch;
              final remaining = deadline != null ? deadline.millisecondsSinceEpoch - now : 0;
              final hours = (remaining / (1000 * 60 * 60)).clamp(0, 999).toInt();
              final minutes = ((remaining % (1000 * 60 * 60)) / (1000 * 60)).clamp(0, 59).toInt();
              final seconds = ((remaining % (1000 * 60)) / 1000).clamp(0, 59).toInt();

              // Color based on urgency
              Color urgencyColor;
              if (remaining <= 0) {
                urgencyColor = AppColors.danger;
              } else if (hours < 1) {
                urgencyColor = AppColors.danger;
              } else if (hours < 6) {
                urgencyColor = AppColors.accentOrange;
              } else {
                urgencyColor = AppColors.success;
              }

              final isPulse = hours < 1 && DateTime.now().second % 2 == 0;

              return AnimatedContainer(
                duration: const Duration(seconds: 1),
                curve: Curves.easeInOut,
                margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      urgencyColor.withValues(alpha: 0.12),
                      urgencyColor.withValues(alpha: 0.04),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  border: Border.all(color: urgencyColor.withValues(alpha: 0.4), width: 1.5),
                  boxShadow: (hours < 1 && remaining > 0)
                      ? [
                          BoxShadow(
                            color: AppColors.danger.withValues(alpha: isPulse ? 0.3 : 0.05),
                            blurRadius: isPulse ? 20 : 5,
                            spreadRadius: isPulse ? 5 : 0,
                          )
                        ]
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.emoji_events, color: urgencyColor, size: 24),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'You Won! Complete Payment',
                            style: AppTextStyles.labelLarge.copyWith(color: urgencyColor, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Complete payment before the deadline to claim ownership of this NFT.',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    // Countdown Timer
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: urgencyColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border: Border.all(color: urgencyColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.timer, color: urgencyColor, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            remaining <= 0
                                ? 'DEADLINE EXPIRED'
                                : '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
                            style: AppTextStyles.h3.copyWith(
                              color: urgencyColor,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Amount:', style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary)),
                        Text(
                          '${auction.highestBid.toStringAsFixed(4)} ETH',
                          style: AppTextStyles.labelLarge.copyWith(color: AppColors.accentOrange, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),

        // â•â•â• PAYMENT PENDING â€” Non-Winner / Public View with Countdown â•â•â•
        if (!isLive &&
            auction.status == AuctionStatus.paymentPending &&
            _web3.currentAddress?.toLowerCase() != logo.highestBidderWallet?.toLowerCase())
          Builder(
            builder: (_) {
              final deadline = logo.paymentDeadline;
              final now = DateTime.now().millisecondsSinceEpoch;
              final remaining = deadline != null ? deadline.millisecondsSinceEpoch - now : 0;
              final hours = (remaining / (1000 * 60 * 60)).clamp(0, 999).toInt();
              final minutes = ((remaining % (1000 * 60 * 60)) / (1000 * 60)).clamp(0, 59).toInt();

              return Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.accentOrange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.accentOrange.withValues(alpha: 0.2)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.hourglass_top, color: AppColors.accentOrange, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Awaiting Winner Payment', style: AppTextStyles.labelLarge.copyWith(color: AppColors.accentOrange)),
                              const SizedBox(height: 4),
                              Text(
                                remaining > 0
                                    ? 'Winner has ${hours}h ${minutes}m remaining to complete payment.'
                                    : 'Payment deadline has expired.',
                                style: AppTextStyles.bodySmall.copyWith(color: AppColors.accentOrange),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),

        // â•â•â• PAYMENT EXPIRED â€” Premium Red Banner â•â•â•
        if (auction.status == AuctionStatus.paymentExpired)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.lg),
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.danger.withValues(alpha: 0.15),
                  AppColors.danger.withValues(alpha: 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppRadius.xl),
              border: Border.all(color: AppColors.danger.withValues(alpha: 0.4), width: 1.5),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.timer_off, color: AppColors.danger, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Payment Expired',
                        style: AppTextStyles.labelLarge.copyWith(
                          color: AppColors.danger,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'The winner failed to complete payment within the 24-hour deadline. This NFT can be re-auctioned.',
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.danger),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // â”€â”€â”€ Re-Auction Button â”€â”€â”€
        if (isOwner &&
            !logo.isFrozen &&
            logo.status != ValidationStatus.rejected &&
            (auction.status == AuctionStatus.ended ||
             auction.status == AuctionStatus.endedNoBids ||
             logo.auctionStatus == 'ENDED_NO_BIDS' ||
             logo.auctionStatus == 'ended_no_bids' ||
             auction.status == AuctionStatus.failedPayment ||
             auction.status == AuctionStatus.paymentExpired) &&
            (logo.highestBidderWallet == null ||
                logo.highestBidderWallet!.isEmpty ||
                auction.status == AuctionStatus.failedPayment ||
                auction.status == AuctionStatus.paymentExpired))
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: PrimaryButton(
              text: 'Re-Auction This NFT',
              icon: Icons.refresh,
              backgroundColor: AppColors.primary,
              onPressed: () async {
                try {
                  await FirestoreService.instance.requestReAuction(
                    auction.tokenId,
                  );
                  if (mounted) {
                    NotificationManager.show(
                      context: context,
                      title: 'Request Submitted',
                      message: 'Re-auction request submitted. Awaiting admin approval.',
                      type: NotificationType.success,
                    );
                    Navigator.pop(context);
                  }
                } catch (e) {
                  if (mounted) {
                    NotificationManager.show(
                      context: context,
                      title: 'Error',
                      message: e.toString().replaceFirst("Exception: ", ""),
                      type: NotificationType.error,
                    );
                  }
                }
              },
            ),
          ),

        if (!isOwner &&
            (auction.status == AuctionStatus.active ||
                auction.status == AuctionStatus.frozen))
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PrimaryButton(
                  text: 'Bid Now',
                  icon: Icons.rocket_launch,
                  backgroundColor: AppColors.accentOrange,
                  onPressed: () {
                    if (logo.isFrozen || auction.status == AuctionStatus.frozen) {
                      NotificationManager.show(
                        context: context,
                        title: 'Action Denied',
                        message: 'Auction is frozen by Admin.',
                        type: NotificationType.error,
                      );
                      return;
                    }
                    if (!_web3.isConnected) {
                      WalletUtils.showConnectDialog(
                        context,
                        _web3,
                        title: 'Connect Wallet Required',
                        message: 'Please connect your wallet to place a bid.',
                      ).then((connected) {
                         if (connected && mounted) setState(() {});
                      });
                      return;
                    }
                    if (isOwner) {
                      NotificationManager.show(
                        context: context,
                        title: 'Invalid Bid',
                        message: 'Owners cannot bid on their own NFT',
                        type: NotificationType.warning,
                      );
                      return;
                    }
                    if (!isLive) {
                      NotificationManager.show(
                        context: context,
                        title: 'Auction Not Live',
                        message: 'Auction is not live right now',
                        type: NotificationType.warning,
                      );
                      return;
                    }
                    _showBidDialog(auction);
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                // OFF-CHAIN BADGE
                Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(color: AppColors.success.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.success,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'OFF-CHAIN BID',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: AppColors.success,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '· No wallet charge',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: AppColors.success.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Placing a bid does not charge your wallet.\nPayment is only required if you win the auction.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

        if (auction.status == AuctionStatus.paymentPending &&
            auction.status != AuctionStatus.cancelled &&
            (!_web3.isConnected || _web3.currentAddress?.toLowerCase() == logo.highestBidderWallet?.toLowerCase()))
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: PrimaryButton(
              text: 'Complete Payment',
              icon: Icons.payment,
              backgroundColor: AppColors.accentOrange,
              onPressed: () {
                if (!_web3.isConnected) {
                  WalletUtils.showConnectDialog(
                    context,
                    _web3,
                    title: 'Connect Wallet Required',
                    message: 'Please connect your wallet to complete payment.',
                  ).then((connected) {
                     if (connected && mounted) setState(() {});
                  });
                  return;
                }
                if (logo.isPaymentProcessing) {
                  NotificationManager.show(
                    context: context,
                    title: 'Payment in Progress',
                    message: 'A payment is currently being processed for this NFT.',
                    type: NotificationType.warning,
                  );
                  return;
                }
                Navigator.push(context, MaterialPageRoute(builder: (_) => AuctionPaymentPage(tokenId: widget.logo.tokenId)));
              },
            ),
          ),

        if (isOwner) ...[
          if (isLive && _mergedBids.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: PrimaryButton(
                text: 'Cancel Auction',
                icon: Icons.cancel_outlined,
                backgroundColor: AppColors.danger,
                onPressed: () async {
                  try {
                    await FirestoreService.instance.endOffChainAuction(
                      widget.logo.tokenId,
                    );
                    if (!mounted) return;
                    Navigator.pop(context);
                  } catch (e) {
                    if (!mounted) return;
                    NotificationManager.show(
                      context: context,
                      title: 'Error',
                      message: e.toString().replaceFirst("Exception: ", ""),
                      type: NotificationType.error,
                    );
                  }
                },
              ),
            ),

        ],

        // â”€â”€â”€ TOP 10 LIVE LEADERBOARD â”€â”€â”€
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
            boxShadow: [
              BoxShadow(
                color: Colors.amber.withValues(alpha: 0.1),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.emoji_events, color: Colors.amber, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'TOP 10 LIVE LEADERBOARD',
                  style: AppTextStyles.labelLarge.copyWith(
                    color: Colors.amber,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              // Pulsing live dot
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isLive ? AppColors.success : AppColors.textSecondary,
                  shape: BoxShape.circle,
                  boxShadow: isLive
                      ? [
                          BoxShadow(
                            color: AppColors.success.withValues(alpha: 0.6),
                            blurRadius: 6,
                          ),
                        ]
                      : null,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                isLive ? 'LIVE' : 'ENDED',
                style: AppTextStyles.labelMedium.copyWith(
                  color: isLive ? AppColors.success : AppColors.textSecondary,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // Always show 10 slots
        ...List.generate(10, (index) {
          final bid = index < _mergedBids.length ? _mergedBids[index] : null;
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(
                opacity: animation,
                child: child,
              );
            },
            child: _buildLeaderboardItem(
              bid,
              index + 1,
              key: ValueKey(bid?.bidderWallet ?? 'empty_$index'),
            ),
          );
        }),

        // Show user's rank if outside top 10
        if (_mergedBids.length > 10 && _web3.currentAddress != null) ...[
          Builder(
            builder: (_) {
              final userIndex = _mergedBids.indexWhere(
                (b) =>
                    b.bidderWallet.toLowerCase() ==
                    _web3.currentAddress!.toLowerCase(),
              );
              if (userIndex >= 10) {
                return Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'â€¢ â€¢ â€¢',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    _buildLeaderboardItem(
                      _mergedBids[userIndex],
                      userIndex + 1,
                      key: ValueKey(_mergedBids[userIndex].bidderWallet),
                    ),
                  ],
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],

        const SizedBox(height: AppSpacing.xxl),

        Center(
          child: TextButton.icon(
            onPressed: () => ReportDialog.show(context, widget.logo.tokenId),
            icon: const Icon(
              Icons.flag_outlined,
              size: 16,
              color: AppColors.textSecondary,
            ),
            label: Text(
              'Report Artwork',
              style: AppTextStyles.labelMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLeaderboardItem(Bid? bid, int rank, {Key? key}) {
    Color rankColor;
    IconData? rankIcon;

    switch (rank) {
      case 1:
        rankColor = const Color(0xFFFFD700); // Gold
        rankIcon = Icons.workspace_premium;
        break;
      case 2:
        rankColor = const Color(0xFFC0C0C0); // Silver
        rankIcon = Icons.workspace_premium;
        break;
      case 3:
        rankColor = const Color(0xFFCD7F32); // Bronze
        rankIcon = Icons.workspace_premium;
        break;
      default:
        rankColor = AppColors.textSecondary;
        rankIcon = null;
    }

    if (bid == null) {
      // Empty slot styling
      return Container(
        key: key,
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: AppColors.border.withValues(alpha: 0.5),
            width: 1,
            style: BorderStyle.solid,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.card.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '#$rank',
                  style: AppTextStyles.labelLarge.copyWith(
                    color: AppColors.textSecondary.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                '\u2014',
                style: AppTextStyles.labelLarge.copyWith(
                  color: AppColors.textSecondary.withValues(alpha: 0.3),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final lowerWallet = bid.bidderWallet.toLowerCase();
    
    if (_userCache.containsKey(lowerWallet)) {
      final user = _userCache[lowerWallet];
      return _buildLeaderboardItemContent(user, bid, rank, rankColor, rankIcon, key: key);
    }

    return FutureBuilder<UserModel?>(
      key: key,
      future: _resolveUser(bid.bidderWallet, bid.bidderId),
      builder: (context, snapshot) {
        final user = snapshot.data;
        return _buildLeaderboardItemContent(user, bid, rank, rankColor, rankIcon);
      }
    );
  }

  Widget _buildLeaderboardItemContent(UserModel? user, Bid bid, int rank, Color rankColor, IconData? rankIcon, {Key? key}) {
    final displayName = UserDisplayUtils.getDisplayName(user, bid.bidderWallet);
    final country = user?.country ?? 'Unknown';

    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: rank <= 3 ? rankColor.withValues(alpha: 0.3) : AppColors.border,
          width: 1,
        ),
        boxShadow: rank <= 3
            ? [
                BoxShadow(
                  color: rankColor.withValues(alpha: 0.15),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          // Rank Badge
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: rank <= 3
                  ? rankColor.withValues(alpha: 0.1)
                  : AppColors.card,
              shape: BoxShape.circle,
              border: Border.all(
                color: rank <= 3 ? rankColor : Colors.transparent,
              ),
            ),
            child: Center(
              child: rankIcon != null
                  ? Icon(rankIcon, color: rankColor, size: 20)
                  : Text(
                      '#$rank',
                      style: AppTextStyles.labelLarge.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 16),
          
          // Avatar
          UserDisplayUtils.buildAvatar(user, bid.bidderWallet, radius: 20, isFirst: rank == 1),
          const SizedBox(width: 12),

          // Bidder Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: AppTextStyles.labelLarge.copyWith(
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  country,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (rank == 1) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Current Leader',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          // Amount
          Flexible(
            flex: 0,
            child: Text(
              '${bid.amount.toStringAsFixed(4)} ETH',
              style: AppTextStyles.labelLarge.copyWith(
                color: rank == 1 ? rankColor : AppColors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _showBidDialog(Auction auction) {
    if (!_web3.isConnected) {
      NotificationManager.show(
        context: context,
        title: 'Wallet Required',
        message: 'Please connect wallet',
        type: NotificationType.error,
      );
      return;
    }

    if (_lastBidAttempt != null &&
        DateTime.now().difference(_lastBidAttempt!).inSeconds < 3) {
      NotificationManager.show(
        context: context,
        title: 'Rate Limit',
        message: 'Please wait 3 seconds before trying again.',
        type: NotificationType.warning,
      );
      return;
    }
    _lastBidAttempt = DateTime.now();

    final currentWallet = _web3.currentAddress;
    final logo = widget.logo;
    if (currentWallet != null &&
        currentWallet.toLowerCase().trim() ==
            logo.creatorWallet.toLowerCase().trim()) {
      NotificationManager.show(
        context: context,
        title: 'Invalid Bid',
        message: 'Creators cannot bid on their own NFT',
        type: NotificationType.warning,
      );
      return;
    }

    showDialog(
      context: context,
      builder: (_) => BidDialog(
        currentBid: logo.highestBid,
        startingPrice: logo.price,
        userBalance: _web3.balance,
        onBid: (amount) async {
          try {
            final bid = Bid(
              bidId: '${_web3.currentAddress!.toLowerCase()}_${DateTime.now().millisecondsSinceEpoch}',
              bidderId: AuthService.instance.currentUser?.uid ?? '',
              bidderWallet: _web3.currentAddress!,
              amount: amount,
              firstBidTimestamp: DateTime.now(),
              lastBidTimestamp: DateTime.now(),
              transactionHash:
                  'offchain_${DateTime.now().millisecondsSinceEpoch}',
            );
            await FirestoreService.instance.placeBid(
              widget.logo.tokenId,
              bid,
              userBalance: _web3.balance,
            );
            if (!mounted) return;
            NotificationManager.show(
              context: context,
              title: 'Success',
              message: 'Bid placed successfully! 🎉',
              type: NotificationType.success,
            );
          } catch (e) {
            if (!mounted) return;
            NotificationManager.show(
              context: context,
              title: 'Error',
              message: e.toString().replaceFirst("Exception: ", ""),
              type: NotificationType.error,
            );
          }
        },
      ),
    );
  }

  String _shortenAddress(String address) {
    if (address.length <= 10) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 12),
          Text(label, style: AppTextStyles.bodyMedium),
          const Spacer(),
          Text(value, style: AppTextStyles.labelMedium),
        ],
      ),
    );
  }



  Widget _placeholder() {
    return Shimmer.fromColors(
      baseColor: AppColors.surface,
      highlightColor: AppColors.border,
      child: Container(
        color: AppColors.surface,
        child: const Center(
          child: Icon(
            Icons.image_outlined,
            size: 60,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  String _formatAuctionDuration(int seconds) {
    if (seconds >= 86400) {
      final days = seconds ~/ 86400;
      return '$days ${days == 1 ? 'Day' : 'Days'}';
    } else if (seconds >= 3600) {
      final hours = seconds ~/ 3600;
      return '$hours ${hours == 1 ? 'Hour' : 'Hours'}';
    } else if (seconds >= 60) {
      final mins = seconds ~/ 60;
      return '$mins ${mins == 1 ? 'Minute' : 'Minutes'}';
    }
    return '$seconds Seconds';
  }
}

