// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ICustomerVault
 * @notice Interface for CustomerVault as consumed by PartnerVault.
 * @dev Added as part of fix #10 (reclaimUnclaimed permanently unreachable):
 *      PartnerVault.reclaimFromCV() calls reclaimUnclaimed(amount) on the CV.
 *      onlyParent in CustomerVault ensures msg.sender == parentVault (this contract).
 */
interface ICustomerVault {
    /// @notice Partner reclaims PSRE from an unclaimed CustomerVault back to parentVault.
    ///         Only callable while customerClaimed == false.
    ///         PSRE returns to parentVault; ecosystemBalance is unchanged (stays in ecosystem).
    function reclaimUnclaimed(uint256 amount) external;
}
