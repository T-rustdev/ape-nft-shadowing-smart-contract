// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "../contracts/ShadowApe.sol";

/**
 * @title Deploy ShadowApe to ApeChain (Foundry)
 * @notice Foundry deployment script for ShadowApe contract
 * 
 * Usage:
 * forge script script/DeployApeChain.s.sol:DeployApeChain --rpc-url $APECHAIN_RPC --broadcast --verify
 */
contract DeployApeChain is Script {
    // ApeChain LayerZero v2 Endpoint
    address constant LZ_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
    
    // Metadata base URI
    string constant BASE_URI = "ipfs://QmShadowApeMetadataHash/";

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== ShadowApe Deployment to ApeChain ===");
        console.log("Deployer:", deployer);
        console.log("LayerZero Endpoint:", LZ_ENDPOINT);
        console.log("Base URI:", BASE_URI);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        ShadowApe shadowApe = new ShadowApe(
            LZ_ENDPOINT,
            deployer,
            BASE_URI
        );

        vm.stopBroadcast();

        console.log("ShadowApe deployed at:", address(shadowApe));
        console.log("");
        console.log("Verification command:");
        console.log('forge verify-contract', address(shadowApe), "contracts/ShadowApe.sol:ShadowApe");
        console.log('--constructor-args $(cast abi-encode "constructor(address,address,string)" ', LZ_ENDPOINT, deployer, BASE_URI, ")");
        console.log('--chain-id 33111'); // ApeChain mainnet
        console.log("");
        console.log("Next steps:");
        console.log("1. Deploy BAYCShadowSource to Ethereum");
        console.log("2. Run SetupLayerZero.s.sol to configure trusted remotes");
    }
}

