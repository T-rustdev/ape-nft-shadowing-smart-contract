# LayerZero v2 Integration Guide ⚡

Complete technical documentation for LayerZero v2 integration in ShadowApe.

## 🏗️ Architecture Overview

```
┌──────────────────────────────────────────────────────────────┐
│                      Ethereum Mainnet                         │
│                                                               │
│  ┌─────────────┐      ┌──────────────────┐                  │
│  │ BAYC NFT    │─────▶│ BAYCShadowSource │                  │
│  │ (External)  │      │  (OApp)          │                  │
│  └─────────────┘      └────────┬─────────┘                  │
│                                │                              │
└────────────────────────────────┼──────────────────────────────┘
                                 │
                                 │ LayerZero v2
                                 │ (DVN + Executor)
                                 │
┌────────────────────────────────┼──────────────────────────────┐
│                                │         ApeChain             │
│                                ▼                              │
│                       ┌─────────────────┐                     │
│                       │   ShadowApe     │                     │
│                       │   (OApp + ERC721│                     │
│                       └─────────────────┘                     │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

## 📡 LayerZero v2 Endpoints

### Mainnet Addresses (2025 Current)

| Network | Endpoint Address | Endpoint ID (EID) |
|---------|-----------------|-------------------|
| Ethereum Mainnet | `0x1a44076050125825900e736c501f859c50fE728c` | `30101` |
| ApeChain Mainnet | `0x1a44076050125825900e736c501f859c50fE728c` | `30151` |

### Testnet Addresses

| Network | Endpoint Address | Endpoint ID (EID) |
|---------|-----------------|-------------------|
| Sepolia | `0x6EDCE65403992e310A62460808c4b910D972f10f` | `40161` |
| Curtis (ApeChain Testnet) | `0x6EDCE65403992e310A62460808c4b910D972f10f` | `40251` |

## 🔧 OApp Implementation

### What is OApp?

**OApp (Omnichain Application)** is LayerZero v2's standard for building cross-chain applications. It provides:

- Message sending/receiving
- Trusted peer management
- Security configuration (DVN, Executor)
- Gas estimation and payment

### Key Components

#### 1. Message Sending (Ethereum → ApeChain)

```solidity
function _sendOwnershipProof(
    uint256 tokenId,
    address previousOwner,
    address currentOwner,
    SyncAction action,
    address refundAddress
) internal returns (bytes32 guid) {
    // Encode payload
    bytes memory payload = abi.encode(
        uint8(action),      // 0=MINT, 1=TRANSFER, 2=BURN
        tokenId,            // BAYC token ID
        currentOwner,       // Current owner
        previousOwner       // Previous owner
    );
    
    // Build options (gas limit)
    bytes memory options = abi.encodePacked(
        uint16(1),          // Option type (gas)
        uint128(dstGasLimit) // 200,000 gas
    );
    
    // Quote fee
    MessagingFee memory fee = _quote(APECHAIN_EID, payload, options, false);
    
    // Send via LayerZero
    MessagingReceipt memory receipt = _lz_send(
        APECHAIN_EID,       // Destination endpoint ID
        payload,            // Encoded message
        options,            // Execution options
        MessagingFee(msg.value, 0), // Fee in native token
        refundAddress       // Refund excess to this address
    );
    
    return receipt.guid;
}
```

#### 2. Message Receiving (ApeChain)

```solidity
function _lzReceive(
    Origin calldata _origin,
    bytes32 _guid,
    bytes calldata _message,
    address _executor,
    bytes calldata _extraData
) internal override {
    // Security: verify source
    if (_origin.srcEid != ETH_MAINNET_EID) revert InvalidSourceChain();
    
    // Decode payload
    (uint8 actionType, uint256 tokenId, address currentOwner, address previousOwner) = 
        abi.decode(_message, (uint8, uint256, address, address));
    
    // Execute action
    SyncAction action = SyncAction(actionType);
    
    if (action == SyncAction.MINT) {
        _handleMint(tokenId, currentOwner);
    } else if (action == SyncAction.TRANSFER) {
        _handleTransfer(tokenId, previousOwner, currentOwner);
    } else if (action == SyncAction.BURN) {
        _handleBurn(tokenId, previousOwner);
    }
    
    emit ShadowSynced(tokenId, currentOwner, action);
}
```

## 🔐 Security Configuration

### Trusted Peers (setPeer)

Both contracts must designate each other as trusted peers:

```solidity
// On ApeChain ShadowApe
function configureTrustedRemote() external onlyOwner {
    // Set Ethereum source as trusted peer
    setPeer(
        30101, // Ethereum EID
        bytes32(uint256(uint160(SHADOW_SOURCE_ADDRESS)))
    );
}

// On Ethereum BAYCShadowSource
function configureTrustedRemote() external onlyOwner {
    // Set ApeChain destination as trusted peer
    setPeer(
        30151, // ApeChain EID
        bytes32(uint256(uint160(SHADOW_APE_ADDRESS)))
    );
}
```

### DVN (Decentralized Verifier Network)

LayerZero v2 uses DVNs to verify cross-chain messages:

**Default DVN Configuration** (automatically set):
- LayerZero Labs DVN
- Google Cloud DVN
- Polyhedra ZK DVN (optional)

**Custom DVN Setup** (advanced):

```solidity
// Set custom DVN configuration
EndpointV2.SetConfigParam memory dvnConfig = EndpointV2.SetConfigParam({
    eid: APECHAIN_EID,
    configType: 2, // DVN config
    config: abi.encode(
        UlnConfig({
            confirmations: 15, // Block confirmations
            requiredDVNCount: 2, // Require 2 DVNs
            optionalDVNCount: 1,
            optionalDVNThreshold: 1,
            requiredDVNs: [dvn1, dvn2],
            optionalDVNs: [dvn3]
        })
    )
});

endpoint.setConfig(address(this), sendLib, dvnConfig);
```

### Executor Configuration

Executors deliver messages to the destination chain:

```solidity
// Set custom executor
EndpointV2.SetConfigParam memory execConfig = EndpointV2.SetConfigParam({
    eid: APECHAIN_EID,
    configType: 1, // Executor config
    config: abi.encode(
        ExecutorConfig({
            maxMessageSize: 10000, // Max message size in bytes
            executor: LAYERZERO_EXECUTOR // Executor address
        })
    )
});

endpoint.setConfig(address(this), sendLib, execConfig);
```

## ⛽ Gas & Fee Management

### Gas Estimation

```javascript
// Quote exact fee for a sync
const payload = ethers.AbiCoder.defaultAbiCoder().encode(
    ["uint8", "uint256", "address", "address"],
    [0, tokenId, currentOwner, previousOwner]
);

const options = ethers.solidityPacked(
    ["uint16", "uint128"],
    [1, 200000] // 200k gas
);

const fee = await shadowSource.quote(
    30151, // ApeChain EID
    payload,
    options,
    false // Pay in native token
);

console.log("Fee:", ethers.formatEther(fee.nativeFee), "ETH");
```

### Fee Calculation

**Fee = (Destination Gas × Gas Price) + DVN Fees + Executor Fees**

**Typical Costs** (as of 2025):
- **Ethereum → ApeChain**: ~0.003-0.005 ETH (~$8-15)
- **DVN Fee**: ~$1-2
- **Executor Fee**: ~$1-2
- **Destination Gas**: Free on ApeChain (very low)

### Fee Optimization

1. **Batch Operations**: Amortize fixed costs over multiple messages
2. **Gas Limits**: Set `dstGasLimit` to minimum required (200k is safe)
3. **Native Fee Payment**: Pay in native tokens (not LZ token) for better rates
4. **Refund Address**: Always set refund address to recover excess fees

```javascript
// Optimized sync with refund
const fee = await shadowSource.quoteSyncFee(tokenId);
const buffer = (fee.nativeFee * 105n) / 100n; // 5% buffer

await shadowSource.syncBAYC(
    tokenId,
    myAddress, // Refund address - will receive excess
    { value: buffer }
);
```

## 🔄 Message Flow

### Complete Flow Timeline

```
T+0s   │ User calls syncBAYC() on Ethereum
       │ ├─ Encode payload
       │ ├─ Calculate fee
       │ └─ Call LayerZero endpoint.send()
       │
T+5s   │ Ethereum transaction confirmed
       │ └─ Event: PacketSent
       │
T+15s  │ DVN 1 verifies block finality
       │ DVN 2 verifies block finality
       │ └─ Both DVNs sign verification
       │
T+30s  │ Executor detects verified message
       │ ├─ Builds delivery transaction
       │ └─ Submits to ApeChain
       │
T+45s  │ ApeChain receives message
       │ ├─ Calls _lzReceive()
       │ ├─ Mints/transfers shadow
       │ └─ Event: ShadowMinted/ShadowSynced
       │
✅     │ Sync complete!
```

### Retry Mechanism

If delivery fails, messages can be retried:

```javascript
// Get failed message
const failedMessages = await endpoint.getInboundNonce(
    APECHAIN_EID,
    shadowSourceAddress
);

// Retry delivery
await endpoint.retry(
    APECHAIN_EID,
    shadowSourceAddress,
    payload,
    { gasLimit: 500000 } // Higher gas limit
);
```

## 📊 Monitoring & Debugging

### LayerZero Scan

Track all cross-chain messages:
- **URL**: https://layerzeroscan.com/
- **Search**: By TX hash, address, or GUID

### Event Monitoring

```javascript
// Listen for sent messages
shadowSource.on("OwnershipProofSent", (tokenId, from, to, action, guid) => {
    console.log(`Message sent: GUID ${guid}`);
    console.log(`Token ${tokenId}: ${from} → ${to}`);
});

// Listen for received messages
shadowApe.on("ShadowSynced", (tokenId, newOwner, action) => {
    console.log(`Shadow synced: Token ${tokenId} → ${newOwner}`);
});
```

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Message not delivered | Insufficient gas | Increase `dstGasLimit` |
| "Invalid source" error | Peer not set | Call `setPeer()` on both chains |
| Fee too low | Gas spike | Add 10-20% buffer to quoted fee |
| Retry failed | Payload changed | Use exact original payload |

## 🛠️ Advanced Features

### Pre-Crime Module (Optional)

Pre-crime prevents malicious messages before delivery:

```solidity
// Enable pre-crime
shadowApe.setPreCrime(preCrimeAddress);

// Pre-crime checks:
// - Payload validity
// - State consistency
// - Replay protection
```

### Custom Adapter Params

```solidity
// Build advanced options
bytes memory options = abi.encodePacked(
    uint16(1), uint128(200000),    // Gas option
    uint16(2), uint128(0.1 ether), // Airdrop option (send native tokens)
    uint16(3), bytes("custom data") // Custom option
);
```

### Ordered Message Delivery

Ensure messages arrive in order:

```solidity
// Enable ordered delivery
shadowApe.setConfig(
    APECHAIN_EID,
    CONFIG_TYPE_ORDERED,
    abi.encode(true)
);
```

## ✅ Best Practices

1. **Always Set Refund Address**: Recover excess fees
2. **Buffer Gas Estimates**: Add 5-10% to quoted fees
3. **Verify Source Chain**: Check `_origin.srcEid` in `_lzReceive`
4. **Handle Failures Gracefully**: Implement retry logic
5. **Monitor Message Status**: Use LayerZero Scan
6. **Test on Testnet First**: Curtis ↔ Sepolia
7. **Use Enforced Options**: Set minimum gas limits
8. **Keep Trusted Peers Updated**: Review after upgrades

## 🔗 Resources

- **LayerZero Docs**: https://docs.layerzero.network/
- **LayerZero Scan**: https://layerzeroscan.com/
- **DVN Explorer**: https://layerzero.network/dvn
- **GitHub**: https://github.com/LayerZero-Labs/LayerZero-v2

---

**LayerZero v2 - The Omnichain Messaging Protocol 🌐⚡**

