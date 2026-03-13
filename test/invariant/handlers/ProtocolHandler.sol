// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import "../../../contracts/core/PSRE.sol";
import "../../../contracts/core/PartnerVaultFactory.sol";
import "../../../contracts/core/PartnerVault.sol";
import "../../../contracts/periphery/StakingVault.sol";
import "../../../contracts/periphery/RewardEngine.sol";
import "../../../contracts/interfaces/IPartnerVault.sol";

import "../mocks/MockERC20.sol";
import "../mocks/MockRouter.sol";

/**
 * @title ProtocolHandler
 * @notice Foundry invariant-test handler for the Prospereum protocol.
 *         Deploys a fully wired protocol in its constructor and exposes
 *         bounded action functions that the fuzzer can call in sequence.
 *
 * @dev The handler inherits from Test so it can use vm.prank / vm.warp.
 *      All actions use try/catch to swallow expected reverts (epoch cap,
 *      sequence errors, etc.) so the fuzzer continues rather than failing.
 */
contract ProtocolHandler is Test {

    // ─────────────────────────────────────────────────────────────────────────
    // Protocol contracts (public — accessed by ProsereumInvariantTest)
    // ─────────────────────────────────────────────────────────────────────────

    PSRE                 public psre;
    PartnerVaultFactory  public factory;
    StakingVault         public stakingVault;
    RewardEngine         public rewardEngine;
    MockRouter           public router;
    MockERC20            public usdc;
    MockERC20            public lp;

    // ─────────────────────────────────────────────────────────────────────────
    // Fuzzer state
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice 5 fixed actors used by all handler functions.
    address[] public actors;

    /// @notice Vault addresses deployed during the fuzzer run (max 5).
    address[] public vaults;

    // ─────────────────────────────────────────────────────────────────────────
    // Ghost variables (tracked by handler; verified by invariants)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Last known cumBuy for each vault — updated after every successful buy
    ///         and after every successful finalizeEpoch.  Used to verify monotonicity.
    mapping(address => uint256) public ghost_lastCumBuy;

    /// @notice Number of epochs successfully finalized during this run.
    ///         Invariant: rewardEngine.currentEpochId() >= ghost_lastEpoch.
    uint256 public ghost_lastEpoch;

    /// @notice Net PSRE deposited into StakingVault during this run.
    ///         Handler never calls unstake, so this equals the staking vault's
    ///         PSRE balance (useful for the solvency invariant).
    uint256 public ghost_totalPsreStaked;

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor: deploy & wire the full protocol
    // ─────────────────────────────────────────────────────────────────────────

    constructor() {
        uint256 genesis = block.timestamp;

        // ── Mock ERC-20 tokens ───────────────────────────────────────────────
        usdc = new MockERC20("USD Coin",     "USDC", 6);
        lp   = new MockERC20("PSRE/USDC LP", "PSLP", 18);

        // ── PartnerVault implementation (cloned by factory) ──────────────────
        PartnerVault vaultImpl = new PartnerVault();

        // ── PSRE token ────────────────────────────────────────────────────────
        // Handler is admin, treasury, and teamVesting for test simplicity.
        // Genesis mints 8.4 M PSRE to address(this); those tokens are inert here.
        psre = new PSRE(
            address(this), // admin
            address(this), // treasury  (receives 4.2 M genesis PSRE)
            address(this), // teamVesting (receives 4.2 M genesis PSRE)
            genesis
        );

        // ── Mock router — mints PSRE on every swap (no real pool needed) ─────
        router = new MockRouter(address(psre));

        // ── PartnerVaultFactory ───────────────────────────────────────────────
        factory = new PartnerVaultFactory(
            address(vaultImpl),
            address(psre),
            address(router),
            address(usdc),
            address(this)  // owner (Ownable2Step)
        );

        // ── StakingVault ──────────────────────────────────────────────────────
        stakingVault = new StakingVault(
            address(psre),
            address(lp),
            genesis,
            address(this)  // owner
        );

        // ── RewardEngine ──────────────────────────────────────────────────────
        rewardEngine = new RewardEngine(
            address(psre),
            address(factory),
            address(stakingVault),
            genesis,
            address(this)  // owner
        );

        // ── Wire: set RewardEngine on factory and stakingVault ────────────────
        factory.setRewardEngine(address(rewardEngine));
        stakingVault.setRewardEngine(address(rewardEngine));

        // ── Grant MINTER_ROLE ─────────────────────────────────────────────────
        bytes32 MINTER_ROLE = psre.MINTER_ROLE();
        psre.grantRole(MINTER_ROLE, address(rewardEngine)); // mints at epoch finalization
        psre.grantRole(MINTER_ROLE, address(router));       // mints on vault buys
        psre.grantRole(MINTER_ROLE, address(this));         // handler mints for staking setup

        // ── Actors ────────────────────────────────────────────────────────────
        for (uint256 i = 1; i <= 5; i++) {
            actors.push(address(uint160(i)));
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Action 1: createVault
    // Pick an actor, create a PartnerVault for them if they don't have one yet.
    // Capped at 5 vaults total.
    // ─────────────────────────────────────────────────────────────────────────

    function createVault(uint256 actorSeed) external {
        if (vaults.length >= 5) return;

        address actor = actors[actorSeed % actors.length];
        if (factory.vaultOf(actor) != address(0)) return; // actor already has a vault

        vm.prank(actor);
        try factory.createVault() returns (address vault) {
            vaults.push(vault);
        } catch {}
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Action 2: executeBuy
    // Mint USDC to vault owner, approve the vault, call vault.buy().
    // Updates ghost_lastCumBuy on success.
    //
    // NOTE: PartnerVault.buy() signature is:
    //   buy(uint256 amountIn, uint256 minAmountOut, uint256 deadline, uint24 fee)
    // minAmountOut must be > 0 (slippage protection enforced by vault).
    // ─────────────────────────────────────────────────────────────────────────

    function executeBuy(uint256 vaultSeed, uint256 usdcAmount) external {
        if (vaults.length == 0) return;

        usdcAmount = bound(usdcAmount, 1e6, 5000e6);

        address vault = vaults[vaultSeed % vaults.length];
        address owner = factory.partnerOf(vault);

        // Fund the vault owner with fresh USDC
        usdc.mint(owner, usdcAmount);

        vm.startPrank(owner);
        usdc.approve(vault, usdcAmount);
        try PartnerVault(vault).buy(
            usdcAmount,
            1,                       // minAmountOut: must be > 0; router always produces > 0
            block.timestamp + 60,
            3000                     // 0.3% fee tier (ignored by MockRouter)
        ) {
            // cumBuy is monotonically increasing — record last known value
            ghost_lastCumBuy[vault] = IPartnerVault(vault).cumBuy();
        } catch {}
        vm.stopPrank();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Action 3: stakePSRE
    // Mint PSRE to actor, approve StakingVault, and stake.
    // May silently skip if the PSRE epoch mint cap is exhausted.
    // ─────────────────────────────────────────────────────────────────────────

    function stakePSRE(uint256 actorSeed, uint256 amount) external {
        amount = bound(amount, 1e18, 1000e18);
        address actor = actors[actorSeed % actors.length];

        // Mint PSRE to actor. May revert if PSRE epoch cap (25,200/epoch) is hit.
        bool minted = false;
        try psre.mint(actor, amount) {
            minted = true;
        } catch {}
        if (!minted) return;

        vm.startPrank(actor);
        psre.approve(address(stakingVault), amount);
        try stakingVault.stakePSRE(amount) {
            ghost_totalPsreStaked += amount;
        } catch {}
        vm.stopPrank();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Action 4: advanceTime
    // Warp forward 1 second to 8 days. Crossing a 7-day boundary moves the
    // protocol into the next epoch, resetting PSRE's per-epoch mint cap.
    // ─────────────────────────────────────────────────────────────────────────

    function advanceTime(uint256 seconds_) external {
        seconds_ = bound(seconds_, 1, 8 days);
        vm.warp(block.timestamp + seconds_);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Action 5: snapshotAndFinalize
    // Attempts to finalize the next sequential epoch.
    // RewardEngine.finalizeEpoch() internally calls stakingVault.snapshotEpoch(),
    // so there is no separate snapshot call needed here.
    // On success: increments ghost_lastEpoch and refreshes ghost_lastCumBuy.
    // ─────────────────────────────────────────────────────────────────────────

    function snapshotAndFinalize() external {
        // Determine the next epoch that needs finalization
        uint256 epochToFinalize;
        if (!rewardEngine.firstEpochFinalized()) {
            epochToFinalize = 0;
        } else {
            epochToFinalize = rewardEngine.lastFinalizedEpoch() + 1;
        }

        // RewardEngine requires currentEpochId() > epochId before finalizing
        if (rewardEngine.currentEpochId() <= epochToFinalize) return;

        try rewardEngine.finalizeEpoch(epochToFinalize) {
            ghost_lastEpoch++;

            // Refresh cumBuy snapshots for all known vaults
            for (uint256 i = 0; i < vaults.length; i++) {
                ghost_lastCumBuy[vaults[i]] = IPartnerVault(vaults[i]).cumBuy();
            }
        } catch {}
    }

    // ─────────────────────────────────────────────────────────────────────────
    // View helpers
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Returns all deployed vault addresses for invariant iteration.
    function getVaults() external view returns (address[] memory) {
        return vaults;
    }

    /// @notice Returns all actor addresses.
    function getActors() external view returns (address[] memory) {
        return actors;
    }
}
