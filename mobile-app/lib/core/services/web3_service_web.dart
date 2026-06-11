// Web-specific implementation of Web3Service
// Uses dart:html and dart:js_util for MetaMask integration
// ignore_for_file: uri_does_not_exist, avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:js_util' as js_util;
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'package:nft_logo_marketplace/shared/models/logo_nft.dart';
import 'package:nft_logo_marketplace/shared/models/auction.dart';
import 'package:nft_logo_marketplace/shared/models/user_model.dart';
import 'package:nft_logo_marketplace/config/contract_config.dart';
import 'package:nft_logo_marketplace/core/services/web3_service.dart';
import 'package:nft_logo_marketplace/core/services/auth_service.dart';
import 'package:nft_logo_marketplace/core/services/session_service.dart';

class Web3Service extends Web3ServiceBase {
  static Web3Service? _instance;
  static Web3Service get instance => _instance ??= Web3Service._();

  Web3Service._();

  // State
  String? _currentAddress;
  double _balance = 0;
  bool _isConnected = false;
  bool _isInitialized = false;
  int? _chainId;
  String _connectionType = 'none';
  Timer? _balanceTimer;

  // Multi-seller data
  final Map<String, SellerInfo> _sellers = {};
  final List<SaleRecord> _saleHistory = [];

  // Data lists
  final List<LogoNFT> _allLogos = [];
  final List<Auction> _allAuctions = [];
  // Reserved counters for fallback ID generation
  // ignore: unused_field
  final int _tokenIdCounter = 0;
  // ignore: unused_field
  final int _auctionIdCounter = 0;

  // Getters
  @override String? get currentAddress => _currentAddress;
  @override String? get contractOwner => '0xc45d0AdF10c6F722e1763aDAEb8d0B6E6A25c83F'; // Hardcoded for demo/testing. Should be fetched via contract `owner()`.
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
    return null; // UI should use AuthService.instance.currentUserStream
  }

  @override
  bool get isMetaMaskInstalled {
    try {
      final ethereum = js_util.getProperty(html.window, 'ethereum');
      if (ethereum == null) return false;
      final isMetaMask = js_util.getProperty(ethereum, 'isMetaMask');
      return isMetaMask == true;
    } catch (e) {
      return false;
    }
  }

  @override
  bool get isMobileDevice {
    final userAgent = html.window.navigator.userAgent.toLowerCase();
    return userAgent.contains('android') || 
           userAgent.contains('iphone') || 
           userAgent.contains('ipad');
  }

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;

    if (isMetaMaskInstalled) {
      await _setupAccountChangeListener();
      await _setupChainChangeListener();
      await _checkConnection();
    } else {
      // If MetaMask is not installed, clear any stale web session
      _clearWebSession();
    }
    
    _startBalancePolling();

    _isInitialized = true;
    notifyListeners();
  }

  Future<void> _setupAccountChangeListener() async {
    try {
      final ethereum = js_util.getProperty(html.window, 'ethereum');
      js_util.callMethod(ethereum, 'on', [
        'accountsChanged',
        js_util.allowInterop((accounts) {
          final accountList = (accounts as List).cast<String>();
          if (accountList.isEmpty) {
            _disconnect();
          } else {
            _currentAddress = accountList.first;
            _updateBalance();
            notifyListeners();
          }
        }),
      ]);
    } catch (e) {
      if (kDebugMode) { debugPrint('Error setting up account listener: $e'); }
    }
  }

  Future<void> _setupChainChangeListener() async {
    try {
      final ethereum = js_util.getProperty(html.window, 'ethereum');
      js_util.callMethod(ethereum, 'on', [
        'chainChanged',
        js_util.allowInterop((chainId) {
          _chainId = int.parse(chainId.toString().replaceFirst('0x', ''), radix: 16);
          notifyListeners();
        }),
      ]);
    } catch (e) {
      if (kDebugMode) { debugPrint('Error setting up chain listener: $e'); }
    }
  }

  void _startBalancePolling() {
    _balanceTimer?.cancel();
    _balanceTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      if (_isConnected && _currentAddress != null) {
        _updateBalance();
      }
    });
  }

  Future<void> _checkConnection() async {
    try {
      final ethereum = js_util.getProperty(html.window, 'ethereum');
      final result = await js_util.promiseToFuture(
        js_util.callMethod(ethereum, 'request', [
          js_util.jsify({'method': 'eth_accounts'}),
        ]),
      );

      final accounts = (result as List).cast<String>();
      if (accounts.isNotEmpty) {
        _currentAddress = accounts.first;
        _isConnected = true;
        _connectionType = 'browser';
        await _getChainId();
        await _updateBalance();
        // Persist session awareness for page refresh
        _saveWebSession();
        if (kDebugMode) { debugPrint('✅ Web wallet restored from MetaMask: $_currentAddress'); }
      } else {
        // MetaMask has no active accounts — clear stale session
        _clearWebSession();
      }
    } catch (e) {
      if (kDebugMode) { debugPrint('Error checking connection: $e'); }
    }
  }

  @override
  Future<bool> connectBrowserWallet({String walletName = 'metamask', bool restoreSession = false}) async {
    if (!isMetaMaskInstalled) {
      throw Exception('MetaMask is not installed. Please install the MetaMask extension.');
    }

    try {
      final ethereum = js_util.getProperty(html.window, 'ethereum');
      
      final method = restoreSession ? 'eth_accounts' : 'eth_requestAccounts';
      
      final result = await js_util.promiseToFuture(
        js_util.callMethod(ethereum, 'request', [
          js_util.jsify({'method': method}),
        ]),
      );

      final accounts = (result as List).cast<String>();
      if (accounts.isNotEmpty) {
        final connectedAddress = accounts.first;
        
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
              _disconnect(); // Force disconnect
              throw Exception('WALLET_MISMATCH: Connected wallet does not match registered profile wallet ($storedWallet). Please switch your wallet in MetaMask or update your profile.');
            }
          }
        }
        
        _currentAddress = connectedAddress;
        _isConnected = true;
        _connectionType = 'browser';
        await _getChainId();
        await _updateBalance();
        _registerAsSeller(_currentAddress!);
        // Persist session for page refresh
        _saveWebSession();
        notifyListeners();
        return true;
      } else {
        if (restoreSession) {
          if (kDebugMode) { debugPrint('⚠️ Silent restore failed (no accounts). Clearing session.'); }
          _clearWebSession();
          await SessionService.instance.fullLogout();
        }
        return false;
      }
    } catch (e) {
      if (kDebugMode) { debugPrint('Error connecting browser wallet: $e'); }
      if (e.toString().contains('WALLET_MISMATCH')) {
        rethrow;
      }
      throw Exception('Failed to connect wallet: $e');
    }
  }

  @override
  Future<bool> connectMobileWallet({String walletName = 'metamask', bool restoreSession = false}) async {
    try {
      if (restoreSession) return false;
      final currentUrl = html.window.location.href;
      final cleanUrl = currentUrl.replaceFirst(RegExp(r'^https?://'), '');
      final metamaskDeepLink = 'https://metamask.app.link/dapp/$cleanUrl';
      html.window.location.href = metamaskDeepLink;
      return true;
    } catch (e) {
      if (kDebugMode) { debugPrint('Error connecting mobile wallet: $e'); }
      throw Exception('Failed to open MetaMask App: $e');
    }
  }

  @override
  Future<bool> connectWallet({String walletName = 'metamask', bool restoreSession = false}) async {
    if (isMobileDevice && !isMetaMaskInstalled) {
      return await connectMobileWallet(walletName: walletName, restoreSession: restoreSession);
    }
    if (isMetaMaskInstalled) {
      return await connectBrowserWallet(walletName: walletName, restoreSession: restoreSession);
    }
    if (isMobileDevice) {
      return await connectMobileWallet(walletName: walletName, restoreSession: restoreSession);
    } else {
      throw Exception('MetaMask is not installed. Please install the MetaMask extension.');
    }
  }

  @override
  Future<bool?> getTransactionStatus(String txHash) async {
    try {
      final receipt = await _getTransactionReceipt(txHash);
      if (receipt != null) {
        return receipt['status'] == '0x1';
      }
      return null;
    } catch (e) {
      if (kDebugMode) { debugPrint('[WEB3_WEB] Error getting tx receipt: $e'); }
      return null;
    }
  }

  @override
  void openInMetaMaskBrowser() {
    final currentUrl = html.window.location.href;
    final cleanUrl = currentUrl.replaceFirst(RegExp(r'^https?://'), '');
    final metamaskLink = 'https://metamask.app.link/dapp/$cleanUrl';
    html.window.location.href = metamaskLink;
  }

  void _disconnect() {
    _currentAddress = null;
    _isConnected = false;
    _balance = 0;
    _connectionType = 'none';
    _balanceTimer?.cancel();
    _clearWebSession();
    notifyListeners();
  }

  @override
  void disconnectWallet() {
    _disconnect();
  }

  // ============ Web Session Persistence (localStorage) ============

  /// Save minimal session metadata to localStorage for page-refresh awareness
  void _saveWebSession() {
    try {
      html.window.localStorage['leo_wallet_connected'] = 'true';
      html.window.localStorage['leo_wallet_address'] = _currentAddress ?? '';
      html.window.localStorage['leo_wallet_provider'] = _connectionType;
      html.window.localStorage['leo_last_connected'] = DateTime.now().toIso8601String();
      if (_chainId != null) {
        html.window.localStorage['leo_chain_id'] = _chainId.toString();
      }
      if (kDebugMode) { debugPrint('💾 Web session saved to localStorage'); }
    } catch (e) {
      if (kDebugMode) { debugPrint('⚠️ Error saving web session: $e'); }
    }
  }

  /// Clear session data from localStorage (on logout or disconnect)
  void _clearWebSession() {
    try {
      html.window.localStorage.remove('leo_wallet_connected');
      html.window.localStorage.remove('leo_wallet_address');
      html.window.localStorage.remove('leo_wallet_provider');
      html.window.localStorage.remove('leo_last_connected');
      html.window.localStorage.remove('leo_chain_id');
      if (kDebugMode) { debugPrint('🔌 Web session cleared from localStorage'); }
    } catch (e) {
      if (kDebugMode) { debugPrint('⚠️ Error clearing web session: $e'); }
    }
  }

  Future<void> _getChainId() async {
    try {
      final ethereum = js_util.getProperty(html.window, 'ethereum');
      final result = await js_util.promiseToFuture(
        js_util.callMethod(ethereum, 'request', [
          js_util.jsify({'method': 'eth_chainId'}),
        ]),
      );
      _chainId = int.parse(result.toString().replaceFirst('0x', ''), radix: 16);
    } catch (e) {
      if (kDebugMode) { debugPrint('Error getting chain ID: $e'); }
    }
  }

  @override
  Future<String> createAuctionOnChain({
    required int tokenId,
    required String creatorAddress,
    required double startingPrice,
    required int durationSeconds,
  }) async {
    throw UnimplementedError('createAuctionOnChain not implemented for web yet');
  }

  Future<void> _updateBalance() async {
    if (_currentAddress == null) return;

    try {
      final ethereum = js_util.getProperty(html.window, 'ethereum');
      final result = await js_util.promiseToFuture(
        js_util.callMethod(ethereum, 'request', [
          js_util.jsify({
            'method': 'eth_getBalance',
            'params': [_currentAddress, 'latest'],
          }),
        ]),
      );

      final balanceWei = BigInt.parse(result.toString().replaceFirst('0x', ''), radix: 16);
      _balance = balanceWei / BigInt.from(10).pow(18);
      notifyListeners();
    } catch (e) {
      if (kDebugMode) { debugPrint('Error getting balance: $e'); }
    }
  }

  @override
  Future<bool> switchToSepolia() async {
    if (!isMetaMaskInstalled) return false;

    try {
      final ethereum = js_util.getProperty(html.window, 'ethereum');
      await js_util.promiseToFuture(
        js_util.callMethod(ethereum, 'request', [
          js_util.jsify({
            'method': 'wallet_switchEthereumChain',
            'params': [
              {'chainId': Web3ServiceBase.sepoliaChainIdHex}
            ],
          }),
        ]),
      );
      _chainId = Web3ServiceBase.sepoliaChainId;
      notifyListeners();
      return true;
    } catch (e) {
      try {
        final ethereum = js_util.getProperty(html.window, 'ethereum');
        await js_util.promiseToFuture(
          js_util.callMethod(ethereum, 'request', [
            js_util.jsify({
              'method': 'wallet_addEthereumChain',
              'params': [
                {
                  'chainId': Web3ServiceBase.sepoliaChainIdHex,
                  'chainName': 'Sepolia Testnet',
                  'nativeCurrency': {
                    'name': 'SepoliaETH',
                    'symbol': 'ETH',
                    'decimals': 18,
                  },
                  'rpcUrls': [Web3ServiceBase.sepoliaRpcUrl],
                  'blockExplorerUrls': [Web3ServiceBase.sepoliaBlockExplorer],
                }
              ],
            }),
          ]),
        );
        _chainId = Web3ServiceBase.sepoliaChainId;
        notifyListeners();
        return true;
      } catch (addError) {
        if (kDebugMode) { debugPrint('Error adding Sepolia: $addError'); }
        return false;
      }
    }
  }

  String generateImageHash(String imageData) {
    // FIX: Store full URL directly
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
    if (_currentAddress == null) throw Exception('Wallet not connected');
    if (!isOnSepolia) throw Exception('Please switch to Sepolia network');

    _registerAsSeller(_currentAddress!);
    final imageHash = generateImageHash(imageUrl);
    
    // Convert price to wei (1 ETH = 10^18 wei)
    final priceWei = BigInt.from(price * 1e18);
    
    // Encode function call data for mint(name, description, imageHash, price)
    // Function selector for mint is embedded in _encodeMintCall
    // const functionSelector = '0x94bf804d';
    
    // For simplicity, we'll use eth_sendTransaction with encoded data
    // In production, use proper ABI encoding
    final txData = _encodeMintCall(name, description, imageHash, priceWei);

    try {
      final ethereum = js_util.getProperty(html.window, 'ethereum');
      final txHash = await js_util.promiseToFuture(
        js_util.callMethod(ethereum, 'request', [
          js_util.jsify({
            'method': 'eth_sendTransaction',
            'params': [{
              'from': _currentAddress,
              'to': ContractConfig.logoNFTAddress,
              'data': txData,
              // Let MetaMask auto-estimate gas (typically 200-500K for NFT mint)
            }],
          }),
        ]),
      );
      
      if (kDebugMode) { debugPrint('✅ Mint transaction sent: $txHash'); }
      if (kDebugMode) { debugPrint('🔗 View on Etherscan: ${ContractConfig.getEtherscanTxUrl(txHash.toString())}'); }
      
      // Wait for transaction confirmation
      if (kDebugMode) { debugPrint('⏳ Waiting for mint confirmation...'); }
      final receipt = await _waitForReceipt(txHash.toString());
      if (receipt == null) throw Exception('Transaction failed');

      final realTokenId = _parseTokenIdFromReceipt(receipt);
      if (kDebugMode) { debugPrint('🎉 Minted Token ID: $realTokenId'); }
      
      final firebaseUid = AuthService.instance.currentUser?.uid ?? '';

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
        txHash: txHash.toString(),
        category: category,
      );

      _allLogos.removeWhere((l) => l.tokenId == realTokenId);
      _allLogos.add(logo);

      final key = _currentAddress!.toLowerCase();
      if (_sellers.containsKey(key)) {
        _sellers[key] = _sellers[key]!.copyWith(
          totalLogosCreated: _sellers[key]!.totalLogosCreated + 1,
        );
      }

      await _updateBalance();
      notifyListeners();
      return logo;
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ Mint failed: $e'); }
      throw Exception('Mint failed: $e');
    }
  }
  
  /// Encode mint function call (simplified ABI encoding)
  String _encodeMintCall(String name, String desc, String hash, BigInt price) {
    // Function selector for mint(string,string,string,uint256)
    // Using pre-computed selector to avoid dependencies
    const selector = '94bf804d';
    
    // Simplified encoding - in production use proper ABI encoder
    // For now, encode strings as hex
    final nameHex = _stringToHex(name);
    final descHex = _stringToHex(desc);
    final hashHex = _stringToHex(hash);
    final priceHex = price.toRadixString(16).padLeft(64, '0');
    
    // Dynamic data layout with offsets
    // offset1 (name) | offset2 (desc) | offset3 (hash) | price | name_data | desc_data | hash_data
    final offset1 = (4 * 32).toRadixString(16).padLeft(64, '0'); // 128 = 0x80
    final namePadded = _padHexString(nameHex);
    final descPadded = _padHexString(descHex);
    final hashPadded = _padHexString(hashHex);
    
    final offset2 = (4 * 32 + namePadded.length ~/ 2).toRadixString(16).padLeft(64, '0');
    final offset3 = (4 * 32 + namePadded.length ~/ 2 + descPadded.length ~/ 2).toRadixString(16).padLeft(64, '0');
    
    return '0x$selector$offset1$offset2$offset3$priceHex$namePadded$descPadded$hashPadded';
  }
  
  String _stringToHex(String str) {
    return utf8.encode(str).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
  
  String _padHexString(String hex) {
    final len = (hex.length ~/ 2).toRadixString(16).padLeft(64, '0');
    final padded = hex.padRight(((hex.length + 63) ~/ 64) * 64, '0');
    return len + padded;
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
    notifyListeners();
  }

  // --- Admin Operations ---

  /// Encode approveNFT function call
  String _encodeApproveNFTCall(int tokenId) {
    const selector = '85e0fe17'; // approveNFT(uint256)
    final tokenIdArg = BigInt.from(tokenId).toRadixString(16).padLeft(64, '0');
    return '0x$selector$tokenIdArg';
  }

  /// Encode rejectNFT function call
  String _encodeRejectNFTCall(int tokenId) {
    const selector = '0b3687be'; // rejectNFT(uint256)
    final tokenIdArg = BigInt.from(tokenId).toRadixString(16).padLeft(64, '0');
    return '0x$selector$tokenIdArg';
  }

  /// Encode disableNFT function call
  String _encodeDisableNFTCall(int tokenId) {
    const selector = 'ebdfbf9e'; // disableNFT(uint256)
    final tokenIdArg = BigInt.from(tokenId).toRadixString(16).padLeft(64, '0');
    return '0x$selector$tokenIdArg';
  }

  @override
  Future<void> approveNFT(int tokenId) async {
    if (_currentAddress == null) throw Exception('Wallet not connected');
    
    final txData = _encodeApproveNFTCall(tokenId);

    try {
      final ethereum = js_util.getProperty(html.window, 'ethereum');
      final txHash = await js_util.promiseToFuture(
        js_util.callMethod(ethereum, 'request', [
          js_util.jsify({
            'method': 'eth_sendTransaction',
            'params': [{
              'from': _currentAddress,
              'to': ContractConfig.logoNFTAddress,
              'data': txData,
            }],
          }),
        ]),
      );
      
      if (kDebugMode) { debugPrint('✅ Approve NFT TX: $txHash'); }
      
      // Optimistic update
      final index = _allLogos.indexWhere((l) => l.tokenId == tokenId);
      if (index != -1) {
        _allLogos[index] = _allLogos[index].copyWith(status: ValidationStatus.approved);
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ Approve NFT failed: $e'); }
      throw Exception('Approve NFT failed: $e');
    }
  }

  @override
  Future<void> rejectNFT(int tokenId) async {
    if (_currentAddress == null) throw Exception('Wallet not connected');
    
    final txData = _encodeRejectNFTCall(tokenId);

    try {
      final ethereum = js_util.getProperty(html.window, 'ethereum');
      final txHash = await js_util.promiseToFuture(
        js_util.callMethod(ethereum, 'request', [
          js_util.jsify({
            'method': 'eth_sendTransaction',
            'params': [{
              'from': _currentAddress,
              'to': ContractConfig.logoNFTAddress,
              'data': txData,
            }],
          }),
        ]),
      );
      
      if (kDebugMode) { debugPrint('✅ Reject NFT TX: $txHash'); }
      
      // Optimistic update
      final index = _allLogos.indexWhere((l) => l.tokenId == tokenId);
      if (index != -1) {
        _allLogos[index] = _allLogos[index].copyWith(status: ValidationStatus.rejected);
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ Reject NFT failed: $e'); }
      throw Exception('Reject NFT failed: $e');
    }
  }

  @override
  Future<void> disableNFT(int tokenId) async {
    if (_currentAddress == null) throw Exception('Wallet not connected');
    
    final txData = _encodeDisableNFTCall(tokenId);

    try {
      final ethereum = js_util.getProperty(html.window, 'ethereum');
      final txHash = await js_util.promiseToFuture(
        js_util.callMethod(ethereum, 'request', [
          js_util.jsify({
            'method': 'eth_sendTransaction',
            'params': [{
              'from': _currentAddress,
              'to': ContractConfig.logoNFTAddress,
              'data': txData,
            }],
          }),
        ]),
      );
      
      if (kDebugMode) { debugPrint('✅ Disable NFT TX: $txHash'); }
      
      // Optimistic update
      final index = _allLogos.indexWhere((l) => l.tokenId == tokenId);
      if (index != -1) {
        _allLogos[index] = _allLogos[index].copyWith(
          status: ValidationStatus.disabled,
          isForSale: false,
          isInAuction: false,
        );
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ Disable NFT failed: $e'); }
      throw Exception('Disable NFT failed: $e');
    }
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

    notifyListeners();
  }
  @override
  Future<String> payAuctionWinner(String sellerWallet, double amountInEth) async {
    if (_currentAddress == null) throw Exception('Wallet not connected');
    if (_chainId != Web3ServiceBase.sepoliaChainId) {
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
      
      final ethereum = js_util.getProperty(html.window, 'ethereum');
      final txHash = await js_util.promiseToFuture(
        js_util.callMethod(ethereum, 'request', [
          js_util.jsify({
            'method': 'eth_sendTransaction',
            'params': [{
              'from': _currentAddress,
              'to': sellerWallet,
              'value': weiAmountHex,
            }],
          }),
        ]),
      );
      
      if (kDebugMode) { debugPrint('[PAYMENT] Validating blockchain transaction...'); }
      
      // Wait for receipt
      final receipt = await _waitForReceipt(txHash.toString());

      if (receipt == null || receipt['status'] == null || int.parse(receipt['status'].toString().replaceFirst('0x', ''), radix: 16) == 0) {
          throw Exception('Blockchain transaction failed');
      }

      // ═══ STRICT ON-CHAIN VALIDATION ═══
      final txData = await _getTransactionByHash(txHash.toString());

      if (txData != null) {
        // Validate sender wallet (tx.from)
        final txFrom = (txData['from'] as String? ?? '').toLowerCase();
        if (txFrom != _currentAddress!.toLowerCase()) {
          throw Exception('Sender wallet mismatch. Unverified sender.');
        }

        // Validate receiver wallet (tx.to)
        final txTo = (txData['to'] as String? ?? '').toLowerCase();
        if (txTo != sellerWallet.toLowerCase()) {
          throw Exception('Receiver wallet mismatch.');
        }

        // Validate exact ETH amount (Wei precision)
        final txValueHex = txData['value'] as String? ?? '0x0';
        final txValue = BigInt.parse(txValueHex.replaceFirst('0x', ''), radix: 16);
        if (txValue != weiAmount) {
          throw Exception('Invalid blockchain payment amount');
        }
        
        // Exact Chain ID check (just in case they switch mid-flight)
        final txChainIdHex = txData['chainId'] as String? ?? '0x0';
        final txChainId = int.parse(txChainIdHex.replaceFirst('0x', ''), radix: 16);
        if (txChainId != 11155111) {
          throw Exception('Please switch to Sepolia Testnet');
        }

        if (kDebugMode) { debugPrint('[PAYMENT] Exact amount validation passed'); }
      } else {
        throw Exception('Could not fetch transaction for validation');
      }
      
      await _updateBalance();
      notifyListeners();
      
      return txHash.toString();
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ Payment failed: $e'); }
      if (e.toString().contains('User rejected') || e.toString().contains('cancelled') || e.toString().contains('User denied')) {
        throw Exception('Payment cancelled');
      }
      throw Exception('$e'.replaceFirst('Exception: ', '')); // Strip generic Exception prefix
    }
  }

  /// Fetch transaction data by hash for on-chain validation
  Future<Map<String, dynamic>?> _getTransactionByHash(String txHash) async {
    try {
      final ethereum = js_util.getProperty(html.window, 'ethereum');
      final result = await js_util.promiseToFuture(
        js_util.callMethod(ethereum, 'request', [
          js_util.jsify({
            'method': 'eth_getTransactionByHash',
            'params': [txHash],
          }),
        ]),
      );
      if (result != null) {
        return _jsObjectToMap(result);
      }
    } catch (e) {
      if (kDebugMode) { debugPrint('Error getting transaction by hash: $e'); }
    }
    return null;
  }

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

  // ============ Transaction Helpers for Web ============

  Future<Map<String, dynamic>?> _getTransactionReceipt(String txHash) async {
    try {
      final ethereum = js_util.getProperty(html.window, 'ethereum');
      final result = await js_util.promiseToFuture(
        js_util.callMethod(ethereum, 'request', [
          js_util.jsify({
            'method': 'eth_getTransactionReceipt',
            'params': [txHash],
          }),
        ]),
      );
      if (result != null) {
        return _jsObjectToMap(result);
      }
    } catch (e) {
      if (kDebugMode) { debugPrint('Error getting receipt: $e'); }
    }
    return null;
  }
  
  Map<String, dynamic> _jsObjectToMap(dynamic jsObj) {
    try {
       final jsonString = js_util.callMethod(js_util.getProperty(html.window, 'JSON'), 'stringify', [jsObj]);
       return jsonDecode(jsonString.toString()) as Map<String, dynamic>;
    } catch (e) {
       return {};
    }
  }

  Future<Map<String, dynamic>?> _waitForReceipt(String txHash) async {
    int attempts = 0;
    while (attempts < 30) {
      final receipt = await _getTransactionReceipt(txHash);
      if (receipt != null && receipt['blockNumber'] != null) {
        // Wait a small extra time to ensure logs are fully parsed by RPC
        await Future.delayed(const Duration(seconds: 1));
        return receipt;
      }
      await Future.delayed(const Duration(seconds: 2));
      attempts++;
    }
    throw Exception('Transaction timed out');
  }

  int _parseTokenIdFromReceipt(Map<String, dynamic> receipt) {
    // transfer topic: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    final logs = receipt['logs'] as List<dynamic>?;
    if (logs != null) {
      for (final log in logs) {
        final topics = log['topics'] as List<dynamic>?;
        if (topics != null && topics.isNotEmpty) {
          final sig = topics[0].toString().toLowerCase();
          if (sig == '0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef') {
            if (topics.length >= 4) {
              final tokenIdHex = topics[3].toString();
              return int.parse(tokenIdHex.replaceFirst('0x', ''), radix: 16);
            }
          }
        }
      }
    }
    throw Exception('Could not find Token ID in transaction receipt');
  }

  // ignore: unused_element
  int _parseAuctionIdFromReceipt(Map<String, dynamic> receipt) {
    final logs = receipt['logs'] as List<dynamic>?;
    if (logs != null) {
      for (final log in logs) {
        final address = log['address']?.toString().toLowerCase();
        if (address == ContractConfig.logoAuctionAddress.toLowerCase()) {
          final topics = log['topics'] as List<dynamic>?;
          if (topics != null && topics.length >= 2) {
             // topic 1 is the auctionId in AuctionCreated event
             final auctionIdHex = topics[1].toString();
             return int.parse(auctionIdHex.replaceFirst('0x', ''), radix: 16);
          }
        }
      }
    }
    throw Exception('Could not find Auction ID in transaction receipt');
  }

  // ignore: unused_element
  String _encodeApproveCall(String spender, BigInt tokenId) {
    const selector = '095ea7b3';
    final spenderArg = spender.replaceFirst('0x', '').toLowerCase().padLeft(64, '0');
    final tokenIdArg = tokenId.toRadixString(16).padLeft(64, '0');
    return '0x$selector$spenderArg$tokenIdArg';
  }

  // ignore: unused_element
  String _encodeCreateAuctionCall(int tokenId, String creator, BigInt startingPrice, BigInt reservePrice, int durationSeconds) {
    const selector = 'f84b2591';
    final tokenIdArg = BigInt.from(tokenId).toRadixString(16).padLeft(64, '0');
    final creatorArg = creator.replaceFirst('0x', '').toLowerCase().padLeft(64, '0');
    final startPriceArg = startingPrice.toRadixString(16).padLeft(64, '0');
    final reservePriceArg = reservePrice.toRadixString(16).padLeft(64, '0');
    final durationArg = BigInt.from(durationSeconds).toRadixString(16).padLeft(64, '0');
    return '0x$selector$tokenIdArg$creatorArg$startPriceArg$reservePriceArg$durationArg';
  }
}
