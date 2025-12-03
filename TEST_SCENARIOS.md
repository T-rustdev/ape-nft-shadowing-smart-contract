# ShadowApe Test Scenarios 🧪

Comprehensive test scenarios for delegation, soulbound behavior, and cross-chain sync.

## 🎯 Test Categories

1. **Soulbound Behavior Tests**
2. **Delegation Tests**
3. **Cross-Chain Sync Tests**
4. **Edge Cases & Security Tests**

---

## 1. Soulbound Behavior Tests

### Test 1.1: Transfer Blocked When Locked

**Setup:**
```javascript
// Mint shadow to user1
await shadowApe.emergencyMint(TOKEN_ID, user1.address);
```

**Test:**
```javascript
// Attempt transfer (should fail)
await expect(
  shadowApe.connect(user1).transferFrom(user1.address, user2.address, TOKEN_ID)
).to.be.revertedWithCustomError(shadowApe, "ShadowIsLocked");
```

**Expected**: ❌ Transaction reverts with `ShadowIsLocked`

---

### Test 1.2: Transfer Succeeds After Unlock

**Setup:**
```javascript
await shadowApe.emergencyMint(TOKEN_ID, user1.address);
```

**Test:**
```javascript
// Unlock shadow
await shadowApe.connect(user1).unlockShadow(TOKEN_ID);

// Transfer should succeed
await shadowApe.connect(user1).transferFrom(user1.address, user2.address, TOKEN_ID);

// Verify new owner
expect(await shadowApe.ownerOf(TOKEN_ID)).to.equal(user2.address);
```

**Expected**: ✅ Transfer succeeds, user2 is new owner

---

### Test 1.3: Unlock is Permanent

**Test:**
```javascript
await shadowApe.emergencyMint(TOKEN_ID, user1.address);
await shadowApe.connect(user1).unlockShadow(TOKEN_ID);

// Attempt to "relock" (no such function exists)
// Transfer to user2
await shadowApe.connect(user1).transferFrom(user1.address, user2.address, TOKEN_ID);

// user2 can transfer again (still unlocked)
await shadowApe.connect(user2).transferFrom(user2.address, user3.address, TOKEN_ID);
```

**Expected**: ✅ Once unlocked, shadow remains transferable forever

---

### Test 1.4: Only Original Owner Can Unlock

**Setup:**
```javascript
await shadowApe.emergencyMint(TOKEN_ID, user1.address);

// Simulate cross-chain transfer (force transfer while locked)
await shadowApe.connect(owner).emergencyBurn(TOKEN_ID);
await shadowApe.emergencyMint(TOKEN_ID, user2.address);
```

**Test:**
```javascript
// user2 tries to unlock (should fail - not original owner)
await expect(
  shadowApe.connect(user2).unlockShadow(TOKEN_ID)
).to.be.revertedWithCustomError(shadowApe, "NotAuthorized");
```

**Expected**: ❌ Only original minter can unlock

---

### Test 1.5: SafeTransferFrom Also Blocked

**Test:**
```javascript
await shadowApe.emergencyMint(TOKEN_ID, user1.address);

// Try safeTransferFrom (should also fail)
await expect(
  shadowApe.connect(user1)["safeTransferFrom(address,address,uint256)"](
    user1.address,
    user2.address,
    TOKEN_ID
  )
).to.be.revertedWithCustomError(shadowApe, "ShadowIsLocked");
```

**Expected**: ❌ All transfer methods blocked when locked

---

## 2. Delegation Tests

### Test 2.1: Owner Can Delegate

**Setup:**
```javascript
await shadowApe.emergencyMint(TOKEN_ID, user1.address);
```

**Test:**
```javascript
// Delegate to stakingContract
await expect(
  shadowApe.connect(user1).delegateShadow(TOKEN_ID, stakingContract.address)
)
  .to.emit(shadowApe, "ShadowDelegated")
  .withArgs(TOKEN_ID, user1.address, stakingContract.address);

// Verify delegation
expect(await shadowApe.getShadowDelegate(TOKEN_ID)).to.equal(stakingContract.address);
```

**Expected**: ✅ Delegation succeeds, event emitted

---

### Test 2.2: Only Owner Can Delegate

**Test:**
```javascript
await shadowApe.emergencyMint(TOKEN_ID, user1.address);

// user2 tries to delegate (should fail)
await expect(
  shadowApe.connect(user2).delegateShadow(TOKEN_ID, stakingContract.address)
).to.be.revertedWithCustomError(shadowApe, "NotShadowOwner");
```

**Expected**: ❌ Non-owners cannot delegate

---

### Test 2.3: Delegation Can Be Revoked

**Test:**
```javascript
await shadowApe.emergencyMint(TOKEN_ID, user1.address);
await shadowApe.connect(user1).delegateShadow(TOKEN_ID, stakingContract.address);

// Revoke delegation
await expect(
  shadowApe.connect(user1).revokeDelegation(TOKEN_ID)
)
  .to.emit(shadowApe, "DelegationRevoked")
  .withArgs(TOKEN_ID, user1.address, stakingContract.address);

// Verify delegation cleared
expect(await shadowApe.getShadowDelegate(TOKEN_ID)).to.equal(ethers.ZeroAddress);
```

**Expected**: ✅ Delegation revoked, event emitted

---

### Test 2.4: Delegation Cleared on Ownership Change

**Test:**
```javascript
await shadowApe.emergencyMint(TOKEN_ID, user1.address);
await shadowApe.connect(user1).delegateShadow(TOKEN_ID, stakingContract.address);

// Unlock and transfer
await shadowApe.connect(user1).unlockShadow(TOKEN_ID);
await shadowApe.connect(user1).transferFrom(user1.address, user2.address, TOKEN_ID);

// Delegation should be cleared
expect(await shadowApe.getShadowDelegate(TOKEN_ID)).to.equal(ethers.ZeroAddress);
```

**Expected**: ✅ Delegation automatically cleared on transfer

---

### Test 2.5: Delegation Doesn't Grant Transfer Rights

**Test:**
```javascript
await shadowApe.emergencyMint(TOKEN_ID, user1.address);
await shadowApe.connect(user1).delegateShadow(TOKEN_ID, delegate.address);

// Delegate tries to transfer (should fail - shadow still locked)
await expect(
  shadowApe.connect(delegate).transferFrom(user1.address, user2.address, TOKEN_ID)
).to.be.revertedWithCustomError(shadowApe, "ShadowIsLocked");
```

**Expected**: ❌ Delegation does NOT grant transfer permission (only for reading/staking use cases)

---

## 3. Cross-Chain Sync Tests

### Test 3.1: Ethereum Transfer → ApeChain Mint

**Scenario**: User acquires BAYC #100 on Ethereum for the first time

**Ethereum Steps:**
```javascript
// Sync BAYC #100
const fee = await shadowSource.quoteSyncFee(100);
await shadowSource.syncBAYC(100, deployerAddress, { value: fee.nativeFee });
```

**Expected Timeline:**
- T+0s: TX confirmed on Ethereum
- T+15s: LayerZero DVN verifies
- T+30s: Message delivered to ApeChain
- T+45s: Shadow #100 minted

**ApeChain Verification:**
```javascript
// Check shadow exists
expect(await shadowApe.shadowExists(100)).to.equal(true);

// Check owner matches Ethereum BAYC owner
const baycOwner = await bayc.ownerOf(100);
expect(await shadowApe.ownerOf(100)).to.equal(baycOwner);

// Check shadow is locked
expect(await shadowApe.isShadowUnlocked(100)).to.equal(false);
```

**Expected**: ✅ Shadow minted to correct owner, locked by default

---

### Test 3.2: Ethereum Transfer → ApeChain Transfer

**Scenario**: BAYC #100 transferred from Alice to Bob on Ethereum

**Ethereum Steps:**
```javascript
// Alice transfers BAYC to Bob
await bayc.connect(alice).transferFrom(alice.address, bob.address, 100);

// Sync the change
await shadowSource.syncBAYC(100, deployerAddress, { value: fee.nativeFee });
```

**ApeChain Expected:**
```javascript
// Shadow owner should update to Bob
expect(await shadowApe.ownerOf(100)).to.equal(bob.address);

// Delegation should be cleared
expect(await shadowApe.getShadowDelegate(100)).to.equal(ethers.ZeroAddress);
```

**Expected**: ✅ Shadow transfers to new owner, delegation cleared

---

### Test 3.3: Batch Sync Multiple Tokens

**Test:**
```javascript
const tokenIds = [1, 2, 3, 4, 5];
const fee = await shadowSource.quoteBatchSyncFee(tokenIds.length);

await shadowSource.batchSyncBAYC(
  tokenIds,
  deployerAddress,
  { value: fee.mul(110).div(100) } // 10% buffer
);
```

**Expected**: ✅ All 5 shadows minted within 60 seconds

---

### Test 3.4: Sync Non-Existent Token (Should Handle Gracefully)

**Test:**
```javascript
// BAYC only has tokens 0-9999
await expect(
  shadowSource.syncBAYC(10000, deployerAddress, { value: fee.nativeFee })
).to.be.revertedWithCustomError(shadowSource, "InvalidTokenId");
```

**Expected**: ❌ Reverts with InvalidTokenId

---

### Test 3.5: Burn Shadow When BAYC Burned (Edge Case)

**Note**: BAYC doesn't support burning, but test the mechanism

**Test:**
```javascript
// Admin reports burn
await shadowSource.connect(owner).reportBAYCBurn(
  100,
  deployerAddress,
  { value: fee.nativeFee }
);

// Wait for message delivery...

// Shadow should be burned on ApeChain
await expect(
  shadowApe.ownerOf(100)
).to.be.revertedWithCustomError(shadowApe, "ERC721NonexistentToken");
```

**Expected**: ✅ Shadow burned, token no longer exists

---

## 4. Edge Cases & Security Tests

### Test 4.1: Emergency Pause Blocks Messages

**Test:**
```javascript
// Pause incoming messages
await shadowApe.connect(owner).setPaused(true);

// Attempt to process LayerZero message (should fail)
// This would be tested via mock LayerZero endpoint
```

**Expected**: ❌ Messages blocked while paused

---

### Test 4.2: Unpause Resumes Normal Operation

**Test:**
```javascript
await shadowApe.connect(owner).setPaused(true);
await shadowApe.connect(owner).setPaused(false);

// Normal sync should work again
await shadowSource.syncBAYC(200, deployerAddress, { value: fee.nativeFee });
```

**Expected**: ✅ Sync resumes after unpause

---

### Test 4.3: Non-Owner Cannot Pause

**Test:**
```javascript
await expect(
  shadowApe.connect(user1).setPaused(true)
).to.be.revertedWithCustomError(shadowApe, "OwnableUnauthorizedAccount");
```

**Expected**: ❌ Only owner can pause

---

### Test 4.4: Cannot Unlock Twice

**Test:**
```javascript
await shadowApe.emergencyMint(TOKEN_ID, user1.address);
await shadowApe.connect(user1).unlockShadow(TOKEN_ID);

await expect(
  shadowApe.connect(user1).unlockShadow(TOKEN_ID)
).to.be.revertedWithCustomError(shadowApe, "AlreadyUnlocked");
```

**Expected**: ❌ Cannot unlock already unlocked shadow

---

### Test 4.5: View Functions for Non-Existent Token

**Test:**
```javascript
await expect(
  shadowApe.getShadowDelegate(9999)
).to.be.revertedWithCustomError(shadowApe, "ShadowDoesNotExist");

await expect(
  shadowApe.isShadowUnlocked(9999)
).to.be.revertedWithCustomError(shadowApe, "ShadowDoesNotExist");
```

**Expected**: ❌ Proper error for non-existent tokens

---

### Test 4.6: Get All Shadows Owned by Address

**Test:**
```javascript
await shadowApe.emergencyMint(1, user1.address);
await shadowApe.emergencyMint(5, user1.address);
await shadowApe.emergencyMint(10, user1.address);

const shadows = await shadowApe.getShadowsByOwner(user1.address);

expect(shadows.length).to.equal(3);
expect(shadows).to.include(BigInt(1));
expect(shadows).to.include(BigInt(5));
expect(shadows).to.include(BigInt(10));
```

**Expected**: ✅ Returns all owned shadow IDs

---

### Test 4.7: Token URI Returns Correct Metadata

**Test:**
```javascript
await shadowApe.emergencyMint(TOKEN_ID, user1.address);

const baseURI = "ipfs://QmTest/";
const expectedURI = baseURI + TOKEN_ID + ".json";

expect(await shadowApe.tokenURI(TOKEN_ID)).to.equal(expectedURI);
```

**Expected**: ✅ Correct metadata URI

---

### Test 4.8: Base URI Can Be Updated

**Test:**
```javascript
const newURI = "ipfs://QmNewHash/";

await expect(shadowApe.connect(owner).setBaseURI(newURI))
  .to.emit(shadowApe, "BaseURIUpdated")
  .withArgs(newURI);

// Verify new URI
await shadowApe.emergencyMint(TOKEN_ID, user1.address);
expect(await shadowApe.tokenURI(TOKEN_ID)).to.include(newURI);
```

**Expected**: ✅ Base URI updated successfully

---

## 🚀 Quick Test Execution

### Run All Tests

```bash
# Hardhat
npx hardhat test

# Foundry
forge test -vvv

# With gas reporting
npx hardhat test --gas-reporter
```

### Run Specific Test Suite

```bash
# Only soulbound tests
npx hardhat test --grep "Soulbound"

# Only delegation tests
npx hardhat test --grep "Delegation"

# Only cross-chain tests
npx hardhat test --grep "Cross-Chain"
```

### Test on Fork

```bash
# Fork Ethereum mainnet for realistic BAYC interaction
npx hardhat test --network hardhat --fork https://eth.llamarpc.com
```

---

## 📊 Expected Test Coverage

| Category | Tests | Coverage Target |
|----------|-------|----------------|
| Soulbound | 5 | 100% |
| Delegation | 5 | 100% |
| Cross-Chain | 5 | 90%+ |
| Edge Cases | 8 | 100% |
| **Total** | **23** | **95%+** |

---

## ✅ Test Success Criteria

All tests must pass with:
- ✅ No reverts (except expected ones)
- ✅ Correct event emissions
- ✅ Proper state changes
- ✅ Gas usage within reasonable limits
- ✅ No security vulnerabilities

**Ready for mainnet deployment! 🦍⚡**

