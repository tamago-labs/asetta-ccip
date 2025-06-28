// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import "../src/RWAManager.sol";
import "../src/RWATokenFactory.sol";
import "../src/PrimaryDistribution.sol";
import "../src/RWAToken.sol";

/**
 * @title DeployRWAManagerMultiChain
 * @notice Deploy RWAManager to testnets and create test projects
 * @dev Requires RWATokenFactory and PrimaryDistribution to be deployed first
 *      Usage (run on each chain):
 *   forge script script/DeployRWAManagerMultiChain.s.sol --rpc-url $ETHEREUM_SEPOLIA_RPC_URL --broadcast --verify
 *   forge script script/DeployRWAManagerMultiChain.s.sol --rpc-url $AVALANCHE_FUJI_RPC_URL --broadcast --verify
 *   forge script script/DeployRWAManagerMultiChain.s.sol --rpc-url $ARBITRUM_SEPOLIA_RPC_URL --broadcast --verify
 */
contract DeployRWAManagerMultiChain is Script {
    
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
        console.log("Deploying RWAManager to testnet");
        console.log("===========================================");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer address:", deployer);
        console.log("Block number:", block.number);
        
        // Get dependency addresses
        address factoryAddress = _getFactoryAddress();
        address primaryDistributionAddress = _getPrimaryDistributionAddress();
        
        console.log("Using RWATokenFactory at:", factoryAddress);
        console.log("Using PrimaryDistribution at:", primaryDistributionAddress);
        
        // Verify the contracts exist
        _verifyDependencies(factoryAddress, primaryDistributionAddress);
        
        address feeRecipient = deployer; // Use deployer as fee recipient
        address treasury = deployer; // Use deployer as treasury
        
        // Check deployer balance
        uint256 balance = deployer.balance;
        console.log("Deployer balance:", balance / 1e18, "native tokens");
        require(balance > 0.01 ether, "Insufficient balance for deployment");
        
        // Start broadcasting transactions to the real testnet
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy RWAManager
        RWAManager rwaManager = new RWAManager(
            factoryAddress,
            primaryDistributionAddress,
            feeRecipient,
            treasury
        );
        
        console.log("RWAManager deployed at:", address(rwaManager));
        console.log("Fee recipient:", feeRecipient);
        console.log("Treasury:", treasury);
        
        // Create a test project to verify everything works
        // string memory chainName = _getChainName(block.chainid);
        // RWAToken.AssetMetadata memory testMetadata = RWAToken.AssetMetadata({
        //     assetType: "real-estate",
        //     description: string.concat("Premium Office Complex - ", chainName, " Testnet"),
        //     totalValue: 50_000_000 * 1e8, // $50M with 8 decimals
        //     url: string.concat("https://example.com/office-", vm.toString(block.chainid)),
        //     createdAt: 0 // Will be set by contract
        // });
        
        // uint256 testProjectId = rwaManager.createRWAToken(
        //     string.concat("Office Token ", chainName),
        //     string.concat("OFFICE", vm.toString(block.chainid)),
        //     testMetadata
        // );
        
        // // Get the created token address
        // RWAManager.RWAProject memory project = rwaManager.getProject(testProjectId);
        // address testTokenAddress = project.rwaToken;
        
        // console.log("Test project created with ID:", testProjectId);
        // console.log("Test token deployed at:", testTokenAddress);
        
        // // Configure CCIP for the test project (marking it as ready)
        // rwaManager.markCCIPConfigured(testProjectId, 1000000 * 1e18); // 1M tokens total supply
        // console.log("Test project marked as CCIP configured");
        
        // // Mint some tokens to the deployer for testing
        // RWAToken testToken = RWAToken(testTokenAddress);
        // testToken.mint(deployer, 100000 * 1e18); // 100k tokens
        // console.log("Minted 100,000 test tokens to deployer");
        
        vm.stopBroadcast();
        
        // Test the deployment
        // _testDeployment(rwaManager);
        
        // Print environment variables for this chain
        _printEnvironmentVariables(address(rwaManager));
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
    
    function _getPrimaryDistributionAddress() internal view returns (address) {
        string memory envVar;
        if (block.chainid == 11155111) {
            envVar = "ETH_SEPOLIA_PRIMARY_DISTRIBUTION_ADDRESS";
        } else if (block.chainid == 43113) {
            envVar = "AVALANCHE_FUJI_PRIMARY_DISTRIBUTION_ADDRESS";
        } else if (block.chainid == 421614) {
            envVar = "ARBITRUM_SEPOLIA_PRIMARY_DISTRIBUTION_ADDRESS";
        } else {
            revert("Unsupported chain");
        }
        
        try vm.envAddress(envVar) returns (address addr) {
            return addr;
        } catch {
            revert(string.concat("PrimaryDistribution address not found. Please set ", envVar, " in .env file"));
        }
    }
    
    function _verifyDependencies(address factory, address primaryDistribution) internal view {
        // Verify RWATokenFactory
        uint256 factoryCodeSize;
        assembly {
            factoryCodeSize := extcodesize(factory)
        }
        require(factoryCodeSize > 0, "RWATokenFactory contract not found");
        
        // Verify PrimaryDistribution
        PrimaryDistribution primaryDist = PrimaryDistribution(primaryDistribution);
        require(primaryDist.platformFeePercent() >= 0, "PrimaryDistribution not accessible");
        
        console.log(" Dependencies verified");
    }
    
    // function _testDeployment(RWAManager rwaManager) internal view {
    //     // Test basic functionality
    //     RWAManager.RWAProject memory project = rwaManager.getProject(projectId);
    //     require(project.rwaToken == tokenAddress, "Token address mismatch");
    //     require(project.isActive == false, "Project should not be active initially");
    //     require(project.ccipConfigured == true, "CCIP should be configured");
    //     require(uint256(project.status) == uint256(RWAManager.ProjectStatus.CCIP_READY), "Wrong project status");
        
    //     // Test token functionality
    //     RWAToken token = RWAToken(tokenAddress);
    //     require(bytes(token.name()).length > 0, "Token name not set");
    //     require(bytes(token.symbol()).length > 0, "Token symbol not set");
        
    //     console.log(" Deployment test passed");
    //     console.log("  Project status: CCIP_READY");
    //     console.log("  Token name:", token.name());
    //     console.log("  Token symbol:", token.symbol());
    // }
    
    function _getChainName(uint256 chainId) internal pure returns (string memory) {
        if (chainId == 11155111) return "ETH Sepolia";
        if (chainId == 43113) return "AVAX Fuji";
        if (chainId == 421614) return "ARB Sepolia";
        return "Unknown";
    }
    
    function _printEnvironmentVariables(address rwaManager) internal view {
        console.log("\n===========================================");
        console.log("Environment Variables for .env file:");
        console.log("===========================================");
        
        string memory managerVar;
        
        if (block.chainid == 11155111) {
            managerVar = "ETH_SEPOLIA_RWA_MANAGER_ADDRESS"; 
        } else if (block.chainid == 43113) {
            managerVar = "AVALANCHE_FUJI_RWA_MANAGER_ADDRESS"; 
        } else if (block.chainid == 421614) {
            managerVar = "ARBITRUM_SEPOLIA_RWA_MANAGER_ADDRESS"; 
        } else {
            managerVar = "UNKNOWN_CHAIN_RWA_MANAGER_ADDRESS"; 
        }
        
        console.log(string.concat("export ", managerVar, "=", vm.toString(rwaManager))); 
        
        // console.log("\n# Add these to your .env file before deploying RWARFQ");
        // console.log("# Test Project Information:");
        // console.log("#   Project ID:", vm.toString(testProjectId));
        // console.log("#   Status: CCIP_READY (ready for primary sales registration)");
        // console.log("#   Total Supply: 1,000,000 tokens");
        // console.log("#   Deployer Balance: 100,000 tokens");
    }
}