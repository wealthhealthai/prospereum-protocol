// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IPartnerVaultFactory
 * @notice Interface for PartnerVaultFactory as consumed by RewardEngine.
 * @dev Extracted from RewardEngine.sol inline definition — pre-audit hygiene fix.
 */
interface IPartnerVaultFactory {
    function getAllVaults() external view returns (address[] memory);
}
