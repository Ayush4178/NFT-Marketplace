// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract NFTMarketplace is ERC721URIStorage, Ownable, ReentrancyGuard {
    uint256 private _tokenIdCounter;
    uint256 private _listingIdCounter;
    
    // Marketplace fee percentage (2.5%)
    uint256 public marketplaceFee = 250; // 250 basis points = 2.5%
    uint256 public constant MAX_FEE = 1000; // 10% maximum fee
    
    struct Listing {
        uint256 tokenId;
        address seller;
        uint256 price;
        bool active;
    }
    
    // Mapping from listing ID to Listing
    mapping(uint256 => Listing) public listings;
    
    // Mapping from token ID to listing ID
    mapping(uint256 => uint256) public tokenToListing;
    
    // Events
    event NFTMinted(uint256 indexed tokenId, address indexed to, string tokenURI);
    event NFTListed(uint256 indexed listingId, uint256 indexed tokenId, address indexed seller, uint256 price);
    event NFTSold(uint256 indexed listingId, uint256 indexed tokenId, address indexed buyer, address seller, uint256 price);
    event ListingCancelled(uint256 indexed listingId, uint256 indexed tokenId);
    event MarketplaceFeeUpdated(uint256 newFee);
    
    constructor() ERC721("NFT Marketplace", "NFTM") Ownable(msg.sender) {}
    
    /**
     * @dev Core Function 1: Mint NFT
     * Allows users to mint new NFTs with metadata URI
     * @param to Address to mint the NFT to
     * @param tokenURI Metadata URI for the NFT
     * @return tokenId The ID of the newly minted token
     */
    function mintNFT(address to, string memory tokenURI) public returns (uint256) {
        require(bytes(tokenURI).length > 0, "Token URI cannot be empty");
        require(to != address(0), "Cannot mint to zero address");
        
        uint256 tokenId = _tokenIdCounter;
        _tokenIdCounter++;
        
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, tokenURI);
        
        emit NFTMinted(tokenId, to, tokenURI);
        return tokenId;
    }
    
    /**
     * @dev Core Function 2: List NFT for Sale
     * Allows NFT owners to list their tokens for sale
     * @param tokenId The ID of the token to list
     * @param price The price in wei to list the token for
     * @return listingId The ID of the created listing
     */
    function listNFT(uint256 tokenId, uint256 price) public returns (uint256) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        require(ownerOf(tokenId) == msg.sender, "Only token owner can list");
        require(price > 0, "Price must be greater than zero");
        require(tokenToListing[tokenId] == 0 || !listings[tokenToListing[tokenId]].active, "Token already listed");
        
        // Transfer token to contract for escrow
        _transfer(msg.sender, address(this), tokenId);
        
        uint256 listingId = _listingIdCounter;
        _listingIdCounter++;
        
        listings[listingId] = Listing({
            tokenId: tokenId,
            seller: msg.sender,
            price: price,
            active: true
        });
        
        tokenToListing[tokenId] = listingId;
        
        emit NFTListed(listingId, tokenId, msg.sender, price);
        return listingId;
    }
    
    /**
     * @dev Core Function 3: Buy NFT
     * Allows users to purchase listed NFTs
     * @param listingId The ID of the listing to purchase
     */
    function buyNFT(uint256 listingId) public payable nonReentrant {
        Listing storage listing = listings[listingId];
        
        require(listing.active, "Listing is not active");
        require(msg.value >= listing.price, "Insufficient payment");
        require(msg.sender != listing.seller, "Cannot buy your own NFT");
        
        // Calculate fees
        uint256 fee = (listing.price * marketplaceFee) / 10000;
        uint256 sellerPayment = listing.price - fee;
        
        // Mark listing as inactive
        listing.active = false;
        
        // Transfer NFT to buyer
        _transfer(address(this), msg.sender, listing.tokenId);
        
        // Transfer payments
        payable(listing.seller).transfer(sellerPayment);
        payable(owner()).transfer(fee);
        
        // Refund excess payment
        if (msg.value > listing.price) {
            payable(msg.sender).transfer(msg.value - listing.price);
        }
        
        emit NFTSold(listingId, listing.tokenId, msg.sender, listing.seller, listing.price);
    }
    
    /**
     * @dev Cancel a listing and return NFT to seller
     * @param listingId The ID of the listing to cancel
     */
    function cancelListing(uint256 listingId) public {
        Listing storage listing = listings[listingId];
        
        require(listing.active, "Listing is not active");
        require(listing.seller == msg.sender || msg.sender == owner(), "Only seller or owner can cancel");
        
        listing.active = false;
        
        // Return NFT to seller
        _transfer(address(this), listing.seller, listing.tokenId);
        
        emit ListingCancelled(listingId, listing.tokenId);
    }
    
    /**
     * @dev Update marketplace fee (only owner)
     * @param newFee New fee in basis points (100 = 1%)
     */
    function updateMarketplaceFee(uint256 newFee) public onlyOwner {
        require(newFee <= MAX_FEE, "Fee cannot exceed maximum");
        marketplaceFee = newFee;
        emit MarketplaceFeeUpdated(newFee);
    }
    
    /**
     * @dev Get listing details
     * @param listingId The ID of the listing
     * @return tokenId The ID of the token in the listing
     * @return seller The address of the seller
     * @return price The price of the listing in wei
     * @return active Whether the listing is currently active
     */
    function getListing(uint256 listingId) public view returns (
        uint256 tokenId,
        address seller,
        uint256 price,
        bool active
    ) {
        Listing storage listing = listings[listingId];
        return (listing.tokenId, listing.seller, listing.price, listing.active);
    }
    
    /**
     * @dev Get total number of tokens minted
     */
    function totalSupply() public view returns (uint256) {
        return _tokenIdCounter;
    }
    
    /**
     * @dev Get total number of listings created
     */
    function totalListings() public view returns (uint256) {
        return _listingIdCounter;
    }
    
    /**
     * @dev Withdraw accumulated fees (only owner)
     */
    function withdrawFees() public onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");
        payable(owner()).transfer(balance);
    }
}


