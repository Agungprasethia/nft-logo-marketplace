const { ethers } = require("hardhat");

async function main() {
    const rpcUrl = "https://ethereum-sepolia-rpc.publicnode.com";
    const provider = new ethers.JsonRpcProvider(rpcUrl);

    const logoNFTAddress = "0xe234f6844024eaE1EAf220E01BDC942B20431355";
    const logoAuctionAddress = "0xFcB81D253f0eAaEF600A6D76C1cfed643861cAd8";

    console.log("Fetching events...");

    // We can use generic ERC721 Transfer event for Mint (from 0x0 to user)
    const transferEventSignature = "Transfer(address,address,uint256)";
    
    // For LogoAuction, let's just get the latest logs to the contract address
    
    const blockNumber = await provider.getBlockNumber();
    const fromBlock = Math.max(0, blockNumber - 500000); // Last 500k blocks

    // Fetching Transfer events for LogoNFT
    const nftLogs = await provider.getLogs({
        address: logoNFTAddress,
        fromBlock: fromBlock,
        toBlock: 'latest',
        topics: [
            ethers.id(transferEventSignature),
            ethers.zeroPadValue("0x0000000000000000000000000000000000000000", 32) // from zero address = mint
        ]
    });

    console.log(`Found ${nftLogs.length} Mint transactions on LogoNFT`);
    if (nftLogs.length > 0) {
        console.log("Latest Mint Transaction Hash:", nftLogs[nftLogs.length - 1].transactionHash);
    }

    // Since LogoAuction events might have specific signatures, let's just fetch all transactions to the auction contract
    // Wait, getLogs requires topics. Let's just use the known signatures if possible.
    // BidPlaced(uint256 auctionId, address bidder, uint256 amount)
    // AuctionEnded(uint256 auctionId, address winner, uint256 amount)
    const bidPlacedSig = ethers.id("BidPlaced(uint256,address,uint256)");
    const auctionEndedSig = ethers.id("AuctionEnded(uint256,address,uint256)");

    const bidLogs = await provider.getLogs({
        address: logoAuctionAddress,
        fromBlock: fromBlock,
        toBlock: 'latest',
        topics: [bidPlacedSig]
    });
    console.log(`Found ${bidLogs.length} Bid transactions on LogoAuction`);
    if (bidLogs.length > 0) {
        console.log("Latest Bid Transaction Hash:", bidLogs[bidLogs.length - 1].transactionHash);
    }

    const endLogs = await provider.getLogs({
        address: logoAuctionAddress,
        fromBlock: fromBlock,
        toBlock: 'latest',
        topics: [auctionEndedSig]
    });
    console.log(`Found ${endLogs.length} EndAuction transactions on LogoAuction`);
    if (endLogs.length > 0) {
        console.log("Latest EndAuction Transaction Hash:", endLogs[endLogs.length - 1].transactionHash);
    }
}

main().catch(console.error);
