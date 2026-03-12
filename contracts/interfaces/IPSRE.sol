// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IPSRE
 * @notice Interface for the PSRE token as consumed by RewardEngine.
 * @dev Extracted from RewardEngine.sol inline definition — pre-audit hygiene fix.
 */
interface IPSRE {
    /**
     * @notice Mint PSRE tokens. Called by RewardEngine at epoch finalization.
     * @dev balanceOf() and transfer() are not declared here because RewardEngine
     *      accesses them through IERC20(address(psre)) — no interface conflict needed.
     */
    function mint(address to, uint256 amount) external;
}
