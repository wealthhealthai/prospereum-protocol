// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IPartnerVaultFactory.sol";
import "./PartnerVault.sol";

/**
 * @title PartnerVaultFactory
 * @notice Deploys one PartnerVault per partner address using EIP-1167 minimal proxies.
 *         The vault address is the partner's permanent on-chain identity.
 *
 * @dev Dev Spec v2.3, Section 2.2
 *      - partnerAddress -> vaultAddress mapping (one vault per address)
 *      - vaultAddress -> partnerAddress reverse mapping
 *      - EIP-1167 clones: ~10x cheaper deployment than full contracts
 *      - Admin can set a MAX_PARTNERS cap to bound finalizeEpoch gas
 */
contract PartnerVaultFactory is Ownable2Step, ReentrancyGuard, IPartnerVaultFactory {
    using Clones for address;

    // ─────────────────────────────────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Implementation contract that all clones delegate to.
    address public immutable vaultImplementation;

    /// @notice PSRE token address (passed to each vault at init).
    address public immutable psre;

    /// @notice Uniswap v3 SwapRouter on Base.
    address public immutable router;

    /// @notice Input token for swaps (e.g., USDC on Base).
    address public immutable inputToken;

    /// @notice RewardEngine address (set after RewardEngine deployment).
    address public rewardEngine;

    /// @notice partnerAddress => vaultAddress
    mapping(address => address) public vaultOf;

    /// @notice vaultAddress => partnerAddress
    mapping(address => address) public partnerOf;

    /// @notice Ordered list of all registered vault addresses (for RewardEngine iteration).
    address[] public allVaults;

    /// @notice Maximum number of registered partners (bounds finalizeEpoch gas).
    uint256 public maxPartners = 200;

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    event VaultCreated(address indexed partner, address indexed vault);
    event RewardEngineSet(address indexed rewardEngine);
    event MaxPartnersUpdated(uint256 oldMax, uint256 newMax);

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @param _vaultImplementation Deployed PartnerVault implementation contract.
     * @param _psre                PSRE token address.
     * @param _router              Uniswap v3 SwapRouter address on Base.
     * @param _inputToken          Input token for buys (USDC on Base).
     * @param _admin               Admin address (Gnosis Safe multisig).
     */
    constructor(
        address _vaultImplementation,
        address _psre,
        address _router,
        address _inputToken,
        address _admin
    ) Ownable(_admin) {
        require(_vaultImplementation != address(0), "Factory: zero impl");
        require(_psre       != address(0), "Factory: zero psre");
        require(_router     != address(0), "Factory: zero router");
        require(_inputToken != address(0), "Factory: zero inputToken");

        vaultImplementation = _vaultImplementation;
        psre                = _psre;
        router              = _router;
        inputToken          = _inputToken;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Admin
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Set the RewardEngine address. Called once after RewardEngine deployment.
     * @param _rewardEngine Deployed RewardEngine contract address.
     */
    function setRewardEngine(address _rewardEngine) external onlyOwner {
        require(_rewardEngine  != address(0), "Factory: zero rewardEngine");
        require(rewardEngine   == address(0), "Factory: already set");
        rewardEngine = _rewardEngine;
        emit RewardEngineSet(_rewardEngine);
    }

    /**
     * @notice Update the maximum number of registered partners.
     *         Keeps finalizeEpoch gas bounded.
     */
    function setMaxPartners(uint256 _max) external onlyOwner {
        require(_max > 0, "Factory: zero max");
        emit MaxPartnersUpdated(maxPartners, _max);
        maxPartners = _max;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Vault creation
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Create a PartnerVault for the calling address.
     *         Each address can only create one vault.
     *
     * @return vault Address of the newly deployed PartnerVault clone.
     *
     * @dev RewardEngine must be set before vault creation so vaults are
     *      immediately registered and eligible for reward accounting.
     */
    function createVault() external nonReentrant returns (address vault) {
        require(rewardEngine != address(0), "Factory: rewardEngine not set");
        require(vaultOf[msg.sender] == address(0), "Factory: vault already exists");
        require(allVaults.length < maxPartners, "Factory: max partners reached");

        // Deploy EIP-1167 minimal proxy clone
        vault = vaultImplementation.clone();

        // Initialize the clone
        PartnerVault(vault).initialize(
            msg.sender,
            psre,
            router,
            inputToken,
            rewardEngine
        );

        // Record mappings
        vaultOf[msg.sender] = vault;
        partnerOf[vault]    = msg.sender;
        allVaults.push(vault);

        emit VaultCreated(msg.sender, vault);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // View helpers
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Returns the total number of registered partner vaults.
    function vaultCount() external view returns (uint256) {
        return allVaults.length;
    }

    /// @notice Returns all registered vault addresses.
    ///         Used by RewardEngine during epoch finalization.
    function getAllVaults() external view returns (address[] memory) {
        return allVaults;
    }
}
