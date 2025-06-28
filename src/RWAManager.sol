// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AccessControl} from
    "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/access/AccessControl.sol";

import "./RWATokenFactory.sol"; 
import "./RWAToken.sol";
import "./PrimaryDistribution.sol";

/**
 * @title RWAManager
 * @notice Main contract for managing RWA tokens and their primary sales distribution.
 * @dev New flow: 
 *      1. Creator issues RWA token from RWATokenFactory
 *      2. Creator manually sets up CCIP configuration on all chains
 *      3. Creator mints tokens on all chains
 *      4. Creator registers to RWAManager for primary distribution
 */

 contract RWAManager is AccessControl {
    
    // Specialized factories
    RWATokenFactory public immutable tokenFactory;
    PrimaryDistribution public immutable primaryDistribution;

    // Project management
    struct RWAProject {
        address rwaToken;
        address creator;
        bool isActive;
        bool ccipConfigured;
        uint256 totalSupply;
        uint256 createdAt;
        uint256 registeredAt;
        ProjectStatus status;
    }

    enum ProjectStatus {
        CREATED,      // Token created but CCIP not configured
        CCIP_READY,   // CCIP configured, tokens minted, ready for registration
        REGISTERED,   // Registered for primary sales
        ACTIVE,       // Primary sales active
        COMPLETED     // Primary sales completed
    }
    
    mapping(uint256 => RWAProject) public projects;
    mapping(address => uint256[]) public creatorProjects;
    mapping(address => uint256) public tokenToProjectId; // New: map token address to project ID
    uint256 public nextProjectId = 1;

    // Configuration
    address public feeRecipient;
    address public treasury;
    
    event ProjectCreated(
        uint256 indexed projectId,
        address indexed creator,
        address indexed tokenAddress,
        string name,
        string symbol
    );

    event ProjectCCIPConfigured(
        uint256 indexed projectId,
        address indexed creator,
        uint256 totalSupply
    );

    event ProjectRegisteredForSales(
        uint256 indexed projectId,
        address indexed creator,
        uint256 salesAllocation,
        uint256 pricePerTokenUSDC
    );

    event ProjectStatusUpdated(
        uint256 indexed projectId,
        ProjectStatus oldStatus,
        ProjectStatus newStatus
    );

    constructor(
        address _tokenFactory,
        address _primaryDistribution,
        address _feeRecipient,
        address _treasury
    ) {
        require(_tokenFactory != address(0), "Invalid token factory");
        require(_primaryDistribution != address(0), "Invalid primary distribution");
        require(_feeRecipient != address(0), "Invalid fee recipient");
        require(_treasury != address(0), "Invalid treasury");
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        tokenFactory = RWATokenFactory(_tokenFactory); 
        primaryDistribution = PrimaryDistribution(_primaryDistribution);
        feeRecipient = _feeRecipient;
        treasury = _treasury;
    }

    /**
     * @notice Step 1: Create RWA token (no CCIP configuration yet)
     * @param name Token name
     * @param symbol Token symbol
     * @param metadata Asset metadata
     * @return projectId ID of the created project
     */
    function createRWAToken(
        string memory name,
        string memory symbol,
        RWAToken.AssetMetadata memory metadata
    ) external returns (uint256 projectId) {
        require(bytes(name).length > 0, "Name required");
        require(bytes(symbol).length > 0, "Symbol required");
        
        projectId = nextProjectId++;
        
        // Create token using TokenFactory
        address tokenAddress = tokenFactory.createToken(
            projectId,
            name,
            symbol,
            metadata
        );
        
        // Store project information
        projects[projectId] = RWAProject({
            rwaToken: tokenAddress,
            creator: msg.sender,
            isActive: false, // Not active until registered for sales
            ccipConfigured: false,
            totalSupply: 0,
            createdAt: block.timestamp,
            registeredAt: 0,
            status: ProjectStatus.CREATED
        });
        
        creatorProjects[msg.sender].push(projectId);
        tokenToProjectId[tokenAddress] = projectId;
        
        emit ProjectCreated(
            projectId,
            msg.sender,
            tokenAddress,
            name,
            symbol
        );
        
        return projectId;
    }

    /**
     * @notice Step 2: Mark CCIP as configured and set total supply
     * @dev Called after creator has manually configured CCIP on all chains and minted tokens
     * @param projectId Project ID
     * @param totalSupply Total token supply across all chains
     */
    function markCCIPConfigured(
        uint256 projectId,
        uint256 totalSupply
    ) external {
        require(projects[projectId].creator == msg.sender, "Not project creator");
        require(projects[projectId].status == ProjectStatus.CREATED, "Invalid status");
        require(totalSupply > 0, "Invalid total supply");
        
        projects[projectId].ccipConfigured = true;
        projects[projectId].totalSupply = totalSupply;
        
        ProjectStatus oldStatus = projects[projectId].status;
        projects[projectId].status = ProjectStatus.CCIP_READY;
        
        emit ProjectCCIPConfigured(projectId, msg.sender, totalSupply);
        emit ProjectStatusUpdated(projectId, oldStatus, ProjectStatus.CCIP_READY);
    }

    /**
     * @notice Step 3: Register RWA project for primary sales distribution
     * @param projectId Project ID (must have CCIP configured)
     * @param projectWallet Project treasury wallet
     * @param projectAllocationPercent Percentage allocated to project (0-100)
     * @param pricePerTokenUSDC Price per token in USDC for primary sales
     * @param minPurchaseUSDC Minimum purchase amount in USDC
     * @param maxPurchaseUSDC Maximum purchase amount in USDC
     */
    function registerForPrimarySales(
        uint256 projectId,
        address projectWallet,
        uint256 projectAllocationPercent,
        uint256 pricePerTokenUSDC,
        uint256 minPurchaseUSDC,
        uint256 maxPurchaseUSDC
    ) external {
        require(projects[projectId].creator == msg.sender, "Not project creator");
        require(projects[projectId].status == ProjectStatus.CCIP_READY, "CCIP not configured");
        require(projectWallet != address(0), "Invalid project wallet");
        require(pricePerTokenUSDC > 0, "Price required");
        require(projectAllocationPercent <= 100, "Invalid allocation");
        require(minPurchaseUSDC <= maxPurchaseUSDC, "Invalid purchase limits");
        
        RWAProject storage project = projects[projectId];
        
        // Calculate allocations based on reported total supply
        uint256 projectTokens = (project.totalSupply * projectAllocationPercent) / 100;
        uint256 salesAllocation = project.totalSupply - projectTokens;
        
        // Register for primary distribution
        primaryDistribution.registerTokenSale(
            projectId,
            project.rwaToken,
            projectWallet, // Treasury for receiving USDC
            salesAllocation,
            pricePerTokenUSDC,
            minPurchaseUSDC,
            maxPurchaseUSDC
        );
        
        // Note: Creator should manually transfer sales allocation tokens to PrimaryDistribution contract
        // and project allocation tokens to project wallet after this call
        
        // Update project status
        project.registeredAt = block.timestamp;
        ProjectStatus oldStatus = project.status;
        project.status = ProjectStatus.REGISTERED;
        
        emit ProjectRegisteredForSales(
            projectId,
            msg.sender,
            salesAllocation,
            pricePerTokenUSDC
        );
        
        emit ProjectStatusUpdated(projectId, oldStatus, ProjectStatus.REGISTERED);
    }

    /**
     * @notice Activate primary sales for a registered project
     * @param projectId Project ID
     */
    function activatePrimarySales(uint256 projectId) external {
        require(projects[projectId].creator == msg.sender, "Not project creator");
        require(projects[projectId].status == ProjectStatus.REGISTERED, "Not registered");
        
        projects[projectId].isActive = true;
        ProjectStatus oldStatus = projects[projectId].status;
        projects[projectId].status = ProjectStatus.ACTIVE;
        
        emit ProjectStatusUpdated(projectId, oldStatus, ProjectStatus.ACTIVE);
    }

    /**
     * @notice Complete primary sales for a project
     * @param projectId Project ID
     */
    function completePrimarySales(uint256 projectId) external {
        require(projects[projectId].creator == msg.sender, "Not project creator");
        require(projects[projectId].status == ProjectStatus.ACTIVE, "Not active");
        
        projects[projectId].isActive = false;
        ProjectStatus oldStatus = projects[projectId].status;
        projects[projectId].status = ProjectStatus.COMPLETED;
        
        emit ProjectStatusUpdated(projectId, oldStatus, ProjectStatus.COMPLETED);
    }
    
    /**
     * @notice Get project details
     */
    function getProject(uint256 projectId) external view returns (RWAProject memory) {
        return projects[projectId];
    }
    
    /**
     * @notice Get projects created by a specific address
     */
    function getCreatorProjects(address creator) external view returns (uint256[] memory) {
        return creatorProjects[creator];
    }
    
    /**
     * @notice Get project ID by token address
     */
    function getProjectIdByToken(address tokenAddress) external view returns (uint256) {
        return tokenToProjectId[tokenAddress];
    }
    
    /**
     * @notice Check if a project exists and is in a specific status
     */
    function isProjectInStatus(uint256 projectId, ProjectStatus status) external view returns (bool) {
        return projects[projectId].status == status;
    }
    
    /**
     * @notice Check if a project is ready for CCIP configuration
     */
    function isReadyForCCIP(uint256 projectId) external view returns (bool) {
        return projects[projectId].status == ProjectStatus.CREATED;
    }
    
    /**
     * @notice Check if a project is ready for primary sales registration
     */
    function isReadyForSalesRegistration(uint256 projectId) external view returns (bool) {
        return projects[projectId].status == ProjectStatus.CCIP_READY;
    }
    
    /**
     * @notice Emergency pause project (only creator)
     */
    function pauseProject(uint256 projectId) external {
        require(projects[projectId].creator == msg.sender, "Not project creator");
        projects[projectId].isActive = false;
    }
    
    /**
     * @notice Update treasury address (only admin)
     */
    function updateTreasury(address newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newTreasury != address(0), "Invalid treasury");
        treasury = newTreasury;
    }
    
    /**
     * @notice Update fee recipient (only admin)
     */
    function updateFeeRecipient(address newFeeRecipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newFeeRecipient != address(0), "Invalid fee recipient");
        feeRecipient = newFeeRecipient;
    }

    /**
     * @notice Get project statistics
     */
    function getProjectStats(uint256 projectId) external view returns (
        ProjectStatus status,
        bool ccipConfigured,
        uint256 totalSupply,
        bool isActive,
        uint256 createdAt,
        uint256 registeredAt
    ) {
        RWAProject memory project = projects[projectId];
        return (
            project.status,
            project.ccipConfigured,
            project.totalSupply,
            project.isActive,
            project.createdAt,
            project.registeredAt
        );
    }
 }
