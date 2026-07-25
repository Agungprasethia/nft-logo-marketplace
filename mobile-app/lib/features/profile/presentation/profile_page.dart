import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
import 'package:nft_logo_marketplace/features/nft/presentation/detail_logo_page.dart';
import 'package:nft_logo_marketplace/features/auction/presentation/auction_payment_page.dart';
import 'package:nft_logo_marketplace/features/profile/presentation/edit_profile_page.dart';
import 'package:nft_logo_marketplace/core/utils/wallet_utils.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

import 'package:nft_logo_marketplace/core/utils/notification_manager.dart';
import 'package:nft_logo_marketplace/shared/models/app_notification.dart';
import 'package:shimmer/shimmer.dart';
import 'package:nft_logo_marketplace/features/profile/presentation/auction_detail_page.dart';
import 'package:nft_logo_marketplace/features/profile/presentation/relist_auction_dialog.dart';
import 'package:nft_logo_marketplace/features/profile/presentation/notifications_page.dart';

// --- NEW DARK THEME DEFINITION ---
class _ProfileColors {
  static const Color bg = Color(0xFF07070F);
  static const Color cardBg = Color(0xFF0F0F1D);
  static const Color surface = Color(0xFF0D0D1F);
  static const Color accent = Color(0xFF7C3AED); // Purple
  static const Color textWhite = Color(0xFFF1F5F9);
  static const Color textMuted = Color(0xFF6B7280);
  static const Color border = Color(0xFF1A1A2E);
  static const Color headerBtnBg = Color(0xFF13131F);
  static const Color headerBtnBorder = Color(0xFF2A2A3F);

  static const Color successBg = Color(0xFF052E16);
  static const Color successText = Color(0xFF4ADE80);
  static const Color warningBg = Color(0xFF451A03);
  static const Color warningText = Color(0xFFFBBF24);
  static const Color dangerBg = Color(0xFF450A0A);
  static const Color dangerText = Color(0xFFF87171);
  static const Color dangerBorder = Color(0xFF7F1D1D);
  static const Color actionAmberBorder = Color(0xFF78350F);
  static const Color actionAmberBtnBg = Color(0xFF92400E);
  static const Color actionAmberBtnText = Color(0xFFFDE68A);
  
  static const Color tabActiveBg = Color(0xFF1E1B4B);
  static const Color tabActiveText = Color(0xFFA78BFA);
  
  static const Color downloadBtnBorder = Color(0xFF1D4ED8);
  static const Color downloadBtnText = Color(0xFF60A5FA);
}

class ProfilePage extends StatefulWidget {
  final int initialTabIndex;
  const ProfilePage({super.key, this.initialTabIndex = 0});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with SingleTickerProviderStateMixin {
  final _web3 = Web3Service.instance;
  Timer? _refreshTimer;
  UserModel? _userProfile;
  late TabController _tabController;
  
  bool _isDownloading = false;
  int _auctionTabFilter = 0; // 0: My Auctions, 1: Joined Auctions
  ValidationStatus? _creationsFilter; // null means 'All'
  bool _isLoading = false;

  // Favorites dummy set
  final Set<int> _favorites = {};
  final Map<int, Stream<DocumentSnapshot>> _nftStreams = {}; // NEW

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this, initialIndex: widget.initialTabIndex);
    _tabController.addListener(_onTabChanged);
    _web3.addListener(_onWeb3StateChanged);
    _initData();
  }

  String _currentWalletForStreams = '';
  int _ownedCount = 0;
  int _createdCount = 0;
  StreamSubscription? _ownedSub;
  StreamSubscription? _createdSub;

  Stream<List<LogoNFT>>? _createdNFTsStream;
  Stream<List<LogoNFT>>? _ownedNFTsStream;
  Map<int, Map<String, dynamic>>? _participatedBids;
  StreamSubscription? _participatedSub;

  Stream<DocumentSnapshot> _getNftStream(int tokenId) {
    return _nftStreams.putIfAbsent(
      tokenId,
      () => FirestoreService.instance.db
          .collection('nfts')
          .doc(tokenId.toString())
          .snapshots(),
    );
  }

  Future<void> _initData() async {
    try {
      await Future.wait([_loadProfile(), _subscribeToCounts()]);
      _checkGlobalOrphanedPayments(); // Check for pending transactions across all NFTs
    } catch (e) {
      if (mounted) {
        NotificationManager.show(context: context, title: 'Error', message: 'Failed to load profile data', type: NotificationType.error);
      }
    }
    if (mounted) setState(() {});
  }

  /// Iterates through SharedPreferences keys looking for orphaned transactions and attempts recovery
  Future<void> _checkGlobalOrphanedPayments() async {
    if (!mounted) return;
    final wallet = _web3.currentAddress?.toLowerCase();
    if (wallet == null || wallet.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith('orphan_tx_')).toList();
      
      for (final key in keys) {
        final txHash = prefs.getString(key);
        if (txHash == null || txHash.isEmpty) continue;
        
        final tokenIdStr = key.replaceFirst('orphan_tx_', '');
        final tokenId = int.tryParse(tokenIdStr);
        if (tokenId == null) continue;

        if (kDebugMode) { debugPrint('[PROFILE ORPHAN] Checking NFT #$tokenId with hash $txHash'); }

        // We use the basic getTransactionStatus here since we just want to know if it succeeded on-chain.
        final status = await _web3.getTransactionStatus(txHash);
        
        if (status == true) {
          if (kDebugMode) { debugPrint('[PROFILE ORPHAN] Hash $txHash for #$tokenId confirmed. Recovering...'); }
          final recovered = await FirestoreService.instance.recoverOrphanedPayment(tokenId, wallet, txHash);
          if (recovered) {
            await prefs.remove(key); // clear the key since it's recovered
            if (kDebugMode) { debugPrint('[PROFILE ORPHAN] Successfully recovered #$tokenId'); }
          }
        } else if (status == false) {
          // Explicitly failed on-chain (reverted)
          if (kDebugMode) { debugPrint('[PROFILE ORPHAN] Hash $txHash for #$tokenId reverted. Clearing storage.'); }
          await FirestoreService.instance.setPaymentProcessing(tokenId, false);
          await prefs.remove(key);
        }
        // If status == null, it's either network error or pending in mempool, we leave it alone.
      }
    } catch (e) {
      if (kDebugMode) { debugPrint('[PROFILE ORPHAN] Error checking global orphans: $e'); }
    }
  }

  Future<void> _subscribeToCounts() async {
    final wallet = _web3.currentAddress?.toLowerCase() ?? '';
    if (wallet.isEmpty) return;

    if (wallet != _currentWalletForStreams) {
      _currentWalletForStreams = wallet;
      _createdNFTsStream = FirestoreService.instance.getUserCreatedNFTsStream(wallet);
      _ownedNFTsStream = FirestoreService.instance.getUserNFTsStream(wallet);
      
      _participatedSub?.cancel();
      _participatedBids = null; // reset while loading
      _participatedSub = FirestoreService.instance.getUserParticipatedBidsStream(wallet).listen((bids) {
        if (mounted) setState(() => _participatedBids = bids);
      }, onError: (e) {
        if (mounted) setState(() => _participatedBids = {});
      });
    }
    
    // Fetch counts efficiently using Firestore count()
    final results = await Future.wait([
      FirestoreService.instance.getUserCreatedNFTsCount(wallet),
      FirestoreService.instance.getUserNFTsCount(wallet),
    ]);
    if (mounted) {
      _createdCount = results[0];
      _ownedCount = results[1];
    }
  }

  void _onTabChanged() {
    // Logic moved to _subscribeToCounts to prevent rebuilds
  }

  void _onWeb3StateChanged() {
    final newWallet = _web3.currentAddress?.toLowerCase() ?? '';
    if (newWallet != _currentWalletForStreams) {
      _initData();
    } else {
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadProfile() async {
    final isAuthenticated = _web3.isConnected && (_web3.currentAddress?.isNotEmpty ?? false);
    if (!isAuthenticated) {
      _userProfile = null;
      return;
    }

    final firebaseUser = FirebaseAuth.instance.currentUser;
    final walletAddress = _web3.currentAddress?.toLowerCase();
    final uid = firebaseUser?.uid ?? walletAddress;

    if (uid != null) {
      final profile = await AuthService.instance.getUserData(uid);
      _userProfile = profile;
    } else {
      _userProfile = null;
    }
  }

  Future<void> _handleRefresh() async {
    setState(() => _isLoading = true);
    await _initData();
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _refreshTimer?.cancel();
    _ownedSub?.cancel();
    _createdSub?.cancel();
    _participatedSub?.cancel();
    _web3.removeListener(_onWeb3StateChanged);
    _nftStreams.clear();
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
      backgroundColor: _ProfileColors.bg,
      body: SafeArea(
        child: isAuthenticated 
            ? RefreshIndicator(
                onRefresh: _handleRefresh,
                color: _ProfileColors.accent,
                backgroundColor: _ProfileColors.cardBg,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: _buildProfile(),
                  ),
                ),
              ) 
            : _buildConnectPrompt(),
      ),
    );
  }

  Widget _buildProfile() {
    final currentWallet = _web3.currentAddress?.toLowerCase().trim() ?? '';
    final myAuctions = _web3.allAuctions.where((a) => a.sellerWallet.toLowerCase() == currentWallet).toList();

    return NestedScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      headerSliverBuilder: (context, innerBoxIsScrolled) {
        return [
          SliverToBoxAdapter(
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeaderTopSection(),
                    const SizedBox(height: 20),
                    _buildBalanceStrip(),
                    const SizedBox(height: 20),
                    _buildStatsRow(myAuctions.length),
                  ],
                ),
              ),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _SliverAppBarDelegate(
              minHeight: 56.0,
              maxHeight: 56.0,
              child: Container(
                color: _ProfileColors.bg,
                child: _buildTabBar(),
              ),
            ),
          ),
        ];
      },
      body: TabBarView(
        controller: _tabController,
        children: [
          _KeepAliveTab(child: _buildCreationsTab()),
          _KeepAliveTab(child: _buildCollectionTab()),
          _buildPaymentTab(),
          _buildAuctionsTab(),
          _buildWalletTab(),
        ],
      ),
    );
  }

  // --- HEADER WIDGETS ---

  Widget _buildHeaderTopSection() {
    final rawName = _userProfile?.displayName;
    final displayName = (rawName != null && rawName.isNotEmpty) ? rawName : 'My Wallet';
    final address = _web3.currentAddress ?? '';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Row(
            children: [
            // Avatar
            if (_userProfile == null)
              Shimmer.fromColors(
                baseColor: _ProfileColors.cardBg,
                highlightColor: _ProfileColors.surface,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                ),
              )
            else
              Stack(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF4C1D95), width: 2),
                      image: _userProfile?.profileImage != null && _userProfile!.profileImage!.startsWith('data:image')
                          ? DecorationImage(
                              image: MemoryImage(base64Decode(_userProfile!.profileImage!.split(',')[1])),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: _userProfile?.profileImage == null || !_userProfile!.profileImage!.startsWith('data:image')
                        ? Center(
                            child: Text(
                              displayName.isNotEmpty ? displayName.substring(0, 1).toUpperCase() : '?',
                              style: const TextStyle(color: _ProfileColors.textWhite, fontSize: 24, fontWeight: FontWeight.bold),
                            ),
                          )
                        : null,
                  ),
                  Positioned(
                    bottom: 2,
                    right: 2,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _ProfileColors.successText,
                        shape: BoxShape.circle,
                        border: Border.all(color: _ProfileColors.bg, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              // Name & Wallet
              Expanded(
                child: _userProfile == null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Shimmer.fromColors(
                            baseColor: _ProfileColors.cardBg,
                            highlightColor: _ProfileColors.surface,
                            child: Container(height: 20, width: 120, color: Colors.white),
                          ),
                          const SizedBox(height: 8),
                          Shimmer.fromColors(
                            baseColor: _ProfileColors.cardBg,
                            highlightColor: _ProfileColors.surface,
                            child: Container(height: 14, width: 200, color: Colors.white),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: const TextStyle(color: _ProfileColors.textWhite, fontSize: 17, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  _shortenAddress(address),
                                  style: const TextStyle(color: _ProfileColors.textMuted, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              GestureDetector(
                                onTap: () {
                                  Clipboard.setData(ClipboardData(text: address));
                                  NotificationManager.show(context: context, title: 'Copied', message: 'Address copied to clipboard', type: NotificationType.success);
                                },
                                child: const Icon(Icons.copy, size: 12, color: _ProfileColors.textMuted),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _ProfileColors.successBg,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text('Sepolia', style: TextStyle(color: _ProfileColors.successText, fontSize: 9, fontWeight: FontWeight.bold)),
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
        // Action Icons
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTopIconButton(Icons.share_outlined, () {
               SharePlus.instance.share(ShareParams(text: 'Check out my NFT Profile on LEO Marketplace!'));
            }),
            const SizedBox(width: 8),
            _buildTopIconButton(Icons.logout_rounded, () {
              _showDisconnectConfirmation();
            }),
            const SizedBox(width: 8),
            _buildNotificationBell(address),
            const SizedBox(width: 8),
            _buildTopIconButton(Icons.edit_outlined, () async {
              final firebaseUser = FirebaseAuth.instance.currentUser;
              final walletAddress = _web3.currentAddress;
              final uid = firebaseUser?.uid ?? walletAddress?.toLowerCase();
              if (uid == null) return;
              
              UserModel userToEdit = _userProfile ?? UserModel(
                uid: uid,
                fullName: 'User',
                email: firebaseUser?.email ?? '',
                walletAddress: walletAddress,
                createdAt: DateTime.now(),
                lastLogin: DateTime.now(),
              );
              await Navigator.push(context, MaterialPageRoute(builder: (_) => EditProfilePage(user: userToEdit)));
              await _loadProfile();
              if (mounted) setState(() {});
            }),
          ],
        ),
      ],
    );
  }

  Widget _buildTopIconButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: _ProfileColors.headerBtnBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _ProfileColors.headerBtnBorder, width: 0.5),
        ),
        child: Icon(icon, size: 16, color: _ProfileColors.textWhite),
      ),
    );
  }

  void _showDisconnectConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _ProfileColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Disconnect Wallet', style: TextStyle(color: _ProfileColors.textWhite)),
        content: const Text('Are you sure you want to disconnect your wallet? You will need to reconnect to interact with the marketplace.', style: TextStyle(color: _ProfileColors.textMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: _ProfileColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _logout();
            },
            style: ElevatedButton.styleFrom(backgroundColor: _ProfileColors.dangerBg),
            child: const Text('Disconnect', style: TextStyle(color: _ProfileColors.dangerText)),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationBell(String walletAddress) {
    if (walletAddress.isEmpty) {
      return _buildTopIconButton(Icons.notifications_outlined, () {});
    }

    return StreamBuilder<int>(
      stream: FirestoreService.instance.getUnreadNotificationsCountStream(walletAddress),
      builder: (context, snapshot) {
        final unreadCount = snapshot.data ?? 0;
        
        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => NotificationsPage(userWallet: walletAddress.toLowerCase()),
              ),
            );
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _ProfileColors.headerBtnBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _ProfileColors.headerBtnBorder, width: 0.5),
                ),
                child: const Icon(Icons.notifications_outlined, size: 16, color: _ProfileColors.textWhite),
              ),
              if (unreadCount > 0)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      unreadCount > 99 ? '99+' : unreadCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBalanceStrip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _ProfileColors.headerBtnBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E1E30), width: 0.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Total balance', style: TextStyle(color: _ProfileColors.textMuted, fontSize: 9)),
              const SizedBox(height: 2),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 6,
                children: [
                  Text(
                    '${_web3.balance.toStringAsFixed(4)} ETH',
                    style: const TextStyle(color: _ProfileColors.textWhite, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '~ \$${(_web3.balance * 3000).toStringAsFixed(2)}',
                    style: const TextStyle(color: _ProfileColors.textMuted, fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPillButton('Send', _ProfileColors.accent),
              const SizedBox(width: 4),
              _buildPillButton('Receive', const Color(0xFF3B82F6)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPillButton(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.5),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildStatsRow(int auctionCount) {
    return Row(
      children: [
        Expanded(child: _buildStatCard('Created', '$_createdCount')),
        const SizedBox(width: 8),
        Expanded(child: _buildStatCard('Owned', '$_ownedCount')),
        const SizedBox(width: 8),
        Expanded(child: _buildStatCard('Auctions', '$auctionCount')),
        const SizedBox(width: 8),
        Expanded(child: _buildStatCard('Bids', '--')), // Will be dynamic later if needed
      ],
    );
  }

  Widget _buildStatCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: _ProfileColors.headerBtnBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1E1E30), width: 0.5),
      ),
      child: Column(
        children: [
          Text(value, style: const TextStyle(color: _ProfileColors.textWhite, fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: _ProfileColors.textMuted, fontSize: 8)),
        ],
      ),
    );
  }

  // --- TAB BAR WIDGET ---

  Widget _buildTabBar() {
    return TabBar(
      controller: _tabController,
      isScrollable: true,
      indicatorColor: _ProfileColors.accent,
      labelColor: _ProfileColors.tabActiveText,
      unselectedLabelColor: _ProfileColors.textMuted,
      dividerColor: Colors.transparent,
      tabAlignment: TabAlignment.start,
      tabs: const [
        Tab(icon: Icon(Icons.palette_outlined, size: 16), text: 'Creations'),
        Tab(icon: Icon(Icons.inventory_2_outlined, size: 16), text: 'Collection'),
        Tab(icon: Icon(Icons.credit_card_outlined, size: 16), text: 'Payment'),
        Tab(icon: Icon(Icons.gavel_outlined, size: 16), text: 'Auction'),
        Tab(icon: Icon(Icons.account_balance_wallet_outlined, size: 16), text: 'Wallet'),
      ],
    );
  }

  // --- TAB 1: CREATIONS ---

  Widget _buildCreationsTab() {
    return StreamBuilder<List<LogoNFT>>(
      stream: _createdNFTsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting || _isLoading) {
          return _buildShimmerGrid();
        }

        if (snapshot.hasError) {
          return _buildEmptyState(Icons.error_outline, 'Error loading creations');
        }

        List<LogoNFT> displayLogos = [];
        if (snapshot.hasData) {
          final uniqueIds = <String>{};
          displayLogos = snapshot.data!.where((logo) {
            return uniqueIds.add(logo.tokenId.toString());
          }).toList();
        }

        // Apply local filter
        final filteredList = displayLogos.where((logo) {
          if (_creationsFilter == null) return true; // Show ALL
          return logo.status == _creationsFilter; 
        }).toList();
        
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 20, bottom: 16),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildCreationsFilterChip('All', null),
                      const SizedBox(width: 8),
                      _buildCreationsFilterChip('Pending', ValidationStatus.pending),
                      const SizedBox(width: 8),
                      _buildCreationsFilterChip('Approved', ValidationStatus.approved),
                      const SizedBox(width: 8),
                      _buildCreationsFilterChip('Rejected', ValidationStatus.rejected),
                    ],
                  ),
                ),
              ),
            ),
            if (filteredList.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildEmptyState(Icons.palette_outlined, 'No creations found for this filter.'),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.75,
                    crossAxisSpacing: 9,
                    mainAxisSpacing: 9,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final logo = filteredList[index];
                      return _buildCreationCard(logo);
                    },
                    childCount: filteredList.length,
                  ),
                ),
              ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
          ],
        );
      }
    );
  }

  Widget _buildCreationsFilterChip(String label, ValidationStatus? status) {
    final isActive = _creationsFilter == status;
    return GestureDetector(
      onTap: () => setState(() => _creationsFilter = status),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? _ProfileColors.tabActiveBg : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isActive ? _ProfileColors.accent : _ProfileColors.headerBtnBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? _ProfileColors.tabActiveText : const Color(0xFF555555),
            fontSize: 12,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildCreationCard(LogoNFT logo) {
    Color badgeBg;
    Color badgeText;
    String badgeLabel = logo.status.name.toUpperCase();
    
    switch (logo.status) {
      case ValidationStatus.pending:
        badgeBg = _ProfileColors.warningBg;
        badgeText = _ProfileColors.warningText;
        break;
      case ValidationStatus.approved:
      case ValidationStatus.available:
        badgeBg = _ProfileColors.successBg;
        badgeText = _ProfileColors.successText;
        break;
      case ValidationStatus.auction:
        badgeBg = const Color(0xFF3B82F6).withValues(alpha: 0.15); // Blue
        badgeText = const Color(0xFF3B82F6);
        break;
      case ValidationStatus.pendingPayment:
        badgeBg = const Color(0xFF8B5CF6).withValues(alpha: 0.15); // Purple
        badgeText = const Color(0xFF8B5CF6);
        badgeLabel = 'PAYMENT PENDING';
        break;
      case ValidationStatus.sold:
        badgeBg = _ProfileColors.successBg;
        badgeText = _ProfileColors.successText;
        break;
      case ValidationStatus.rejected:
        badgeBg = _ProfileColors.dangerBg;
        badgeText = _ProfileColors.dangerText;
        break;
      case ValidationStatus.disabled:
        badgeBg = _ProfileColors.headerBtnBg;
        badgeText = _ProfileColors.textMuted;
        break;
      case ValidationStatus.frozenAuction:
        badgeBg = _ProfileColors.dangerBg;
        badgeText = _ProfileColors.dangerText;
        badgeLabel = 'FROZEN';
        break;
      default:
        badgeBg = _ProfileColors.headerBtnBg;
        badgeText = _ProfileColors.textMuted;
    }

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DetailLogoPage(logo: logo))),
      onLongPress: () => _showLongPressMenu(logo, isMyCreations: true),
      child: Container(
        decoration: BoxDecoration(
          color: _ProfileColors.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _ProfileColors.border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image Area
            Container(
              height: 104,
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFF0A0A14),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Stack(
                children: [
                  Center(
                    child: _buildNetworkImage(logo.imageUrl),
                  ),

                  // Status Badge
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        badgeLabel,
                        style: TextStyle(color: badgeText, fontSize: 8, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Body Area
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    logo.name,
                    style: const TextStyle(color: _ProfileColors.textWhite, fontSize: 11, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Token #${logo.tokenId}',
                    style: const TextStyle(color: _ProfileColors.textMuted, fontSize: 9),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- TAB 2: COLLECTION ---

  Widget _buildCollectionTab() {
    final currentWallet = _web3.currentAddress?.toLowerCase() ?? '';
    if (currentWallet.isEmpty) return _buildEmptyState(Icons.account_balance_wallet, 'Connect wallet to view collection');

    return StreamBuilder<List<LogoNFT>>(
      stream: _ownedNFTsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting || _isLoading) return _buildShimmerGrid();
        if (snapshot.hasError) return _buildEmptyState(Icons.error, 'Error loading collection');

        final uniqueIds = <String>{};
        final verifiedLogos = (snapshot.data ?? []).where((logo) {
          return uniqueIds.add(logo.tokenId.toString());
        }).toList();

        return CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(left: 16, top: 20, bottom: 12),
                child: Text('Logos you own', style: TextStyle(color: _ProfileColors.textMuted, fontSize: 10)),
              ),
            ),
            if (verifiedLogos.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildEmptyState(Icons.inventory_2_outlined, "You don't own any purchased NFTs yet."),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.55, // Adjusted to fit the download button
                    crossAxisSpacing: 9,
                    mainAxisSpacing: 9,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      return _buildCollectionCard(verifiedLogos[index]);
                    },
                    childCount: verifiedLogos.length,
                  ),
                ),
              ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
          ],
        );
      }
    );
  }

  Widget _buildCollectionCard(LogoNFT logo) {
    final isFav = _favorites.contains(logo.tokenId);
    
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DetailLogoPage(logo: logo, openedFromMyCollection: true))),
      onLongPress: () => _showLongPressMenu(logo, isMyCreations: false),
      child: Container(
        decoration: BoxDecoration(
          color: _ProfileColors.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _ProfileColors.border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image Area
            Container(
              height: 104,
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFF0A0A14),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Stack(
                children: [
                  Center(child: _buildNetworkImage(logo.imageUrl)),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: GestureDetector(
                      onTap: () => setState(() {
                        if (isFav) {
                          _favorites.remove(logo.tokenId);
                        } else {
                          _favorites.add(logo.tokenId);
                        }
                      }),
                      child: Icon(
                        isFav ? Icons.favorite : Icons.favorite_border,
                        size: 16,
                        color: isFav ? _ProfileColors.dangerText : _ProfileColors.textWhite,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Body Area
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(logo.name, style: const TextStyle(color: _ProfileColors.textWhite, fontSize: 11, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        const Text('Owned since recently', style: TextStyle(color: _ProfileColors.textMuted, fontSize: 9)),
                        const SizedBox(height: 2),
                        Text('${logo.price > 0 ? logo.price : logo.highestBid} ETH paid', style: const TextStyle(color: _ProfileColors.accent, fontSize: 10)),
                      ],
                    ),
                    // Download Button
                    GestureDetector(
                      onTap: _isDownloading ? null : () => _downloadImage(logo.imageUrl, logo.name),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(color: _ProfileColors.downloadBtnBorder),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(_isDownloading ? Icons.hourglass_empty : Icons.download, size: 12, color: _ProfileColors.downloadBtnText),
                            const SizedBox(width: 4),
                            Text(
                              _isDownloading ? 'Downloading...' : 'Download',
                              style: const TextStyle(color: _ProfileColors.downloadBtnText, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- TAB 3: PAYMENT ---

  Widget _buildPaymentTab() {
    final currentWallet = _web3.currentAddress?.toLowerCase() ?? '';
    if (currentWallet.isEmpty) return _buildEmptyState(Icons.account_balance_wallet, 'Connect wallet to view bids');

    if (_participatedBids == null || _isLoading) return _buildShimmerGrid();

    final bidsMap = _participatedBids!;
    if (bidsMap.isEmpty) return _buildEmptyState(Icons.gavel_outlined, 'No bids found.');

    final sortedEntries = bidsMap.entries.toList()..sort((a, b) => (b.value['timestamp'] ?? 0).compareTo(a.value['timestamp'] ?? 0));

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final entry = sortedEntries[index];
                    return StreamBuilder<DocumentSnapshot>(
                      stream: _getNftStream(entry.key),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData || !snapshot.data!.exists) return const SizedBox.shrink();
                        final logo = LogoNFT.fromFirestore(snapshot.data!.data() as Map<String, dynamic>? ?? {});
                        final auction = _web3.getAuctionForLogo(logo.tokenId);
                        return _buildPaymentCard(logo, auction, (entry.value['amount'] as num).toDouble(), currentWallet);
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
  }

  Widget _buildPaymentCard(LogoNFT logo, Auction? auction, double myBid, String currentWallet) {
    String status = 'UNKNOWN';
    final isLive = logo.isAuctionActive && logo.endTime != null && DateTime.now().isBefore(logo.endTime!);
    final isHighest = logo.highestBidderWallet?.toLowerCase() == currentWallet;

    if (logo.status == ValidationStatus.rejected || logo.isFrozen || auction?.status == AuctionStatus.cancelled) {
      status = 'CANCELLED';
    } else if (isLive) {
      status = isHighest ? 'WINNING' : 'OUTBID';
    } else if (logo.highestBidderWallet?.isNotEmpty == true && isHighest) {
      if (auction?.status == AuctionStatus.claimed || logo.ownerWallet.toLowerCase() == currentWallet) {
        status = 'PAID/CLAIMED';
      } else {
        status = 'ACTION REQUIRED';
      }
    } else if (logo.highestBidderWallet?.isNotEmpty == true && !isHighest) {
      status = 'LOST';
    } else {
      status = 'CANCELLED';
    }

    // Auto-hide PAID/CLAIMED as per old logic? 
    // New design specifies "Section: History" with PAID/CLAIMED, LOST, CANCELLED.
    // For simplicity, I'll group them mentally, but render them sequentially.
    // I'll style based on status.

    if (status == 'ACTION REQUIRED') {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _ProfileColors.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _ProfileColors.actionAmberBorder, width: 1.5), // Thicker border for warning
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFF2A1508),
                borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 14, color: _ProfileColors.warningText),
                  SizedBox(width: 6),
                  Text('Action required', style: TextStyle(color: _ProfileColors.warningText, fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(width: 38, height: 38, child: _buildNetworkImage(logo.imageUrl)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(logo.name, style: const TextStyle(color: _ProfileColors.textWhite, fontSize: 13, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text('You won · $myBid ETH', style: const TextStyle(color: _ProfileColors.textMuted, fontSize: 11)),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AuctionPaymentPage(tokenId: logo.tokenId))),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(color: _ProfileColors.actionAmberBtnBg, borderRadius: BorderRadius.circular(20)),
                      child: const Text('Pay Now', style: TextStyle(color: _ProfileColors.actionAmberBtnText, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Default Bid Card (Active or History)
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _ProfileColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _ProfileColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(width: 38, height: 38, child: _buildNetworkImage(logo.imageUrl)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(logo.name, style: const TextStyle(color: _ProfileColors.textWhite, fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text('My bid: $myBid ETH', style: const TextStyle(color: _ProfileColors.textMuted, fontSize: 11)),
              ],
            ),
          ),
          _buildBidStatusBadge(status),
        ],
      ),
    );
  }

  Widget _buildBidStatusBadge(String status) {
    if (status == 'WINNING') {
      return _buildPill(status, _ProfileColors.successBg, _ProfileColors.successText, false);
    } else if (status == 'OUTBID') {
      return _buildPill(status, Colors.transparent, _ProfileColors.dangerText, true, borderColor: _ProfileColors.dangerBorder);
    } else if (status == 'PAID/CLAIMED') {
      return _buildPill(status, const Color(0xFF1E3A8A), const Color(0xFF93C5FD), false);
    } else if (status == 'LOST') {
      return _buildPill(status, _ProfileColors.headerBtnBg, _ProfileColors.textMuted, false);
    } else { // CANCELLED
      return _buildPill(status, _ProfileColors.dangerBg, _ProfileColors.dangerText, false);
    }
  }

  Widget _buildPill(String text, Color bg, Color textColor, bool isOutlined, {Color? borderColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: isOutlined ? Border.all(color: borderColor ?? textColor, width: 1) : null,
      ),
      child: Text(text, style: TextStyle(color: textColor, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  // --- TAB 4: AUCTION ---

  Widget _buildAuctionsTab() {
    final currentWallet = _web3.currentAddress?.toLowerCase() ?? '';
    
    return Column(
      children: [
        // Sub-tabs
        Padding(
          padding: const EdgeInsets.only(left: 16, right: 16, top: 20, bottom: 12),
          child: Row(
            children: [
              Expanded(child: _buildSubTab('My Auctions', 0)),
              const SizedBox(width: 12),
              Expanded(child: _buildSubTab('Joined Auctions', 1)),
            ],
          ),
        ),
        // Content
        Expanded(
          child: _auctionTabFilter == 0 
            ? _buildMyAuctionsList(currentWallet)
            : _buildJoinedAuctionsList(currentWallet),
        ),
      ],
    );
  }

  Widget _buildSubTab(String label, int index) {
    final isActive = _auctionTabFilter == index;
    return GestureDetector(
      onTap: () => setState(() => _auctionTabFilter = index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive ? _ProfileColors.tabActiveBg : _ProfileColors.cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isActive ? _ProfileColors.accent : _ProfileColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? _ProfileColors.tabActiveText : _ProfileColors.textMuted,
            fontSize: 12,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildMyAuctionsList(String currentWallet) {
    return StreamBuilder<List<Auction>>(
      stream: FirestoreService.instance.getUserAuctionsStream(currentWallet),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _ProfileColors.accent));
        }
        if (snapshot.hasError) {
          return _buildEmptyState(Icons.error_outline, 'Failed to load auctions');
        }

        final myAuctions = snapshot.data ?? [];
        if (myAuctions.isEmpty) {
          return _buildEmptyState(Icons.gavel, 'No auctions found');
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: myAuctions.length,
          itemBuilder: (context, index) {
            final auction = myAuctions[index];
            // Get logo either from stream or from web3 allLogos cache
            return StreamBuilder<DocumentSnapshot>(
              stream: _getNftStream(auction.tokenId),
              builder: (context, logoSnap) {
                LogoNFT? logo;
                if (logoSnap.hasData && logoSnap.data!.exists) {
                  logo = LogoNFT.fromFirestore(logoSnap.data!.data() as Map<String, dynamic>);
                } else {
                  try { logo = _web3.allLogos.firstWhere((l) => l.tokenId == auction.tokenId); } catch (_) {}
                }

                // Check eligibility for relisting
                final bool isLive = auction.status == AuctionStatus.active;
                final bool isPaymentPending = auction.status == AuctionStatus.paymentPending;
                
                bool canReAuction = false;
                if (!isLive && !isPaymentPending && logo != null) {
                  canReAuction = auction.status == AuctionStatus.endedNoBids || 
                                 auction.status == AuctionStatus.failedPayment || 
                                 auction.status == AuctionStatus.paymentExpired || 
                                 logo.auctionStatus == 'ENDED_NO_BIDS' ||
                                 logo.auctionStatus == 'PAYMENT_EXPIRED' || 
                                 logo.auctionStatus == 'EXPIRED_NO_BID' ||
                                 logo.auctionStatus == 'EXPIRED';
                }

                return _buildAuctionCard(
                  logo: logo,
                  auction: auction,
                  isMyAuction: true,
                  isLive: isLive,
                  canReAuction: canReAuction,
                );
              }
            );
          },
        );
      },
    );
  }

  Widget _buildJoinedAuctionsList(String currentWallet) {
    if (_participatedBids == null) return _buildShimmerGrid();
    final bids = _participatedBids!;
    if (bids.isEmpty) return _buildEmptyState(Icons.group_outlined, 'No joined auctions');

    final bidsList = bids.entries.toList();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: bidsList.length,
      itemBuilder: (context, index) {
        final entry = bidsList[index];
        return StreamBuilder<DocumentSnapshot>(
          stream: _getNftStream(entry.key),
          builder: (context, snap) {
            if (!snap.hasData || !snap.data!.exists) return const SizedBox.shrink();
            final logo = LogoNFT.fromFirestore(snap.data!.data() as Map<String, dynamic>? ?? {});
            final auction = _web3.getAuctionForLogo(logo.tokenId);
            final myBid = (entry.value['amount'] as num).toDouble();
            final isLive = logo.isAuctionActive;
            final status = logo.highestBidderWallet?.toLowerCase() == currentWallet ? 'WINNING' : 'OUTBID';

            return _buildAuctionCard(
              logo: logo,
              auction: auction,
              isMyAuction: false,
              isLive: isLive,
              myBid: myBid,
              joinedStatus: status,
            );
          },
        );
      },
    );
  }

  Widget _buildAuctionCard({
    LogoNFT? logo, 
    Auction? auction, 
    required bool isMyAuction, 
    required bool isLive, 
    bool canReAuction = false,
    double? myBid,
    String? joinedStatus,
  }) {
    // Determine the exact badge and color
    String badgeText = 'ENDED';
    Color badgeBg = _ProfileColors.dangerBg;
    Color badgeTextCol = _ProfileColors.dangerText;

    if (auction != null) {
      if (auction.status == AuctionStatus.active) {
        badgeText = 'LIVE';
        badgeBg = _ProfileColors.successBg;
        badgeTextCol = _ProfileColors.successText;
      } else if (auction.status == AuctionStatus.paymentPending) {
        badgeText = 'PAYMENT PENDING';
        badgeBg = _ProfileColors.actionAmberBtnBg.withValues(alpha: 0.2);
        badgeTextCol = _ProfileColors.actionAmberBtnText;
      } else if (auction.status == AuctionStatus.paymentCompleted || auction.status == AuctionStatus.claimed || auction.status == AuctionStatus.ended) {
        // ended might mean sold if there are bids, but we'll use paymentCompleted/claimed for SOLD
        badgeText = 'SOLD';
        badgeBg = _ProfileColors.accent.withValues(alpha: 0.2);
        badgeTextCol = _ProfileColors.accent;
      } else if (auction.status == AuctionStatus.failedPayment || auction.status == AuctionStatus.paymentExpired) {
        badgeText = 'PAYMENT FAILED';
        badgeBg = _ProfileColors.dangerBg;
        badgeTextCol = _ProfileColors.dangerText;
      } else if (auction.status == AuctionStatus.endedNoBids) {
        badgeText = 'UNSOLD';
        badgeBg = _ProfileColors.textMuted.withValues(alpha: 0.2);
        badgeTextCol = _ProfileColors.textMuted;
      } else if (auction.status == AuctionStatus.cancelled) {
        badgeText = 'CANCELLED';
        badgeBg = _ProfileColors.dangerBg;
        badgeTextCol = _ProfileColors.dangerText;
      }
    }

    return GestureDetector(
      onTap: () {
        if (auction != null && logo != null) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => AuctionDetailPage(auction: auction, logo: logo)));
        } else if (logo != null) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => DetailLogoPage(logo: logo)));
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _ProfileColors.cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _ProfileColors.border, width: 0.5),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(width: 42, height: 42, child: _buildNetworkImage(logo?.imageUrl ?? '')),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(logo?.name ?? 'Token', style: const TextStyle(color: _ProfileColors.textWhite, fontSize: 13, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        if (isMyAuction)
                          Text('${auction?.totalBids ?? 0} bidders â€¢ ${auction?.highestBid ?? 0} ETH', style: const TextStyle(color: _ProfileColors.textMuted, fontSize: 10))
                        else
                          Text('My bid: $myBid ETH', style: const TextStyle(color: _ProfileColors.textMuted, fontSize: 10)),
                      ],
                    ),
                  ),
                  if (isLive)
                    Row(
                      children: [
                        const Icon(Icons.access_time, size: 12, color: _ProfileColors.successText),
                        const SizedBox(width: 4),
                        Text(auction?.timeRemainingFormatted ?? '--', style: const TextStyle(color: _ProfileColors.successText, fontSize: 10, fontWeight: FontWeight.bold)),
                      ],
                    ),
                ],
              ),
            ),
            const Divider(color: _ProfileColors.border, height: 1, thickness: 0.5),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (isMyAuction) ...[
                    _buildPill(badgeText, badgeBg, badgeTextCol, false),
                    if (canReAuction)
                      GestureDetector(
                        onTap: () {
                          if (logo != null) RelistAuctionDialog.show(context, logo);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: _ProfileColors.accent, width: 1),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.refresh, size: 12, color: _ProfileColors.accent),
                              SizedBox(width: 4),
                              Text('Relist Auction', style: TextStyle(color: _ProfileColors.accent, fontSize: 10, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      )
                    else
                      const Text('[TAP TO VIEW]', style: TextStyle(color: _ProfileColors.textMuted, fontSize: 10)),
                  ] else ...[
                    if (joinedStatus != null) _buildBidStatusBadge(joinedStatus),
                    const Text('[TAP TO VIEW]', style: TextStyle(color: _ProfileColors.textMuted, fontSize: 10)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- TAB 5: WALLET ---

  Widget _buildWalletTab() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
          Container(
            decoration: BoxDecoration(
              color: _ProfileColors.cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _ProfileColors.border, width: 0.5),
            ),
            child: Column(
              children: [
                _buildWalletInfoRow('Address', _shortenAddress(_web3.currentAddress ?? ''), isPurple: true, icon: Icons.copy),
                const Divider(color: _ProfileColors.border, height: 1, thickness: 0.5),
                _buildWalletInfoRow('Balance', '${_web3.balance.toStringAsFixed(4)} ETH'),
                const Divider(color: _ProfileColors.border, height: 1, thickness: 0.5),
                _buildWalletInfoRow('Network', _web3.isOnSepolia ? 'Sepolia Testnet' : 'Unknown', isGreen: true),
                const Divider(color: _ProfileColors.border, height: 1, thickness: 0.5),
                _buildWalletInfoRow('Connection', _web3.connectionType),
                const Divider(color: _ProfileColors.border, height: 1, thickness: 0.5),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.history, size: 14, color: _ProfileColors.downloadBtnText),
                      const SizedBox(width: 8),
                      Text('View transaction history', style: TextStyle(color: _ProfileColors.downloadBtnText, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _logout,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _ProfileColors.dangerBorder, width: 0.5),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.logout, size: 16, color: _ProfileColors.dangerText),
                  SizedBox(width: 8),
                  Text('Logout & disconnect wallet', style: TextStyle(color: _ProfileColors.dangerText, fontSize: 13, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    ));
  }

  Widget _buildWalletInfoRow(String label, String value, {bool isPurple = false, bool isGreen = false, IconData? icon}) {
    Color valColor = _ProfileColors.textWhite;
    if (isPurple) valColor = _ProfileColors.accent;
    if (isGreen) valColor = _ProfileColors.successText;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: _ProfileColors.textMuted, fontSize: 12)),
          const SizedBox(width: 8),
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    value,
                    style: TextStyle(color: valColor, fontSize: 12, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (icon != null) ...[
                  const SizedBox(width: 6),
                  Icon(icon, size: 12, color: valColor),
                ]
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- HELPERS & DIALOGS ---

  Widget _buildEmptyState(IconData icon, String msg) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: _ProfileColors.textMuted.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text(msg, style: const TextStyle(color: _ProfileColors.textMuted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildConnectPrompt() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.account_balance_wallet, size: 64, color: _ProfileColors.textMuted),
          const SizedBox(height: 16),
          const Text('Wallet Not Connected', style: TextStyle(color: _ProfileColors.textWhite, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: () async {
              try {
                await WalletUtils.showConnectDialog(context, _web3);
              } catch (e) {
                if (!mounted) return;
                NotificationManager.show(context: context, title: 'Error', message: e.toString().replaceFirst("Exception: ", ""), type: NotificationType.error);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(color: _ProfileColors.accent, borderRadius: BorderRadius.circular(20)),
              child: const Text('Connect Wallet', style: TextStyle(color: _ProfileColors.textWhite, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerGrid() {
    return Shimmer.fromColors(
      baseColor: _ProfileColors.cardBg,
      highlightColor: _ProfileColors.headerBtnBg,
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.75,
          crossAxisSpacing: 9,
          mainAxisSpacing: 9,
        ),
        itemCount: 4,
        itemBuilder: (_, __) => Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }

  Widget _buildNetworkImage(String imageUrl) {
    String finalUrl = imageUrl.replaceFirst('dweb.link/ipfs/', 'ipfs.io/ipfs/').replaceFirst('ipfs://', 'https://ipfs.io/ipfs/');
    if (finalUrl.isEmpty) return const Icon(Icons.image, color: _ProfileColors.textMuted);
    if (finalUrl.startsWith('data:image')) {
      return Image.memory(base64Decode(finalUrl.split(',').last), fit: BoxFit.cover, width: double.infinity, height: double.infinity);
    }
    return CachedNetworkImage(
      imageUrl: finalUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      memCacheWidth: 400,
      memCacheHeight: 400,
      filterQuality: FilterQuality.low,
      errorWidget: (_, __, ___) => const Icon(Icons.image, color: _ProfileColors.textMuted),
    );
  }

  String _shortenAddress(String address) {
    if (address.length <= 10) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
  }

  // --- EXISTING LOGIC KEEPS ---

  Future<void> _downloadImage(String imageUrl, String name) async {
    final currentWallet = _web3.currentAddress?.toLowerCase();
    if (currentWallet == null) return;

    setState(() => _isDownloading = true);
    try {
      final isOwner = await FirestoreService.instance.verifyNFTOwnership(imageUrl, currentWallet);
      if (!isOwner) throw Exception('Ownership verification failed.');

      Uint8List bytes;
      if (imageUrl.startsWith('http')) {
        var response = await Dio().get(imageUrl, options: Options(responseType: ResponseType.bytes));
        bytes = Uint8List.fromList(response.data);
      } else if (imageUrl.startsWith('data:image')) {
        bytes = base64Decode(imageUrl.split(',').last);
      } else {
        bytes = base64Decode(imageUrl);
      }
      await Gal.putImageBytes(bytes);
      if (!mounted) return;
      NotificationManager.show(context: context, title: 'Success', message: 'Saved to gallery!', type: NotificationType.success);
    } catch (e) {
      if (!mounted) return;
      NotificationManager.show(context: context, title: 'Failed', message: e.toString().replaceFirst("Exception: ", ""), type: NotificationType.error);
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  void _showLongPressMenu(LogoNFT logo, {required bool isMyCreations}) {
    final currentWallet = _web3.currentAddress?.toLowerCase() ?? '';
    final isOwner = logo.ownerWallet.toLowerCase() == currentWallet;

    showModalBottomSheet(
      context: context,
      backgroundColor: _ProfileColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (BuildContext context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: _ProfileColors.textMuted, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.share, color: _ProfileColors.accent),
              title: const Text('Share NFT', style: TextStyle(color: _ProfileColors.textWhite)),
              onTap: () {
                Navigator.pop(context);
                SharePlus.instance.share(ShareParams(text: 'Check out ${logo.name} on LEO!'));
              },
            ),
            if (isOwner)
              ListTile(
                leading: const Icon(Icons.download, color: _ProfileColors.successText),
                title: const Text('Download Logo', style: TextStyle(color: _ProfileColors.textWhite)),
                onTap: () {
                  Navigator.pop(context);
                  _downloadImage(logo.imageUrl, logo.name);
                },
              ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final double minHeight;
  final double maxHeight;
  final Widget child;
  _SliverAppBarDelegate({required this.minHeight, required this.maxHeight, required this.child});

  @override
  double get minExtent => minHeight;
  @override
  double get maxExtent => maxHeight;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => SizedBox.expand(child: child);
  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) => maxHeight != oldDelegate.maxHeight || minHeight != oldDelegate.minHeight || child != oldDelegate.child;
}

class _KeepAliveTab extends StatefulWidget {
  final Widget child;
  const _KeepAliveTab({required this.child});

  @override
  State<_KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<_KeepAliveTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
