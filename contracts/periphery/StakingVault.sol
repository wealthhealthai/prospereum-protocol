// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IStakingVault.sol";

/**
 * @title StakingVault v2.0 — Epoch-Aware Checkpointing
 * @notice Time-weighted staking for PSRE tokens and PSRE/USDC LP tokens.
 *         Implements two separate reward sub-pools within the 30% staker allocation:
 *           - PSRE pool: rewards for PSRE stakers
 *           - LP pool:   rewards for LP token stakers
 *         Default split: 50% / 50%, governance-adjustable via setSplit().
 *
 *         Epoch-aware checkpointing (Synthetix-style):
 *           - _checkpoint() attributes time-weighted balance to each epoch correctly
 *           - No cross-epoch contamination: time is attributed to the epoch it was earned in
 *           - MAX_CHECKPOINT_EPOCHS (52) cap prevents gas exhaustion for dormant stakers
 *
 *         Pull-based claiming: users call claimStake(epochId) after epoch is snapshotted
 *         and rewards are distributed by RewardEngine via distributeStakerRewards().
 *
 * @dev Fixes #5, #9, #13, #15, #20 from BlockApex audit:
 *      - #5: epoch boundary contamination → fixed by per-epoch time attribution
 *      - #9: stakeTime cross-epoch accumulation → fixed by epoch-aware _checkpoint
 *      - #13: single global totalStakeTime → fixed by per-epoch mappings
 *      - #15: recordStakeTime() manual injection → removed, automatic checkpointing
 *      - #20: accStakeTime partial deduction issue → removed, new epoch-attributed model
 */
contract StakingVault is ReentrancyGuard, IStakingVault {
    using SafeERC20 for IERC20;

    // ─────────────────────────────────────────────────────────────────────────
    // Constants
    // ─────────────────────────────────────────────────────────────────────────

    uint256 public constant EPOCH_DURATION = 7 days;

    /// @notice Governance precision (1e18 = 100%).
    uint256 public constant PRECISION = 1e18;

    /// @notice Maximum epochs to look back during _checkpoint (gas safety).
    ///         Stakers who go dormant for >52 epochs forfeit contributions for skipped epochs.
    uint256 public constant MAX_CHECKPOINT_EPOCHS = 52;

    // ─────────────────────────────────────────────────────────────────────────
    // Immutables
    // ─────────────────────────────────────────────────────────────────────────

    address public immutable psre;
    address public immutable lpToken;
    uint256 public immutable genesisTimestamp;

    // ─────────────────────────────────────────────────────────────────────────
    // Sub-pool split (within the 30% staker allocation)
    // psreSplit + lpSplit must always == PRECISION (1e18)
    // ─────────────────────────────────────────────────────────────────────────

    uint256 public psreSplit = 0.5e18;   // 50% to PSRE stakers
    uint256 public lpSplit   = 0.5e18;   // 50% to LP stakers

    // ─────────────────────────────────────────────────────────────────────────
    // Per-user staking state
    // ─────────────────────────────────────────────────────────────────────────

    struct UserStake {
        uint256 psreBalance;              // PSRE tokens currently staked
        uint256 lpBalance;                // LP tokens currently staked
        uint256 lastCheckpointTimestamp;  // timestamp of last _checkpoint call
        uint256 lastCheckpointEpoch;      // epoch of last _checkpoint call
    }

    mapping(address => UserStake) public userStakes;

    // ─────────────────────────────────────────────────────────────────────────
    // Per-epoch time-weighted totals
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Total PSRE stakeTime in epoch e = Σ(psreBalance × seconds) across all stakers.
    mapping(uint256 => uint256) public totalPSREStakedTime;

    /// @notice Total LP stakeTime in epoch e = Σ(lpBalance × seconds) across all stakers.
    mapping(uint256 => uint256) public totalLPStakedTime;

    /// @notice Per-user PSRE stakeTime contribution to epoch e.
    mapping(uint256 => mapping(address => uint256)) public userPSREStakedTime;

    /// @notice Per-user LP stakeTime contribution to epoch e.
    mapping(uint256 => mapping(address => uint256)) public userLPStakedTime;

    // ─────────────────────────────────────────────────────────────────────────
    // Epoch reward pools (set by RewardEngine via distributeStakerRewards)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice PSRE reward pool for epoch e (PSRE-pool portion of staker allocation).
    mapping(uint256 => uint256) public epochPSREPool;

    /// @notice LP reward pool for epoch e (LP-pool portion of staker allocation).
    mapping(uint256 => uint256) public epochLPPool;

    // ─────────────────────────────────────────────────────────────────────────
    // Claim tracking & snapshot state
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice True once a user has claimed rewards for an epoch (prevents double-claim).
    mapping(uint256 => mapping(address => bool)) public hasClaimed;

    /// @notice True once snapshotEpoch() has been called for an epoch.
    ///         After snapshotting, no new contributions are accepted for that epoch.
    mapping(uint256 => bool) public epochSnapshotted;

    // ─────────────────────────────────────────────────────────────────────────
    // Governance & access control
    // ─────────────────────────────────────────────────────────────────────────

    address public owner;
    address public rewardEngine;
    bool    private rewardEngineSet;

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    event PSREStaked(address indexed user, uint256 amount);
    event PSREUnstaked(address indexed user, uint256 amount);
    event LPStaked(address indexed user, uint256 amount);
    event LPUnstaked(address indexed user, uint256 amount);
    event EpochSnapshotted(uint256 indexed epochId);
    event StakerRewardsDistributed(uint256 indexed epochId, uint256 psrePool, uint256 lpPool);
    event StakeRewardClaimed(address indexed user, uint256 indexed epochId,
                              uint256 psreReward, uint256 lpReward);
    event SplitUpdated(uint256 psreSplit_, uint256 lpSplit_);
    event RewardEngineSet(address indexed rewardEngine_);

    // ─────────────────────────────────────────────────────────────────────────
    // Modifiers
    // ─────────────────────────────────────────────────────────────────────────

    modifier onlyOwner() {
        require(msg.sender == owner, "StakingVault: not owner");
        _;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────

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

    // ─────────────────────────────────────────────────────────────────────────
    // Epoch helpers
    // ─────────────────────────────────────────────────────────────────────────

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

    // ─────────────────────────────────────────────────────────────────────────
    // Staking: PSRE
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Stake PSRE tokens. Checkpoints the caller before updating balance.
     */
    function stakePSRE(uint256 amount) external nonReentrant {
        require(amount > 0, "StakingVault: zero amount");
        _checkpoint(msg.sender);
        IERC20(psre).safeTransferFrom(msg.sender, address(this), amount);
        userStakes[msg.sender].psreBalance += amount;
        emit PSREStaked(msg.sender, amount);
    }

    /**
     * @notice Unstake PSRE tokens. Checkpoints the caller before updating balance.
     */
    function unstakePSRE(uint256 amount) external nonReentrant {
        require(amount > 0, "StakingVault: zero amount");
        require(userStakes[msg.sender].psreBalance >= amount, "StakingVault: insufficient balance");
        _checkpoint(msg.sender);
        userStakes[msg.sender].psreBalance -= amount;
        IERC20(psre).safeTransfer(msg.sender, amount);
        emit PSREUnstaked(msg.sender, amount);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Staking: LP tokens
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Stake LP tokens. Checkpoints the caller before updating balance.
     */
    function stakeLP(uint256 amount) external nonReentrant {
        require(amount > 0, "StakingVault: zero amount");
        _checkpoint(msg.sender);
        IERC20(lpToken).safeTransferFrom(msg.sender, address(this), amount);
        userStakes[msg.sender].lpBalance += amount;
        emit LPStaked(msg.sender, amount);
    }

    /**
     * @notice Unstake LP tokens. Checkpoints the caller before updating balance.
     */
    function unstakeLP(uint256 amount) external nonReentrant {
        require(amount > 0, "StakingVault: zero amount");
        require(userStakes[msg.sender].lpBalance >= amount, "StakingVault: insufficient balance");
        _checkpoint(msg.sender);
        userStakes[msg.sender].lpBalance -= amount;
        IERC20(lpToken).safeTransfer(msg.sender, amount);
        emit LPUnstaked(msg.sender, amount);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // snapshotEpoch — called by RewardEngine at epoch finalization
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Snapshot (finalize) an epoch. Called only by RewardEngine.
     *         After this call, no new contributions are accepted for epochId.
     *         Must be called before distributeStakerRewards for the same epoch.
     */
    function snapshotEpoch(uint256 epochId) external override {
        require(msg.sender == rewardEngine,   "StakingVault: only rewardEngine");
        require(!epochSnapshotted[epochId],   "StakingVault: already snapshotted");
        epochSnapshotted[epochId] = true;
        emit EpochSnapshotted(epochId);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // distributeStakerRewards — called by RewardEngine after snapshotEpoch
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Fund the reward pools for a finalized epoch.
     *         Pulls `totalStakerPool` PSRE from RewardEngine (caller must have approved this
     *         contract for at least `totalStakerPool` before calling).
     *         Splits the pool between PSRE stakers (psreSplit) and LP stakers (lpSplit).
     *
     * @param epochId         The epoch to fund rewards for.
     * @param totalStakerPool Total PSRE to distribute across both sub-pools.
     */
    function distributeStakerRewards(uint256 epochId, uint256 totalStakerPool)
        external override
    {
        require(msg.sender == rewardEngine,                              "StakingVault: only rewardEngine");
        require(epochSnapshotted[epochId],                               "StakingVault: not snapshotted");
        require(epochPSREPool[epochId] == 0 && epochLPPool[epochId] == 0, "StakingVault: already distributed");
        require(totalStakerPool > 0,                                     "StakingVault: zero pool");

        epochPSREPool[epochId] = totalStakerPool * psreSplit / PRECISION;
        epochLPPool[epochId]   = totalStakerPool * lpSplit   / PRECISION;

        IERC20(psre).safeTransferFrom(rewardEngine, address(this), totalStakerPool);

        emit StakerRewardsDistributed(epochId, epochPSREPool[epochId], epochLPPool[epochId]);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // claimStake — user pulls their reward for a specific epoch
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Claim staking rewards for a finalized epoch.
     *         Caller must have stakeTime recorded for epochId (via prior checkpoints
     *         made BEFORE the epoch was snapshotted).
     *
     *         Calls _checkpoint to finalize any pending contributions for the current
     *         (ongoing) epoch, but contributions to already-snapshotted epochs are ignored.
     *
     * @param epochId The finalized epoch to claim rewards for.
     */
    function claimStake(uint256 epochId) external nonReentrant {
        require(epochSnapshotted[epochId],              "StakingVault: epoch not finalized");
        require(!hasClaimed[epochId][msg.sender],       "StakingVault: already claimed");

        // Checkpoint to finalize contributions for any ongoing (non-snapshotted) epochs.
        // Contributions to already-snapshotted epochs are blocked inside _addContribution.
        _checkpoint(msg.sender);

        uint256 psreReward = 0;
        uint256 lpReward   = 0;

        uint256 userPSRE  = userPSREStakedTime[epochId][msg.sender];
        uint256 totalPSRE = totalPSREStakedTime[epochId];
        if (totalPSRE > 0 && userPSRE > 0) {
            psreReward = epochPSREPool[epochId] * userPSRE / totalPSRE;
        }

        uint256 userLP  = userLPStakedTime[epochId][msg.sender];
        uint256 totalLP = totalLPStakedTime[epochId];
        if (totalLP > 0 && userLP > 0) {
            lpReward = epochLPPool[epochId] * userLP / totalLP;
        }

        uint256 total = psreReward + lpReward;
        require(total > 0, "StakingVault: nothing to claim");

        hasClaimed[epochId][msg.sender] = true;
        IERC20(psre).safeTransfer(msg.sender, total);

        emit StakeRewardClaimed(msg.sender, epochId, psreReward, lpReward);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // checkpointUser — anyone can trigger a checkpoint for any user
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Externally trigger a checkpoint for any user.
     *         Useful for keepers to finalize staker contributions just before
     *         RewardEngine calls snapshotEpoch(), ensuring contributions are captured.
     *
     * @param user  The user to checkpoint.
     */
    function checkpointUser(address user) external {
        _checkpoint(user);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Governance
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Update the PSRE/LP split within the staker allocation.
     *         Both splits must sum to exactly PRECISION (1e18 = 100%).
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
        require(!rewardEngineSet,              "StakingVault: already set");
        require(_rewardEngine != address(0),   "StakingVault: zero addr");
        rewardEngine    = _rewardEngine;
        rewardEngineSet = true;
        emit RewardEngineSet(_rewardEngine);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // View helpers
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Current staked balances for a user.
    function totalStakeOf(address user) external view returns (uint256 psreBal, uint256 lpBal) {
        return (userStakes[user].psreBalance, userStakes[user].lpBalance);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal: epoch-aware checkpointing
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @dev Core checkpoint logic. Attributes time-weighted balance to the correct epoch(s)
     *      since the last checkpoint, respecting epoch boundaries.
     *
     *      First interaction: records timestamp only (no contribution yet, as no time has elapsed).
     *
     *      Subsequent calls: attributes `balance × elapsed` to each epoch proportionally.
     *      If the user spans multiple epochs since last checkpoint, each epoch gets its
     *      correct slice (no cross-epoch contamination).
     *
     *      Gas cap: if toEpoch - fromEpoch > MAX_CHECKPOINT_EPOCHS, the oldest epochs
     *      are skipped (user forfeits those contributions). Prevents gas DoS for dormant stakers.
     *
     *      Post-snapshot guard: contributions to already-snapshotted epochs are silently
     *      dropped inside _addContribution, preventing post-snapshot inflation.
     */
    function _checkpoint(address user) internal {
        UserStake storage s = userStakes[user];

        // First interaction: just record the starting timestamp.
        // No elapsed time yet, so no stakeTime to attribute.
        if (s.lastCheckpointTimestamp == 0) {
            s.lastCheckpointTimestamp = block.timestamp;
            s.lastCheckpointEpoch     = currentEpochId();
            return;
        }

        uint256 fromTime  = s.lastCheckpointTimestamp;
        uint256 fromEpoch = s.lastCheckpointEpoch;
        uint256 toTime    = block.timestamp;
        uint256 toEpoch   = currentEpochId();

        // Same block — nothing to do.
        if (fromTime >= toTime) {
            return;
        }

        // Cap epoch range to MAX_CHECKPOINT_EPOCHS to prevent gas exhaustion.
        // User forfeits stakeTime contributions for epochs beyond the cap.
        if (toEpoch > fromEpoch + MAX_CHECKPOINT_EPOCHS) {
            fromEpoch = toEpoch - MAX_CHECKPOINT_EPOCHS;
            fromTime  = epochStart(fromEpoch);
        }

        uint256 psreBal = s.psreBalance;
        uint256 lpBal   = s.lpBalance;

        if (fromEpoch == toEpoch) {
            // Simple case: all elapsed time is within the same epoch.
            _addContribution(fromEpoch, user, psreBal, lpBal, toTime - fromTime);
        } else {
            // Straddles multiple epochs — attribute time to each epoch correctly.

            // 1. Remainder of fromEpoch (fromTime → epochEnd(fromEpoch))
            uint256 endOfFrom = epochEnd(fromEpoch);
            if (endOfFrom > fromTime) {
                _addContribution(fromEpoch, user, psreBal, lpBal, endOfFrom - fromTime);
            }

            // 2. Full epochs between fromEpoch+1 and toEpoch-1
            for (uint256 e = fromEpoch + 1; e < toEpoch; e++) {
                _addContribution(e, user, psreBal, lpBal, EPOCH_DURATION);
            }

            // 3. Partial current epoch (epochStart(toEpoch) → toTime)
            uint256 startOfTo = epochStart(toEpoch);
            if (toTime > startOfTo) {
                _addContribution(toEpoch, user, psreBal, lpBal, toTime - startOfTo);
            }
        }

        s.lastCheckpointTimestamp = toTime;
        s.lastCheckpointEpoch     = toEpoch;
    }

    /**
     * @dev Record a user's balance × elapsed contribution to an epoch.
     *      Silently skips already-snapshotted epochs (post-snapshot manipulation guard).
     */
    function _addContribution(
        uint256 epochId,
        address user,
        uint256 psreBal,
        uint256 lpBal,
        uint256 elapsed
    ) internal {
        // Post-snapshot guard: contributions to finalized epochs are rejected.
        if (epochSnapshotted[epochId]) return;

        if (psreBal > 0) {
            uint256 contrib = psreBal * elapsed;
            userPSREStakedTime[epochId][user] += contrib;
            totalPSREStakedTime[epochId]      += contrib;
        }
        if (lpBal > 0) {
            uint256 contrib = lpBal * elapsed;
            userLPStakedTime[epochId][user] += contrib;
            totalLPStakedTime[epochId]      += contrib;
        }
    }
}
