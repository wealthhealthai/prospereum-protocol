// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../contracts/interfaces/IStakingVault.sol";

/// @dev Mock StakingVault for RewardEngine tests.
///      Implements IStakingVault v2 interface (epoch-aware checkpointing).
///      distributeStakerRewards() is a no-op (no token transfers in mock).
contract MockStakingVault is IStakingVault {
    // Track snapshotted epochs
    mapping(uint256 => bool) public snapshotted;

    // Track distributed rewards per epoch
    mapping(uint256 => uint256) public distributedAmount;

    function snapshotEpoch(uint256 epochId) external override {
        snapshotted[epochId] = true;
    }

    function distributeStakerRewards(uint256 epochId, uint256 amount) external override {
        distributedAmount[epochId] = amount;
        // No actual token transfer in mock
    }
}
