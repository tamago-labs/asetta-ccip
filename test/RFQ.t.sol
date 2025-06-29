// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import "../src/RWARFQ.sol";
import "../src/RWAToken.sol";
import { MockUSDC } from "../src/MockUSDC.sol";

contract RWARFQTest is Test {
    RWARFQ public rfq;
    RWAToken public rwaToken;
    MockUSDC public usdc;
    
    address public admin = makeAddr("admin");
    address public minter = makeAddr("minter");
    address public feeRecipient = makeAddr("feeRecipient");
    address public maker1 = makeAddr("maker1");
    address public maker2 = makeAddr("maker2");
    address public taker1 = makeAddr("taker1");
    address public taker2 = makeAddr("taker2");
    
    uint256 public constant INITIAL_RWA_SUPPLY = 10000 * 1e18;
    uint256 public constant INITIAL_USDC_SUPPLY = 100000 * 1e6; // $100,000
    
    event QuoteSubmitted(
        uint256 indexed quoteId,
        address indexed maker,
        bool isBuyQuote,
        uint256 rwaAmount,
        uint256 pricePerToken
    );
    
    event QuoteFilled(
        uint256 indexed quoteId,
        address indexed taker,
        uint256 rwaAmount,
        uint256 usdcAmount
    );
    
    event QuoteCancelled(uint256 indexed quoteId);
    
    function setUp() public {

        // Deploy USDC
        usdc = new MockUSDC();
        
        // Deploy RWA Token
        RWAToken.AssetMetadata memory metadata = RWAToken.AssetMetadata({
            assetType: "real-estate",
            description: "Commercial office building in Singapore",
            totalValue: 25_000_000 * 1e8, // $25M
            url: "https://example.com/singapore-office",
            createdAt: 0
        });
        
        vm.prank(admin);
 
        rwaToken = new RWAToken(
            "Singapore Office Token",
            "SOT",
            metadata,
            admin
        );

        // sanity‑check
        assertTrue(rwaToken.hasRole(rwaToken.DEFAULT_ADMIN_ROLE(), admin));

        // Deploy RFQ
        rfq = new RWARFQ(
            address(rwaToken),
            address(usdc),
            feeRecipient,
            admin
        );
         
        // grant MINTER_ROLE 
        vm.stopPrank();      
        vm.startPrank(admin);
        rwaToken.grantRole(rwaToken.MINTER_ROLE(), minter);
        vm.stopPrank();

        vm.startPrank(minter);
        
        // Mint tokens to users
        rwaToken.mint(maker1, INITIAL_RWA_SUPPLY);
        rwaToken.mint(maker2, INITIAL_RWA_SUPPLY);
        rwaToken.mint(taker1, INITIAL_RWA_SUPPLY);
        rwaToken.mint(taker2, INITIAL_RWA_SUPPLY);

        vm.stopPrank();
        
        usdc.mint(maker1, INITIAL_USDC_SUPPLY);
        usdc.mint(maker2, INITIAL_USDC_SUPPLY);
        usdc.mint(taker1, INITIAL_USDC_SUPPLY);
        usdc.mint(taker2, INITIAL_USDC_SUPPLY);
        
        // Approve RFQ contract to spend tokens
        vm.prank(maker1);
        rwaToken.approve(address(rfq), type(uint256).max);
        vm.prank(maker1);
        usdc.approve(address(rfq), type(uint256).max);
        
        vm.prank(maker2);
        rwaToken.approve(address(rfq), type(uint256).max);
        vm.prank(maker2);
        usdc.approve(address(rfq), type(uint256).max);
        
        vm.prank(taker1);
        rwaToken.approve(address(rfq), type(uint256).max);
        vm.prank(taker1);
        usdc.approve(address(rfq), type(uint256).max);
        
        vm.prank(taker2);
        rwaToken.approve(address(rfq), type(uint256).max);
        vm.prank(taker2);
        usdc.approve(address(rfq), type(uint256).max);
    }
    
    function test_SubmitBuyQuote() public {
        uint256 rwaAmount = 100 * 1e18; // 100 RWA tokens
        uint256 pricePerToken = 10 * 1e6; // $10 per token
        uint256 duration = 1 hours;
         
        uint256 usdcRequired = (rwaAmount * pricePerToken) / 1e18; // $1000
        
        uint256 usdcBalanceBefore = usdc.balanceOf(maker1);
        uint256 contractUsdcBefore = usdc.balanceOf(address(rfq));
        
        vm.expectEmit(true, true, false, true);
        emit QuoteSubmitted(0, maker1, true, rwaAmount, pricePerToken);
        
        vm.prank(maker1);
        rfq.submitQuote(true, rwaAmount, pricePerToken, duration);
        
        // Check USDC was deposited
        assertEq(usdc.balanceOf(maker1), usdcBalanceBefore - usdcRequired);
        assertEq(usdc.balanceOf(address(rfq)), contractUsdcBefore + usdcRequired);
        
        // Check quote details
        (
            address quoteMaker,
            bool isBuyQuote,
            uint256 quoteRwaAmount,
            uint256 quotePricePerToken,
            uint256 expiry,
            bool isActive
        ) = rfq.quotes(0);
        
        assertEq(quoteMaker, maker1);
        assertTrue(isBuyQuote);
        assertEq(quoteRwaAmount, rwaAmount);
        assertEq(quotePricePerToken, pricePerToken);
        assertEq(expiry, block.timestamp + duration);
        assertTrue(isActive);
        
        // Check user quotes mapping
        uint256[] memory userQuotes = rfq.getUserQuotes(maker1);
        assertEq(userQuotes.length, 1);
        assertEq(userQuotes[0], 0);
    }
    
    function test_SubmitSellQuote() public {
        uint256 rwaAmount = 200 * 1e18; // 200 RWA tokens
        uint256 pricePerToken = 15 * 1e6; // $15 per token
        uint256 duration = 2 hours;
        
        uint256 rwaBalanceBefore = rwaToken.balanceOf(maker1);
        uint256 contractRwaBefore = rwaToken.balanceOf(address(rfq));
        
        vm.expectEmit(true, true, false, true);
        emit QuoteSubmitted(0, maker1, false, rwaAmount, pricePerToken);
        
        vm.prank(maker1);
        rfq.submitQuote(false, rwaAmount, pricePerToken, duration);
        
        // Check RWA tokens were deposited
        assertEq(rwaToken.balanceOf(maker1), rwaBalanceBefore - rwaAmount);
        assertEq(rwaToken.balanceOf(address(rfq)), contractRwaBefore + rwaAmount);
        
        // Check quote details
        (
            address quoteMaker,
            bool isBuyQuote,
            uint256 quoteRwaAmount,
            uint256 quotePricePerToken,
            uint256 expiry,
            bool isActive
        ) = rfq.quotes(0);
        
        assertEq(quoteMaker, maker1);
        assertFalse(isBuyQuote);
        assertEq(quoteRwaAmount, rwaAmount);
        assertEq(quotePricePerToken, pricePerToken);
        assertEq(expiry, block.timestamp + duration);
        assertTrue(isActive);
    }
    
    function test_SubmitQuote_RevertInvalidAmount() public {
        // Zero RWA amount
        vm.expectRevert(RWARFQ.InvalidAmount.selector);
        vm.prank(maker1);
        rfq.submitQuote(true, 0, 10 * 1e6, 1 hours);
        
        // Zero price
        vm.expectRevert(RWARFQ.InvalidAmount.selector);
        vm.prank(maker1);
        rfq.submitQuote(true, 100 * 1e18, 0, 1 hours);
    }
    
    function test_FillBuyQuote() public {
        // Maker submits buy quote
        uint256 rwaAmount = 100 * 1e18;
        uint256 pricePerToken = 10 * 1e6;
        uint256 duration = 1 hours;
        
        vm.prank(maker1);
        rfq.submitQuote(true, rwaAmount, pricePerToken, duration);
        
        // Taker fills the quote
        uint256 usdcAmount = (rwaAmount * pricePerToken) / 1e18;
        uint256 fee = (usdcAmount * 25) / 10000; // 0.25% fee
        uint256 netAmount = usdcAmount - fee;
        
        uint256 takerRwaBefore = rwaToken.balanceOf(taker1);
        uint256 takerUsdcBefore = usdc.balanceOf(taker1);
        uint256 makerRwaBefore = rwaToken.balanceOf(maker1);
        uint256 feeRecipientBefore = usdc.balanceOf(feeRecipient);
        
        vm.expectEmit(true, true, false, true);
        emit QuoteFilled(0, taker1, rwaAmount, usdcAmount);
        
        vm.prank(taker1);
        rfq.fillQuote(0);
        
        // Check balances
        assertEq(rwaToken.balanceOf(taker1), takerRwaBefore - rwaAmount); // Taker loses RWA
        assertEq(usdc.balanceOf(taker1), takerUsdcBefore + netAmount); // Taker gets USDC minus fee
        assertEq(rwaToken.balanceOf(maker1), makerRwaBefore + rwaAmount); // Maker gets RWA
        assertEq(usdc.balanceOf(feeRecipient), feeRecipientBefore + fee); // Fee recipient gets fee
        
        // Check quote is no longer active
        (, , , , , bool isActive) = rfq.quotes(0);
        assertFalse(isActive);
        
        // Check trading stats
        (uint256 totalVolume, uint256 totalTrades) = rfq.getTradingStats();
        assertEq(totalVolume, usdcAmount);
        assertEq(totalTrades, 1);
    }
     
    
    function test_FillQuote_RevertQuoteNotActive() public {
        // Submit and immediately fill a quote
        vm.prank(maker1);
        rfq.submitQuote(true, 100 * 1e18, 10 * 1e6, 1 hours);
        
        vm.prank(taker1);
        rfq.fillQuote(0);
        
        // Try to fill again
        vm.expectRevert(RWARFQ.QuoteNotActive.selector);
        vm.prank(taker2);
        rfq.fillQuote(0);
    }
    
    function test_FillQuote_RevertQuoteExpired() public {
        // Submit quote with short duration
        vm.prank(maker1);
        rfq.submitQuote(true, 100 * 1e18, 10 * 1e6, 1 hours);
        
        // Fast forward past expiry
        vm.warp(block.timestamp + 2 hours);
        
        vm.expectRevert(RWARFQ.QuoteExpired.selector);
        vm.prank(taker1);
        rfq.fillQuote(0);
    }
    
    function test_CancelQuote() public {
        // Submit buy quote
        uint256 rwaAmount = 100 * 1e18;
        uint256 pricePerToken = 10 * 1e6;
        uint256 usdcAmount = (rwaAmount * pricePerToken) / 1e18;
        
        vm.prank(maker1);
        rfq.submitQuote(true, rwaAmount, pricePerToken, 1 hours);
        
        uint256 makerUsdcBefore = usdc.balanceOf(maker1);
        uint256 contractUsdcBefore = usdc.balanceOf(address(rfq));
        
        vm.expectEmit(false, false, false, true);
        emit QuoteCancelled(0);
        
        vm.prank(maker1);
        rfq.cancelQuote(0);
        
        // Check USDC was refunded
        assertEq(usdc.balanceOf(maker1), makerUsdcBefore + usdcAmount);
        assertEq(usdc.balanceOf(address(rfq)), contractUsdcBefore - usdcAmount);
        
        // Check quote is no longer active
        (, , , , , bool isActive) = rfq.quotes(0);
        assertFalse(isActive);
    }
    
    function test_CancelSellQuote() public {
        // Submit sell quote
        uint256 rwaAmount = 200 * 1e18;
        uint256 pricePerToken = 15 * 1e6;
        
        vm.prank(maker1);
        rfq.submitQuote(false, rwaAmount, pricePerToken, 1 hours);
        
        uint256 makerRwaBefore = rwaToken.balanceOf(maker1);
        uint256 contractRwaBefore = rwaToken.balanceOf(address(rfq));
        
        vm.expectEmit(false, false, false, true);
        emit QuoteCancelled(0);
        
        vm.prank(maker1);
        rfq.cancelQuote(0);
        
        // Check RWA tokens were refunded
        assertEq(rwaToken.balanceOf(maker1), makerRwaBefore + rwaAmount);
        assertEq(rwaToken.balanceOf(address(rfq)), contractRwaBefore - rwaAmount);
        
        // Check quote is no longer active
        (, , , , , bool isActive) = rfq.quotes(0);
        assertFalse(isActive);
    }
    
    function test_CancelQuote_RevertNotQuoteMaker() public {
        vm.prank(maker1);
        rfq.submitQuote(true, 100 * 1e18, 10 * 1e6, 1 hours);
        
        vm.expectRevert(RWARFQ.NotQuoteMaker.selector);
        vm.prank(maker2);
        rfq.cancelQuote(0);
    }
    
    function test_CancelQuote_RevertQuoteNotActive() public {
        vm.prank(maker1);
        rfq.submitQuote(true, 100 * 1e18, 10 * 1e6, 1 hours);
        
        // Cancel once
        vm.prank(maker1);
        rfq.cancelQuote(0);
        
        // Try to cancel again
        vm.expectRevert(RWARFQ.QuoteNotActive.selector);
        vm.prank(maker1);
        rfq.cancelQuote(0);
    }
    
    function test_GetActiveQuotes() public {
        // Submit multiple quotes
        vm.prank(maker1);
        rfq.submitQuote(true, 100 * 1e18, 10 * 1e6, 1 hours); // Buy quote
        
        vm.prank(maker2);
        rfq.submitQuote(false, 200 * 1e18, 15 * 1e6, 2 hours); // Sell quote
        
        vm.prank(maker1);
        rfq.submitQuote(true, 150 * 1e18, 12 * 1e6, 3 hours); // Another buy quote
        
        // Get active buy quotes
        uint256[] memory buyQuotes = rfq.getActiveQuotes(true);
        assertEq(buyQuotes.length, 2);
        assertEq(buyQuotes[0], 0);
        assertEq(buyQuotes[1], 2);
        
        // Get active sell quotes
        uint256[] memory sellQuotes = rfq.getActiveQuotes(false);
        assertEq(sellQuotes.length, 1);
        assertEq(sellQuotes[0], 1);
        
        // Fill one buy quote
        vm.prank(taker1);
        rfq.fillQuote(0);
        
        // Check active buy quotes again
        buyQuotes = rfq.getActiveQuotes(true);
        assertEq(buyQuotes.length, 1);
        assertEq(buyQuotes[0], 2);
    }
    
    function test_GetActiveQuotes_ExpiresQuotes() public {
        // Submit quote with short duration
        vm.prank(maker1);
        rfq.submitQuote(true, 100 * 1e18, 10 * 1e6, 1 hours);
        
        // Should show active initially
        uint256[] memory activeQuotes = rfq.getActiveQuotes(true);
        assertEq(activeQuotes.length, 1);
        
        // Fast forward past expiry
        vm.warp(block.timestamp + 2 hours);
        
        // Should not show expired quotes
        activeQuotes = rfq.getActiveQuotes(true);
        assertEq(activeQuotes.length, 0);
    }
    
    function test_GetBestPrices() public {
        // Submit multiple buy quotes
        vm.prank(maker1);
        rfq.submitQuote(true, 100 * 1e18, 10 * 1e6, 1 hours); // $10
        
        vm.prank(maker2);
        rfq.submitQuote(true, 150 * 1e18, 12 * 1e6, 1 hours); // $12 (higher)
        
        // Submit multiple sell quotes
        vm.prank(maker1);
        rfq.submitQuote(false, 200 * 1e18, 15 * 1e6, 1 hours); // $15
        
        vm.prank(maker2);
        rfq.submitQuote(false, 250 * 1e18, 13 * 1e6, 1 hours); // $13 (lower)
        
        (uint256 bestBuyPrice, uint256 bestSellPrice) = rfq.getBestPrices();
        
        assertEq(bestBuyPrice, 12 * 1e6); // Highest buy price
        assertEq(bestSellPrice, 13 * 1e6); // Lowest sell price
    }
    
    function test_GetBestPrices_NoQuotes() public {
        (uint256 bestBuyPrice, uint256 bestSellPrice) = rfq.getBestPrices();
        
        assertEq(bestBuyPrice, 0);
        assertEq(bestSellPrice, type(uint256).max);
    }
    
    function test_GetUserQuotes() public {
        // Submit multiple quotes for maker1
        vm.startPrank(maker1);
        rfq.submitQuote(true, 100 * 1e18, 10 * 1e6, 1 hours);
        rfq.submitQuote(false, 200 * 1e18, 15 * 1e6, 1 hours);
        rfq.submitQuote(true, 150 * 1e18, 12 * 1e6, 1 hours);
        vm.stopPrank();
        
        // Submit one quote for maker2
        vm.prank(maker2);
        rfq.submitQuote(false, 300 * 1e18, 20 * 1e6, 1 hours);
        
        uint256[] memory maker1Quotes = rfq.getUserQuotes(maker1);
        assertEq(maker1Quotes.length, 3);
        assertEq(maker1Quotes[0], 0);
        assertEq(maker1Quotes[1], 1);
        assertEq(maker1Quotes[2], 2);
        
        uint256[] memory maker2Quotes = rfq.getUserQuotes(maker2);
        assertEq(maker2Quotes.length, 1);
        assertEq(maker2Quotes[0], 3);
    }
     
    
    function test_UpdateTradingFee() public {
        uint256 newFee = 50; // 0.5%
        
        vm.prank(admin);
        rfq.updateTradingFee(newFee);
        
        assertEq(rfq.tradingFee(), newFee);
    }
    
    function test_UpdateTradingFee_RevertFeeTooHigh() public {
        uint256 highFee = 1500; // 15%
        
        vm.expectRevert("Fee too high");
        vm.prank(admin);
        rfq.updateTradingFee(highFee);
    }
    
    function test_UpdateFeeRecipient() public {
        address newRecipient = makeAddr("newFeeRecipient");
        
        vm.prank(admin);
        rfq.updateFeeRecipient(newRecipient);
        
        assertEq(rfq.feeRecipient(), newRecipient);
    }
    
    function test_UpdateFeeRecipient_RevertInvalidRecipient() public {
        vm.expectRevert("Invalid recipient");
        vm.prank(admin);
        rfq.updateFeeRecipient(address(0));
    }
    
    function test_ComplexTradingScenario() public {
        // Multiple makers submit quotes
        vm.prank(maker1);
        rfq.submitQuote(true, 100 * 1e18, 10 * 1e6, 1 hours); // Buy at $10
        
        vm.prank(maker2);
        rfq.submitQuote(false, 200 * 1e18, 12 * 1e6, 1 hours); // Sell at $12
        
        vm.prank(maker1);
        rfq.submitQuote(false, 150 * 1e18, 11 * 1e6, 1 hours); // Sell at $11 (better)
        
        // Check best prices
        (uint256 bestBuyPrice, uint256 bestSellPrice) = rfq.getBestPrices();
        assertEq(bestBuyPrice, 10 * 1e6);
        assertEq(bestSellPrice, 11 * 1e6);
        
        // Taker fills the best sell quote
        vm.prank(taker1);
        rfq.fillQuote(2); // Quote with $11 price
        
        // Check updated best prices
        (bestBuyPrice, bestSellPrice) = rfq.getBestPrices();
        assertEq(bestBuyPrice, 10 * 1e6);
        assertEq(bestSellPrice, 12 * 1e6);
        
        // Check trading volume
        (uint256 totalVolume, uint256 totalTrades) = rfq.getTradingStats();
        uint256 expectedVolume = (150 * 1e18 * 11 * 1e6) / 1e18; // $1650
        assertEq(totalVolume, expectedVolume);
        assertEq(totalTrades, 1);
    }
}