// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AccessControl} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/access/AccessControl.sol";
import {SafeERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

import "./RWAToken.sol";

/**
 * @title RWARFQ 
 * @notice Simple Request-for-Quote system for RWA token secondary market trading
 * @dev Minimal implementation using USDC for institutional trading
 */
contract RWARFQ is AccessControl {
    
    using SafeERC20 for IERC20;
    
    RWAToken public immutable rwaToken;
    IERC20 public immutable usdc;
    
    struct Quote {
        address maker;
        bool isBuyQuote; // true = buying RWA with USDC, false = selling RWA for USDC
        uint256 rwaAmount; // Amount of RWA tokens
        uint256 pricePerToken; // Price per RWA token in USDC (6 decimals)
        uint256 expiry;
        bool isActive;
    }
    
    Quote[] public quotes;
    mapping(address => uint256[]) public userQuotes;
    
    // Configuration
    uint256 public tradingFee = 25; // 0.25% (basis points)
    address public feeRecipient;
    
    // Statistics
    uint256 public totalVolumeUSDC;
    uint256 public totalTrades;
    
    // Events
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
    
    // Errors
    error QuoteNotActive();
    error QuoteExpired();
    error InvalidAmount();
    error NotQuoteMaker();
    
    constructor(
        address _rwaToken,
        address _usdc,
        address _feeRecipient,
        address _admin
    ) {
        rwaToken = RWAToken(_rwaToken);
        usdc = IERC20(_usdc);
        feeRecipient = _feeRecipient;
        
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }
    
    /**
     * @notice Submit a new quote for RWA tokens
     */
    function submitQuote(
        bool isBuyQuote,
        uint256 rwaAmount,
        uint256 pricePerToken,
        uint256 duration
    ) external {
        if (rwaAmount == 0 || pricePerToken == 0) revert InvalidAmount();
        
        uint256 usdcAmount = (rwaAmount * pricePerToken) / 1e18;
        
        if (isBuyQuote) {
            // Buyer deposits USDC
            usdc.safeTransferFrom(msg.sender, address(this), usdcAmount);
        } else {
            // Seller deposits RWA tokens
            rwaToken.transferFrom(msg.sender, address(this), rwaAmount);
        }
        
        quotes.push(Quote({
            maker: msg.sender,
            isBuyQuote: isBuyQuote,
            rwaAmount: rwaAmount,
            pricePerToken: pricePerToken,
            expiry: block.timestamp + duration,
            isActive: true
        }));
        
        uint256 quoteId = quotes.length - 1;
        userQuotes[msg.sender].push(quoteId);
        
        emit QuoteSubmitted(quoteId, msg.sender, isBuyQuote, rwaAmount, pricePerToken);
    }
    
    /**
     * @notice Fill a quote completely
     */
    function fillQuote(uint256 quoteId) external {
        Quote storage quote = quotes[quoteId];
        
        if (!quote.isActive) revert QuoteNotActive();
        if (block.timestamp > quote.expiry) revert QuoteExpired();
        
        uint256 usdcAmount = (quote.rwaAmount * quote.pricePerToken) / 1e18;
        uint256 fee = (usdcAmount * tradingFee) / 10000;
        uint256 netAmount = usdcAmount - fee;
        
        quote.isActive = false;
        
        if (quote.isBuyQuote) {
            // Maker buying, taker selling
            rwaToken.transferFrom(msg.sender, quote.maker, quote.rwaAmount);
            usdc.safeTransfer(msg.sender, netAmount);
        } else {
            // Maker selling, taker buying
            usdc.safeTransferFrom(msg.sender, quote.maker, netAmount);
            rwaToken.transfer(msg.sender, quote.rwaAmount);
        }
        
        // Transfer fee
        if (fee > 0) {
            usdc.safeTransfer(feeRecipient, fee);
        }
        
        // Update stats
        totalVolumeUSDC += usdcAmount;
        totalTrades++;
        
        emit QuoteFilled(quoteId, msg.sender, quote.rwaAmount, usdcAmount);
    }
    
    /**
     * @notice Cancel an active quote
     */
    function cancelQuote(uint256 quoteId) external {
        Quote storage quote = quotes[quoteId];
        
        if (quote.maker != msg.sender) revert NotQuoteMaker();
        if (!quote.isActive) revert QuoteNotActive();
        
        quote.isActive = false;
        
        uint256 usdcAmount = (quote.rwaAmount * quote.pricePerToken) / 1e18;
        
        if (quote.isBuyQuote) {
            // Refund USDC to buyer
            usdc.safeTransfer(quote.maker, usdcAmount);
        } else {
            // Return RWA tokens to seller
            rwaToken.transfer(quote.maker, quote.rwaAmount);
        }
        
        emit QuoteCancelled(quoteId);
    }
    
    /**
     * @notice Get active quotes
     */
    function getActiveQuotes(bool isBuyQuote) external view returns (uint256[] memory) {
        uint256 count = 0;
        
        // Count active quotes
        for (uint256 i = 0; i < quotes.length; i++) {
            if (quotes[i].isActive && 
                quotes[i].isBuyQuote == isBuyQuote && 
                block.timestamp <= quotes[i].expiry) {
                count++;
            }
        }
        
        uint256[] memory activeQuoteIds = new uint256[](count);
        uint256 index = 0;
        
        for (uint256 i = 0; i < quotes.length; i++) {
            if (quotes[i].isActive && 
                quotes[i].isBuyQuote == isBuyQuote && 
                block.timestamp <= quotes[i].expiry) {
                activeQuoteIds[index] = i;
                index++;
            }
        }
        
        return activeQuoteIds;
    }
    
    /**
     * @notice Get best prices
     */
    function getBestPrices() external view returns (uint256 bestBuyPrice, uint256 bestSellPrice) {
        bestSellPrice = type(uint256).max;
        
        for (uint256 i = 0; i < quotes.length; i++) {
            if (!quotes[i].isActive || block.timestamp > quotes[i].expiry) continue;
            
            if (quotes[i].isBuyQuote && quotes[i].pricePerToken > bestBuyPrice) {
                bestBuyPrice = quotes[i].pricePerToken;
            } else if (!quotes[i].isBuyQuote && quotes[i].pricePerToken < bestSellPrice) {
                bestSellPrice = quotes[i].pricePerToken;
            }
        }
    }
    
    /**
     * @notice Get user quotes
     */
    function getUserQuotes(address user) external view returns (uint256[] memory) {
        return userQuotes[user];
    }
    
    /**
     * @notice Get trading stats
     */
    function getTradingStats() external view returns (uint256, uint256) {
        return (totalVolumeUSDC, totalTrades);
    }
    
    /**
     * @notice Update trading fee (admin only)
     */
    function updateTradingFee(uint256 newFee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newFee <= 1000, "Fee too high"); // Max 10%
        tradingFee = newFee;
    }
    
    /**
     * @notice Update fee recipient (admin only)
     */
    function updateFeeRecipient(address newRecipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newRecipient != address(0), "Invalid recipient");
        feeRecipient = newRecipient;
    }
}
