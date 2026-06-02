// Mobile-specific implementation of Web3Service
// Uses WalletConnect for real MetaMask connection
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:web3dart/web3dart.dart' hide Wallet;
import 'package:web3dart/crypto.dart';
import 'package:nft_logo_marketplace/shared/models/logo_nft.dart';
import 'package:nft_logo_marketplace/shared/models/auction.dart';
import 'package:nft_logo_marketplace/shared/models/user_model.dart';
import 'package:nft_logo_marketplace/config/contract_config.dart';
import 'package:nft_logo_marketplace/core/services/web3_service.dart';
import 'package:nft_logo_marketplace/core/services/firestore_service.dart';
import 'package:nft_logo_marketplace/core/services/notification_service.dart';
import 'package:nft_logo_marketplace/core/services/walletconnect_service.dart';
import 'package:nft_logo_marketplace/core/services/session_service.dart';
import 'package:nft_logo_marketplace/core/services/auth_service.dart';
import 'package:nft_logo_marketplace/core/services/api_service.dart';

class Web3Service extends Web3ServiceBase {
  static Web3Service? _instance;
  static Web3Service get instance => _instance ??= Web3Service._();

  Web3Service._();

  late Web3Client _client;
  bool _rpcReady = false;

  // State
  String? _currentAddress;
  double _balance = 0;
  bool _isConnected = false;
  bool _isInitialized = false;
  int? _chainId;
  String _connectionType = 'none';
  Timer? _notificationTimer;
  Timer? _balanceTimer;
  final Set<int> _notifiedAuctionIds = {};

  // Multi-seller data
  final Map<String, SellerInfo> _sellers = {};
  final List<SaleRecord> _saleHistory = [];

  // Data lists
  final List<LogoNFT> _allLogos = [];
  final List<Auction> _allAuctions = [];
  int _tokenIdCounter = 0;
  int _auctionIdCounter = 0;

  // Deployed contract instances for reading
  DeployedContract? _nftContract;
  DeployedContract? _auctionContract;

  /// Whether the NFT contract is ready for transactions
  bool get isContractReady => _nftContract != null;

  @override
  Future<void> initialize() async {
    // Hot-reload safety: allow re-init if contracts are null
    if (_isInitialized && _nftContract != null) {
      if (kDebugMode) { debugPrint('[WEB3] Already initialized, skipping'); }
      return;
    }

    if (kDebugMode) { debugPrint('[WEB3] ═══════════════════════════════════════'); }
    if (kDebugMode) { debugPrint('[WEB3] Mobile Web3Service initialization started'); }
    if (kDebugMode) { debugPrint('[WEB3] RPC URL: ${ContractConfig.rpcUrl}'); }
    
    _client = Web3Client(ContractConfig.rpcUrl, http.Client());
    _rpcReady = true;
    if (kDebugMode) { debugPrint('[WEB3] ✅ RPC client created'); }

    // Initialize Notification Service
    await NotificationService().initialize();
    if (kDebugMode) { debugPrint('[WEB3] ✅ Notification service initialized'); }

    // Initialize contract instances for reading
    _initContracts();
    if (kDebugMode) { debugPrint('[WEB3] NFT Contract ready: ${_nftContract != null}'); }
    if (kDebugMode) { debugPrint('[WEB3] Auction Contract ready: ${_auctionContract != null}'); }
    
    // Load cached data from SharedPreferences
    await _loadFromStorage();
    if (kDebugMode) { debugPrint('[WEB3] ✅ Cached data loaded'); }
    
    // Start polling for auction wins
    _startWinnerPolling();
    _startBalancePolling();
    
    _isInitialized = true;
    if (kDebugMode) { debugPrint('[WEB3] ✅ Initialization complete'); }
    if (kDebugMode) { debugPrint('[WEB3] ═══════════════════════════════════════'); }
    notifyListeners();
  }

  // ============ Contract ABI Definitions ============

  static const String _logoNftAbi = '''[
    {"inputs":[],"name":"totalSupply","outputs":[{"type":"uint256","name":""}],"stateMutability":"view","type":"function"},
    {"inputs":[{"type":"uint256","name":"index"}],"name":"tokenByIndex","outputs":[{"type":"uint256","name":""}],"stateMutability":"view","type":"function"},
    {"inputs":[{"type":"uint256","name":"tokenId"}],"name":"ownerOf","outputs":[{"type":"address","name":""}],"stateMutability":"view","type":"function"},
    {"inputs":[{"type":"uint256","name":"tokenId"}],"name":"tokenURI","outputs":[{"type":"string","name":""}],"stateMutability":"view","type":"function"},
    {"inputs":[],"name":"owner","outputs":[{"type":"address","name":""}],"stateMutability":"view","type":"function"},
    {"inputs":[{"type":"uint256","name":"_tokenId"}],"name":"getLogo","outputs":[{"components":[{"type":"uint256","name":"tokenId"},{"type":"string","name":"name"},{"type":"string","name":"description"},{"type":"string","name":"imageHash"},{"type":"address","name":"creator"},{"type":"uint256","name":"createdAt"},{"type":"uint256","name":"price"},{"type":"bool","name":"isForSale"},{"type":"bool","name":"isInAuction"},{"type":"uint8","name":"status"}],"type":"tuple","name":""}],"stateMutability":"view","type":"function"},
    {"inputs":[{"type":"uint256","name":"_tokenId"}],"name":"getValidationStatus","outputs":[{"type":"uint8","name":""}],"stateMutability":"view","type":"function"},
    {"inputs":[{"type":"address","name":"to"},{"type":"uint256","name":"tokenId"}],"name":"approve","outputs":[],"stateMutability":"nonpayable","type":"function"},
    {"inputs":[{"type":"string","name":"_name"},{"type":"string","name":"_description"},{"type":"string","name":"_imageHash"},{"type":"uint256","name":"_price"}],"name":"mint","outputs":[{"type":"uint256","name":""}],"stateMutability":"nonpayable","type":"function"}
  ]''';

  static const String _logoAuctionAbi = '''[
    {"inputs":[],"name":"totalAuctions","outputs":[{"type":"uint256","name":""}],"stateMutability":"view","type":"function"},
    {"inputs":[{"type":"uint256","name":"_auctionId"}],"name":"getAuction","outputs":[{"components":[{"type":"uint256","name":"auctionId"},{"type":"uint256","name":"tokenId"},{"type":"address","name":"seller"},{"type":"address","name":"creator"},{"type":"uint256","name":"startingPrice"},{"type":"uint256","name":"reservePrice"},{"type":"uint256","name":"highestBid"},{"type":"address","name":"highestBidder"},{"type":"uint256","name":"startTime"},{"type":"uint256","name":"endTime"},{"type":"bool","name":"isActive"},{"type":"bool","name":"isEnded"},{"type":"bool","name":"reserveMet"}],"type":"tuple","name":""}],"stateMutability":"view","type":"function"},
    {"inputs":[],"name":"getActiveAuctions","outputs":[{"type":"uint256[]","name":""}],"stateMutability":"view","type":"function"},
    {"inputs":[{"type":"uint256","name":"_auctionId"}],"name":"getAuctionBids","outputs":[{"components":[{"type":"address","name":"bidder"},{"type":"uint256","name":"amount"},{"type":"uint256","name":"timestamp"}],"type":"tuple[]","name":""}],"stateMutability":"view","type":"function"},
    {"inputs":[{"type":"uint256","name":"_tokenId"},{"type":"address","name":"_creator"},{"type":"uint256","name":"_startingPrice"},{"type":"uint256","name":"_reservePrice"},{"type":"uint256","name":"_duration"}],"name":"createAuction","outputs":[{"type":"uint256","name":""}],"stateMutability":"nonpayable","type":"function"}
  ]''';

  void _initContracts() {
    // Initialize each contract independently so one failure doesn't block the other
    if (kDebugMode) { debugPrint('[WEB3] Loading contract ABIs...'); }
    try {
      _nftContract = DeployedContract(
        ContractAbi.fromJson(_logoNftAbi, 'LogoNFT'),
        EthereumAddress.fromHex(ContractConfig.logoNFTAddress),
      );
      if (kDebugMode) { debugPrint('[WEB3] ✅ NFT Contract initialized at ${ContractConfig.logoNFTAddress}'); }
      if (kDebugMode) { debugPrint('[WEB3] ✅ NFT ABI loaded successfully'); }
    } catch (e) {
      if (kDebugMode) { debugPrint('[WEB3] ❌ NFT Contract init FAILED: $e'); }
      if (kDebugMode) { debugPrint('[WEB3] ❌ Contract address: ${ContractConfig.logoNFTAddress}'); }
    }

    try {
      _auctionContract = DeployedContract(
        ContractAbi.fromJson(_logoAuctionAbi, 'LogoAuction'),
        EthereumAddress.fromHex(ContractConfig.logoAuctionAddress),
      );
      if (kDebugMode) { debugPrint('[WEB3] ✅ Auction Contract initialized at ${ContractConfig.logoAuctionAddress}'); }
      if (kDebugMode) { debugPrint('[WEB3] ✅ Auction ABI loaded successfully'); }
    } catch (e) {
      if (kDebugMode) { debugPrint('[WEB3] ❌ Auction Contract init FAILED: $e'); }
      if (kDebugMode) { debugPrint('[WEB3] ❌ Contract address: ${ContractConfig.logoAuctionAddress}'); }
    }
  }

  /// Public recovery method: retry contract initialization if it failed
  Future<void> ensureContractsInitialized() async {
    if (_nftContract != null && _auctionContract != null) return;

    if (kDebugMode) { debugPrint('[WEB3] ⚠️ Contract recovery triggered...'); }

    // Ensure RPC client is ready
    if (!_rpcReady) {
      if (kDebugMode) { debugPrint('[WEB3] Re-creating RPC client...'); }
      _client = Web3Client(ContractConfig.rpcUrl, http.Client());
      _rpcReady = true;
    }

    _initContracts();

    if (_nftContract == null) {
      if (kDebugMode) { debugPrint('[WEB3] ❌ Contract recovery FAILED — _nftContract still null'); }
    } else {
      if (kDebugMode) { debugPrint('[WEB3] ✅ Contract recovery succeeded'); }
    }
  }

  // ============ Blockchain Data Loading ============

  /// Load all logos and auctions from the blockchain
  @override
  Future<void> loadFromChain() async {
    if (kDebugMode) { debugPrint('🔄 Loading data from API/Firestore (Fast Path)...'); }
    try {
      // 1. FAST PATH: Fetch API / Firestore data immediately
      final apiService = ApiService.instance;
      final apiLogos = await apiService.fetchAllNFTs(forceRefresh: true);
      
      _allLogos.clear();
      _allLogos.addAll(apiLogos);
      
      // Load Firestore auctions to populate activeAuctions for fast load
      await _mergeFirestoreAuctions();
      
      // Auto-close any expired auctions
      await FirestoreService.instance.closeExpiredAuctions();
      
      notifyListeners();
      if (kDebugMode) { debugPrint('✅ Fast data loaded & UI updated'); }
      
      // FALLBACK: If Firestore is empty, do a one-time sync to populate it
      if (_allLogos.isEmpty) {
        if (kDebugMode) { debugPrint('⚠️ Firestore is empty, running one-time fallback blockchain sync...'); }
        Future.delayed(const Duration(milliseconds: 800), () {
          _syncBlockchainInBackground();
        });
      }
    } catch (e) {
      if (kDebugMode) { debugPrint('⚠️ Error loading from API/Firestore: $e'); }
      // Fallback to background sync if API completely fails and we have no local cache
      if (_allLogos.isEmpty) {
        Future.delayed(const Duration(milliseconds: 800), () {
          _syncBlockchainInBackground();
        });
      }
    }
  }

  Future<void> _syncBlockchainInBackground() async {
    if (kDebugMode) { debugPrint('🔄 Background syncing with blockchain...'); }
    try {
      await _loadLogosFromChain();
      await _loadAuctionsFromChain();
      
      // Sync Firestore state with blockchain data on app reopen
      // This catches any desync from failed Firestore updates
      await FirestoreService.instance.syncFirestoreState(_allLogos);
      
      // ⚡ CRITICAL: Merge Firestore auction metadata back into local logos
      // Blockchain doesn't store isAuctionActive, endTime, highestBid, etc.
      // Without this step, isLive is always false and "Bid Now" never shows
      await _mergeFirestoreData();
      
      // ⚡ CRITICAL: Merge Firestore auctions into _allAuctions
      // Off-chain auctions (created by admin approval) only exist in Firestore,
      // not on the blockchain. Without this, getAuctionForLogo() returns null
      // and "Bid Now" / "View Live Auction" buttons never appear.
      await _mergeFirestoreAuctions();
      
      await _saveToStorage();
      notifyListeners();
      if (kDebugMode) { debugPrint('✅ Background blockchain sync complete: ${_allLogos.length} logos, ${_allAuctions.length} auctions'); }
    } catch (e) {
      if (kDebugMode) { debugPrint('⚠️ Error background syncing: $e'); }
    }
  }

  /// Merge Firestore auction metadata into locally-loaded blockchain logos.
  /// Blockchain only stores: name, description, imageHash, creator, price, isForSale, isInAuction, status.
  /// Firestore additionally stores: isAuctionActive, endTime, startTime, highestBid, highestBidderWallet,
  /// isFrozen, auctionCreated, category, creatorUsername, auctionDuration, totalBids, etc.
  Future<void> _mergeFirestoreData() async {
    try {
      // PHASE 3: Fetch all NFTs efficiently from backend API to prevent Firestore spam
      final apiService = ApiService.instance;
      final apiLogos = await apiService.fetchAllNFTs(forceRefresh: true);
      
      // Map for O(1) lookup
      final Map<int, LogoNFT> apiDataMap = {};
      for (final l in apiLogos) {
        apiDataMap[l.tokenId] = l;
      }

      for (int i = 0; i < _allLogos.length; i++) {
        final logo = _allLogos[i];
        try {
          final apiLogoData = apiDataMap[logo.tokenId];
          if (apiLogoData != null) {
            _allLogos[i] = logo.copyWith(
              isAuctionActive: apiLogoData.isAuctionActive,
              startTime: apiLogoData.startTime,
              endTime: apiLogoData.endTime,
              highestBid: apiLogoData.highestBid,
              highestBidderId: apiLogoData.highestBidderId,
              highestBidderWallet: apiLogoData.highestBidderWallet,
              isFrozen: apiLogoData.isFrozen,
              auctionCreated: apiLogoData.auctionCreated,
              isActive: apiLogoData.isActive,
              category: apiLogoData.category,
              creatorUsername: apiLogoData.creatorUsername,
              creatorId: apiLogoData.creatorId,
              ownerId: apiLogoData.ownerId,
              auctionDuration: apiLogoData.auctionDuration,
              totalBids: apiLogoData.totalBids,
              approvedBy: apiLogoData.approvedBy,
            );
            // Also update status if it differs
            if (apiLogoData.status != _allLogos[i].status) {
              _allLogos[i] = _allLogos[i].copyWith(status: apiLogoData.status);
            }
          }
        } catch (e) {
          if (kDebugMode) { debugPrint('⚠️ Error merging API data for token #${logo.tokenId}: $e'); }
        }
      }
      if (kDebugMode) { debugPrint('🔄 Backend API metadata merged into ${_allLogos.length} logos'); }
    } catch (e) {
      if (kDebugMode) { debugPrint('⚠️ _mergeFirestoreData error: $e'); }
    }
  }

  /// Merge Firestore auctions into _allAuctions.
  /// Off-chain auctions (created when admin approves an NFT) only exist in
  /// Firestore — the blockchain knows nothing about them. Without this merge,
  /// getAuctionForLogo() returns null and "Bid Now" never appears on other devices.
  Future<void> _mergeFirestoreAuctions() async {
    try {
      final firestore = FirestoreService.instance;
      for (final logo in _allLogos) {
        // Only check logos that might have an auction
        if (!logo.auctionCreated && !logo.isAuctionActive && logo.status != ValidationStatus.auction) continue;

        // Skip if we already have this auction from the blockchain
        final alreadyLoaded = _allAuctions.any(
          (a) => a.tokenId == logo.tokenId || a.auctionId == logo.tokenId,
        );
        if (alreadyLoaded) continue;

        // Load auction from Firestore (doc ID = tokenId)
        final auction = await firestore.getAuction(logo.tokenId);
        if (auction != null) {
          _allAuctions.add(auction);
          if (kDebugMode) { debugPrint('📦 Loaded Firestore-only auction for token #${logo.tokenId} (status: ${auction.status})'); }
          
          // Ensure the logo object reflects the active auction
          final int index = _allLogos.indexWhere((l) => l.tokenId == logo.tokenId);
          if (index != -1) {
            _allLogos[index] = _allLogos[index].copyWith(
              isAuctionActive: auction.isOngoing,
              endTime: auction.endTime,
              status: auction.isOngoing ? ValidationStatus.auction : _allLogos[index].status,
            );
          }
        }
      }
      if (kDebugMode) { debugPrint('🔄 Firestore auctions merged: ${_allAuctions.length} total auctions'); }
    } catch (e) {
      if (kDebugMode) { debugPrint('⚠️ _mergeFirestoreAuctions error: $e'); }
    }
  }

  /// Fetch all logos from LogoNFT contract using web3dart ABI decoder
  Future<void> _loadLogosFromChain() async {
    if (_nftContract == null) return;

    try {
      // Get total supply
      final totalSupplyResult = await _client.call(
        contract: _nftContract!,
        function: _nftContract!.function('totalSupply'),
        params: [],
      );
      final totalSupply = (totalSupplyResult[0] as BigInt).toInt();
      if (kDebugMode) { debugPrint('📊 Total NFTs on chain: $totalSupply'); }

      if (totalSupply == 0) return;

      // Save existing local metadata (txHash, category) to preserve them
      final Map<int, LogoNFT> existingLogos = {};
      for (final logo in _allLogos) {
        existingLogos[logo.tokenId] = logo;
      }

      final List<LogoNFT> chainLogos = [];

      const int chunkSize = 10;
      for (int i = 0; i < totalSupply; i += chunkSize) {
        final int end = (i + chunkSize < totalSupply) ? i + chunkSize : totalSupply;
        final chunkFutures = <Future<LogoNFT?>>[];

        for (int j = i; j < end; j++) {
          chunkFutures.add(() async {
            try {
              // Get tokenId by index
              final tokenIdResult = await _client.call(
                contract: _nftContract!,
                function: _nftContract!.function('tokenByIndex'),
                params: [BigInt.from(j)],
              );
              final tokenId = (tokenIdResult[0] as BigInt).toInt();

              // Get owner
              final ownerResult = await _client.call(
                contract: _nftContract!,
                function: _nftContract!.function('ownerOf'),
                params: [BigInt.from(tokenId)],
              );
              final owner = (ownerResult[0] as EthereumAddress).hexEip55;

              // Get logo data using getLogo(uint256) via web3dart ABI decoder
              final logoResult = await _client.call(
                contract: _nftContract!,
                function: _nftContract!.function('getLogo'),
                params: [BigInt.from(tokenId)],
              );

              // logoResult[0] is a List<dynamic> representing the Logo struct tuple
              final tuple = logoResult[0] as List<dynamic>;
              
              // Parse struct fields:
              // [0] uint256 tokenId, [1] string name, [2] string description,
              // [3] string imageHash, [4] address creator, [5] uint256 createdAt,
              // [6] uint256 price, [7] bool isForSale, [8] bool isInAuction,
              // [9] uint8 status
              final name = tuple[1] as String;
              final description = tuple[2] as String;
              final imageHash = tuple[3] as String;
              final creator = (tuple[4] as EthereumAddress).hexEip55;
              final createdAtTimestamp = (tuple[5] as BigInt).toInt();
              final priceWei = tuple[6] as BigInt;
              final isForSale = tuple[7] as bool;
              final isInAuction = tuple[8] as bool;
              final statusInt = (tuple[9] as BigInt).toInt();

              // Convert values
              final price = (priceWei / BigInt.from(10).pow(18)).toDouble();
              final createdAt = DateTime.fromMillisecondsSinceEpoch(createdAtTimestamp * 1000);
              
              ValidationStatus status;
              switch (statusInt) {
                case 0: status = ValidationStatus.pending; break;
                case 1: status = ValidationStatus.approved; break;
                case 2: status = ValidationStatus.rejected; break;
                case 3: status = ValidationStatus.disabled; break;
                default: status = ValidationStatus.pending;
              }

              // Preserve local metadata (txHash, category) if we had it before
              final existing = existingLogos[tokenId];
              
              final logo = LogoNFT(
                tokenId: tokenId,
                name: name.isNotEmpty ? name : 'Logo #$tokenId',
                description: description,
                imageUrl: imageHash, // imageHash stores the IPFS URL
                imageHash: imageHash,
                creatorId: existing?.creatorId ?? '',
                creatorWallet: creator,
                ownerId: existing?.ownerId ?? '',
                ownerWallet: owner,
                createdAt: createdAt,
                price: price,
                isForSale: isForSale,
                isInAuction: isInAuction,
                status: status,
                txHash: existing?.txHash,
                category: existing?.category ?? 'Technology',
              );

              if (kDebugMode) { debugPrint('📦 Loaded logo #$tokenId: "$name" [${status.name}]'); }
              return logo;
            } catch (e) {
              if (kDebugMode) { debugPrint('⚠️ Error loading token index $j: $e'); }
              return null;
            }
          }());
        }
        
        final results = await Future.wait(chunkFutures);
        for (final result in results) {
          if (result != null) {
            chainLogos.add(result);
          }
        }
      }

      // Merge chain data with local data — preserve locally-minted items
      // that may not have been indexed on-chain yet
      final chainTokenIds = chainLogos.map((l) => l.tokenId).toSet();
      final localOnlyLogos = _allLogos.where(
        (l) => !chainTokenIds.contains(l.tokenId)
      ).toList();
      
      _allLogos.clear();
      _allLogos.addAll(chainLogos);
      _allLogos.addAll(localOnlyLogos); // Keep locally-minted not yet on chain
      _tokenIdCounter = totalSupply;
      if (kDebugMode) { debugPrint('📦 Merged: ${chainLogos.length} chain + ${localOnlyLogos.length} local-only logos'); }
    } catch (e) {
      if (kDebugMode) { debugPrint('⚠️ Error loading logos from chain: $e'); }
    }
  }

  /// Fetch all active auctions from LogoAuction contract
  Future<void> _loadAuctionsFromChain() async {
    if (_auctionContract == null) return;

    try {
      // Get total auctions count
      final totalResult = await _client.call(
        contract: _auctionContract!,
        function: _auctionContract!.function('totalAuctions'),
        params: [],
      );
      final totalAuctions = (totalResult[0] as BigInt).toInt();
      if (kDebugMode) { debugPrint('📊 Total auctions on chain: $totalAuctions'); }

      if (totalAuctions == 0) return;

      final List<Auction> chainAuctions = [];

      const int chunkSize = 10;
      for (int i = 1; i <= totalAuctions; i += chunkSize) {
        final int end = (i + chunkSize <= totalAuctions + 1) ? i + chunkSize : totalAuctions + 1;
        final chunkFutures = <Future<Auction?>>[];

        for (int aId = i; aId < end; aId++) {
          chunkFutures.add(() async {
            try {
              final auctionResult = await _client.call(
                contract: _auctionContract!,
                function: _auctionContract!.function('getAuction'),
                params: [BigInt.from(aId)],
              );

              // getAuction returns a tuple (struct)
              final tuple = auctionResult[0] as List<dynamic>;
              
              final auctionId = (tuple[0] as BigInt).toInt();
              final tokenId = (tuple[1] as BigInt).toInt();
              final seller = (tuple[2] as EthereumAddress).hexEip55;
              // tuple[3] = creator (address) - not used in Auction model
              final startingPriceWei = tuple[4] as BigInt;
              // tuple[5] = reservePrice
              final highestBidWei = tuple[6] as BigInt;
              final highestBidder = (tuple[7] as EthereumAddress);
              final startTimeUnix = (tuple[8] as BigInt).toInt();
              final endTimeUnix = (tuple[9] as BigInt).toInt();
              final isActive = tuple[10] as bool;
              final isEnded = tuple[11] as bool;

              final startingPrice = startingPriceWei / BigInt.from(10).pow(18);
              final highestBid = highestBidWei / BigInt.from(10).pow(18);
              final highestBidderHex = highestBidder.hexEip55;
              final isZeroAddress = highestBidderHex == '0x0000000000000000000000000000000000000000';

              // Fetch bids for this auction
              List<Bid> bids = [];
              try {
                final bidsResult = await _client.call(
                  contract: _auctionContract!,
                  function: _auctionContract!.function('getAuctionBids'),
                  params: [BigInt.from(aId)],
                );
                final bidsList = bidsResult[0] as List<dynamic>;
                bids = bidsList.map((bidTuple) {
                  final b = bidTuple as List<dynamic>;
                  return Bid.fromBlockchain(
                    bidder: (b[0] as EthereumAddress).hexEip55,
                    amount: ((b[1] as BigInt) / BigInt.from(10).pow(18)).toDouble(),
                    timestamp: DateTime.fromMillisecondsSinceEpoch(
                      (b[2] as BigInt).toInt() * 1000,
                    ),
                  );
                }).toList();
              } catch (e) {
                if (kDebugMode) { debugPrint('⚠️ Error fetching bids for auction $aId: $e'); }
              }

              final auction = Auction.fromBlockchain(
                auctionId: auctionId,
                tokenId: tokenId,
                seller: seller,
                startingPrice: startingPrice.toDouble(),
                highestBid: highestBid.toDouble(),
                highestBidder: isZeroAddress ? null : highestBidderHex,
                startTime: DateTime.fromMillisecondsSinceEpoch(startTimeUnix * 1000),
                endTime: DateTime.fromMillisecondsSinceEpoch(endTimeUnix * 1000),
                isActive: isActive,
                isEnded: isEnded,
                bids: bids,
              );

              return auction;
            } catch (e) {
              if (kDebugMode) { debugPrint('⚠️ Error loading auction $aId: $e'); }
              return null;
            }
          }());
        }

        final results = await Future.wait(chunkFutures);
        for (final result in results) {
          if (result != null) {
            chainAuctions.add(result);
          }
        }
      }

      // Merge chain data with local data — preserve locally-created auctions
      // that may not have been indexed on-chain yet
      final chainAuctionIds = chainAuctions.map((a) => a.auctionId).toSet();
      final localOnlyAuctions = _allAuctions.where(
        (a) => !chainAuctionIds.contains(a.auctionId)
      ).toList();
      
      _allAuctions.clear();
      _allAuctions.addAll(chainAuctions);
      _allAuctions.addAll(localOnlyAuctions); // Keep locally-created not yet on chain
      _auctionIdCounter = totalAuctions;
      if (kDebugMode) { debugPrint('📦 Merged: ${chainAuctions.length} chain + ${localOnlyAuctions.length} local-only auctions'); }
    } catch (e) {
      if (kDebugMode) { debugPrint('⚠️ Error loading auctions from chain: $e'); }
    }
  }

  // ============ Data Persistence (SharedPreferences) ============

  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'web3_logos',
        jsonEncode(_allLogos.map((l) => l.toFirestore()).toList()),
      );
      await prefs.setString(
        'web3_auctions',
        jsonEncode(_allAuctions.map((a) => a.toFirestore()).toList()),
      );
      await prefs.setInt('web3_tokenIdCounter', _tokenIdCounter);
      await prefs.setInt('web3_auctionIdCounter', _auctionIdCounter);
      if (kDebugMode) { debugPrint('💾 Data saved to storage'); }
    } catch (e) {
      if (kDebugMode) { debugPrint('⚠️ Error saving to storage: $e'); }
    }
  }

  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final logosJson = prefs.getString('web3_logos');
      if (logosJson != null && logosJson.isNotEmpty) {
        final List<dynamic> list = jsonDecode(logosJson);
        _allLogos.clear();
        _allLogos.addAll(list.map((j) => LogoNFT.fromJson(j)));
        if (kDebugMode) { debugPrint('📦 Loaded ${_allLogos.length} logos from storage'); }
      }

      final auctionsJson = prefs.getString('web3_auctions');
      if (auctionsJson != null && auctionsJson.isNotEmpty) {
        final List<dynamic> list = jsonDecode(auctionsJson);
        _allAuctions.clear();
        _allAuctions.addAll(list.map((j) => Auction.fromFirestore(j)));
        if (kDebugMode) { debugPrint('📦 Loaded ${_allAuctions.length} auctions from storage'); }
      }

      _tokenIdCounter = prefs.getInt('web3_tokenIdCounter') ?? 0;
      _auctionIdCounter = prefs.getInt('web3_auctionIdCounter') ?? 0;
    } catch (e) {
      if (kDebugMode) { debugPrint('⚠️ Error loading from storage: $e'); }
    }
  }

  // ============ Winner Notification Polling ============
  
  void _startWinnerPolling() {
    _notificationTimer?.cancel();
    _notificationTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
        if (!_isConnected || _currentAddress == null) return;
        
        final myAddress = _currentAddress!.toLowerCase();
        
        for (var auction in _allAuctions) {
            final isEnded = auction.status == AuctionStatus.ended || (auction.status == AuctionStatus.active && DateTime.now().isAfter(auction.endTime));
            final isWinner = auction.highestBidder?.toLowerCase() == myAddress;
            
            if (isEnded && isWinner && !_notifiedAuctionIds.contains(auction.auctionId)) {
                String logoName = 'Logo #${auction.tokenId}';
                try {
                    final logo = _allLogos.firstWhere((l) => l.tokenId == auction.tokenId);
                    logoName = logo.name;
                } catch (_) {}
                
                NotificationService().showNotification(
                    id: auction.auctionId,
                    title: 'Congratulations! You Won the Auction! 🏆',
                    body: 'You have won the auction for "$logoName". Check your collection now!',
                );
                
                _notifiedAuctionIds.add(auction.auctionId);
                if (kDebugMode) { debugPrint('🔔 Notification sent for auction ${auction.auctionId}'); }
            }
        }
    });
  }

  void _startBalancePolling() {
    _balanceTimer?.cancel();
    _balanceTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      if (_isConnected && _currentAddress != null) {
        _updateBalance();
      }
    });
  }
  
  void _disconnect() {
    _currentAddress = null;
    _isConnected = false;
    _balance = 0;
    _connectionType = 'none';
    _notificationTimer?.cancel();
    _balanceTimer?.cancel();
    notifyListeners();
  }

  // ============ Getters ============

  @override String? get currentAddress => _currentAddress;
  @override String? get contractOwner => '0xc45d0AdF10c6F722e1763aDAEb8d0B6E6A25c83F';
  @override double get balance => _balance;
  @override bool get isConnected => _isConnected;
  @override bool get isInitialized => _isInitialized;
  @override int? get chainId => _chainId;
  @override bool get isOnSepolia => _chainId == Web3ServiceBase.sepoliaChainId;
  @override String get connectionType => _connectionType;
  @override List<LogoNFT> get allLogos => List.unmodifiable(_allLogos);
  @override List<Auction> get allAuctions => List.unmodifiable(_allAuctions);

  @override
  List<LogoNFT> get logosForSale =>
      _allLogos.where((l) => l.isForSale && !l.isInAuction).toList();

  @override
  List<LogoNFT> get logosInAuction =>
      _allLogos.where((l) => l.isInAuction).toList();

  @override
  List<Auction> get activeAuctions =>
      _allAuctions.where((a) => a.status == AuctionStatus.active).toList();

  @override
  UserModel? get currentUser {
    // Return cached user from AuthService (Firestore profile)
    // rather than constructing a non-existent User class
    return null; // UI should use AuthService.instance.currentUserStream
  }

  @override
  bool get isMetaMaskInstalled => false;

  @override
  bool get isMobileDevice => Platform.isAndroid || Platform.isIOS;

  // ============ Wallet Connection ============

  @override
  Future<bool> connectBrowserWallet({bool restoreSession = false, String walletName = 'metamask'}) async {
    throw Exception('Browser wallet is not available on mobile app. Use MetaMask Mobile App.');
  }

  final _walletConnect = WalletConnectService.instance;

  @override
  Future<bool> connectMobileWallet({String walletName = 'metamask', bool restoreSession = false}) async {
    try {
      bool connected = false;
      if (restoreSession) {
        // Check if WalletConnect already restored the session during initialize()
        connected = _walletConnect.isConnected;
        if (connected) {
          if (kDebugMode) { debugPrint('✅ WalletConnect session still alive, restoring...'); }
          // Refresh the lastConnectedAt timestamp to prevent staleness
          await SessionService.instance.updateLastConnected();
        } else {
          if (kDebugMode) { debugPrint('⚠️ WalletConnect session not alive, cannot restore silently'); }
          // Clear stale session data so we don't retry on next launch
          await SessionService.instance.fullLogout();
          return false;
        }
      } else {
        connected = await _walletConnect.connect(walletName: walletName);
      }
      
      if (connected && _walletConnect.address != null) {
        final connectedAddress = _walletConnect.address!;
        
        // --- Wallet Verification Logic ---
        final firebaseUser = AuthService.instance.currentUser;
        if (firebaseUser != null) {
          final userData = await AuthService.instance.getUserData(firebaseUser.uid);
          if (userData != null) {
            final storedWallet = userData.walletAddress;
            if (storedWallet == null || storedWallet.isEmpty) {
              // User has no wallet linked yet, link this one
              await AuthService.instance.updateWalletAddress(firebaseUser.uid, connectedAddress);
            } else if (storedWallet.toLowerCase() != connectedAddress.toLowerCase()) {
              // Mismatch!
              _walletConnect.disconnect(); // Force disconnect
              throw Exception('WALLET_MISMATCH: Connected wallet does not match registered profile wallet ($storedWallet). Please switch your wallet in MetaMask or update your profile.');
            }
          }
        }
        
        _currentAddress = connectedAddress;
        _isConnected = true;
        _connectionType = 'walletconnect';
        _chainId = _walletConnect.chainId ?? Web3ServiceBase.sepoliaChainId;
        _registerAsSeller(_currentAddress!);

        // Load data from blockchain after connecting
        await loadFromChain();
        await _updateBalance();

        notifyListeners();
        
        // Ensure any newly expired auctions are cleaned up on load
        await FirestoreService.instance.closeExpiredAuctions();
        
        // Update UI state after all sync tasks
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ _loadState error: $e'); }
      if (e.toString().contains('WALLET_MISMATCH')) {
        rethrow; // Preserve the specific mismatch exception
      }
      throw Exception('Failed to connect to MetaMask: $e');
    }
  }

  @override
  Future<bool> connectWallet({String walletName = 'metamask', bool restoreSession = false}) async {
    return await connectMobileWallet(walletName: walletName, restoreSession: restoreSession);
  }

  @override
  void openInMetaMaskBrowser() {
    connectMobileWallet();
  }

  @override
  void disconnectWallet() {
    // Disconnect WalletConnect session (this also clears WalletSessionManager)
    _walletConnect.disconnect();
    _disconnect();
  }

  @override
  Future<bool> switchToSepolia() async {
    return false;
  }

  // ============ Helper Methods ============

  String generateImageHash(String imageData) {
    return imageData;
  }

  void _registerAsSeller(String address) {
    final key = address.toLowerCase();
    if (!_sellers.containsKey(key)) {
      _sellers[key] = SellerInfo(
        address: address,
        totalSales: 0,
        totalVolume: 0,
        totalLogosCreated: 0,
        totalRoyaltiesEarned: 0,
        rating: 0,
        ratingCount: 0,
        isActive: true,
        registeredAt: DateTime.now(),
      );
    }
  }

  @override
  void setDemoAddress(String address, double balance) {
    final initialBalance = balance;
    _currentAddress = address;
    _balance = initialBalance;
    _isConnected = true;
    _connectionType = 'demo';
    _chainId = Web3ServiceBase.sepoliaChainId;
    _registerAsSeller(address);
    // Load from chain in demo mode too
    loadFromChain();
    notifyListeners();
  }

  // ============ NFT Operations ============

  String _encodeMintCall(String name, String description, String imageHash, BigInt priceWei) {
    if (_nftContract == null) {
      // Auto-recovery attempt
      if (kDebugMode) { debugPrint('[WEB3] ⚠️ _nftContract is null in _encodeMintCall, attempting recovery...'); }
      _initContracts();
    }
    if (_nftContract == null) {
      throw Exception(
        'NFT Contract initialization failed. '
        'RPC: $_rpcReady, '
        'Contract address: ${ContractConfig.logoNFTAddress}, '
        'Wallet: $_currentAddress, '
        'Initialized: $_isInitialized'
      );
    }
    final function = _nftContract!.function('mint');
    final data = function.encodeCall([name, description, imageHash, priceWei]);
    return '0x${bytesToHex(data)}';
  }

  @override
  Future<LogoNFT> mintLogo({
    required String name,
    required String description,
    required String imageUrl,
    required double price,
    String category = 'Technology',
    String? metadataUrl,
    String? copyrightHash,
    String? hashAlgorithm,
  }) async {
    // ═══ STRICT PRE-FLIGHT VALIDATION ═══
    if (kDebugMode) { debugPrint('[MINT START] ═══════════════════════════════'); }
    if (kDebugMode) { debugPrint('[MINT START] Wallet: $_currentAddress'); }
    if (kDebugMode) { debugPrint('[MINT START] Connected: $_isConnected'); }
    if (kDebugMode) { debugPrint('[MINT START] Chain ID: $_chainId'); }
    if (kDebugMode) { debugPrint('[MINT START] RPC ready: $_rpcReady'); }
    if (kDebugMode) { debugPrint('[MINT START] NFT Contract ready: ${_nftContract != null}'); }
    if (kDebugMode) { debugPrint('[MINT START] Initialized: $_isInitialized'); }

    if (_currentAddress == null) throw Exception('Wallet not connected');
    if (!_walletConnect.isOnSepolia) throw Exception('Please switch to Sepolia network in MetaMask');

    // Ensure contracts are ready (auto-recovery for hot reload)
    if (_nftContract == null) {
      if (kDebugMode) { debugPrint('[MINT START] ⚠️ Contract null — running ensureContractsInitialized()'); }
      await ensureContractsInitialized();
    }
    if (_nftContract == null) {
      throw Exception(
        'NFT Contract not initialized. Please restart the app. '
        'RPC: $_rpcReady, Chain: $_chainId'
      );
    }

    _registerAsSeller(_currentAddress!);
    final imageHash = generateImageHash(imageUrl);
    
    final priceWei = BigInt.from(price * 1e18);
    final txData = _encodeMintCall(name, description, imageHash, priceWei);

    try {
      if (kDebugMode) { debugPrint('[TX SENT] 🚀 Sending mint transaction to LogoNFT contract...'); }
      if (kDebugMode) { debugPrint('[TX SENT] 📄 Contract: ${ContractConfig.logoNFTAddress}'); }
      
      final txHash = await _walletConnect.sendTransaction(
        to: ContractConfig.logoNFTAddress,
        data: txData,
      );
      
      if (kDebugMode) { debugPrint('[TX SENT] ✅ Mint transaction sent: $txHash'); }
      if (kDebugMode) { debugPrint('[TX SENT] 🔗 Etherscan: ${ContractConfig.getEtherscanTxUrl(txHash)}'); }
      
      if (kDebugMode) { debugPrint('[WAITING CONFIRMATION] ⏳ Waiting for blockchain confirmation...'); }
      final receipt = await _waitForReceipt(txHash);

      if (receipt == null || receipt.status != true) {
        if (kDebugMode) { debugPrint('[TX FAILED] ❌ Transaction failed on-chain'); }
        throw Exception('Transaction failed on-chain');
      }
      
      if (kDebugMode) { debugPrint('[TX CONFIRMED] ✅ Transaction confirmed on-chain'); }
      
      final realTokenId = _parseTokenIdFromReceipt(receipt);
      if (kDebugMode) { debugPrint('[TOKEN ID PARSED] 🎉 Real Token ID from blockchain: $realTokenId'); }

      final firebaseUid = AuthService.instance.currentUser?.uid ?? _currentAddress?.toLowerCase() ?? '';
      
      final logo = LogoNFT(
        tokenId: realTokenId,
        name: name,
        description: description,
        imageUrl: imageUrl,
        imageHash: imageHash,
        creatorId: firebaseUid,
        creatorWallet: _currentAddress!,
        ownerId: firebaseUid,
        ownerWallet: _currentAddress!,
        createdAt: DateTime.now(),
        price: price,
        txHash: txHash,
        category: category,
        status: ValidationStatus.pending,
        metadataUrl: metadataUrl,
        copyrightHash: copyrightHash ?? '',
        hashAlgorithm: hashAlgorithm ?? 'SHA-256',
        copyrightVerifiedAt: DateTime.now(),
        nftVisible: false,
        auctionStatus: 'NONE',
        isAuctionActive: false,
        isInAuction: false,
        isMetadataLocked: false,
      );

      // ═══ ATOMIC FIRESTORE WRITE — ONLY AFTER BLOCKCHAIN SUCCESS ═══
      try {
        if (kDebugMode) { debugPrint('[FIRESTORE SAVE START] 🔥 Saving NFT #$realTokenId to Firestore...'); }
        await FirestoreService.instance.saveNFT(logo);
        if (kDebugMode) { debugPrint('[FIRESTORE SAVE SUCCESS] ✅ NFT #$realTokenId saved to Firestore'); }
      } catch (fsError) {
        if (kDebugMode) { debugPrint('[FIRESTORE SAVE] ⚠️ Firestore write failed: $fsError'); }
        throw Exception('Firestore fail: $fsError');
      }

      // Remove any existing entry with same tokenId (from chain load)
      _allLogos.removeWhere((l) => l.tokenId == realTokenId);
      _allLogos.add(logo);

      final key = _currentAddress!.toLowerCase();
      if (_sellers.containsKey(key)) {
        _sellers[key] = _sellers[key]!.copyWith(
          totalLogosCreated: _sellers[key]!.totalLogosCreated + 1,
        );
      }

      await _updateBalance();
      await _saveToStorage();
      notifyListeners();
      
      if (kDebugMode) { debugPrint('[MINT COMPLETE] ✅ Token #$realTokenId minted and saved successfully'); }
      if (kDebugMode) { debugPrint('[MINT COMPLETE] ═══════════════════════════════'); }
      return logo;
    } catch (e) {
      if (kDebugMode) { debugPrint('[MINT FAILED] ❌ Mint failed: $e'); }
      if (e.toString().contains('User rejected') || e.toString().contains('cancelled')) {
        throw Exception('Transaction cancelled by user');
      }
      throw Exception('Mint failed: $e');
    }
  }

  String _encodeCreateAuctionCall(BigInt tokenId, EthereumAddress creator, BigInt startingPriceWei, BigInt reservePriceWei, BigInt durationSeconds) {
    if (_auctionContract == null) {
      if (kDebugMode) { debugPrint('[WEB3] ⚠️ _auctionContract is null in _encodeCreateAuctionCall, attempting recovery...'); }
      _initContracts();
    }
    if (_auctionContract == null) {
      throw Exception('Auction Contract initialization failed.');
    }
    final function = _auctionContract!.function('createAuction');
    final data = function.encodeCall([tokenId, creator, startingPriceWei, reservePriceWei, durationSeconds]);
    return '0x${bytesToHex(data)}';
  }

  @override
  Future<String> createAuctionOnChain({
    required int tokenId,
    required String creatorAddress,
    required double startingPrice,
    required int durationSeconds,
  }) async {
    if (kDebugMode) { debugPrint('[WEB3] ═══ Create Auction Pre-flight Check ═══'); }
    if (_currentAddress == null) throw Exception('Wallet not connected');
    if (!_walletConnect.isOnSepolia) throw Exception('Please switch to Sepolia network in MetaMask');

    if (_auctionContract == null) {
      await ensureContractsInitialized();
    }
    if (_auctionContract == null) {
      throw Exception('Auction Contract not initialized.');
    }

    final tokenIdBigInt = BigInt.from(tokenId);
    final creatorEthAddress = EthereumAddress.fromHex(creatorAddress);
    final startingPriceWei = BigInt.from(startingPrice * 1e18);
    final reservePriceWei = BigInt.zero;
    final durationBigInt = BigInt.from(durationSeconds);
    
    final txData = _encodeCreateAuctionCall(tokenIdBigInt, creatorEthAddress, startingPriceWei, reservePriceWei, durationBigInt);

    try {
      if (kDebugMode) { debugPrint('🚀 Sending createAuction transaction to LogoAuction contract...'); }
      final txHash = await _walletConnect.sendTransaction(
        to: ContractConfig.logoAuctionAddress,
        data: txData,
      );
      if (kDebugMode) { debugPrint('✅ createAuction transaction sent: $txHash'); }
      
      final receipt = await _waitForReceipt(txHash);
      if (receipt == null || receipt.status != true) {
          throw Exception('Transaction failed on-chain');
      }
      return txHash;
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ createAuction failed: $e'); }
      throw Exception('Create auction failed: $e');
    }
  }


  
  Future<void> _updateBalance() async {
    if (_currentAddress == null) return;
    try {
      final newBalance = await _walletConnect.getBalance();
      if (newBalance > 0) {
        _balance = newBalance;
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) { debugPrint('Error updating balance: $e'); }
    }
  }

  @override
  Future<void> listForSale(int tokenId, double price) async {
    if (_currentAddress == null) throw Exception('Wallet not connected');

    final index = _allLogos.indexWhere((l) => l.tokenId == tokenId);
    if (index == -1) throw Exception('Logo not found');

    final logo = _allLogos[index];
    if (logo.ownerWallet.toLowerCase() != _currentAddress!.toLowerCase()) {
      throw Exception('Not the owner');
    }
    if (logo.isInAuction) throw Exception('Logo is in auction');

    _allLogos[index] = logo.copyWith(isForSale: true, price: price);
    await _saveToStorage();
    notifyListeners();
  }

  @override
  Future<void> cancelListing(int tokenId) async {
    if (_currentAddress == null) throw Exception('Wallet not connected');

    final index = _allLogos.indexWhere((l) => l.tokenId == tokenId);
    if (index == -1) throw Exception('Logo not found');

    final logo = _allLogos[index];
    if (logo.ownerWallet.toLowerCase() != _currentAddress!.toLowerCase()) {
      throw Exception('Not the owner');
    }

    _allLogos[index] = logo.copyWith(isForSale: false);
    await _saveToStorage();
    notifyListeners();
  }

  @override
  Future<void> buyLogo(int tokenId) async {
    if (_currentAddress == null) throw Exception('Wallet not connected');

    final index = _allLogos.indexWhere((l) => l.tokenId == tokenId);
    if (index == -1) throw Exception('Logo not found');

    final logo = _allLogos[index];
    if (!logo.isForSale) throw Exception('Not for sale');
    if (logo.ownerWallet.toLowerCase() == _currentAddress!.toLowerCase()) {
      throw Exception('Already owned');
    }
    if (_balance < logo.price) throw Exception('Insufficient balance');

    final seller = logo.owner;
    final creator = logo.creatorWallet;
    final price = logo.price;

    double royalty = 0;
    if (seller.toLowerCase() != creator.toLowerCase()) {
      royalty = price * (Web3ServiceBase.royaltyPercentage / 100);
    }

    _allLogos[index] = logo.copyWith(
      ownerId: '', ownerWallet: _currentAddress!,
      isForSale: false,
    );

    _balance -= price;

    final sellerKey = seller.toLowerCase();
    if (_sellers.containsKey(sellerKey)) {
      _sellers[sellerKey] = _sellers[sellerKey]!.copyWith(
        totalSales: _sellers[sellerKey]!.totalSales + 1,
        totalVolume: _sellers[sellerKey]!.totalVolume + price,
      );
    }

    if (royalty > 0) {
      final creatorKey = creator.toLowerCase();
      if (_sellers.containsKey(creatorKey)) {
        _sellers[creatorKey] = _sellers[creatorKey]!.copyWith(
          totalRoyaltiesEarned: _sellers[creatorKey]!.totalRoyaltiesEarned + royalty,
        );
      }
    }

    _saleHistory.add(SaleRecord(
      tokenId: tokenId,
      seller: seller,
      buyer: _currentAddress!,
      price: price,
      royaltyPaid: royalty,
      timestamp: DateTime.now(),
    ));

    await _saveToStorage();
    notifyListeners();
  }

  // ============ Admin Operations ============

  String _encodeApproveNFTCall(int tokenId) {
    const selector = '85e0fe17';
    final tokenIdArg = BigInt.from(tokenId).toRadixString(16).padLeft(64, '0');
    return '0x$selector$tokenIdArg';
  }

  String _encodeRejectNFTCall(int tokenId) {
    const selector = '0b3687be';
    final tokenIdArg = BigInt.from(tokenId).toRadixString(16).padLeft(64, '0');
    return '0x$selector$tokenIdArg';
  }

  String _encodeDisableNFTCall(int tokenId) {
    const selector = 'ebdfbf9e';
    final tokenIdArg = BigInt.from(tokenId).toRadixString(16).padLeft(64, '0');
    return '0x$selector$tokenIdArg';
  }

  @override
  Future<void> approveNFT(int tokenId) async {
    if (_currentAddress == null) throw Exception('Wallet not connected');
    
    if (kDebugMode) { debugPrint('🚀 Approving NFT $tokenId...'); }
    final data = _encodeApproveNFTCall(tokenId);
    
    final txHash = await _walletConnect.sendTransaction(
      to: ContractConfig.logoNFTAddress,
      data: data,
    );
    if (kDebugMode) { debugPrint('✅ Approve NFT TX: $txHash'); }
    
    // Wait for confirmation
    await _waitForReceipt(txHash);
    
    final index = _allLogos.indexWhere((l) => l.tokenId == tokenId);
    if (index != -1) {
      _allLogos[index] = _allLogos[index].copyWith(status: ValidationStatus.approved);
      await _saveToStorage();
      notifyListeners();
    }
  }

  @override
  Future<void> rejectNFT(int tokenId) async {
    if (_currentAddress == null) throw Exception('Wallet not connected');
    
    if (kDebugMode) { debugPrint('🚀 Rejecting NFT $tokenId...'); }
    final data = _encodeRejectNFTCall(tokenId);
    
    final txHash = await _walletConnect.sendTransaction(
      to: ContractConfig.logoNFTAddress,
      data: data,
    );
    if (kDebugMode) { debugPrint('✅ Reject NFT TX: $txHash'); }
    
    final index = _allLogos.indexWhere((l) => l.tokenId == tokenId);
    if (index != -1) {
      _allLogos[index] = _allLogos[index].copyWith(status: ValidationStatus.rejected);
      await _saveToStorage();
      notifyListeners();
    }
  }

  @override
  Future<void> disableNFT(int tokenId) async {
    if (_currentAddress == null) throw Exception('Wallet not connected');
    
    if (kDebugMode) { debugPrint('🚀 Disabling NFT $tokenId...'); }
    final data = _encodeDisableNFTCall(tokenId);
    
    final txHash = await _walletConnect.sendTransaction(
      to: ContractConfig.logoNFTAddress,
      data: data,
    );
    if (kDebugMode) { debugPrint('✅ Disable NFT TX: $txHash'); }
    
    final index = _allLogos.indexWhere((l) => l.tokenId == tokenId);
    if (index != -1) {
      _allLogos[index] = _allLogos[index].copyWith(
        status: ValidationStatus.disabled,
        isForSale: false,
        isInAuction: false,
      );
      await _saveToStorage();
      notifyListeners();
    }
  }

  // ============ Auction Operations ============
  // These encoding helpers are used by the on-chain auction methods below.

  // ignore: unused_element
  String _encodeApproveCall(String spender, BigInt tokenId) {
    // Try contract-based encoding first, fallback to manual
    if (_nftContract != null) {
      try {
        final function = _nftContract!.function('approve');
        final data = function.encodeCall([EthereumAddress.fromHex(spender), tokenId]);
        return '0x${bytesToHex(data)}';
      } catch (e) {
        if (kDebugMode) { debugPrint('⚠️ ABI encode approve failed, using manual: $e'); }
      }
    }
    // Manual encoding: approve(address,uint256)
    // Function selector: 0x095ea7b3
    const selector = '095ea7b3';
    final spenderArg = spender.replaceFirst('0x', '').toLowerCase().padLeft(64, '0');
    final tokenIdArg = tokenId.toRadixString(16).padLeft(64, '0');
    return '0x$selector$spenderArg$tokenIdArg';
  }



  String _encodePlaceBidCall(int auctionId) {
    const selector = '1998aeef';
    final auctionIdArg = BigInt.from(auctionId).toRadixString(16).padLeft(64, '0');
    return '0x$selector$auctionIdArg';
  }

  String _encodeEndAuctionCall(int auctionId) {
    const selector = '51b88e00';
    final auctionIdArg = BigInt.from(auctionId).toRadixString(16).padLeft(64, '0');
    return '0x$selector$auctionIdArg';
  }

  /// Create an on-chain auction for an approved NFT.
  ///
  /// This is a TWO-STEP process:
  ///   1. Approve the LogoAuction contract to transfer the NFT (ERC-721 approve)
  ///   2. Call `createAuction` on LogoAuction to escrow the NFT and start the auction
  ///
  /// After both blockchain transactions succeed, Firestore is updated to reflect the live auction.
  Future<void> createAuction(int tokenId) async {
    if (_currentAddress == null) throw Exception('Wallet not connected');
    if (!_walletConnect.isOnSepolia) throw Exception('Please switch to Sepolia Testnet');

    // Look up NFT data from Firestore
    final nftDoc = await FirestoreService.instance.db
        .collection('nfts')
        .doc(tokenId.toString())
        .get();
    if (!nftDoc.exists) throw Exception('NFT not found in Firestore');

    final nftData = nftDoc.data()!;
    final status = nftData['status'] as String? ?? '';
    if (status != 'approved' && status != 'available') {
      throw Exception('NFT must be approved before starting an auction. Current status: $status');
    }

    final creatorWallet = nftData['creatorWallet'] as String? ?? _currentAddress!;
    final priceEth = (nftData['price'] as num?)?.toDouble() ?? 0.01;
    final durationSeconds = nftData['auctionDuration'] as int? ?? 86400;

    // Convert ETH to Wei
    final startingPriceWei = BigInt.from(priceEth * 1e18);
    final reservePriceWei = startingPriceWei; // reserve = starting price

    try {
      // ── STEP 1: Approve the Auction Contract to transfer NFT ──
      if (kDebugMode) { debugPrint('🚀 Step 1: Approving Auction Contract for NFT #$tokenId...'); }
      final approveData = _encodeApproveCall(
        ContractConfig.logoAuctionAddress,
        BigInt.from(tokenId),
      );

      final approveTxHash = await _walletConnect.sendTransaction(
        to: ContractConfig.logoNFTAddress,
        data: approveData,
      );
      if (kDebugMode) { debugPrint('✅ Approve TX: $approveTxHash'); }

      // Wait for approval to be mined
      final approveReceipt = await _waitForReceipt(approveTxHash);
      if (approveReceipt == null || approveReceipt.status != true) {
        throw Exception('Approve transaction failed on-chain');
      }
      if (kDebugMode) { debugPrint('✅ Approval confirmed on-chain'); }

      // ── STEP 2: Create the Auction on-chain ──
      if (kDebugMode) { debugPrint('🚀 Step 2: Creating Auction on-chain for NFT #$tokenId...'); }
      final createData = _encodeCreateAuctionCall(
        BigInt.from(tokenId),
        EthereumAddress.fromHex(creatorWallet),
        startingPriceWei,
        reservePriceWei,
        BigInt.from(durationSeconds),
      );

      final createTxHash = await _walletConnect.sendTransaction(
        to: ContractConfig.logoAuctionAddress,
        data: createData,
      );
      if (kDebugMode) { debugPrint('✅ CreateAuction TX: $createTxHash'); }

      // Wait for confirmation
      final createReceipt = await _waitForReceipt(createTxHash);
      if (createReceipt == null || createReceipt.status != true) {
        throw Exception('CreateAuction transaction failed on-chain');
      }

      // Parse the on-chain auction ID from the AuctionCreated event
      int onChainAuctionId = tokenId; // fallback
      try {
        onChainAuctionId = _parseAuctionIdFromReceipt(createReceipt);
      } catch (_) {
        if (kDebugMode) { debugPrint('⚠️ Could not parse auction ID from receipt, using tokenId as fallback'); }
      }
      if (kDebugMode) { debugPrint('🎉 Auction created on-chain! Auction ID: $onChainAuctionId'); }

      // ── STEP 3: Update Firestore to reflect AUCTION_LIVE ──
      await FirestoreService.instance.startAuction(tokenId, onChainAuctionId: onChainAuctionId);

      // Update local state
      final index = _allLogos.indexWhere((l) => l.tokenId == tokenId);
      if (index != -1) {
        _allLogos[index] = _allLogos[index].copyWith(
          status: ValidationStatus.auction,
          isInAuction: true,
          isAuctionActive: true,
          auctionCreated: true,
        );
      }

      await _updateBalance();
      await _saveToStorage();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ createAuction failed: $e'); }
      if (e.toString().contains('User rejected') || e.toString().contains('cancelled')) {
        throw Exception('Transaction cancelled by user');
      }
      rethrow;
    }
  }

  /// Place a bid on an active on-chain auction.
  ///
  /// Sends ETH as msg.value to the `placeBid(auctionId)` function on LogoAuction.
  /// After the blockchain transaction succeeds, updates Firestore with the bid data.
  Future<void> placeBid(int tokenId, double amountInEth) async {
    if (_currentAddress == null) throw Exception('Wallet not connected');
    if (!_walletConnect.isOnSepolia) throw Exception('Please switch to Sepolia Testnet');

    // Lookup the on-chain auction ID from Firestore
    final auctionDoc = await FirestoreService.instance.db
        .collection('auctions')
        .doc(tokenId.toString())
        .get();
    
    int onChainAuctionId;
    if (auctionDoc.exists) {
      onChainAuctionId = auctionDoc.data()?['auctionId'] as int? ?? tokenId;
    } else {
      throw Exception('No active auction found for this NFT');
    }

    // Convert ETH to Wei (hex string)
    final amountStr = amountInEth.toStringAsFixed(18);
    final parts = amountStr.split('.');
    final whole = parts[0];
    final decimal = parts.length > 1
        ? parts[1].padRight(18, '0')
        : '000000000000000000';
    final weiAmount = BigInt.parse('$whole$decimal');
    final weiHex = '0x${weiAmount.toRadixString(16)}';

    try {
      if (kDebugMode) { debugPrint('🚀 Placing on-chain bid: $amountInEth ETH ($weiHex wei) on Auction #$onChainAuctionId'); }

      final data = _encodePlaceBidCall(onChainAuctionId);

      final txHash = await _walletConnect.sendTransaction(
        to: ContractConfig.logoAuctionAddress,
        data: data,
        value: weiHex,
      );
      if (kDebugMode) { debugPrint('✅ PlaceBid TX: $txHash'); }

      // Wait for confirmation
      final receipt = await _waitForReceipt(txHash);
      if (receipt == null || receipt.status != true) {
        throw Exception('Bid transaction failed on-chain');
      }
      if (kDebugMode) { debugPrint('✅ Bid confirmed on-chain!'); }

      // ── Sync Firestore with on-chain bid ──
      final bid = Bid(
        bidId: _currentAddress!.toLowerCase(),
        bidderId: AuthService.instance.currentUser?.uid ?? '',
        bidderWallet: _currentAddress!,
        amount: amountInEth,
        firstBidTimestamp: DateTime.now(),
        lastBidTimestamp: DateTime.now(),
        transactionHash: txHash,
      );
      await FirestoreService.instance.placeBid(tokenId, bid, userBalance: _balance);

      await _updateBalance();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ placeBid failed: $e'); }
      if (e.toString().contains('User rejected') || e.toString().contains('cancelled')) {
        throw Exception('Transaction cancelled by user');
      }
      rethrow;
    }
  }

  /// End an on-chain auction and trigger settlement (NFT transfer + payment distribution).
  Future<void> endAuction(int tokenId) async {
    if (_currentAddress == null) throw Exception('Wallet not connected');
    if (!_walletConnect.isOnSepolia) throw Exception('Please switch to Sepolia Testnet');

    // Lookup on-chain auction ID
    final auctionDoc = await FirestoreService.instance.db
        .collection('auctions')
        .doc(tokenId.toString())
        .get();
    
    int onChainAuctionId;
    if (auctionDoc.exists) {
      onChainAuctionId = auctionDoc.data()?['auctionId'] as int? ?? tokenId;
    } else {
      throw Exception('No auction found for this NFT');
    }

    try {
      if (kDebugMode) { debugPrint('🚀 Ending auction #$onChainAuctionId on-chain...'); }

      final data = _encodeEndAuctionCall(onChainAuctionId);

      final txHash = await _walletConnect.sendTransaction(
        to: ContractConfig.logoAuctionAddress,
        data: data,
      );
      if (kDebugMode) { debugPrint('✅ EndAuction TX: $txHash'); }

      final receipt = await _waitForReceipt(txHash);
      if (receipt == null || receipt.status != true) {
        throw Exception('EndAuction transaction failed on-chain');
      }
      if (kDebugMode) { debugPrint('✅ Auction ended and settled on-chain!'); }

      // ── Sync Firestore ──
      await FirestoreService.instance.endOffChainAuction(tokenId);

      // Update local state
      final index = _allLogos.indexWhere((l) => l.tokenId == tokenId);
      if (index != -1) {
        _allLogos[index] = _allLogos[index].copyWith(
          isInAuction: false,
          isAuctionActive: false,
        );
      }

      await _updateBalance();
      await _saveToStorage();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ endAuction failed: $e'); }
      if (e.toString().contains('User rejected') || e.toString().contains('cancelled')) {
        throw Exception('Transaction cancelled by user');
      }
      rethrow;
    }
  }

  @override
  Future<String> payAuctionWinner(String sellerWallet, double amountInEth) async {
    if (_currentAddress == null) throw Exception('Wallet not connected');
    if (!_walletConnect.isOnSepolia) throw Exception('Please switch to Sepolia Testnet');
    
    // ═══ STRICT CHAIN VALIDATION ═══
    if (_chainId != null && _chainId != Web3ServiceBase.sepoliaChainId) {
      throw Exception('Please switch to Sepolia Testnet');
    }

    try {
      if (kDebugMode) { debugPrint('[PAYMENT] Opening MetaMask'); }
      if (kDebugMode) { debugPrint('[PAYMENT] Winning Bid: $amountInEth'); }
      if (kDebugMode) { debugPrint('[PAYMENT] Creator Wallet: $sellerWallet'); }
      if (kDebugMode) { debugPrint('[PAYMENT] Winner Wallet: $_currentAddress'); }
      
      // Strict string-based ETH to Wei conversion to avoid precision loss
      final amountStr = amountInEth.toStringAsFixed(18);
      final parts = amountStr.split('.');
      final whole = parts[0];
      final decimal = parts.length > 1
          ? parts[1].padRight(18, '0')
          : '000000000000000000';
      final weiAmount = BigInt.parse('$whole$decimal');

      if (kDebugMode) { debugPrint('=== PAYMENT DEBUG ==='); }
      if (kDebugMode) { debugPrint('Winning Bid ETH: $amountInEth'); }
      if (kDebugMode) { debugPrint('Wei Amount: $weiAmount'); }
      if (kDebugMode) { debugPrint('Hex Value: 0x${weiAmount.toRadixString(16)}'); }

      final weiAmountHex = '0x${weiAmount.toRadixString(16)}';
      
      // Send transaction to transfer exact ETH amount
      // Do NOT send 'data' field for plain ETH transfers to avoid MetaMask rejection
      final txHash = await _walletConnect.sendTransaction(
        to: sellerWallet,
        data: '', // empty string ensures it's stripped by walletconnect_service
        value: weiAmountHex,
      );
      
      if (kDebugMode) { debugPrint('[PAYMENT] Validating blockchain transaction...'); }
      
      final receipt = await _waitForReceipt(txHash);

      if (receipt == null || receipt.status != true) {
          throw Exception('Blockchain transaction failed');
      }

      // Strict Web3 validation
      final tx = await _client.getTransactionByHash(txHash);
      if (tx == null) {
          throw Exception('Could not fetch transaction for validation');
      }

      // Validate exact ETH amount (Wei precision)
      if (tx.value.getInWei != weiAmount) {
          throw Exception('Invalid blockchain payment amount');
      }

      // Validate sender wallet
      if (tx.from.hexEip55.toLowerCase() != _currentAddress!.toLowerCase()) {
          throw Exception('Sender wallet mismatch. Unverified sender.');
      }

      // Validate receiver wallet
      if (tx.to?.hexEip55.toLowerCase() != sellerWallet.toLowerCase()) {
          throw Exception('Receiver wallet mismatch.');
      }
      
      if (kDebugMode) { debugPrint('[PAYMENT] Exact amount validation passed'); }
      
      await _updateBalance();
      notifyListeners();
      
      return txHash;
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ Payment failed: $e'); }
      if (e.toString().contains('User rejected') || e.toString().contains('cancelled')) {
        throw Exception('Payment cancelled');
      }
      throw Exception('$e'.replaceFirst('Exception: ', '')); // Strip generic Exception prefix
    }
  }

  // ============ Query Methods ============
  
  @override
  List<LogoNFT> getMyLogos() {
    if (_currentAddress == null) return [];
    return _allLogos.where((l) => 
      l.ownerWallet.toLowerCase() == _currentAddress!.toLowerCase() &&
      l.auctionStatus?.toUpperCase().trim() == 'PAYMENT_COMPLETED'
    ).toList();
  }

  @override
  List<LogoNFT> getMyCreatedLogos() {
    if (_currentAddress == null) return [];
    return _allLogos
        .where((l) => 
          l.creatorWallet.toLowerCase() == _currentAddress!.toLowerCase() && 
          l.ownerWallet.toLowerCase() == _currentAddress!.toLowerCase()
        )
        .toList();
  }

  @override
  Auction? getAuctionForLogo(int tokenId) {
    try {
      return _allAuctions.firstWhere(
        (a) => a.tokenId == tokenId && a.status == AuctionStatus.active,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Map<String, dynamic> verifyCopyright(int tokenId) {
    final logo = _allLogos.firstWhere(
      (l) => l.tokenId == tokenId,
      orElse: () => throw Exception('Logo not found'),
    );

    final salesCount = _saleHistory.where((s) => s.tokenId == tokenId).length;

    return {
      'tokenId': logo.tokenId,
      'name': logo.name,
      'creator': logo.creatorWallet,
      'currentOwner': logo.ownerWallet,
      'createdAt': logo.createdAt.toIso8601String(),
      'imageHash': logo.imageHash,
      'verified': true,
      'salesCount': salesCount,
      'network': isOnSepolia ? 'Sepolia Testnet' : 'Local',
    };
  }

  @override
  Future<void> addBalance(double amount) async {
    _balance += amount;
    notifyListeners();
  }

  // ============ Transaction Helpers ============

  Future<TransactionReceipt?> _waitForReceipt(String txHash) async {
      int attempts = 0;
      while (attempts < 60) {
          try {
              final receipt = await _client.getTransactionReceipt(txHash);
              if (receipt != null) {
                  return receipt;
              }
          } catch (e) {
              if (kDebugMode) { debugPrint('Error checking receipt: $e'); }
          }
          await Future.delayed(const Duration(seconds: 2));
          attempts++;
      }
      throw Exception('Transaction timed out on-chain (waited 120s)');
  }

  int _parseTokenIdFromReceipt(TransactionReceipt receipt) {
      for (final log in receipt.logs) {
          if (log.topics != null && log.topics!.isNotEmpty) {
              final sig = log.topics![0].toString().toLowerCase();
              // Transfer(address from, address to, uint256 tokenId)
              if (sig == '0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef') {
                   if (log.topics!.length >= 4) {
                       final tokenIdHex = log.topics![3].toString();
                       return BigInt.parse(tokenIdHex).toInt();
                   }
              }
          }
      }
      
      if (kDebugMode) { debugPrint('Logs found: ${receipt.logs.length}'); }
      throw Exception('Could not find Token ID in transaction receipt');
  }

  // ignore: unused_element
  int _parseAuctionIdFromReceipt(TransactionReceipt receipt) {
      for (final log in receipt.logs) {
         if (log.topics != null && log.topics!.length >= 2) {
              if (log.address?.hexEip55.toLowerCase() == ContractConfig.logoAuctionAddress.toLowerCase()) {
                 final auctionIdHex = log.topics![1].toString();
                 return BigInt.parse(auctionIdHex).toInt();
             }
         }
      }
      throw Exception('Could not find Auction ID in transaction receipt');
  }
}
