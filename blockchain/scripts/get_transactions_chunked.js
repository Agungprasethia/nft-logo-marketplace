const { ethers } = require("hardhat");

async function main() {
    const rpcUrl = "https://ethereum-sepolia-rpc.publicnode.com";
    const provider = new ethers.JsonRpcProvider(rpcUrl);

    const logoNFTAddress = "0xe234f6844024eaE1EAf220E01BDC942B20431355";
    const logoAuctionAddress = "0xFcB81D253f0eAaEF600A6D76C1cfed643861cAd8";

    // Deployment block from previous error: 0xa76726 (10970918)
    const startBlock = 10970918;
    const currentBlock = await provider.getBlockNumber();
    console.log(`Searching from block ${startBlock} to ${currentBlock}...`);

    const transferEventSignature = "Transfer(address,address,uint256)";
    const bidPlacedSig = ethers.id("BidPlaced(uint256,address,uint256)");
    const auctionEndedSig = ethers.id("AuctionEnded(uint256,address,uint256,bool)"); // Fixed signature

    let nftLogs = [];
    let bidLogs = [];
    let endLogs = [];

    const chunkSize = 40000;
    
    for (let i = startBlock; i <= currentBlock; i += chunkSize) {
        let fromBlock = i;
        let toBlock = Math.min(i + chunkSize - 1, currentBlock);
        console.log(`Querying blocks ${fromBlock} to ${toBlock}...`);

        try {
            const chunkNftLogs = await provider.getLogs({
                address: logoNFTAddress,
                fromBlock: fromBlock,
                toBlock: toBlock,
                topics: [
                    ethers.id(transferEventSignature),
                    ethers.zeroPadValue("0x0000000000000000000000000000000000000000", 32)
                ]
            });
            nftLogs = nftLogs.concat(chunkNftLogs);

            const chunkBidLogs = await provider.getLogs({
                address: logoAuctionAddress,
                fromBlock: fromBlock,
                toBlock: toBlock,
                topics: [bidPlacedSig]
            });
            bidLogs = bidLogs.concat(chunkBidLogs);

            const chunkEndLogs = await provider.getLogs({
                address: logoAuctionAddress,
                fromBlock: fromBlock,
                toBlock: toBlock,
                topics: [auctionEndedSig]
            });
            endLogs = endLogs.concat(chunkEndLogs);
        } catch (e) {
            console.error(`Error querying blocks ${fromBlock}-${toBlock}:`, e.message);
        }
    }

    console.log(`\n--- RESULTS ---`);
    console.log(`Found ${nftLogs.length} Mint transactions.`);
    if (nftLogs.length > 0) {
        console.log("Latest Mint Transaction Hash:", nftLogs[nftLogs.length - 1].transactionHash);
    }

    console.log(`Found ${bidLogs.length} Bid transactions.`);
    if (bidLogs.length > 0) {
        console.log("Latest Bid Transaction Hash:", bidLogs[bidLogs.length - 1].transactionHash);
    }

    console.log(`Found ${endLogs.length} EndAuction transactions.`);
    if (endLogs.length > 0) {
        console.log("Latest EndAuction Transaction Hash:", endLogs[endLogs.length - 1].transactionHash);
    }
}

main().catch(console.error);
