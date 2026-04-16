// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IStakingVault.sol";

/**
 * @title StakingVault v3.1 -- Synthetix Cumulative Accumulator (O(1) Settlement)
 * @notice "Stake and forget." Users stake PSRE or LP tokens once and earn
 *         rewards across all finalized epochs automatically -- no checkpointing
 *         required before each epoch end.
 *
 *         Design (true Synthetix cumulative accumulator):
 *         - Two global accumulators: cumulativePSRERewardPerToken and
 *           cumulativeLPRewardPerToken, incremented by each epoch's rewardPerToken
 *           when distributeStakerRewards() is called.
 *         - Per-user paid accumulators: userPSRERewardPerTokenPaid and
 *           userLPRewardPerTokenPaid, set to the current global value after
 *           each settlement.
 *         - earned = balance x (cumulativeRPT - paidRPT) / REWARD_PRECISION
 *         - Settlement is O(1) -- one subtraction per asset. No loop, no gas cap.
 *
 *         Fixes BlockApex Issue #1 (retroactive theft + reward loss + insolvency):
 *         - Replaces the epoch-cursor loop (_settleFinishedEpochs) which had two
 *           compounding defects: lastSettledEpoch starting at 0 for new users
 *           (retroactive theft), and MAX_SETTLE_EPOCHS advancing the cursor past
 *           epochs with stale balances (reward loss / overpayment).
 *         - Cumulative model auto-initializes new users correctly: on first
 *           _updatePending() with balance=0, paidRPT is set to current cumulative,
 *           so only future epochs are credited.
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
    uint256 public constant REWARD_PRECISION = 1e36;

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

    uint256 public psreSplit = 0.5e18;
    uint256 public lpSplit   = 0.5e18;

    // -------------------------------------------------------------------------
    // Global staking counters -- updated on every stake / unstake
    // -------------------------------------------------------------------------

    uint256 public totalPSREStaked;
    uint256 public totalLPStaked;

    // -------------------------------------------------------------------------
    // Per-epoch state -- set at finalization time by RewardEngine
    // -------------------------------------------------------------------------

    /// @notice Total PSRE staked at the time snapshotEpoch(epochId) was called.
    mapping(uint256 => uint256) public epochTotalPSREStaked;

    /// @notice Total LP staked at the time snapshotEpoch(epochId) was called.
    mapping(uint256 => uint256) public epochTotalLPStaked;

    /// @notice PSRE reward per token for epoch (x REWARD_PRECISION).
    mapping(uint256 => uint256) public epochPSRERewardPerToken;

    /// @notice LP reward per token for epoch (x REWARD_PRECISION).
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
    uint256 public lastFinalizedEpoch = type(uint256).max;

    // -------------------------------------------------------------------------
    // Cumulative reward accumulators (Synthetix pattern, O(1) settlement)
    // Incremented by each epoch's rewardPerToken in distributeStakerRewards().
    // -------------------------------------------------------------------------

    /// @notice Running sum of all epochPSRERewardPerToken values distributed so far.
    uint256 public cumulativePSRERewardPerToken;

    /// @notice Running sum of all epochLPRewardPerToken values distributed so far.
    uint256 public cumulativeLPRewardPerToken;

    // -------------------------------------------------------------------------
    // Per-user state
    // -------------------------------------------------------------------------

    struct UserStake {
        uint256 psreBalance;
        uint256 lpBalance;
    }

    mapping(address => UserStake) public userStakes;

    /// @notice Cumulative PSRE rewardPerToken already credited to user at last update.
    mapping(address => uint256) public userPSRERewardPerTokenPaid;

    /// @notice Cumulative LP rewardPerToken already credited to user at last update.
    mapping(address => uint256) public userLPRewardPerTokenPaid;

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

    function stakePSRE(uint256 amount) external nonReentrant {
        require(amount > 0, "StakingVault: zero amount");
        _updatePending(msg.sender);
        IERC20(psre).safeTransferFrom(msg.sender, address(this), amount);
        userStakes[msg.sender].psreBalance += amount;
        totalPSREStaked += amount;
        emit PSREStaked(msg.sender, amount);
    }

    function unstakePSRE(uint256 amount) external nonReentrant {
        require(amount > 0, "StakingVault: zero amount");
        require(userStakes[msg.sender].psreBalance >= amount, "StakingVault: insufficient balance");
        _updatePending(msg.sender);
        userStakes[msg.sender].psreBalance -= amount;
        totalPSREStaked -= amount;
        IERC20(psre).safeTransfer(msg.sender, amount);
        emit PSREUnstaked(msg.sender, amount);
    }

    // -------------------------------------------------------------------------
    // Staking: LP tokens
    // -------------------------------------------------------------------------

    function stakeLP(uint256 amount) external nonReentrant {
        require(amount > 0, "StakingVault: zero amount");
        _updatePending(msg.sender);
        IERC20(lpToken).safeTransferFrom(msg.sender, address(this), amount);
        userStakes[msg.sender].lpBalance += amount;
        totalLPStaked += amount;
        emit LPStaked(msg.sender, amount);
    }

    function unstakeLP(uint256 amount) external nonReentrant {
        require(amount > 0, "StakingVault: zero amount");
        require(userStakes[msg.sender].lpBalance >= amount, "StakingVault: insufficient balance");
        _updatePending(msg.sender);
        userStakes[msg.sender].lpBalance -= amount;
        totalLPStaked -= amount;
        IERC20(lpToken).safeTransfer(msg.sender, amount);
        emit LPUnstaked(msg.sender, amount);
    }

    // -------------------------------------------------------------------------
    // snapshotEpoch -- called by RewardEngine at epoch finalization
    // -------------------------------------------------------------------------

    /**
     * @notice Snapshot (finalize) an epoch's staking totals.
     *         Records the current total PSRE and LP staked as the epoch's basis
     *         for rewardPerToken computation.
     */
    function snapshotEpoch(uint256 epochId) external override onlyRewardEngine {
        require(!epochSnapshotted[epochId], "StakingVault: already snapshotted");
        epochTotalPSREStaked[epochId] = totalPSREStaked;
        epochTotalLPStaked[epochId]   = totalLPStaked;
        epochSnapshotted[epochId]     = true;
        emit EpochSnapshotted(epochId);
    }

    // -------------------------------------------------------------------------
    // distributeStakerRewards -- called by RewardEngine after snapshotEpoch
    // -------------------------------------------------------------------------

    /**
     * @notice Fund the reward pools for a snapshotted epoch and compute rewardPerToken.
     *         Pulls `totalStakerPool` PSRE from the caller (RewardEngine must approve first).
     *         If no PSRE stakers exist, epochPSRERewardPerToken stays 0.
     *         If no LP stakers exist, epochLPRewardPerToken stays 0.
     *         Unclaimed pool tokens remain in the contract.
     *
     * @param epochId         The snapshotted epoch to distribute rewards for.
     * @param totalStakerPool Total PSRE to split between PSRE stakers and LP stakers.
     */
    function distributeStakerRewards(uint256 epochId, uint256 totalStakerPool)
        external override onlyRewardEngine
    {
        require(epochSnapshotted[epochId],  "StakingVault: not snapshotted");
        require(!epochDistributed[epochId], "StakingVault: already distributed");
        require(totalStakerPool > 0, "StakingVault: zero pool");

        uint256 totalPSREcheck = epochTotalPSREStaked[epochId];
        uint256 totalLPcheck   = epochTotalLPStaked[epochId];

        // No stakers at all: mark distributed, don't pull tokens.
        // Pool stays in caller (RewardEngine) — use sweepUnclaimedPool() if needed.
        if (totalPSREcheck == 0 && totalLPcheck == 0) {
            epochDistributed[epochId] = true;
            if (lastFinalizedEpoch == type(uint256).max || epochId > lastFinalizedEpoch) {
                lastFinalizedEpoch = epochId;
            }
            emit StakerRewardsDistributed(epochId, 0, 0);
            return;
        }

        uint256 psrePool = (totalStakerPool * psreSplit) / PRECISION;
        uint256 lpPool_  = (totalStakerPool * lpSplit)   / PRECISION;

        epochPSREPool[epochId] = psrePool;
        epochLPPool[epochId]   = lpPool_;
        epochDistributed[epochId] = true;

        uint256 totalPSRE = epochTotalPSREStaked[epochId];
        uint256 totalLP   = epochTotalLPStaked[epochId];

        // Compute rewardPerToken (0 if no tokens staked; avoids division by zero)
        // and update the global cumulative accumulators used for O(1) settlement.
        if (totalPSRE > 0) {
            uint256 psreRpt = (psrePool * REWARD_PRECISION) / totalPSRE;
            epochPSRERewardPerToken[epochId]  = psreRpt;
            cumulativePSRERewardPerToken      += psreRpt;
        }
        if (totalLP > 0) {
            uint256 lpRpt = (lpPool_ * REWARD_PRECISION) / totalLP;
            epochLPRewardPerToken[epochId]    = lpRpt;
            cumulativeLPRewardPerToken        += lpRpt;
        }

        // Advance lastFinalizedEpoch.
        if (lastFinalizedEpoch == type(uint256).max || epochId > lastFinalizedEpoch) {
            lastFinalizedEpoch = epochId;
        }

        // Pull funds from RewardEngine into this vault; unclaimed pools remain here.
        IERC20(psre).safeTransferFrom(msg.sender, address(this), totalStakerPool);

        emit StakerRewardsDistributed(epochId, psrePool, lpPool_);
    }

    // -------------------------------------------------------------------------
    // sweepUnclaimedPool -- recover stranded sub-pool rewards (governance)
    // -------------------------------------------------------------------------

    /**
     * @notice Recover any unclaimed staking rewards from an epoch where one or both
     *         sub-pools had no stakers (rewardPerToken = 0). Only callable by owner.
     *         Sends unclaimed portion to `to` (typically treasury or next-epoch pool).
     * @param epochId  The epoch to sweep.
     * @param to       Recipient address.
     */
    function sweepUnclaimedPool(uint256 epochId, address to) external onlyOwner {
        require(epochDistributed[epochId], "StakingVault: not distributed");
        require(to != address(0),          "StakingVault: zero recipient");

        uint256 unclaimed = 0;
        if (epochPSRERewardPerToken[epochId] == 0 && epochPSREPool[epochId] > 0) {
            unclaimed += epochPSREPool[epochId];
            epochPSREPool[epochId] = 0;
        }
        if (epochLPRewardPerToken[epochId] == 0 && epochLPPool[epochId] > 0) {
            unclaimed += epochLPPool[epochId];
            epochLPPool[epochId] = 0;
        }

        if (unclaimed > 0) {
            IERC20(psre).safeTransfer(to, unclaimed);
        }
    }

    // -------------------------------------------------------------------------
    // claimAll -- settle all finalized epochs and pay pending rewards
    // -------------------------------------------------------------------------

    /**
     * @notice Settle all finalized epochs and transfer accumulated rewards.
     *         The "primary" claim interface for v3.
     */
    function claimAll() external nonReentrant {
        _updatePending(msg.sender);
        uint256 owed = pendingRewards[msg.sender];
        require(owed > 0, "StakingVault: nothing to claim");
        pendingRewards[msg.sender] = 0;
        IERC20(psre).safeTransfer(msg.sender, owed);
        emit RewardsClaimed(msg.sender, owed);
    }

    // -------------------------------------------------------------------------
    // claimStake -- backward-compatible epoch-specific entry point
    // -------------------------------------------------------------------------

    /**
     * @notice Backward-compatible claim. Verifies that `epochId` is finalized,
     *         settles ALL finalized epochs, then pays all accumulated pending rewards.
     *         Resolves the v2 claimStake paradox where passive stakers always received 0.
     *
     * @param epochId Any finalized epoch (used as proof that claiming is valid).
     */
    function claimStake(uint256 epochId) external nonReentrant {
        require(epochSnapshotted[epochId], "StakingVault: epoch not finalized");
        _updatePending(msg.sender);
        uint256 owed = pendingRewards[msg.sender];
        require(owed > 0, "StakingVault: nothing to claim");
        pendingRewards[msg.sender] = 0;
        IERC20(psre).safeTransfer(msg.sender, owed);
        emit RewardsClaimed(msg.sender, owed);
    }

    // -------------------------------------------------------------------------
    // checkpointUser -- keeper compatibility
    // -------------------------------------------------------------------------

    /**
     * @notice Trigger settlement for any user. Kept for keeper/bot compatibility.
     *         In v3, settlement is lazy and automatic -- keepers are not required
     *         to call this before epoch finalization.
     */
    function checkpointUser(address user) external {
        _updatePending(user);
    }

    // -------------------------------------------------------------------------
    // Governance
    // -------------------------------------------------------------------------

    function setSplit(uint256 _psreSplit, uint256 _lpSplit) external onlyOwner {
        require(_psreSplit + _lpSplit == PRECISION, "StakingVault: splits must sum to 1e18");
        psreSplit = _psreSplit;
        lpSplit   = _lpSplit;
        emit SplitUpdated(_psreSplit, _lpSplit);
    }

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

    function totalStakeOf(address user) external view returns (uint256 psreBal, uint256 lpBal) {
        return (userStakes[user].psreBalance, userStakes[user].lpBalance);
    }

    // -------------------------------------------------------------------------
    // Internal: O(1) Synthetix-style pending reward update
    // -------------------------------------------------------------------------

    /**
     * @dev Update pendingRewards[user] using the global cumulative accumulators.
     *      O(1) regardless of how many epochs have passed. No loop, no gas cap.
     *
     *      Must be called BEFORE any balance change. The user's stored balance
     *      reflects their actual stake for all epochs since their last update.
     *
     *      New users: on first call with balance=0, earned=0 and paidRPT is set to
     *      the current cumulative, so only future epochs are credited. This prevents
     *      the retroactive theft exploit (BlockApex Issue #1 Path 1).
     */
    function _updatePending(address user) internal {
        UserStake storage s = userStakes[user];

        uint256 psreEarned = 0;
        uint256 lpEarned   = 0;

        if (s.psreBalance > 0) {
            psreEarned = (s.psreBalance *
                (cumulativePSRERewardPerToken - userPSRERewardPerTokenPaid[user]))
                / REWARD_PRECISION;
        }
        if (s.lpBalance > 0) {
            lpEarned = (s.lpBalance *
                (cumulativeLPRewardPerToken - userLPRewardPerTokenPaid[user]))
                / REWARD_PRECISION;
        }

        pendingRewards[user]              += psreEarned + lpEarned;
        userPSRERewardPerTokenPaid[user]   = cumulativePSRERewardPerToken;
        userLPRewardPerTokenPaid[user]     = cumulativeLPRewardPerToken;
    }
}
