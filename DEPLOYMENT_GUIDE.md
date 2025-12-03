# ShadowApe Deployment Guide 🚀

Complete step-by-step guide for deploying the ShadowApe cross-chain NFT system to production.

## Pre-Deployment Checklist

- [ ] Node.js 18+ installed
- [ ] Private key with sufficient ETH (Ethereum) and APE (ApeChain)
- [ ] Etherscan API key (for verification)
- [ ] IPFS/Arweave metadata prepared
- [ ] All dependencies installed (`npm install`)
- [ ] Environment variables configured

## 📋 Step-by-Step Deployment

### Step 1: Prepare Metadata

Upload your shadow NFT metadata to IPFS or Arweave:

```bash
# Metadata format: {baseURI}/{tokenId}.json
# Example: ipfs://QmYourHash/1.json

# Metadata should include:
{
  "name": "Shadow Ape #1",
  "description": "Shadow NFT mirroring BAYC #1 on ApeChain",
  "image": "ipfs://QmImageHash/1.png",
  "attributes": [
    {"trait_type": "Type", "value": "Shadow"},
    {"trait_type": "Source Chain", "value": "Ethereum"},
    {"trait_type": "Soulbound", "value": "True"}
  ]
}
```

### Step 2: Deploy to ApeChain

#### Using Hardhat

```bash
# Update BASE_URI in scripts/deploy-apechain.js
npm run deploy:apechain
```

#### Using Foundry

```bash
forge script script/DeployApeChain.s.sol \
  --rpc-url $APECHAIN_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify
```

**Expected Output:**

```
✅ ShadowApe deployed to: 0x...
⏳ Waiting for 5 block confirmations...
✅ Confirmed!
```

**Save this address!** You'll need it for configuration.

### Step 3: Deploy to Ethereum Mainnet

#### Using Hardhat

```bash
npm run deploy:ethereum
```

#### Using Foundry

```bash
forge script script/DeployEthereum.s.sol \
  --rpc-url $ETH_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify
```

**Expected Output:**

```
✅ BAYCShadowSource deployed to: 0x...
⏳ Waiting for 5 block confirmations...
✅ Confirmed!
```

**Save this address!** You'll need it for configuration.

### Step 4: Verify Contracts

#### ApeChain (Blockscout)

```bash
npx hardhat verify --network apechain \
  SHADOW_APE_ADDRESS \
  "0x1a44076050125825900e736c501f859c50fE728c" \
  "YOUR_WALLET_ADDRESS" \
  "ipfs://QmYourHash/"
```

#### Ethereum (Etherscan)

```bash
npx hardhat verify --network mainnet \
  SHADOW_SOURCE_ADDRESS \
  "0x1a44076050125825900e736c501f859c50fE728c" \
  "YOUR_WALLET_ADDRESS"
```

### Step 5: Configure LayerZero Trusted Remotes

**CRITICAL**: Both contracts must trust each other for cross-chain messaging.

Update addresses in `scripts/configure-layerzero.js`:

```javascript
const SHADOW_APE_ADDRESS = "0x..."; // From Step 2
const SHADOW_SOURCE_ADDRESS = "0x..."; // From Step 3
```

#### Configure ApeChain

```bash
npm run configure:apechain
```

**Expected Output:**

```
✅ Trusted remote set! Tx: 0x...
✅ Enforced options set! Tx: 0x...
✅ ApeChain configuration complete!
```

#### Configure Ethereum

```bash
npm run configure:ethereum
```

**Expected Output:**

```
✅ Trusted remote set! Tx: 0x...
✅ Gas limit set to 200,000! Tx: 0x...
✅ Ethereum configuration complete!
```

### Step 6: Configure LayerZero DVN (Decentralized Verifier Network)

This step configures security settings for LayerZero message verification.

**On Ethereum (Source):**

```bash
# Using LayerZero CLI or contract interaction
cast send $SHADOW_SOURCE_ADDRESS \
  "setDelegate(address)" \
  0x589dEDbD617e0CBcB916A9223F4d1300c294236b \ # LayerZero Delegate
  --rpc-url $ETH_RPC_URL \
  --private-key $PRIVATE_KEY
```

**On ApeChain (Destination):**

```bash
cast send $SHADOW_APE_ADDRESS \
  "setDelegate(address)" \
  0x589dEDbD617e0CBcB916A9223F4d1300c294236b \
  --rpc-url $APECHAIN_RPC_URL \
  --private-key $PRIVATE_KEY
```

### Step 7: Test the System

#### Test Single Token Sync

Update `scripts/test-sync.js`:

```javascript
const SHADOW_SOURCE_ADDRESS = "0x...";
const TEST_TOKEN_ID = 0; // Use a real BAYC token ID
```

Run the test:

```bash
npm run test:sync
```

**Expected Timeline:**

1. **T+0s**: Transaction sent on Ethereum
2. **T+15s**: LayerZero DVN verifies message
3. **T+30s**: Message delivered to ApeChain
4. **T+45s**: Shadow NFT minted

**Verify on ApeChain:**

```bash
# Check if shadow exists
cast call $SHADOW_APE_ADDRESS \
  "shadowExists(uint256)(bool)" \
  $TEST_TOKEN_ID \
  --rpc-url $APECHAIN_RPC_URL

# Get shadow owner
cast call $SHADOW_APE_ADDRESS \
  "ownerOf(uint256)(address)" \
  $TEST_TOKEN_ID \
  --rpc-url $APECHAIN_RPC_URL
```

### Step 8: Batch Sync (Optional)

For initial deployment, sync all BAYC tokens:

```javascript
// Create batch-sync.js
const tokenIds = [0, 1, 2, 3, 4, 5, ...]; // Up to 10,000

const fee = await shadowSource.quoteBatchSyncFee(tokenIds.length);
await shadowSource.batchSyncBAYC(
  tokenIds,
  deployerAddress,
  { value: fee.mul(110).div(100) } // 10% buffer
);
```

**Warning**: Batch syncing 10,000 tokens will be expensive. Consider:
- Syncing in smaller batches (100-500 tokens)
- Only syncing tokens with active owners
- Gradual sync over time

## 🔧 Post-Deployment Configuration

### Update Base URI (if needed)

```bash
cast send $SHADOW_APE_ADDRESS \
  "setBaseURI(string)" \
  "ipfs://QmNewHash/" \
  --rpc-url $APECHAIN_RPC_URL \
  --private-key $PRIVATE_KEY
```

### Set Destination Gas Limit (if needed)

```bash
cast send $SHADOW_SOURCE_ADDRESS \
  "setDstGasLimit(uint128)" \
  250000 \
  --rpc-url $ETH_RPC_URL \
  --private-key $PRIVATE_KEY
```

### Emergency Pause (if needed)

```bash
# Pause incoming messages on ApeChain
cast send $SHADOW_APE_ADDRESS \
  "setPaused(bool)" \
  true \
  --rpc-url $APECHAIN_RPC_URL \
  --private-key $PRIVATE_KEY
```

## 📊 Monitoring & Analytics

### Track Sync Events

Monitor Ethereum for `OwnershipProofSent` events:

```bash
cast logs --from-block latest \
  --address $SHADOW_SOURCE_ADDRESS \
  --rpc-url $ETH_RPC_URL
```

Monitor ApeChain for `ShadowMinted` events:

```bash
cast logs --from-block latest \
  --address $SHADOW_APE_ADDRESS \
  --rpc-url $APECHAIN_RPC_URL
```

### Check LayerZero Message Status

Visit LayerZero Scan to track cross-chain messages:
- https://layerzeroscan.com/

Search by transaction hash or address.

## 🚨 Troubleshooting

### Message Not Delivered

**Symptoms**: Shadow not minting after 60+ seconds

**Solutions**:

1. **Check LayerZero Scan**: Verify message was sent and delivered
2. **Check Gas Limits**: Increase `dstGasLimit` if execution fails
3. **Check Trusted Remotes**: Ensure both contracts have correct peers set
4. **Check Balance**: Ensure LayerZero Executor has funds to relay

### Insufficient Fee Error

**Symptoms**: Transaction reverts with "InsufficientFee"

**Solutions**:

```javascript
// Quote exact fee
const fee = await shadowSource.quoteSyncFee(tokenId);

// Add 20% buffer
const feeWithBuffer = fee.nativeFee.mul(120).div(100);

// Send with buffer
await shadowSource.syncBAYC(tokenId, refundAddress, {
  value: feeWithBuffer
});
```

### Shadow Already Exists

**Symptoms**: Duplicate mint attempts

**Solutions**:

```bash
# Check if shadow exists before syncing
cast call $SHADOW_APE_ADDRESS \
  "shadowExists(uint256)(bool)" \
  $TOKEN_ID \
  --rpc-url $APECHAIN_RPC_URL
```

## 🔐 Security Best Practices

1. **Multi-Sig Ownership**: Transfer contract ownership to multi-sig
2. **Timelock**: Add timelock for critical parameter changes
3. **Rate Limiting**: Consider adding rate limits for batch sync
4. **Monitoring**: Set up alerts for unusual activity
5. **Emergency Pause**: Keep emergency pause ready but use sparingly

## 📈 Gas Cost Estimates (as of 2025)

| Operation | Ethereum (30 gwei) | ApeChain |
|-----------|-------------------|----------|
| Deploy Source | ~$15-25 | N/A |
| Deploy Shadow | N/A | ~$0.10 |
| Sync Single | ~$3-5 | Free (receive) |
| Batch Sync (100) | ~$250-350 | Free (receive) |
| Delegate | N/A | ~$0.001 |
| Unlock | N/A | ~$0.001 |

## 🎉 Launch Checklist

- [ ] Both contracts deployed and verified
- [ ] Trusted remotes configured on both chains
- [ ] LayerZero DVN configured
- [ ] Test sync completed successfully
- [ ] Base URI pointing to correct metadata
- [ ] Ownership transferred to multi-sig (if applicable)
- [ ] Documentation and frontend updated
- [ ] Community announcement prepared

## 📞 Support

- **LayerZero Discord**: https://discord.gg/layerzero
- **ApeChain Discord**: https://discord.gg/apecoin
- **GitHub Issues**: Open an issue for bugs/features

---

**Deployment completed! Your shadow NFT system is live! 🦍⚡**

