import 'dart:async';
import 'package:flutter/material.dart';

import 'package:nft_logo_marketplace/shared/models/logo_nft.dart';
import 'package:nft_logo_marketplace/shared/models/auction.dart';
import 'package:nft_logo_marketplace/core/services/web3_service.dart';
import 'package:nft_logo_marketplace/shared/widgets/logo_card.dart';
import 'package:nft_logo_marketplace/features/nft/presentation/upload_page.dart';
import 'package:nft_logo_marketplace/features/auction/presentation/auction_page.dart';
import 'package:nft_logo_marketplace/features/profile/presentation/profile_page.dart';
import 'package:nft_logo_marketplace/core/utils/wallet_utils.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/core/services/firestore_service.dart';
import 'package:nft_logo_marketplace/shared/widgets/wallet_connect_modal.dart';

import 'package:nft_logo_marketplace/core/theme/app_radius.dart';
import 'package:nft_logo_marketplace/core/theme/app_spacing.dart';
import 'package:nft_logo_marketplace/shared/widgets/empty_state_widget.dart';
import 'package:nft_logo_marketplace/shared/widgets/loading_skeleton.dart';
import 'package:nft_logo_marketplace/shared/widgets/custom_loading_indicator.dart';
import 'package:nft_logo_marketplace/core/theme/app_shadows.dart';
import 'package:nft_logo_marketplace/core/widgets/notification_bell.dart';
import 'package:nft_logo_marketplace/core/utils/notification_manager.dart';
import 'package:nft_logo_marketplace/shared/models/notification_model.dart';

import 'package:nft_logo_marketplace/core/services/api_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _web3 = Web3Service.instance;
  int _currentIndex = 0;
  String _searchQuery = '';
  String _selectedCategory = NFTCategory.all;
  final _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;
  
  int _limit = 10;
  bool _isRefreshing = false;

  List<LogoNFT> _firestoreLogosCache = [];
  List<LogoNFT> _cachedMarketplaceLogos = [];

  @override
  void initState() {
    super.initState();
    _loadNFTsFromBackend();

    _web3.addListener(_refresh);
    _searchFocusNode.addListener(_onSearchFocusChanged);
    _scrollController.addListener(_onScroll);
    FirestoreService.instance.closeExpiredAuctions();
    FirestoreService.instance.expirePaymentDeadlines();
    _loadBlockchainData();
  }

  Future<void> _loadNFTsFromBackend() async {
    try {
      final logos = await ApiService.instance.fetchAllNFTs();
      if (!mounted) return;
      
      final approvedLogos = logos.where((l) => l.status == ValidationStatus.approved).toList();
      approvedLogos.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      
      setState(() {
        _firestoreLogosCache = approvedLogos;
        _applyFilters();
      });
    } catch (e) {
      debugPrint('Error loading backend NFTs: $e');
    }
  }

  void _applyFilters() {
    if (!mounted) return;
    setState(() {
      _cachedMarketplaceLogos = _filterLogos(_firestoreLogosCache);
    });
  }

  void _onSearchFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchFocusNode.removeListener(_onSearchFocusChanged);
    _searchFocusNode.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    _web3.removeListener(_refresh);
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (_limit < 100) { 
        setState(() {
          _limit += 10;
        });
      }
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _loadBlockchainData() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      await _web3.loadFromChain();
    } catch (e) {
      debugPrint('Error loading blockchain data: $e');
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  List<LogoNFT> _filterLogos(List<LogoNFT> logos) {
    final now = DateTime.now();
    return logos.where((logo) {
      // ═══ STRICT POSITIVE FILTERING: LIVE AUCTIONS ONLY ═══
      // 1. Must be approved
      if (logo.status != ValidationStatus.approved) return false;
      
      // 2. STRICT STATUS EXCLUSION — Block ALL non-LIVE statuses
      final auctionStatus = (logo.auctionStatus ?? '').toUpperCase().trim();
      const blockedStatuses = {
        'ENDED_NO_BID', 'ENDED_NO_BIDS',
        'PAYMENT_PENDING',
        'PAYMENT_COMPLETED',
        'PAYMENT_EXPIRED',
        'RE_AUCTION_REQUESTED',
        'CANCELLED',
        'REJECTED',
        'FROZEN',
        'FAILED_PAYMENT',
        'CLAIMED',
        'SOLD',
        'ENDED',
      };
      if (blockedStatuses.contains(auctionStatus)) return false;

      // 3. Must have an active auction
      if (!logo.isAuctionActive) return false;
      // 4. Must not be frozen
      if (logo.isFrozen) return false;
      // 5. Must have endTime in the future (still live)
      if (logo.endTime == null || !logo.endTime!.isAfter(now)) return false;

      // ── Category filter ──
      if (_selectedCategory != NFTCategory.all &&
          logo.category != _selectedCategory) {
        return false;
      }
      // ── Search filter ──
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchesName = logo.name.toLowerCase().contains(query);
        final matchesDesc = logo.description.toLowerCase().contains(query);
        if (!matchesName && !matchesDesc) return false;
      }

      return true;
    }).toList();
  }

  Widget _buildNetworkBanner() {
    if (!_web3.isConnected || _web3.chainId == Web3ServiceBase.sepoliaChainId) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      color: AppColors.danger,
      child: SafeArea(
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Wrong Network Detected. Please switch your wallet to Sepolia Testnet.',
                style: AppTextStyles.labelMedium.copyWith(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = IndexedStack(
      index: _currentIndex,
      children: [
        _buildHomeContent(),
        UploadPage(
          onMintSuccess: () {
            setState(() => _currentIndex = 0);
            _loadBlockchainData();
          },
        ),
        const ProfilePage(),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 800) {
          // Desktop Layout
          return Scaffold(
            backgroundColor: AppColors.background,
            body: Column(
              children: [
                _buildNetworkBanner(),
                Expanded(
                  child: Row(
                    children: [
                      NavigationRail(
                        selectedIndex: _currentIndex,
                        onDestinationSelected: (index) async {
                          if ((index == 1 || index == 2) && !_web3.isConnected) {
                            final connected = await WalletConnectModal.show(
                              context,
                              title: 'Connect Wallet Required',
                              message: index == 1 
                                ? 'Please connect your wallet to mint and upload NFTs.' 
                                : 'Please connect your wallet to access your profile and collection.',
                            );
                            if (connected && mounted) setState(() => _currentIndex = index);
                          } else {
                            setState(() => _currentIndex = index);
                          }
                        },
                        backgroundColor: AppColors.surface,
                        indicatorColor: AppColors.primary.withValues(alpha: 0.3),
                        selectedIconTheme: const IconThemeData(color: AppColors.primary),
                        extended: constraints.maxWidth > 1000,
                        destinations: const [
                          NavigationRailDestination(
                            icon: Icon(Icons.home_outlined),
                            selectedIcon: Icon(Icons.home),
                            label: Text('Home'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.add_circle_outline),
                            selectedIcon: Icon(Icons.add_circle),
                            label: Text('Upload'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.person_outline),
                            selectedIcon: Icon(Icons.person),
                            label: Text('Profile'),
                          ),
                        ],
                      ),
                      const VerticalDivider(thickness: 1, width: 1, color: AppColors.border),
                      Expanded(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1200),
                            child: content,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        // Mobile Layout
        return Scaffold(
          backgroundColor: AppColors.background,
          body: Column(
            children: [
              _buildNetworkBanner(),
              Expanded(child: content),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) async {
              if ((index == 1 || index == 2) && !_web3.isConnected) {
                final connected = await WalletConnectModal.show(
                  context,
                  title: 'Connect Wallet Required',
                  message: index == 1 
                    ? 'Please connect your wallet to mint and upload NFTs.' 
                    : 'Please connect your wallet to access your profile and collection.',
                );
                if (connected && mounted) setState(() => _currentIndex = index);
              } else {
                setState(() => _currentIndex = index);
              }
            },
            backgroundColor: AppColors.surface,
            indicatorColor: AppColors.primary.withValues(alpha: 0.3),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home, color: AppColors.primary),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.add_circle_outline),
                selectedIcon: Icon(Icons.add_circle, color: AppColors.primary),
                label: 'Upload',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person, color: AppColors.primary),
                label: 'Profile',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHomeContent() {
    // Only take up to _limit items for lazy loading
    final filteredLogos = _cachedMarketplaceLogos.take(_limit).toList();
    final bool hasMore = _cachedMarketplaceLogos.length > _limit;
    final isLoading = _firestoreLogosCache.isEmpty && _isRefreshing; // basic loading state

    return RefreshIndicator(
      onRefresh: _loadBlockchainData,
      color: AppColors.primary,
          backgroundColor: AppColors.surface,
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              // Hero Section
              SliverToBoxAdapter(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Container(
                      decoration: const BoxDecoration(
                        gradient: AppColors.heroGradient,
                      ),
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.screenPadding),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Header Row
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Flexible(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Flexible(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text('LEO', style: AppTextStyles.h2.copyWith(letterSpacing: 2, fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis),
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Container(
                                                    width: 6,
                                                    height: 6,
                                                    decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Flexible(
                                                    child: Text(
                                                      'Sepolia Testnet',
                                                      style: AppTextStyles.caption.copyWith(color: AppColors.success, fontSize: 10),
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
                                  ),
                                  const SizedBox(width: 8),
                                  const NotificationBell(iconColor: AppColors.textPrimary),
                                  const SizedBox(width: 8),
                                  // Connect Button
                                  GestureDetector(
                                    onTap: () async {
                                      if (!_web3.isConnected) {
                                        try {
                                          await WalletUtils.showConnectDialog(context, _web3);
                                        } catch (e) {
                                          if (!context.mounted) return;
                                          NotificationManager.show(
                                            context: context,
                                            title: 'Connection Failed',
                                            message: e.toString().replaceFirst('Exception: ', ''),
                                            type: NotificationType.error,
                                          );
                                        }
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: _web3.isConnected
                                            ? AppColors.surface
                                            : AppColors.primary,
                                        borderRadius: BorderRadius.circular(AppRadius.pill),
                                        border: Border.all(
                                          color: _web3.isConnected ? AppColors.border : AppColors.secondary,
                                        ),
                                        boxShadow: _web3.isConnected ? null : AppShadows.glowPrimary,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.account_balance_wallet,
                                            size: 14,
                                            color: _web3.isConnected ? AppColors.success : AppColors.textPrimary,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            _web3.isConnected ? 'Connected' : 'Connect',
                                            style: AppTextStyles.labelMedium.copyWith(
                                              color: AppColors.textPrimary,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.xl),
                              // Title
                              Text(
                                'Logo Exchange\n& Ownership',
                                style: AppTextStyles.display.copyWith(
                                  fontSize: constraints.maxWidth < 600 ? 28 : 44,
                                  height: 1.15,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Discover, collect & auction verified digital logo artworks on-chain',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // â”€â”€â”€ Search Bar â”€â”€â”€
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.screenPadding, AppSpacing.xxl, AppSpacing.screenPadding, AppSpacing.md),
                  child: Container(
                    decoration: BoxDecoration(
                      boxShadow: AppShadows.soft,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      onChanged: (value) {
                        _searchDebounce?.cancel();
                        _searchDebounce = Timer(const Duration(milliseconds: 300), () {
                          if (mounted) {
                            setState(() => _searchQuery = value);
                            _applyFilters();
                          }
                        });
                      },
                      style: AppTextStyles.bodyLarge,
                      decoration: InputDecoration(
                        hintText: 'Search artworks, creators...',
                        prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: AppColors.textSecondary),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
              ),

              // ─── Category Filters ───
              SliverToBoxAdapter(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
                  child: Row(
                    children: NFTCategory.filterValues.map((category) {
                      final isSelected = _selectedCategory == category;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: FilterChip(
                          label: Text(
                            category,
                            style: AppTextStyles.labelMedium.copyWith(
                              color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              fontSize: 12, // smaller font for mobile
                            ),
                          ),
                          selected: isSelected,
                          onSelected: (_) {
                            setState(() => _selectedCategory = category);
                            _applyFilters();
                          },
                          backgroundColor: AppColors.surface,
                          selectedColor: AppColors.primary,
                          checkmarkColor: AppColors.textPrimary,
                          showCheckmark: false,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            side: BorderSide(
                              color: isSelected ? AppColors.primary : AppColors.border,
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),

              // â”€â”€â”€ Section Title â”€â”€â”€
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.screenPadding, AppSpacing.xxl, AppSpacing.screenPadding, AppSpacing.md),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Explore Artworks', style: AppTextStyles.h2),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text('${filteredLogos.length} Items', style: AppTextStyles.caption),
                      ),
                    ],
                  ),
                ),
              ),

              // â”€â”€â”€ Grid View â”€â”€â”€
              if (isLoading)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.screenPadding, 0, AppSpacing.screenPadding, 120),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 250,
                      childAspectRatio: 0.95,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => const LoadingSkeleton(),
                      childCount: 4,
                    ),
                  ),
                )
              else if (filteredLogos.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: EmptyStateWidget(
                      icon: _searchQuery.isNotEmpty || _selectedCategory != NFTCategory.all
                          ? Icons.search_off
                          : Icons.image_not_supported_outlined,
                      title: 'No artwork found',
                      message: _searchQuery.isNotEmpty || _selectedCategory != NFTCategory.all
                          ? 'Try adjusting your search filters.'
                          : 'Mint a new artwork to get started.',
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.screenPadding, 0, AppSpacing.screenPadding, 120),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 250,
                      childAspectRatio: 0.95,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (index == filteredLogos.length) {
                          return Center(child: CustomLoadingIndicator(size: 24));
                        }
                        final logo = filteredLogos[index];
                        Auction? activeAuction;
                        try {
                          activeAuction = _web3.activeAuctions.firstWhere((a) => a.tokenId == logo.tokenId);
                        } catch (_) {
                          activeAuction = null;
                        }

                        return RepaintBoundary(
                          child: AnimatedOpacity(
                            opacity: 1.0,
                            duration: Duration(milliseconds: 300 + (index * 50)),
                            curve: Curves.easeIn,
                            child: LogoCard(
                              logo: logo,
                              auction: activeAuction,
                              onTap: () {
                                // All items on homepage are LIVE auctions → go to AuctionPage
                                Navigator.push(context, MaterialPageRoute(builder: (_) => AuctionPage(tokenId: logo.tokenId)));
                              },
                            ),
                          ),
                        );
                      },
                      childCount: filteredLogos.length + (hasMore ? 1 : 0),
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 40)), // Adjusted padding
            ],
          ),
        );
  }
}
