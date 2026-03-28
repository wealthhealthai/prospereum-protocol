// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../contracts/interfaces/IPartnerVaultFactory.sol";

/// @dev Simple factory stub for PartnerVault unit tests.
contract MockVaultFactory is IPartnerVaultFactory {
    mapping(address => bool) public _isVault;

    function setIsVault(address a, bool v) external {
        _isVault[a] = v;
    }

    function getAllVaults() external pure override returns (address[] memory) {
        address[] memory empty;
        return empty;
    }

    function vaultOf(address) external pure override returns (address) { return address(0); }

    function partnerOf(address) external pure override returns (address) { return address(0); }

    function isRegisteredVault(address vault) external view override returns (bool) {
        return _isVault[vault];
    }

    function isRegisteredCustomerVault(address) external pure override returns (address) {
        return address(0);
    }
}
