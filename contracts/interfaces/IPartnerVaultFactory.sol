// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IPartnerVaultFactory
 * @notice Interface for PartnerVaultFactory as consumed by other contracts (v3.2).
 */
interface IPartnerVaultFactory {
    function getAllVaults() external view returns (address[] memory);
    function vaultOf(address partner) external view returns (address);
    function partnerOf(address vault) external view returns (address);
    function isRegisteredVault(address vault) external view returns (bool);
    function isRegisteredCustomerVault(address cv) external view returns (address parentVault);
}
