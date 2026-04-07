// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IPartnerVault
 * @notice Interface for PartnerVault as consumed by RewardEngine (v3.2).
 * @dev Dev Spec v3.2, Section 2.3
 */
interface IPartnerVault {
    // ── Ownership ──────────────────────────────────────────────────────────
    /// @notice Returns the current owner of the vault.
    ///         Used by RewardEngine and Factory to authorize actions after
    ///         ownership transfer (fix #8: partnerOf stale after vault transfer).
    function owner() external view returns (address);

    // ── v3.2 snapshotEpoch (replaces cumBuy read) ──────────────────────────
    /// @notice Called by RewardEngine at epoch finalization.
    ///         Runs _updateCumS() then returns deltaCumS = cumS - lastEpochCumS
    ///         and commits lastEpochCumS = cumS.
    function snapshotEpoch() external returns (uint256 deltaCumS);

    // ── cumS state ─────────────────────────────────────────────────────────
    function getCumS()        external view returns (uint256);
    function getInitialCumS() external view returns (uint256);
    function isQualified()    external view returns (bool);

    // ── Leakage callback (called by registered CustomerVaults on withdrawal) ─
    function reportLeakage(uint256 amount) external;
}
