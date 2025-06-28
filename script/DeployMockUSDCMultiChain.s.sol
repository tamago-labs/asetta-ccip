// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import "../src/MockUSDC.sol";

/**
 * @title DeployMockUSDCMultiChain
 * @notice Deploy MockUSDC to multiple testnets (Ethereum Sepolia, Avalanche Fuji, Arbitrum Sepolia)
 * @dev Usage: 
 *   forge script script/DeployMockUSDCMultiChain.s.sol --rpc-url $ETHEREUM_SEPOLIA_RPC_URL --broadcast --verify
 *   forge script script/DeployMockUSDCMultiChain.s.sol --rpc-url $AVALANCHE_FUJI_RPC_URL --broadcast --verify
 *   forge script script/DeployMockUSDCMultiChain.s.sol --rpc-url $ARBITRUM_SEPOLIA_RPC_URL --broadcast --verify
 */
contract DeployMockUSDCMultiChain is Script {
    
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
        console.log("Deploying MockUSDC to testnet");
        console.log("===========================================");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer address:", deployer);
        console.log("Block number:", block.number); 
        
        // Check deployer balance
        uint256 balance = deployer.balance;
        console.log("Deployer balance:", balance / 1e18, "ETH");
        require(balance > 0.01 ether, "Insufficient balance for deployment");
        
        // Start broadcasting transactions to the real testnet
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy MockUSDC
        MockUSDC mockUSDC = new MockUSDC();
        
        // Stop broadcasting
        vm.stopBroadcast();
        
        console.log("MockUSDC deployed successfully!");
        console.log("Contract address:", address(mockUSDC));
        console.log("Name:", mockUSDC.name());
        console.log("Symbol:", mockUSDC.symbol());
        console.log("Decimals:", mockUSDC.decimals());
        
        // Mint some test tokens to deployer for testing
        vm.startBroadcast(deployerPrivateKey);
        mockUSDC.mint(deployer, 1000000 * 1e6); // 1M USDC
        vm.stopBroadcast();
        
        console.log("Minted 1,000,000 USDC to deployer");
        console.log("Deployer USDC balance:", mockUSDC.balanceOf(deployer) / 1e6);
        
        // Print environment variable for this chain
        _printEnvironmentVariable(address(mockUSDC));
    }
    
    function _printEnvironmentVariable(address mockUSDC) internal view {
        console.log("\n===========================================");
        console.log("Environment Variable for .env file:");
        console.log("===========================================");
        
        string memory envVar;
        if (block.chainid == 11155111) {
            envVar = "ETH_SEPOLIA_USDC_ADDRESS";
        } else if (block.chainid == 43113) {
            envVar = "AVALANCHE_FUJI_USDC_ADDRESS";
        } else if (block.chainid == 421614) {
            envVar = "ARBITRUM_SEPOLIA_USDC_ADDRESS";
        } else {
            envVar = "UNKNOWN_CHAIN_USDC_ADDRESS";
        }
        
        console.log(string.concat("export ", envVar, "=", vm.toString(mockUSDC)));
        console.log("\n# Add this to your .env file");
        console.log("# Then run the same command on other chains:");
        console.log("# forge script script/DeployMockUSDCMultiChain.s.sol --rpc-url $AVALANCHE_FUJI_RPC_URL --broadcast --verify");
        console.log("# forge script script/DeployMockUSDCMultiChain.s.sol --rpc-url $ARBITRUM_SEPOLIA_RPC_URL --broadcast --verify");
    }
}