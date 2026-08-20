const { ethers } = require("hardhat");

async function main() {
    const rpcUrl = "https://ethereum-sepolia-rpc.publicnode.com";
    const provider = new ethers.JsonRpcProvider(rpcUrl);

    const logoNFTAddress = "0xe234f6844024eaE1EAf220E01BDC942B20431355";
    const logoAuctionAddress = "0xFcB81D253f0eAaEF600A6D76C1cfed643861cAd8";

    // Deployment block from project: 10970918
    const startBlock = 10970918;
    const currentBlock = await provider.getBlockNumber();
    console.log(`Searching from block ${startBlock} to ${currentBlock}...`);

    // Event signatures
    const mintSig = ethers.id("Transfer(address,address,uint256)");
    const zeroAddr = ethers.zeroPadValue("0x0000000000000000000000000000000000000000", 32);
    
    // LogoNFT events
    const approvedSig = ethers.id("NFTApproved(uint256,uint256)");
    const rejectedSig = ethers.id("NFTRejected(uint256,uint256)");
    const logoSoldSig = ethers.id("LogoSold(uint256,address,address,uint256)");
    const listedSig = ethers.id("LogoListedForSale(uint256,address,uint256)");
    
    // LogoAuction events
    const auctionCreatedSig = ethers.id("AuctionCreated(uint256,uint256,address,uint256,uint256,uint256)");
    const bidPlacedSig = ethers.id("BidPlaced(uint256,address,uint256)");
    const auctionEndedSig = ethers.id("AuctionEnded(uint256,address,uint256,bool)");
    const auctionCancelledSig = ethers.id("AuctionCancelled(uint256,address)");

    const chunkSize = 50000;
    
    // Collect all unique tx hashes per category
    const txCategories = {
        deployment_nft: [],
        deployment_auction: [],
        mint: [],
        approve_nft: [],
        reject_nft: [],
        list_for_sale: [],
        buy: [],
        auction_created: [],
        bid_placed: [],
        auction_ended: [],
        auction_cancelled: [],
        erc721_approve: [],
        other_nft: [],
        other_auction: [],
    };

    console.log("\n=== Fetching event logs in chunks ===\n");

    for (let i = startBlock; i <= currentBlock; i += chunkSize) {
        let fromBlock = i;
        let toBlock = Math.min(i + chunkSize - 1, currentBlock);
        process.stdout.write(`  Blocks ${fromBlock}-${toBlock}... `);

        try {
            // Mint events (Transfer from 0x0)
            const mintLogs = await provider.getLogs({
                address: logoNFTAddress, fromBlock, toBlock,
                topics: [mintSig, zeroAddr]
            });
            for (const log of mintLogs) txCategories.mint.push(log.transactionHash);

            // NFT Approved
            const approveLogs = await provider.getLogs({
                address: logoNFTAddress, fromBlock, toBlock,
                topics: [approvedSig]
            });
            for (const log of approveLogs) txCategories.approve_nft.push(log.transactionHash);

            // NFT Rejected
            const rejectLogs = await provider.getLogs({
                address: logoNFTAddress, fromBlock, toBlock,
                topics: [rejectedSig]
            });
            for (const log of rejectLogs) txCategories.reject_nft.push(log.transactionHash);

            // Listed for Sale
            const listLogs = await provider.getLogs({
                address: logoNFTAddress, fromBlock, toBlock,
                topics: [listedSig]
            });
            for (const log of listLogs) txCategories.list_for_sale.push(log.transactionHash);

            // Logo Sold (buy)
            const soldLogs = await provider.getLogs({
                address: logoNFTAddress, fromBlock, toBlock,
                topics: [logoSoldSig]
            });
            for (const log of soldLogs) txCategories.buy.push(log.transactionHash);

            // Auction Created
            const createdLogs = await provider.getLogs({
                address: logoAuctionAddress, fromBlock, toBlock,
                topics: [auctionCreatedSig]
            });
            for (const log of createdLogs) txCategories.auction_created.push(log.transactionHash);

            // Bid Placed
            const bidLogs = await provider.getLogs({
                address: logoAuctionAddress, fromBlock, toBlock,
                topics: [bidPlacedSig]
            });
            for (const log of bidLogs) txCategories.bid_placed.push(log.transactionHash);

            // Auction Ended
            const endedLogs = await provider.getLogs({
                address: logoAuctionAddress, fromBlock, toBlock,
                topics: [auctionEndedSig]
            });
            for (const log of endedLogs) txCategories.auction_ended.push(log.transactionHash);

            // Auction Cancelled
            const cancelledLogs = await provider.getLogs({
                address: logoAuctionAddress, fromBlock, toBlock,
                topics: [auctionCancelledSig]
            });
            for (const log of cancelledLogs) txCategories.auction_cancelled.push(log.transactionHash);

            console.log("OK");
        } catch (e) {
            console.log(`ERROR: ${e.message.substring(0, 80)}`);
        }
    }

    // Deduplicate
    for (const key of Object.keys(txCategories)) {
        txCategories[key] = [...new Set(txCategories[key])];
    }

    console.log("\n=== EVENT COUNTS ===\n");
    for (const [key, hashes] of Object.entries(txCategories)) {
        if (hashes.length > 0) {
            console.log(`  ${key}: ${hashes.length} transactions`);
        }
    }

    // Now fetch gas details for each unique tx
    const allTxHashes = new Set();
    for (const hashes of Object.values(txCategories)) {
        for (const h of hashes) allTxHashes.add(h);
    }

    console.log(`\n=== FETCHING GAS DATA FOR ${allTxHashes.size} UNIQUE TRANSACTIONS ===\n`);

    const txDetails = {};

    for (const txHash of allTxHashes) {
        try {
            const [tx, receipt] = await Promise.all([
                provider.getTransaction(txHash),
                provider.getTransactionReceipt(txHash)
            ]);

            if (tx && receipt) {
                txDetails[txHash] = {
                    hash: txHash,
                    gasUsed: receipt.gasUsed.toString(),
                    gasPrice: receipt.gasPrice ? receipt.gasPrice.toString() : (tx.gasPrice ? tx.gasPrice.toString() : "0"),
                    effectiveGasPrice: receipt.gasPrice ? receipt.gasPrice.toString() : "0",
                    gasLimit: tx.gasLimit.toString(),
                    status: receipt.status,
                    blockNumber: receipt.blockNumber,
                    value: tx.value.toString(),
                    from: tx.from,
                    to: tx.to,
                    methodId: tx.data.substring(0, 10),
                };

                // Calculate fee
                const gasUsed = BigInt(txDetails[txHash].gasUsed);
                const gasPrice = BigInt(txDetails[txHash].effectiveGasPrice);
                const feeWei = gasUsed * gasPrice;
                txDetails[txHash].feeWei = feeWei.toString();
                txDetails[txHash].feeEth = Number(feeWei) / 1e18;
                txDetails[txHash].gasPriceGwei = Number(gasPrice) / 1e9;
            }
        } catch (e) {
            console.log(`  Error fetching ${txHash}: ${e.message.substring(0, 60)}`);
        }
    }

    // Print detailed gas analysis per category
    console.log("\n" + "=".repeat(120));
    console.log("  DETAILED GAS ANALYSIS PER FUNCTION");
    console.log("=".repeat(120) + "\n");

    const summary = [];

    for (const [category, hashes] of Object.entries(txCategories)) {
        if (hashes.length === 0) continue;

        console.log(`\n--- ${category.toUpperCase()} (${hashes.length} tx) ---`);

        let totalGas = 0n;
        let totalFee = 0;
        let count = 0;
        const gasValues = [];
        const gasPrices = [];
        const feeValues = [];

        for (const h of hashes) {
            const d = txDetails[h];
            if (!d) continue;
            count++;
            const gu = BigInt(d.gasUsed);
            totalGas += gu;
            totalFee += d.feeEth;
            gasValues.push(Number(gu));
            gasPrices.push(d.gasPriceGwei);
            feeValues.push(d.feeEth);

            console.log(`  TX: ${h}`);
            console.log(`    Gas Used: ${d.gasUsed} | Gas Limit: ${d.gasLimit} | Gas Price: ${d.gasPriceGwei.toFixed(4)} Gwei`);
            console.log(`    Fee: ${d.feeEth.toFixed(10)} ETH | Status: ${d.status ? 'SUCCESS' : 'FAILED'} | Value: ${Number(BigInt(d.value)) / 1e18} ETH`);
        }

        if (count > 0) {
            const avgGas = gasValues.reduce((a, b) => a + b, 0) / count;
            const minGas = Math.min(...gasValues);
            const maxGas = Math.max(...gasValues);
            const avgPrice = gasPrices.reduce((a, b) => a + b, 0) / count;
            const avgFee = totalFee / count;

            console.log(`\n  Summary for ${category}:`);
            console.log(`    Count: ${count}`);
            console.log(`    Avg Gas Used: ${avgGas.toFixed(0)}`);
            console.log(`    Min Gas Used: ${minGas}`);
            console.log(`    Max Gas Used: ${maxGas}`);
            console.log(`    Avg Gas Price: ${avgPrice.toFixed(4)} Gwei`);
            console.log(`    Avg Fee: ${avgFee.toFixed(10)} ETH`);

            summary.push({
                category,
                count,
                avgGas: avgGas.toFixed(0),
                minGas,
                maxGas,
                avgGasPrice: avgPrice.toFixed(4),
                avgFeeEth: avgFee.toFixed(10),
                totalFeeEth: totalFee.toFixed(10),
            });
        }
    }

    console.log("\n" + "=".repeat(120));
    console.log("  SUMMARY TABLE (for report)");
    console.log("=".repeat(120));
    console.log("\n  Category            | Count | Avg Gas Used | Min Gas | Max Gas | Avg Gas Price (Gwei) | Avg Fee (ETH)");
    console.log("  " + "-".repeat(110));
    for (const s of summary) {
        console.log(`  ${s.category.padEnd(20)} | ${String(s.count).padEnd(5)} | ${String(s.avgGas).padEnd(12)} | ${String(s.minGas).padEnd(7)} | ${String(s.maxGas).padEnd(7)} | ${String(s.avgGasPrice).padEnd(20)} | ${s.avgFeeEth}`);
    }

    // Save to JSON
    const fs = require("fs");
    const output = { summary, txDetails, txCategories };
    fs.writeFileSync("gas_analysis_results.json", JSON.stringify(output, null, 2));
    console.log("\n\n💾 Full results saved to gas_analysis_results.json");
}

main().catch(console.error);
