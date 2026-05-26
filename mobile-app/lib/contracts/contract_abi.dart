// ABI definitions for LogoNFT and LogoAuction contracts
// These are used to interact with deployed smart contracts on Sepolia

class ContractABI {
  /// LogoNFT Contract ABI - key functions
  static const String logoNFTABI = '''[
    {
      "inputs": [
        {"internalType": "string", "name": "_name", "type": "string"},
        {"internalType": "string", "name": "_description", "type": "string"},
        {"internalType": "string", "name": "_imageHash", "type": "string"},
        {"internalType": "uint256", "name": "_price", "type": "uint256"}
      ],
      "name": "mint",
      "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
      "stateMutability": "nonpayable",
      "type": "function"
    },
    {
      "inputs": [
        {"internalType": "uint256", "name": "_tokenId", "type": "uint256"},
        {"internalType": "uint256", "name": "_price", "type": "uint256"}
      ],
      "name": "listForSale",
      "outputs": [],
      "stateMutability": "nonpayable",
      "type": "function"
    },
    {
      "inputs": [{"internalType": "uint256", "name": "_tokenId", "type": "uint256"}],
      "name": "cancelListing",
      "outputs": [],
      "stateMutability": "nonpayable",
      "type": "function"
    },
    {
      "inputs": [{"internalType": "uint256", "name": "_tokenId", "type": "uint256"}],
      "name": "buy",
      "outputs": [],
      "stateMutability": "payable",
      "type": "function"
    },
    {
      "inputs": [{"internalType": "uint256", "name": "_tokenId", "type": "uint256"}],
      "name": "getLogo",
      "outputs": [
        {
          "components": [
            {"internalType": "uint256", "name": "tokenId", "type": "uint256"},
            {"internalType": "string", "name": "name", "type": "string"},
            {"internalType": "string", "name": "description", "type": "string"},
            {"internalType": "string", "name": "imageHash", "type": "string"},
            {"internalType": "address", "name": "creator", "type": "address"},
            {"internalType": "address", "name": "owner", "type": "address"},
            {"internalType": "uint256", "name": "createdAt", "type": "uint256"},
            {"internalType": "uint256", "name": "price", "type": "uint256"},
            {"internalType": "bool", "name": "isForSale", "type": "bool"},
            {"internalType": "bool", "name": "isInAuction", "type": "bool"}
          ],
          "internalType": "struct LogoNFT.Logo",
          "name": "",
          "type": "tuple"
        }
      ],
      "stateMutability": "view",
      "type": "function"
    },
    {
      "inputs": [],
      "name": "totalSupply",
      "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
      "stateMutability": "view",
      "type": "function"
    },
    {
      "inputs": [{"internalType": "address", "name": "_owner", "type": "address"}],
      "name": "getOwnerTokens",
      "outputs": [{"internalType": "uint256[]", "name": "", "type": "uint256[]"}],
      "stateMutability": "view",
      "type": "function"
    },
    {
      "inputs": [],
      "name": "getLogosForSale",
      "outputs": [{"internalType": "uint256[]", "name": "", "type": "uint256[]"}],
      "stateMutability": "view",
      "type": "function"
    },
    {
      "inputs": [
        {"internalType": "uint256", "name": "_tokenId", "type": "uint256"},
        {"internalType": "bool", "name": "_status", "type": "bool"}
      ],
      "name": "setAuctionStatus",
      "outputs": [],
      "stateMutability": "nonpayable",
      "type": "function"
    },
    {
      "inputs": [{"internalType": "uint256", "name": "_tokenId", "type": "uint256"}],
      "name": "verifyCopyright",
      "outputs": [
        {"internalType": "address", "name": "creator", "type": "address"},
        {"internalType": "address", "name": "currentOwner", "type": "address"},
        {"internalType": "uint256", "name": "createdAt", "type": "uint256"},
        {"internalType": "string", "name": "imageHash", "type": "string"},
        {"internalType": "uint256", "name": "salesCount", "type": "uint256"}
      ],
      "stateMutability": "view",
      "type": "function"
    },
    {
      "anonymous": false,
      "inputs": [
        {"indexed": true, "internalType": "uint256", "name": "tokenId", "type": "uint256"},
        {"indexed": true, "internalType": "address", "name": "creator", "type": "address"},
        {"indexed": false, "internalType": "string", "name": "name", "type": "string"},
        {"indexed": false, "internalType": "string", "name": "imageHash", "type": "string"}
      ],
      "name": "LogoMinted",
      "type": "event"
    }
  ]''';

  /// LogoAuction Contract ABI - key functions
  static const String logoAuctionABI = '''[
    {
      "inputs": [
        {"internalType": "uint256", "name": "_tokenId", "type": "uint256"},
        {"internalType": "address", "name": "_creator", "type": "address"},
        {"internalType": "uint256", "name": "_startingPrice", "type": "uint256"},
        {"internalType": "uint256", "name": "_reservePrice", "type": "uint256"},
        {"internalType": "uint256", "name": "_duration", "type": "uint256"}
      ],
      "name": "createAuction",
      "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
      "stateMutability": "nonpayable",
      "type": "function"
    },
    {
      "inputs": [{"internalType": "uint256", "name": "_auctionId", "type": "uint256"}],
      "name": "placeBid",
      "outputs": [],
      "stateMutability": "payable",
      "type": "function"
    },
    {
      "inputs": [{"internalType": "uint256", "name": "_auctionId", "type": "uint256"}],
      "name": "endAuction",
      "outputs": [],
      "stateMutability": "nonpayable",
      "type": "function"
    },
    {
      "inputs": [{"internalType": "uint256", "name": "_auctionId", "type": "uint256"}],
      "name": "cancelAuction",
      "outputs": [],
      "stateMutability": "nonpayable",
      "type": "function"
    },
    {
      "inputs": [],
      "name": "withdraw",
      "outputs": [],
      "stateMutability": "nonpayable",
      "type": "function"
    },
    {
      "inputs": [{"internalType": "uint256", "name": "_auctionId", "type": "uint256"}],
      "name": "getAuction",
      "outputs": [
        {
          "components": [
            {"internalType": "uint256", "name": "auctionId", "type": "uint256"},
            {"internalType": "uint256", "name": "tokenId", "type": "uint256"},
            {"internalType": "address", "name": "seller", "type": "address"},
            {"internalType": "address", "name": "creator", "type": "address"},
            {"internalType": "uint256", "name": "startingPrice", "type": "uint256"},
            {"internalType": "uint256", "name": "reservePrice", "type": "uint256"},
            {"internalType": "uint256", "name": "highestBid", "type": "uint256"},
            {"internalType": "address", "name": "highestBidder", "type": "address"},
            {"internalType": "uint256", "name": "startTime", "type": "uint256"},
            {"internalType": "uint256", "name": "endTime", "type": "uint256"},
            {"internalType": "bool", "name": "isActive", "type": "bool"},
            {"internalType": "bool", "name": "isEnded", "type": "bool"},
            {"internalType": "bool", "name": "reserveMet", "type": "bool"}
          ],
          "internalType": "struct LogoAuction.Auction",
          "name": "",
          "type": "tuple"
        }
      ],
      "stateMutability": "view",
      "type": "function"
    },
    {
      "inputs": [],
      "name": "getActiveAuctions",
      "outputs": [{"internalType": "uint256[]", "name": "", "type": "uint256[]"}],
      "stateMutability": "view",
      "type": "function"
    },
    {
      "inputs": [{"internalType": "uint256", "name": "_tokenId", "type": "uint256"}],
      "name": "getActiveAuctionForToken",
      "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
      "stateMutability": "view",
      "type": "function"
    },
    {
      "anonymous": false,
      "inputs": [
        {"indexed": true, "internalType": "uint256", "name": "auctionId", "type": "uint256"},
        {"indexed": true, "internalType": "uint256", "name": "tokenId", "type": "uint256"},
        {"indexed": true, "internalType": "address", "name": "seller", "type": "address"},
        {"indexed": false, "internalType": "uint256", "name": "startingPrice", "type": "uint256"},
        {"indexed": false, "internalType": "uint256", "name": "reservePrice", "type": "uint256"},
        {"indexed": false, "internalType": "uint256", "name": "endTime", "type": "uint256"}
      ],
      "name": "AuctionCreated",
      "type": "event"
    },
    {
      "anonymous": false,
      "inputs": [
        {"indexed": true, "internalType": "uint256", "name": "auctionId", "type": "uint256"},
        {"indexed": true, "internalType": "address", "name": "bidder", "type": "address"},
        {"indexed": false, "internalType": "uint256", "name": "amount", "type": "uint256"}
      ],
      "name": "BidPlaced",
      "type": "event"
    }
  ]''';
}
