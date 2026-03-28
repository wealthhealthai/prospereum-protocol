// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../contracts/interfaces/IPartnerVaultFactory.sol";

/// @dev Mock factory for RewardEngine tests.
///      Allows tests to control the vault list returned to finalizeEpoch.
contract MockFactory is IPartnerVaultFactory {
    address[] private _vaults;
    mapping(address => address) private _partnerOf;
    mapping(address => bool)    private _isVault;
    mapping(address => address) private _cvParent;

    function addVault(address vault, address partner) external {
        _vaults.push(vault);
        _partnerOf[vault] = partner;
        _isVault[vault]   = true;
    }

    /// @dev Called by tests before registerCustomerVault() to simulate factory-deployed CV.
    function setIsCustomerVaultOf(address cv, address parentVault) external {
        _cvParent[cv] = parentVault;
    }

    function getAllVaults() external view override returns (address[] memory) {
        return _vaults;
    }

    function vaultOf(address) external pure override returns (address) {
        return address(0);
    }

    function partnerOf(address vault) external view override returns (address) {
        return _partnerOf[vault];
    }

    function isRegisteredVault(address vault) external view override returns (bool) {
        return _isVault[vault];
    }

    function isRegisteredCustomerVault(address) external pure override returns (address) {
        return address(0);
    }

    function isCustomerVaultOf(address cv) external view override returns (address) {
        return _cvParent[cv];
    }
}
