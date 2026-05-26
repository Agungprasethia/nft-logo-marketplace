// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title LogoAuction
 * @dev Auction contract untuk Logo NFT dengan Multi-Seller Support
 * Sistem lelang dengan fitur bidding, automatic transfer, dan royalty
 * 
 * FITUR MULTI-SELLER:
 * - Setiap seller bisa membuat auction
 * - Tracking auction per seller
 * - Royalty payment to original creator
 * - Commission fee untuk platform
 * - Auto Transfer NFT (Escrow)
 */
contract LogoAuction is ReentrancyGuard {
    
    uint256 public constant PLATFORM_FEE_PERCENTAGE = 2; // 2% platform fee
    uint256 public constant ROYALTY_PERCENTAGE = 5; // 5% royalty untuk creator
    address public platformWallet;
    IERC721 public nftContract; // Reference to the NFT Contract
    
    struct Auction {
        uint256 auctionId;
        uint256 tokenId;
        address seller;
        address creator; // Original creator for royalty
        uint256 startingPrice;
        uint256 reservePrice; // Minimum price to be met
        uint256 highestBid;
        address highestBidder;
        uint256 startTime;
        uint256 endTime;
        bool isActive;
        bool isEnded;
        bool reserveMet;
    }
    
    struct Bid {
        address bidder;
        uint256 amount;
        uint256 timestamp;
    }
    
    struct SellerAuctionStats {
        uint256 totalAuctions;
        uint256 successfulAuctions;
        uint256 totalVolume;
        uint256 cancelledAuctions;
    }
    
    uint256 private _auctionIdCounter;
    
    mapping(uint256 => Auction) public auctions;
    mapping(uint256 => Bid[]) public auctionBids;
    mapping(uint256 => uint256) public tokenToAuction;
    mapping(address => uint256) public pendingReturns;
    
    // Multi-seller mappings
    mapping(address => uint256[]) public sellerAuctions;
    mapping(address => SellerAuctionStats) public sellerStats;
    
    // Events
    event AuctionCreated(
        uint256 indexed auctionId, 
        uint256 indexed tokenId, 
        address indexed seller, 
        uint256 startingPrice, 
        uint256 reservePrice,
        uint256 endTime
    );
    event BidPlaced(uint256 indexed auctionId, address indexed bidder, uint256 amount);
    event AuctionEnded(uint256 indexed auctionId, address winner, uint256 winningBid, bool reserveMet);
    event AuctionCancelled(uint256 indexed auctionId, address indexed seller);
    event RoyaltyPaid(uint256 indexed auctionId, address indexed creator, uint256 amount);
    event PlatformFeePaid(uint256 indexed auctionId, uint256 amount);
    event BidRefunded(address indexed bidder, uint256 amount);
    
    constructor(address _nftContract) {
        platformWallet = msg.sender;
        nftContract = IERC721(_nftContract);
    }
    
    modifier auctionExists(uint256 _auctionId) {
        require(_auctionId > 0 && _auctionId <= _auctionIdCounter, "Auction does not exist");
        _;
    }
    
    modifier onlyAuctionSeller(uint256 _auctionId) {
        require(auctions[_auctionId].seller == msg.sender, "Not the seller");
        _;
    }
    
    /**
     * @dev Create a new auction (any seller can create)
     * Requires user to approve this contract first!
     */
    function createAuction(
        uint256 _tokenId,
        address _creator, // Original creator for royalty
        uint256 _startingPrice,
        uint256 _reservePrice,
        uint256 _duration
    ) public nonReentrant returns (uint256) {
        require(_duration >= 1 hours, "Duration too short");
        require(_duration <= 30 days, "Duration too long");
        require(tokenToAuction[_tokenId] == 0, "Token already in auction");
        require(_startingPrice > 0, "Starting price must be > 0");
        require(_reservePrice >= _startingPrice, "Reserve must be >= starting price");
        
        // Transfer NFT to this contract (Escrow)
        nftContract.transferFrom(msg.sender, address(this), _tokenId);
        
        _auctionIdCounter++;
        uint256 newAuctionId = _auctionIdCounter;
        
        auctions[newAuctionId] = Auction({
            auctionId: newAuctionId,
            tokenId: _tokenId,
            seller: msg.sender,
            creator: _creator,
            startingPrice: _startingPrice,
            reservePrice: _reservePrice,
            highestBid: 0,
            highestBidder: address(0),
            startTime: block.timestamp,
            endTime: block.timestamp + _duration,
            isActive: true,
            isEnded: false,
            reserveMet: false
        });
        
        tokenToAuction[_tokenId] = newAuctionId;
        sellerAuctions[msg.sender].push(newAuctionId);
        sellerStats[msg.sender].totalAuctions++;
        
        emit AuctionCreated(newAuctionId, _tokenId, msg.sender, _startingPrice, _reservePrice, block.timestamp + _duration);
        
        return newAuctionId;
    }
    
    /**
     * @dev Place a bid on an auction
     */
    function placeBid(uint256 _auctionId) public payable auctionExists(_auctionId) nonReentrant {
        Auction storage auction = auctions[_auctionId];
        
        require(auction.isActive, "Auction not active");
        require(!auction.isEnded, "Auction already ended");
        require(block.timestamp < auction.endTime, "Auction expired");
        require(msg.sender != auction.seller, "Seller cannot bid");
        require(msg.value > auction.highestBid, "Bid too low");
        require(msg.value >= auction.startingPrice, "Below starting price");
        
        // Return previous highest bid
        if (auction.highestBidder != address(0)) {
            pendingReturns[auction.highestBidder] += auction.highestBid;
        }
        
        auction.highestBid = msg.value;
        auction.highestBidder = msg.sender;
        
        // Check if reserve is met
        if (msg.value >= auction.reservePrice) {
            auction.reserveMet = true;
        }
        
        auctionBids[_auctionId].push(Bid({
            bidder: msg.sender,
            amount: msg.value,
            timestamp: block.timestamp
        }));
        
        emit BidPlaced(_auctionId, msg.sender, msg.value);
    }
    
    /**
     * @dev End an auction and distribute funds
     */
    function endAuction(uint256 _auctionId) public auctionExists(_auctionId) nonReentrant {
        Auction storage auction = auctions[_auctionId];
        
        require(auction.isActive, "Auction not active");
        require(!auction.isEnded, "Already ended");
        require(
            block.timestamp >= auction.endTime || msg.sender == auction.seller,
            "Auction not yet ended"
        );
        
        auction.isActive = false;
        auction.isEnded = true;
        tokenToAuction[auction.tokenId] = 0;
        
        bool success = auction.highestBidder != address(0) && auction.reserveMet;
        
        if (success) {
            uint256 totalAmount = auction.highestBid;
            
            // Calculate fees
            uint256 platformFee = (totalAmount * PLATFORM_FEE_PERCENTAGE) / 100;
            uint256 royalty = 0;
            
            // Only pay royalty if seller is not the creator
            if (auction.seller != auction.creator) {
                royalty = (totalAmount * ROYALTY_PERCENTAGE) / 100;
            }
            
            uint256 sellerAmount = totalAmount - platformFee - royalty;
            
            // Transfer NFT to Winner
            nftContract.safeTransferFrom(address(this), auction.highestBidder, auction.tokenId);
            
            // Transfer to seller
            payable(auction.seller).transfer(sellerAmount);
            
            // Transfer platform fee
            payable(platformWallet).transfer(platformFee);
            emit PlatformFeePaid(_auctionId, platformFee);
            
            // Transfer royalty to creator
            if (royalty > 0) {
                payable(auction.creator).transfer(royalty);
                emit RoyaltyPaid(_auctionId, auction.creator, royalty);
            }
            
            // Update seller stats
            sellerStats[auction.seller].successfulAuctions++;
            sellerStats[auction.seller].totalVolume += totalAmount;
        } else {
            // No winner or reserve not met
            // Return NFT to Seller
             nftContract.safeTransferFrom(address(this), auction.seller, auction.tokenId);
             
            if (auction.highestBidder != address(0)) {
                // Return bid to highest bidder if reserve not met
                pendingReturns[auction.highestBidder] += auction.highestBid;
            }
        }
        
        emit AuctionEnded(_auctionId, auction.highestBidder, auction.highestBid, success);
    }
    
    /**
     * @dev Cancel an auction (only if no bids or reserve not met)
     */
    function cancelAuction(uint256 _auctionId) public auctionExists(_auctionId) onlyAuctionSeller(_auctionId) nonReentrant {
        Auction storage auction = auctions[_auctionId];
        
        require(auction.isActive, "Auction not active");
        require(!auction.reserveMet, "Cannot cancel - reserve met");
        
        // Return any existing bid
        if (auction.highestBidder != address(0)) {
            pendingReturns[auction.highestBidder] += auction.highestBid;
        }
        
        auction.isActive = false;
        auction.isEnded = true;
        tokenToAuction[auction.tokenId] = 0;
        
        // Return NFT to Seller
        nftContract.safeTransferFrom(address(this), auction.seller, auction.tokenId);
        
        sellerStats[msg.sender].cancelledAuctions++;
        
        emit AuctionCancelled(_auctionId, msg.sender);
    }
    
    /**
     * @dev Withdraw pending returns (outbid refunds)
     */
    function withdraw() public nonReentrant {
        uint256 amount = pendingReturns[msg.sender];
        require(amount > 0, "Nothing to withdraw");
        
        pendingReturns[msg.sender] = 0;
        payable(msg.sender).transfer(amount);
        
        emit BidRefunded(msg.sender, amount);
    }
    
    /**
     * @dev Update platform wallet (only current platform wallet)
     */
    function updatePlatformWallet(address _newWallet) public {
        require(msg.sender == platformWallet, "Not authorized");
        require(_newWallet != address(0), "Invalid address");
        platformWallet = _newWallet;
    }
    
    // ============ View Functions ============
    
    function getAuction(uint256 _auctionId) public view auctionExists(_auctionId) returns (Auction memory) {
        return auctions[_auctionId];
    }
    
    function getAuctionBids(uint256 _auctionId) public view returns (Bid[] memory) {
        return auctionBids[_auctionId];
    }
    
    function getActiveAuctionForToken(uint256 _tokenId) public view returns (uint256) {
        return tokenToAuction[_tokenId];
    }
    
    function getSellerAuctions(address _seller) public view returns (uint256[] memory) {
        return sellerAuctions[_seller];
    }
    
    function getSellerStats(address _seller) public view returns (SellerAuctionStats memory) {
        return sellerStats[_seller];
    }
    
    function getActiveAuctions() public view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 1; i <= _auctionIdCounter; i++) {
            if (auctions[i].isActive && !auctions[i].isEnded) {
                count++;
            }
        }
        
        uint256[] memory active = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 1; i <= _auctionIdCounter; i++) {
            if (auctions[i].isActive && !auctions[i].isEnded) {
                active[index] = i;
                index++;
            }
        }
        
        return active;
    }
    
    function getAuctionTimeRemaining(uint256 _auctionId) public view auctionExists(_auctionId) returns (uint256) {
        Auction memory auction = auctions[_auctionId];
        if (!auction.isActive || auction.isEnded || block.timestamp >= auction.endTime) {
            return 0;
        }
        return auction.endTime - block.timestamp;
    }
    
    function totalAuctions() public view returns (uint256) {
        return _auctionIdCounter;
    }
    
    function getBidCount(uint256 _auctionId) public view returns (uint256) {
        return auctionBids[_auctionId].length;
    }
}
