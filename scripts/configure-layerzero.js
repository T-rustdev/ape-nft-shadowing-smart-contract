/**
 * Configure LayerZero trusted remotes and settings for both contracts
 * 
 * Usage:
 * 1. Update SHADOW_APE_ADDRESS and SHADOW_SOURCE_ADDRESS
 * 2. Run on Ethereum: npx hardhat run scripts/configure-layerzero.js --network mainnet
 * 3. Run on ApeChain: npx hardhat run scripts/configure-layerzero.js --network apechain
 */

const hre = require("hardhat");

// UPDATE THESE AFTER DEPLOYMENT
const SHADOW_APE_ADDRESS = "0x..."; // ShadowApe on ApeChain
const SHADOW_SOURCE_ADDRESS = "0x..."; // BAYCShadowSource on Ethereum

async function main() {
    const network = hre.network.name;
    console.log(`🔧 Configuring LayerZero for ${network}...\n`);

    const [signer] = await hre.ethers.getSigners();
    console.log("Signer:", signer.address);
    console.log("");

    if (network === "apechain") {
        await configureApeChain(signer);
    } else if (network === "mainnet") {
        await configureEthereum(signer);
    } else {
        console.error("❌ Unsupported network. Use 'apechain' or 'mainnet'");
        process.exit(1);
    }
}

async function configureApeChain(signer) {
    console.log("📡 Configuring ShadowApe on ApeChain...\n");

    const shadowApe = await hre.ethers.getContractAt("ShadowApe", SHADOW_APE_ADDRESS, signer);

    // Ethereum Mainnet endpoint ID
    const ETH_MAINNET_EID = 30101;

    // Encode the trusted remote (Ethereum source contract address)
    const trustedRemote = hre.ethers.solidityPacked(
        ["address", "address"],
        [SHADOW_SOURCE_ADDRESS, SHADOW_APE_ADDRESS]
    );

    console.log("Setting trusted remote:");
    console.log("- Source EID:", ETH_MAINNET_EID);
    console.log("- Remote Address:", SHADOW_SOURCE_ADDRESS);
    console.log("");

    // Set peer (LayerZero v2 uses setPeer)
    const tx1 = await shadowApe.setPeer(ETH_MAINNET_EID, hre.ethers.zeroPadValue(SHADOW_SOURCE_ADDRESS, 32));
    await tx1.wait();
    console.log("✅ Trusted remote set! Tx:", tx1.hash);
    console.log("");

    // Optional: Configure enforced options for extra security
    console.log("⚙️ Configuring enforced options...");
    
    // This enforces a minimum gas limit on the destination
    const enforcedOptions = hre.ethers.solidityPacked(
        ["uint16", "uint128"],
        [1, 200000] // option type 1 (gas), 200k gas
    );

    try {
        const tx2 = await shadowApe.setEnforcedOptions([
            {
                eid: ETH_MAINNET_EID,
                msgType: 1, // standard message type
                options: enforcedOptions
            }
        ]);
        await tx2.wait();
        console.log("✅ Enforced options set! Tx:", tx2.hash);
    } catch (e) {
        console.log("⚠️ Could not set enforced options (may not be supported in this OApp version)");
    }

    console.log("\n✅ ApeChain configuration complete!");
}

async function configureEthereum(signer) {
    console.log("📡 Configuring BAYCShadowSource on Ethereum...\n");

    const shadowSource = await hre.ethers.getContractAt("BAYCShadowSource", SHADOW_SOURCE_ADDRESS, signer);

    // ApeChain endpoint ID
    const APECHAIN_EID = 30151;

    // Encode the trusted remote
    const trustedRemote = hre.ethers.solidityPacked(
        ["address", "address"],
        [SHADOW_APE_ADDRESS, SHADOW_SOURCE_ADDRESS]
    );

    console.log("Setting trusted remote:");
    console.log("- Destination EID:", APECHAIN_EID);
    console.log("- Remote Address:", SHADOW_APE_ADDRESS);
    console.log("");

    // Set peer
    const tx1 = await shadowSource.setPeer(APECHAIN_EID, hre.ethers.zeroPadValue(SHADOW_APE_ADDRESS, 32));
    await tx1.wait();
    console.log("✅ Trusted remote set! Tx:", tx1.hash);
    console.log("");

    // Optional: Set destination gas limit
    console.log("⚙️ Setting destination gas limit...");
    const tx2 = await shadowSource.setDstGasLimit(200000);
    await tx2.wait();
    console.log("✅ Gas limit set to 200,000! Tx:", tx2.hash);

    console.log("\n✅ Ethereum configuration complete!");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

