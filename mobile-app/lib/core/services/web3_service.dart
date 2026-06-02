import 'package:flutter/foundation.dart';
import 'package:nft_logo_marketplace/shared/models/logo_nft.dart';
import 'package:nft_logo_marketplace/shared/models/auction.dart';
import 'package:nft_logo_marketplace/shared/models/user_model.dart';

// Export the platform-specific implementation
export 'web3_service_stub.dart'
    if (dart.library.html) 'web3_service_web.dart'
    if (dart.library.io) 'web3_service_mobile.dart';

/// Base abstract class for Web3 Service
/// Implemented differently for Web and Mobile
abstract class Web3ServiceBase extends ChangeNotifier {
  // Sepolia Network Config
  static const int sepoliaChainId = 11155111;
  static const String sepoliaChainIdHex = '0xaa36a7';
  static const String sepoliaRpcUrl = 'https://rpc.sepolia.org';
  static const String sepoliaBlockExplorer = 'https://sepolia.etherscan.io';

  // Fee constants
  static const double platformFeePercentage = 2.0;
  static const double royaltyPercentage = 5.0;

  // Abstract getters - harus di-implement platform
  String? get currentAddress;
  String? get contractOwner;
  double get balance;
  bool get isConnected;
  bool get isInitialized;
  int? get chainId;
  bool get isOnSepolia;
  bool get isMetaMaskInstalled;
  bool get isMobileDevice;
  String get connectionType;
  List<LogoNFT> get allLogos;
  List<Auction> get allAuctions;
  UserModel? get currentUser;

  // Filtered getters
  List<LogoNFT> get logosForSale;
  List<LogoNFT> get logosInAuction;
  List<Auction> get activeAuctions;

  // Abstract methods - harus di-implement per platform
  Future<void> initialize();
  Future<bool> connectWallet({String walletName = 'metamask', bool restoreSession = false});
  Future<bool> connectBrowserWallet({String walletName = 'metamask', bool restoreSession = false});
  Future<bool> connectMobileWallet({String walletName = 'metamask', bool restoreSession = false});
  void openInMetaMaskBrowser();
  void disconnectWallet();
  Future<bool> switchToSepolia();

  // NFT Operations
  Future<LogoNFT> mintLogo({
    required String name,
    required String description,
    required String imageUrl,
    required double price,
    String category = 'Technology',
    String? metadataUrl,
    String? copyrightHash,
    String? hashAlgorithm,
  });
  Future<void> listForSale(int tokenId, double price);
  Future<void> cancelListing(int tokenId);
  Future<void> buyLogo(int tokenId);

  // Admin Operations
  Future<void> approveNFT(int tokenId);
  Future<void> rejectNFT(int tokenId);
  Future<void> disableNFT(int tokenId);

  // Auction Operations have been migrated to FirestoreService
  // No longer implemented on-chain, except for final payment transfer
  Future<String> payAuctionWinner(String sellerWallet, double amountInEth);
  
  // Re-adding on-chain auction creation as per the reference flow
  Future<String> createAuctionOnChain({
    required int tokenId,
    required String creatorAddress,
    required double startingPrice,
    required int durationSeconds,
  });

  // Query methods
  List<LogoNFT> getMyLogos();
  List<LogoNFT> getMyCreatedLogos();
  Auction? getAuctionForLogo(int tokenId);
  Map<String, dynamic> verifyCopyright(int tokenId);
  Future<void> addBalance(double amount);
  
  // Demo mode - for testing without real wallet
  void setDemoAddress(String address, double balance) {
    // Default implementation does nothing, override in mobile
  }

  // Load data from blockchain - default no-op, override in platform implementations
  Future<void> loadFromChain() async {
    // Default implementation does nothing
  }
}

/// Seller Info model
class SellerInfo {
  final String address;
  final int totalSales;
  final double totalVolume;
  final int totalLogosCreated;
  final double totalRoyaltiesEarned;
  final double rating;
  final int ratingCount;
  final bool isActive;
  final DateTime registeredAt;

  SellerInfo({
    required this.address,
    required this.totalSales,
    required this.totalVolume,
    required this.totalLogosCreated,
    required this.totalRoyaltiesEarned,
    required this.rating,
    required this.ratingCount,
    required this.isActive,
    required this.registeredAt,
  });

  SellerInfo copyWith({
    String? address,
    int? totalSales,
    double? totalVolume,
    int? totalLogosCreated,
    double? totalRoyaltiesEarned,
    double? rating,
    int? ratingCount,
    bool? isActive,
    DateTime? registeredAt,
  }) {
    return SellerInfo(
      address: address ?? this.address,
      totalSales: totalSales ?? this.totalSales,
      totalVolume: totalVolume ?? this.totalVolume,
      totalLogosCreated: totalLogosCreated ?? this.totalLogosCreated,
      totalRoyaltiesEarned: totalRoyaltiesEarned ?? this.totalRoyaltiesEarned,
      rating: rating ?? this.rating,
      ratingCount: ratingCount ?? this.ratingCount,
      isActive: isActive ?? this.isActive,
      registeredAt: registeredAt ?? this.registeredAt,
    );
  }

  String get addressShort {
    if (address.length <= 10) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
  }
}

/// Sale Record model
class SaleRecord {
  final int tokenId;
  final String seller;
  final String buyer;
  final double price;
  final double royaltyPaid;
  final double platformFee;
  final DateTime timestamp;

  SaleRecord({
    required this.tokenId,
    required this.seller,
    required this.buyer,
    required this.price,
    this.royaltyPaid = 0,
    this.platformFee = 0,
    required this.timestamp,
  });
}
