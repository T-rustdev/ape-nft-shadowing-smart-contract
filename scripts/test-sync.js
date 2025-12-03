/**
 * Test syncing a BAYC token from Ethereum to ApeChain
 * 
 * Usage:
 * npx hardhat run scripts/test-sync.js --network mainnet
 */

const hre = require("hardhat");

// UPDATE THESE
const SHADOW_SOURCE_ADDRESS = "0x..."; // BAYCShadowSource on Ethereum
const TEST_TOKEN_ID = 0; // BAYC token ID to test (use one you own or can verify)

async function main() {
    console.log("🧪 Testing BAYC → ApeChain sync...\n");

    const [signer] = await hre.ethers.getSigners();
    console.log("Signer:", signer.address);
    console.log("");

    const shadowSource = await hre.ethers.getContractAt("BAYCShadowSource", SHADOW_SOURCE_ADDRESS, signer);

    // Get current BAYC owner
    const BAYC_ADDRESS = "0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D";
    const bayc = await hre.ethers.getContractAt(
        ["function ownerOf(uint256) view returns (address)"],
        BAYC_ADDRESS
    );

    let currentOwner;
    try {
        currentOwner = await bayc.ownerOf(TEST_TOKEN_ID);
        console.log(`BAYC #${TEST_TOKEN_ID} owner:`, currentOwner);
    } catch (e) {
        console.error("❌ Could not get BAYC owner. Token may not exist.");
        process.exit(1);
    }

    // Quote the sync fee
    console.log("\n💰 Quoting sync fee...");
    const fee = await shadowSource.quoteSyncFee(TEST_TOKEN_ID);
    const feeInEth = hre.ethers.formatEther(fee.nativeFee);
    console.log("Estimated fee:", feeInEth, "ETH");
    console.log("");

    // Add 20% buffer to fee
    const feeWithBuffer = (fee.nativeFee * 120n) / 100n;

    console.log("🚀 Syncing BAYC #" + TEST_TOKEN_ID + "...");
    console.log("This will:");
    console.log("1. Send LayerZero message from Ethereum");
    console.log("2. Message relayed by LayerZero DVN/Executor");
    console.log("3. Shadow minted on ApeChain (~5-30 seconds)");
    console.log("");

    // Sync the token
    const tx = await shadowSource.syncBAYC(
        TEST_TOKEN_ID,
        signer.address, // refund address
        { value: feeWithBuffer }
    );

    console.log("Transaction sent:", tx.hash);
    console.log("⏳ Waiting for confirmation...");

    const receipt = await tx.wait();
    console.log("✅ Transaction confirmed!");
    console.log("Gas used:", receipt.gasUsed.toString());
    console.log("");

    // Parse events
    const events = receipt.logs;
    console.log("📝 Events emitted:", events.length);
    
    // Find OwnershipProofSent event
    try {
        const iface = shadowSource.interface;
        for (const log of events) {
            try {
                const parsed = iface.parseLog(log);
                if (parsed.name === "OwnershipProofSent") {
                    console.log("\n✉️ OwnershipProofSent:");
                    console.log("- Token ID:", parsed.args.tokenId.toString());
                    console.log("- From:", parsed.args.from);
                    console.log("- To:", parsed.args.to);
                    console.log("- Action:", ["MINT", "TRANSFER", "BURN"][parsed.args.action]);
                    console.log("- GUID:", parsed.args.guid);
                }
            } catch (e) {
                // Not our event
            }
        }
    } catch (e) {
        console.log("Could not parse events");
    }

    console.log("\n✅ Sync initiated successfully!");
    console.log("\n📡 Check ApeChain in ~10-30 seconds:");
    console.log(`- Visit https://apescan.io/address/${SHADOW_SOURCE_ADDRESS}`);
    console.log("- Shadow should be minted to:", currentOwner);
    console.log("\n🎉 Test complete!");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

