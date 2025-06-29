// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
 
import "./RWAToken.sol";

/**
 * @title RWATokenFactory
 * @notice Factory for creating RWA tokens
 */
contract RWATokenFactory {
    
    event TokenCreated(
        uint256 indexed projectId,
        address indexed creator,
        address indexed token,
        string name,
        string symbol
    );
    
    /**
     * @notice Create a new RWA token
     * @param projectId Project identifier from manager
     * @param name Token name
     * @param symbol Token symbol
     * @param metadata Asset metadata
     * @return tokenAddress Address of created token
     */
    function createToken(
        uint256 projectId,
        string memory name,
        string memory symbol,
        RWAToken.AssetMetadata memory metadata
    ) external returns (address tokenAddress) {
        require(bytes(name).length > 0, "Name required");
        require(bytes(symbol).length > 0, "Symbol required");
        
        // Deploy RWA Token
        RWAToken token = new RWAToken(
            name,
            symbol,
            metadata,
            msg.sender
        );
         
        tokenAddress = address(token);
        
        emit TokenCreated(
            projectId,
            tx.origin, // Original caller (project creator)
            tokenAddress,
            name,
            symbol
        );
    }
}
