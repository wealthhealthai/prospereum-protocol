// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/IPSRE.sol";
import "../interfaces/IPartnerVault.sol";
import "../interfaces/IPartnerVaultFactory.sol";
import "../interfaces/IStakingVault.sol";

/**
 * @title RewardEngine
 * @notice Core monetary policy contract for Prospereum.
 *
 * @dev Dev Spec v2.3, Sections 2.5, 3-11
 *
 *      Reward rates (whitepaper §6.2, confirmed by Shu):
 *        Bronze: alphaBase * M_BRONZE = 8%  * 1.00 = 8%
 *        Silver: alphaBase * M_SILVER = 8%  * 1.25 = 10%
 *        Gold:   alphaBase * M_GOLD   = 8%  * 1.50 = 12%
 */
contract RewardEngine is ReentrancyGuard, Pausable, Ownable2Step {
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    uint256 public constant S_EMISSION     = 12_600_000e18;
    uint256 public constant EPOCH_DURATION = 7 days;
    uint256 public constant PRECISION      = 1e18;

    // Governance bounds
    uint256 public constant ALPHA_MIN  = 0.05e18;
    uint256 public constant ALPHA_MAX  = 0.15e18;
    uint256 public constant E0_MIN     = S_EMISSION * 5 / 10000;  // 0.0005 * S_EMISSION
    uint256 public constant E0_MAX     = S_EMISSION * 2 / 1000;   // 0.002  * S_EMISSION
    uint256 public constant SPLIT_MIN  = 0.60e18;
    uint256 public constant SPLIT_MAX  = 0.80e18;
    uint256 public constant PARAM_TIMELOCK = 48 hours;

    // -------------------------------------------------------------------------
    // Immutables
    // -------------------------------------------------------------------------

    IPSRE                public immutable psre;
    IPartnerVaultFactory public immutable factory;
    IStakingVault        public immutable stakingVault;
    uint256              public immutable genesisTimestamp;

    // -------------------------------------------------------------------------
    // Governance parameters (Dev Spec v2.3 §1.3-1.5)
    // -------------------------------------------------------------------------

    uint256 public alphaBase    = 0.08e18;  // 8% base rate
    uint256 public E0           = S_EMISSION / 1000; // 12,600 PSRE/week default
    uint256 public constant k   = 2;        // scarcity exponent, immutable v1
    uint256 public constant theta = 76_923_076_923_076_923; // 1e18/13

    uint256 public silverThreshold = 0.005e18;
    uint256 public goldThreshold   = 0.02e18;
    uint256 public mBronze         = 1.00e18;
    uint256 public mSilver         = 1.25e18;
    uint256 public mGold           = 1.50e18;

    uint256 public partnerSplit = 0.70e18;

    // -------------------------------------------------------------------------
    // Global emission tracking
    // -------------------------------------------------------------------------

    uint256 public T;                   // total PSRE minted by this engine
    uint256 public lastFinalizedEpoch;
    bool    public firstEpochFinalized;

    // -------------------------------------------------------------------------
    // Partner state (by vault address)
    // -------------------------------------------------------------------------

    mapping(address => uint256) public creditedNB;
    mapping(address => uint256) public R;
    uint256 public sumR;

    // -------------------------------------------------------------------------
    // Epoch records
    // -------------------------------------------------------------------------

    mapping(uint256 => bool)    public epochFinalized;
    mapping(uint256 => uint256) public epochBudget;
    mapping(uint256 => uint256) public epochPartnersPool;
    mapping(uint256 => uint256) public epochStakersPool;
    mapping(uint256 => uint256) public epochMinted;

    mapping(address => uint256) public owedPartner;

    // Double-claim prevention for stakers
    mapping(bytes32 => bool) private _stakeClaimed;

    // -------------------------------------------------------------------------
    // Timelock queue
    // -------------------------------------------------------------------------

    struct PendingParam { uint256 value; uint256 readyAt; }
    PendingParam public pendingAlphaBase;
    PendingParam public pendingE0;
    PendingParam public pendingPartnerSplit;
    PendingParam public pendingTierParams; // signals a tier param update is queued

    // Staged tier param values (applied atomically with applyTierParams)
    uint256 public pendingSilverTh;
    uint256 public pendingGoldTh;
    uint256 public pendingMBronze;
    uint256 public pendingMSilver;
    uint256 public pendingMGold;

    // -------------------------------------------------------------------------
    // Events (Dev Spec v2.3 §10)
    // -------------------------------------------------------------------------

    event EpochFinalized(
        uint256 indexed epochId, uint256 B,
        uint256 E_demand, uint256 E_scarcity,
        uint256 B_partners, uint256 B_stakers, uint256 minted
    );
    event PartnerDeltaComputed(
        uint256 indexed epochId, address indexed vault,
        uint256 deltaNB, uint256 alpha_p, uint256 weight, uint256 reward
    );
    event StakeClaimed(uint256 indexed epochId, address indexed user, uint256 stakeTime, uint256 reward);
    event PartnerClaimed(uint256 indexed epochId, address indexed vault, uint256 reward);
    event ParamUpdateQueued(string param, uint256 value, uint256 readyAt);
    event ParamUpdated(string param, uint256 oldValue, uint256 newValue);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(
        address _psre,
        address _factory,
        address _stakingVault,
        uint256 _genesisTimestamp,
        address _admin
    ) Ownable(_admin) {
        require(_psre         != address(0), "RE: zero psre");
        require(_factory      != address(0), "RE: zero factory");
        require(_stakingVault != address(0), "RE: zero stakingVault");
        require(_genesisTimestamp > 0,       "RE: zero genesis");

        psre             = IPSRE(_psre);
        factory          = IPartnerVaultFactory(_factory);
        stakingVault     = IStakingVault(_stakingVault);
        genesisTimestamp = _genesisTimestamp;
    }

    // -------------------------------------------------------------------------
    // Epoch helpers
    // -------------------------------------------------------------------------

    function currentEpochId() public view returns (uint256) {
        if (block.timestamp < genesisTimestamp) return 0;
        return (block.timestamp - genesisTimestamp) / EPOCH_DURATION;
    }

    // -------------------------------------------------------------------------
    // finalizeEpoch (Dev Spec v2.3 §4, §5, §6)
    // -------------------------------------------------------------------------

    /**
     * @notice Finalize an epoch. Callable by anyone after the epoch has ended.
     *         Processes exactly one epoch at a time (strictly sequential).
     */
    function finalizeEpoch(uint256 epochId) external nonReentrant whenNotPaused {
        if (!firstEpochFinalized) {
            require(epochId == 0, "RE: must start at epoch 0");
        } else {
            require(epochId == lastFinalizedEpoch + 1, "RE: wrong epoch sequence");
        }
        require(!epochFinalized[epochId],       "RE: already finalized");
        require(currentEpochId() > epochId,     "RE: epoch not ended yet");

        // Snapshot staking vault
        stakingVault.snapshotEpoch(epochId);

        // ── Per-partner computation ─────────────────────────────────────────
        address[] memory vaults = factory.getAllVaults();
        uint256 nVaults = vaults.length;

        uint256[] memory deltaNBArr = new uint256[](nVaults);
        uint256[] memory alphaArr   = new uint256[](nVaults);
        uint256[] memory weightArr  = new uint256[](nVaults);

        uint256 W        = 0;
        uint256 E_demand = 0;

        for (uint256 i = 0; i < nVaults; i++) {
            address vault  = vaults[i];
            uint256 cumBuy = IPartnerVault(vault).cumBuy();
            uint256 cred   = creditedNB[vault];
            uint256 dNB    = cumBuy > cred ? cumBuy - cred : 0;

            if (dNB > 0) creditedNB[vault] += dNB;

            // Spec §11 invariant: creditedNB[vault] <= cumBuy[vault]
            assert(creditedNB[vault] <= cumBuy);

            // EMA: R_new = (R_old*(1e18-theta) + dNB*theta) / 1e18
            uint256 R_old = R[vault];
            uint256 R_new = (R_old * (PRECISION - theta) + dNB * theta) / PRECISION;
            sumR = sumR - R_old + R_new;
            R[vault] = R_new;

            // Tier multiplier
            uint256 mult;
            if (sumR > 0) {
                uint256 s = (R_new * PRECISION) / sumR;
                mult = s >= goldThreshold ? mGold : (s >= silverThreshold ? mSilver : mBronze);
            } else {
                mult = mBronze; // §1.9: sumR==0 -> use base
            }

            uint256 alpha_p = (alphaBase * mult) / PRECISION;
            uint256 w_p     = (alpha_p * dNB) / PRECISION;

            deltaNBArr[i] = dNB;
            alphaArr[i]   = alpha_p;
            weightArr[i]  = w_p;
            W             += w_p;
            E_demand      += w_p;
        }

        // ── Scarcity cap ────────────────────────────────────────────────────
        uint256 E_scarcity;
        uint256 remaining = S_EMISSION > T ? S_EMISSION - T : 0;
        if (T >= S_EMISSION) {
            E_scarcity = 0;
        } else {
            uint256 x         = (T * PRECISION) / S_EMISSION;
            uint256 omx       = PRECISION - x;
            uint256 omx2      = (omx * omx) / PRECISION; // (1-x)^2
            E_scarcity        = (E0 * omx2) / PRECISION;
        }

        // ── Budget B = min(E_demand, E_scarcity, remaining) ─────────────────
        uint256 B = _min3(E_demand, E_scarcity, remaining);
        uint256 B_partners = (B * partnerSplit) / PRECISION;
        uint256 B_stakers  = B - B_partners;

        // ── Partner rewards ─────────────────────────────────────────────────
        uint256 P_partners = 0;
        if (W > 0 && B_partners > 0) {
            for (uint256 i = 0; i < nVaults; i++) {
                if (weightArr[i] == 0) continue;
                address vault    = vaults[i];
                uint256 reward_p = (B_partners * weightArr[i]) / W;
                if (reward_p > 0) {
                    owedPartner[vault] += reward_p;
                    P_partners         += reward_p;
                    emit PartnerDeltaComputed(epochId, vault, deltaNBArr[i], alphaArr[i], weightArr[i], reward_p);
                }
            }
        }

        // ── Staker pool ─────────────────────────────────────────────────────
        uint256 P_stakers = stakingVault.totalStakeTime(epochId) > 0 ? B_stakers : 0;

        // ── Mint ─────────────────────────────────────────────────────────────
        uint256 P          = P_partners + P_stakers;
        uint256 mintAmount = P < remaining ? P : remaining;

        if (mintAmount > 0) {
            psre.mint(address(this), mintAmount);
            T += mintAmount;
            assert(T <= S_EMISSION);
        }

        epochFinalized[epochId]    = true;
        epochBudget[epochId]       = B;
        epochPartnersPool[epochId] = B_partners;
        epochStakersPool[epochId]  = B_stakers;
        epochMinted[epochId]       = mintAmount;
        lastFinalizedEpoch         = epochId;
        firstEpochFinalized        = true;

        emit EpochFinalized(epochId, B, E_demand, E_scarcity, B_partners, B_stakers, mintAmount);
    }

    // -------------------------------------------------------------------------
    // Claims
    // -------------------------------------------------------------------------

    /**
     * @notice Claim all accumulated partner rewards for a vault.
     *         owedPartner[vault] accumulates across multiple epochs (pull-based).
     *         The epochId parameter is used only to verify the epoch is finalized
     *         before allowing claims. The emitted PartnerClaimed event includes
     *         the passed epochId as a reference point, not the per-epoch reward amount.
     *         Off-chain indexers should track cumulative claimed amounts, not per-epoch.
     *         Per-epoch tracking will be added in v2.
     */
    function claimPartner(uint256 epochId, address vault) external nonReentrant {
        require(epochFinalized[epochId], "RE: epoch not finalized");
        uint256 owed = owedPartner[vault];
        require(owed > 0, "RE: nothing to claim");
        owedPartner[vault] = 0;
        IERC20(address(psre)).safeTransfer(vault, owed);
        emit PartnerClaimed(epochId, vault, owed);
    }

    function claimStake(uint256 epochId) external nonReentrant {
        require(epochFinalized[epochId], "RE: epoch not finalized");

        bytes32 key = keccak256(abi.encodePacked(epochId, msg.sender));
        require(!_stakeClaimed[key], "RE: already claimed");

        uint256 totalST = stakingVault.totalStakeTime(epochId);
        require(totalST > 0, "RE: no staking activity");
        uint256 userST  = stakingVault.stakeTimeOf(msg.sender, epochId);
        require(userST  > 0, "RE: no stake this epoch");

        uint256 reward = (epochStakersPool[epochId] * userST) / totalST;
        require(reward > 0, "RE: zero reward");

        _stakeClaimed[key] = true;
        IERC20(address(psre)).safeTransfer(msg.sender, reward);

        emit StakeClaimed(epochId, msg.sender, userST, reward);
    }

    // -------------------------------------------------------------------------
    // Governance: timelock param updates
    // -------------------------------------------------------------------------

    function queueAlphaBase(uint256 v) external onlyOwner {
        require(v >= ALPHA_MIN && v <= ALPHA_MAX, "RE: out of bounds");
        pendingAlphaBase = PendingParam(v, block.timestamp + PARAM_TIMELOCK);
        emit ParamUpdateQueued("alphaBase", v, pendingAlphaBase.readyAt);
    }
    function applyAlphaBase() external onlyOwner {
        require(block.timestamp >= pendingAlphaBase.readyAt && pendingAlphaBase.readyAt > 0, "RE: timelock");
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
        require(block.timestamp >= pendingE0.readyAt && pendingE0.readyAt > 0, "RE: timelock");
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
        require(block.timestamp >= pendingPartnerSplit.readyAt && pendingPartnerSplit.readyAt > 0, "RE: timelock");
        emit ParamUpdated("partnerSplit", partnerSplit, pendingPartnerSplit.value);
        partnerSplit = pendingPartnerSplit.value;
        delete pendingPartnerSplit;
    }

    /// @notice Queue a tier parameter update. Takes effect after PARAM_TIMELOCK (48h).
    ///         Closes the governance front-run vector identified by ADJUDICATOR.
    function queueTierParams(
        uint256 _silverTh, uint256 _goldTh,
        uint256 _mB, uint256 _mS, uint256 _mG
    ) external onlyOwner {
        require(_goldTh > _silverTh,      "RE: invalid thresholds");
        require(_mG >= _mS && _mS >= _mB, "RE: invalid multipliers");
        pendingSilverTh  = _silverTh;
        pendingGoldTh    = _goldTh;
        pendingMBronze   = _mB;
        pendingMSilver   = _mS;
        pendingMGold     = _mG;
        pendingTierParams = PendingParam(1, block.timestamp + PARAM_TIMELOCK); // value=1 as flag
        emit ParamUpdateQueued("tierParams", 1, pendingTierParams.readyAt);
    }

    /// @notice Apply queued tier parameter update after timelock has passed.
    function applyTierParams() external onlyOwner {
        require(pendingTierParams.readyAt > 0 && block.timestamp >= pendingTierParams.readyAt, "RE: timelock");
        silverThreshold = pendingSilverTh;
        goldThreshold   = pendingGoldTh;
        mBronze         = pendingMBronze;
        mSilver         = pendingMSilver;
        mGold           = pendingMGold;
        delete pendingTierParams;
        emit ParamUpdated("tierParams", 0, 1);
    }

    // -------------------------------------------------------------------------
    // Pause
    // -------------------------------------------------------------------------

    function pause()   external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    function _min3(uint256 a, uint256 b, uint256 c) internal pure returns (uint256) {
        return a < b ? (a < c ? a : c) : (b < c ? b : c);
    }

    function remainingEmission() external view returns (uint256) {
        return S_EMISSION > T ? S_EMISSION - T : 0;
    }

    function currentScarcityCap() external view returns (uint256) {
        if (T >= S_EMISSION) return 0;
        uint256 x    = (T * PRECISION) / S_EMISSION;
        uint256 omx  = PRECISION - x;
        uint256 omx2 = (omx * omx) / PRECISION;
        return (E0 * omx2) / PRECISION;
    }
}
