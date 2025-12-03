// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "../contracts/ethereum/BAYCShadowSource.sol";

/**
 * @title Deploy BAYCShadowSource to Ethereum (Foundry)
 * @notice Foundry deployment script for BAYCShadowSource contract
 * 
 * Usage:
 * forge script script/DeployEthereum.s.sol:DeployEthereum --rpc-url $ETH_RPC --broadcast --verify
 */
contract DeployEthereum is Script {
    // Ethereum Mainnet LayerZero v2 Endpoint
    address constant LZ_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== BAYCShadowSource Deployment to Ethereum ===");
        console.log("Deployer:", deployer);
        console.log("LayerZero Endpoint:", LZ_ENDPOINT);
        console.log("BAYC Address: 0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D");
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        BAYCShadowSource shadowSource = new BAYCShadowSource(
            LZ_ENDPOINT,
            deployer
        );

        vm.stopBroadcast();

        console.log("BAYCShadowSource deployed at:", address(shadowSource));
        console.log("");
        console.log("Verification command:");
        console.log('forge verify-contract', address(shadowSource), "contracts/ethereum/BAYCShadowSource.sol:BAYCShadowSource");
        console.log('--constructor-args $(cast abi-encode "constructor(address,address)" ', LZ_ENDPOINT, deployer, ")");
        console.log('--chain-id 1'); // Ethereum mainnet
        console.log("");
        console.log("Next steps:");
        console.log("1. Run SetupLayerZero.s.sol to configure trusted remotes");
        console.log("2. Test sync with a BAYC token");
    }
}

