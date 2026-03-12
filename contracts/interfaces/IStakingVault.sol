// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IStakingVault
 * @notice Interface for StakingVault as consumed by RewardEngine.
 * @dev Extracted from RewardEngine.sol inline definition — pre-audit hygiene fix.
 */
interface IStakingVault {
    function snapshotEpoch(uint256 epochId) external;
    function totalStakeTime(uint256 epochId) external view returns (uint256);
    function stakeTimeOf(address user, uint256 epochId) external view returns (uint256);
}
