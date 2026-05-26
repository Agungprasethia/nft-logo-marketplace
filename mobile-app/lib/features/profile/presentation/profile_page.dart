import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nft_logo_marketplace/core/utils/firestore_error_handler.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import 'package:nft_logo_marketplace/shared/models/auction.dart';
import 'package:nft_logo_marketplace/shared/models/logo_nft.dart';
import 'package:nft_logo_marketplace/shared/models/user_model.dart';
import 'package:nft_logo_marketplace/core/services/web3_service.dart';
import 'package:nft_logo_marketplace/core/services/firestore_service.dart';
import 'package:nft_logo_marketplace/core/services/auth_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:nft_logo_marketplace/shared/widgets/logo_card.dart';
import 'package:nft_logo_marketplace/shared/widgets/primary_button.dart';
import 'package:nft_logo_marketplace/shared/widgets/glass_card.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/core/theme/app_spacing.dart';
import 'package:nft_logo_marketplace/core/theme/app_shadows.dart';
import 'package:nft_logo_marketplace/features/nft/presentation/detail_logo_page.dart';
import 'package:nft_logo_marketplace/features/auction/presentation/auction_page.dart';
import 'package:nft_logo_marketplace/features/auction/presentation/auction_payment_page.dart';
import 'package:nft_logo_marketplace/features/profile/presentation/edit_profile_page.dart';
import 'package:nft_logo_marketplace/core/utils/wallet_utils.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:nft_logo_marketplace/core/theme/app_radius.dart';
import 'package:nft_logo_marketplace/features/profile/presentation/widgets/live_auction_monitoring.dart';
import 'package:nft_logo_marketplace/shared/widgets/custom_loading_indicator.dart';
import 'package:nft_logo_marketplace/core/utils/notification_manager.dart';
import 'package:nft_logo_marketplace/shared/models/notification_model.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with SingleTickerProviderStateMixin {
  final _web3 = Web3Service.instance;
  Timer? _refreshTimer;
  UserModel? _userProfile;
  late TabController _tabController;
  
  bool _isDownloading = false;
  int _auctionFilter = 0; // 0: All, 1: Live, 2: Ended, 3: Pending Payment, 4: Frozen

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _web3.addListener(_onWeb3StateChanged);
    FirestoreService.instance.closeExpiredAuctions();
    FirestoreService.instance.expirePaymentDeadlines();
    _loadProfile();
  }

  void _onWeb3StateChanged() {
    _loadProfile();
    if (mounted) setState(() {});
  }

  Future<void> _loadProfile() async {
    final isAuthenticated = _web3.isConnected && (_web3.currentAddress?.isNotEmpty ?? false);
    if (!isAuthenticated) {
      if (mounted) setState(() => _userProfile = null);
      return;
    }

    final firebaseUser = FirebaseAuth.instance.currentUser;
    final walletAddress = _web3.currentAddress?.toLowerCase();
    final uid = firebaseUser?.uid ?? walletAddress;

    if (uid != null) {
      final profile = await AuthService.instance.getUserData(uid);
      if (mounted) {
        setState(() {
          _userProfile = profile;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _userProfile = null;
        });
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _refreshTimer?.cancel();
    _web3.removeListener(_onWeb3StateChanged);
    super.dispose();
  }

  void _logout() async {
    _web3.disconnectWallet();
    await AuthService.instance.signOut();
    if (mounted) setState(() {});
  }


  @override
  Widget build(BuildContext context) {
    final isAuthenticated = _web3.isConnected && (_web3.currentAddress?.isNotEmpty ?? false);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: isAuthenticated 
          ? Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: _buildProfile(),
              ),
            ) 
          : _buildConnectPrompt(),
    );
  }

  Widget _buildProfile() {
    final currentWallet = _web3.currentAddress?.toLowerCase().trim() ?? '';
    final myLogos = _web3.getMyLogos();
    final myCreatedLogos = _web3.getMyCreatedLogos().where((logo) {
      final isCreator = logo.creatorWallet.toLowerCase().trim() == currentWallet;
      final stillOwnedByCreator = logo.auctionStatus != 'PAYMENT_COMPLETED';
      return isCreator && stillOwnedByCreator;
    }).toList();
    final myAuctions = _web3.allAuctions.where((a) {
      return a.sellerWallet.toLowerCase() == (_web3.currentAddress?.toLowerCase() ?? '');
    }).toList();

    return CustomScrollView(
      slivers: [
        // ─── Profile Info ───
        // ─── Profile Info ───
        SliverToBoxAdapter(
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. HEADER PROFILE CARD
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(AppRadius.xxl),
                      border: Border.all(color: AppColors.border),
                      boxShadow: AppShadows.soft,
                    ),
                    child: Row(
                      children: [
                        // Avatar
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: AppColors.primaryGradient,
                            border: Border.all(color: AppColors.border, width: 2),
                            image: _userProfile?.profileImage != null && _userProfile!.profileImage!.startsWith('data:image')
                                ? DecorationImage(
                                    image: MemoryImage(base64Decode(_userProfile!.profileImage!.split(',')[1])),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: _userProfile?.profileImage == null || !_userProfile!.profileImage!.startsWith('data:image')
                              ? const Icon(Icons.person, size: 32, color: AppColors.textPrimary)
                              : null,
                        ),
                        const SizedBox(width: 16),
                        // Wallet Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _userProfile?.displayName ?? 'My Wallet',
                                style: AppTextStyles.h3,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _shortenAddress(_web3.currentAddress ?? ''),
                                style: AppTextStyles.mono.copyWith(color: AppColors.textSecondary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.success.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(AppRadius.sm),
                                  border: Border.all(color: AppColors.success.withValues(alpha: 0.5)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                                    const SizedBox(width: 6),
                                    Text('Sepolia Testnet', style: AppTextStyles.labelSmall.copyWith(color: AppColors.success)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Actions
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, color: AppColors.primary),
                              onPressed: () async {
                                final firebaseUser = FirebaseAuth.instance.currentUser;
                                final walletAddress = _web3.currentAddress;
                                final uid = firebaseUser?.uid ?? walletAddress?.toLowerCase();
                                
                                if (uid == null) {
                                  NotificationManager.show(context: context, title: 'Wallet Required', message: 'Please connect wallet first', type: NotificationType.warning);
                                  return;
                                }
                                
                                UserModel userToEdit = _userProfile ?? UserModel(
                                  uid: uid,
                                  fullName: 'User',
                                  email: firebaseUser?.email ?? '',
                                  walletAddress: walletAddress,
                                  createdAt: DateTime.now(),
                                  lastLogin: DateTime.now(),
                                );
                                
                                await Navigator.push(context, MaterialPageRoute(builder: (_) => EditProfilePage(user: userToEdit)));
                                _loadProfile();
                              },
                            ),

                            IconButton(
                              onPressed: _logout,
                              icon: const Icon(Icons.logout, color: AppColors.danger),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  if (_userProfile?.title?.isNotEmpty == true || 
                      _userProfile?.country?.isNotEmpty == true || 
                      _userProfile?.motto?.isNotEmpty == true || 
                      _userProfile?.bio?.isNotEmpty == true) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_userProfile?.title?.isNotEmpty == true) ...[
                            Row(
                              children: [
                                const Icon(Icons.badge_outlined, size: 16, color: AppColors.primary),
                                const SizedBox(width: 8),
                                Expanded(child: Text(_userProfile!.title!, style: AppTextStyles.labelMedium.copyWith(color: AppColors.primary))),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.sm),
                          ],
                          if (_userProfile?.country?.isNotEmpty == true) ...[
                            Row(
                              children: [
                                const Icon(Icons.public, size: 16, color: AppColors.textSecondary),
                                const SizedBox(width: 8),
                                Expanded(child: Text(_userProfile!.country!, style: AppTextStyles.bodyMedium)),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.sm),
                          ],
                          if (_userProfile?.motto?.isNotEmpty == true) ...[
                            Row(
                              children: [
                                const Icon(Icons.format_quote, size: 16, color: AppColors.accentOrange),
                                const SizedBox(width: 8),
                                Expanded(child: Text('"${_userProfile!.motto!}"', style: AppTextStyles.bodyMedium.copyWith(fontStyle: FontStyle.italic))),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.sm),
                          ],
                          if (_userProfile?.bio?.isNotEmpty == true) ...[
                            if (_userProfile?.title?.isNotEmpty == true || _userProfile?.country?.isNotEmpty == true || _userProfile?.motto?.isNotEmpty == true)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
                                child: Divider(color: AppColors.border),
                              ),
                            Text(
                              _userProfile!.bio!,
                              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: AppSpacing.lg),
                  
                  // 2. BALANCE CARD
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: AppColors.cardGradient,
                      borderRadius: BorderRadius.circular(AppRadius.xxl),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
                      boxShadow: AppShadows.glowPrimary,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Total Balance', style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary)),
                              const SizedBox(height: 8),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '${_web3.balance.toStringAsFixed(4)} ETH',
                                  style: AppTextStyles.display.copyWith(fontSize: 28),
                                  maxLines: 1,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text('~ \$${(_web3.balance * 3000).toStringAsFixed(2)} USD', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // 3. STATISTICS SECTION
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: constraints.maxWidth < 350 ? 2 : 4,
                        childAspectRatio: 1.2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        children: [
                          _buildStatBox('Created', '${myCreatedLogos.length}'),
                          _buildStatBox('Owned', '${myLogos.length}'),
                          _buildStatBox('Auctions', '${myAuctions.length}'),
                          _buildStatBox('Balance', _web3.balance.toStringAsFixed(2)),
                        ],
                      );
                    }
                  ),
                ],
              ),
            ),
          ),
        ),

        // ─── Sticky Tabs ───
        SliverAppBar(
          pinned: true,
          toolbarHeight: 0,
          backgroundColor: AppColors.background,
          elevation: 0,
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: AppColors.primary,
            indicatorWeight: 3,
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textSecondary,
            labelStyle: AppTextStyles.labelMedium,
            unselectedLabelStyle: AppTextStyles.labelMedium,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'My Creations (${myCreatedLogos.length})'),
              Tab(text: 'My Collection (${myLogos.length})'),
              const Tab(text: 'Bids'),
              Tab(text: 'Auctions (${myAuctions.length})'),
              const Tab(text: 'Wallet'),
            ],
          ),
        ),

        // ─── Tab Content ───
        SliverFillRemaining(
          child: AnimatedBuilder(
            animation: _tabController,
            builder: (context, _) {
              return IndexedStack(
                index: _tabController.index,
                children: [
                  _LazyIndexedTab(isActive: _tabController.index == 0, builder: () => _buildMyCreationsTab(myCreatedLogos)),
                  _LazyIndexedTab(isActive: _tabController.index == 1, builder: () => _buildMyCollectionTab(myLogos)),
                  _LazyIndexedTab(isActive: _tabController.index == 2, builder: () => _buildBidsTab()),
                  _LazyIndexedTab(isActive: _tabController.index == 3, builder: () => _buildAuctionsManagementTab(myAuctions)),
                  _LazyIndexedTab(isActive: _tabController.index == 4, builder: () => _buildWalletTab()),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Tab 1: My Creations — Pure Creator Portfolio ──
  Widget _buildMyCreationsTab(List<LogoNFT> initialLogos) {
    final currentWallet = _web3.currentAddress?.toLowerCase() ?? '';
    
    return StreamBuilder<QuerySnapshot>(
      stream: FirestoreService.instance.db
          .collection('nfts')
          .where('creatorWallet', isEqualTo: _web3.currentAddress)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('Error loading creations', style: AppTextStyles.bodyMedium)),
              ),
            ],
          );
        }

        List<LogoNFT> displayLogos = initialLogos;
        
        if (snapshot.hasData) {
          displayLogos = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>? ?? {};
            final creatorW = (data['creatorWallet'] as String? ?? data['creator'] as String? ?? '').toLowerCase().trim();
            final ownerW = (data['ownerWallet'] as String? ?? data['owner'] as String? ?? '').toLowerCase().trim();
            final auctionStatus = (data['auctionStatus'] as String? ?? '').toUpperCase().trim();
            
            debugPrint('[MY CREATIONS DEBUG] TokenID: ${data['tokenId']} | creatorWallet: $creatorW | ownerWallet: $ownerW | currentWallet: $currentWallet | auctionStatus: $auctionStatus');
            
            return creatorW == currentWallet && ownerW == currentWallet;
          }).map((doc) {
            final data = doc.data() as Map<String, dynamic>? ?? {};
            return LogoNFT.fromFirestore(data);
          }).toList();
        }

        return CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(left: AppSpacing.lg, right: AppSpacing.lg, top: AppSpacing.xl, bottom: AppSpacing.sm),
                child: Row(
                  children: [
                    Icon(Icons.brush, color: AppColors.primary, size: 20),
                    SizedBox(width: 8),
                    Text('Creator Portfolio', style: AppTextStyles.h3),
                  ],
                ),
              ),
            ),
            _buildLogoSliverGrid(displayLogos, 'You haven\'t created any NFTs yet'),
            const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
          ],
        );
      }
    );
  }

  // ── Tab 2: My Collection — STRICT Ownership (Blockchain-Verified Only) ──
  Widget _buildMyCollectionTab(List<LogoNFT> myLogos) {
    final currentWallet = _web3.currentAddress?.toLowerCase() ?? '';
    if (currentWallet.isEmpty) {
      return CustomScrollView(
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: _buildEmptyState(Icons.account_balance_wallet, 'Connect wallet to view collection'),
              ),
            ),
          ),
        ],
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirestoreService.instance.db
          .collection('nfts')
          .where('ownerWallet', isEqualTo: _web3.currentAddress)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primary));
        }

        if (snapshot.hasError) {
          return CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('Error loading collection', style: AppTextStyles.bodyMedium)),
              ),
            ],
          );
        }

        // ═══ STRICT OWNERSHIP FILTER ═══
        // Only show NFTs where ownership is VERIFIED:
        // - auctionStatus is PAYMENT_COMPLETED, sold, or normal (no pending auction)
        // - NEVER show PAYMENT_PENDING or PAYMENT_EXPIRED
        final verifiedLogos = (snapshot.data?.docs ?? []).where((doc) {
          final data = doc.data() as Map<String, dynamic>? ?? {};
          final auctionStatus = (data['auctionStatus'] as String? ?? '').toUpperCase().trim();
          final ownerW = (data['ownerWallet'] as String? ?? data['owner'] as String? ?? '').toLowerCase().trim();
          final paymentStatus = (data['paymentStatus'] as String? ?? '').toUpperCase().trim();

          debugPrint('[MY COLLECTION DEBUG] TokenID: ${data['tokenId']} | ownerWallet: $ownerW | currentWallet: $currentWallet | auctionStatus: $auctionStatus | paymentStatus: $paymentStatus');

          return ownerW == currentWallet && (
            auctionStatus == 'COMPLETED' ||
            auctionStatus == 'PAYMENT_COMPLETED' ||
            (data['status'] as String? ?? '').toLowerCase().trim() == 'sold'
          );
        }).map((doc) {
          final data = doc.data() as Map<String, dynamic>? ?? {};
          return LogoNFT.fromFirestore(data);
        }).toList();

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(left: AppSpacing.lg, right: AppSpacing.lg, top: AppSpacing.xl, bottom: AppSpacing.sm),
                child: Row(
                  children: [
                    const Icon(Icons.collections_bookmark, color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    Text('Owned NFTs (${verifiedLogos.length})', style: AppTextStyles.h3),
                  ],
                ),
              ),
            ),
            _buildCollectionSliverGrid(verifiedLogos, 'No NFTs owned yet'),
            const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
          ],
        );
      },
    );
  }

  Widget _buildLogoSliverGrid(List<LogoNFT> logos, String emptyText) {
    if (logos.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: _buildEmptyState(Icons.image_outlined, emptyText),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 240,
          mainAxisExtent: 430, // Increased to accommodate the warning card
          crossAxisSpacing: AppSpacing.lg,
          mainAxisSpacing: AppSpacing.lg,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final logo = logos[index];
            return Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      GestureDetector(
                        onLongPress: () => _showLongPressMenu(logo, isMyCreations: true),
                        child: LogoCard(
                          logo: logo,
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => DetailLogoPage(tokenId: logo.tokenId)));
                          },
                        ),
                      ),
                      if (logo.status == ValidationStatus.rejected)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.background.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(AppRadius.xxl),
                            ),
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.danger,
                                  borderRadius: BorderRadius.circular(AppRadius.sm),
                                ),
                                child: const Text('REJECTED', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 12)),
                              ),
                            ),
                          ),
                        )
                      else if (logo.isAppealed)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.background.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(AppRadius.xxl),
                            ),
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(AppRadius.sm),
                                ),
                                child: const Text('APPEAL SUBMITTED', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.0, fontSize: 10), textAlign: TextAlign.center,),
                              ),
                            ),
                          ),
                        )
                      else if (logo.isFrozen)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.background.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(AppRadius.xxl),
                            ),
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.accentOrange,
                                  borderRadius: BorderRadius.circular(AppRadius.sm),
                                ),
                                child: const Text('UNDER INVESTIGATION', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.0, fontSize: 10), textAlign: TextAlign.center,),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (logo.isFrozen)
                  FutureBuilder<Map<String, dynamic>?>(
                    future: FirestoreService.instance.getLatestReportForToken(logo.tokenId),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData || snapshot.data == null) return const SizedBox.shrink();
                      final report = snapshot.data!;
                      return Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.accentOrange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(color: AppColors.accentOrange.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.warning, size: 12, color: AppColors.accentOrange),
                                const SizedBox(width: 4),
                                Text('INVESTIGATION', style: AppTextStyles.caption.copyWith(color: AppColors.accentOrange, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              report['reason'] ?? 'A marketplace report is being investigated.',
                              style: AppTextStyles.caption.copyWith(color: AppColors.textPrimary),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      );
                    }
                  ),
              ],
            );
          },
          childCount: logos.length,
        ),
      ),
    );
  }

  // ── My Collection Grid with Exclusive Download ──
  Widget _buildCollectionSliverGrid(List<LogoNFT> logos, String emptyText) {
    if (logos.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: _buildEmptyState(Icons.collections_bookmark_outlined, emptyText),
          ),
        ),
      );
    }

    final currentWallet = _web3.currentAddress?.toLowerCase() ?? '';

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 240,
          mainAxisExtent: 420,
          crossAxisSpacing: AppSpacing.lg,
          mainAxisSpacing: AppSpacing.lg,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final logo = logos[index];
            final bool isVerifiedOwner = currentWallet == logo.ownerWallet.toLowerCase();
            final bool canDownload = isVerifiedOwner && !logo.isFrozen && !logo.isAuctionActive;

            return Column(
              children: [
                // NFT Card
                Expanded(
                  child: GestureDetector(
                    onLongPress: () => _showLongPressMenu(logo, isMyCreations: false),
                    child: LogoCard(
                      logo: logo,
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => DetailLogoPage(tokenId: logo.tokenId, openedFromMyCollection: true)));
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Exclusive Owner Download Button
                if (canDownload)
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary.withValues(alpha: 0.15),
                          AppColors.secondary.withValues(alpha: 0.10),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _isDownloading ? null : () => _downloadImage(logo.imageUrl, logo.name),
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _isDownloading ? Icons.hourglass_top : Icons.download_rounded,
                                size: 16,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  _isDownloading ? 'Downloading...' : 'Download Original',
                                  style: AppTextStyles.labelSmall.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_outline, size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            logo.isFrozen ? 'Frozen' : (logo.isAuctionActive ? 'In Auction' : 'Owner Only'),
                            style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
          childCount: logos.length,
        ),
      ),
    );
  }

  // ── Tab 3: Bids — Participation Tracking ──
  Widget _buildBidsTab() {
    final currentWallet = _web3.currentAddress?.toLowerCase() ?? '';
    if (currentWallet.isEmpty) {
      return CustomScrollView(
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: _buildEmptyState(Icons.account_balance_wallet, 'Please connect your wallet to view bids'),
              ),
            ),
          ),
        ],
      );
    }

    return StreamBuilder<Map<int, Map<String, dynamic>>>(
      stream: FirestoreService.instance.getUserParticipatedBidsStream(currentWallet),
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

        final bidsMap = snapshot.data ?? {};
        if (bidsMap.isEmpty) {
          return CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xxl),
                    child: _buildEmptyState(Icons.gavel, 'You haven\'t placed any bids yet'),
                  ),
                ),
              ),
            ],
          );
        }

        // Sort bids by timestamp
        final sortedEntries = bidsMap.entries.toList()
          ..sort((a, b) {
            final tA = a.value['timestamp'];
            final tB = b.value['timestamp'];
            if (tA == null || tB == null) return 0;
            return tB.compareTo(tA);
          });

        return CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(left: AppSpacing.lg, right: AppSpacing.lg, top: AppSpacing.xl, bottom: AppSpacing.sm),
                child: Row(
                  children: [
                    Icon(Icons.gavel, color: AppColors.primary, size: 20),
                    SizedBox(width: 8),
                    Text('Bidding Activity', style: AppTextStyles.h3),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final entry = sortedEntries[index];
                    final tokenId = entry.key;
                    final bidData = entry.value;
                    final myBidAmount = (bidData['amount'] as num).toDouble();

                    return StreamBuilder<DocumentSnapshot>(
                      stream: FirestoreService.instance.db.collection('nfts').doc(tokenId.toString()).snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                          return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator(color: AppColors.primary)));
                        }
                        
                        if (!snapshot.hasData || !snapshot.data!.exists) {
                          return const SizedBox.shrink();
                        }

                        final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
                        final logo = LogoNFT.fromFirestore(data);

                        // Check if it's already paid / completed
                        final auctionStatus = (data['auctionStatus'] as String? ?? '').toUpperCase().trim();
                        final ownerW = (data['ownerWallet'] as String? ?? '').toLowerCase();
                        
                        final isCompleted = auctionStatus == 'COMPLETED' || auctionStatus == 'PAYMENT_COMPLETED' || ownerW == currentWallet;

                        // Filter: If paid, auto-remove from Bids tab
                        if (isCompleted) {
                          return const SizedBox.shrink();
                        }

                        final auction = _web3.getAuctionForLogo(logo.tokenId);
                        
                        return _buildBidCard(logo, auction, myBidAmount, currentWallet);
                      },
                    );
                  },
                  childCount: sortedEntries.length,
                ),
              ),
            ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
          ],
        );
      },
    );
  }

  Widget _buildBidCard(LogoNFT logo, Auction? auction, double myBidAmount, String currentWallet) {
    // Determine status
    String statusText = 'UNKNOWN';
    Color statusColor = AppColors.textSecondary;
    IconData statusIcon = Icons.help_outline;
    
    final bool isLive = logo.isAuctionActive && logo.endTime != null && DateTime.now().isBefore(logo.endTime!);
    final highestBidder = logo.highestBidderWallet?.toLowerCase() ?? '';
    final isHighestBidder = highestBidder == currentWallet;
    final bool hasWinner = highestBidder.isNotEmpty;
    
    // Status Logic
    if (logo.status == ValidationStatus.rejected || logo.isFrozen || auction?.status == AuctionStatus.cancelled) {
      statusText = 'CANCELLED';
      statusColor = AppColors.danger;
      statusIcon = Icons.cancel;
    } else if (isLive) {
      if (isHighestBidder) {
        statusText = 'WINNING';
        statusColor = AppColors.success;
        statusIcon = Icons.emoji_events;
      } else {
        statusText = 'OUTBID';
        statusColor = AppColors.accentOrange;
        statusIcon = Icons.trending_down;
      }
    } else {
      // Auction Ended
      if (hasWinner && isHighestBidder) {
        if (auction?.status == AuctionStatus.paymentPending) {
          statusText = 'WON - PAYMENT REQUIRED';
          statusColor = AppColors.accentOrange;
          statusIcon = Icons.payment;
        } else if (auction?.status == AuctionStatus.claimed || logo.ownerWallet.toLowerCase() == currentWallet) {
          statusText = 'PAID / CLAIMED';
          statusColor = AppColors.primary;
          statusIcon = Icons.check_circle;
        } else {
          statusText = 'WON - PAYMENT REQUIRED';
          statusColor = AppColors.accentOrange;
          statusIcon = Icons.payment;
        }
      } else if (hasWinner && !isHighestBidder) {
        statusText = 'LOST';
        statusColor = AppColors.textSecondary;
        statusIcon = Icons.close;
      } else if (!hasWinner) {
        statusText = 'ENDED (NO BIDS)';
        statusColor = AppColors.textSecondary;
        statusIcon = Icons.timer_off;
      }
    }

    String displayImageUrl = logo.imageUrl;
    if (displayImageUrl.contains('dweb.link/ipfs/')) {
       displayImageUrl = displayImageUrl.replaceAll('dweb.link/ipfs/', 'ipfs.io/ipfs/');
    } else if (displayImageUrl.contains('ipfs://')) {
       displayImageUrl = displayImageUrl.replaceAll('ipfs://', 'https://ipfs.io/ipfs/');
    }

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DetailLogoPage(tokenId: logo.tokenId))),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: statusColor.withValues(alpha: 0.05),
              blurRadius: 10,
              spreadRadius: 1,
            )
          ],
        ),
        child: Column(
          children: [
            // Top Section: Image + Info
            Row(
              children: [
                // Image
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: AppColors.border),
                    color: AppColors.surfaceLight,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    child: displayImageUrl.isNotEmpty
                      ? (displayImageUrl.startsWith('data:image') 
                          ? Image.memory(base64Decode(displayImageUrl.split(',').last), fit: BoxFit.cover) 
                          : CachedNetworkImage(
                              imageUrl: displayImageUrl,
                              fit: BoxFit.cover,
                              errorWidget: (context, url, error) => const Icon(Icons.image_outlined, color: AppColors.textSecondary),
                            ))
                      : const Icon(Icons.image_outlined, color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
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
                              logo.name,
                              style: AppTextStyles.h3.copyWith(fontSize: 16),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                              border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(statusIcon, size: 12, color: statusColor),
                                const SizedBox(width: 4),
                                Text(
                                  statusText,
                                  style: AppTextStyles.labelSmall.copyWith(color: statusColor, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('Token #${logo.tokenId}', style: AppTextStyles.caption),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Your Bid', style: AppTextStyles.caption),
                                Text('${myBidAmount.toStringAsFixed(4)} ETH', style: AppTextStyles.labelMedium),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('Current Highest', style: AppTextStyles.caption),
                                Text('${logo.highestBid > 0 ? logo.highestBid.toStringAsFixed(4) : logo.price.toStringAsFixed(4)} ETH', style: AppTextStyles.labelMedium.copyWith(color: AppColors.primary)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Bottom Section: Actions
            if (statusText == 'WON - PAYMENT REQUIRED') ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Divider(color: AppColors.border),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.accentOrange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.accentOrange.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    Text(
                      'Congratulations! You won this auction.',
                      style: AppTextStyles.labelMedium.copyWith(color: AppColors.accentOrange),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Complete your Sepolia payment to claim ownership.',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.accentOrange),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      width: double.infinity,
                      // Prevent tap from bubbling up to the card's GestureDetector
                      child: GestureDetector(
                        onTap: () {},
                        child: ElevatedButton.icon(
                          onPressed: () {
                            debugPrint('[PAYMENT FLOW] Opening AuctionPaymentPage');
                            debugPrint('[PAYMENT FLOW] Current auction status: ${auction?.status}');
                            debugPrint('[PAYMENT FLOW] Highest bidder: ${auction?.highestBidderWallet}');
                            debugPrint('[PAYMENT FLOW] Current wallet: $currentWallet');
                            
                            // Force route to AuctionPaymentPage
                            Navigator.push(context, MaterialPageRoute(builder: (_) => AuctionPaymentPage(tokenId: logo.tokenId)));
                          },
                          icon: const Icon(Icons.payment, size: 16),
                          label: const Text('Complete Payment'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accentOrange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (statusText == 'PAID / CLAIMED') ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Divider(color: AppColors.border),
              ),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    // Navigate to collection or detail
                    Navigator.push(context, MaterialPageRoute(builder: (_) => DetailLogoPage(tokenId: logo.tokenId, openedFromMyCollection: true)));
                  },
                  icon: const Icon(Icons.collections_bookmark, size: 16, color: AppColors.primary),
                  label: Text('View in Collection', style: AppTextStyles.labelMedium.copyWith(color: AppColors.primary)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Download Image (Owner Exclusive) ──
  Future<void> _downloadImage(String imageUrl, String name) async {
    // Real-time ownership validation
    final currentWallet = _web3.currentAddress?.toLowerCase();
    if (currentWallet == null) {
      if (mounted) {
        NotificationManager.show(context: context, title: 'Wallet Not Connected', message: 'Wallet not connected', type: NotificationType.error);
      }
      return;
    }

    setState(() => _isDownloading = true);
    try {
      // Backend ownership validation
      final isOwner = await FirestoreService.instance.verifyNFTOwnership(
        imageUrl,
        currentWallet,
      );
      if (!isOwner) {
        throw Exception('Ownership verification failed. You are not the verified owner of this NFT.');
      }

      Uint8List bytes;
      if (imageUrl.startsWith('http')) {
        var response = await Dio().get(
          imageUrl,
          options: Options(responseType: ResponseType.bytes),
        );
        bytes = Uint8List.fromList(response.data);
      } else if (imageUrl.startsWith('data:image')) {
        final base64String = imageUrl.split(',').last;
        bytes = base64Decode(base64String);
      } else {
        bytes = base64Decode(imageUrl);
      }

      await Gal.putImageBytes(bytes);

      if (!mounted) return;
      NotificationManager.show(
        context: context,
        title: 'Download Successful',
        message: 'Original logo saved to gallery!',
        type: NotificationType.success,
      );
    } catch (e) {
      if (!mounted) return;
      NotificationManager.show(
        context: context,
        title: 'Download Failed',
        message: e.toString().replaceFirst("Exception: ", ""),
        type: NotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  void _showLongPressMenu(LogoNFT logo, {required bool isMyCreations}) {
    final currentWallet = _web3.currentAddress?.toLowerCase() ?? '';
    final isCreator = logo.creatorWallet.toLowerCase() == currentWallet;
    final isOwner = logo.ownerWallet.toLowerCase() == currentWallet;

    final canDelete = isMyCreations &&
        isCreator &&
        logo.status != ValidationStatus.rejected &&
        !logo.isAuctionActive &&
        !logo.isFrozen &&
        logo.auctionStatus != 'PAYMENT_PENDING' &&
        logo.previousWinnerWallet == null;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.xl),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 8, bottom: AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.sm),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: CachedNetworkImage(
                        imageUrl: logo.imageUrl,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) => const Icon(Icons.image, color: AppColors.textSecondary),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(logo.name.isNotEmpty ? logo.name : 'Token #${logo.tokenId}', style: AppTextStyles.h3, maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(isMyCreations ? 'My Creation' : 'My Collection', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: AppColors.border, height: 24),
              // Share Action
              ListTile(
                leading: const Icon(Icons.share, color: AppColors.primary),
                title: const Text('Share NFT', style: AppTextStyles.bodyLarge),
                onTap: () {
                  Navigator.pop(context);
                  SharePlus.instance.share(ShareParams(text: 'Check out this amazing NFT Logo "${logo.name}" on the LEO Marketplace! Token ID: #${logo.tokenId}\n\nImage: ${logo.imageUrl}'));
                },
              ),
              // Download Action (Only if authorized)
              if (isOwner)
                ListTile(
                  leading: const Icon(Icons.download_rounded, color: AppColors.success),
                  title: const Text('Download Logo to Gallery', style: AppTextStyles.bodyLarge),
                  onTap: () {
                    Navigator.pop(context);
                    _downloadImage(logo.imageUrl, logo.name);
                  },
                ),
              // Delete Action
              if (canDelete)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: AppColors.danger),
                  title: Text('Delete NFT', style: AppTextStyles.bodyLarge.copyWith(color: AppColors.danger)),
                  onTap: () {
                    Navigator.pop(context);
                    _showDeleteConfirmationDialog(logo);
                  },
                ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        );
      },
    );
  }

  void _showDeleteConfirmationDialog(LogoNFT logo) {
    showDialog(
      context: context,
      builder: (context) {
        bool isDeleting = false;
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
              title: const Text('Delete NFT?', style: AppTextStyles.h2),
              content: const Text(
                'Deleting this NFT removes it from your portfolio and marketplace. This action cannot be fully undone.',
                style: AppTextStyles.bodyMedium,
              ),
              actions: [
                TextButton(
                  onPressed: isDeleting ? null : () => Navigator.pop(context),
                  child: Text('Cancel', style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary)),
                ),
                ElevatedButton(
                  onPressed: isDeleting ? null : () async {
                    setStateDialog(() => isDeleting = true);
                    try {
                      final currentWallet = _web3.currentAddress ?? '';
                      await FirestoreService.instance.softDeleteNFT(logo.tokenId, currentWallet);
                      if (context.mounted) {
                        Navigator.pop(context);
                        NotificationManager.show(
                          context: context,
                          title: 'Success',
                          message: 'NFT deleted successfully',
                          type: NotificationType.success,
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        setStateDialog(() => isDeleting = false);
                        NotificationManager.show(
                          context: context,
                          title: 'Error',
                          message: e.toString().replaceFirst("Exception: ", ""),
                          type: NotificationType.error,
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
                  child: isDeleting 
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Delete', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          }
        );
      },
    );
  }

  Widget _buildStatBox(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(value, style: AppTextStyles.h3, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  // ── Tab 2: My Auctions ──
  // ── Tab 3: Auctions Management Center ──
  Widget _buildAuctionsManagementTab(List<Auction> allAuctions) {
    if (allAuctions.isEmpty) {
      return _buildEmptyState(Icons.gavel_outlined, 'No auctions yet');
    }

    // Filter auctions based on selected filter
    final List<Auction> filtered;
    switch (_auctionFilter) {
      case 1: filtered = allAuctions.where((a) => a.isOngoing).toList(); break;
      case 2: filtered = allAuctions.where((a) => a.status == AuctionStatus.ended || a.status == AuctionStatus.endedNoBids || a.status == AuctionStatus.failedPayment || a.status == AuctionStatus.paymentExpired).toList(); break;
      case 3: filtered = allAuctions.where((a) => a.status == AuctionStatus.paymentPending || a.status == AuctionStatus.claimed).toList(); break;
      case 4: filtered = allAuctions.where((a) => a.status == AuctionStatus.frozen || a.status == AuctionStatus.cancelled).toList(); break;
      case 5:
        filtered = allAuctions.where((a) {
          LogoNFT? logo;
          try { logo = _web3.allLogos.firstWhere((l) => l.tokenId == a.tokenId); } catch (_) {}
          return logo?.status == ValidationStatus.rejected;
        }).toList();
        break;
      default: filtered = allAuctions;
    }

    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(left: AppSpacing.lg, right: AppSpacing.lg, top: AppSpacing.xl, bottom: AppSpacing.sm),
            child: Text('Live Auction Monitoring', style: AppTextStyles.h3),
          ),
        ),
        const LiveAuctionMonitoring(),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _buildFilterChip('All', 0, Icons.list_alt),
                const SizedBox(width: 8),
                _buildFilterChip('Live', 1, Icons.play_circle_outline),
                const SizedBox(width: 8),
                _buildFilterChip('Ended', 2, Icons.timer_off_outlined),
                const SizedBox(width: 8),
                _buildFilterChip('Payment', 3, Icons.payment),
                const SizedBox(width: 8),
                _buildFilterChip('Frozen', 4, Icons.ac_unit),
                const SizedBox(width: 8),
                _buildFilterChip('Rejected', 5, Icons.block),
              ]),
            ),
          ),
        ),
        if (filtered.isEmpty)
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(AppSpacing.xxl), child: _buildEmptyState(Icons.filter_alt_outlined, 'No auctions in this category')))
        else
          SliverList(delegate: SliverChildBuilderDelegate((context, index) {
            final auction = filtered[index];
            LogoNFT? logo;
            try { logo = _web3.allLogos.firstWhere((l) => l.tokenId == auction.tokenId); } catch (_) {}

            String statusText; Color statusColor; IconData statusIcon;
            if (auction.isOngoing) {
              statusText = auction.timeRemainingFormatted; statusColor = AppColors.primary; statusIcon = Icons.timer_outlined;
            } else {
              switch (auction.status) {
                case AuctionStatus.paymentPending: statusText = 'Payment Pending'; statusColor = AppColors.accentOrange; statusIcon = Icons.payment; break;
                case AuctionStatus.claimed: statusText = 'Claimed'; statusColor = AppColors.success; statusIcon = Icons.check_circle_outline; break;
                case AuctionStatus.failedPayment: statusText = 'Payment Failed'; statusColor = AppColors.danger; statusIcon = Icons.error_outline; break;
                case AuctionStatus.paymentExpired: statusText = 'Payment Expired'; statusColor = AppColors.danger; statusIcon = Icons.error_outline; break;
                case AuctionStatus.frozen: statusText = 'Frozen'; statusColor = AppColors.frozenBlue; statusIcon = Icons.ac_unit; break;
                case AuctionStatus.cancelled: statusText = 'Cancelled'; statusColor = AppColors.textSecondary; statusIcon = Icons.cancel_outlined; break;
                case AuctionStatus.endedNoBids: statusText = 'No Bids'; statusColor = AppColors.danger; statusIcon = Icons.not_interested; break;
                default:
                  if (auction.totalBids == 0) { statusText = 'No Bids'; statusColor = AppColors.danger; statusIcon = Icons.not_interested; }
                  else { statusText = 'Ended'; statusColor = AppColors.textSecondary; statusIcon = Icons.timer_off_outlined; }
              }
            }

            final bool canReAuction = !auction.isOngoing && logo != null && !logo.isFrozen &&
                logo.status != ValidationStatus.rejected &&
                (auction.status == AuctionStatus.ended || auction.status == AuctionStatus.endedNoBids || auction.status == AuctionStatus.failedPayment || auction.status == AuctionStatus.paymentExpired || logo.auctionStatus == 'ENDED_NO_BID') &&
                (logo.highestBidderWallet == null || logo.highestBidderWallet!.isEmpty || auction.status == AuctionStatus.failedPayment || auction.status == AuctionStatus.paymentExpired);

            return Container(
              margin: const EdgeInsets.only(left: AppSpacing.lg, right: AppSpacing.lg, bottom: AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.xl),
                border: Border.all(color: auction.isOngoing ? AppColors.primary.withValues(alpha: 0.3) : AppColors.border),
                boxShadow: auction.isOngoing ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.05), blurRadius: 10, spreadRadius: 1)] : null,
              ),
              child: InkWell(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AuctionPage(tokenId: auction.tokenId))),
                borderRadius: BorderRadius.circular(AppRadius.xl),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(children: [
                    Row(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        child: SizedBox(width: 80, height: 80,
                          child: logo != null && logo.imageUrl.isNotEmpty
                            ? CachedNetworkImage(imageUrl: logo.imageUrl, fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(color: AppColors.surfaceLight, child: const Icon(Icons.image_outlined, color: AppColors.textSecondary)), placeholder: (_, __) => Container(color: AppColors.surfaceLight, child: const CustomLoadingIndicator(size: 20)))
                            : Container(color: AppColors.surfaceLight, child: const Icon(Icons.image_outlined, color: AppColors.textSecondary)),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(logo?.name ?? 'Token #${auction.tokenId}', style: AppTextStyles.h3, maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 8),
                        Row(children: [
                          Icon(statusIcon, size: 16, color: statusColor),
                          const SizedBox(width: 6),
                          Flexible(child: Text(statusText, style: AppTextStyles.labelMedium.copyWith(color: statusColor), overflow: TextOverflow.ellipsis)),
                        ]),
                        Builder(builder: (_) {
                          final reAuctionCount = logo?.auctionCount ?? 0;
                          if (reAuctionCount > 0) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text('Re-Auctioned ${reAuctionCount}x', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                            );
                          }
                          return const SizedBox.shrink();
                        }),
                      ])),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('${(auction.highestBid > 0 ? auction.highestBid : auction.startingPrice).toStringAsFixed(4)} ETH', style: AppTextStyles.h3),
                        if (auction.totalBids > 0) ...[const SizedBox(height: 4), Text('${auction.totalBids} bids', style: AppTextStyles.bodySmall)],
                      ]),
                      const SizedBox(width: AppSpacing.sm),
                      const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                    ]),
                    if (canReAuction) ...[
                      const SizedBox(height: AppSpacing.md),
                      const Divider(color: AppColors.border),
                      const SizedBox(height: AppSpacing.sm),
                      SizedBox(width: double.infinity, child: OutlinedButton.icon(
                        onPressed: () {
                          _showReAuctionBottomSheet(context, auction, logo!);
                        },
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Request Re-Auction'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                        ),
                      )),
                    ],
                  ]),
                ),
              ),
            );
          }, childCount: filtered.length)),
        const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
      ],
    );
  }

  Widget _buildFilterChip(String label, int value, IconData icon) {
    final bool isSelected = _auctionFilter == value;
    return FilterChip(
      label: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: isSelected ? AppColors.background : AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(label),
      ]),
      selected: isSelected,
      onSelected: (_) => setState(() => _auctionFilter = value),
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.surface,
      checkmarkColor: AppColors.background,
      labelStyle: TextStyle(color: isSelected ? AppColors.background : AppColors.textSecondary, fontSize: 13),
      side: BorderSide(color: isSelected ? AppColors.primary : AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
    );
  }

  // ── Tab 5: Wallet Info ──
  Widget _buildWalletTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: AppSpacing.lg, right: AppSpacing.lg, top: AppSpacing.lg, bottom: 40),
      child: Column(
        children: [
          GlassCard(
            child: Column(
              children: [
                _buildInfoRow('Wallet Address', _web3.currentAddress ?? 'Not connected', Icons.account_balance_wallet_outlined, AppColors.primary),
                const Divider(color: AppColors.border, height: 32),
                _buildInfoRow('Balance', '${_web3.balance.toStringAsFixed(4)} ETH', Icons.monetization_on_outlined, AppColors.success),
                const Divider(color: AppColors.border, height: 32),
                _buildInfoRow('Network', _web3.isOnSepolia ? 'Sepolia Testnet' : 'Unknown', Icons.language, AppColors.frozenBlue),
                const Divider(color: AppColors.border, height: 32),
                _buildInfoRow('Connection', _web3.connectionType, Icons.link_outlined, AppColors.accentOrange),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          PrimaryButton(
            text: 'Logout & Disconnect',
            icon: Icons.logout,
            backgroundColor: AppColors.danger,
            onPressed: _logout,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 4),
              Text(value, style: AppTextStyles.bodyLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(IconData icon, String text, {String? ctaText, VoidCallback? onCtaPressed}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(icon, size: 48, color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(text, style: AppTextStyles.labelLarge.copyWith(color: AppColors.textSecondary)),
          if (ctaText != null && onCtaPressed != null) ...[
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              text: ctaText,
              onPressed: onCtaPressed,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConnectPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: AppColors.accentOrange.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.accentOrange.withValues(alpha: 0.3)),
              ),
              child: const Icon(Icons.account_balance_wallet_outlined, size: 64, color: AppColors.accentOrange),
            ),
            const SizedBox(height: AppSpacing.xxl),
            const Text('Wallet Not Connected', style: AppTextStyles.h2),
            const SizedBox(height: AppSpacing.sm),
            Text('Connect your wallet to view your profile and manage your NFTs.', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary), textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.xxl),
            PrimaryButton(
              text: 'Connect Wallet',
              icon: Icons.link,
              backgroundColor: AppColors.accentOrange,
              onPressed: () async {
                try {
                  await WalletUtils.showConnectDialog(context, _web3);
                } catch (e) {
                  if (!mounted) return;
                  NotificationManager.show(context: context, title: 'Error', message: e.toString().replaceFirst("Exception: ", ""), type: NotificationType.error);
                }
              },
            ),
          ],
        ),
      ),
    );
  }



  void _showReAuctionBottomSheet(BuildContext context, Auction auction, LogoNFT logo) {
    final TextEditingController priceController = TextEditingController(text: auction.startingPrice.toString());
    final TextEditingController notesController = TextEditingController();
    int selectedDuration = 86400; // default 24h

    final List<Map<String, dynamic>> durationOptions = [
      {'label': '30 Seconds (Demo)', 'value': 30},
      {'label': '1 Minute (Demo)', 'value': 60},
      {'label': '5 Minutes (Demo)', 'value': 300},
      {'label': '1 Hour', 'value': 3600},
      {'label': '24 Hours', 'value': 86400},
      {'label': '3 Days', 'value': 259200},
      {'label': '7 Days', 'value': 604800},
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext bottomSheetContext) {
        bool isSubmitting = false;

        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              padding: EdgeInsets.only(
                top: AppSpacing.xl,
                left: AppSpacing.xl,
                right: AppSpacing.xl,
                bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
              ),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
                border: Border.all(color: AppColors.border),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle Bar
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: AppSpacing.xl),
                        decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    
                    Text('Request Re-Auction', style: AppTextStyles.h2),
                    const SizedBox(height: AppSpacing.lg),

                    // NFT Preview Header
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            child: CachedNetworkImage(
                              imageUrl: logo.imageUrl,
                              width: 60,
                              height: 60,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Container(
                                width: 60, height: 60, color: AppColors.surfaceLight,
                                child: const Icon(Icons.image, color: AppColors.textSecondary),
                              ),
                              placeholder: (_, __) => Container(
                                width: 60, height: 60, color: AppColors.surfaceLight,
                                child: const CustomLoadingIndicator(size: 20),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(logo.name.isNotEmpty ? logo.name : 'Token #${logo.tokenId}', style: AppTextStyles.h3),
                                const SizedBox(height: 4),
                                Text(
                                  'Prev Highest Bid: ${(auction.highestBid > 0 ? auction.highestBid : 0).toStringAsFixed(4)} ETH',
                                  style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    // Form Fields
                    Text('New Starting Price (ETH)', style: AppTextStyles.labelMedium),
                    const SizedBox(height: AppSpacing.sm),
                    TextFormField(
                      controller: priceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide.none),
                        hintText: '0.00',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    Text('Auction Duration', style: AppTextStyles.labelMedium),
                    const SizedBox(height: AppSpacing.sm),
                    DropdownButtonFormField<int>(
                      initialValue: selectedDuration,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide.none),
                      ),
                      dropdownColor: AppColors.surface,
                      items: durationOptions.map((opt) {
                        return DropdownMenuItem<int>(
                          value: opt['value'] as int,
                          child: Text(opt['label'] as String, style: AppTextStyles.bodyMedium),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setModalState(() => selectedDuration = val);
                      },
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    Text('Creator Notes (Optional)', style: AppTextStyles.labelMedium),
                    const SizedBox(height: AppSpacing.sm),
                    TextFormField(
                      controller: notesController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide.none),
                        hintText: 'e.g. Relisting after payment failed.',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    // Marketplace Warning Box
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.accentOrange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border: Border.all(color: AppColors.accentOrange.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: AppColors.accentOrange),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Text(
                              'This NFT will return to Admin Review before becoming publicly visible again.',
                              style: AppTextStyles.bodySmall.copyWith(color: AppColors.accentOrange),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      child: PrimaryButton(
                        text: 'Submit Re-Auction Request',
                        isLoading: isSubmitting,
                        onPressed: isSubmitting ? null : () async {
                          final priceStr = priceController.text.trim();
                          if (priceStr.isEmpty) {
                            NotificationManager.show(context: context, title: 'Invalid Input', message: 'Please enter a starting price', type: NotificationType.warning);
                            return;
                          }
                          final price = double.tryParse(priceStr);
                          if (price == null || price <= 0) {
                            NotificationManager.show(context: context, title: 'Invalid Input', message: 'Invalid price', type: NotificationType.warning);
                            return;
                          }

                          setModalState(() => isSubmitting = true);
                          try {
                            await FirestoreService.instance.requestReAuctionWithSettings(
                              auction.tokenId,
                              selectedDuration,
                              price,
                              notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
                            );
                            if (bottomSheetContext.mounted) {
                              Navigator.pop(bottomSheetContext);
                              NotificationManager.show(
                                context: context,
                                title: 'Success',
                                message: 'Re-auction request submitted successfully!',
                                type: NotificationType.success,
                              );
                              setState(() {}); // Refresh Auctions tab
                            }
                          } catch (e) {
                            if (bottomSheetContext.mounted) {
                              setModalState(() => isSubmitting = false);
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
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _shortenAddress(String address) {
    if (address.length <= 10) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
  }


}

class _LazyIndexedTab extends StatefulWidget {
  final Widget Function() builder;
  final bool isActive;

  const _LazyIndexedTab({required this.builder, required this.isActive});

  @override
  State<_LazyIndexedTab> createState() => _LazyIndexedTabState();
}

class _LazyIndexedTabState extends State<_LazyIndexedTab> {
  bool _hasInitialized = false;

  @override
  Widget build(BuildContext context) {
    if (widget.isActive) {
      _hasInitialized = true;
    }

    if (!_hasInitialized) {
      return const SizedBox.shrink();
    }

    return widget.builder();
  }
}
