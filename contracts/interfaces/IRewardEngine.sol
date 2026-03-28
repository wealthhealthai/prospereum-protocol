// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IRewardEngine
 * @notice Interface for RewardEngine as consumed by PartnerVaultFactory (v3.2).
 */
interface IRewardEngine {
    /// @notice Register a new vault with its initial cumS baseline.
    ///         Called by PartnerVaultFactory immediately after vault creation + initial buy.
    function registerVault(address vault, uint256 initialCumS_) external;
}
