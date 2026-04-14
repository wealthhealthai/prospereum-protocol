// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IStakingVault.sol";

/**
 * @title StakingVault v3.0 — Synthetix-Style Passive Staking
 * @notice "Stake and forget." Users stake PSRE or LP tokens once and earn
 *         rewards across all finalized epochs automatically — no checkpointing
 *         required before each epoch end.
 *
 *         Design (epoch-adapted Synthetix model):
 *         - Each epoch has a global rewardPerToken for PSRE stakers and LP stakers.
 *         - rewardPerToken[e] is computed at distributeStakerRewards() time using
 *           the total staked captured in snapshotEpoch().
 *         - A user's share for epoch E = their balance (at settlement time) × rewardPerToken[E].
 *         - _settleFinishedEpochs() accumulates pending rewards lazily, called
 *           before every balance change (stake/unstake) and before every claim.
 *
 *         Correctness invariant:
 *         - Because settlement runs BEFORE any balance change, the user's balance
 *           at settlement time equals their balance during those past epochs.
 *         - A user who stakes once and never touches their balance earns rewards
 *           for every finalized epoch without any further interaction.
 *
 *         Fixes the BlockApex liveness failure (passive stakers always got 0):
 *         - v2 _checkpoint() inside claimStake() silently skipped snapshotted epochs,
 *           so passive stakers' contributions were never recorded.
 *         - v3 eliminates that problem entirely: no pre-claim checkpointing needed.
 *
 * @dev Shu-authorized redesign. Epoch interface to RewardEngine is unchanged:
 *      snapshotEpoch() and distributeStakerRewards() retain the same signatures.
 */
contract StakingVault is ReentrancyGuard, IStakingVault {
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    uint256 public constant EPOCH_DURATION = 7 days;

    /// @notice Governance precision (1e18 = 100%).
    uint256 public constant PRECISION = 1e18;

    /// @notice Precision multiplier for per-token reward accumulator.
    ///         Using 1e36 avoids precision loss when dividing small reward pools
    ///         by large token supplies.
    uint256 public constant REWARD_PRECISION = 1e36;

    /// @notice Gas cap: maximum epochs settled per _settleFinishedEpochs() call.
    ///         If a user is >52 epochs behind, multiple interactions are needed.
    uint256 public constant MAX_SETTLE_EPOCHS = 52;

    // -------------------------------------------------------------------------
    // Immutables
    // -------------------------------------------------------------------------

    address public immutable psre;
    address public immutable lpToken;
    uint256 public immutable genesisTimestamp;

    // -------------------------------------------------------------------------
    // Sub-pool split (within the staker allocation)
    // psreSplit + lpSplit must always == PRECISION (1e18)
    // -------------------------------------------------------------------------

    uint256 public psreSplit = 0.5e18;   // 50% to PSRE stakers
    uint256 public lpSplit   = 0.5e18;   // 50% to LP stakers

    // -------------------------------------------------------------------------
    // Global staking counters — updated on every stake / unstake
    // -------------------------------------------------------------------------

    uint256 public totalPSREStaked;
    uint256 public totalLPStaked;

    // -------------------------------------------------------------------------
    // Per-epoch state — set at finalization time by RewardEngine
    // -------------------------------------------------------------------------

    /// @notice Total PSRE staked at the time snapshotEpoch(epochId) was called.
    mapping(uint256 => uint256) public epochTotalPSREStaked;

    /// @notice Total LP staked at the time snapshotEpoch(epochId) was called.
    mapping(uint256 => uint256) public epochTotalLPStaked;

    /// @notice PSRE reward per token for epoch (× REWARD_PRECISION).
    ///         Zero if no PSRE was staked during the epoch.
    mapping(uint256 => uint256) public epochPSRERewardPerToken;

    /// @notice LP reward per token for epoch (× REWARD_PRECISION).
    ///         Zero if no LP was staked during the epoch.
    mapping(uint256 => uint256) public epochLPRewardPerToken;

    /// @notice PSRE sub-pool for epoch (psreSplit fraction of totalStakerPool).
    mapping(uint256 => uint256) public epochPSREPool;

    /// @notice LP sub-pool for epoch (lpSplit fraction of totalStakerPool).
    mapping(uint256 => uint256) public epochLPPool;

    /// @notice True once snapshotEpoch() has been called for this epoch.
    mapping(uint256 => bool) public epochSnapshotted;

    /// @notice True once distributeStakerRewards() has been called for this epoch.
    mapping(uint256 => bool) public epochDistributed;

    /// @notice The highest epoch for which distributeStakerRewards() has been called.
    ///         Initialized to type(uint256).max (sentinel: no epoch finalized yet).
    ///         _settleFinishedEpochs() returns early until at least one epoch is finalized.
    uint256 public lastFinalizedEpoch = type(uint256).max;

    // -------------------------------------------------------------------------
    // Per-user state
    // -------------------------------------------------------------------------

    struct UserStake {
        uint256 psreBalance;      // PSRE tokens currently staked
        uint256 lpBalance;        // LP tokens currently staked
        uint256 lastSettledEpoch; // next epoch index to be settled for this user
    }

    mapping(address => UserStake) public userStakes;

    /// @notice Accumulated but unclaimed rewards for each user (in PSRE, 18 decimals).
    mapping(address => uint256) public pendingRewards;

    // -------------------------------------------------------------------------
    // Governance & access control
    // -------------------------------------------------------------------------

    address public owner;
    address public rewardEngine;
    bool    private rewardEngineSet;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event PSREStaked(address indexed user, uint256 amount);
    event PSREUnstaked(address indexed user, uint256 amount);
    event LPStaked(address indexed user, uint256 amount);
    event LPUnstaked(address indexed user, uint256 amount);
    event EpochSnapshotted(uint256 indexed epochId);
    event StakerRewardsDistributed(uint256 indexed epochId, uint256 psrePool, uint256 lpPool);
    event RewardsClaimed(address indexed user, uint256 amount);
    event SplitUpdated(uint256 psreSplit_, uint256 lpSplit_);
    event RewardEngineSet(address indexed rewardEngine_);

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------

    modifier onlyOwner() {
        require(msg.sender == owner, "StakingVault: not owner");
        _;
    }

    modifier onlyRewardEngine() {
        require(msg.sender == rewardEngine, "StakingVault: only rewardEngine");
        _;
    }

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(
        address _psre,
        address _lpToken,
        uint256 _genesisTimestamp,
        address _owner
    ) {
        require(_psre    != address(0), "StakingVault: zero addr");
        require(_lpToken != address(0), "StakingVault: zero addr");
        require(_genesisTimestamp > 0,  "StakingVault: zero genesis");
        psre             = _psre;
        lpToken          = _lpToken;
        genesisTimestamp = _genesisTimestamp;
        owner            = _owner;
    }

    // -------------------------------------------------------------------------
    // Epoch helpers
    // -------------------------------------------------------------------------

    function currentEpochId() public view returns (uint256) {
        if (block.timestamp < genesisTimestamp) return 0;
        return (block.timestamp - genesisTimestamp) / EPOCH_DURATION;
    }

    function epochStart(uint256 epochId) public view returns (uint256) {
        return genesisTimestamp + epochId * EPOCH_DURATION;
    }

    function epochEnd(uint256 epochId) public view returns (uint256) {
        return genesisTimestamp + (epochId + 1) * EPOCH_DURATION;
    }

    // -------------------------------------------------------------------------
    // Staking: PSRE
    // -------------------------------------------------------------------------

    /**
     * @notice Stake PSRE tokens.
     *         Settles all finalized epochs before updating balance (preserves
     *         the invariant that balance during past epochs = balance at settlement).
     */
    function stakePSRE(uint256 amount) external nonReentrant {
        require(amount > 0, "StakingVault: zero amount");
        _settleFinishedEpochs(msg.sender);
        IERC20(psre).safeTransferFrom(msg.sender, address(this), amount);
        userStakes[msg.sender].psreBalance += amount;
        totalPSREStaked += amount;
        emit PSREStaked(msg.sender, amount);
    }

    /**
     * @notice Unstake PSRE tokens.
     *         Settles all finalized epochs before updating balance.
     */
    function unstakePSRE(uint256 amount) external nonReentrant {
        require(amount > 0, "StakingVault: zero amount");
        require(userStakes[msg.sender].psreBalance >= amount, "StakingVault: insufficient balance");
        _settleFinishedEpochs(msg.sender);
        userStakes[msg.sender].psreBalance -= amount;
        totalPSREStaked -= amount;
        IERC20(psre).safeTransfer(msg.sender, amount);
        emit PSREUnstaked(msg.sender, amount);
    }

    // -------------------------------------------------------------------------
    // Staking: LP tokens
    // -------------------------------------------------------------------------

    /**
     * @notice Stake LP tokens.
     *         Settles all finalized epochs before updating balance.
     */
    function stakeLP(uint256 amount) external nonReentrant {
        require(amount > 0, "StakingVault: zero amount");
        _settleFinishedEpochs(msg.sender);
        IERC20(lpToken).safeTransferFrom(msg.sender, address(this), amount);
        userStakes[msg.sender].lpBalance += amount;
        totalLPStaked += amount;
        emit LPStaked(msg.sender, amount);
    }

    /**
     * @notice Unstake LP tokens.
     *         Settles all finalized epochs before updating balance.
     */
    function unstakeLP(uint256 amount) external nonReentrant {
        require(amount > 0, "StakingVault: zero amount");
        require(userStakes[msg.sender].lpBalance >= amount, "StakingVault: insufficient balance");
        _settleFinishedEpochs(msg.sender);
        userStakes[msg.sender].lpBalance -= amount;
        totalLPStaked -= amount;
        IERC20(lpToken).safeTransfer(msg.sender, amount);
        emit LPUnstaked(msg.sender, amount);
    }

    // -------------------------------------------------------------------------
    // snapshotEpoch — called by RewardEngine at epoch finalization
    // -------------------------------------------------------------------------

    /**
     * @notice Snapshot (finalize) an epoch's staking totals.
     *         Called only by RewardEngine immediately before distributeStakerRewards.
     *         Records the current total PSRE and LP staked as the epoch's basis
     *         for rewardPerToken computation.
     *
     * @param epochId The epoch being finalized.
     */
    function snapshotEpoch(uint256 epochId) external override onlyRewardEngine {
        require(!epochSnapshotted[epochId], "StakingVault: already snapshotted");
        epochTotalPSREStaked[epochId] = totalPSREStaked;
        epochTotalLPStaked[epochId]   = totalLPStaked;
        epochSnapshotted[epochId]     = true;
        emit EpochSnapshotted(epochId);
    }

    // -------------------------------------------------------------------------
    // distributeStakerRewards — called by RewardEngine after snapshotEpoch
    // -------------------------------------------------------------------------

    /**
     * @notice Fund the reward pools for a snapshotted epoch and compute rewardPerToken.
     *         Pulls `totalStakerPool` PSRE from the caller (RewardEngine must approve first).
     *
     * @param epochId         The snapshotted epoch to distribute rewards for.
     * @param totalStakerPool Total PSRE to split between PSRE stakers and LP stakers.
     */
    function distributeStakerRewards(uint256 epochId, uint256 totalStakerPool)
        external override onlyRewardEngine
    {
        require(epochSnapshotted[epochId],   "StakingVault: not snapshotted");
        require(!epochDistributed[epochId],  "StakingVault: already distributed");
        require(totalStakerPool > 0,         "StakingVault: zero pool");

        uint256 psrePool = totalStakerPool * psreSplit / PRECISION;
        uint256 lpPool_  = totalStakerPool * lpSplit   / PRECISION;

        epochPSREPool[epochId] = psrePool;
        epochLPPool[epochId]   = lpPool_;
        epochDistributed[epochId] = true;

        // Compute rewardPerToken (0 if no tokens staked — avoids division by zero).
        uint256 totalPSRE = epochTotalPSREStaked[epochId];
        uint256 totalLP   = epochTotalLPStaked[epochId];

        if (totalPSRE > 0) {
            epochPSRERewardPerToken[epochId] = (psrePool * REWARD_PRECISION) / totalPSRE;
        }
        if (totalLP > 0) {
            epochLPRewardPerToken[epochId] = (lpPool_ * REWARD_PRECISION) / totalLP;
        }

        // Advance lastFinalizedEpoch (epochs are finalized in order by RewardEngine).
        if (lastFinalizedEpoch == type(uint256).max || epochId > lastFinalizedEpoch) {
            lastFinalizedEpoch = epochId;
        }

        IERC20(psre).safeTransferFrom(msg.sender, address(this), totalStakerPool);

        emit StakerRewardsDistributed(epochId, psrePool, lpPool_);
    }

    // -------------------------------------------------------------------------
    // claimAll — settle all finalized epochs and pay pending rewards
    // -------------------------------------------------------------------------

    /**
     * @notice Settle all finalized epochs and transfer accumulated rewards.
     *         The "primary" claim interface for v3.
     */
    function claimAll() external nonReentrant {
        _settleFinishedEpochs(msg.sender);
        uint256 owed = pendingRewards[msg.sender];
        require(owed > 0, "StakingVault: nothing to claim");
        pendingRewards[msg.sender] = 0;
        IERC20(psre).safeTransfer(msg.sender, owed);
        emit RewardsClaimed(msg.sender, owed);
    }

    // -------------------------------------------------------------------------
    // claimStake — backward-compatible epoch-specific entry point
    // -------------------------------------------------------------------------

    /**
     * @notice Backward-compatible claim. Verifies that `epochId` is finalized,
     *         settles ALL finalized epochs, then pays all accumulated pending rewards.
     *
     *         Note: pays ALL pending rewards (not epoch-specific) because the
     *         v3 model accumulates them in a single pendingRewards bucket.
     *         This resolves the v2 claimStake paradox where passive stakers always
     *         received 0 (their contributions were never recorded before snapshot).
     *
     * @param epochId Any finalized epoch (used as proof that claiming is valid).
     */
    function claimStake(uint256 epochId) external nonReentrant {
        require(epochSnapshotted[epochId], "StakingVault: epoch not finalized");
        _settleFinishedEpochs(msg.sender);
        uint256 owed = pendingRewards[msg.sender];
        require(owed > 0, "StakingVault: nothing to claim");
        pendingRewards[msg.sender] = 0;
        IERC20(psre).safeTransfer(msg.sender, owed);
        emit RewardsClaimed(msg.sender, owed);
    }

    // -------------------------------------------------------------------------
    // checkpointUser — keeper compatibility
    // -------------------------------------------------------------------------

    /**
     * @notice Trigger settlement for any user. Kept for keeper/bot compatibility.
     *         In v3, settlement is lazy and automatic — keepers are not required
     *         to call this before epoch finalization, but may do so to pre-accrue.
     *
     * @param user The user to settle.
     */
    function checkpointUser(address user) external {
        _settleFinishedEpochs(user);
    }

    // -------------------------------------------------------------------------
    // Governance
    // -------------------------------------------------------------------------

    /**
     * @notice Update the PSRE/LP reward split. Both values must sum to PRECISION.
     */
    function setSplit(uint256 _psreSplit, uint256 _lpSplit) external onlyOwner {
        require(_psreSplit + _lpSplit == PRECISION, "StakingVault: splits must sum to 1e18");
        psreSplit = _psreSplit;
        lpSplit   = _lpSplit;
        emit SplitUpdated(_psreSplit, _lpSplit);
    }

    /**
     * @notice Set the RewardEngine address. One-time, immutable after setting.
     */
    function setRewardEngine(address _rewardEngine) external onlyOwner {
        require(!rewardEngineSet,            "StakingVault: already set");
        require(_rewardEngine != address(0), "StakingVault: zero addr");
        rewardEngine    = _rewardEngine;
        rewardEngineSet = true;
        emit RewardEngineSet(_rewardEngine);
    }

    // -------------------------------------------------------------------------
    // View helpers
    // -------------------------------------------------------------------------

    /// @notice Current staked balances for a user.
    function totalStakeOf(address user) external view returns (uint256 psreBal, uint256 lpBal) {
        return (userStakes[user].psreBalance, userStakes[user].lpBalance);
    }

    // -------------------------------------------------------------------------
    // Internal: lazy settlement of finalized epochs
    // -------------------------------------------------------------------------

    /**
     * @dev For each finalized epoch since the user's last settlement, compute
     *      the user's reward share and add it to pendingRewards[user].
     *
     *      Correctness invariant:
     *        This must be called BEFORE any balance change. At call time the
     *        user's stored balance == their balance during all unsettled epochs
     *        (because they haven't changed it since last settlement).
     *
     *      Gas cap:
     *        Iterates at most MAX_SETTLE_EPOCHS per call. If the user is further
     *        behind, they need multiple interactions to fully catch up (all pending
     *        rewards are preserved across calls via pendingRewards accumulation).
     *
     *      sentinel:
     *        lastFinalizedEpoch starts at type(uint256).max. We return early
     *        until at least one epoch has been distributed, preventing the
     *        lastSettledEpoch counter from advancing past unfinalised epochs.
     */
    function _settleFinishedEpochs(address user) internal {
        // No epochs finalized yet — nothing to settle.
        if (lastFinalizedEpoch == type(uint256).max) return;

        UserStake storage s = userStakes[user];
        uint256 startEpoch  = s.lastSettledEpoch;
        uint256 endEpoch    = lastFinalizedEpoch;

        // Already up to date.
        if (startEpoch > endEpoch) return;

        // Apply gas cap.
        uint256 cap = startEpoch + MAX_SETTLE_EPOCHS - 1;
        if (endEpoch > cap) endEpoch = cap;

        for (uint256 e = startEpoch; e <= endEpoch; e++) {
            // Skip epochs that were snapshotted but not distributed
            // (e.g., no staker allocation minted for that epoch).
            if (!epochDistributed[e]) continue;

            uint256 psreRpt = epochPSRERewardPerToken[e];
            uint256 lpRpt   = epochLPRewardPerToken[e];

            if (psreRpt > 0 && s.psreBalance > 0) {
                pendingRewards[user] += (s.psreBalance * psreRpt) / REWARD_PRECISION;
            }
            if (lpRpt > 0 && s.lpBalance > 0) {
                pendingRewards[user] += (s.lpBalance * lpRpt) / REWARD_PRECISION;
            }
        }

        s.lastSettledEpoch = endEpoch + 1;
    }
}
