// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../interfaces/IPSRE.sol";

/**
 * @title PSRE — Prospereum Token
 * @notice ERC-20 token for the Prospereum behavioral mining protocol.
 *         Mint authority is restricted to the RewardEngine only.
 *         Total supply is hard-capped at 21,000,000 PSRE.
 *         The emission reserve (12,600,000 PSRE) is never minted at genesis —
 *         it is minted incrementally by the RewardEngine at epoch finalization.
 *
 * @dev Dev Spec v2.3, Section 2.1
 *      - Standard ERC-20 with decimals=18
 *      - mint(to, amount) callable only by RewardEngine (MINTER_ROLE)
 *      - No other mint authority
 *      - Pausable: only halts transfers, NOT minting (minting is controlled by role)
 */
contract PSRE is ERC20, AccessControl, Pausable, IPSRE {
    // ─────────────────────────────────────────────────────────────────────────
    // Roles
    // ─────────────────────────────────────────────────────────────────────────

    bytes32 public constant MINTER_ROLE  = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE  = keccak256("PAUSER_ROLE");

    // ─────────────────────────────────────────────────────────────────────────
    // Supply constants (Dev Spec v2.3 §1.1)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Hard cap: total supply can never exceed this value.
    uint256 public constant MAX_SUPPLY      = 21_000_000e18;

    /// @notice Emission reserve: max tokens mintable by RewardEngine over protocol lifetime.
    uint256 public constant EMISSION_RESERVE = 12_600_000e18;

    // ─────────────────────────────────────────────────────────────────────────
    // Epoch-level mint rate limiter (defense-in-depth against RewardEngine exploit)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Genesis timestamp, set at deployment. Used for epoch-based rate limiting.
    uint256 public immutable genesisTimestamp;

    /// @notice Max PSRE mintable in any single epoch (upper E0 bound = 0.002 * EMISSION_RESERVE).
    ///         This is a hard circuit-breaker in the token itself, independent of RewardEngine logic.
    uint256 public constant MAX_MINT_PER_EPOCH = 25_200e18; // 0.002 * 12,600,000

    /// @notice Tracks how much was minted in each epoch. epochId => amount minted.
    mapping(uint256 => uint256) public epochMinted;

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    event Minted(address indexed to, uint256 amount, uint256 epochId);

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @param admin         Address granted DEFAULT_ADMIN_ROLE and PAUSER_ROLE (should be multisig).
     * @param treasury      Address receiving the genesis treasury mint (4,200,000 PSRE).
     * @param teamVesting   Address of the TeamVesting contract receiving team allocation (4,200,000 PSRE).
     * @param _genesisTimestamp Epoch clock start. Pass block.timestamp at deployment.
     *
     * @dev Genesis minting (per whitepaper v2.3 §3.2):
     *      - Team & Founders:   4,200,000 PSRE → teamVesting contract (1yr cliff, 4yr vest)
     *      - Ecosystem Growth:  1,680,000 PSRE → treasury SAFE
     *      - DAO Treasury:      1,470,000 PSRE → treasury SAFE
     *      - Bootstrap Liq:     1,050,000 PSRE → treasury SAFE
     *      Total minted at genesis: 8,400,000 PSRE (40% of supply)
     *      Emission reserve (12,600,000 PSRE) is NOT minted at genesis.
     */
    constructor(
        address admin,
        address treasury,
        address teamVesting,
        uint256 _genesisTimestamp
    ) ERC20("Prospereum", "PSRE") {
        require(admin       != address(0), "PSRE: zero admin");
        require(treasury    != address(0), "PSRE: zero treasury");
        require(teamVesting != address(0), "PSRE: zero teamVesting");
        require(_genesisTimestamp > 0,     "PSRE: zero genesis");

        genesisTimestamp = _genesisTimestamp;

        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        // MINTER_ROLE is NOT granted here — it must be granted to RewardEngine separately
        // after RewardEngine is deployed and verified.

        // Genesis mints (whitepaper §3.2)
        uint256 teamAlloc      = 4_200_000e18; // 20% — to vesting contract
        uint256 treasuryAlloc  = 4_200_000e18; // 20% — ecosystem growth + DAO treasury + bootstrap liq

        _mint(teamVesting, teamAlloc);
        _mint(treasury,    treasuryAlloc);

        // Verify: total genesis supply = 8.4M, leaving 12.6M for emission
        assert(totalSupply() == 8_400_000e18);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Minting (RewardEngine only)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Mint PSRE tokens. Callable only by the RewardEngine (MINTER_ROLE).
     * @param to     Recipient address (typically the RewardEngine itself, or a vault).
     * @param amount Amount to mint in wei.
     *
     * @dev Enforces two independent supply caps:
     *      1. Global: totalSupply + amount <= MAX_SUPPLY (21M)
     *      2. Epoch rate: minted this epoch + amount <= MAX_MINT_PER_EPOCH
     *         This is a circuit-breaker independent of RewardEngine logic.
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        require(to != address(0), "PSRE: mint to zero");
        require(amount > 0,       "PSRE: zero amount");

        // Global supply cap
        require(
            totalSupply() + amount <= MAX_SUPPLY,
            "PSRE: exceeds max supply"
        );

        // Epoch rate limiter (circuit-breaker)
        uint256 epochId = _currentEpochId();
        require(
            epochMinted[epochId] + amount <= MAX_MINT_PER_EPOCH,
            "PSRE: epoch mint cap exceeded"
        );

        epochMinted[epochId] += amount;
        _mint(to, amount);

        emit Minted(to, amount, epochId);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Pause (emergency only — halts transfers, NOT minting)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Pause token transfers. Emergency use only.
     *         Does NOT pause minting — rewards already earned can still be distributed.
     */
    function pause()   external onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() external onlyRole(PAUSER_ROLE) { _unpause(); }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal helpers
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @dev Computes current epoch ID from genesis timestamp.
     *      Matches RewardEngine epoch calculation exactly.
     */
    function _currentEpochId() internal view returns (uint256) {
        if (block.timestamp < genesisTimestamp) return 0;
        return (block.timestamp - genesisTimestamp) / 7 days;
    }

    /**
     * @dev Override to enforce pause on transfers.
     *      Called by transfer(), transferFrom(), _mint(), _burn().
     *      Note: _mint() calls this too — but we only pause transfers,
     *      not genesis mints (constructor calls _mint before pause can be set).
     */
    /// @dev OZ v5: override _update (replaces _beforeTokenTransfer).
    ///      Allow minting even when paused; block transfers/burns when paused.
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        if (from != address(0)) {
            require(!paused(), "PSRE: transfers paused");
        }
        super._update(from, to, value);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // View helpers
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Returns the current epoch ID (same formula as RewardEngine).
    function currentEpochId() external view returns (uint256) {
        return _currentEpochId();
    }

    /// @notice Returns how many tokens remain mintable under the global cap.
    function remainingMintable() external view returns (uint256) {
        return MAX_SUPPLY - totalSupply();
    }

    /// @notice Returns how many tokens remain mintable this epoch under the rate limiter.
    function remainingEpochMintable() external view returns (uint256) {
        uint256 used = epochMinted[_currentEpochId()];
        return used >= MAX_MINT_PER_EPOCH ? 0 : MAX_MINT_PER_EPOCH - used;
    }
}
