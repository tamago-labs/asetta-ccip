// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import "../src/RWATokenFactory.sol";
import "../src/RWAToken.sol";

/**
 * @title DeployRWATokenFactoryMultiChain
 * @notice Deploy RWATokenFactory to testnets and create test tokens
 * @dev Usage (run on each chain): 
 *   forge script script/DeployRWATokenFactoryMultiChain.s.sol --rpc-url $ETHEREUM_SEPOLIA_RPC_URL --broadcast --verify
 *   forge script script/DeployRWATokenFactoryMultiChain.s.sol --rpc-url $AVALANCHE_FUJI_RPC_URL --broadcast --verify
 *   forge script script/DeployRWATokenFactoryMultiChain.s.sol --rpc-url $ARBITRUM_SEPOLIA_RPC_URL --broadcast --verify
 */
contract DeployRWATokenFactoryMultiChain is Script {
    
    // Test token metadata
    RWAToken.AssetMetadata testMetadata = RWAToken.AssetMetadata({
        assetType: "real-estate",
        description: "Test Multi-chain RWA Token for Platform Testing",
        totalValue: 50_000_000 * 1e8, // $50M with 8 decimals
        url: "https://example.com/test-rwa-multichain",
        createdAt: 0 // Will be set by contract
    });
    
    function run() external {
       string memory privateKeyString = vm.envString("PRIVATE_KEY");
        uint256 deployerPrivateKey;
        
        // Handle private key with or without 0x prefix
        if (bytes(privateKeyString)[0] == '0' && bytes(privateKeyString)[1] == 'x') {
            deployerPrivateKey = vm.parseUint(privateKeyString);
        } else {
            deployerPrivateKey = vm.parseUint(string(abi.encodePacked("0x", privateKeyString)));
        }
        
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("===========================================");
        console.log("Deploying RWATokenFactory to testnet");
        console.log("===========================================");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer address:", deployer);
        console.log("Block number:", block.number);
        
        // Check deployer balance
        uint256 balance = deployer.balance;
        console.log("Deployer balance:", balance / 1e18, "native tokens");
        require(balance > 0.01 ether, "Insufficient balance for deployment");
        
        // Start broadcasting transactions to the real testnet
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy RWATokenFactory
        RWATokenFactory factory = new RWATokenFactory();
        console.log("RWATokenFactory deployed at:", address(factory));
        
        // Create a test token to verify factory works
        string memory chainName = _getChainName(block.chainid);
        address testTokenAddress = factory.createToken(
            999, // Test project ID
            string.concat("Test RWA Token ", chainName),
            string.concat("TEST", vm.toString(block.chainid)),
            testMetadata
        );
        
        // Stop broadcasting
        vm.stopBroadcast();
        
        RWAToken testToken = RWAToken(testTokenAddress);
        
        console.log("Test RWA Token deployed at:", testTokenAddress);
        console.log("Test Token name:", testToken.name());
        console.log("Test Token symbol:", testToken.symbol());  
        
        // Print environment variables for this chain
        _printEnvironmentVariables(address(factory), testTokenAddress);
    }
    
    function _getChainName(uint256 chainId) internal pure returns (string memory) {
        if (chainId == 11155111) return "ETH Sepolia";
        if (chainId == 43113) return "AVAX Fuji";
        if (chainId == 421614) return "ARB Sepolia";
        return "Unknown";
    }
    
    function _printEnvironmentVariables(address factory, address testToken) internal view {
        console.log("\n===========================================");
        console.log("Environment Variables for .env file:");
        console.log("===========================================");
        
        string memory factoryVar;
        string memory testTokenVar;
        
        if (block.chainid == 11155111) {
            factoryVar = "ETH_SEPOLIA_FACTORY_ADDRESS";
            testTokenVar = "ETH_SEPOLIA_TEST_TOKEN_ADDRESS";
        } else if (block.chainid == 43113) {
            factoryVar = "AVALANCHE_FUJI_FACTORY_ADDRESS";
            testTokenVar = "AVALANCHE_FUJI_TEST_TOKEN_ADDRESS";
        } else if (block.chainid == 421614) {
            factoryVar = "ARBITRUM_SEPOLIA_FACTORY_ADDRESS";
            testTokenVar = "ARBITRUM_SEPOLIA_TEST_TOKEN_ADDRESS";
        } else {
            factoryVar = "UNKNOWN_CHAIN_FACTORY_ADDRESS";
            testTokenVar = "UNKNOWN_CHAIN_TEST_TOKEN_ADDRESS";
        }
        
        console.log(string.concat("export ", factoryVar, "=", vm.toString(factory)));
        console.log(string.concat("export ", testTokenVar, "=", vm.toString(testToken)));
        
        console.log("\n# Add these to your .env file");
        console.log("# Then run the same command on other chains");
    }
}