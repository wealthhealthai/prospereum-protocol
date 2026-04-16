// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IStakingVault
 * @notice Interface for StakingVault as consumed by RewardEngine.
 *
 * @dev Updated for StakingVault v2.0 (epoch-aware checkpointing):
 *      - snapshotEpoch(): finalize an epoch (no new contributions accepted after this)
 *      - distributeStakerRewards(): fund the reward pools for a finalized epoch
 *
 *      The old totalStakeTime() and stakeTimeOf() view helpers are no longer part of
 *      the RewardEngine interface — reward calculation and distribution is now handled
 *      entirely within StakingVault. Users claim via StakingVault.claimStake(epochId).
 */
interface IStakingVault {
    /// @notice Finalize an epoch. Called by RewardEngine during _finalizeSingleEpoch().
    ///         After this call, no new stakeTime contributions are accepted for epochId.
    function snapshotEpoch(uint256 epochId) external;

    /// @notice Fund the PSRE and LP reward pools for a finalized epoch.
    ///         Pulls `totalStakerPool` PSRE from RewardEngine via safeTransferFrom.
    ///         RewardEngine must approve this contract for totalStakerPool before calling.
    ///         Called by RewardEngine immediately after snapshotEpoch in _finalizeSingleEpoch().
    function distributeStakerRewards(uint256 epochId, uint256 totalStakerPool) external;

    /// @notice Total PSRE staked captured at snapshotEpoch(epochId).
    ///         Used by RewardEngine to skip staker mint when no stakers exist.
    function epochTotalPSREStaked(uint256 epochId) external view returns (uint256);

    /// @notice Total LP staked captured at snapshotEpoch(epochId).
    ///         Used by RewardEngine to skip staker mint when no stakers exist.
    function epochTotalLPStaked(uint256 epochId) external view returns (uint256);
}
