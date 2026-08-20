const hre = require("hardhat");

async function main() {
    const [deployer, seller, buyer] = await hre.ethers.getSigners();
    
    // 1. Deploy contracts
    const LogoNFT = await hre.ethers.getContractFactory("LogoNFT");
    const logoNFT = await LogoNFT.deploy();
    await logoNFT.waitForDeployment();
    
    const LogoAuction = await hre.ethers.getContractFactory("LogoAuction");
    const logoAuction = await LogoAuction.deploy(await logoNFT.getAddress());
    await logoAuction.waitForDeployment();

    const results = [];

    // Helper to estimate and record gas
    async function recordGas(name, txPromise) {
        try {
            const tx = await txPromise;
            const receipt = await tx.wait();
            results.push({
                function: name,
                gasUsed: receipt.gasUsed.toString(),
            });
            console.log(`- ${name}: ${receipt.gasUsed} gas`);
            return receipt;
        } catch (e) {
            console.log(`Error estimating ${name}: ${e.message.substring(0,50)}`);
            return null;
        }
    }

    console.log("Estimating Gas Usage...");

    // Register Seller
    await recordGas("registerAsSeller", logoNFT.connect(seller).registerAsSeller());

    // Mint NFT
    const mintTx = await logoNFT.connect(seller).mint(
        "Test Logo",
        "Test Description",
        "QmTzQ...", // Dummy IPFS hash
        hre.ethers.parseEther("0.1")
    );
    const mintReceipt = await mintTx.wait();
    results.push({ function: "mint (LogoNFT)", gasUsed: mintReceipt.gasUsed.toString() });
    console.log(`- mint: ${mintReceipt.gasUsed} gas`);
    const tokenId = 1;

    // Approve NFT (Admin)
    await recordGas("approveNFT (Admin)", logoNFT.connect(deployer).approveNFT(tokenId));

    // List for sale
    await recordGas("listForSale", logoNFT.connect(seller).listForSale(tokenId, hre.ethers.parseEther("0.1")));

    // Buy NFT
    await recordGas("buy", logoNFT.connect(buyer).buy(tokenId, { value: hre.ethers.parseEther("0.1") }));

    // Now buyer owns it. Let's create an auction.
    // First, register buyer as seller
    await logoNFT.connect(buyer).registerAsSeller();
    
    // Approve auction contract to move NFT
    await recordGas("approve (ERC721)", logoNFT.connect(buyer).approve(await logoAuction.getAddress(), tokenId));

    // Create Auction
    await recordGas("createAuction", logoAuction.connect(buyer).createAuction(
        tokenId,
        seller.address, // original creator
        hre.ethers.parseEther("0.05"),
        hre.ethers.parseEther("0.05"),
        3600 // 1 hour duration
    ));

    // Place Bid
    await recordGas("placeBid", logoAuction.connect(seller).placeBid(1, { value: hre.ethers.parseEther("0.06") }));

    // End Auction (needs time travel or fast forward)
    await hre.network.provider.send("evm_increaseTime", [3601]);
    await hre.network.provider.send("evm_mine");

    await recordGas("endAuction", logoAuction.connect(seller).endAuction(1));

    console.log("\nResults:", JSON.stringify(results, null, 2));
}

main().catch(console.error);
