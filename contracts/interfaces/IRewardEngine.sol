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

    /// @notice Lazily finalize up to AUTO_FINALIZE_MAX_EPOCHS pending epochs.
    ///         Permissionless. Called automatically by createVault() and buy() so that
    ///         partner activity drives epoch finalization — no dedicated keeper required.
    ///         Safe to call when no epochs are pending (no-op).
    function autoFinalizeEpochs() external;

    /// @notice Returns true if the vault has qualified for rewards (cumS > initialCumS).
    ///         Used by PartnerVault.isQualified() to delegate the authoritative check to
    ///         RewardEngine (fix #21: PartnerVault.qualified flag always false).
    function qualified(address vault) external view returns (bool);
}
