import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nft_logo_marketplace/config/contract_config.dart';
import 'package:nft_logo_marketplace/shared/models/logo_nft.dart';
import 'package:nft_logo_marketplace/core/services/web3_service.dart';
import 'package:nft_logo_marketplace/shared/dialogs/report_dialog.dart';
import 'package:nft_logo_marketplace/features/nft/presentation/appeal_case_page.dart';
import 'package:nft_logo_marketplace/features/auction/presentation/auction_page.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/core/theme/app_spacing.dart';
import 'package:nft_logo_marketplace/core/theme/app_radius.dart';
import 'package:nft_logo_marketplace/core/theme/app_shadows.dart';
import 'package:nft_logo_marketplace/shared/widgets/primary_button.dart';
import 'package:nft_logo_marketplace/shared/models/auction.dart';
import 'package:nft_logo_marketplace/core/services/firestore_service.dart';
import 'package:nft_logo_marketplace/core/services/auth_service.dart';
import 'package:nft_logo_marketplace/shared/widgets/wallet_connect_modal.dart';
import 'package:nft_logo_marketplace/shared/dialogs/bid_dialog.dart';
import 'package:nft_logo_marketplace/shared/models/user_model.dart';
import 'package:nft_logo_marketplace/shared/widgets/auction_badge.dart';
import 'package:nft_logo_marketplace/shared/dialogs/re_auction_dialog.dart';
import 'package:nft_logo_marketplace/core/utils/notification_manager.dart';
import 'package:nft_logo_marketplace/shared/models/app_notification.dart';
import 'package:nft_logo_marketplace/core/utils/firestore_error_handler.dart';
import 'package:nft_logo_marketplace/core/exceptions/insufficient_balance_exception.dart';
import 'package:nft_logo_marketplace/shared/dialogs/insufficient_balance_dialog.dart';
import 'package:nft_logo_marketplace/core/utils/user_display_utils.dart';

class DetailLogoPage extends StatefulWidget {
  final LogoNFT logo;
  final bool openedFromMyCollection;

  const DetailLogoPage({super.key, required this.logo, this.openedFromMyCollection = false});

  @override
  State<DetailLogoPage> createState() => _DetailLogoPageState();
}

class _DetailLogoPageState extends State<DetailLogoPage> {
  final _web3 = Web3Service.instance;
  DateTime? _lastBidAttempt;
  final Map<String, UserModel> _userCache = {};

  Future<UserModel?> _getUserProfile(String walletAddress) async {
    final lowerWallet = walletAddress.toLowerCase();
    if (_userCache.containsKey(lowerWallet)) return _userCache[lowerWallet];

    try {
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
  void initState() {
    super.initState();
    _web3.addListener(_refresh);
  }

  @override
  void dispose() {
    _web3.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _mintPendingNFT(LogoNFT pendingLogo) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );

      final newLogo = await _web3.mintLogo(
        name: pendingLogo.name,
        description: pendingLogo.description,
        imageUrl: pendingLogo.imageUrl,
        price: pendingLogo.price,
        category: pendingLogo.category,
      );

      // We should also delete the old pending document to avoid duplicates
      await FirebaseFirestore.instance.collection('nfts').doc(pendingLogo.tokenId.toString()).delete();

      if (!mounted) return;
      Navigator.pop(context); // close loading
      
      NotificationManager.show(
        context: context,
        title: 'Mint Success',
        message: 'NFT successfully minted!',
        type: NotificationType.success,
      );

      // Navigate to new detail page and pop the old one
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => DetailLogoPage(logo: newLogo),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // close loading
      NotificationManager.show(
        context: context,
        title: 'Mint Failed',
        message: e.toString(),
        type: NotificationType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final logo = widget.logo;

    final auction = _web3.getAuctionForLogo(logo.tokenId);
    final isCreator = _web3.currentAddress?.toLowerCase() == logo.creatorWallet.toLowerCase();
    
    String displayImageUrl = logo.imageUrl;
    if (displayImageUrl.contains('dweb.link/ipfs/')) {
       displayImageUrl = displayImageUrl.replaceAll('dweb.link/ipfs/', 'ipfs.io/ipfs/');
    } else if (displayImageUrl.contains('ipfs://')) {
       displayImageUrl = displayImageUrl.replaceAll('ipfs://', 'https://ipfs.io/ipfs/');
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('nfts').doc(logo.tokenId.toString()).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return FirestoreErrorHandler.buildErrorWidget(
              snapshot.error,
              onRetry: () {
                if (mounted) setState(() {});
              },
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }
          final doc = snapshot.data!;
          final data = doc.data() as Map<String, dynamic>? ?? {};
          final status = data['status'] ?? 'unknown';
          final auctionCreated = data['auctionCreated'] ?? false;
          final isActive = data['isActive'] ?? true;

          return CustomScrollView(
            slivers: [
              // Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ App Bar Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
              SliverAppBar(
                pinned: true,
                backgroundColor: AppColors.background,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                  onPressed: () => Navigator.pop(context),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.share_outlined, color: AppColors.textPrimary),
                    onPressed: () {
                      // Share functionality
                    },
                  ),
                ],
              ),

              // Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ Content Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
              SliverToBoxAdapter(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isDesktop = constraints.maxWidth > 900;
                    
                    if (isDesktop) {
                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1200),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sectionPadding, vertical: AppSpacing.lg),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Left side - Image
                                Expanded(
                                  flex: 5,
                                  child: _buildImageHero(displayImageUrl),
                                ),
                                const SizedBox(width: AppSpacing.sectionPadding),
                                // Right side - Details
                                Expanded(
                                  flex: 4,
                                  child: _buildDetailsColumn(logo, auction, isCreator, status, auctionCreated, isActive),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    } else {
                      return Padding(
                        padding: const EdgeInsets.all(AppSpacing.screenPadding),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildImageHero(displayImageUrl),
                            const SizedBox(height: AppSpacing.xxl),
                            _buildDetailsColumn(logo, auction, isCreator, status, auctionCreated, isActive),
                          ],
                        ),
                      );
                    }
                  },
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          );
        }
      ),
    );
  }

  Widget _buildImageHero(String displayImageUrl) {
    return AspectRatio(
      aspectRatio: 1.0,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.xxl),
          border: Border.all(color: AppColors.border, width: 2),
          boxShadow: AppShadows.glowPrimary,
          color: AppColors.surface,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.xxl),
          child: displayImageUrl.isNotEmpty
              ? (displayImageUrl.startsWith('data:image') 
                  ? Image.memory(base64Decode(displayImageUrl.split(',').last), fit: BoxFit.contain, width: double.infinity) 
                  : CachedNetworkImage(
                      imageUrl: displayImageUrl,
                      fit: BoxFit.contain,
                      width: double.infinity,
                      placeholder: (context, url) => _placeholder(),
                      errorWidget: (context, url, error) => _placeholder(),
                    ))
              : _placeholder(),
        ),
      ),
    );
  }

  Widget _buildDetailsColumn(LogoNFT logo, Auction? auction, bool isCreator, String status, bool auctionCreated, bool isActive) {
    final bool isCompletedCollectionNFT = widget.openedFromMyCollection;
    
    final bool isCompleted = isCompletedCollectionNFT || 
                             logo.auctionStatus == 'COMPLETED' || 
                             logo.auctionStatus == 'PAYMENT_COMPLETED' || 
                             status == 'sold' ||
                             logo.ownershipType == 'collected';

    final bool hasVerification = isCompleted || (logo.copyrightHash != null && logo.copyrightHash!.isNotEmpty);





    final bool showFinalBidPrice = isCompleted;
    final bool showAuctionDuration = !isCompleted;
    final bool showOwnerWallet = isCompleted || logo.canViewCurrentOwner(currentWallet: _web3.currentAddress ?? '');

    final bool canDownload = isCompleted && logo.ownerWallet.toLowerCase() == (_web3.currentAddress ?? '').toLowerCase();

    final double bidPrice = (logo.previousFinalBid != null && logo.previousFinalBid! > 0) ? logo.previousFinalBid! : (logo.highestBid > 0 ? logo.highestBid : 0.0);
    final formattedPrice = '${bidPrice.toStringAsFixed(2)} ETH';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!_web3.isConnected)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.lg),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.accentOrange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.accentOrange.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.visibility_outlined, color: AppColors.accentOrange, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('View Only Mode', style: AppTextStyles.labelLarge.copyWith(color: AppColors.accentOrange)),
                      const SizedBox(height: 4),
                      Text('Connect your wallet to interact.', style: AppTextStyles.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // Collection / Category
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.category, size: 14, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(logo.category, style: AppTextStyles.labelMedium.copyWith(color: AppColors.primary)),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // Title & Badge
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    logo.name, 
                    style: AppTextStyles.display.copyWith(
                      fontSize: MediaQuery.of(context).size.width < 600 ? 28 : 36,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text('Token #${logo.tokenId}', style: AppTextStyles.subtitle2),
                ],
              ),
            ),
            if (auction != null && auction.isOngoing)
              const AuctionBadge(text: 'LIVE', type: BadgeType.live)
            else if (logo.auctionStatus == 'RE_AUCTION_REQUESTED')
              const AuctionBadge(text: 'RE-AUCTION REQUESTED', type: BadgeType.neutral)
            else if (status == 'ended_no_bid' || logo.auctionStatus == 'ENDED_NO_BID')
              const AuctionBadge(text: 'NO BIDS', type: BadgeType.ended)
            else if (auctionCreated && !isActive)
              const AuctionBadge(text: 'ENDED', type: BadgeType.ended)
            else if (auctionCreated && isActive)
              const AuctionBadge(text: 'AUCTION', type: BadgeType.success)
            else if (status == 'approved')
              const AuctionBadge(text: 'APPROVED', type: BadgeType.success)
            else if (status == 'pending')
              const AuctionBadge(text: 'PENDING', type: BadgeType.neutral)
            else if (status == 'rejected')
              const AuctionBadge(text: 'REJECTED', type: BadgeType.ended)
            else if (status == 'disabled')
              const AuctionBadge(text: 'DISABLED', type: BadgeType.neutral),
          ],
        ),
        const SizedBox(height: AppSpacing.xxl),

        // Creator Profile Card
        FutureBuilder<UserModel?>(
          future: AuthService.instance.getUserData(logo.creatorId),
          builder: (context, snapshot) {
            final creatorUser = snapshot.data;
            return Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                gradient: AppColors.cardGradient,
                borderRadius: BorderRadius.circular(AppRadius.xl),
                border: Border.all(color: AppColors.border),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  Widget creatorAvatar = CircleAvatar(
                    radius: constraints.maxWidth < 400 ? 20 : 24,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                    backgroundImage: creatorUser?.profileImage != null && creatorUser!.profileImage!.startsWith('data:image')
                        ? MemoryImage(base64Decode(creatorUser.profileImage!.split(',')[1]))
                        : null,
                    child: creatorUser?.profileImage == null || !creatorUser!.profileImage!.startsWith('data:image')
                        ? Icon(Icons.person, color: AppColors.primary, size: constraints.maxWidth < 400 ? 18 : 24)
                        : null,
                  );

                  String creatorName = creatorUser?.displayName ?? logo.creatorUsername ?? _shortenAddress(logo.creatorWallet);

                  if (constraints.maxWidth < 400) {
                    // Stack vertically on very small screens
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            creatorAvatar,
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Creator', style: AppTextStyles.caption),
                                  Text(creatorName, style: AppTextStyles.labelMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  if (creatorUser?.country?.isNotEmpty == true)
                                    Row(
                                      children: [
                                        const Icon(Icons.public, size: 12, color: AppColors.textSecondary),
                                        const SizedBox(width: 4),
                                        Expanded(child: Text(creatorUser?.country ?? '', style: AppTextStyles.caption, maxLines: 1, overflow: TextOverflow.ellipsis)),
                                      ],
                                    )
                                  else if (logo.creatorUsername != null && logo.creatorUsername!.isNotEmpty)
                                    Text(_shortenAddress(logo.creatorWallet), style: AppTextStyles.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                          ],
                        ),
                        Divider(color: AppColors.border, height: 24),
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: AppColors.accentOrange.withValues(alpha: 0.2),
                              child: const Icon(Icons.person_outline, color: AppColors.accentOrange, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (showOwnerWallet) Text('Current Owner', style: AppTextStyles.caption),
                                  Text(!showOwnerWallet ? 'Owner Hidden for Privacy' : _shortenAddress(logo.ownerWallet.isNotEmpty ? logo.ownerWallet : logo.creatorWallet), style: !showOwnerWallet ? AppTextStyles.labelMedium.copyWith(fontStyle: FontStyle.italic, color: AppColors.textSecondary) : AppTextStyles.labelMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      creatorAvatar,
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Creator', style: AppTextStyles.caption),
                            Text(creatorName, style: AppTextStyles.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                            if (creatorUser?.country?.isNotEmpty == true)
                              Row(
                                children: [
                                  const Icon(Icons.public, size: 14, color: AppColors.textSecondary),
                                  const SizedBox(width: 4),
                                  Expanded(child: Text(creatorUser?.country ?? '', style: AppTextStyles.caption, maxLines: 1, overflow: TextOverflow.ellipsis)),
                                ],
                              )
                            else if (logo.creatorUsername != null && logo.creatorUsername!.isNotEmpty)
                              Text(_shortenAddress(logo.creatorWallet), style: AppTextStyles.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 40,
                        color: AppColors.border,
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (showOwnerWallet) Text('Current Owner', style: AppTextStyles.caption),
                            Text(!showOwnerWallet ? 'Owner Hidden for Privacy' : _shortenAddress(logo.ownerWallet.isNotEmpty ? logo.ownerWallet : logo.creatorWallet), style: !showOwnerWallet ? AppTextStyles.labelLarge.copyWith(fontStyle: FontStyle.italic, color: AppColors.textSecondary) : AppTextStyles.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          }
        ),
        if (hasVerification)
          Container(
            margin: const EdgeInsets.only(top: AppSpacing.md),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.verified, size: 16, color: AppColors.success),
                const SizedBox(width: 8),
                Text('Copyright Verified', style: AppTextStyles.labelMedium.copyWith(color: AppColors.success)),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.xl),

        // Description
        Text('Description', style: AppTextStyles.h3),
        const SizedBox(height: AppSpacing.sm),
        Text(
          logo.description,
          style: AppTextStyles.bodyLarge.copyWith(height: 1.6, color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.lg),

        // Add Category & Auction Duration Info
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.category_outlined, color: AppColors.primary, size: 20),
                  const SizedBox(width: 12),
                  Text('Category', style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary)),
                  const Spacer(),
                  Text(logo.category, style: AppTextStyles.labelLarge),
                ],
              ),
              const Divider(color: AppColors.border, height: 24),
              if (showFinalBidPrice) ...[
                Row(
                  children: [
                    const Icon(Icons.local_offer_outlined, color: AppColors.accentOrange, size: 20),
                    const SizedBox(width: 12),
                    Text('Final Bid Price', style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary)),
                    const Spacer(),
                    Text(formattedPrice, style: AppTextStyles.labelLarge.copyWith(color: AppColors.accentOrange, fontWeight: FontWeight.bold)),
                  ],
                ),
                if (logo.highestBidderWallet != null && logo.highestBidderWallet!.isNotEmpty) ...[
                  const Divider(color: AppColors.border, height: 24),
                  Row(
                    children: [
                      const Icon(Icons.emoji_events_outlined, color: AppColors.accentOrange, size: 20),
                      const SizedBox(width: 12),
                      Text('Highest Bidder', style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary)),
                      const Spacer(),
                      FutureBuilder<UserModel?>(
                        future: _getUserProfile(logo.highestBidderWallet!),
                        builder: (context, snapshot) {
                          final displayName = UserDisplayUtils.getDisplayName(snapshot.data, logo.highestBidderWallet!);
                          return Text(displayName, style: AppTextStyles.labelLarge);
                        },
                      ),
                    ],
                  ),
                ],
              ] else if (showAuctionDuration) ...[
                Row(
                  children: [
                    const Icon(Icons.timer_outlined, color: AppColors.accentOrange, size: 20),
                    const SizedBox(width: 12),
                    Text('Auction Duration', style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary)),
                    const Spacer(),
                    Text(_formatDuration(logo.auctionDuration ?? 86400), style: AppTextStyles.labelLarge),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),

        // Copyright verification
        if (hasVerification) ...[
          _buildPremiumCopyrightCard(logo),
          const SizedBox(height: AppSpacing.lg),
        ],

        // Blockchain transaction
        if (logo.txHash != null && logo.txHash!.isNotEmpty)
          _buildBlockchainInfoCard(logo.txHash!),
        const SizedBox(height: AppSpacing.xxl),

        // â€”â€”â€” Actions â€”â€”â€”
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              if (logo.isFrozen) ...[
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: Colors.lightBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: Colors.lightBlue.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.gavel, color: Colors.lightBlue, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Copyright Review', style: AppTextStyles.labelLarge.copyWith(color: Colors.lightBlue)),
                                const SizedBox(height: 4),
                                Text('This NFT is currently under review due to a copyright report.', style: AppTextStyles.bodySmall),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => AppealCasePage(logo: logo)));
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.lightBlue,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('View Case'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              if (!logo.isFrozen) ...[
                // Completed Actions (Download / Save to Gallery)
                if (canDownload) ...[
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                        onPressed: () => _downloadNFT(logo.imageUrl),
                        icon: const Icon(Icons.download),
                        label: const Text('Download NFT', maxLines: 1, overflow: TextOverflow.ellipsis),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _saveToGallery(logo.imageUrl),
                        icon: const Icon(Icons.image),
                        label: const Text('Save to Gallery', maxLines: 1, overflow: TextOverflow.ellipsis),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                          foregroundColor: AppColors.primary,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                            side: BorderSide(color: AppColors.primary.withValues(alpha: 0.3)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
              ],


              // Mint Pending NFT Button
              if (isCreator && status == 'approvedPendingMint')
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.accentOrange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: AppColors.accentOrange.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.stars, color: AppColors.accentOrange, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Admin approved! Mint your NFT to the blockchain to make it official.',
                              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.accentOrange, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => _mintPendingNFT(logo),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accentOrange,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Mint Now'),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Estimated Gas Fee will be calculated by MetaMask',
                        style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary, fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),

              // Show manual start auction button for creators when approved/available
              if (isCreator && (status == 'approved' || status == 'available') && !isActive && (logo.auctionStatus == 'NONE' || logo.auctionStatus == 'COMPLETED' || logo.auctionStatus == 'ENDED_NO_BID' || logo.auctionStatus == 'PAYMENT_EXPIRED'))
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.rocket_launch, color: AppColors.success, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Your NFT is ready! Start the auction to allow bidding.',
                              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.success, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            if (logo.isAuctionActive || logo.auctionStatus == 'ACTIVE') {
                              NotificationManager.show(
                                context: context,
                                title: 'Error',
                                message: 'An auction is already active for this NFT.',
                                type: NotificationType.error,
                              );
                              return;
                            }
                            try {
                              showDialog(
                                context: context,
                                barrierDismissible: false,
                                builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
                              );
                              // 1. Create on-chain
                              await _web3.createAuctionOnChain(
                                tokenId: logo.tokenId,
                                creatorAddress: logo.creatorWallet,
                                startingPrice: logo.price,
                                durationSeconds: logo.auctionDuration ?? 86400,
                              );
                              // 2. Start on Firestore
                              await FirestoreService.instance.startAuction(logo.tokenId);
                              if (!mounted) return;
                              Navigator.pop(context); // close loading
                              NotificationManager.show(
                                context: context,
                                title: 'Auction Started',
                                message: 'Your NFT is now live for bidding!',
                                type: NotificationType.success,
                              );
                            } on InsufficientBalanceException catch (e) {
                              if (!mounted) return;
                              Navigator.pop(context); // close loading
                              showDialog(
                                context: context,
                                builder: (_) => InsufficientBalanceDialog(exception: e),
                              );
                            } catch (e) {
                              if (!mounted) return;
                              Navigator.pop(context); // close loading
                              NotificationManager.show(
                                context: context,
                                title: 'Error',
                                message: 'Failed to start auction: $e',
                                type: NotificationType.error,
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.success,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Start Auction Now'),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Estimated Gas Fee will be calculated by MetaMask',
                        style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary, fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),

              // Ended with no bids or payment expired info
              if (isCreator && (logo.auctionStatus == 'EXPIRED_NO_BID' || logo.auctionStatus == 'ENDED_NO_BIDS' || logo.auctionStatus == 'ENDED_NO_BID' || logo.auctionStatus == 'PAYMENT_EXPIRED'))
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.textSecondary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: AppColors.textSecondary.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.timer_off, color: AppColors.textSecondary, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              logo.auctionStatus == 'PAYMENT_EXPIRED' 
                                ? 'Winner failed to pay within 24 hours.' 
                                : 'Auction ended. No bids were placed.',
                              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => ReAuctionDialog.show(context, logo),
                          child: const Text('Request Re-Auction'),
                        ),
                      ),
                    ],
                  ),
                ),

              // Re-Auction Requested Banner
              if (isCreator && logo.auctionStatus == 'RE_AUCTION_REQUESTED' && status != 'rejected')
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.pending_actions, color: AppColors.primary, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Re-Auction requested. Waiting for admin approval.',
                          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary),
                        ),
                      ),
                    ],
                  ),
                ),

              if (status == 'pending' || status == 'rejected' || status == 'disabled' || (status != 'approved' && status != 'sold'))
                Builder(builder: (_) {
                  late final Color color;
                  late final String message;

                  if (status == 'disabled') {
                    color = AppColors.textSecondary;
                    message = 'This NFT has been disabled by admin.';
                  } else if (status == 'rejected') {
                    color = AppColors.danger;
                    message = 'This NFT has been permanently removed by marketplace moderation.';
                  } else if (status != 'approved' && status != 'sold' && status != 'available') {
                    color = AppColors.accentOrange;
                    message = 'NFT is waiting for admin approval.';
                  } else {
                    return const SizedBox.shrink();
                  }

                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: color.withValues(alpha: 0.3)),
                    ),
                    child: Text(message, style: AppTextStyles.bodyMedium.copyWith(color: color)),
                  );
                }),

              if (auction != null && auction.isOngoing)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: PrimaryButton(
                    text: 'View Live Auction',
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AuctionPage(logo: logo))),
                  ),
                ),
              
              // Payment pending - show for winner or creator
              if (auctionCreated && !isActive && logo.highestBidderWallet != null && status != 'rejected' && (logo.auctionStatus == 'PAYMENT_PENDING' || logo.auctionStatus == 'PENDING_PAYMENT' || logo.auctionStatus == 'payment_pending' || logo.auctionStatus == 'pending_payment'))
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.accentOrange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: AppColors.accentOrange.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.payment, color: AppColors.accentOrange, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Auction ended. Payment pending from the winner.',
                                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.accentOrange, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        if (logo.paymentDeadline != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.access_time, color: AppColors.accentOrange, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: StreamBuilder<int>(
                                  stream: Stream.periodic(const Duration(seconds: 1), (i) => i),
                                  builder: (context, _) {
                                    final now = DateTime.now();
                                    final deadline = logo.paymentDeadline!;
                                    if (now.isAfter(deadline)) {
                                      return Text('Payment deadline has expired.', style: AppTextStyles.bodySmall.copyWith(color: AppColors.danger, fontWeight: FontWeight.bold));
                                    }
                                    final diff = deadline.difference(now);
                                    final hours = diff.inHours;
                                    final minutes = (diff.inMinutes % 60).toString().padLeft(2, '0');
                                    final seconds = (diff.inSeconds % 60).toString().padLeft(2, '0');
                                    return Text(
                                      'Expires in: $hours:$minutes:$seconds',
                                      style: AppTextStyles.bodyMedium.copyWith(color: AppColors.accentOrange, fontWeight: FontWeight.bold),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ], // End of !logo.isFrozen block

              if (!logo.isFrozen)
                TextButton.icon(
                onPressed: () => ReportDialog.show(context, widget.logo.tokenId),
                icon: const Icon(Icons.flag_outlined, size: 16, color: AppColors.danger),
                label: Text('Report Artwork', style: AppTextStyles.labelMedium.copyWith(color: AppColors.danger)),
              ),
            ],
          ),
        ),

        // â€”â€”â€” Leaderboard Section â€”â€”â€”
        if (auctionCreated)
          _buildLeaderboardSection(auction),
      ],
    );
  }

  Widget _placeholder() {
    return Shimmer.fromColors(
      baseColor: AppColors.surface,
      highlightColor: AppColors.border,
      child: Container(
        color: AppColors.surface,
        child: const Center(
          child: Icon(Icons.image_outlined, size: 60, color: AppColors.textSecondary),
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    if (seconds == 3600) return '1 Hour';
    if (seconds == 21600) return '6 Hours';
    if (seconds == 43200) return '12 Hours';
    if (seconds == 86400) return '24 Hours';
    if (seconds == 259200) return '3 Days';
    if (seconds == 604800) return '7 Days';
    return '${(seconds / 3600).round()} Hours';
  }

  Widget _buildLeaderboardSection(Auction? auction) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.xxl),

        // Section Header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.emoji_events, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Bid Leaderboard', style: AppTextStyles.h3),
            ),
            if (auction != null && auction.isOngoing)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6, height: 6,
                      decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text('LIVE', style: AppTextStyles.labelSmall.copyWith(color: AppColors.success, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),

        // Leaderboard Content
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: AppColors.border),
          ),
          child: StreamBuilder<List<Bid>>(
            stream: FirestoreService.instance.getAuctionBidsStream(widget.logo.tokenId),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(AppSpacing.xxl),
                  child: FirestoreErrorHandler.buildErrorWidget(
                    snapshot.error,
                    onRetry: () {
                      if (mounted) setState(() {});
                    },
                  ),
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(AppSpacing.xxl),
                  child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                );
              }

              final bids = snapshot.data ?? [];

              if (bids.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(AppSpacing.xxl),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.gavel_outlined, size: 48, color: AppColors.textSecondary.withValues(alpha: 0.4)),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          auction != null && auction.isOngoing ? 'No bids yet â€” be the first!' : 'No bids were placed',
                          style: AppTextStyles.labelLarge.copyWith(color: AppColors.textSecondary),
                        ),
                        if (auction != null && auction.isOngoing) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'Place your bid to claim the top spot',
                            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }

              // Show up to 10 bids
              final displayBids = bids.take(10).toList();

              return Column(
                children: [
                  // Summary Header
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary.withValues(alpha: 0.1),
                          Colors.transparent,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.how_to_vote_outlined, color: AppColors.primary, size: 18),
                            const SizedBox(width: 8),
                            Text('${bids.length} ${bids.length == 1 ? 'bid' : 'bids'}', style: AppTextStyles.labelLarge),
                          ],
                        ),
                        Row(
                          children: [
                            Text('Highest: ', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                            Text('${bids.first.amount.toStringAsFixed(4)} ETH', style: AppTextStyles.labelLarge.copyWith(color: AppColors.primary)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.border),

                  // Bid Rows
                  ...displayBids.asMap().entries.map((entry) {
                    final index = entry.key;
                    final bid = entry.value;

                    final rank = index + 1;
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

                    // Fetch user profile based on wallet address
                    final future = bid.bidderId.isNotEmpty 
                        ? FirebaseFirestore.instance.collection('users').doc(bid.bidderId).get().then((doc) => doc.exists ? UserModel.fromFirestore(doc.data()!) : null)
                        : FirebaseFirestore.instance.collection('users').where('walletAddress', isEqualTo: bid.bidderWallet).limit(1).get().then((q) => q.docs.isNotEmpty ? UserModel.fromFirestore(q.docs.first.data()) : null);

                    return FutureBuilder<UserModel?>(
                      future: future,
                      builder: (context, snapshot) {
                        final user = snapshot.data;
                        
                        final username = user?.username ?? 'Anonymous Bidder';
                        final country = user?.country ?? 'Unknown';
                        final profileImageUrl = user?.profileImage;

                        return Container(
                          margin: const EdgeInsets.only(bottom: AppSpacing.sm, left: AppSpacing.md, right: AppSpacing.md),
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
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.card,
                                  border: Border.all(color: AppColors.border),
                                ),
                                clipBehavior: Clip.hardEdge,
                                child: profileImageUrl != null && profileImageUrl.isNotEmpty
                                    ? Image.network(profileImageUrl, fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => const Icon(Icons.person, color: AppColors.textSecondary))
                                    : const Icon(Icons.person, color: AppColors.textSecondary),
                              ),
                              const SizedBox(width: 12),

                              // Bidder Info
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      username,
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
                    );
                  }),

                  // Show "more" indicator
                  if (bids.length > 10)
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Text(
                        '+ ${bids.length - 10} more bids',
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                ],
              );
            },
          ),
        ),

        // Bid Now Button
        if (auction != null && auction.isOngoing)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.lg),
            child: PrimaryButton(
              text: 'Bid Now',
              icon: Icons.rocket_launch,
              backgroundColor: AppColors.accentOrange,
              onPressed: () => _showBidDialog(auction),
            ),
          ),
      ],
    );
  }

  void _showBidDialog(Auction auction) {
    if (!_web3.isConnected) {
      WalletUtils.showConnectDialog(
        context,
        _web3,
        title: 'Connect Wallet Required',
        message: 'Please connect your wallet to purchase this artwork.',
      ).then((connected) {
         if (connected && mounted) setState(() {});
      });
      return;
    }

    if (_lastBidAttempt != null && DateTime.now().difference(_lastBidAttempt!).inSeconds < 3) {
      NotificationManager.show(context: context, title: 'Rate Limit', message: 'Please wait 3 seconds before trying again.', type: NotificationType.warning);
      return;
    }
    _lastBidAttempt = DateTime.now();

    final currentWallet = _web3.currentAddress;
    final logo = widget.logo;
    if (currentWallet != null && currentWallet.toLowerCase().trim() == logo.ownerWallet.toLowerCase().trim()) {
      NotificationManager.show(context: context, title: 'Invalid Bid', message: 'Cannot bid on own auction', type: NotificationType.warning);
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
              bidId: _web3.currentAddress!.toLowerCase(),
              bidderId: AuthService.instance.currentUser?.uid ?? '',
              bidderWallet: _web3.currentAddress!,
              amount: amount,
              firstBidTimestamp: DateTime.now(),
              lastBidTimestamp: DateTime.now(),
              transactionHash: 'offchain_${DateTime.now().millisecondsSinceEpoch}',
            );
            await FirestoreService.instance.placeBid(widget.logo.tokenId, bid, userBalance: _web3.balance);
            if (!mounted) return;
            NotificationManager.show(context: context, title: 'Success', message: 'Bid placed successfully! ðŸŽ‰', type: NotificationType.success);
          } catch (e) {
            if (!mounted) return;
            NotificationManager.show(context: context, title: 'Error', message: e.toString().replaceFirst("Exception: ", ""), type: NotificationType.error);
          }
        },
      ),
    );
  }



  Widget _buildPremiumCopyrightCard(LogoNFT logo) {
    return _PremiumCopyrightCard(logo: logo);
  }

  Widget _buildBlockchainInfoCard(String txHash) {
    final explorerUrls = ContractConfig.getTxExplorerUrls(txHash);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.link, color: AppColors.primary, size: 24),
              const SizedBox(width: 12),
              Text('Blockchain Transaction', style: AppTextStyles.labelLarge.copyWith(color: AppColors.primary)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy, size: 18, color: AppColors.textSecondary),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: txHash));
                  NotificationManager.show(context: context, title: 'Copied', message: 'Copied!', type: NotificationType.info);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Tx: ${txHash.substring(0, 10)}...${txHash.substring(txHash.length - 8)}',
            style: AppTextStyles.bodySmall.copyWith(fontFamily: 'monospace'),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: explorerUrls.map((explorer) {
              return ActionChip(
                label: Text(explorer['name']!, style: AppTextStyles.labelMedium),
                backgroundColor: AppColors.surface,
                side: const BorderSide(color: AppColors.border),
                onPressed: () => _openExplorer(explorer['url']!),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Future<void> _openExplorer(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _shortenAddress(String address) {
    if (address.length <= 10) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
  }

  Future<void> _downloadNFT(String imageUrl) async {
    if (!_web3.isConnected) {
      WalletUtils.showConnectDialog(
        context,
        _web3,
        title: 'Connect Wallet Required',
        message: 'Please connect your wallet to purchase this artwork.',
      ).then((connected) {
         if (connected && mounted) setState(() {});
      });
      return;
    }
    try {
      if (imageUrl.startsWith('data:image')) {
        final bytes = base64Decode(imageUrl.split(',').last);
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/nft_${DateTime.now().millisecondsSinceEpoch}.png');
        await file.writeAsBytes(bytes);
        if (!mounted) return;
        NotificationManager.show(context: context, title: 'Success', message: 'NFT downloaded to temporary storage.', type: NotificationType.success);
        return;
      }

      String url = imageUrl;
      if (url.contains('dweb.link/ipfs/')) {
        url = url.replaceAll('dweb.link/ipfs/', 'ipfs.io/ipfs/');
      } else if (url.contains('ipfs://')) {
        url = url.replaceAll('ipfs://', 'https://ipfs.io/ipfs/');
      }

      final tempDir = await getTemporaryDirectory();
      final savePath = '${tempDir.path}/nft_${DateTime.now().millisecondsSinceEpoch}.png';

      await Dio().download(url, savePath);

      if (!mounted) return;
      NotificationManager.show(context: context, title: 'Success', message: 'NFT downloaded successfully!', type: NotificationType.success);
    } catch (e) {
      if (!mounted) return;
      NotificationManager.show(context: context, title: 'Error', message: 'Failed to download NFT.', type: NotificationType.error);
    }
  }

  Future<void> _saveToGallery(String imageUrl) async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final hasAccess = await Gal.hasAccess();
        if (!hasAccess) {
          final request = await Gal.requestAccess();
          if (!request) {
            if (!mounted) return;
            NotificationManager.show(context: context, title: 'Permission Denied', message: 'Storage permission is required to save to gallery.', type: NotificationType.error);
            return;
          }
        }
      }

      String? filePath;

      if (imageUrl.startsWith('data:image')) {
        final bytes = base64Decode(imageUrl.split(',').last);
        final tempDir = await getTemporaryDirectory();
        filePath = '${tempDir.path}/gallery_${DateTime.now().millisecondsSinceEpoch}.png';
        final file = File(filePath);
        await file.writeAsBytes(bytes);
      } else {
        String url = imageUrl;
        if (url.contains('dweb.link/ipfs/')) {
          url = url.replaceAll('dweb.link/ipfs/', 'ipfs.io/ipfs/');
        } else if (url.contains('ipfs://')) {
          url = url.replaceAll('ipfs://', 'https://ipfs.io/ipfs/');
        }

        final tempDir = await getTemporaryDirectory();
        filePath = '${tempDir.path}/gallery_${DateTime.now().millisecondsSinceEpoch}.png';
        await Dio().download(url, filePath);
      }

      await Gal.putImage(filePath);
      if (!mounted) return;
      NotificationManager.show(context: context, title: 'Success', message: 'NFT saved to gallery! ðŸŽ‰', type: NotificationType.success);
    } catch (e) {
      if (!mounted) return;
      NotificationManager.show(context: context, title: 'Error', message: 'Failed to save to gallery.', type: NotificationType.error);
    }
  }
}

class _PremiumCopyrightCard extends StatefulWidget {
  final LogoNFT logo;

  const _PremiumCopyrightCard({required this.logo});

  @override
  State<_PremiumCopyrightCard> createState() => _PremiumCopyrightCardState();
}

class _PremiumCopyrightCardState extends State<_PremiumCopyrightCard> {
  bool _isExpanded = false;

  void _copyHash() {
    final hashToCopy = widget.logo.copyrightHash ?? widget.logo.imageHash;
    Clipboard.setData(ClipboardData(text: hashToCopy));
    NotificationManager.show(
      context: context,
      title: 'Copied',
      message: 'Hash copied! \uD83D\uDCCB',
      type: NotificationType.info,
    );
  }

  String _shortenHash(String hash) {
    if (hash.length <= 16) return hash;
    return '${hash.substring(0, 10)}...${hash.substring(hash.length - 6)}';
  }

  String _shortenAddress(String address) {
    if (address.length <= 10) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    final hasCopyrightInfo = widget.logo.copyrightHash != null && widget.logo.copyrightHash!.isNotEmpty;
    final algorithm = widget.logo.hashAlgorithm ?? 'SHA-256';
    final hashValue = hasCopyrightInfo ? widget.logo.copyrightHash! : widget.logo.imageHash;
    final verifiedDate = widget.logo.copyrightVerifiedAt ?? widget.logo.createdAt;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.success.withValues(alpha: 0.15),
            AppColors.success.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
        boxShadow: _isExpanded ? AppShadows.glowSuccess : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.verified_user, color: AppColors.success, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('Copyright Verified', style: AppTextStyles.subtitle1.copyWith(color: AppColors.success)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.success,
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: Text(algorithm, style: AppTextStyles.labelSmall.copyWith(color: AppColors.background, fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _shortenHash(hashValue),
                              style: AppTextStyles.mono.copyWith(color: AppColors.textPrimary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          GestureDetector(
                            onTap: _copyHash,
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8.0),
                              child: Icon(Icons.copy, size: 16, color: AppColors.success),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  color: AppColors.success,
                ),
              ],
            ),
          ),
          
          if (_isExpanded) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Divider(color: AppColors.success, height: 1),
            ),
            
            // Expanded Details
            Text('Verified Ownership', style: AppTextStyles.labelLarge.copyWith(color: AppColors.success)),
            const SizedBox(height: AppSpacing.sm),
            
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.success.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  _buildDetailRow('Creator', widget.logo.creatorUsername ?? _shortenAddress(widget.logo.creatorWallet)),
                  const SizedBox(height: 6),
                  _buildDetailRow('Current Owner', _shortenAddress(widget.logo.ownerWallet)),
                  const SizedBox(height: 6),
                  _buildDetailRow('Verification Date', '${verifiedDate.day}/${verifiedDate.month}/${verifiedDate.year}'),
                  const SizedBox(height: 6),
                  _buildDetailRow('Network', 'Sepolia Ethereum'),
                ],
              ),
            ),
            
            const SizedBox(height: AppSpacing.md),
            Text(
              'This digital fingerprint ensures the authenticity of the artwork and verifies the ownership rights.',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary, fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary)),
        Text(value, style: AppTextStyles.labelMedium.copyWith(color: AppColors.textPrimary)),
      ],
    );
  }
}
