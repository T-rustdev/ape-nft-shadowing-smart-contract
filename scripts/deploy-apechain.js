/**
 * Deploy ShadowApe contract to ApeChain
 * 
 * Usage:
 * npx hardhat run scripts/deploy-apechain.js --network apechain
 */

const hre = require("hardhat");

async function main() {
    console.log("🦍 Deploying ShadowApe to ApeChain...\n");

    const [deployer] = await hre.ethers.getSigners();
    console.log("Deployer address:", deployer.address);
    console.log("Deployer balance:", hre.ethers.formatEther(await hre.ethers.provider.getBalance(deployer.address)), "APE\n");

    // ApeChain LayerZero v2 Endpoint
    const LZ_ENDPOINT_APECHAIN = "0x1a44076050125825900e736c501f859c50fE728c";
    
    // Metadata base URI (update with your IPFS hash)
    const BASE_URI = "ipfs://QmShadowApeMetadataHash/";

    console.log("Deployment Parameters:");
    console.log("- LayerZero Endpoint:", LZ_ENDPOINT_APECHAIN);
    console.log("- Initial Owner:", deployer.address);
    console.log("- Base URI:", BASE_URI);
    console.log("");

    // Deploy ShadowApe
    const ShadowApe = await hre.ethers.getContractFactory("ShadowApe");
    const shadowApe = await ShadowApe.deploy(
        LZ_ENDPOINT_APECHAIN,
        deployer.address,
        BASE_URI
    );

    await shadowApe.waitForDeployment();
    const shadowApeAddress = await shadowApe.getAddress();

    console.log("✅ ShadowApe deployed to:", shadowApeAddress);
    console.log("");

    // Wait for block confirmations
    console.log("⏳ Waiting for 5 block confirmations...");
    await shadowApe.deploymentTransaction().wait(5);
    console.log("✅ Confirmed!\n");

    // Save deployment info
    const deploymentInfo = {
        network: "apechain",
        contract: "ShadowApe",
        address: shadowApeAddress,
        deployer: deployer.address,
        lzEndpoint: LZ_ENDPOINT_APECHAIN,
        baseURI: BASE_URI,
        timestamp: new Date().toISOString(),
        blockNumber: await hre.ethers.provider.getBlockNumber()
    };

    console.log("📝 Deployment Info:");
    console.log(JSON.stringify(deploymentInfo, null, 2));
    console.log("");

    // Verification command
    console.log("📋 Verify on ApeChain Blockscout:");
    console.log(`npx hardhat verify --network apechain ${shadowApeAddress} "${LZ_ENDPOINT_APECHAIN}" "${deployer.address}" "${BASE_URI}"`);
    console.log("");

    console.log("🎉 Deployment complete! Next steps:");
    console.log("1. Deploy BAYCShadowSource to Ethereum Mainnet");
    console.log("2. Set trusted remote on both contracts");
    console.log("3. Configure LayerZero DVN and executor");
    console.log("4. Test with a sync transaction");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

