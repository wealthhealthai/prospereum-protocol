// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IPartnerVault
 * @notice Interface for PartnerVault as consumed by RewardEngine.
 * @dev Extracted from RewardEngine.sol inline definition — pre-audit hygiene fix.
 */
interface IPartnerVault {
    function cumBuy() external view returns (uint256);
}
