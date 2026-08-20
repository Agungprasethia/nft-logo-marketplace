async function main() {
    const nftAddr = "0xe234f6844024eaE1EAf220E01BDC942B20431355";
    const auctionAddr = "0xFcB81D253f0eAaEF600A6D76C1cfed643861cAd8";

    // Fetch txlist for NFT
    try {
        console.log("Fetching NFT transactions...");
        const res1 = await fetch(`https://api-sepolia.etherscan.io/api?module=account&action=txlist&address=${nftAddr}&startblock=0&endblock=99999999&sort=desc`);
        const data1 = await res1.json();
        if (data1.status === "1") {
            console.log(`Found ${data1.result.length} transactions for NFT contract.`);
            data1.result.slice(0, 5).forEach(tx => console.log(`[NFT] Hash: ${tx.hash}, MethodId: ${tx.methodId}, Function: ${tx.functionName}`));
        } else {
            console.log("Error fetching NFT:", data1.message);
        }
    } catch (e) {
        console.error(e);
    }

    // Fetch txlist for Auction
    try {
        console.log("Fetching Auction transactions...");
        const res2 = await fetch(`https://api-sepolia.etherscan.io/api?module=account&action=txlist&address=${auctionAddr}&startblock=0&endblock=99999999&sort=desc`);
        const data2 = await res2.json();
        if (data2.status === "1") {
            console.log(`Found ${data2.result.length} transactions for Auction contract.`);
            data2.result.slice(0, 10).forEach(tx => console.log(`[Auction] Hash: ${tx.hash}, MethodId: ${tx.methodId}, Function: ${tx.functionName}`));
        } else {
            console.log("Error fetching Auction:", data2.message);
        }
    } catch (e) {
        console.error(e);
    }
}

main();
