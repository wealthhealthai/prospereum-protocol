// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/IPSRE.sol";
import "../interfaces/IPausableToken.sol";
import "../interfaces/IPartnerVault.sol";
import "../interfaces/IPartnerVaultFactory.sol";
import "../interfaces/IStakingVault.sol";
import "../interfaces/IRewardEngine.sol";

/**
 * @title RewardEngine v3.2
 * @notice Core monetary policy contract for Prospereum.
 *         Implements "Proof of Prosperity" epoch-based emission with
 *         effectiveCumS deduction to prevent reward compounding.
 *
 * @dev Dev Spec v3.2, Sections 2.5, 3-11
 *
 *      UUPS upgradeable: implementation is deployed once; proxy holds all state.
 *      Use ERC1967Proxy + initialize() for deployment.
 *
 *      Key v3.2 changes from v2.3:
 *      - Reward basis: effectiveCumS = cumS - cumulativeRewardMinted (anti-compounding)
 *      - Tracks ΔeffectiveCumS per epoch (not ΔcumBuy / ΔTWR)
 *      - First qualification: no reward until cumS > initialCumS
 *      - Tier multipliers: Bronze=0.8×, Silver=1.0×, Gold=1.2× (effective: 8%/10%/12%)
 *      - registerVault() called by factory at vault creation
 *      - Immediate reward claim (no vesting ledger)
 *      - No vault bond, no vault expiry, no TWR accumulator
 *
 *      Tier effective rates at alphaBase=0.10e18 (r_base=10%):
 *        Bronze: 0.10 × 0.80 = 8%
 *        Silver: 0.10 × 1.00 = 10%
 *        Gold:   0.10 × 1.20 = 12%
 */
contract RewardEngine is
    UUPSUpgradeable,
    Ownable2StepUpgradeable,
    ReentrancyGuard,
    PausableUpgradeable,
    IRewardEngine
{
    using SafeERC20 for IERC20;

    // ─────────────────────────────────────────────────────────────────────────
    // Constants
    // ─────────────────────────────────────────────────────────────────────────

    uint256 public constant S_EMISSION     = 12_600_000e18;
    uint256 public constant EPOCH_DURATION = 7 days;
    uint256 public constant PRECISION      = 1e18;

    /// @notice Epochs of no cumS growth before a vault is marked inactive.
    uint256 public constant INACTIVE_THRESHOLD = 52;

    /// @notice Maximum epochs auto-finalized per lazy trigger (gas ceiling).
    uint256 public constant AUTO_FINALIZE_MAX_EPOCHS = 10;

    // Governance bounds
    uint256 public constant ALPHA_MIN  = 0.05e18;
    uint256 public constant ALPHA_MAX  = 0.15e18;
    uint256 public constant E0_MIN     = S_EMISSION * 5 / 10000;  // 0.0005 × S_EMISSION
    uint256 public constant E0_MAX     = S_EMISSION * 2 / 1000;   // 0.002  × S_EMISSION
    uint256 public constant SPLIT_MIN  = 0.60e18;
    uint256 public constant SPLIT_MAX  = 0.80e18;
    uint256 public constant PARAM_TIMELOCK = 48 hours;

    // ─────────────────────────────────────────────────────────────────────────
    // State — core protocol references (set in initialize, not immutable)
    // ─────────────────────────────────────────────────────────────────────────

    IPSRE                public psre;
    IPartnerVaultFactory public factory;
    IStakingVault        public stakingVault;
    uint256              public genesisTimestamp;

    // ─────────────────────────────────────────────────────────────────────────
    // Governance parameters (Dev Spec v3.2 §1.3-1.5)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice r_base: base reward rate (10% default per v3.2 spec).
    ///         Named alphaBase for storage consistency with v3.0 layout.
    uint256 public alphaBase;

    /// @notice Weekly scarcity ceiling (default: 12,600 PSRE/week = 0.001 × S_EMISSION).
    uint256 public E0;

    uint256 public constant k     = 2;       // scarcity exponent, immutable
    uint256 public constant theta = 76_923_076_923_076_923; // 1/13 ≈ 0.0769e18

    // Tier thresholds (share of sumR, 1e18-scaled)
    uint256 public silverThreshold;  // 0.5%
    uint256 public goldThreshold;    // 2.0%

    // Tier multipliers (1e18-scaled) — v3.2 corrected values
    uint256 public mBronze;   // 8%  effective at alphaBase=10%
    uint256 public mSilver;   // 10% effective at alphaBase=10%
    uint256 public mGold;     // 12% effective at alphaBase=10%

    uint256 public partnerSplit;  // 70% to partners

    // ─────────────────────────────────────────────────────────────────────────
    // Global emission tracking
    // ─────────────────────────────────────────────────────────────────────────

    uint256 public T;                   // cumulative PSRE minted by this engine
    uint256 public lastFinalizedEpoch;
    bool    public firstEpochFinalized;

    // ─────────────────────────────────────────────────────────────────────────
    // Partner accounting — by vault address (v3.2)
    // ─────────────────────────────────────────────────────────────────────────

    // EMA rolling score on ΔeffectiveCumS (replaces v2.3 creditedNB/cumBuy)
    mapping(address => uint256) public R;
    uint256 public sumR;

    // effectiveCumS tracking
    /// @notice cumS deduction: running total of PSRE ever minted as reward for this vault.
    ///         effectiveCumS = cumS - cumulativeRewardMinted. Prevents reward compounding.
    mapping(address => uint256) public cumulativeRewardMinted;

    /// @notice effectiveCumS at the last epoch finalize. Used to compute ΔeffectiveCumS.
    ///         Initialized to initialCumS[vault] at vault creation.
    mapping(address => uint256) public lastEffectiveCumS;

    // First qualification
    /// @notice True once vault's cumS has grown past its initialCumS baseline.
    ///         Set to true during the first finalizeEpoch where cumS > initialCumS.
    mapping(address => bool) public qualified;

    /// @notice S_p(N): cumS at vault creation = initial buy amount.
    mapping(address => uint256) public initialCumS;

    // Vault activity
    mapping(address => uint256) public lastGrowthEpoch;
    mapping(address => bool)    public vaultActive;

    // Reward claims (pull-based, no vesting)
    mapping(address => uint256) public owedPartner;
    mapping(address => uint256) public totalClaimed;

    // ─────────────────────────────────────────────────────────────────────────
    // Epoch records
    // ─────────────────────────────────────────────────────────────────────────

    mapping(uint256 => bool)    public epochFinalized;
    mapping(uint256 => uint256) public epochBudget;
    mapping(uint256 => uint256) public epochPartnersPool;
    mapping(uint256 => uint256) public epochStakersPool;
    mapping(uint256 => uint256) public epochMinted;
    mapping(uint256 => uint256) public epochDeltaEffectiveCumSTotal;

    // Staker double-claim prevention
    mapping(bytes32 => bool) private _stakeClaimed;

    // ─────────────────────────────────────────────────────────────────────────
    // UUPS upgrade timelock
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Mandatory delay between scheduling and executing a UUPS upgrade.
    ///         Gives users time to exit before a malicious implementation takes effect.
    uint256 public constant UPGRADE_TIMELOCK = 7 days;

    /// @notice Implementation address pending upgrade (zero if no upgrade scheduled).
    address public pendingUpgrade;

    /// @notice Earliest timestamp at which the pending upgrade may be executed.
    uint256 public upgradeTimestamp;

    event UpgradeScheduled(address indexed newImplementation, uint256 executeAfter);
    event UpgradeCancelled(address indexed cancelledImplementation);

    // ─────────────────────────────────────────────────────────────────────────
    // Timelock queue
    // ─────────────────────────────────────────────────────────────────────────

    struct PendingParam { uint256 value; uint256 readyAt; }
    PendingParam public pendingAlphaBase;
    PendingParam public pendingE0;
    PendingParam public pendingPartnerSplit;
    PendingParam public pendingTierParams;

    uint256 public pendingSilverTh;
    uint256 public pendingGoldTh;
    uint256 public pendingMBronze;
    uint256 public pendingMSilver;
    uint256 public pendingMGold;

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    event EpochFinalized(
        uint256 indexed epochId,
        uint256 B, uint256 E_demand, uint256 E_scarcity,
        uint256 B_partners, uint256 B_stakers, uint256 minted,
        uint256 deltaEffectiveCumSTotal
    );
    event PartnerEffectiveCumSSnapshot(
        uint256 indexed epochId, address indexed vault,
        uint256 cumS_, uint256 effectiveCumS, uint256 deltaEffectiveCumS,
        uint256 alpha_p, uint256 weight, uint256 rewardEarned
    );
    event VaultFirstQualified(address indexed vault, uint256 indexed epochId,
                               uint256 cumS_, uint256 initialCumS_);
    event PartnerRewardAccrued(uint256 indexed epochId, address indexed vault, uint256 amount);
    event PartnerRewardClaimed(address indexed vault, uint256 amount);
    event StakeClaimed(uint256 indexed epochId, address indexed user, uint256 stakeTime, uint256 reward);
    event VaultRegistered(address indexed vault, uint256 initialCumS_);
    event VaultMarkedInactive(address indexed vault, uint256 indexed epochId);
    event VaultReactivated(address indexed vault, uint256 indexed epochId);
    event ParamUpdateQueued(string param, uint256 value, uint256 readyAt);
    event ParamUpdated(string param, uint256 oldValue, uint256 newValue);

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor — disables initializers on the implementation contract
    // ─────────────────────────────────────────────────────────────────────────

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // initialize() — called once via proxy at deployment
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Initialize the RewardEngine proxy.
     *         Called exactly once via ERC1967Proxy constructor data.
     *
     * @param _psre             PSRE token address.
     * @param _factory          PartnerVaultFactory address.
     * @param _stakingVault     StakingVault address.
     * @param _genesisTimestamp Protocol genesis Unix timestamp.
     * @param _owner            Initial owner (Gnosis Safe multisig).
     */
    function initialize(
        address _psre,
        address _factory,
        address _stakingVault,
        uint256 _genesisTimestamp,
        address _owner
    ) external initializer {
        require(_psre         != address(0), "RE: zero psre");
        require(_factory      != address(0), "RE: zero factory");
        require(_stakingVault != address(0), "RE: zero stakingVault");
        require(_genesisTimestamp > 0,       "RE: zero genesis");

        __Ownable_init(_owner);
        __Ownable2Step_init();
        __Pausable_init();
        // ReentrancyGuard uses ERC-7201 namespaced storage in OZ v5 — no init needed.

        psre             = IPSRE(_psre);
        factory          = IPartnerVaultFactory(_factory);
        stakingVault     = IStakingVault(_stakingVault);
        genesisTimestamp = _genesisTimestamp;

        // Initialize governance parameters (storage is zero on proxy; must set explicitly)
        alphaBase       = 0.10e18;
        E0              = S_EMISSION / 1000;
        silverThreshold = 0.005e18;
        goldThreshold   = 0.02e18;
        mBronze         = 0.8e18;
        mSilver         = 1.0e18;
        mGold           = 1.2e18;
        partnerSplit    = 0.70e18;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // UUPS upgrade authorization — 7-day timelock
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Schedule a UUPS upgrade. Must be called by the owner at least
     *         UPGRADE_TIMELOCK (7 days) before calling upgradeToAndCall().
     *         Gives users advance notice and time to exit.
     *
     * @param newImplementation The implementation contract to upgrade to.
     */
    function scheduleUpgrade(address newImplementation) external onlyOwner {
        require(newImplementation != address(0), "RE: zero implementation");
        require(newImplementation.code.length > 0, "RE: implementation must be a contract");
        require(pendingUpgrade == address(0), "RE: upgrade already scheduled - cancel first");
        pendingUpgrade   = newImplementation;
        upgradeTimestamp = block.timestamp + UPGRADE_TIMELOCK;
        emit UpgradeScheduled(newImplementation, upgradeTimestamp);
    }

    /**
     * @notice Cancel a pending upgrade scheduled via scheduleUpgrade().
     */
    function cancelUpgrade() external onlyOwner {
        address cancelled = pendingUpgrade;
        pendingUpgrade   = address(0);
        upgradeTimestamp = 0;
        emit UpgradeCancelled(cancelled);
    }

    /**
     * @notice Enforces the 7-day upgrade timelock. Called internally by upgradeToAndCall().
     *         The upgrade must have been scheduled via scheduleUpgrade() and the timelock
     *         must have elapsed.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        require(upgradeTimestamp > 0,                    "RE: no upgrade scheduled");
        require(pendingUpgrade == newImplementation,     "RE: upgrade not scheduled");
        require(block.timestamp >= upgradeTimestamp,     "RE: timelock not elapsed");
        // Clear pending state — prevents replay
        pendingUpgrade   = address(0);
        upgradeTimestamp = 0;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Ownership safety
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Permanently disabled — renouncing ownership would lock the protocol
     *         (H-1: pause + renounce = permanent halt; no one can unpause or upgrade).
     *         Transfer ownership to a new multisig instead.
     */
    function renounceOwnership() public override onlyOwner {
        revert("RewardEngine: renounce disabled -- transfer to new owner instead");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // registerVault() — Called by PartnerVaultFactory at vault creation
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Register a new vault and record its initialCumS baseline.
     *         Called by factory immediately after vault creation + initial buy.
     *
     * @dev Sets lastEffectiveCumS[vault] = initialCumS[vault] per spec §5.2 recommendation:
     *      "Store lastEffectiveCumS[vault] = initialCumS[vault] at vault creation"
     *      This ensures the first qualifying epoch's delta = effectiveCumS_now - initialCumS.
     *
     * @param vault        Address of the new PartnerVault.
     * @param initialCumS_ Amount of PSRE from initial buy (S_p(N) baseline).
     */
    function registerVault(address vault, uint256 initialCumS_)
        external override
    {
        require(msg.sender == address(factory), "RE: only factory");
        require(vault != address(0),          "RE: zero vault");
        require(initialCumS_ > 0,            "RE: zero initialCumS");
        require(initialCumS[vault] == 0,      "RE: vault already registered");

        initialCumS[vault]        = initialCumS_;
        lastEffectiveCumS[vault]  = initialCumS_; // per spec §5.4 recommendation
        cumulativeRewardMinted[vault] = 0;
        qualified[vault]          = false;
        vaultActive[vault]        = true;
        lastGrowthEpoch[vault]    = currentEpochId();

        emit VaultRegistered(vault, initialCumS_);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Epoch helpers
    // ─────────────────────────────────────────────────────────────────────────

    function currentEpochId() public view returns (uint256) {
        if (block.timestamp < genesisTimestamp) return 0;
        return (block.timestamp - genesisTimestamp) / EPOCH_DURATION;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // finalizeEpoch() — Core monetary policy (Dev Spec v3.2 §4, §5)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Finalize an epoch. Callable by anyone after the epoch has ended.
     *         Processes exactly one epoch at a time (strictly sequential).
     *
     * @dev Algorithm (per spec §4.1):
     *   For each active vault:
     *     1. snapshotEpoch() → deltaCumS_p (raw cumS growth)
     *     2. Compute effectiveCumS_p(t) = cumS_p(t) - cumulativeRewardMinted[vault]
     *     3. Compute deltaEffectiveCumS = max(0, effectiveCumS_p(t) - lastEffectiveCumS[vault])
     *     4. First qualification check
     *     5. EMA update on deltaEffectiveCumS
     *     6. Accumulate deltaEffectiveCumSTotal
     *   Compute E_demand, E_scarcity, B, B_partners, B_stakers
     *   Distribute partner rewards proportional to weighted deltaEffectiveCumS
     *   Update cumulativeRewardMinted[vault] AFTER computing reward
     *   Mint, record epoch
     */
    function finalizeEpoch(uint256 epochId) external nonReentrant whenNotPaused {
        if (!firstEpochFinalized) {
            require(epochId == 0, "RE: must start at epoch 0");
        } else {
            require(epochId == lastFinalizedEpoch + 1, "RE: wrong epoch sequence");
        }
        require(!epochFinalized[epochId],   "RE: already finalized");
        require(currentEpochId() > epochId, "RE: epoch not ended yet");
        _finalizeSingleEpoch(epochId);
    }

    /**
     * @notice Lazily finalize up to AUTO_FINALIZE_MAX_EPOCHS pending epochs.
     *         Called automatically by vault interactions (createVault, buy) so that
     *         partner activity drives epoch finalization — no dedicated keeper required.
     *         Also callable by anyone directly (permissionless).
     * @dev    Safe to call when no epochs are pending (no-op).
     */
    function autoFinalizeEpochs() external nonReentrant whenNotPaused {
        if (currentEpochId() == 0) return;                                              // before first epoch ends
        if (firstEpochFinalized && lastFinalizedEpoch + 1 >= currentEpochId()) return;  // all caught up

        uint256 current = currentEpochId();
        uint256 next = firstEpochFinalized ? lastFinalizedEpoch + 1 : 0;
        uint256 count = 0;
        while (next < current && count < AUTO_FINALIZE_MAX_EPOCHS) {
            _finalizeSingleEpoch(next);
            next++;
            count++;
        }
    }

    /**
     * @notice Internal: execute epoch finalization logic for a single epoch.
     *         Called by finalizeEpoch() (with guards) and autoFinalizeEpochs() (sequentially).
     *
     * @dev Assumes caller has already validated epoch ordering and end-time.
     *      autoFinalizeEpochs() guarantees sequential ordering via its while loop.
     *      finalizeEpoch() enforces ordering with explicit require guards.
     */
    function _finalizeSingleEpoch(uint256 epochId) internal {
        // Defense-in-depth: prevent double-finalization regardless of caller.
        require(!epochFinalized[epochId], "RE: already finalized");

        // ── Snapshot staking vault ───────────────────────────────────────────
        stakingVault.snapshotEpoch(epochId);

        // ── Per-vault reward computation ─────────────────────────────────────
        address[] memory vaults = factory.getAllVaults();
        uint256 nVaults = vaults.length;

        uint256[] memory deltaEffArr  = new uint256[](nVaults);
        uint256[] memory alphaArr     = new uint256[](nVaults);
        uint256[] memory weightArr    = new uint256[](nVaults);
        uint256[] memory rewardArr    = new uint256[](nVaults); // to update cumulativeRewardMinted later
        uint256[] memory cumSArr      = new uint256[](nVaults);
        uint256[] memory effCumSArr   = new uint256[](nVaults);

        uint256 W                       = 0;
        uint256 deltaEffectiveCumSTotal = 0;

        // ── Pass 1: compute effectiveCumS deltas, EMA, tiers, weights ────────
        for (uint256 i = 0; i < nVaults; i++) {
            address vault = vaults[i];

            // Skip unregistered vaults (initialCumS not set)
            if (initialCumS[vault] == 0) continue;

            // 1. Snapshot epoch → get raw deltaCumS (cumS − lastEpochCumS)
            //    Also updates lastEpochCumS in the vault.
            IPartnerVault(vault).snapshotEpoch();
            // After snapshotEpoch, vault's cumS reflects current state.
            // Read cumS via interface.
            uint256 currentCumS = IPartnerVault(vault).getCumS();
            cumSArr[i] = currentCumS;

            // 2. Compute effectiveCumS(t) = cumS(t) - cumulativeRewardMinted[vault]
            //    Defensive floor at 0.
            //    INVARIANT: cumS >= cumulativeRewardMinted holds by construction because:
            //      - rewards(epoch) = r_base × ΔeffectiveCumS ≤ r_base × ΔcumS
            //      - r_base ≤ alphaBase_MAX = 0.15e18 (15%) < 1.0e18 (100%)
            //      - Therefore cumulativeRewardMinted = Σ rewards ≤ Σ(r_base × ΔcumS) = r_base × cumS ≤ cumS
            //    The floor is a defense-in-depth guard for future upgrade scenarios only.
            uint256 cumRM = cumulativeRewardMinted[vault];
            uint256 effCumS = currentCumS >= cumRM ? currentCumS - cumRM : 0;
            effCumSArr[i] = effCumS;

            // 3. Compute deltaEffectiveCumS = max(0, effCumS - lastEffectiveCumS)
            uint256 lastEff = lastEffectiveCumS[vault];
            uint256 delta   = effCumS > lastEff ? effCumS - lastEff : 0;

            // 4. First qualification check
            if (!qualified[vault]) {
                if (currentCumS > initialCumS[vault]) {
                    // Vault qualifies for the first time
                    qualified[vault] = true;
                    // First reward basis: effectiveCumS - initialCumS
                    // (cumulativeRewardMinted == 0 here since no rewards yet minted)
                    uint256 basis = effCumS > initialCumS[vault]
                        ? effCumS - initialCumS[vault]
                        : 0;
                    delta = basis;
                    emit VaultFirstQualified(vault, epochId, currentCumS, initialCumS[vault]);
                } else {
                    // Not yet qualified — no reward contribution
                    delta = 0;
                }
            }

            deltaEffArr[i] = delta;

            // 5. EMA update on deltaEffectiveCumS (per spec §5.5)
            uint256 R_old = R[vault];
            uint256 R_new = (R_old * (PRECISION - theta) + delta * theta) / PRECISION;
            sumR = sumR - R_old + R_new;
            R[vault] = R_new;

            // 6. Tier assignment based on share of sumR
            uint256 mult;
            if (sumR > 0) {
                uint256 s = (R_new * PRECISION) / sumR;
                if (s >= goldThreshold) {
                    mult = mGold;
                } else if (s >= silverThreshold) {
                    mult = mSilver;
                } else {
                    mult = mBronze;
                }
            } else {
                // §1.9: sumR == 0 → Bronze for all active qualifying vaults
                mult = mBronze;
            }

            // alpha_p = r_base × tier_multiplier / 1e18
            uint256 alpha_p = (alphaBase * mult) / PRECISION;
            alphaArr[i] = alpha_p;

            // 7. Weight: w_p = alpha_p × deltaEffectiveCumS / 1e18
            uint256 w_p = (alpha_p * delta) / PRECISION;
            weightArr[i]            = w_p;
            W                       += w_p;
            deltaEffectiveCumSTotal += delta;

            // Accumulate vault activity
            if (delta > 0) {
                if (!vaultActive[vault]) {
                    vaultActive[vault] = true;
                    emit VaultReactivated(vault, epochId);
                }
                lastGrowthEpoch[vault] = epochId;
            } else {
                if (vaultActive[vault] &&
                    epochId >= lastGrowthEpoch[vault] + INACTIVE_THRESHOLD)
                {
                    vaultActive[vault] = false;
                    emit VaultMarkedInactive(vault, epochId);
                }
            }
        }

        // ── Compute budget ──────────────────────────────────────────────────
        uint256 remaining = S_EMISSION > T ? S_EMISSION - T : 0;

        // E_demand = alphaBase × Σ deltaEffectiveCumS_p / 1e18  (§5.6)
        uint256 E_demand = (alphaBase * deltaEffectiveCumSTotal) / PRECISION;

        // E_scarcity = E0 × (1 - x)^2 where x = T / S_EMISSION  (§5.7)
        uint256 E_scarcity;
        if (T >= S_EMISSION) {
            E_scarcity = 0;
        } else {
            uint256 x    = (T * PRECISION) / S_EMISSION;
            uint256 omx  = PRECISION - x;
            E_scarcity   = (E0 * omx / PRECISION) * omx / PRECISION;
        }

        // B = min(E_demand, E_scarcity, remaining)  (§5.8)
        uint256 B = _min3(E_demand, E_scarcity, remaining);

        // Split  (§5.9)
        uint256 B_partners = (B * partnerSplit) / PRECISION;
        uint256 B_stakers  = B - B_partners;

        // ── Distribute partner rewards ──────────────────────────────────────
        // Per §5.10: W == 0 → partner pool unminted
        uint256 P_partners = 0;

        if (W > 0 && B_partners > 0) {
            for (uint256 i = 0; i < nVaults; i++) {
                if (weightArr[i] == 0) continue;
                address vault = vaults[i];
                if (initialCumS[vault] == 0) continue;

                uint256 reward_p = (B_partners * weightArr[i]) / W;
                if (reward_p == 0) continue;

                owedPartner[vault] += reward_p;
                P_partners         += reward_p;
                rewardArr[i]        = reward_p;

                emit PartnerRewardAccrued(epochId, vault, reward_p);
                emit PartnerEffectiveCumSSnapshot(
                    epochId, vault,
                    cumSArr[i], effCumSArr[i], deltaEffArr[i],
                    alphaArr[i], weightArr[i], reward_p
                );
            }
        }

        // ── Update cumulativeRewardMinted and lastEffectiveCumS ─────────────
        // CRITICAL: update cumulativeRewardMinted AFTER computing rewards
        // to prevent self-referential compounding within a single epoch. (§5.2)
        for (uint256 i = 0; i < nVaults; i++) {
            address vault = vaults[i];
            if (initialCumS[vault] == 0) continue;

            // Update cumulativeRewardMinted AFTER reward computation
            if (rewardArr[i] > 0) {
                cumulativeRewardMinted[vault] += rewardArr[i];
            }

            // Store effectiveCumS for next epoch's delta computation
            lastEffectiveCumS[vault] = effCumSArr[i];
        }

        // ── Staker pool ──────────────────────────────────────────────────────
        uint256 P_stakers = stakingVault.totalStakeTime(epochId) > 0 ? B_stakers : 0;

        // ── Mint ─────────────────────────────────────────────────────────────
        uint256 P          = P_partners + P_stakers;
        uint256 mintAmount = P < remaining ? P : remaining;

        if (mintAmount > 0) {
            // Fix #16: if PSRE transfers are paused, mints would succeed but claims would fail,
            // consuming emission budget with tokens nobody can receive. Revert instead.
            // Use Pausable interface directly; paused() is not on IPSRE to avoid diamond conflict.
            require(!IPausableToken(address(psre)).paused(), "RE: PSRE transfers paused");
            psre.mint(address(this), mintAmount);
            T += mintAmount;
            assert(T <= S_EMISSION);
        }

        // ── Record epoch ─────────────────────────────────────────────────────
        epochFinalized[epochId]              = true;
        epochBudget[epochId]                 = B;
        epochPartnersPool[epochId]           = B_partners;
        epochStakersPool[epochId]            = B_stakers;
        epochMinted[epochId]                 = mintAmount;
        epochDeltaEffectiveCumSTotal[epochId] = deltaEffectiveCumSTotal;
        lastFinalizedEpoch                   = epochId;
        firstEpochFinalized                  = true;

        emit EpochFinalized(
            epochId, B, E_demand, E_scarcity,
            B_partners, B_stakers, mintAmount, deltaEffectiveCumSTotal
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Claims
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Claim all accumulated partner rewards for a vault.
     *         No vesting — rewards are immediately claimable after epoch finalization.
     *         Caller must be the vault owner (partnerOwner).
     *
     * @param vault  Address of the PartnerVault to claim rewards for.
     */
    function claimPartnerReward(address vault) external nonReentrant whenNotPaused {
        // Fix #8: query vault's current owner directly instead of factory.partnerOf(),
        // which goes stale after updateOwner/acceptOwnership vault transfers.
        // Fix #18: whenNotPaused — pausing RE must freeze reward outflows, not just new epochs.
        require(
            IPartnerVault(vault).owner() == msg.sender,
            "RE: not vault owner"
        );
        uint256 owed = owedPartner[vault];
        require(owed > 0, "RE: nothing to claim");

        owedPartner[vault]   = 0;
        totalClaimed[vault] += owed;

        IERC20(address(psre)).safeTransfer(msg.sender, owed);

        emit PartnerRewardClaimed(vault, owed);
    }

    /**
     * @notice Claim staker reward for a specific epoch.
     * @param epochId  The epoch to claim staker reward for.
     */
    function claimStake(uint256 epochId) external nonReentrant whenNotPaused {
        // Fix #18: whenNotPaused — pausing RE must freeze staker reward outflows.
        require(epochFinalized[epochId], "RE: epoch not finalized");

        bytes32 key = keccak256(abi.encodePacked(epochId, msg.sender));
        require(!_stakeClaimed[key], "RE: already claimed");

        uint256 totalST = stakingVault.totalStakeTime(epochId);
        require(totalST > 0, "RE: no staking activity");

        uint256 userST = stakingVault.stakeTimeOf(msg.sender, epochId);
        require(userST > 0, "RE: no stake this epoch");

        uint256 reward = (epochStakersPool[epochId] * userST) / totalST;
        require(reward > 0, "RE: zero reward");

        _stakeClaimed[key] = true;
        IERC20(address(psre)).safeTransfer(msg.sender, reward);

        emit StakeClaimed(epochId, msg.sender, userST, reward);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Governance: timelock param updates (Dev Spec v3.2 §10)
    // ─────────────────────────────────────────────────────────────────────────

    function queueAlphaBase(uint256 v) external onlyOwner {
        require(v >= ALPHA_MIN && v <= ALPHA_MAX, "RE: out of bounds");
        pendingAlphaBase = PendingParam(v, block.timestamp + PARAM_TIMELOCK);
        emit ParamUpdateQueued("alphaBase", v, pendingAlphaBase.readyAt);
    }

    function applyAlphaBase() external onlyOwner {
        require(pendingAlphaBase.readyAt > 0 &&
                block.timestamp >= pendingAlphaBase.readyAt, "RE: timelock");
        emit ParamUpdated("alphaBase", alphaBase, pendingAlphaBase.value);
        alphaBase = pendingAlphaBase.value;
        delete pendingAlphaBase;
    }

    function queueE0(uint256 v) external onlyOwner {
        require(v >= E0_MIN && v <= E0_MAX, "RE: out of bounds");
        pendingE0 = PendingParam(v, block.timestamp + PARAM_TIMELOCK);
        emit ParamUpdateQueued("E0", v, pendingE0.readyAt);
    }

    function applyE0() external onlyOwner {
        require(pendingE0.readyAt > 0 &&
                block.timestamp >= pendingE0.readyAt, "RE: timelock");
        emit ParamUpdated("E0", E0, pendingE0.value);
        E0 = pendingE0.value;
        delete pendingE0;
    }

    function queuePartnerSplit(uint256 v) external onlyOwner {
        require(v >= SPLIT_MIN && v <= SPLIT_MAX, "RE: out of bounds");
        pendingPartnerSplit = PendingParam(v, block.timestamp + PARAM_TIMELOCK);
        emit ParamUpdateQueued("partnerSplit", v, pendingPartnerSplit.readyAt);
    }

    function applyPartnerSplit() external onlyOwner {
        require(pendingPartnerSplit.readyAt > 0 &&
                block.timestamp >= pendingPartnerSplit.readyAt, "RE: timelock");
        emit ParamUpdated("partnerSplit", partnerSplit, pendingPartnerSplit.value);
        partnerSplit = pendingPartnerSplit.value;
        delete pendingPartnerSplit;
    }

    /// @notice Queue a tier parameter update (48h timelock).
    function queueTierParams(
        uint256 _silverTh, uint256 _goldTh,
        uint256 _mB, uint256 _mS, uint256 _mG
    ) external onlyOwner {
        require(_goldTh > _silverTh,      "RE: invalid thresholds");
        require(_mG >= _mS && _mS >= _mB, "RE: invalid multipliers");
        pendingSilverTh   = _silverTh;
        pendingGoldTh     = _goldTh;
        pendingMBronze    = _mB;
        pendingMSilver    = _mS;
        pendingMGold      = _mG;
        pendingTierParams = PendingParam(1, block.timestamp + PARAM_TIMELOCK);
        emit ParamUpdateQueued("tierParams", 1, pendingTierParams.readyAt);
    }

    /// @notice Apply queued tier parameter update.
    function applyTierParams() external onlyOwner {
        require(pendingTierParams.readyAt > 0 &&
                block.timestamp >= pendingTierParams.readyAt, "RE: timelock");
        silverThreshold = pendingSilverTh;
        goldThreshold   = pendingGoldTh;
        mBronze         = pendingMBronze;
        mSilver         = pendingMSilver;
        mGold           = pendingMGold;
        delete pendingTierParams;
        emit ParamUpdated("tierParams", 0, 1);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Pause
    // ─────────────────────────────────────────────────────────────────────────

    function pause()   external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // ─────────────────────────────────────────────────────────────────────────
    // View helpers
    // ─────────────────────────────────────────────────────────────────────────

    function remainingEmission() external view returns (uint256) {
        return S_EMISSION > T ? S_EMISSION - T : 0;
    }

    function currentScarcityCap() external view returns (uint256) {
        if (T >= S_EMISSION) return 0;
        uint256 x   = (T * PRECISION) / S_EMISSION;
        uint256 omx = PRECISION - x;
        return (E0 * omx / PRECISION) * omx / PRECISION;
    }

    /// @notice Compute effectiveCumS for a vault (read-only helper).
    function effectiveCumSOf(address vault) external view returns (uint256) {
        uint256 cumS_ = IPartnerVault(vault).getCumS();
        uint256 cumRM = cumulativeRewardMinted[vault];
        return cumS_ >= cumRM ? cumS_ - cumRM : 0;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────────

    function _min3(uint256 a, uint256 b, uint256 c) internal pure returns (uint256) {
        return a < b ? (a < c ? a : c) : (b < c ? b : c);
    }
}
