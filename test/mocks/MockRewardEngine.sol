// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../contracts/interfaces/IRewardEngine.sol";

/// @dev Mock RewardEngine for factory tests. Records vault registrations.
contract MockRewardEngine is IRewardEngine {
    mapping(address => uint256) public registeredInitialCumS;
    address[] public registeredVaults;

    function registerVault(address vault, uint256 initialCumS_) external override {
        registeredInitialCumS[vault] = initialCumS_;
        registeredVaults.push(vault);
    }

    /// @dev No-op implementation for tests; real finalization is not needed in factory unit tests.
    function autoFinalizeEpochs() external override {
        // no-op in mock
    }

    function getRegisteredVaultCount() external view returns (uint256) {
        return registeredVaults.length;
    }
}
