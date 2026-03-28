// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IPartnerVault.sol";

/**
 * @title CustomerVault v3.2
 * @notice Lightweight on-chain escrow for a single customer's PSRE rewards.
 *         Linked to exactly one parent PartnerVault.
 *         Deployed by PartnerVaultFactory as an EIP-1167 minimal proxy clone.
 *         Customers do not need to interact with the blockchain — the partner's
 *         backend manages all deposits.
 *
 * @dev Dev Spec v3.2, Section 2.3a
 *
 *      Key properties:
 *      - PSRE held here counts toward parent's S_eco (via parent's balanceOf scan).
 *      - Customer claims ownership by asserting their wallet address.
 *      - Customer withdrawals reduce parent's ecosystemBalance via reportLeakage().
 *      - Partner can reclaim PSRE from unclaimed vault (e.g., account created in error).
 *      - No gas required from customer until they claim ownership.
 *
 *      Deployment gas is paid by the partner (the partnerOwner of the parent PartnerVault).
 */
contract CustomerVault is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─────────────────────────────────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice PSRE token address.
    address public psre;

    /// @notice The PartnerVault that registered and owns this CustomerVault.
    address public parentVault;

    /// @notice The partner who deployed this vault (controls until customer claims).
    address public partnerOwner;

    /// @notice Customer wallet address. address(0) until claimVault() is called.
    address public customer;

    /// @notice True once customer has claimed ownership via claimVault().
    bool public customerClaimed;

    bool private _cvInitialized;

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    event CustomerVaultClaimed(address indexed customerVault, address indexed customerWallet);
    event CustomerWithdraw(address indexed customerVault, address indexed customer, uint256 amount);
    event CustomerVaultReclaimed(address indexed customerVault, address indexed parentVault, uint256 amount);

    // ─────────────────────────────────────────────────────────────────────────
    // Modifiers
    // ─────────────────────────────────────────────────────────────────────────

    modifier onlyParent() {
        require(msg.sender == parentVault, "CustomerVault: only parentVault");
        _;
    }

    modifier onlyCustomer() {
        require(customerClaimed && msg.sender == customer, "CustomerVault: only customer");
        _;
    }

    modifier onlyPartnerOrCustomer() {
        require(
            msg.sender == partnerOwner || (customerClaimed && msg.sender == customer),
            "CustomerVault: not authorized"
        );
        _;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Initializer (called by factory on clone deployment)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Initialize the CustomerVault.
     *         Called by PartnerVaultFactory immediately after clone deployment.
     *
     * @param _parentVault   Address of the parent PartnerVault.
     * @param _psre          Address of the PSRE token.
     * @param _partnerOwner  Address of the partner who controls this vault.
     */
    function initialize(
        address _parentVault,
        address _psre,
        address _partnerOwner
    ) external {
        require(!_cvInitialized,             "CustomerVault: already initialized");
        require(_parentVault  != address(0), "CustomerVault: zero parentVault");
        require(_psre         != address(0), "CustomerVault: zero psre");
        require(_partnerOwner != address(0), "CustomerVault: zero partnerOwner");

        _cvInitialized = true;
        parentVault    = _parentVault;
        psre           = _psre;
        partnerOwner   = _partnerOwner;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // claimVault() — Customer asserts ownership of this vault
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Customer asserts their wallet address to claim ownership of this vault.
     *         Can only be called once, before any prior claim.
     *         After claiming, only the customer can withdraw.
     *
     * @param customerWallet The wallet address asserting ownership.
     */
    function claimVault(address customerWallet) external {
        require(!customerClaimed,            "CustomerVault: already claimed");
        require(customerWallet != address(0), "CustomerVault: zero wallet");
        require(msg.sender == customerWallet, "CustomerVault: must be called by claimant");

        customer        = customerWallet;
        customerClaimed = true;

        emit CustomerVaultClaimed(address(this), customerWallet);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // withdraw() — Customer withdraws PSRE to their wallet
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Customer withdraws PSRE from this vault to their wallet.
     *         Reduces parent's ecosystemBalance via reportLeakage() — the PSRE
     *         exits the partner ecosystem.
     *
     * @dev PSRE transfer happens first, then leakage is reported.
     *      If reportLeakage reverts (e.g., parent is somehow broken), withdrawal reverts.
     */
    function withdraw(uint256 amount) external onlyCustomer nonReentrant {
        require(amount > 0, "CustomerVault: zero amount");
        require(
            IERC20(psre).balanceOf(address(this)) >= amount,
            "CustomerVault: insufficient balance"
        );

        IERC20(psre).safeTransfer(customer, amount);
        IPartnerVault(parentVault).reportLeakage(amount);

        emit CustomerWithdraw(address(this), customer, amount);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // reclaimUnclaimed() — Partner reclaims PSRE from an unclaimed vault
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Partner reclaims PSRE from this vault.
     *         Only callable while customer has NOT yet claimed ownership.
     *         PSRE returns to parentVault — ecosystemBalance is unchanged
     *         (PSRE stays within the ecosystem boundary).
     */
    function reclaimUnclaimed(uint256 amount) external onlyParent nonReentrant {
        require(!customerClaimed, "CustomerVault: customer has claimed; cannot reclaim");
        require(amount > 0,       "CustomerVault: zero amount");
        require(
            IERC20(psre).balanceOf(address(this)) >= amount,
            "CustomerVault: insufficient balance"
        );

        // Transfer back to parentVault — ecosystemBalance in parent is unchanged
        IERC20(psre).safeTransfer(parentVault, amount);

        emit CustomerVaultReclaimed(address(this), parentVault, amount);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // View helpers
    // ─────────────────────────────────────────────────────────────────────────

    function psreBalance() external view returns (uint256) {
        return IERC20(psre).balanceOf(address(this));
    }
}
