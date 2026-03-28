// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IPartnerVaultFactory.sol";
import "../interfaces/IRewardEngine.sol";
import "./PartnerVault.sol";
import "./CustomerVault.sol";

/// @dev Minimal Uniswap v3 SwapRouter interface (Base mainnet)
interface IFactorySwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24  fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    function exactInputSingle(ExactInputSingleParams calldata params)
        external payable returns (uint256 amountOut);
}

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

    /// @notice Minimum initial buy: 500 USDC (6-decimal USDC, no oracle needed).
    uint256 public constant S_MIN = 500_000_000; // 500e6

    // ─────────────────────────────────────────────────────────────────────────
    // Immutables
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice PartnerVault implementation contract that all clones delegate to.
    address public immutable vaultImplementation;

    /// @notice CustomerVault implementation contract that all clones delegate to.
    address public immutable customerVaultImplementation;

    /// @notice PSRE token address.
    address public immutable psre;

    /// @notice Uniswap v3 SwapRouter on Base.
    address public immutable router;

    /// @notice Input token for swaps (USDC on Base, 6 decimals).
    address public immutable inputToken;

    // ─────────────────────────────────────────────────────────────────────────
    // Mutable state
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice RewardEngine address (set after RewardEngine deployment).
    address public rewardEngine;

    /// @notice Maximum number of registered partners (bounds finalizeEpoch gas).
    uint256 public maxPartners = 200;

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

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @param _vaultImplementation         Deployed PartnerVault implementation.
     * @param _customerVaultImplementation Deployed CustomerVault implementation.
     * @param _psre                        PSRE token address.
     * @param _router                      Uniswap v3 SwapRouter address.
     * @param _inputToken                  Input token (USDC on Base).
     * @param _admin                       Admin address (Gnosis Safe multisig).
     */
    constructor(
        address _vaultImplementation,
        address _customerVaultImplementation,
        address _psre,
        address _router,
        address _inputToken,
        address _admin
    ) Ownable(_admin) {
        require(_vaultImplementation         != address(0), "Factory: zero vaultImpl");
        require(_customerVaultImplementation != address(0), "Factory: zero cvImpl");
        require(_psre                        != address(0), "Factory: zero psre");
        require(_router                      != address(0), "Factory: zero router");
        require(_inputToken                  != address(0), "Factory: zero inputToken");

        vaultImplementation         = _vaultImplementation;
        customerVaultImplementation = _customerVaultImplementation;
        psre                        = _psre;
        router                      = _router;
        inputToken                  = _inputToken;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Admin
    // ─────────────────────────────────────────────────────────────────────────

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
        emit MaxPartnersUpdated(maxPartners, _max);
        maxPartners = _max;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // createVault()
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Create a PartnerVault for the calling address and execute the initial buy.
     *
     *         Flow:
     *         1. Validate usdcAmountIn >= S_MIN ($500 USDC, no oracle needed).
     *         2. Deploy PartnerVault EIP-1167 clone.
     *         3. Pull USDC from partner.
     *         4. Swap USDC → PSRE via router (recipient = new vault).
     *         5. Call vault.factoryInit(psreOut) to set initialCumS baseline.
     *         6. Call rewardEngine.registerVault(vault, psreOut) to register in RE.
     *         7. Record mappings and emit VaultCreated.
     *
     * @param usdcAmountIn   Amount of USDC to spend on the initial buy. Must be >= S_MIN.
     * @param minPsreOut     Minimum PSRE to receive (slippage protection; must be > 0).
     * @param deadline       Swap deadline.
     * @param fee            Uniswap v3 pool fee tier (e.g. 3000 = 0.3%).
     *
     * @return vault  Address of the newly deployed PartnerVault clone.
     */
    function createVault(
        uint256 usdcAmountIn,
        uint256 minPsreOut,
        uint256 deadline,
        uint24  fee
    ) external nonReentrant returns (address vault) {
        require(rewardEngine != address(0),              "Factory: rewardEngine not set");
        require(vaultOf[msg.sender] == address(0),       "Factory: vault already exists");
        require(allVaults.length < maxPartners,          "Factory: max partners reached");
        require(usdcAmountIn >= S_MIN,                   "Factory: below S_MIN ($500 USDC)");
        require(minPsreOut > 0,                          "Factory: slippage protection required");
        require(deadline >= block.timestamp,             "Factory: expired deadline");

        // ── Deploy vault clone ───────────────────────────────────────────────
        vault = vaultImplementation.clone();

        PartnerVault(vault).initialize(
            msg.sender,   // owner = partner
            psre,
            router,
            inputToken,
            rewardEngine,
            address(this)
        );

        // ── Execute initial buy (factory pulls USDC, swap → PSRE → vault) ───
        IERC20(inputToken).safeTransferFrom(msg.sender, address(this), usdcAmountIn);
        IERC20(inputToken).forceApprove(router, usdcAmountIn);

        uint256 psreBefore = IERC20(psre).balanceOf(vault);

        IFactorySwapRouter(router).exactInputSingle(
            IFactorySwapRouter.ExactInputSingleParams({
                tokenIn:           inputToken,
                tokenOut:          psre,
                fee:               fee,
                recipient:         vault,
                deadline:          deadline,
                amountIn:          usdcAmountIn,
                amountOutMinimum:  minPsreOut,
                sqrtPriceLimitX96: 0
            })
        );

        uint256 psreAfter = IERC20(psre).balanceOf(vault);
        uint256 psreOut   = psreAfter - psreBefore;
        require(psreOut > 0, "Factory: zero psreOut from initial buy");

        // ── Set initialCumS baseline in vault ───────────────────────────────
        PartnerVault(vault).factoryInit(psreOut);

        // ── Register vault in RewardEngine ──────────────────────────────────
        IRewardEngine(rewardEngine).registerVault(vault, psreOut);

        // ── Record factory mappings ──────────────────────────────────────────
        vaultOf[msg.sender] = vault;
        partnerOf[vault]    = msg.sender;
        allVaults.push(vault);

        // Compute epoch ID for the event (informational)
        uint256 epochId = _currentEpochId();

        emit VaultCreated(msg.sender, vault, psreOut, epochId);
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
        require(partnerOf[partnerVault] == msg.sender, "Factory: not vault owner");

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

    /// @notice Returns the parent PartnerVault address if cv is a registered CustomerVault.
    ///         Returns address(0) if not registered.
    function isRegisteredCustomerVault(address cv)
        external view override returns (address parentVault_)
    {
        return customerVaultParent[cv];
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
