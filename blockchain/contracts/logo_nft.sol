// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title LogoNFT
 * @dev ERC-721 NFT Contract untuk Logo Marketplace dengan Multi-Seller Support
 * Compatible dengan OpenSea dan marketplace lainnya
 * Includes admin validation system (Pending/Approved/Rejected/Disabled)
 */
contract LogoNFT is ERC721, ERC721URIStorage, ERC721Enumerable, Ownable {
    uint256 private _tokenIdCounter;
    uint256 public constant ROYALTY_PERCENTAGE = 5; // 5% royalty untuk creator
    uint256 public constant PLATFORM_FEE = 2; // 2% platform fee

    // Validation status for admin moderation
    enum ValidationStatus { Pending, Approved, Rejected, Disabled }
    
    struct Logo {
        uint256 tokenId;
        string name;
        string description;
        string imageHash;
        address creator;
        uint256 createdAt;
        uint256 price;
        bool isForSale;
        bool isInAuction;
        ValidationStatus status;
    }
    
    struct Seller {
        address sellerAddress;
        uint256 totalSales;
        uint256 totalVolume;
        uint256 totalLogosCreated;
        uint256 totalRoyaltiesEarned;
        uint256 rating;
        uint256 ratingCount;
        bool isActive;
        uint256 registeredAt;
    }
    
    struct SaleHistory {
        uint256 tokenId;
        address seller;
        address buyer;
        uint256 price;
        uint256 timestamp;
    }
    
    // Mappings
    mapping(uint256 => Logo) public logos;
    mapping(address => uint256[]) public creatorTokens;
    mapping(address => Seller) public sellers;
    mapping(address => bool) public isSeller;
    address[] public allSellers;
    
    // Sale history
    SaleHistory[] public saleHistory;
    mapping(uint256 => uint256[]) public tokenSaleHistory;
    
    // Events
    event LogoMinted(uint256 indexed tokenId, address indexed creator, string name, string imageHash);
    event LogoListedForSale(uint256 indexed tokenId, address indexed seller, uint256 price);
    event LogoSold(uint256 indexed tokenId, address indexed seller, address indexed buyer, uint256 price);
    event ListingCancelled(uint256 indexed tokenId);
    event SellerRegistered(address indexed seller, uint256 timestamp);
    event SellerRated(address indexed seller, address indexed rater, uint256 rating);
    event RoyaltyPaid(uint256 indexed tokenId, address indexed creator, uint256 amount);
    
    // Admin moderation events
    event NFTApproved(uint256 indexed tokenId, uint256 timestamp);
    event NFTRejected(uint256 indexed tokenId, uint256 timestamp);
    event NFTDisabled(uint256 indexed tokenId, uint256 timestamp);
    
    constructor() ERC721("Logo NFT Marketplace", "LOGO") Ownable(msg.sender) {}
    
    // ============ Core Functions ============
    
    function registerAsSeller() public {
        require(!isSeller[msg.sender], "Already registered as seller");
        
        sellers[msg.sender] = Seller({
            sellerAddress: msg.sender,
            totalSales: 0,
            totalVolume: 0,
            totalLogosCreated: 0,
            totalRoyaltiesEarned: 0,
            rating: 0,
            ratingCount: 0,
            isActive: true,
            registeredAt: block.timestamp
        });
        
        isSeller[msg.sender] = true;
        allSellers.push(msg.sender);
        
        emit SellerRegistered(msg.sender, block.timestamp);
    }
    
    function mint(
        string memory _name,
        string memory _description,
        string memory _imageHash,
        uint256 _price
    ) public returns (uint256) {
        if (!isSeller[msg.sender]) {
            registerAsSeller();
        }
        
        _tokenIdCounter++;
        uint256 newTokenId = _tokenIdCounter;
        
        _safeMint(msg.sender, newTokenId);
        _setTokenURI(newTokenId, _imageHash);
        
        logos[newTokenId] = Logo({
            tokenId: newTokenId,
            name: _name,
            description: _description,
            imageHash: _imageHash,
            creator: msg.sender,
            createdAt: block.timestamp,
            price: _price,
            isForSale: false,
            isInAuction: false,
            status: ValidationStatus.Pending
        });
        
        creatorTokens[msg.sender].push(newTokenId);
        sellers[msg.sender].totalLogosCreated++;
        
        emit LogoMinted(newTokenId, msg.sender, _name, _imageHash);
        
        return newTokenId;
    }
    
    function listForSale(uint256 _tokenId, uint256 _price) public {
        require(ownerOf(_tokenId) == msg.sender, "Not the owner");
        require(!logos[_tokenId].isInAuction, "Logo is in auction");
        require(_price > 0, "Price must be greater than 0");
        require(logos[_tokenId].status == ValidationStatus.Approved, "NFT must be approved before listing");
        
        if (!isSeller[msg.sender]) {
            registerAsSeller();
        }
        
        logos[_tokenId].price = _price;
        logos[_tokenId].isForSale = true;
        
        emit LogoListedForSale(_tokenId, msg.sender, _price);
    }
    
    function cancelListing(uint256 _tokenId) public {
        require(ownerOf(_tokenId) == msg.sender, "Not the owner");
        require(logos[_tokenId].isForSale, "Not listed for sale");
        
        logos[_tokenId].isForSale = false;
        
        emit ListingCancelled(_tokenId);
    }
    
    function buy(uint256 _tokenId) public payable {
        require(_ownerOf(_tokenId) != address(0), "Token does not exist");
        require(logos[_tokenId].status == ValidationStatus.Approved, "NFT is not approved");
        
        Logo storage logo = logos[_tokenId];
        address seller = ownerOf(_tokenId);
        
        require(logo.isForSale, "Not for sale");
        require(msg.value >= logo.price, "Insufficient payment");
        require(seller != msg.sender, "Already owned");
        
        address creator = logo.creator;
        uint256 price = logo.price;
        
        // Calculate royalty (only if seller is not the creator)
        uint256 royalty = 0;
        if (seller != creator) {
            royalty = (price * ROYALTY_PERCENTAGE) / 100;
        }
        
        uint256 sellerAmount = price - royalty;
        
        // Update state before transfers
        logo.isForSale = false;
        
        // Transfer NFT using ERC721
        _transfer(seller, msg.sender, _tokenId);
        
        // Pay seller
        payable(seller).transfer(sellerAmount);
        
        // Pay royalty to creator
        if (royalty > 0) {
            payable(creator).transfer(royalty);
            sellers[creator].totalRoyaltiesEarned += royalty;
            emit RoyaltyPaid(_tokenId, creator, royalty);
        }
        
        // Update seller stats
        if (isSeller[seller]) {
            sellers[seller].totalSales++;
            sellers[seller].totalVolume += price;
        }
        
        // Record sale history
        uint256 historyIndex = saleHistory.length;
        saleHistory.push(SaleHistory({
            tokenId: _tokenId,
            seller: seller,
            buyer: msg.sender,
            price: price,
            timestamp: block.timestamp
        }));
        tokenSaleHistory[_tokenId].push(historyIndex);
        
        // Refund excess payment
        if (msg.value > price) {
            payable(msg.sender).transfer(msg.value - price);
        }
        
        emit LogoSold(_tokenId, seller, msg.sender, price);
    }
    
    function setAuctionStatus(uint256 _tokenId, bool _status) public {
        require(ownerOf(_tokenId) == msg.sender, "Not the owner");
        if (_status) {
            require(logos[_tokenId].status == ValidationStatus.Approved, "NFT must be approved for auction");
        }
        logos[_tokenId].isInAuction = _status;
        if (_status) {
            logos[_tokenId].isForSale = false;
        }
    }
    
    function rateSeller(address _seller, uint256 _rating) public {
        require(_rating >= 1 && _rating <= 5, "Rating must be 1-5");
        require(isSeller[_seller], "Not a seller");
        require(_seller != msg.sender, "Cannot rate yourself");
        
        Seller storage seller = sellers[_seller];
        uint256 totalRating = seller.rating * seller.ratingCount + _rating;
        seller.ratingCount++;
        seller.rating = totalRating / seller.ratingCount;
        
        emit SellerRated(_seller, msg.sender, _rating);
    }
    
    // ============ Admin Moderation Functions ============
    
    function approveNFT(uint256 _tokenId) public onlyOwner {
        require(_ownerOf(_tokenId) != address(0), "Token does not exist");
        require(logos[_tokenId].status == ValidationStatus.Pending, "NFT is not pending");
        
        logos[_tokenId].status = ValidationStatus.Approved;
        emit NFTApproved(_tokenId, block.timestamp);
    }
    
    function rejectNFT(uint256 _tokenId) public onlyOwner {
        require(_ownerOf(_tokenId) != address(0), "Token does not exist");
        require(logos[_tokenId].status == ValidationStatus.Pending, "NFT is not pending");
        
        logos[_tokenId].status = ValidationStatus.Rejected;
        emit NFTRejected(_tokenId, block.timestamp);
    }
    
    function disableNFT(uint256 _tokenId) public onlyOwner {
        require(_ownerOf(_tokenId) != address(0), "Token does not exist");
        require(logos[_tokenId].status != ValidationStatus.Disabled, "NFT is already disabled");
        
        logos[_tokenId].status = ValidationStatus.Disabled;
        // Also remove from sale if listed
        logos[_tokenId].isForSale = false;
        emit NFTDisabled(_tokenId, block.timestamp);
    }
    
    function getValidationStatus(uint256 _tokenId) public view returns (ValidationStatus) {
        require(_ownerOf(_tokenId) != address(0), "Token does not exist");
        return logos[_tokenId].status;
    }
    
    function getPendingNFTs() public view returns (uint256[] memory) {
        uint256 total = _tokenIdCounter;
        uint256 count = 0;
        
        for (uint256 i = 1; i <= total; i++) {
            if (_ownerOf(i) != address(0) && logos[i].status == ValidationStatus.Pending) {
                count++;
            }
        }
        
        uint256[] memory pending = new uint256[](count);
        uint256 index = 0;
        
        for (uint256 i = 1; i <= total; i++) {
            if (_ownerOf(i) != address(0) && logos[i].status == ValidationStatus.Pending) {
                pending[index] = i;
                index++;
            }
        }
        
        return pending;
    }
    
    function getApprovedNFTs() public view returns (uint256[] memory) {
        uint256 total = _tokenIdCounter;
        uint256 count = 0;
        
        for (uint256 i = 1; i <= total; i++) {
            if (_ownerOf(i) != address(0) && logos[i].status == ValidationStatus.Approved) {
                count++;
            }
        }
        
        uint256[] memory approved = new uint256[](count);
        uint256 index = 0;
        
        for (uint256 i = 1; i <= total; i++) {
            if (_ownerOf(i) != address(0) && logos[i].status == ValidationStatus.Approved) {
                approved[index] = i;
                index++;
            }
        }
        
        return approved;
    }
    
    // ============ View Functions ============
    
    function getLogo(uint256 _tokenId) public view returns (Logo memory) {
        require(_ownerOf(_tokenId) != address(0), "Token does not exist");
        return logos[_tokenId];
    }
    
    function getLogoOwner(uint256 _tokenId) public view returns (address) {
        return ownerOf(_tokenId);
    }
    
    function getCreatorTokens(address _creator) public view returns (uint256[] memory) {
        return creatorTokens[_creator];
    }
    
    function getSeller(address _sellerAddress) public view returns (Seller memory) {
        return sellers[_sellerAddress];
    }
    
    function getAllSellers() public view returns (address[] memory) {
        return allSellers;
    }
    
    function getSellerCount() public view returns (uint256) {
        return allSellers.length;
    }
    
    function getTokenSaleHistory(uint256 _tokenId) public view returns (SaleHistory[] memory) {
        uint256[] memory indices = tokenSaleHistory[_tokenId];
        SaleHistory[] memory history = new SaleHistory[](indices.length);
        
        for (uint256 i = 0; i < indices.length; i++) {
            history[i] = saleHistory[indices[i]];
        }
        
        return history;
    }
    
    function verifyCopyright(uint256 _tokenId) public view returns (
        address creator,
        address currentOwner,
        uint256 createdAt,
        string memory imageHash,
        uint256 salesCount
    ) {
        require(_ownerOf(_tokenId) != address(0), "Token does not exist");
        Logo memory logo = logos[_tokenId];
        return (
            logo.creator, 
            ownerOf(_tokenId), 
            logo.createdAt, 
            logo.imageHash,
            tokenSaleHistory[_tokenId].length
        );
    }
    
    function getLogosForSale() public view returns (uint256[] memory) {
        uint256 total = _tokenIdCounter;
        uint256 count = 0;
        
        for (uint256 i = 1; i <= total; i++) {
            if (_ownerOf(i) != address(0) && logos[i].isForSale && !logos[i].isInAuction && logos[i].status == ValidationStatus.Approved) {
                count++;
            }
        }
        
        uint256[] memory forSale = new uint256[](count);
        uint256 index = 0;
        
        for (uint256 i = 1; i <= total; i++) {
            if (_ownerOf(i) != address(0) && logos[i].isForSale && !logos[i].isInAuction && logos[i].status == ValidationStatus.Approved) {
                forSale[index] = i;
                index++;
            }
        }
        
        return forSale;
    }
    
    // ============ Required Overrides ============
    
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._increaseBalance(account, value);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721URIStorage, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
