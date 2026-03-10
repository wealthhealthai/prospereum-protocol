// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title TeamVesting
 * @notice Holds the 4,200,000 PSRE team allocation minted at genesis.
 *         Enforces: 1-year cliff, 4-year linear vesting, no governance override.
 *
 * @dev Whitepaper v2.3 §3.2 and §3.3:
 *      "1-year cliff, 4-year linear vesting, locked at genesis, no governance override"
 *
 *      Vesting schedule:
 *      - Months 0-12:   0 PSRE claimable (cliff)
 *      - Month 12:      cliff unlocks, linear vesting begins
 *      - Months 12-60:  PSRE becomes claimable linearly
 *      - Month 60:      100% vested
 *
 *      Multiple beneficiaries are supported. Each has their own allocation.
 *      This contract is intentionally simple and non-upgradeable.
 */
contract TeamVesting {
    using SafeERC20 for IERC20;

    // ─────────────────────────────────────────────────────────────────────────
    // Constants
    // ─────────────────────────────────────────────────────────────────────────

    uint256 public constant CLIFF_DURATION = 365 days;  // 1 year
    uint256 public constant VEST_DURATION  = 4 * 365 days; // 4 years (from cliff end)

    // ─────────────────────────────────────────────────────────────────────────
    // Immutables
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice PSRE token.
    IERC20 public immutable psre;

    /// @notice Genesis timestamp — vesting clock starts here.
    uint256 public immutable genesisTimestamp;

    /// @notice Cliff end timestamp. No tokens claimable before this.
    uint256 public immutable cliffEnd;

    /// @notice Vest end timestamp. 100% vested at this point.
    uint256 public immutable vestEnd;

    // ─────────────────────────────────────────────────────────────────────────
    // Beneficiary state
    // ─────────────────────────────────────────────────────────────────────────

    struct Beneficiary {
        uint256 totalAllocation; // total PSRE allocated to this beneficiary
        uint256 claimed;         // amount already claimed
    }

    mapping(address => Beneficiary) public beneficiaries;
    address[] public beneficiaryList;

    uint256 public totalAllocated;

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    event Claimed(address indexed beneficiary, uint256 amount, uint256 totalClaimed);

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @param _psre             PSRE token address.
     * @param _genesisTimestamp Protocol genesis timestamp (same as PSRE and RewardEngine).
     * @param _beneficiaries    Array of beneficiary addresses.
     * @param _allocations      Array of PSRE allocations (must sum to 4,200,000e18).
     *
     * @dev After deployment, PSRE contract mints 4,200,000 PSRE to this address.
     *      No admin key — parameters are immutable. No governance override possible.
     */
    constructor(
        address _psre,
        uint256 _genesisTimestamp,
        address[] memory _beneficiaries,
        uint256[] memory _allocations
    ) {
        require(_psre != address(0),                     "TeamVesting: zero psre");
        require(_genesisTimestamp > 0,                   "TeamVesting: zero genesis");
        require(_beneficiaries.length > 0,               "TeamVesting: no beneficiaries");
        require(_beneficiaries.length == _allocations.length, "TeamVesting: length mismatch");

        psre             = IERC20(_psre);
        genesisTimestamp = _genesisTimestamp;
        cliffEnd         = _genesisTimestamp + CLIFF_DURATION;
        vestEnd          = cliffEnd + VEST_DURATION;

        uint256 total;
        for (uint256 i = 0; i < _beneficiaries.length; i++) {
            address b = _beneficiaries[i];
            uint256 a = _allocations[i];
            require(b != address(0), "TeamVesting: zero beneficiary");
            require(a > 0,           "TeamVesting: zero allocation");
            require(beneficiaries[b].totalAllocation == 0, "TeamVesting: duplicate beneficiary");

            beneficiaries[b].totalAllocation = a;
            beneficiaryList.push(b);
            total += a;
        }

        require(total == 4_200_000e18, "TeamVesting: allocations must sum to 4.2M PSRE");
        totalAllocated = total;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Claim
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Claim all currently vested PSRE for the caller.
     *         Reverts if before cliff or if nothing new to claim.
     */
    function claim() external {
        require(block.timestamp >= cliffEnd, "TeamVesting: still in cliff period");

        Beneficiary storage b = beneficiaries[msg.sender];
        require(b.totalAllocation > 0, "TeamVesting: not a beneficiary");

        uint256 vested  = _vestedAmount(b.totalAllocation);
        uint256 claimable = vested - b.claimed;
        require(claimable > 0, "TeamVesting: nothing to claim");

        b.claimed += claimable;
        psre.safeTransfer(msg.sender, claimable);

        emit Claimed(msg.sender, claimable, b.claimed);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // View helpers
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Returns how much PSRE a beneficiary can claim right now.
     */
    function claimableOf(address beneficiary) external view returns (uint256) {
        Beneficiary storage b = beneficiaries[beneficiary];
        if (block.timestamp < cliffEnd) return 0;
        uint256 vested = _vestedAmount(b.totalAllocation);
        return vested > b.claimed ? vested - b.claimed : 0;
    }

    /**
     * @notice Returns total vested amount for a given allocation at current timestamp.
     */
    function vestedOf(address beneficiary) external view returns (uint256) {
        if (block.timestamp < cliffEnd) return 0;
        return _vestedAmount(beneficiaries[beneficiary].totalAllocation);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @dev Linear vesting from cliffEnd to vestEnd.
     *      At cliffEnd: 0 vested (cliff just ended, linear begins)
     *      At vestEnd:  totalAllocation vested (100%)
     *
     *      vested = totalAllocation × min(now - cliffEnd, VEST_DURATION) / VEST_DURATION
     */
    function _vestedAmount(uint256 totalAllocation) internal view returns (uint256) {
        if (block.timestamp < cliffEnd) return 0;
        if (block.timestamp >= vestEnd) return totalAllocation;

        uint256 elapsed = block.timestamp - cliffEnd;
        return (totalAllocation * elapsed) / VEST_DURATION;
    }
}
