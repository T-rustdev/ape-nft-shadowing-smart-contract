# ShadowApe Quick Start Guide ⚡

Get your shadow NFT system running in under 10 minutes.

## 🚀 TL;DR

```bash
# 1. Install
npm install

# 2. Configure
cp .env.example .env
# Edit .env with your keys

# 3. Deploy to ApeChain
npm run deploy:apechain
# Save address: 0xYourShadowApeAddress

# 4. Deploy to Ethereum
npm run deploy:ethereum
# Save address: 0xYourSourceAddress

# 5. Configure LayerZero
# Update addresses in scripts/configure-layerzero.js
npm run configure:apechain
npm run configure:ethereum

# 6. Test sync
# Update addresses in scripts/test-sync.js
npm run test:sync

# 7. Wait ~30 seconds → Shadow appears on ApeChain! 🎉
```

## 📋 What You Need

- **Ethereum Wallet**: With ~0.05 ETH for deployment + sync fees
- **ApeChain Wallet**: With ~10 APE for deployment (gas is ~$0.10)
- **Node.js**: Version 18 or higher
- **RPC URLs**: Ethereum and ApeChain (public or private)

## 🔑 Environment Setup

Create `.env` file:

```bash
# Required
PRIVATE_KEY=0xyour_private_key_without_0x_prefix

# RPC URLs (use public or your own)
ETH_RPC_URL=https://eth.llamarpc.com
APECHAIN_RPC_URL=https://rpc.apechain.com/http

# Optional (for verification)
ETHERSCAN_API_KEY=your_etherscan_api_key
```

## 📦 Installation

```bash
# Clone or create project
npm install

# Install dependencies
npm install @openzeppelin/contracts@^5.0.1
npm install @layerzerolabs/lz-evm-oapp-v2@^2.2.0
npm install @layerzerolabs/lz-evm-protocol-v2@^2.2.0
```

## 🎯 Core Concepts

### What is a Shadow NFT?

- **Soulbound** copy of BAYC on ApeChain
- **Auto-syncs** when BAYC transfers on Ethereum
- **Delegatable** for staking/gaming (while staying soulbound)
- **Unlockable** by original owner (makes it transferable)

### Flow Example

```
1. Alice owns BAYC #100 on Ethereum
2. Someone calls syncBAYC(100)
3. LayerZero sends message to ApeChain (~30 sec)
4. Shadow #100 minted to Alice on ApeChain
5. Alice transfers BAYC #100 to Bob on Ethereum
6. Someone calls syncBAYC(100) again
7. Shadow #100 automatically transfers to Bob on ApeChain
```

## ⚙️ Configuration After Deployment

### Set Trusted Remotes

**Critical Step**: Both contracts must trust each other.

Edit `scripts/configure-layerzero.js`:

```javascript
// Line 10-11: Update with your deployed addresses
const SHADOW_APE_ADDRESS = "0x..."; // From ApeChain deployment
const SHADOW_SOURCE_ADDRESS = "0x..."; // From Ethereum deployment
```

Then run:

```bash
npm run configure:apechain
npm run configure:ethereum
```

### Verify Contracts (Optional but Recommended)

**ApeChain:**

```bash
npx hardhat verify --network apechain \
  <SHADOW_APE_ADDRESS> \
  "0x1a44076050125825900e736c501f859c50fE728c" \
  "<YOUR_WALLET>" \
  "ipfs://QmYourHash/"
```

**Ethereum:**

```bash
npx hardhat verify --network mainnet \
  <SHADOW_SOURCE_ADDRESS> \
  "0x1a44076050125825900e736c501f859c50fE728c" \
  "<YOUR_WALLET>"
```

## 🧪 Test the System

### Manual Sync Test

```bash
# Edit scripts/test-sync.js
const SHADOW_SOURCE_ADDRESS = "0x...";
const TEST_TOKEN_ID = 0; // Any BAYC token ID (0-9999)

# Run test
npm run test:sync
```

**Expected Output:**

```
🧪 Testing BAYC → ApeChain sync...
BAYC #0 owner: 0x1A92f7381B9F03921564a437210bB9396471050C
💰 Quoting sync fee...
Estimated fee: 0.003 ETH
🚀 Syncing BAYC #0...
Transaction sent: 0x...
✅ Transaction confirmed!
✉️ OwnershipProofSent: Token #0, Action: MINT
📡 Check ApeChain in ~10-30 seconds
```

### Verify Shadow Minted

After ~30 seconds, check ApeChain:

```bash
# Check if shadow exists
cast call <SHADOW_APE_ADDRESS> \
  "shadowExists(uint256)(bool)" \
  0 \
  --rpc-url https://rpc.apechain.com/http

# Returns: true

# Get shadow owner
cast call <SHADOW_APE_ADDRESS> \
  "ownerOf(uint256)(address)" \
  0 \
  --rpc-url https://rpc.apechain.com/http

# Returns: 0x1A92f7381B9F03921564a437210bB9396471050C (BAYC owner)
```

## 🎨 Using Shadow NFTs

### Check Your Shadows

```javascript
const shadows = await shadowApe.getShadowsByOwner(yourAddress);
console.log("You own shadows:", shadows);
// Output: [1, 5, 42, 100]
```

### Delegate a Shadow (for Staking)

```javascript
// Delegate shadow #1 to staking contract
await shadowApe.delegateShadow(1, stakingContractAddress);

// Shadow stays with you, but staking contract can read it
console.log(await shadowApe.getShadowDelegate(1));
// Output: <staking contract address>

// Revoke anytime
await shadowApe.revokeDelegation(1);
```

### Unlock a Shadow (Make Transferable)

```javascript
// Only original owner can unlock (irreversible!)
await shadowApe.unlockShadow(1);

// Now you can transfer it
await shadowApe.transferFrom(yourAddress, recipientAddress, 1);
```

## 📊 Key Addresses (Mainnet)

### LayerZero v2 Endpoints

- **Ethereum**: `0x1a44076050125825900e736c501f859c50fE728c`
- **ApeChain**: `0x1a44076050125825900e736c501f859c50fE728c`

### Chain Info

| Chain | Chain ID | EID | Explorer |
|-------|----------|-----|----------|
| Ethereum | 1 | 30101 | etherscan.io |
| ApeChain | 33139 | 30151 | apescan.io |

### BAYC Contract

- **Address**: `0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D`

## 💰 Cost Breakdown

| Action | Ethereum | ApeChain |
|--------|----------|----------|
| Deploy Source | $15-25 | N/A |
| Deploy Shadow | N/A | ~$0.10 |
| Sync Single Token | $8-15 | Free (receive) |
| Delegate Shadow | N/A | ~$0.001 |
| Unlock Shadow | N/A | ~$0.001 |

*Note: ApeChain gas is extremely cheap (~0.1 gwei)*

## 🔍 Troubleshooting

### "Insufficient Fee" Error

```javascript
// Add buffer to quoted fee
const fee = await shadowSource.quoteSyncFee(tokenId);
const feeWithBuffer = (fee.nativeFee * 120n) / 100n; // 20% buffer

await shadowSource.syncBAYC(tokenId, yourAddress, {
  value: feeWithBuffer
});
```

### Message Not Arriving

1. Check LayerZero Scan: https://layerzeroscan.com/
2. Search by your transaction hash
3. Typical delivery: 30-60 seconds
4. If stuck, may need to retry (rare)

### "Shadow Already Exists"

```javascript
// Check before syncing
const exists = await shadowApe.shadowExists(tokenId);
if (exists) {
  console.log("Shadow already minted!");
}
```

## 📚 Learn More

- **Full Documentation**: See `README.md`
- **Deployment Guide**: See `DEPLOYMENT_GUIDE.md`
- **Test Scenarios**: See `TEST_SCENARIOS.md`
- **LayerZero Deep Dive**: See `LAYERZERO_INTEGRATION.md`

## 🛟 Support

- **GitHub Issues**: Open an issue for bugs
- **LayerZero Discord**: https://discord.gg/layerzero
- **ApeChain Discord**: https://discord.gg/apecoin

## ✅ Checklist

- [ ] Dependencies installed
- [ ] `.env` configured
- [ ] Deployed to ApeChain
- [ ] Deployed to Ethereum
- [ ] Trusted remotes set
- [ ] Contracts verified
- [ ] Test sync successful
- [ ] Shadow appeared on ApeChain

**You're ready to build on ApeChain! 🦍⚡**

