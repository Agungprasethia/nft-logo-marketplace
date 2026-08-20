import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:nft_logo_marketplace/shared/models/logo_nft.dart';
import 'package:nft_logo_marketplace/shared/models/auction.dart';
import 'package:nft_logo_marketplace/core/services/web3_service.dart';
import 'package:nft_logo_marketplace/shared/widgets/logo_card.dart';
import 'package:nft_logo_marketplace/features/nft/presentation/upload_page.dart';
import 'package:nft_logo_marketplace/features/auction/presentation/auction_page.dart';
import 'package:nft_logo_marketplace/features/nft/presentation/detail_logo_page.dart';
import 'package:nft_logo_marketplace/features/profile/presentation/profile_page.dart';
import 'package:nft_logo_marketplace/core/utils/wallet_utils.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/core/services/firestore_service.dart';

import 'package:nft_logo_marketplace/core/theme/app_radius.dart';
import 'package:nft_logo_marketplace/core/theme/app_spacing.dart';
import 'package:nft_logo_marketplace/shared/widgets/empty_state_widget.dart';
import 'package:nft_logo_marketplace/shared/widgets/loading_skeleton.dart';
import 'package:nft_logo_marketplace/shared/widgets/custom_loading_indicator.dart';
import 'package:nft_logo_marketplace/core/theme/app_shadows.dart';
import 'package:nft_logo_marketplace/core/utils/notification_manager.dart';
import 'package:nft_logo_marketplace/shared/models/app_notification.dart';

// Removed api_service.dart

class HomePage extends StatefulWidget {
  static final GlobalKey<HomePageState> globalKey = GlobalKey<HomePageState>();

  HomePage({Key? key}) : super(key: key ?? globalKey);

  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  final _web3 = Web3Service.instance;
  int _currentIndex = 0;
  int _profileInitialTab = 0;
  String _searchQuery = '';
  String _selectedCategory = NFTCategory.all;
  final _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;
  
  int _limit = 50;
  bool _isRefreshing = false;
  late final Stream<List<LogoNFT>> _nftStream;

  @override
  void initState() {
    super.initState();
    debugPrint('🔎 [INVESTIGASI] HomePageState: initState() DIPANGGIL!');

    _nftStream = FirestoreService.instance.getApprovedNFTsStream();

    _web3.addListener(_refresh);
    _searchFocusNode.addListener(_onSearchFocusChanged);
    _scrollController.addListener(_onScroll);
    FirestoreService.instance.closeExpiredAuctions();
    FirestoreService.instance.expirePaymentDeadlines();
    _loadBlockchainData();
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
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadBlockchainData() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      await _web3.loadFromChain();
    } catch (e) {
      if (kDebugMode) { debugPrint('Error loading blockchain data: $e'); }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  void goToProfileCollection() {
    debugPrint('🔎 [INVESTIGASI] HomePageState: goToProfileCollection() dipanggil via GlobalKey!');
    setState(() {
      _currentIndex = 2; // index tab Profile di bottom nav
      _profileInitialTab = 1; // index tab Collection di ProfilePage
    });
  }

  List<LogoNFT> _filterLogos(List<LogoNFT> logos) {
    if (kDebugMode) { debugPrint('FILTER INPUT: ${logos.length} items from Firestore Stream'); }
    final uniqueIds = <String>{};
    
    return logos.where((logo) {
      if (!uniqueIds.add(logo.tokenId.toString())) {
        if (kDebugMode) { debugPrint('FILTER REJECTED:\nNFT=${logo.name}\nReason=duplicate'); }
        return false;
      }
      
      if (!logo.nftVisible) {
        if (kDebugMode) { debugPrint('FILTER REJECTED:\nNFT=${logo.name}\nReason=nftVisible=false'); }
        return false;
      }

      // ── ACTIVE AUCTION FILTER (gabungan, toleran terhadap data tidak konsisten) ──
      if (logo.endTime == null) {
        if (kDebugMode) { debugPrint('FILTER REJECTED:\nNFT=${logo.name}\nReason=endTime is null'); }
        return false;
      }

      if (DateTime.now().isAfter(logo.endTime!)) {
        if (kDebugMode) { debugPrint('FILTER REJECTED:\nNFT=${logo.name}\nReason=auction expired (ended at ${logo.endTime})'); }
        return false;
      }

      if (logo.isFrozen) {
        // NFT frozen: tetap tampil di homepage tapi dengan state khusus
        // Badge FROZEN akan dirender oleh logo_card.dart berdasarkan logo.isFrozen
        // Hanya filter berdasarkan nftVisible dan kategori/search saja
      } else {
        final bool hasActiveFlag = logo.isAuctionActive == true;
        final bool hasActiveStatus = logo.auctionStatus?.toUpperCase() == 'ACTIVE';
        if (!hasActiveFlag && !hasActiveStatus) {
          if (kDebugMode) { debugPrint('FILTER REJECTED:\nNFT=${logo.name}\nReason=neither isAuctionActive nor auctionStatus indicates active (isAuctionActive=${logo.isAuctionActive}, auctionStatus=${logo.auctionStatus})'); }
          return false;
        }
      }

      if (kDebugMode) {
        debugPrint('NFT: ${logo.tokenId}');
        debugPrint('STATUS: ${logo.status}');
        debugPrint('AUCTION STATUS: ${logo.auctionStatus}');
        debugPrint('IS AUCTION ACTIVE: ${logo.isAuctionActive}');
        debugPrint('VISIBLE: ${logo.nftVisible}');
      }

      // ── Category filter ──
      if (_selectedCategory != NFTCategory.all &&
          logo.category != _selectedCategory) {
        if (kDebugMode) { debugPrint('FILTER REJECTED:\nNFT=${logo.name}\nReason=category mismatch'); }
        return false;
      }
      
      // ── Search filter ──
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchesName = logo.name.toLowerCase().contains(query);
        final matchesDesc = logo.description.toLowerCase().contains(query);
        if (!matchesName && !matchesDesc) {
          if (kDebugMode) { debugPrint('FILTER REJECTED:\nNFT=${logo.name}\nReason=search mismatch'); }
          return false;
        }
      }

      if (kDebugMode) {
        debugPrint('FILTER PASSED: NFT=${logo.name} (Status: ${logo.status}, isAuctionActive: ${logo.isAuctionActive}, endTime: ${logo.endTime})');
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
    debugPrint('🔎 [INVESTIGASI] HomePageState: build() DIPANGGIL!');
    final content = IndexedStack(
      index: _currentIndex,
      children: [
        _buildHomeContent(),
        UploadPage(
          onMintSuccess: () {
            setState(() => _currentIndex = 2);
            _loadBlockchainData();
          },
        ),
        ProfilePage(key: ValueKey(_profileInitialTab), initialTabIndex: _profileInitialTab),
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
                            await WalletUtils.showConnectDialog(
                              context,
                              _web3,
                              title: 'Connect Wallet Required',
                              message: index == 1 
                                ? 'Please connect your wallet to mint and upload NFTs.' 
                                : 'Please connect your wallet to access your profile and collection.',
                            );
                            if (_web3.isConnected && mounted) setState(() => _currentIndex = index);
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
                await WalletUtils.showConnectDialog(
                  context,
                  _web3,
                  title: 'Connect Wallet Required',
                  message: index == 1 
                    ? 'Please connect your wallet to mint and upload NFTs.' 
                    : 'Please connect your wallet to access your profile and collection.',
                );
                if (_web3.isConnected && mounted) setState(() => _currentIndex = index);
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
    return RefreshIndicator(
      onRefresh: _loadBlockchainData,
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      child: StreamBuilder<List<LogoNFT>>(
        stream: _nftStream,
        builder: (context, snapshot) {
          final List<LogoNFT> allLogos = snapshot.hasData ? snapshot.data! : [];
          debugPrint('🔎 [INVESTIGASI] HomePageState: _buildHomeContent() Stream mendapat ${allLogos.length} items (connectionState=${snapshot.connectionState})');
          
          if (kDebugMode) {
            debugPrint("STREAM SNAPSHOT: connectionState=${snapshot.connectionState} hasData=${snapshot.hasData} data.length=${allLogos.length}");
          }
          final filteredLogos = _filterLogos(allLogos);
          debugPrint('🔎 [INVESTIGASI] HomePageState: _buildHomeContent() Setelah difilter tersisa ${filteredLogos.length} items');
          
          final displayedLogos = filteredLogos.take(_limit).toList();
          if (kDebugMode) {
            debugPrint("DISPLAYED LOGOS COUNT: ${displayedLogos.length}");
          }
          final bool hasMore = filteredLogos.length > _limit;
          final isLoading = snapshot.connectionState == ConnectionState.waiting;
          final hasError = snapshot.hasError;

          if (hasError && kDebugMode) {
            debugPrint('🔥 NFT Stream Error: ${snapshot.error}');
          }

          return CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
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
                                                    decoration: BoxDecoration(
                                                      color: !_web3.isConnected ? AppColors.textSecondary : (_web3.chainId != Web3ServiceBase.sepoliaChainId ? AppColors.danger : AppColors.success),
                                                      shape: BoxShape.circle,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Flexible(
                                                    child: Text(
                                                      !_web3.isConnected ? 'Not Connected' : (_web3.chainId != Web3ServiceBase.sepoliaChainId ? 'Wrong Network' : 'Sepolia Testnet'),
                                                      style: AppTextStyles.caption.copyWith(
                                                        color: !_web3.isConnected ? AppColors.textSecondary : (_web3.chainId != Web3ServiceBase.sepoliaChainId ? AppColors.danger : AppColors.success),
                                                        fontSize: 10,
                                                      ),
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

              // Search Bar
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

              // Category Filters
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
                              fontSize: 12,
                            ),
                          ),
                          selected: isSelected,
                          onSelected: (_) {
                            setState(() => _selectedCategory = category);
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

              // Section Title
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

              // Grid View
              if (isLoading)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.screenPadding, 0, AppSpacing.screenPadding, 120),
                  sliver: SliverLayoutBuilder(
                    builder: (context, constraints) {
                      return SliverGrid(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 240,
                          childAspectRatio: 0.72,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => const LoadingSkeleton(),
                          childCount: 6,
                        ),
                      );
                    },
                  ),
                )
              else if (hasError)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, color: AppColors.danger, size: 48),
                          const SizedBox(height: 16),
                          Text('Gagal memuat NFT', style: AppTextStyles.h3),
                          TextButton(
                            onPressed: () => setState(() {}),
                            child: const Text('Coba Lagi', style: TextStyle(color: AppColors.primary)),
                          )
                        ],
                      ),
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
                  sliver: SliverLayoutBuilder(
                    builder: (context, constraints) {
                      return SliverGrid(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 240,
                          childAspectRatio: 0.72,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            if (index == 0 && kDebugMode) {
                              debugPrint("GRIDVIEW ITEM COUNT: ${displayedLogos.length + (hasMore ? 1 : 0)}");
                            }
                            if (index == displayedLogos.length) {
                              return const Center(child: CustomLoadingIndicator(size: 24));
                            }
                            final logo = displayedLogos[index];
                            if (kDebugMode) { debugPrint("CARD RENDERED:\nNFT=${logo.name}\nIndex=$index"); }
                            Auction? activeAuction;
                            try {
                              activeAuction = _web3.activeAuctions.firstWhere((a) => a.tokenId == logo.tokenId);
                            } catch (_) {
                              activeAuction = null;
                            }

                            return AnimatedOpacity(
                              opacity: 1.0,
                              duration: Duration(milliseconds: 300 + (index * 50)),
                              curve: Curves.easeIn,
                              child: LogoCard(
                                logo: logo,
                                auction: activeAuction,
                                onTap: () {
                                  bool isActiveAuction = logo.isAuctionActive == true || 
                                    (logo.auctionStatus?.toUpperCase() == 'ACTIVE');

                                  if (isActiveAuction) {
                                    Navigator.push(context, MaterialPageRoute(builder: (_) => AuctionPage(logo: logo)));
                                  } else {
                                    Navigator.push(context, MaterialPageRoute(builder: (_) => DetailLogoPage(logo: logo)));
                                  }
                                },
                              ),
                            );
                          },
                          childCount: displayedLogos.length + (hasMore ? 1 : 0),
                        ),
                      );
                    },
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          );
        },
      ),
    );
  }
}
