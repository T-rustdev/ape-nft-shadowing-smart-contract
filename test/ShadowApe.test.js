const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ShadowApe", function () {
    let shadowApe;
    let mockLZEndpoint;
    let owner;
    let user1;
    let user2;
    let delegate;

    const TOKEN_ID = 1;
    const BASE_URI = "ipfs://QmTest/";
    const ETH_MAINNET_EID = 30101;

    beforeEach(async function () {
        [owner, user1, user2, delegate] = await ethers.getSigners();

        // Deploy mock LayerZero endpoint
        const MockLZEndpoint = await ethers.getContractFactory("MockLayerZeroEndpoint");
        mockLZEndpoint = await MockLZEndpoint.deploy();

        // Deploy ShadowApe
        const ShadowApe = await ethers.getContractFactory("ShadowApe");
        shadowApe = await ShadowApe.deploy(
            await mockLZEndpoint.getAddress(),
            owner.address,
            BASE_URI
        );
    });

    describe("Deployment", function () {
        it("Should set the correct name and symbol", async function () {
            expect(await shadowApe.name()).to.equal("ShadowApe");
            expect(await shadowApe.symbol()).to.equal("sAPE");
        });

        it("Should set the correct owner", async function () {
            expect(await shadowApe.owner()).to.equal(owner.address);
        });

        it("Should set the correct base URI", async function () {
            expect(await shadowApe._baseURI()).to.equal(BASE_URI);
        });
    });

    describe("Soulbound Behavior", function () {
        beforeEach(async function () {
            // Simulate LayerZero mint message
            const payload = ethers.AbiCoder.defaultAbiCoder().encode(
                ["uint8", "uint256", "address", "address"],
                [0, TOKEN_ID, user1.address, ethers.ZeroAddress] // MINT action
            );

            await shadowApe.connect(owner).emergencyMint(TOKEN_ID, user1.address);
        });

        it("Should prevent transfer when locked", async function () {
            await expect(
                shadowApe.connect(user1).transferFrom(user1.address, user2.address, TOKEN_ID)
            ).to.be.revertedWithCustomError(shadowApe, "ShadowIsLocked");
        });

        it("Should allow transfer after unlocking", async function () {
            // Unlock shadow
            await shadowApe.connect(user1).unlockShadow(TOKEN_ID);

            // Now transfer should work
            await expect(
                shadowApe.connect(user1).transferFrom(user1.address, user2.address, TOKEN_ID)
            ).to.not.be.reverted;

            expect(await shadowApe.ownerOf(TOKEN_ID)).to.equal(user2.address);
        });

        it("Should emit ShadowUnlocked event", async function () {
            await expect(shadowApe.connect(user1).unlockShadow(TOKEN_ID))
                .to.emit(shadowApe, "ShadowUnlocked")
                .withArgs(TOKEN_ID, user1.address, await time.latest() + 1);
        });
    });

    describe("Delegation", function () {
        beforeEach(async function () {
            await shadowApe.connect(owner).emergencyMint(TOKEN_ID, user1.address);
        });

        it("Should allow owner to delegate shadow", async function () {
            await expect(shadowApe.connect(user1).delegateShadow(TOKEN_ID, delegate.address))
                .to.emit(shadowApe, "ShadowDelegated")
                .withArgs(TOKEN_ID, user1.address, delegate.address);

            expect(await shadowApe.getShadowDelegate(TOKEN_ID)).to.equal(delegate.address);
        });

        it("Should allow owner to revoke delegation", async function () {
            await shadowApe.connect(user1).delegateShadow(TOKEN_ID, delegate.address);
            
            await expect(shadowApe.connect(user1).revokeDelegation(TOKEN_ID))
                .to.emit(shadowApe, "DelegationRevoked")
                .withArgs(TOKEN_ID, user1.address, delegate.address);

            expect(await shadowApe.getShadowDelegate(TOKEN_ID)).to.equal(ethers.ZeroAddress);
        });

        it("Should prevent non-owner from delegating", async function () {
            await expect(
                shadowApe.connect(user2).delegateShadow(TOKEN_ID, delegate.address)
            ).to.be.revertedWithCustomError(shadowApe, "NotShadowOwner");
        });

        it("Should clear delegation on ownership change", async function () {
            // Delegate
            await shadowApe.connect(user1).delegateShadow(TOKEN_ID, delegate.address);
            
            // Unlock and transfer
            await shadowApe.connect(user1).unlockShadow(TOKEN_ID);
            await shadowApe.connect(user1).transferFrom(user1.address, user2.address, TOKEN_ID);

            // Delegation should be cleared
            expect(await shadowApe.getShadowDelegate(TOKEN_ID)).to.equal(ethers.ZeroAddress);
        });
    });

    describe("View Functions", function () {
        beforeEach(async function () {
            await shadowApe.connect(owner).emergencyMint(TOKEN_ID, user1.address);
        });

        it("Should return correct shadow info", async function () {
            const info = await shadowApe.getShadowInfo(TOKEN_ID);
            
            expect(info.owner).to.equal(user1.address);
            expect(info.delegate).to.equal(ethers.ZeroAddress);
            expect(info.unlocked).to.equal(false);
        });

        it("Should return if shadow exists", async function () {
            expect(await shadowApe.shadowExists(TOKEN_ID)).to.equal(true);
            expect(await shadowApe.shadowExists(999)).to.equal(false);
        });

        it("Should return all shadows owned by address", async function () {
            await shadowApe.connect(owner).emergencyMint(2, user1.address);
            await shadowApe.connect(owner).emergencyMint(3, user1.address);

            const shadows = await shadowApe.getShadowsByOwner(user1.address);
            expect(shadows.length).to.equal(3);
            expect(shadows).to.include(BigInt(TOKEN_ID));
        });
    });

    describe("Admin Functions", function () {
        it("Should allow owner to pause", async function () {
            await shadowApe.connect(owner).setPaused(true);
            expect(await shadowApe.paused()).to.equal(true);
        });

        it("Should prevent non-owner from pausing", async function () {
            await expect(
                shadowApe.connect(user1).setPaused(true)
            ).to.be.revertedWithCustomError(shadowApe, "OwnableUnauthorizedAccount");
        });

        it("Should allow owner to update base URI", async function () {
            const newURI = "ipfs://QmNewHash/";
            await expect(shadowApe.connect(owner).setBaseURI(newURI))
                .to.emit(shadowApe, "BaseURIUpdated")
                .withArgs(newURI);
        });

        it("Should allow emergency mint", async function () {
            await expect(shadowApe.connect(owner).emergencyMint(99, user1.address))
                .to.emit(shadowApe, "ShadowMinted")
                .withArgs(99, user1.address, await time.latest() + 1);
        });
    });

    describe("Metadata", function () {
        beforeEach(async function () {
            await shadowApe.connect(owner).emergencyMint(TOKEN_ID, user1.address);
        });

        it("Should return correct token URI", async function () {
            expect(await shadowApe.tokenURI(TOKEN_ID)).to.equal(BASE_URI + TOKEN_ID);
        });
    });
});

// Helper to get latest block timestamp
const time = {
    latest: async () => {
        const block = await ethers.provider.getBlock("latest");
        return block.timestamp;
    }
};

