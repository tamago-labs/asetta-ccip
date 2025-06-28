// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeERC20 } from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from
    "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/access/AccessControl.sol";

import "./RWAToken.sol";
import "./RWATokenFactory.sol";

/**
 * @title PrimaryDistribution
 * @notice Primary distribution contract for RWA tokens 
 */
contract PrimaryDistribution is AccessControl {
    
    using SafeERC20 for IERC20;

    IERC20 public immutable usdc;
    RWATokenFactory public immutable tokenFactory;
    
    struct ProjectSale {
        RWAToken rwaToken;
        address treasury;
        uint256 totalAllocation;
        uint256 totalSold;
        uint256 pricePerTokenUSDC; // Price in USDC (6 decimals)
        uint256 minPurchase; // Minimum purchase in USDC
        uint256 maxPurchase; // Maximum purchase in USDC
        bool isActive;
        address projectOwner;
        bool isRegistered;
    }
    
    // projectId => ProjectSale
    mapping(uint256 => ProjectSale) public projectSales;
    
    // projectId => user => whitelisted
    mapping(uint256 => mapping(address => bool)) public whitelisted;
    
    // projectId => user => purchased amount in USDC
    mapping(uint256 => mapping(address => uint256)) public purchased;
    
    // projectOwner => projectId[]
    mapping(address => uint256[]) public projectsByOwner;
    
    // Track which tokens were created by our factory
    mapping(address => uint256) public tokenToProjectId;

    uint256 public platformFeePercent = 50; // 0.5% (basis points)
    address public platformTreasury;

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
    
    event ProjectSaleUpdated(uint256 indexed projectId, string updateType);
    event UserWhitelisted(uint256 indexed projectId, address indexed user, bool status);
    event PlatformFeeUpdated(uint256 newFeePercent);
    
    error ProjectNotFound();
    error ProjectAlreadyRegistered();
    error ProjectNotActive();
    error NotProjectOwner();
    error TokenNotFromFactory();
    error NotWhitelisted();
    error InsufficientAllocation();
    error BelowMinimumPurchase();
    error ExceedsMaximumPurchase();
    error InvalidPrice();
    error InvalidAllocation();
    error InvalidAddress();
    error InvalidFeePercent();
    
    modifier onlyProjectOwner(uint256 projectId) {
        if (projectSales[projectId].projectOwner != msg.sender) revert NotProjectOwner();
        _;
    }
    
    modifier projectExists(uint256 projectId) {
        if (!projectSales[projectId].isRegistered) revert ProjectNotFound();
        _;
    }

    constructor(
        address _usdc,
        address _tokenFactory,
        address _platformTreasury
    ) {
        if (_usdc == address(0) || _tokenFactory == address(0) || _platformTreasury == address(0)) {
            revert InvalidAddress();
        }
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        usdc = IERC20(_usdc);
        tokenFactory = RWATokenFactory(_tokenFactory);
        platformTreasury = _platformTreasury;
    }

    /**
     * @notice Register existing factory-created token for primary sale
     * @dev Token must have been created by the associated factory
     */
    function registerTokenSale(
        uint256 projectId,
        address tokenAddress,
        address treasury,
        uint256 totalAllocation,
        uint256 pricePerTokenUSDC,
        uint256 minPurchase,
        uint256 maxPurchase
    ) external {
        if (projectSales[projectId].isRegistered) revert ProjectAlreadyRegistered();
        
        // Verify this token was created by our factory for this projectId
        // We'll check this by listening to factory events or maintaining registry
        if (tokenToProjectId[tokenAddress] != projectId && tokenToProjectId[tokenAddress] != 0) {
            revert TokenNotFromFactory();
        }
        
        // If not already mapped, verify via ownership pattern or factory call
        if (tokenToProjectId[tokenAddress] == 0) {
            // Additional verification could go here
            tokenToProjectId[tokenAddress] = projectId;
        }
        
        _registerProjectSale(
            projectId,
            tokenAddress,
            treasury,
            totalAllocation,
            pricePerTokenUSDC,
            minPurchase,
            maxPurchase,
            msg.sender
        );
    }

    /**
     * @notice Internal function to register project sale
     */
    function _registerProjectSale(
        uint256 projectId,
        address tokenAddress,
        address treasury,
        uint256 totalAllocation,
        uint256 pricePerTokenUSDC,
        uint256 minPurchase,
        uint256 maxPurchase,
        address projectOwner
    ) internal {
        if (tokenAddress == address(0) || treasury == address(0)) revert InvalidAddress();
        if (pricePerTokenUSDC == 0) revert InvalidPrice();
        if (totalAllocation == 0) revert InvalidAllocation();
        if (minPurchase > maxPurchase) revert InvalidAllocation();
        
        projectSales[projectId] = ProjectSale({
            rwaToken: RWAToken(tokenAddress),
            treasury: treasury,
            totalAllocation: totalAllocation,
            totalSold: 0,
            pricePerTokenUSDC: pricePerTokenUSDC,
            minPurchase: minPurchase,
            maxPurchase: maxPurchase,
            isActive: true,
            projectOwner: projectOwner,
            isRegistered: true
        });
        
        projectsByOwner[projectOwner].push(projectId);
        
        emit ProjectSaleRegistered(
            projectId,
            projectOwner,
            tokenAddress,
            totalAllocation,
            pricePerTokenUSDC
        );
    }

    /**
     * @notice Purchase tokens for a specific project
     */
    function purchaseTokens(uint256 projectId, uint256 usdcAmount) 
        external 
        projectExists(projectId) 
    {
        ProjectSale storage sale = projectSales[projectId];
        
        if (!sale.isActive) revert ProjectNotActive();
        if (!whitelisted[projectId][msg.sender]) revert NotWhitelisted();
        if (usdcAmount < sale.minPurchase) revert BelowMinimumPurchase();
        if (purchased[projectId][msg.sender] + usdcAmount > sale.maxPurchase) {
            revert ExceedsMaximumPurchase();
        }
        
        // Calculate token amount 
        // usdcAmount: USDC amount with 6 decimals (e.g., $1000 = 1000 * 1e6)
        // pricePerTokenUSDC: Price per token in USDC with 6 decimals (e.g., $5 = 5 * 1e6)
        // Result: Token amount with 18 decimals
        uint256 tokenAmount = (usdcAmount * 1e18) / sale.pricePerTokenUSDC;
        
        if (sale.totalSold + tokenAmount > sale.totalAllocation) {
            revert InsufficientAllocation();
        }
        
        // Calculate platform fee
        uint256 platformFee = (usdcAmount * platformFeePercent) / 10000;
        uint256 projectAmount = usdcAmount - platformFee;
        
        // Update state
        sale.totalSold += tokenAmount;
        purchased[projectId][msg.sender] += usdcAmount;
        
        // Transfer USDC from buyer
        usdc.safeTransferFrom(msg.sender, sale.treasury, projectAmount);
        if (platformFee > 0) {
            usdc.safeTransferFrom(msg.sender, platformTreasury, platformFee);
        }
        
        // Transfer RWA tokens to buyer
        sale.rwaToken.transfer(msg.sender, tokenAmount);
        
        emit TokensPurchased(projectId, msg.sender, usdcAmount, tokenAmount);
    }
    
    /**
     * @notice Whitelist users for a specific project
     */
    function whitelistUsers(
        uint256 projectId,
        address[] calldata users,
        bool status
    ) external projectExists(projectId) onlyProjectOwner(projectId) {
        for (uint256 i = 0; i < users.length; i++) {
            whitelisted[projectId][users[i]] = status;
            emit UserWhitelisted(projectId, users[i], status);
        }
    }
    
    /**
     * @notice Update project price
     */
    function updateProjectPrice(uint256 projectId, uint256 newPrice) 
        external 
        projectExists(projectId) 
        onlyProjectOwner(projectId) 
    {
        if (newPrice == 0) revert InvalidPrice();
        projectSales[projectId].pricePerTokenUSDC = newPrice;
        emit ProjectSaleUpdated(projectId, "price");
    }
    
    /**
     * @notice Update project purchase limits
     */
    function updateProjectLimits(
        uint256 projectId,
        uint256 newMin,
        uint256 newMax
    ) external projectExists(projectId) onlyProjectOwner(projectId) {
        if (newMin > newMax) revert InvalidAllocation();
        projectSales[projectId].minPurchase = newMin;
        projectSales[projectId].maxPurchase = newMax;
        emit ProjectSaleUpdated(projectId, "limits");
    }
    
    /**
     * @notice Update project treasury
     */
    function updateProjectTreasury(uint256 projectId, address newTreasury) 
        external 
        projectExists(projectId) 
        onlyProjectOwner(projectId) 
    {
        if (newTreasury == address(0)) revert InvalidAddress();
        projectSales[projectId].treasury = newTreasury;
        emit ProjectSaleUpdated(projectId, "treasury");
    }
    
    /**
     * @notice Toggle project active status
     */
    function toggleProjectStatus(uint256 projectId) 
        external 
        projectExists(projectId) 
        onlyProjectOwner(projectId) 
    {
        projectSales[projectId].isActive = !projectSales[projectId].isActive;
        emit ProjectSaleUpdated(projectId, "status");
    }
    
    /**
     * @notice Emergency withdraw unsold tokens
     */
    function emergencyWithdraw(uint256 projectId, uint256 amount) 
        external 
        projectExists(projectId) 
        onlyProjectOwner(projectId) 
    {
        projectSales[projectId].rwaToken.transfer(msg.sender, amount);
    }
    
    // View functions
    function getTokensForUSDC(uint256 projectId, uint256 usdcAmount) 
        external 
        view 
        projectExists(projectId) 
        returns (uint256) 
    {
        return (usdcAmount * 1e18) / projectSales[projectId].pricePerTokenUSDC;
    }
    
    function getUSDCForTokens(uint256 projectId, uint256 tokenAmount) 
        external 
        view 
        projectExists(projectId) 
        returns (uint256) 
    {
        return (tokenAmount * projectSales[projectId].pricePerTokenUSDC) / 1e18;
    }
    
    function getProjectsByOwner(address owner) external view returns (uint256[] memory) {
        return projectsByOwner[owner];
    }
    
    function getProjectSale(uint256 projectId) 
        external 
        view 
        projectExists(projectId) 
        returns (ProjectSale memory) 
    {
        return projectSales[projectId];
    }
    
    function isProjectRegistered(uint256 projectId) external view returns (bool) {
        return projectSales[projectId].isRegistered;
    }
    
    // Admin functions
    function updatePlatformFee(uint256 newFeePercent) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newFeePercent > 1000) revert InvalidFeePercent(); // Max 10%
        platformFeePercent = newFeePercent;
        emit PlatformFeeUpdated(newFeePercent);
    }
    
    function updatePlatformTreasury(address newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newTreasury == address(0)) revert InvalidAddress();
        platformTreasury = newTreasury;
    }
     

}