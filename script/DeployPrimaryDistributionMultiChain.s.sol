// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import "../src/PrimaryDistribution.sol"; 
import "../src/RWATokenFactory.sol";

import {MockUSDC } from  "../src/MockUSDC.sol";

/**
 * @title DeployPrimaryDistributionMultiChain
 * @notice Deploy PrimaryDistribution to testnets
 * @dev Requires MockUSDC and RWATokenFactory to be deployed first
 *      Usage (run on each chain): 
 *   forge script script/DeployPrimaryDistributionMultiChain.s.sol --rpc-url $ETHEREUM_SEPOLIA_RPC_URL --broadcast --verify
 *   forge script script/DeployPrimaryDistributionMultiChain.s.sol --rpc-url $AVALANCHE_FUJI_RPC_URL --broadcast --verify
 *   forge script script/DeployPrimaryDistributionMultiChain.s.sol --rpc-url $ARBITRUM_SEPOLIA_RPC_URL --broadcast --verify
 */
contract DeployPrimaryDistributionMultiChain is Script {
    
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
        
        console.log("===============================================");
        console.log("Deploying PrimaryDistribution to testnet");
        console.log("===============================================");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer address:", deployer);
        console.log("Block number:", block.number);
        
        // Get dependency addresses
        address factoryAddress = _getFactoryAddress();
        address usdcAddress = _getUSDCAddress();
        
        console.log("Using RWATokenFactory at:", factoryAddress);
        console.log("Using MockUSDC at:", usdcAddress);
        
        // Verify the contracts exist and are correct
        _verifyDependencies(factoryAddress, usdcAddress);
        
        address platformTreasury = deployer; // Use deployer as platform treasury for now
        
        // Check deployer balance
        uint256 balance = deployer.balance;
        console.log("Deployer balance:", balance / 1e18, "native tokens");
        require(balance > 0.01 ether, "Insufficient balance for deployment");
        
        // Start broadcasting transactions to the real testnet
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy PrimaryDistribution
        PrimaryDistribution primaryDistribution = new PrimaryDistribution(
            usdcAddress,
            factoryAddress,
            platformTreasury
        );
        
        vm.stopBroadcast();
        
        console.log("PrimaryDistribution deployed at:", address(primaryDistribution));
        console.log("Platform treasury:", platformTreasury);
        console.log("Platform fee:", primaryDistribution.platformFeePercent(), "basis points (0.5%)");
        
        // Test the deployment with a simple view call
        _testDeployment(primaryDistribution, factoryAddress, usdcAddress);
        
        // Print environment variable for this chain
        _printEnvironmentVariable(address(primaryDistribution));
    }
    
    function _getFactoryAddress() internal view returns (address) {
        string memory envVar;
        if (block.chainid == 11155111) {
            envVar = "ETH_SEPOLIA_FACTORY_ADDRESS";
        } else if (block.chainid == 43113) {
            envVar = "AVALANCHE_FUJI_FACTORY_ADDRESS";
        } else if (block.chainid == 421614) {
            envVar = "ARBITRUM_SEPOLIA_FACTORY_ADDRESS";
        } else {
            revert("Unsupported chain");
        }
        
        try vm.envAddress(envVar) returns (address addr) {
            return addr;
        } catch {
            revert(string.concat("Factory address not found. Please set ", envVar, " in .env file"));
        }
    }
    
    function _getUSDCAddress() internal view returns (address) {
        string memory envVar;
        if (block.chainid == 11155111) {
            envVar = "ETH_SEPOLIA_USDC_ADDRESS";
        } else if (block.chainid == 43113) {
            envVar = "AVALANCHE_FUJI_USDC_ADDRESS";
        } else if (block.chainid == 421614) {
            envVar = "ARBITRUM_SEPOLIA_USDC_ADDRESS";
        } else {
            revert("Unsupported chain");
        }
        
        try vm.envAddress(envVar) returns (address addr) {
            return addr;
        } catch {
            revert(string.concat("USDC address not found. Please set ", envVar, " in .env file"));
        }
    }
    
    function _verifyDependencies(address factory, address usdc) internal view {
        // Verify RWATokenFactory exists
        uint256 factoryCodeSize;
        assembly {
            factoryCodeSize := extcodesize(factory)
        }
        require(factoryCodeSize > 0, "RWATokenFactory contract not found");
        
        // Verify MockUSDC
        MockUSDC usdcContract = MockUSDC(usdc);
        require(usdcContract.decimals() == 6, "USDC contract has wrong decimals");
        require(keccak256(bytes(usdcContract.symbol())) == keccak256(bytes("USDC")), "Wrong USDC symbol");
        
        console.log("Dependencies verified");
    }
    
    function _testDeployment(PrimaryDistribution primaryDist, address factory, address usdc) internal view {
        // Test basic functionality
        require(address(primaryDist.usdc()) == usdc, "Wrong USDC address in contract");
        require(address(primaryDist.tokenFactory()) == factory, "Wrong factory address in contract");
        require(primaryDist.platformFeePercent() == 50, "Wrong initial platform fee"); // 0.5%
        
        console.log("Deployment test passed");
    }
    
    function _printEnvironmentVariable(address primaryDistribution) internal view {
        console.log("\n===============================================");
        console.log("Environment Variable for .env file:");
        console.log("===============================================");
        
        string memory envVar;
        if (block.chainid == 11155111) {
            envVar = "ETH_SEPOLIA_PRIMARY_DISTRIBUTION_ADDRESS";
        } else if (block.chainid == 43113) {
            envVar = "AVALANCHE_FUJI_PRIMARY_DISTRIBUTION_ADDRESS";
        } else if (block.chainid == 421614) {
            envVar = "ARBITRUM_SEPOLIA_PRIMARY_DISTRIBUTION_ADDRESS";
        } else {
            envVar = "UNKNOWN_CHAIN_PRIMARY_DISTRIBUTION_ADDRESS";
        }
        
        console.log(string.concat("export ", envVar, "=", vm.toString(primaryDistribution)));
        console.log("\n# Add this to your .env file before deploying RWAManager");
    }
}