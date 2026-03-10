// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title StakingVault
 * @notice Time-weighted staking for PSRE tokens and PSRE/USDC LP tokens.
 *         Staking rewards are pull-based: RewardEngine computes owed amounts
 *         using stakeTimeOf() and totalStakeTime() snapshots.
 *
 * @dev Dev Spec v2.3, Section 2.4 and 7
 *      - PSRE staking and LP staking treated equivalently (no weighting multiplier)
 *      - stakeTime = stakeAmount × stakingDuration (in token-seconds)
 *      - Snapshots are taken at epoch boundaries for reward computation
 *      - Pull-based: RewardEngine calls claimStake(epochId) on behalf of user
 *        (or users call directly)
 */
contract StakingVault is ReentrancyGuard, Pausable, Ownable2Step {
    using SafeERC20 for IERC20;

    // ─────────────────────────────────────────────────────────────────────────
    // Constants
    // ─────────────────────────────────────────────────────────────────────────

    uint256 public constant EPOCH_DURATION = 7 days;

    // ─────────────────────────────────────────────────────────────────────────
    // Immutables
    // ─────────────────────────────────────────────────────────────────────────

    address public immutable psre;
    address public immutable lpToken;
    uint256 public immutable genesisTimestamp;

    // ─────────────────────────────────────────────────────────────────────────
    // Per-user state
    // ─────────────────────────────────────────────────────────────────────────

    struct UserStake {
        uint256 psreBalance;          // PSRE tokens staked
        uint256 lpBalance;            // LP tokens staked
        uint256 lastUpdateTimestamp;  // last time accStakeTime was updated
        uint256 accStakeTime;         // token-seconds accumulated in current epoch
    }

    mapping(address => UserStake) public userStakes;

    // ─────────────────────────────────────────────────────────────────────────
    // Epoch snapshots
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Total stakeTime accumulated by all users in a finalized epoch.
    mapping(uint256 => uint256) public totalStakeTimeByEpoch;

    /// @notice Per-user stakeTime in a finalized epoch.
    mapping(uint256 => mapping(address => uint256)) public userStakeTimeByEpoch;

    /// @notice Tracks the epoch each user's accumulator was last snapshotted.
    mapping(address => uint256) public userLastSnapshotEpoch;

    /// @notice Running total stakeTime for the current (unfinalized) epoch.
    uint256 public currentEpochTotalStakeTime;

    /// @notice Tracks which epochs have already been snapshotted (prevents re-snapshot).
    /// @dev Replaces the broken `lastSnapshotEpoch == 0` guard that allowed epoch 0 re-snapshot.
    mapping(uint256 => bool) public epochSnapshotted;

    // ─────────────────────────────────────────────────────────────────────────
    // RewardEngine
    // ─────────────────────────────────────────────────────────────────────────

    address public rewardEngine;

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    event PSREStaked(address indexed user, uint256 amount);
    event PSREUnstaked(address indexed user, uint256 amount);
    event LPStaked(address indexed user, uint256 amount);
    event LPUnstaked(address indexed user, uint256 amount);
    event EpochSnapshotted(uint256 indexed epochId, uint256 totalStakeTime);
    event RewardEngineSet(address indexed rewardEngine);

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────

    constructor(
        address _psre,
        address _lpToken,
        uint256 _genesisTimestamp,
        address _admin
    ) Ownable(_admin) {
        require(_psre      != address(0), "StakingVault: zero psre");
        require(_lpToken   != address(0), "StakingVault: zero lp");
        require(_genesisTimestamp > 0,    "StakingVault: zero genesis");

        psre             = _psre;
        lpToken          = _lpToken;
        genesisTimestamp = _genesisTimestamp;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Admin
    // ─────────────────────────────────────────────────────────────────────────

    function setRewardEngine(address _rewardEngine) external onlyOwner {
        require(_rewardEngine != address(0), "StakingVault: zero rewardEngine");
        require(rewardEngine  == address(0), "StakingVault: already set");
        rewardEngine = _rewardEngine;
        emit RewardEngineSet(_rewardEngine);
    }

    function pause()   external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // ─────────────────────────────────────────────────────────────────────────
    // Epoch helpers
    // ─────────────────────────────────────────────────────────────────────────

    function currentEpochId() public view returns (uint256) {
        if (block.timestamp < genesisTimestamp) return 0;
        return (block.timestamp - genesisTimestamp) / EPOCH_DURATION;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Staking: PSRE
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Stake PSRE tokens.
     * @param amount Amount of PSRE to stake.
     */
    function stakePSRE(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "StakingVault: zero amount");
        _checkpointUser(msg.sender);
        IERC20(psre).safeTransferFrom(msg.sender, address(this), amount);
        userStakes[msg.sender].psreBalance += amount;
        emit PSREStaked(msg.sender, amount);
    }

    /**
     * @notice Unstake PSRE tokens.
     * @param amount Amount of PSRE to unstake.
     */
    function unstakePSRE(uint256 amount) external nonReentrant {
        require(amount > 0, "StakingVault: zero amount");
        require(userStakes[msg.sender].psreBalance >= amount, "StakingVault: insufficient PSRE");
        _checkpointUser(msg.sender);
        userStakes[msg.sender].psreBalance -= amount;
        IERC20(psre).safeTransfer(msg.sender, amount);
        emit PSREUnstaked(msg.sender, amount);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Staking: LP tokens
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Stake LP tokens. Treated equivalently to PSRE for stakeTime accounting.
     *         stakeTime = lpAmount × duration (no weighting multiplier per spec §2.4).
     * @param amount Amount of LP tokens to stake.
     */
    function stakeLP(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "StakingVault: zero amount");
        _checkpointUser(msg.sender);
        IERC20(lpToken).safeTransferFrom(msg.sender, address(this), amount);
        userStakes[msg.sender].lpBalance += amount;
        emit LPStaked(msg.sender, amount);
    }

    /**
     * @notice Unstake LP tokens.
     * @param amount Amount of LP tokens to unstake.
     */
    function unstakeLP(uint256 amount) external nonReentrant {
        require(amount > 0, "StakingVault: zero amount");
        require(userStakes[msg.sender].lpBalance >= amount, "StakingVault: insufficient LP");
        _checkpointUser(msg.sender);
        userStakes[msg.sender].lpBalance -= amount;
        IERC20(lpToken).safeTransfer(msg.sender, amount);
        emit LPUnstaked(msg.sender, amount);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Epoch snapshot (called by RewardEngine at finalization)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Snapshot the current epoch's total stakeTime.
     *         Called by RewardEngine during finalizeEpoch().
     *         Commits currentEpochTotalStakeTime to totalStakeTimeByEpoch[epochId].
     *
     * @param epochId The epoch being finalized.
     */
    function snapshotEpoch(uint256 epochId) external {
        require(msg.sender == rewardEngine,      "StakingVault: only rewardEngine");
        require(!epochSnapshotted[epochId],      "StakingVault: already snapshotted");
        require(currentEpochId() > epochId,      "StakingVault: epoch not ended");

        epochSnapshotted[epochId]          = true;
        totalStakeTimeByEpoch[epochId]     = currentEpochTotalStakeTime;
        currentEpochTotalStakeTime         = 0; // reset for next epoch

        emit EpochSnapshotted(epochId, totalStakeTimeByEpoch[epochId]);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Claim: staker records their personal stakeTime (for RewardEngine)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Record a user's stakeTime for a specific epoch.
     *         Users must call this BEFORE the epoch snapshot to have their
     *         stakeTime recorded. RewardEngine reads userStakeTimeByEpoch[epochId][user].
     *
     * @param epochId The epoch to record stakeTime for.
     */
    function recordStakeTime(uint256 epochId) external {
        require(currentEpochId() > epochId,                        "StakingVault: epoch not ended");
        require(userStakeTimeByEpoch[epochId][msg.sender] == 0,   "StakingVault: already recorded");
        _checkpointUser(msg.sender);

        // Cap stakeTime to the epoch window to prevent unbounded accStakeTime overflow.
        // An epoch spans [epochStart, epochEnd). We cap at the duration of one full epoch.
        // This prevents a staker calling recordStakeTime 52 epochs late from claiming 52x rewards.
        uint256 epochEnd      = genesisTimestamp + (epochId + 1) * EPOCH_DURATION;
        uint256 epochStart    = genesisTimestamp + epochId * EPOCH_DURATION;
        uint256 epochDuration = epochEnd - epochStart; // always = EPOCH_DURATION

        UserStake storage s       = userStakes[msg.sender];
        uint256 totalStake        = s.psreBalance + s.lpBalance;
        uint256 maxEpochStakeTime = totalStake * epochDuration; // theoretical max for this epoch

        // Recorded stakeTime = min(accStakeTime, maxEpochStakeTime).
        // accStakeTime may exceed one epoch if user never checkpointed; we cap it.
        uint256 st = s.accStakeTime < maxEpochStakeTime ? s.accStakeTime : maxEpochStakeTime;
        userStakeTimeByEpoch[epochId][msg.sender] = st;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // View helpers (called by RewardEngine)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Total stakeTime for a finalized epoch. Called by RewardEngine.
    function totalStakeTime(uint256 epochId) external view returns (uint256) {
        return totalStakeTimeByEpoch[epochId];
    }

    /// @notice A specific user's stakeTime for a finalized epoch.
    function stakeTimeOf(address user, uint256 epochId) external view returns (uint256) {
        return userStakeTimeByEpoch[epochId][user];
    }

    /// @notice Current total stake (PSRE + LP) for a user.
    function totalStakeOf(address user) external view returns (uint256 psreBal, uint256 lpBal) {
        return (userStakes[user].psreBalance, userStakes[user].lpBalance);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal: checkpoint a user's stakeTime accumulator
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @dev Updates a user's accStakeTime based on elapsed time × total stake.
     *      Called before any state change (stake, unstake).
     *
     *      stakeTime += (psreBalance + lpBalance) × (now - lastUpdateTimestamp)
     *
     *      Both PSRE and LP contribute equally per spec §2.4 (no weighting multiplier).
     */
    function _checkpointUser(address user) internal {
        UserStake storage s = userStakes[user];
        uint256 epoch = currentEpochId();

        // If user crosses an epoch boundary since last checkpoint,
        // we need to finalize their stakeTime for the previous epoch first.
        // For simplicity in v1, we accumulate across the current epoch only.
        // The snapshot mechanism handles epoch boundaries.

        if (s.lastUpdateTimestamp > 0 && block.timestamp > s.lastUpdateTimestamp) {
            uint256 elapsed   = block.timestamp - s.lastUpdateTimestamp;
            uint256 totalStake = s.psreBalance + s.lpBalance;
            uint256 delta     = totalStake * elapsed;

            s.accStakeTime             += delta;
            currentEpochTotalStakeTime += delta;
        }

        s.lastUpdateTimestamp = block.timestamp;
        userLastSnapshotEpoch[user] = epoch;
    }
}
