// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IPausableToken
 * @notice Minimal interface for checking token pause state.
 *         Used by RewardEngine fix #16: gate minting when PSRE transfers are paused.
 *         Declared separately to avoid diamond conflict with OZ Pausable in PSRE.
 */
interface IPausableToken {
    function paused() external view returns (bool);
}
