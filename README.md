# ShadowApe 🦍⚡

**Automatic BAYC shadow NFT system for ApeChain using LayerZero v2**

ShadowApe creates soulbound "shadow" NFTs on ApeChain that automatically mirror Bored Ape Yacht Club (BAYC) ownership on Ethereum Mainnet. When a BAYC token is transferred on Ethereum, its corresponding shadow is automatically minted/transferred/burned on ApeChain via LayerZero's omnichain messaging protocol.

## 🌟 Features

- **Automatic Cross-Chain Sync**: Uses LayerZero v2 for trustless, automatic synchronization
- **Soulbound by Default**: Shadows are non-transferable unless explicitly unlocked by the original owner
- **Safe Delegation**: Owners can delegate control to a single wallet (for staking/gaming) without transferring ownership
- **Gas-Optimized**: Built for ApeChain's Arbitrum Orbit architecture with minimal gas costs
- **Production-Ready**: Full test coverage, audited patterns, emergency controls

## 📋 Architecture

```
┌─────────────────┐                    ┌─────────────────┐
│   Ethereum      │                    │    ApeChain     │
│                 │                    │                 │
│  BAYC Contract  │                    │                 │
│       ↓         │                    │                 │
│ BAYCShadowSource├──── LayerZero ────→│   ShadowApe    │
│  (tracks BAYC)  │     (v2 OApp)      │  (shadow NFT)   │
└─────────────────┘                    └─────────────────┘
```

### Contracts

1. **ShadowApe.sol** (ApeChain)
   - ERC721Enumerable shadow NFT contract
   - Receives LayerZero messages to mint/transfer/burn shadows
   - Enforces soulbound behavior and delegation rules

2. **BAYCShadowSource.sol** (Ethereum)
   - Tracks BAYC ownership changes
   - Sends LayerZero messages to ApeChain when ownership changes
   - Supports manual sync and batch operations

## 🚀 Quick Start

### Prerequisites

- Node.js 18+
- Hardhat or Foundry
- Private key with ETH (for Ethereum) and APE (for ApeChain)

### Installation

```bash
# Clone the repository
git clone https://github.com/your-org/shadowape
cd shadowape

# Install dependencies
npm install

# Copy environment template
cp .env.example .env
# Edit .env with your keys
```

### Environment Setup

Create a `.env` file:

```bash
PRIVATE_KEY=your_private_key_here
ETH_RPC_URL=https://eth.llamarpc.com
APECHAIN_RPC_URL=https://rpc.apechain.com/http
ETHERSCAN_API_KEY=your_etherscan_api_key
```

## 📦 Deployment

### Option 1: Hardhat

```bash
# 1. Deploy to ApeChain
npm run deploy:apechain

# 2. Deploy to Ethereum Mainnet
npm run deploy:ethereum

# 3. Configure LayerZero trusted remotes
# Update addresses in scripts/configure-layerzero.js
npm run configure:apechain
npm run configure:ethereum
```

### Option 2: Foundry

```bash
# 1. Deploy to ApeChain
forge script script/DeployApeChain.s.sol --rpc-url $APECHAIN_RPC_URL --broadcast --verify

# 2. Deploy to Ethereum
forge script script/DeployEthereum.s.sol --rpc-url $ETH_RPC_URL --broadcast --verify

# 3. Configure trusted remotes (update addresses in script)
forge script script/SetupLayerZero.s.sol --rpc-url $APECHAIN_RPC_URL --broadcast
forge script script/SetupLayerZero.s.sol --rpc-url $ETH_RPC_URL --broadcast
```

## ⚙️ Configuration

### LayerZero Endpoint Addresses (2025 Current)

- **Ethereum Mainnet**: `0x1a44076050125825900e736c501f859c50fE728c`
- **ApeChain Mainnet**: `0x1a44076050125825900e736c501f859c50fE728c`

### Endpoint IDs

- **Ethereum Mainnet EID**: `30101`
- **ApeChain EID**: `30151`

### Setting Trusted Remotes

After deployment, configure trusted remotes on both chains:

```javascript
// On ApeChain
await shadowApe.setPeer(
    30101, // Ethereum EID
    ethers.zeroPadValue(SHADOW_SOURCE_ADDRESS, 32)
);

// On Ethereum
await shadowSource.setPeer(
    30151, // ApeChain EID
    ethers.zeroPadValue(SHADOW_APE_ADDRESS, 32)
);
```

## 🧪 Testing

### Sync a BAYC Token

```bash
# Update TEST_TOKEN_ID and SHADOW_SOURCE_ADDRESS in scripts/test-sync.js
npm run test:sync
```

### Test Flow

1. **Initial Sync**: Call `syncBAYC(tokenId)` on Ethereum
2. **LayerZero Processing**: ~5-30 seconds for message delivery
3. **Shadow Minted**: Check ApeChain - shadow NFT minted to BAYC owner

### Example Payload Format

LayerZero messages use this format:

```solidity
bytes memory payload = abi.encode(
    uint8(action),      // 0=MINT, 1=TRANSFER, 2=BURN
    uint256(tokenId),   // BAYC token ID
    address(currentOwner), // Current owner on Ethereum
    address(previousOwner) // Previous owner
);
```

## 📚 Usage Examples

### Delegation (for Staking/Gaming)

```solidity
// Delegate your shadow to a staking contract
shadowApe.delegateShadow(tokenId, stakingContractAddress);

// Revoke delegation
shadowApe.revokeDelegation(tokenId);
```

### Unlocking (Make Transferable)

```solidity
// Permanently unlock your shadow (irreversible!)
shadowApe.unlockShadow(tokenId);

// Now you can transfer it
shadowApe.transferFrom(from, to, tokenId);
```

### View Functions

```solidity
// Check if shadow exists
bool exists = shadowApe.shadowExists(tokenId);

// Get delegate
address delegate = shadowApe.getShadowDelegate(tokenId);

// Check if unlocked
bool unlocked = shadowApe.isShadowUnlocked(tokenId);

// Get all shadows owned by address
uint256[] memory tokenIds = shadowApe.getShadowsByOwner(ownerAddress);
```

## 🔒 Security Features

- ✅ **Reentrancy Protection**: All state-changing functions use `nonReentrant`
- ✅ **Access Control**: Owner-only admin functions, proper permission checks
- ✅ **Pausable**: Emergency pause for incoming LayerZero messages
- ✅ **Trusted Remotes**: Only accepts messages from configured source chain
- ✅ **Gas Limits**: Enforced minimum gas for execution safety
- ✅ **Custom Errors**: Gas-efficient error handling

## 📊 Gas Estimates

| Operation | Ethereum (Gwei) | ApeChain (APE) |
|-----------|----------------|----------------|
| Sync Single Token | ~0.003 ETH | < 0.001 APE |
| Delegate Shadow | - | < 0.0001 APE |
| Unlock Shadow | - | < 0.0001 APE |
| Transfer (unlocked) | - | < 0.0001 APE |

*Note: ApeChain fees are extremely low (~0.1 gwei base)*

## 🛠️ Development

### Run Tests

```bash
# Hardhat
npx hardhat test

# Foundry
forge test -vvv
```

### Test Scenarios

1. **Soulbound Behavior**
   - ✅ Transfers revert when locked
   - ✅ Transfers succeed after unlock
   - ✅ Unlock is permanent and irreversible

2. **Delegation**
   - ✅ Owner can delegate to single address
   - ✅ Owner can revoke delegation
   - ✅ Delegation clears on ownership change
   - ✅ Non-owners cannot delegate

3. **Cross-Chain Sync**
   - ✅ Mint on first sync
   - ✅ Transfer on ownership change
   - ✅ Burn when BAYC no longer owned
   - ✅ Batch sync operations

## 🎯 Verification

### ApeChain Blockscout

```bash
npx hardhat verify --network apechain \
  SHADOW_APE_ADDRESS \
  "0x1a44076050125825900e736c501f859c50fE728c" \
  "YOUR_ADDRESS" \
  "ipfs://QmYourHash/"
```

### Etherscan

```bash
npx hardhat verify --network mainnet \
  SHADOW_SOURCE_ADDRESS \
  "0x1a44076050125825900e736c501f859c50fE728c" \
  "YOUR_ADDRESS"
```

## 🌐 Network Information

### ApeChain Mainnet

- **Chain ID**: 33139
- **RPC**: https://rpc.apechain.com/http
- **Explorer**: https://apescan.io
- **Currency**: APE

### Curtis Testnet

- **Chain ID**: 33111
- **RPC**: https://curtis.rpc.caldera.xyz/http
- **Explorer**: https://curtis.explorer.caldera.xyz
- **Faucet**: [Curtis Faucet](https://curtis.apechainfaucet.com)

## 📄 License

MIT License - see [LICENSE](LICENSE) for details

## 🤝 Contributing

Contributions welcome! Please open an issue or PR.

## 🔗 Resources

- [LayerZero v2 Docs](https://docs.layerzero.network/)
- [ApeChain Documentation](https://docs.apechain.com/)
- [BAYC Contract](https://etherscan.io/address/0xbc4ca0eda7647a8ab7c2061c2e118a18a936f13d)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts/)

## ⚠️ Disclaimer

This is experimental software. Use at your own risk. Always audit smart contracts before deploying to mainnet with real assets.

---

**Built with 🦍 for the ApeChain ecosystem**

