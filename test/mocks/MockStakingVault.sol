// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../contracts/interfaces/IStakingVault.sol";

/// @dev Mock StakingVault for RewardEngine tests.
///      Implements IStakingVault interface (unchanged from v2 to v3).
///      distributeStakerRewards() is a no-op (no token transfers in mock).
contract MockStakingVault is IStakingVault {
    // Track snapshotted epochs
    mapping(uint256 => bool) public snapshotted;

    // Track distributed rewards per epoch
    mapping(uint256 => uint256) public distributedAmount;

    // Track whether distribution occurred (mirrors v3 epochDistributed)
    mapping(uint256 => bool) public epochDistributed;

    function snapshotEpoch(uint256 epochId) external override {
        snapshotted[epochId] = true;
    }

    function distributeStakerRewards(uint256 epochId, uint256 amount) external override {
        distributedAmount[epochId] = amount;
        epochDistributed[epochId]  = true;
        // No actual token transfer in mock
    }
}
