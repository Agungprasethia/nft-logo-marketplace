const hre = require("hardhat");

async function main() {
    console.log("🚀 Starting deployment to", hre.network.name, "...\n");

    const [deployer] = await hre.ethers.getSigners();
    console.log("📍 Deploying contracts with account:", deployer.address);

    const balance = await hre.ethers.provider.getBalance(deployer.address);
    console.log("💰 Account balance:", hre.ethers.formatEther(balance), "ETH\n");

    // Deploy LogoNFT
    console.log("📦 Deploying LogoNFT...");
    const LogoNFT = await hre.ethers.getContractFactory("LogoNFT");
    const logoNFT = await LogoNFT.deploy();
    await logoNFT.waitForDeployment();
    const logoNFTAddress = await logoNFT.getAddress();
    console.log("✅ LogoNFT deployed to:", logoNFTAddress);

    // Deploy LogoAuction
    console.log("\n📦 Deploying LogoAuction...");
    const LogoAuction = await hre.ethers.getContractFactory("LogoAuction");
    const logoAuction = await LogoAuction.deploy(logoNFTAddress);
    await logoAuction.waitForDeployment();
    const logoAuctionAddress = await logoAuction.getAddress();
    console.log("✅ LogoAuction deployed to:", logoAuctionAddress);

    // Summary
    console.log("\n" + "=".repeat(50));
    console.log("🎉 DEPLOYMENT COMPLETE!");
    console.log("=".repeat(50));
    console.log("\n📋 Contract Addresses (save these!):\n");
    console.log(`   LogoNFT:     ${logoNFTAddress}`);
    console.log(`   LogoAuction: ${logoAuctionAddress}`);
    console.log("\n🔗 View on Etherscan:");
    console.log(`   LogoNFT:     https://sepolia.etherscan.io/address/${logoNFTAddress}`);
    console.log(`   LogoAuction: https://sepolia.etherscan.io/address/${logoAuctionAddress}`);
    console.log("\n" + "=".repeat(50));

    // Save addresses to file for Flutter app
    const fs = require("fs");
    const addresses = {
        network: hre.network.name,
        chainId: 11155111,
        logoNFT: logoNFTAddress,
        logoAuction: logoAuctionAddress,
        deployedAt: new Date().toISOString()
    };

    fs.writeFileSync(
        "deployed_addresses.json",
        JSON.stringify(addresses, null, 2)
    );
    console.log("\n💾 Addresses saved to deployed_addresses.json");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error("❌ Deployment failed:", error);
        process.exit(1);
    });
