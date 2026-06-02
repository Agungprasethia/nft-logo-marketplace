// Stub implementation - should never be compiled
// This file is only used when neither dart:html nor dart:io are available
import 'package:nft_logo_marketplace/shared/models/logo_nft.dart';
import 'package:nft_logo_marketplace/shared/models/auction.dart';
import 'package:nft_logo_marketplace/shared/models/user_model.dart';
import 'package:nft_logo_marketplace/core/services/web3_service.dart';

class Web3Service extends Web3ServiceBase {
  static Web3Service? _instance;
  static Web3Service get instance => _instance ??= Web3Service._();
  Web3Service._();

  @override String? get currentAddress => null;
  @override String? get contractOwner => null;
  @override double get balance => 0;
  @override bool get isConnected => false;
  @override bool get isInitialized => false;
  @override int? get chainId => null;
  @override bool get isOnSepolia => false;
  @override bool get isMetaMaskInstalled => false;
  @override bool get isMobileDevice => false;
  @override String get connectionType => 'none';
  @override List<LogoNFT> get allLogos => [];
  @override List<Auction> get allAuctions => [];
  @override UserModel? get currentUser => null;
  @override List<LogoNFT> get logosForSale => [];
  @override List<LogoNFT> get logosInAuction => [];
  @override List<Auction> get activeAuctions => [];

  @override Future<void> initialize() async {}
  @override Future<bool> connectWallet({String walletName = 'metamask', bool restoreSession = false}) async => false;
  @override Future<bool> connectBrowserWallet({bool restoreSession = false, String walletName = 'metamask'}) async => false;
  @override Future<bool> connectMobileWallet({String walletName = 'metamask', bool restoreSession = false}) async => false;
  @override void openInMetaMaskBrowser() {}
  @override void disconnectWallet() {}
  @override Future<bool> switchToSepolia() async => false;

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
  }) async => throw UnimplementedError();

  @override Future<void> listForSale(int tokenId, double price) async {}
  @override Future<void> cancelListing(int tokenId) async {}
  @override Future<void> buyLogo(int tokenId) async {}

  @override Future<void> approveNFT(int tokenId) async {}
  @override Future<void> rejectNFT(int tokenId) async {}
  @override Future<void> disableNFT(int tokenId) async {}

  @override Future<String> payAuctionWinner(String sellerWallet, double amountInEth) async => throw UnimplementedError();
  @override Future<String> createAuctionOnChain({required int tokenId, required String creatorAddress, required double startingPrice, required int durationSeconds}) async => throw UnimplementedError();

  @override List<LogoNFT> getMyLogos() => [];
  @override List<LogoNFT> getMyCreatedLogos() => [];
  @override Auction? getAuctionForLogo(int tokenId) => null;
  @override Map<String, dynamic> verifyCopyright(int tokenId) => {};
  @override Future<void> addBalance(double amount) async {}
}
