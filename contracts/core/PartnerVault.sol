// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IPartnerVault.sol";
import "../interfaces/IPartnerVaultFactory.sol";
import "../interfaces/IRewardEngine.sol";
import "../interfaces/ICustomerVault.sol";

/// @dev Minimal Uniswap v3 SwapRouter interface (Base mainnet)
interface ISwapRouter {
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
 * @title PartnerVault v3.2
 * @notice Accounting boundary for the partner's PSRE ecosystem.
 *         Tracks S_eco (ecosystem balance) and cumS (high-water-mark ratchet).
 *         Deployed via EIP-1167 minimal proxy clone by PartnerVaultFactory.
 *
 * @dev Dev Spec v3.2, Sections 2.3 and 5.1
 *
 *      Key v3.2 changes from v2.3:
 *      - cumBuy replaced by cumS (high-water-mark ratchet of ecosystem balance)
 *      - ecosystemBalance = running counter of total PSRE in vault + all registered CVs
 *      - CustomerVault support: distribute(), reportLeakage(), registerCustomerVault()
 *      - snapshotEpoch() for RewardEngine (replaces direct cumBuy read)
 *      - Initial buy sets baseline initialCumS; first reward requires cumS > initialCumS
 *      - No sell() function — sell via DEX is disabled
 */
contract PartnerVault is ReentrancyGuard, IPartnerVault {
    using SafeERC20 for IERC20;

    // ─────────────────────────────────────────────────────────────────────────
    // State — Identity
    // ─────────────────────────────────────────────────────────────────────────

    address public owner;
    address public pendingOwner;
    address public psre;
    address public router;
    address public inputToken;
    address public rewardEngine;
    address public factory;

    bool private _initialized;

    // ─────────────────────────────────────────────────────────────────────────
    // State — Ecosystem accounting (v3.2)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Running counter: total PSRE in the ecosystem (this vault + all registered CVs).
    ///         Updated on every balance-changing event.
    uint256 public ecosystemBalance;

    /// @notice High-water-mark of ecosystemBalance. Monotonically non-decreasing (ratchet).
    uint256 public cumS;

    /// @notice S_p(N): initial buy amount at vault creation. First reward requires cumS > initialCumS.
    uint256 public initialCumS;

    /// @notice True once cumS has grown past initialCumS. Set by RewardEngine at first qualification.
    bool public qualified;

    /// @notice cumS snapshotted at the last epoch finalization (used by RewardEngine for deltaCumS).
    uint256 public lastEpochCumS;

    // ─────────────────────────────────────────────────────────────────────────
    // State — CustomerVault registry
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Maximum number of CustomerVaults per PartnerVault (gas bound for _updateCumS).
    uint256 public constant MAX_CUSTOMER_VAULTS = 1000;

    mapping(address => bool) public registeredCustomerVaults;
    address[] public customerVaultList;

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    event PartnerBought(address indexed vault, uint256 amountIn, uint256 psreOut,
                        uint256 ecosystemBalance, uint256 cumS);
    event DistributedToCustomer(address indexed vault, address indexed customerVault, uint256 amount);
    event PSREExitedEcosystem(address indexed vault, address indexed to, uint256 amount,
                              uint256 ecosystemBalance, uint256 cumS);
    event PSRELeaked(address indexed vault, uint256 amount, uint256 ecosystemBalance, uint256 cumS);
    event CustomerVaultRegistered(address indexed parentVault, address indexed customerVault);
    event OwnershipTransferStarted(address indexed currentOwner, address indexed pendingOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // ─────────────────────────────────────────────────────────────────────────
    // Modifiers
    // ─────────────────────────────────────────────────────────────────────────

    modifier onlyOwner() {
        require(msg.sender == owner, "PartnerVault: not owner");
        _;
    }

    modifier onlyRewardEngine() {
        require(msg.sender == rewardEngine, "PartnerVault: only rewardEngine");
        _;
    }

    modifier onlyFactory() {
        require(msg.sender == factory, "PartnerVault: only factory");
        _;
    }

    modifier onlyRegisteredCV() {
        require(registeredCustomerVaults[msg.sender], "PartnerVault: caller not registered CV");
        _;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Initializer
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Initialize the vault (called by factory immediately after clone deployment).
     *         After this, the factory calls factoryInit() to set the initial buy baseline.
     */
    function initialize(
        address _owner,
        address _psre,
        address _router,
        address _inputToken,
        address _rewardEngine,
        address _factory
    ) external {
        require(!_initialized,             "PartnerVault: already initialized");
        require(_owner        != address(0), "PartnerVault: zero owner");
        require(_psre         != address(0), "PartnerVault: zero psre");
        require(_router       != address(0), "PartnerVault: zero router");
        require(_inputToken   != address(0), "PartnerVault: zero inputToken");
        require(_rewardEngine != address(0), "PartnerVault: zero rewardEngine");
        require(_factory      != address(0), "PartnerVault: zero factory");

        _initialized  = true;
        owner         = _owner;
        psre          = _psre;
        router        = _router;
        inputToken    = _inputToken;
        rewardEngine  = _rewardEngine;
        factory       = _factory;
    }

    /**
     * @notice Set the initial cumS baseline after the factory executes the initial buy.
     *         Called by factory only once (guarded by initialCumS == 0).
     *         Per spec §2.2: initial buy sets baseline; first reward requires cumS > initialCumS.
     *
     * @param psreOut  Amount of PSRE from initial buy (already transferred to this vault).
     */
    function factoryInit(uint256 psreOut) external onlyFactory {
        require(initialCumS == 0, "PartnerVault: already init'd with buy");
        require(psreOut > 0,      "PartnerVault: zero initial buy");

        ecosystemBalance = psreOut;
        cumS             = psreOut;
        initialCumS      = psreOut;
        lastEpochCumS    = psreOut;
        qualified        = false;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // buy() — Execute PSRE purchase via DEX router
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Swap inputToken → PSRE and record the buy.
     *         Updates ecosystemBalance and cumS ratchet.
     *
     * @param amountIn      Amount of inputToken to spend.
     * @param minAmountOut  Minimum PSRE to receive (slippage protection; must be > 0).
     * @param deadline      Unix timestamp after which swap reverts.
     * @param fee           Uniswap v3 pool fee tier (e.g. 3000 = 0.3%).
     */
    function buy(
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 deadline,
        uint24  fee
    ) external onlyOwner nonReentrant returns (uint256 psreOut) {
        require(amountIn     > 0,                "PartnerVault: zero amountIn");
        require(minAmountOut > 0,                "PartnerVault: slippage protection required");
        require(deadline >= block.timestamp,     "PartnerVault: expired deadline");

        // Lazy epoch finalization
        IRewardEngine(rewardEngine).autoFinalizeEpochs();

        IERC20(inputToken).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(inputToken).forceApprove(router, amountIn);

        uint256 psreBefore = IERC20(psre).balanceOf(address(this));

        ISwapRouter(router).exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn:           inputToken,
                tokenOut:          psre,
                fee:               fee,
                recipient:         address(this),
                deadline:          deadline,
                amountIn:          amountIn,
                amountOutMinimum:  minAmountOut,
                sqrtPriceLimitX96: 0
            })
        );

        uint256 psreAfter = IERC20(psre).balanceOf(address(this));
        psreOut = psreAfter - psreBefore;
        require(psreOut > 0, "PartnerVault: zero psreOut");

        ecosystemBalance += psreOut;
        _updateCumS();

        emit PartnerBought(address(this), amountIn, psreOut, ecosystemBalance, cumS);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // distributeToCustomer() — Move PSRE to a registered CustomerVault
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Transfer PSRE from this vault to a registered CustomerVault.
     *         ecosystemBalance is unchanged — PSRE stays within the ecosystem boundary.
     *         cumS is unchanged (distributeToCustomer does not increase or decrease S_eco).
     */
    function distributeToCustomer(address customerVault, uint256 amount)
        external onlyOwner nonReentrant
    {
        require(registeredCustomerVaults[customerVault], "PartnerVault: CV not registered");
        require(amount > 0,                              "PartnerVault: zero amount");
        require(
            IERC20(psre).balanceOf(address(this)) >= amount,
            "PartnerVault: insufficient vault balance"
        );

        // ecosystemBalance unchanged — PSRE moves within the ecosystem
        IERC20(psre).safeTransfer(customerVault, amount);

        emit DistributedToCustomer(address(this), customerVault, amount);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // reclaimFromCV() — Reclaim PSRE from an abandoned CustomerVault (Fix #10)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Reclaim unclaimed PSRE from an abandoned CustomerVault back into this vault.
     *         Calls CustomerVault.reclaimUnclaimed(amount) which requires msg.sender == parentVault
     *         (i.e., address(this)). This function fixes the permanently-unreachable path where
     *         funds distributed to a CV with no customer claim were locked forever.
     *
     * @dev    PSRE stays within the ecosystem boundary — ecosystemBalance is unchanged.
     *         Only callable while the CV's customer has NOT yet claimed ownership.
     *         Note: the audit spec assumed reclaimUnclaimed() takes no args; the actual
     *         CustomerVault implementation requires an explicit amount for caller precision.
     *
     * @param customerVault  Address of the registered CustomerVault to reclaim from.
     * @param amount         Amount of PSRE to reclaim (must be <= CV's PSRE balance).
     */
    function reclaimFromCV(address customerVault, uint256 amount)
        external onlyOwner nonReentrant
    {
        require(registeredCustomerVaults[customerVault], "PartnerVault: CV not registered");
        ICustomerVault(customerVault).reclaimUnclaimed(amount);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // transferOut() — Send PSRE to an unregistered address (exits ecosystem)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Transfer PSRE to an address outside the ecosystem.
     *         Reduces ecosystemBalance. cumS ratchet holds at prior high.
     *         The partner must rebuy past their historical peak cumS to earn reward again.
     *
     * @dev Reverts if `to` is a registered CustomerVault or partner vault — use
     *      distributeToCustomer() for registered CVs.
     */
    function transferOut(address to, uint256 amount) external onlyOwner nonReentrant {
        require(to != address(0),                                   "PartnerVault: zero recipient");
        require(!registeredCustomerVaults[to],                      "PartnerVault: use distributeToCustomer for CVs");
        require(
            IPartnerVaultFactory(factory).isRegisteredVault(to) == false,
            "PartnerVault: cannot transferOut to registered vault"
        );
        // Fix #14: also block CVs registered under any vault (not just this one).
        // Without this check, an attacker could transferOut to a CV registered under a
        // different vault, inflating that vault's ecosystemBalance and cumS for free.
        require(
            !IPartnerVaultFactory(factory).isRegisteredCV(to),
            "PartnerVault: cannot transferOut to customer vault"
        );
        require(amount > 0, "PartnerVault: zero amount");
        require(ecosystemBalance >= amount, "PartnerVault: exceeds ecosystemBalance");

        ecosystemBalance -= amount;
        // cumS is NOT changed — ratchet holds at prior high-water-mark

        IERC20(psre).safeTransfer(to, amount);

        emit PSREExitedEcosystem(address(this), to, amount, ecosystemBalance, cumS);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // reportLeakage() — Called by registered CustomerVault on customer withdrawal
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Reduce ecosystemBalance when a customer withdraws from their CustomerVault.
     *         Called only by registered CustomerVaults.
     *         cumS ratchet holds at prior high.
     */
    function reportLeakage(uint256 amount) external override onlyRegisteredCV nonReentrant {
        require(amount > 0, "PartnerVault: zero leakage amount");

        if (ecosystemBalance >= amount) {
            ecosystemBalance -= amount;
        } else {
            ecosystemBalance = 0;
        }
        // cumS unchanged — ratchet holds

        emit PSRELeaked(address(this), amount, ecosystemBalance, cumS);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // registerCustomerVault() — Link a CustomerVault to this PartnerVault
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Register a CustomerVault as part of this vault's ecosystem.
     *         PSRE in registered CustomerVaults counts toward S_eco.
     *         Callable by the vault owner OR the factory (factory deploys and registers in one tx).
     *
     *         Security: only addresses that the factory deployed as CustomerVaults for THIS vault
     *         may be registered. Prevents arbitrary wallet registration (e.g. Uniswap pools)
     *         from inflating cumS. (Dev Spec v3.2, MAJOR-1)
     *
     *         Cap: at most MAX_CUSTOMER_VAULTS per vault (bounds _updateCumS gas). (MAJOR-2)
     *
     * @param customerVault Address of the CustomerVault to register.
     */
    function registerCustomerVault(address customerVault) external {
        require(msg.sender == owner || msg.sender == factory, "PartnerVault: not owner");
        require(customerVault != address(0),              "PartnerVault: zero CV address");
        require(!registeredCustomerVaults[customerVault], "PartnerVault: CV already registered");
        require(customerVaultList.length < MAX_CUSTOMER_VAULTS, "PartnerVault: max CVs reached");

        // Validate that this CV was deployed by the factory specifically for this vault.
        // Prevents anyone from registering arbitrary external addresses to inflate cumS.
        require(
            IPartnerVaultFactory(factory).isCustomerVaultOf(customerVault) == address(this),
            "PartnerVault: CV not deployed by factory for this vault"
        );

        registeredCustomerVaults[customerVault] = true;
        customerVaultList.push(customerVault);

        emit CustomerVaultRegistered(address(this), customerVault);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // snapshotEpoch() — Called by RewardEngine at epoch finalization
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Snapshot cumS for this epoch. Called only by RewardEngine.
     *         Runs _updateCumS() to capture any direct ERC-20 transfers not yet reflected.
     *         Returns deltaCumS = cumS - lastEpochCumS, then commits lastEpochCumS = cumS.
     */
    function snapshotEpoch()
        external override onlyRewardEngine
        returns (uint256 deltaCumS)
    {
        _updateCumS(); // capture any mid-epoch direct ERC-20 transfers

        deltaCumS     = cumS > lastEpochCumS ? cumS - lastEpochCumS : 0;
        lastEpochCumS = cumS;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // _updateCumS() — Internal: update cumS ratchet
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @dev Scans all registered CustomerVault balances to compute total ecosystem balance.
     *      Updates ecosystemBalance if the live scan reveals direct ERC-20 transfers
     *      not tracked by the running counter. Then advances cumS ratchet.
     *
     *      Per spec §5.1: cumS is monotonically non-decreasing. This function may only
     *      increase cumS, never decrease it.
     *
     *      Gas note: O(|customerVaultList|). Capped by maxPartners at the factory level.
     */
    function _updateCumS() internal {
        // Compute actual total ecosystem balance from on-chain balances
        uint256 ownBalance = IERC20(psre).balanceOf(address(this));
        uint256 totalEcosystem = ownBalance;
        uint256 n = customerVaultList.length;
        for (uint256 i = 0; i < n; i++) {
            totalEcosystem += IERC20(psre).balanceOf(customerVaultList[i]);
        }

        // Update ecosystemBalance if live scan reveals direct transfers not captured
        // by the running counter (e.g., customer sends PSRE directly to vault address)
        if (totalEcosystem > ecosystemBalance) {
            ecosystemBalance = totalEcosystem;
        }

        // Advance cumS ratchet — only ever increases
        if (ecosystemBalance > cumS) {
            cumS = ecosystemBalance;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Ownership (two-step)
    // ─────────────────────────────────────────────────────────────────────────

    function updateOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "PartnerVault: zero newOwner");
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "PartnerVault: not pending owner");
        address previous = owner;
        owner        = pendingOwner;
        pendingOwner = address(0);
        emit OwnershipTransferred(previous, owner);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // View helpers
    // ─────────────────────────────────────────────────────────────────────────

    function getCumS()            external view override returns (uint256) { return cumS; }
    function getInitialCumS()     external view override returns (uint256) { return initialCumS; }

    /// @notice Fix #21: delegate to RewardEngine for the authoritative qualification status.
    ///         The `qualified` storage variable is kept for internal compatibility but
    ///         external callers should always see the RE-tracked value.
    ///         (The `qualified` storage var is set to false in factoryInit and never updated
    ///         by PartnerVault itself — RE is the source of truth.)
    function isQualified() external view override returns (bool) {
        return IRewardEngine(rewardEngine).qualified(address(this));
    }

    function getCustomerVaultCount() external view returns (uint256) { return customerVaultList.length; }

    function psreBalance() external view returns (uint256) {
        return IERC20(psre).balanceOf(address(this));
    }
}
