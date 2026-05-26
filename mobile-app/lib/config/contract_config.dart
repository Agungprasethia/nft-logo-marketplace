/// Configuration for deployed smart contracts on Sepolia testnet
class ContractConfig {
  // Network Configuration
  static const int chainId = 11155111;
  static const String chainIdHex = '0xaa36a7';
  static const String networkName = 'Sepolia Testnet';
  static const String rpcUrl = 'https://ethereum-sepolia-rpc.publicnode.com';
  
  // Block Explorers - Primary and Fallback
  static const String blockExplorer = 'https://sepolia.etherscan.io';
  static const String blockExplorerAlt = 'https://sepolia.blockscout.com';
  static const String blockExplorerAlchemy = 'https://sepolia.explorer.alchemy.com';
  
  // WalletConnect Configuration
  static const String walletConnectProjectId = '6d5b8d463b521aad9b0ca75a62ebdad2';
  
  // Contract Addresses - Deployed Just Now (Multi-Seller + Creator Version)
  static const String logoNFTAddress = '0xe234f6844024eaE1EAf220E01BDC942B20431355';
  static const String logoAuctionAddress = '0xFcB81D253f0eAaEF600A6D76C1cfed643861cAd8';
  
  // Fee Configuration
  static const double platformFeePercentage = 2.0;
  static const double royaltyPercentage = 5.0;
  
  // Helper methods for Etherscan (primary)
  static String getEtherscanTokenUrl(int tokenId) {
    return '$blockExplorer/token/$logoNFTAddress?a=$tokenId';
  }
  
  static String getEtherscanTxUrl(String txHash) {
    return '$blockExplorer/tx/$txHash';
  }
  
  static String getEtherscanAddressUrl(String address) {
    return '$blockExplorer/address/$address';
  }
  
  // Helper methods for Blockscout (fallback)
  static String getBlockscoutTxUrl(String txHash) {
    return '$blockExplorerAlt/tx/$txHash';
  }
  
  static String getBlockscoutAddressUrl(String address) {
    return '$blockExplorerAlt/address/$address';
  }
  
  static String getBlockscoutTokenUrl(int tokenId) {
    return '$blockExplorerAlt/token/$logoNFTAddress/instance/$tokenId';
  }
  
  // Get all explorer URLs for a transaction
  static List<Map<String, String>> getTxExplorerUrls(String txHash) {
    return [
      {'name': 'Etherscan', 'url': getEtherscanTxUrl(txHash)},
      {'name': 'Blockscout', 'url': getBlockscoutTxUrl(txHash)},
      {'name': 'Alchemy', 'url': '$blockExplorerAlchemy/tx/$txHash'},
    ];
  }
}
