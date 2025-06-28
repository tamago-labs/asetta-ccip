// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import "../src/RWARFQ.sol";
import "../src/RWAToken.sol";
import { MockUSDC} from "../src/MockUSDC.sol";

/**
 * @title DeployRWARFQMultiChain
 * @notice Deploy RWARFQ to testnets for secondary market trading
 * @dev Requires RWAToken and MockUSDC to be deployed first
 *      Usage (run on each chain):
 *   forge script script/DeployRWARFQMultiChain.s.sol --rpc-url $ETHEREUM_SEPOLIA_RPC_URL --broadcast --verify
 *   forge script script/DeployRWARFQMultiChain.s.sol --rpc-url $AVALANCHE_FUJI_RPC_URL --broadcast --verify
 *   forge script script/DeployRWARFQMultiChain.s.sol --rpc-url $ARBITRUM_SEPOLIA_RPC_URL --broadcast --verify
 */
contract DeployRWARFQMultiChain is Script {
    
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
        
        console.log("=======================================");
        console.log("Deploying RWARFQ to testnet");
        console.log("=======================================");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer address:", deployer);
        console.log("Block number:", block.number);
        
        // Get dependency addresses
        address testTokenAddress = _getTestTokenAddress();
        address usdcAddress = _getUSDCAddress();
        
        console.log("Using test RWA token at:", testTokenAddress);
        console.log("Using MockUSDC at:", usdcAddress);
        
        // Verify the contracts exist
        // _verifyDependencies(testTokenAddress, usdcAddress);
        
        address feeRecipient = deployer; // Use deployer as fee recipient
        address admin = deployer; // Use deployer as admin
        
        // Check deployer balance
        uint256 balance = deployer.balance;
        console.log("Deployer balance:", balance / 1e18, "native tokens");
        require(balance > 0.01 ether, "Insufficient balance for deployment");
        
        // Start broadcasting transactions to the real testnet
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy RWARFQ
        RWARFQ rfq = new RWARFQ(
            testTokenAddress,
            usdcAddress,
            feeRecipient,
            admin
        );
        
        console.log("RWARFQ deployed at:", address(rfq));
        console.log("Fee recipient:", feeRecipient);
        console.log("Admin:", admin);
        console.log("Trading fee:", rfq.tradingFee(), "basis points (0.25%)");
        
        // Prepare test accounts with tokens for demonstration
        // _setupTestAccounts(testTokenAddress, usdcAddress, deployer);
        
        vm.stopBroadcast();
        
        // Test the deployment
        // _testDeployment(rfq, testTokenAddress, usdcAddress);
        
        // Print environment variable and trading instructions
        _printEnvironmentVariable(address(rfq));
        // _printTradingInstructions();
    }
    
    function _getTestTokenAddress() internal view returns (address) {
        string memory envVar;
        if (block.chainid == 11155111) {
            envVar = "ETH_SEPOLIA_TEST_TOKEN_ADDRESS";
        } else if (block.chainid == 43113) {
            envVar = "AVALANCHE_FUJI_TEST_TOKEN_ADDRESS";
        } else if (block.chainid == 421614) {
            envVar = "ARBITRUM_SEPOLIA_TEST_TOKEN_ADDRESS";
        } else {
            revert("Unsupported chain");
        }
        
        try vm.envAddress(envVar) returns (address addr) {
            return addr;
        } catch {
            revert(string.concat("Test token address not found. Please set ", envVar, " in .env file"));
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
    
    function _verifyDependencies(address rwaToken, address usdc) internal view {
        // Verify RWA Token
        RWAToken token = RWAToken(rwaToken);
        require(bytes(token.name()).length > 0, "RWA token name not set");
        require(bytes(token.symbol()).length > 0, "RWA token symbol not set");
        require(token.totalSupply() > 0, "RWA token has no supply");
        
        // Verify MockUSDC
        MockUSDC usdcContract = MockUSDC(usdc);
        require(usdcContract.decimals() == 6, "USDC contract has wrong decimals");
        require(keccak256(bytes(usdcContract.symbol())) == keccak256(bytes("USDC")), "Wrong USDC symbol");
        
        console.log(" Dependencies verified");
        // console.log("  RWA Token:", token.name(), "(", token.symbol(), ")");
        console.log("  Total Supply:", token.totalSupply() / 1e18, "tokens");
        console.log("  USDC decimals:", usdcContract.decimals());
    }
    
    function _setupTestAccounts(address rwaToken, address usdc, address deployer) internal {
        console.log("Setting up test accounts with tokens...");
        
        // Create some test accounts (these will be deterministic addresses)
        address testTrader1 = makeAddr("testTrader1");
        address testTrader2 = makeAddr("testTrader2");
        
        console.log("Test Trader 1:", testTrader1);
        console.log("Test Trader 2:", testTrader2);
        
        // Mint tokens to test accounts
        RWAToken(rwaToken).mint(testTrader1, 10000 * 1e18); // 10k tokens
        RWAToken(rwaToken).mint(testTrader2, 15000 * 1e18); // 15k tokens
        
        // Mint USDC to test accounts
        MockUSDC(usdc).mint(testTrader1, 100000 * 1e6); // $100k USDC
        MockUSDC(usdc).mint(testTrader2, 150000 * 1e6); // $150k USDC
        
        // Also give some extra USDC to deployer for testing
        MockUSDC(usdc).mint(deployer, 500000 * 1e6); // $500k USDC
        
        console.log(" Test accounts funded");
        console.log("  testTrader1: 10,000 RWA tokens + $100,000 USDC");
        console.log("  testTrader2: 15,000 RWA tokens + $150,000 USDC");
        console.log("  Deployer: Additional $500,000 USDC");
    }
    
    function _testDeployment(RWARFQ rfq, address rwaToken, address usdc) internal view {
        // Test basic functionality
        require(address(rfq.rwaToken()) == rwaToken, "Wrong RWA token address");
        require(address(rfq.usdc()) == usdc, "Wrong USDC address");
        require(rfq.tradingFee() == 25, "Wrong initial trading fee"); // 0.25%
        
        // Test stats
        (uint256 totalVolume, uint256 totalTrades) = rfq.getTradingStats();
        require(totalVolume == 0, "Initial volume should be zero");
        require(totalTrades == 0, "Initial trades should be zero");
        
        // Test best prices (should be initial values)
        (uint256 bestBuyPrice, uint256 bestSellPrice) = rfq.getBestPrices();
        require(bestBuyPrice == 0, "Initial best buy price should be zero");
        require(bestSellPrice == type(uint256).max, "Initial best sell price should be max");
        
        console.log("  Deployment test passed");
        console.log("  Trading fee: 0.25%");
        console.log("  Initial trading stats: 0 volume, 0 trades");
    }
    
    function _printEnvironmentVariable(address rfq) internal view {
        console.log("\n=======================================");
        console.log("Environment Variable for .env file:");
        console.log("=======================================");
        
        string memory envVar;
        if (block.chainid == 11155111) {
            envVar = "ETH_SEPOLIA_RFQ_ADDRESS";
        } else if (block.chainid == 43113) {
            envVar = "AVALANCHE_FUJI_RFQ_ADDRESS";
        } else if (block.chainid == 421614) {
            envVar = "ARBITRUM_SEPOLIA_RFQ_ADDRESS";
        } else {
            envVar = "UNKNOWN_CHAIN_RFQ_ADDRESS";
        }
        
        console.log(string.concat("export ", envVar, "=", vm.toString(rfq)));
        console.log("\n# Add this to your .env file for testing scripts");
    }
    
    function _printTradingInstructions() internal view {
        console.log("\n=======================================");
        console.log(" RFQ Trading System Ready!");
        console.log("=======================================");
        
        console.log("\n  How to test:");
        console.log("1. Users can submit buy quotes (deposit USDC, want RWA tokens)");
        console.log("2. Users can submit sell quotes (deposit RWA tokens, want USDC)");
        console.log("3. Other users can fill these quotes");
        console.log("4. A 0.25% trading fee is charged on each trade");
        
        console.log("\n  Example trading flow:");
        console.log("1. Trader A submits buy quote: 1000 RWA tokens at $10 per token");
        console.log("   - Trader A deposits $10,000 USDC into RFQ contract");
        console.log("2. Trader B fills the quote by selling 1000 RWA tokens");
        console.log("   - Trader B gets $9,975 USDC (minus 0.25% fee)");
        console.log("   - Trader A gets 1000 RWA tokens");
        console.log("   - Fee recipient gets $25 USDC");
        
        console.log("\n  Test accounts funded:");
        console.log("- testTrader1 & testTrader2 have RWA tokens and USDC");
        console.log("- Use these accounts to test quote submission and filling");
        console.log("- Addresses are deterministic (same across all deployments)");
        
        console.log("\n  Next steps:");
        console.log("1. Create test trading scenarios");
        console.log("2. Test quote submission, cancellation, and filling");
        console.log("3. Monitor trading fees and volume statistics");
        console.log("4. Optionally deploy RWAVault contracts for staking");
        
        console.log("\n  Chain deployed:", _getChainName(block.chainid));
        console.log("Deploy on other chains using the same command with different RPC URLs");
    }
    
    function _getChainName(uint256 chainId) internal pure returns (string memory) {
        if (chainId == 11155111) return "Ethereum Sepolia";
        if (chainId == 43113) return "Avalanche Fuji";
        if (chainId == 421614) return "Arbitrum Sepolia";
        return "Unknown Chain";
    }
}