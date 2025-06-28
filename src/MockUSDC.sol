// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title MockUSDC
 * @dev Lightweight mock of Circle’s USDC for local tests and public testnets.
 *      – 6‑decimals, symbol “USDC”
 *      – ANY address can call `mint` to create arbitrary tokens
 *
 *      ▸ Deploy → call mint() as needed → use in your dApp tests
 */

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USD Coin", "USDC") {
        // no initial supply – users mint on demand
    }

    /// @notice USDC uses 6 decimals instead of the default 18
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /// @notice Mint any amount of mock USDC to any address (test‑only!)
    /// @param to     Recipient of the newly minted tokens
    /// @param amount Amount **in full units**, e.g. `100_000000` for 100 USDC
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
