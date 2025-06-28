// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import "../src/PrimaryDistribution.sol";
import "../src/RWAToken.sol";
import "../src/RWATokenFactory.sol";
import { MockUSDC } from "../src/MockUSDC.sol";

contract PrimaryDistributionTest is Test {
    PrimaryDistribution public primaryDistribution;
    RWATokenFactory public tokenFactory;
    RWAToken public rwaToken;
    MockUSDC public usdc;
    
    address public admin = makeAddr("admin");
    address public projectOwner = makeAddr("projectOwner");
    address public projectTreasury = makeAddr("projectTreasury");
    address public platformTreasury = makeAddr("platformTreasury");
    address public buyer1 = makeAddr("buyer1");
    address public buyer2 = makeAddr("buyer2");
    
    uint256 public constant PROJECT_ID = 1;
    uint256 public constant TOTAL_ALLOCATION = 1000 * 1e18; // 1000 tokens
    uint256 public constant PRICE_PER_TOKEN = 5 * 1e6; // $5 USDC per token
    uint256 public constant MIN_PURCHASE = 100 * 1e6; // $100 USDC minimum
    uint256 public constant MAX_PURCHASE = 10000 * 1e6; // $10,000 USDC maximum
    
    event ProjectSaleRegistered(
        uint256 indexed projectId,
        address indexed projectOwner,
        address indexed rwaToken,
        uint256 totalAllocation,
        uint256 pricePerTokenUSDC
    );
    
    event TokensPurchased(
        uint256 indexed projectId,
        address indexed buyer,
        uint256 usdcAmount,
        uint256 tokenAmount
    );
    
    function setUp() public {
        // Deploy MockUSDC
        usdc = new MockUSDC();
        
        // Deploy RWATokenFactory
        tokenFactory = new RWATokenFactory();
        
        // Deploy PrimaryDistribution
        vm.prank(admin);
        primaryDistribution = new PrimaryDistribution(
            address(usdc),
            address(tokenFactory),
            platformTreasury
        );
        
        // Create RWA Token
        RWAToken.AssetMetadata memory metadata = RWAToken.AssetMetadata({
            assetType: "real-estate",
            description: "Luxury apartment building in Tokyo",
            totalValue: 50_000_000 * 1e8, // $50M
            url: "https://example.com/tokyo-property",
            createdAt: 0 // Will be set by contract
        });
        
        vm.prank(projectOwner);
        rwaToken = new RWAToken(
            "Tokyo Real Estate Token",
            "TRET",
            metadata
        );
        
        // Mint tokens to project owner for distribution
        vm.prank(projectOwner);
        rwaToken.mint(address(primaryDistribution), TOTAL_ALLOCATION);
        
        // Mint USDC to buyers
        usdc.mint(buyer1, 20000 * 1e6); // $20,000
        usdc.mint(buyer2, 15000 * 1e6); // $15,000
        
        // Approve USDC spending
        vm.prank(buyer1);
        usdc.approve(address(primaryDistribution), type(uint256).max);
        
        vm.prank(buyer2);
        usdc.approve(address(primaryDistribution), type(uint256).max);
    }
    
    function test_RegisterTokenSale() public {
        vm.expectEmit(true, true, true, true);
        emit ProjectSaleRegistered(
            PROJECT_ID,
            projectOwner,
            address(rwaToken),
            TOTAL_ALLOCATION,
            PRICE_PER_TOKEN
        );
        
        vm.prank(projectOwner);
        primaryDistribution.registerTokenSale(
            PROJECT_ID,
            address(rwaToken),
            projectTreasury,
            TOTAL_ALLOCATION,
            PRICE_PER_TOKEN,
            MIN_PURCHASE,
            MAX_PURCHASE
        );
        
        // Verify project sale details
        PrimaryDistribution.ProjectSale memory sale = primaryDistribution.getProjectSale(PROJECT_ID);
        assertEq(address(sale.rwaToken), address(rwaToken));
        assertEq(sale.treasury, projectTreasury);
        assertEq(sale.totalAllocation, TOTAL_ALLOCATION);
        assertEq(sale.pricePerTokenUSDC, PRICE_PER_TOKEN);
        assertEq(sale.minPurchase, MIN_PURCHASE);
        assertEq(sale.maxPurchase, MAX_PURCHASE);
        assertTrue(sale.isActive);
        assertEq(sale.projectOwner, projectOwner);
        assertTrue(sale.isRegistered);
    }
    
    function test_RegisterTokenSale_RevertIfAlreadyRegistered() public {
        // Register first time
        vm.prank(projectOwner);
        primaryDistribution.registerTokenSale(
            PROJECT_ID,
            address(rwaToken),
            projectTreasury,
            TOTAL_ALLOCATION,
            PRICE_PER_TOKEN,
            MIN_PURCHASE,
            MAX_PURCHASE
        );
        
        // Try to register again
        vm.expectRevert(PrimaryDistribution.ProjectAlreadyRegistered.selector);
        vm.prank(projectOwner);
        primaryDistribution.registerTokenSale(
            PROJECT_ID,
            address(rwaToken),
            projectTreasury,
            TOTAL_ALLOCATION,
            PRICE_PER_TOKEN,
            MIN_PURCHASE,
            MAX_PURCHASE
        );
    }
    
    function test_RegisterTokenSale_RevertInvalidInputs() public {
        // Invalid token address
        vm.expectRevert(PrimaryDistribution.InvalidAddress.selector);
        vm.prank(projectOwner);
        primaryDistribution.registerTokenSale(
            PROJECT_ID,
            address(0),
            projectTreasury,
            TOTAL_ALLOCATION,
            PRICE_PER_TOKEN,
            MIN_PURCHASE,
            MAX_PURCHASE
        );
        
        // Invalid treasury
        vm.expectRevert(PrimaryDistribution.InvalidAddress.selector);
        vm.prank(projectOwner);
        primaryDistribution.registerTokenSale(
            PROJECT_ID,
            address(rwaToken),
            address(0),
            TOTAL_ALLOCATION,
            PRICE_PER_TOKEN,
            MIN_PURCHASE,
            MAX_PURCHASE
        );
        
        // Invalid price
        vm.expectRevert(PrimaryDistribution.InvalidPrice.selector);
        vm.prank(projectOwner);
        primaryDistribution.registerTokenSale(
            PROJECT_ID,
            address(rwaToken),
            projectTreasury,
            TOTAL_ALLOCATION,
            0,
            MIN_PURCHASE,
            MAX_PURCHASE
        );
        
        // Invalid allocation
        vm.expectRevert(PrimaryDistribution.InvalidAllocation.selector);
        vm.prank(projectOwner);
        primaryDistribution.registerTokenSale(
            PROJECT_ID,
            address(rwaToken),
            projectTreasury,
            0,
            PRICE_PER_TOKEN,
            MIN_PURCHASE,
            MAX_PURCHASE
        );
        
        // Min > Max purchase
        vm.expectRevert(PrimaryDistribution.InvalidAllocation.selector);
        vm.prank(projectOwner);
        primaryDistribution.registerTokenSale(
            PROJECT_ID,
            address(rwaToken),
            projectTreasury,
            TOTAL_ALLOCATION,
            PRICE_PER_TOKEN,
            MAX_PURCHASE,
            MIN_PURCHASE
        );
    }
    
    function test_WhitelistUsers() public {
        // Register project first
        vm.prank(projectOwner);
        primaryDistribution.registerTokenSale(
            PROJECT_ID,
            address(rwaToken),
            projectTreasury,
            TOTAL_ALLOCATION,
            PRICE_PER_TOKEN,
            MIN_PURCHASE,
            MAX_PURCHASE
        );
        
        address[] memory users = new address[](2);
        users[0] = buyer1;
        users[1] = buyer2;
        
        vm.prank(projectOwner);
        primaryDistribution.whitelistUsers(PROJECT_ID, users, true);
        
        assertTrue(primaryDistribution.whitelisted(PROJECT_ID, buyer1));
        assertTrue(primaryDistribution.whitelisted(PROJECT_ID, buyer2));
        
        // Remove from whitelist
        vm.prank(projectOwner);
        primaryDistribution.whitelistUsers(PROJECT_ID, users, false);
        
        assertFalse(primaryDistribution.whitelisted(PROJECT_ID, buyer1));
        assertFalse(primaryDistribution.whitelisted(PROJECT_ID, buyer2));
    }
    
    function test_WhitelistUsers_RevertNotProjectOwner() public {
        // Register project first
        vm.prank(projectOwner);
        primaryDistribution.registerTokenSale(
            PROJECT_ID,
            address(rwaToken),
            projectTreasury,
            TOTAL_ALLOCATION,
            PRICE_PER_TOKEN,
            MIN_PURCHASE,
            MAX_PURCHASE
        );
        
        address[] memory users = new address[](1);
        users[0] = buyer1;
        
        vm.expectRevert(PrimaryDistribution.NotProjectOwner.selector);
        vm.prank(buyer1);
        primaryDistribution.whitelistUsers(PROJECT_ID, users, true);
    }
    
    function test_PurchaseTokens() public {
        // Setup project
        vm.prank(projectOwner);
        primaryDistribution.registerTokenSale(
            PROJECT_ID,
            address(rwaToken),
            projectTreasury,
            TOTAL_ALLOCATION,
            PRICE_PER_TOKEN,
            MIN_PURCHASE,
            MAX_PURCHASE
        );
        
        // Whitelist buyer
        address[] memory users = new address[](1);
        users[0] = buyer1;
        vm.prank(projectOwner);
        primaryDistribution.whitelistUsers(PROJECT_ID, users, true);
        
        uint256 usdcAmount = 1000 * 1e6; // $1000
        uint256 expectedTokens = (usdcAmount * 1e18) / PRICE_PER_TOKEN; // 200 tokens
        uint256 platformFee = (usdcAmount * 50) / 10000; // 0.5% fee
        uint256 projectAmount = usdcAmount - platformFee;
        
        uint256 treasuryBalanceBefore = usdc.balanceOf(projectTreasury);
        uint256 platformBalanceBefore = usdc.balanceOf(platformTreasury);
        uint256 buyerTokensBefore = rwaToken.balanceOf(buyer1);
        
        vm.expectEmit(true, true, false, true);
        emit TokensPurchased(PROJECT_ID, buyer1, usdcAmount, expectedTokens);
        
        vm.prank(buyer1);
        primaryDistribution.purchaseTokens(PROJECT_ID, usdcAmount);
        
        // Check balances
        assertEq(usdc.balanceOf(projectTreasury), treasuryBalanceBefore + projectAmount);
        assertEq(usdc.balanceOf(platformTreasury), platformBalanceBefore + platformFee);
        assertEq(rwaToken.balanceOf(buyer1), buyerTokensBefore + expectedTokens);
        
        // Check purchase tracking
        assertEq(primaryDistribution.purchased(PROJECT_ID, buyer1), usdcAmount);
        
        // Check total sold
        PrimaryDistribution.ProjectSale memory sale = primaryDistribution.getProjectSale(PROJECT_ID);
        assertEq(sale.totalSold, expectedTokens);
    }
    
    function test_PurchaseTokens_RevertNotWhitelisted() public {
        // Setup project
        vm.prank(projectOwner);
        primaryDistribution.registerTokenSale(
            PROJECT_ID,
            address(rwaToken),
            projectTreasury,
            TOTAL_ALLOCATION,
            PRICE_PER_TOKEN,
            MIN_PURCHASE,
            MAX_PURCHASE
        );
        
        uint256 usdcAmount = 1000 * 1e6;
        
        vm.expectRevert(PrimaryDistribution.NotWhitelisted.selector);
        vm.prank(buyer1);
        primaryDistribution.purchaseTokens(PROJECT_ID, usdcAmount);
    }
    
    function test_PurchaseTokens_RevertProjectNotActive() public {
        // Setup project
        vm.prank(projectOwner);
        primaryDistribution.registerTokenSale(
            PROJECT_ID,
            address(rwaToken),
            projectTreasury,
            TOTAL_ALLOCATION,
            PRICE_PER_TOKEN,
            MIN_PURCHASE,
            MAX_PURCHASE
        );
        
        // Deactivate project
        vm.prank(projectOwner);
        primaryDistribution.toggleProjectStatus(PROJECT_ID);
        
        // Whitelist buyer
        address[] memory users = new address[](1);
        users[0] = buyer1;
        vm.prank(projectOwner);
        primaryDistribution.whitelistUsers(PROJECT_ID, users, true);
        
        uint256 usdcAmount = 1000 * 1e6;
        
        vm.expectRevert(PrimaryDistribution.ProjectNotActive.selector);
        vm.prank(buyer1);
        primaryDistribution.purchaseTokens(PROJECT_ID, usdcAmount);
    }
    
    function test_PurchaseTokens_RevertBelowMinimum() public {
        // Setup project
        vm.prank(projectOwner);
        primaryDistribution.registerTokenSale(
            PROJECT_ID,
            address(rwaToken),
            projectTreasury,
            TOTAL_ALLOCATION,
            PRICE_PER_TOKEN,
            MIN_PURCHASE,
            MAX_PURCHASE
        );
        
        // Whitelist buyer
        address[] memory users = new address[](1);
        users[0] = buyer1;
        vm.prank(projectOwner);
        primaryDistribution.whitelistUsers(PROJECT_ID, users, true);
        
        uint256 usdcAmount = 50 * 1e6; // Below minimum
        
        vm.expectRevert(PrimaryDistribution.BelowMinimumPurchase.selector);
        vm.prank(buyer1);
        primaryDistribution.purchaseTokens(PROJECT_ID, usdcAmount);
    }
    
    function test_PurchaseTokens_RevertExceedsMaximum() public {
        // Setup project
        vm.prank(projectOwner);
        primaryDistribution.registerTokenSale(
            PROJECT_ID,
            address(rwaToken),
            projectTreasury,
            TOTAL_ALLOCATION,
            PRICE_PER_TOKEN,
            MIN_PURCHASE,
            MAX_PURCHASE
        );
        
        // Whitelist buyer
        address[] memory users = new address[](1);
        users[0] = buyer1;
        vm.prank(projectOwner);
        primaryDistribution.whitelistUsers(PROJECT_ID, users, true);
        
        uint256 usdcAmount = 15000 * 1e6; // Above maximum
        
        vm.expectRevert(PrimaryDistribution.ExceedsMaximumPurchase.selector);
        vm.prank(buyer1);
        primaryDistribution.purchaseTokens(PROJECT_ID, usdcAmount);
    }
    
    function test_PurchaseTokens_RevertInsufficientAllocation() public {
        // Setup project
        vm.prank(projectOwner);
        primaryDistribution.registerTokenSale(
            PROJECT_ID,
            address(rwaToken),
            projectTreasury,
            TOTAL_ALLOCATION,
            PRICE_PER_TOKEN,
            MIN_PURCHASE,
            MAX_PURCHASE
        );
        
        // Whitelist buyer
        address[] memory users = new address[](1);
        users[0] = buyer1;
        vm.prank(projectOwner);
        primaryDistribution.whitelistUsers(PROJECT_ID, users, true);
        
        // Try to buy more tokens than allocated
        uint256 usdcAmount = 6000 * 1e6; // Would buy 1200 tokens, but only 1000 allocated
        
        vm.expectRevert(PrimaryDistribution.InsufficientAllocation.selector);
        vm.prank(buyer1);
        primaryDistribution.purchaseTokens(PROJECT_ID, usdcAmount);
    }
    
    function test_UpdateProjectPrice() public {
        // Setup project
        vm.prank(projectOwner);
        primaryDistribution.registerTokenSale(
            PROJECT_ID,
            address(rwaToken),
            projectTreasury,
            TOTAL_ALLOCATION,
            PRICE_PER_TOKEN,
            MIN_PURCHASE,
            MAX_PURCHASE
        );
        
        uint256 newPrice = 10 * 1e6; // $10 per token
        
        vm.prank(projectOwner);
        primaryDistribution.updateProjectPrice(PROJECT_ID, newPrice);
        
        PrimaryDistribution.ProjectSale memory sale = primaryDistribution.getProjectSale(PROJECT_ID);
        assertEq(sale.pricePerTokenUSDC, newPrice);
    }
    
    function test_UpdateProjectLimits() public {
        // Setup project
        vm.prank(projectOwner);
        primaryDistribution.registerTokenSale(
            PROJECT_ID,
            address(rwaToken),
            projectTreasury,
            TOTAL_ALLOCATION,
            PRICE_PER_TOKEN,
            MIN_PURCHASE,
            MAX_PURCHASE
        );
        
        uint256 newMin = 200 * 1e6; // $200
        uint256 newMax = 20000 * 1e6; // $20,000
        
        vm.prank(projectOwner);
        primaryDistribution.updateProjectLimits(PROJECT_ID, newMin, newMax);
        
        PrimaryDistribution.ProjectSale memory sale = primaryDistribution.getProjectSale(PROJECT_ID);
        assertEq(sale.minPurchase, newMin);
        assertEq(sale.maxPurchase, newMax);
    }
    
    function test_UpdateProjectTreasury() public {
        // Setup project
        vm.prank(projectOwner);
        primaryDistribution.registerTokenSale(
            PROJECT_ID,
            address(rwaToken),
            projectTreasury,
            TOTAL_ALLOCATION,
            PRICE_PER_TOKEN,
            MIN_PURCHASE,
            MAX_PURCHASE
        );
        
        address newTreasury = makeAddr("newTreasury");
        
        vm.prank(projectOwner);
        primaryDistribution.updateProjectTreasury(PROJECT_ID, newTreasury);
        
        PrimaryDistribution.ProjectSale memory sale = primaryDistribution.getProjectSale(PROJECT_ID);
        assertEq(sale.treasury, newTreasury);
    }
    
    function test_ToggleProjectStatus() public {
        // Setup project
        vm.prank(projectOwner);
        primaryDistribution.registerTokenSale(
            PROJECT_ID,
            address(rwaToken),
            projectTreasury,
            TOTAL_ALLOCATION,
            PRICE_PER_TOKEN,
            MIN_PURCHASE,
            MAX_PURCHASE
        );
        
        // Should be active initially
        assertTrue(primaryDistribution.getProjectSale(PROJECT_ID).isActive);
        
        // Toggle to inactive
        vm.prank(projectOwner);
        primaryDistribution.toggleProjectStatus(PROJECT_ID);
        
        assertFalse(primaryDistribution.getProjectSale(PROJECT_ID).isActive);
        
        // Toggle back to active
        vm.prank(projectOwner);
        primaryDistribution.toggleProjectStatus(PROJECT_ID);
        
        assertTrue(primaryDistribution.getProjectSale(PROJECT_ID).isActive);
    }
    
    function test_EmergencyWithdraw() public {
        // Setup project
        vm.prank(projectOwner);
        primaryDistribution.registerTokenSale(
            PROJECT_ID,
            address(rwaToken),
            projectTreasury,
            TOTAL_ALLOCATION,
            PRICE_PER_TOKEN,
            MIN_PURCHASE,
            MAX_PURCHASE
        );
        
        uint256 withdrawAmount = 100 * 1e18;
        uint256 contractBalanceBefore = rwaToken.balanceOf(address(primaryDistribution));
        uint256 ownerBalanceBefore = rwaToken.balanceOf(projectOwner);
        
        vm.prank(projectOwner);
        primaryDistribution.emergencyWithdraw(PROJECT_ID, withdrawAmount);
        
        assertEq(rwaToken.balanceOf(address(primaryDistribution)), contractBalanceBefore - withdrawAmount);
        assertEq(rwaToken.balanceOf(projectOwner), ownerBalanceBefore + withdrawAmount);
    }
    
    function test_GetTokensForUSDC() public {
        // Setup project
        vm.prank(projectOwner);
        primaryDistribution.registerTokenSale(
            PROJECT_ID,
            address(rwaToken),
            projectTreasury,
            TOTAL_ALLOCATION,
            PRICE_PER_TOKEN,
            MIN_PURCHASE,
            MAX_PURCHASE
        );
        
        uint256 usdcAmount = 1000 * 1e6; // $1000
        uint256 expectedTokens = (usdcAmount * 1e18) / PRICE_PER_TOKEN; // 200 tokens
        
        uint256 actualTokens = primaryDistribution.getTokensForUSDC(PROJECT_ID, usdcAmount);
        assertEq(actualTokens, expectedTokens);
    }
    
    function test_GetUSDCForTokens() public {
        // Setup project
        vm.prank(projectOwner);
        primaryDistribution.registerTokenSale(
            PROJECT_ID,
            address(rwaToken),
            projectTreasury,
            TOTAL_ALLOCATION,
            PRICE_PER_TOKEN,
            MIN_PURCHASE,
            MAX_PURCHASE
        );
        
        uint256 tokenAmount = 200 * 1e18; // 200 tokens
        uint256 expectedUSDC = (tokenAmount * PRICE_PER_TOKEN) / 1e18; // $1000
        
        uint256 actualUSDC = primaryDistribution.getUSDCForTokens(PROJECT_ID, tokenAmount);
        assertEq(actualUSDC, expectedUSDC);
    }
    
    function test_UpdatePlatformFee() public {
        uint256 newFee = 100; // 1%
        
        vm.prank(admin);
        primaryDistribution.updatePlatformFee(newFee);
        
        assertEq(primaryDistribution.platformFeePercent(), newFee);
    }
    
    function test_UpdatePlatformFee_RevertInvalidFee() public {
        uint256 invalidFee = 1500; // 15% - too high
        
        vm.expectRevert(PrimaryDistribution.InvalidFeePercent.selector);
        vm.prank(admin);
        primaryDistribution.updatePlatformFee(invalidFee);
    }
    
    function test_UpdatePlatformTreasury() public {
        address newTreasury = makeAddr("newPlatformTreasury");
        
        vm.prank(admin);
        primaryDistribution.updatePlatformTreasury(newTreasury);
        
        assertEq(primaryDistribution.platformTreasury(), newTreasury);
    } 
}