/**
 * Deploy BAYCShadowSource contract to Ethereum Mainnet
 * 
 * Usage:
 * npx hardhat run scripts/deploy-ethereum.js --network mainnet
 */

const hre = require("hardhat");

async function main() {
    console.log("🔷 Deploying BAYCShadowSource to Ethereum Mainnet...\n");

    const [deployer] = await hre.ethers.getSigners();
    console.log("Deployer address:", deployer.address);
    console.log("Deployer balance:", hre.ethers.formatEther(await hre.ethers.provider.getBalance(deployer.address)), "ETH\n");

    // Ethereum Mainnet LayerZero v2 Endpoint
    const LZ_ENDPOINT_MAINNET = "0x1a44076050125825900e736c501f859c50fE728c";

    console.log("Deployment Parameters:");
    console.log("- LayerZero Endpoint:", LZ_ENDPOINT_MAINNET);
    console.log("- Initial Owner:", deployer.address);
    console.log("- BAYC Address:", "0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D");
    console.log("");

    // Deploy BAYCShadowSource
    const BAYCShadowSource = await hre.ethers.getContractFactory("BAYCShadowSource");
    const shadowSource = await BAYCShadowSource.deploy(
        LZ_ENDPOINT_MAINNET,
        deployer.address
    );

    await shadowSource.waitForDeployment();
    const shadowSourceAddress = await shadowSource.getAddress();

    console.log("✅ BAYCShadowSource deployed to:", shadowSourceAddress);
    console.log("");

    // Wait for block confirmations
    console.log("⏳ Waiting for 5 block confirmations...");
    await shadowSource.deploymentTransaction().wait(5);
    console.log("✅ Confirmed!\n");

    // Save deployment info
    const deploymentInfo = {
        network: "ethereum-mainnet",
        contract: "BAYCShadowSource",
        address: shadowSourceAddress,
        deployer: deployer.address,
        lzEndpoint: LZ_ENDPOINT_MAINNET,
        timestamp: new Date().toISOString(),
        blockNumber: await hre.ethers.provider.getBlockNumber()
    };

    console.log("📝 Deployment Info:");
    console.log(JSON.stringify(deploymentInfo, null, 2));
    console.log("");

    // Verification command
    console.log("📋 Verify on Etherscan:");
    console.log(`npx hardhat verify --network mainnet ${shadowSourceAddress} "${LZ_ENDPOINT_MAINNET}" "${deployer.address}"`);
    console.log("");

    console.log("🎉 Deployment complete! Next steps:");
    console.log("1. Set trusted remote to ApeChain ShadowApe contract");
    console.log("2. Configure LayerZero DVN and executor");
    console.log("3. Test sync with a BAYC token ID");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

