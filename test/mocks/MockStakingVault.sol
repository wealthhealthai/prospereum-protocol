// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../contracts/interfaces/IStakingVault.sol";

/// @dev Mock StakingVault for RewardEngine tests.
///      Returns zero stakeTime by default (no stakers), or configured values.
contract MockStakingVault is IStakingVault {
    mapping(uint256 => uint256) public _totalStakeTime;
    mapping(uint256 => mapping(address => uint256)) public _userStakeTime;

    function setTotalStakeTime(uint256 epochId, uint256 amount) external {
        _totalStakeTime[epochId] = amount;
    }

    function setUserStakeTime(uint256 epochId, address user, uint256 amount) external {
        _userStakeTime[epochId][user] = amount;
    }

    function snapshotEpoch(uint256) external pure override {}

    function totalStakeTime(uint256 epochId) external view override returns (uint256) {
        return _totalStakeTime[epochId];
    }

    function stakeTimeOf(address user, uint256 epochId) external view override returns (uint256) {
        return _userStakeTime[epochId][user];
    }
}
