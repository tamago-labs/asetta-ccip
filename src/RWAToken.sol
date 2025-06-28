// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IBurnMintERC20} from "@chainlink/contracts/src/v0.8/shared/token/ERC20/IBurnMintERC20.sol";
import {
    ERC20,
    ERC20Burnable,
    IERC20
} from
    "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {AccessControl} from
    "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/access/AccessControl.sol";

/**
 * @title RWAToken
 * @notice Real World Asset (RWA) token in CCIP-compatible 
 * @dev ERC20 token representing fractional ownership of real-world assets
 */
contract RWAToken is IBurnMintERC20, ERC20Burnable, AccessControl {

    address internal immutable i_CCIPAdmin;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    // ============ Structs ============
    
    struct AssetMetadata {
        string assetType;        // "real-estate", "commodity", "art", "intellectual-property"
        string description;      // Detailed description of the asset
        uint256 totalValue;      // Total appraised value in USD (with 8 decimals)
        string url;              // URL to asset documentation/images
        uint256 createdAt;       // Creation timestamp
    }

    // ============ State Variables ============
    
    /// @notice Asset metadata
    AssetMetadata public assetData;
    
    // ============ Events ============
    
    event AssetMetadataUpdated(string assetType, string description, uint256 totalValue, string url);

    // ============ Errors ============
    
    error InvalidAssetType();  
    error InvalidTotalValue();
     
    // ============ Constructor ============
    
    constructor(
        string memory name_,
        string memory symbol_,
        AssetMetadata memory metadata_
    ) ERC20(name_, symbol_) {
        // Validate inputs
        if (bytes(metadata_.assetType).length == 0) revert InvalidAssetType();
        if (metadata_.totalValue == 0) revert InvalidTotalValue();
        
        // Set metadata
        assetData = metadata_;
        assetData.createdAt = block.timestamp;
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(BURNER_ROLE, msg.sender);
        i_CCIPAdmin = msg.sender;
    }

    // ============ Core Functions ============
    
    
     function mint(address account, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(account, amount);
    }

    function burn(uint256 amount) public override(IBurnMintERC20, ERC20Burnable) onlyRole(BURNER_ROLE) {
        super.burn(amount);
    }

    function burnFrom(address account, uint256 amount)
        public
        override(IBurnMintERC20, ERC20Burnable)
        onlyRole(BURNER_ROLE)
    {
        super.burnFrom(account, amount);
    }

    function burn(address account, uint256 amount) public virtual override {
        burnFrom(account, amount);
    }

    function getCCIPAdmin() public view returns (address) {
        return i_CCIPAdmin;
    }

    // ============ View Functions ============
      
    /**
     * @notice Get asset price per token in USD (8 decimals)
     * @return Price per token
     */
    function getPricePerToken() external view returns (uint256) {
        if (totalSupply() == 0) return 0;
        return assetData.totalValue * 1e18 / totalSupply();
    }
    
    /**
     * @notice Get total market cap in USD (8 decimals)
     * @return Market cap
     */
    function getMarketCap() external view returns (uint256) {
        return assetData.totalValue;
    }
      

    // ============ Admin Functions ============
    
     /**
     * @notice Update asset metadata (admin only)
     * @param newMetadata New asset metadata
     */
    function updateAssetMetadata(AssetMetadata memory newMetadata) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (bytes(newMetadata.assetType).length == 0) revert InvalidAssetType();
        if (newMetadata.totalValue == 0) revert InvalidTotalValue();
        
        assetData.assetType = newMetadata.assetType;
        assetData.description = newMetadata.description;
        assetData.totalValue = newMetadata.totalValue;
        assetData.url = newMetadata.url;
        // Keep original createdAt timestamp
        
        emit AssetMetadataUpdated(
            newMetadata.assetType,
            newMetadata.description,
            newMetadata.totalValue,
            newMetadata.url
        );
    }
 
     
}