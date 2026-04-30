// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IPartnerVaultFactory.sol";
import "../interfaces/IPartnerVault.sol";
import "../interfaces/IRewardEngine.sol";
import "./PartnerVault.sol";
import "./CustomerVault.sol";

// IFactorySwapRouter removed — factory no longer handles DEX swaps.
// Partners acquire PSRE via any channel and call createVault(psreAmountIn) directly.

/**
 * @title PartnerVaultFactory v3.2
 * @notice Deploys PartnerVaults and CustomerVaults using EIP-1167 minimal proxy clones.
 *         The vault address is the partner's permanent on-chain identity.
 *
 * @dev Dev Spec v3.2, Section 2.2
 *
 *      v3.2 changes from v2.3:
 *      - S_MIN = 500e6 (500 USDC, 6 decimals): vault creation requires usdcAmountIn >= S_MIN
 *      - Initial buy executed by factory at vault creation; partner pre-approves USDC
 *      - No vault bond — initial buy IS the entry cost
 *      - deployCustomerVault() deploys CustomerVault clones linked to a PartnerVault
 *      - Calls rewardEngine.registerVault() to set initialCumS baseline in RewardEngine
 *      - isRegisteredVault() and isRegisteredCustomerVault() for cross-contract validation
 */
contract PartnerVaultFactory is Ownable2Step, ReentrancyGuard, IPartnerVaultFactory {
    using Clones for address;
    using SafeERC20 for IERC20;

    // ─────────────────────────────────────────────────────────────────────────
    // Constants
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Minimum initial PSRE deposit for vault creation.
    ///         At $0.10 launch price, 5000 PSRE ≈ $500. Governance-adjustable via setPsreMin().
    ///         Denominated in PSRE (18 decimals). No oracle required.
    uint256 public psreMin = 5_000e18;

    // ─────────────────────────────────────────────────────────────────────────
    // Immutables
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice PartnerVault implementation contract that all clones delegate to.
    address public immutable vaultImplementation;

    /// @notice CustomerVault implementation contract that all clones delegate to.
    address public immutable customerVaultImplementation;

    /// @notice PSRE token address.
    address public immutable psre;

    // router and inputToken removed — factory no longer handles DEX swaps.

    // ─────────────────────────────────────────────────────────────────────────
    // Mutable state
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice RewardEngine address (set after RewardEngine deployment).
    address public rewardEngine;

    /// @notice Maximum number of registered partners (bounds finalizeEpoch gas).
    uint256 public maxPartners = 200;

    // Fix #12: track decommissioned vaults so they can be skipped in finalization.
    /// @notice True if the vault was created by this factory and has NOT been decommissioned.
    mapping(address => bool) public vaultActive;

    /// @notice Count of non-decommissioned vaults. Used for maxPartners capacity check
    ///         so decommissioned slots can be reclaimed by new partners.
    uint256 public activeVaultCount;

    // allowedFeeTiers removed — no DEX routing in factory.

    // ─────────────────────────────────────────────────────────────────────────
    // Registries
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice partnerAddress => vaultAddress (one vault per partner)
    mapping(address => address) public vaultOf;

    /// @notice vaultAddress => partnerAddress
    mapping(address => address) public partnerOf;

    /// @notice Ordered list of all registered vault addresses (for RewardEngine iteration).
    address[] public allVaults;

    /// @notice customerVaultAddress => parentPartnerVaultAddress
    mapping(address => address) public customerVaultParent;

    /// @notice customerVaultAddress => partnerVaultAddress that the CV was deployed for.
    ///         Set at deployment time so PartnerVault.registerCustomerVault() can validate
    ///         that the CV was actually deployed by this factory for the calling vault.
    ///         Implements IPartnerVaultFactory.isCustomerVaultOf().
    mapping(address => address) public isCustomerVaultOf;

    /// @notice All deployed CustomerVaults (for enumeration).
    address[] public allCustomerVaults;

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    event VaultCreated(address indexed partner, address indexed vault, uint256 initialCumS, uint256 epochId);
    event CustomerVaultDeployed(address indexed partnerVault, address indexed customerVault, address customer);
    event RewardEngineSet(address indexed rewardEngine);
    event MaxPartnersUpdated(uint256 oldMax, uint256 newMax);
    event PsreMinUpdated(uint256 oldMin, uint256 newMin);
    /// @notice Emitted when a vault is decommissioned. Fix #12.
    event VaultDecommissioned(address indexed vault);

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @param _vaultImplementation         Deployed PartnerVault implementation.
     * @param _customerVaultImplementation Deployed CustomerVault implementation.
     * @param _psre                        PSRE token address.
     * @param _admin                       Admin address (Gnosis Safe multisig).
     */
    constructor(
        address _vaultImplementation,
        address _customerVaultImplementation,
        address _psre,
        address _admin
    ) Ownable(_admin) {
        require(_vaultImplementation         != address(0), "Factory: zero vaultImpl");
        require(_customerVaultImplementation != address(0), "Factory: zero cvImpl");
        require(_psre                        != address(0), "Factory: zero psre");

        vaultImplementation         = _vaultImplementation;
        customerVaultImplementation = _customerVaultImplementation;
        psre                        = _psre;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Admin
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Update the minimum PSRE required to create a vault.
    ///         At $0.10 launch price, default 5000 PSRE ≈ $500.
    function setPsreMin(uint256 _psreMin) external onlyOwner {
        require(_psreMin > 0, "Factory: zero psreMin");
        psreMin = _psreMin;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Ownership safety
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Permanently disabled — renouncing ownership would lock the protocol
     *         (H-1: pause + renounce = permanent halt).
     *         Transfer ownership to a new multisig instead.
     */
    function renounceOwnership() public override onlyOwner {
        revert("Factory: renounce disabled -- transfer to new owner instead");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Admin
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Set the RewardEngine address. Called once after RewardEngine deployment.
    function setRewardEngine(address _rewardEngine) external onlyOwner {
        require(_rewardEngine != address(0), "Factory: zero rewardEngine");
        require(rewardEngine  == address(0), "Factory: already set");
        rewardEngine = _rewardEngine;
        emit RewardEngineSet(_rewardEngine);
    }

    /// @notice Update the maximum number of registered partners.
    function setMaxPartners(uint256 _max) external onlyOwner {
        require(_max > 0, "Factory: zero max");
        require(_max >= activeVaultCount, "Factory: max below active vault count");
        emit MaxPartnersUpdated(maxPartners, _max);
        maxPartners = _max;
    }

    /// @notice Decommission a PartnerVault from the active partner set.
    ///         Fix #12: marks vault inactive so it is skipped in RewardEngine finalization
    ///         and its slot is freed for a new partner (activeVaultCount check).
    ///         The vault address remains in allVaults[] for historical auditability.
    ///         onlyOwner: decommission is a governance action (owner = multisig).
    ///
    /// @param vault  Address of the PartnerVault to decommission.
    function decommissionVault(address vault) external onlyOwner {
        require(partnerOf[vault] != address(0), "Factory: vault not registered");
        require(vaultActive[vault],             "Factory: vault already decommissioned");
        vaultActive[vault] = false;
        activeVaultCount--;
        emit VaultDecommissioned(vault);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // createVault()
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Create a PartnerVault by depositing PSRE directly.
     *
     *         DEX-agnostic: partners acquire PSRE via any channel (Uniswap v3/v4, Aerodrome,
     *         Coinbase, OTC, existing balance) before calling this function. No router
     *         dependency; no version lock.
     *
     *         Flow:
     *         1. Validate psreAmountIn >= psreMin.
     *         2. Deploy PartnerVault EIP-1167 clone.
     *         3. Pull PSRE from partner → vault.
     *         4. Call vault.factoryInit(psreAmountIn) to set initialCumS baseline.
     *         5. Call rewardEngine.registerVault(vault, psreAmountIn) to register in RE.
     *         6. Record mappings and emit VaultCreated.
     *
     * @param psreAmountIn   Amount of PSRE to deposit as initial vault baseline. Must be >= psreMin.
     *
     * @return vault  Address of the newly deployed PartnerVault clone.
     */
    function createVault(uint256 psreAmountIn) external nonReentrant returns (address vault) {
        require(rewardEngine != address(0),              "Factory: rewardEngine not set");
        require(vaultOf[msg.sender] == address(0),       "Factory: vault already exists");
        // Fix #12: check against activeVaultCount so decommissioned slots can be reused.
        require(activeVaultCount < maxPartners,          "Factory: max partners reached");
        require(psreAmountIn >= psreMin,                 "Factory: below psreMin");

        // Lazy epoch finalization: partner activity drives keeper-less epoch closing
        IRewardEngine(rewardEngine).autoFinalizeEpochs();

        // ── Deploy vault clone ───────────────────────────────────────────────
        vault = vaultImplementation.clone();

        PartnerVault(vault).initialize(
            msg.sender,   // owner = partner
            psre,
            rewardEngine,
            address(this)
        );

        // ── Pull PSRE from partner into vault ────────────────────────────────
        IERC20(psre).safeTransferFrom(msg.sender, vault, psreAmountIn);

        // ── Set initialCumS baseline in vault ───────────────────────────────
        PartnerVault(vault).factoryInit(psreAmountIn);

        // ── Register vault in RewardEngine ──────────────────────────────────
        IRewardEngine(rewardEngine).registerVault(vault, psreAmountIn);

        // ── Record factory mappings ──────────────────────────────────────────
        vaultOf[msg.sender] = vault;
        partnerOf[vault]    = msg.sender;
        allVaults.push(vault);
        // Fix #12: mark vault active and increment active count
        vaultActive[vault] = true;
        activeVaultCount++;

        // Compute epoch ID for the event (informational)
        uint256 epochId = _currentEpochId();

        emit VaultCreated(msg.sender, vault, psreAmountIn, epochId);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // deployCustomerVault()
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Deploy a CustomerVault linked to a given PartnerVault.
     *         The caller must be the owner of the specified PartnerVault.
     *         Gas is paid by the partner (msg.sender).
     *
     * @param partnerVault  Address of the parent PartnerVault.
     * @param customer      Customer wallet address (can be address(0) for platform-managed).
     *
     * @return cv  Address of the newly deployed CustomerVault clone.
     */
    function deployCustomerVault(
        address partnerVault,
        address customer
    ) external nonReentrant returns (address cv) {
        // Fix #8: query vault's current owner directly so that after updateOwner/acceptOwnership
        // the new owner can deploy CVs (partnerOf[vault] would still point to old owner).
        require(IPartnerVault(partnerVault).owner() == msg.sender, "Factory: not vault owner");

        // ── Deploy CustomerVault clone ───────────────────────────────────────
        cv = customerVaultImplementation.clone();

        CustomerVault(cv).initialize(
            partnerVault,
            psre,
            msg.sender, // partnerOwner
            customer    // intendedCustomer — stored on-chain to prevent front-run claims
        );

        // ── Record factory origin BEFORE calling registerCustomerVault ───────
        // PartnerVault.registerCustomerVault() checks isCustomerVaultOf[cv] == partnerVault.
        // Must be set first so the validation passes.
        isCustomerVaultOf[cv]   = partnerVault;
        customerVaultParent[cv] = partnerVault;

        // ── Register CV in parent PartnerVault ──────────────────────────────
        PartnerVault(partnerVault).registerCustomerVault(cv);
        allCustomerVaults.push(cv);

        emit CustomerVaultDeployed(partnerVault, cv, customer);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // IPartnerVaultFactory interface implementations
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Returns true if the given address is a registered PartnerVault.
    function isRegisteredVault(address vault) external view override returns (bool) {
        return partnerOf[vault] != address(0);
    }

    /// @notice Returns true if vault is an active (non-decommissioned) PartnerVault.
    ///         Fix #12: used by RewardEngine._finalizeSingleEpoch() to skip decommissioned vaults.
    function isActiveVault(address vault) external view override returns (bool) {
        return vaultActive[vault];
    }

    /// @notice Returns the parent PartnerVault address if cv is a registered CustomerVault.
    ///         Returns address(0) if not registered.
    function isRegisteredCustomerVault(address cv)
        external view override returns (address parentVault_)
    {
        return customerVaultParent[cv];
    }

    /// @notice Fix #14: returns true if cv is a CustomerVault deployed by this factory.
    ///         Used by PartnerVault.transferOut() to block PSRE from being sent to any
    ///         registered CustomerVault, preventing cross-vault cumS inflation.
    function isRegisteredCV(address cv) external view override returns (bool) {
        return customerVaultParent[cv] != address(0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // View helpers
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Returns the total number of registered PartnerVaults.
    function vaultCount() external view returns (uint256) {
        return allVaults.length;
    }

    /// @notice Returns all registered PartnerVault addresses (for RewardEngine iteration).
    function getAllVaults() external view override returns (address[] memory) {
        return allVaults;
    }

    /// @notice Returns the total number of deployed CustomerVaults.
    function customerVaultCount() external view returns (uint256) {
        return allCustomerVaults.length;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal helpers
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Note: genesis is read from rewardEngine in production; for event emission only.
    function _currentEpochId() internal view returns (uint256) {
        // Cannot call rewardEngine.currentEpochId() here due to circular dependency
        // (factory is deployed before RE). Just use 0 as a placeholder for the event.
        // The epochId in VaultCreated is informational only.
        return 0;
    }
}
