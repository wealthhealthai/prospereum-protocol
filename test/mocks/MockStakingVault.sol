// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../contracts/interfaces/IStakingVault.sol";

/// @dev Mock StakingVault for RewardEngine tests.
///      Implements IStakingVault interface.
///      distributeStakerRewards() is a no-op (no token transfers in mock).
contract MockStakingVault is IStakingVault {
    // Track snapshotted epochs
    mapping(uint256 => bool) public snapshotted;

    // Track distributed rewards per epoch
    mapping(uint256 => uint256) public distributedAmount;

    // Track whether distribution occurred
    mapping(uint256 => bool) public epochDistributed;

    // Simulated staker totals (default 1 so RE doesn't zero out P_stakers unless test sets 0)
    mapping(uint256 => uint256) public epochTotalPSREStaked;
    mapping(uint256 => uint256) public epochTotalLPStaked;

    /// @dev Allow tests to set staker totals (e.g. 0 to simulate zero-staker epoch).
    function setEpochStakerTotals(uint256 epochId, uint256 psre, uint256 lp) external {
        epochTotalPSREStaked[epochId] = psre;
        epochTotalLPStaked[epochId]   = lp;
    }

    function snapshotEpoch(uint256 epochId) external override {
        snapshotted[epochId] = true;
        // Default: simulate stakers present (RE won't zero out P_stakers).
        // Tests that want zero-staker behaviour must call setEpochStakerTotals(epochId, 0, 0).
        if (epochTotalPSREStaked[epochId] == 0 && epochTotalLPStaked[epochId] == 0) {
            epochTotalPSREStaked[epochId] = 1;
        }
    }

    function distributeStakerRewards(uint256 epochId, uint256 amount) external override {
        distributedAmount[epochId] = amount;
        epochDistributed[epochId]  = true;
        // No actual token transfer in mock
    }
}
