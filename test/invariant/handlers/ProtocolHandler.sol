// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import "../../../contracts/core/PSRE.sol";
import "../../../contracts/core/PartnerVaultFactory.sol";
import "../../../contracts/core/PartnerVault.sol";
import "../../../contracts/core/CustomerVault.sol";
import "../../../contracts/periphery/StakingVault.sol";
import "../../../contracts/periphery/RewardEngine.sol";
import "../../../contracts/interfaces/IPartnerVault.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../mocks/MockERC20.sol";
import "../mocks/MockRouter.sol";

/**
 * @title ProtocolHandler v3.2
 * @notice Foundry invariant-test handler for the Prospereum protocol.
 *         Deploys a fully wired protocol in its constructor and exposes
 *         bounded action functions that the fuzzer can call in sequence.
 *
 * @dev v3.2 changes from v2.3:
 *      - factory.createVault() now takes (usdcAmountIn, minPsreOut, deadline, fee)
 *      - ghost_lastCumBuy → ghost_lastCumS (uses getCumS())
 *      - CustomerVault implementation required for factory
 *      - S_MIN enforced: createVault needs >= 500e6 USDC
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

    /// @notice Last known cumS for each vault — updated after every successful buy
    ///         and after every successful finalizeEpoch. Used to verify monotonicity.
    mapping(address => uint256) public ghost_lastCumS;

    /// @notice Number of epochs successfully finalized during this run.
    uint256 public ghost_lastEpoch;

    /// @notice Net PSRE deposited into StakingVault during this run.
    uint256 public ghost_totalPsreStaked;

    // S_MIN constant (mirrors factory.S_MIN)
    uint256 constant S_MIN = 500_000_000; // 500 USDC, 6 decimals

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor: deploy & wire the full protocol
    // ─────────────────────────────────────────────────────────────────────────

    constructor() {
        uint256 genesis = block.timestamp;

        // ── Mock ERC-20 tokens ───────────────────────────────────────────────
        usdc = new MockERC20("USD Coin",     "USDC", 6);
        lp   = new MockERC20("PSRE/USDC LP", "PSLP", 18);

        // ── PartnerVault + CustomerVault implementations ──────────────────────
        PartnerVault  vaultImpl = new PartnerVault();
        CustomerVault cvImpl    = new CustomerVault();

        // ── PSRE token ────────────────────────────────────────────────────────
        psre = new PSRE(
            address(this), // admin
            address(this), // treasury  (receives 4.2 M genesis PSRE)
            address(this), // teamVesting (receives 4.2 M genesis PSRE)
            genesis
        );

        // ── Mock router — mints PSRE on every swap (no real pool needed) ─────
        router = new MockRouter(address(psre));

        // ── PartnerVaultFactory (v3.2: needs cvImpl as 2nd arg) ──────────────
        factory = new PartnerVaultFactory(
            address(vaultImpl),
            address(cvImpl),
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

        // ── RewardEngine — deploy via UUPS proxy (MAJOR-3) ───────────────────
        {
            RewardEngine reImpl = new RewardEngine();
            bytes memory initData = abi.encodeCall(
                RewardEngine.initialize,
                (
                    address(psre),
                    address(factory),
                    address(stakingVault),
                    genesis,
                    address(this)  // owner
                )
            );
            ERC1967Proxy proxy = new ERC1967Proxy(address(reImpl), initData);
            rewardEngine = RewardEngine(address(proxy));
        }

        // ── Wire: set RewardEngine on factory and stakingVault ────────────────
        factory.setRewardEngine(address(rewardEngine));
        stakingVault.setRewardEngine(address(rewardEngine));

        // ── Grant MINTER_ROLE ─────────────────────────────────────────────────
        bytes32 MINTER_ROLE = psre.MINTER_ROLE();
        psre.grantRole(MINTER_ROLE, address(rewardEngine)); // mints at epoch finalization
        psre.grantRole(MINTER_ROLE, address(router));       // mints on vault buys (MockRouter)
        psre.grantRole(MINTER_ROLE, address(this));         // handler mints for staking setup

        // ── Actors ────────────────────────────────────────────────────────────
        for (uint256 i = 1; i <= 5; i++) {
            actors.push(address(uint160(i)));
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Action 1: createVault
    // Pick an actor, create a PartnerVault for them if they don't have one yet.
    // v3.2: factory.createVault(usdcAmountIn, minPsreOut, deadline, fee)
    //       Actor must have >= S_MIN USDC and approve factory.
    // ─────────────────────────────────────────────────────────────────────────

    function createVault(uint256 actorSeed) external {
        if (vaults.length >= 5) return;

        address actor = actors[actorSeed % actors.length];
        if (factory.vaultOf(actor) != address(0)) return; // actor already has a vault

        // Mint S_MIN USDC to actor and approve factory (for initial buy)
        usdc.mint(actor, S_MIN);
        vm.prank(actor);
        usdc.approve(address(factory), S_MIN);

        vm.prank(actor);
        try factory.createVault(
            S_MIN,                      // usdcAmountIn = exactly S_MIN
            1,                          // minPsreOut (MockRouter always produces > 0)
            block.timestamp + 1 hours,
            3000
        ) returns (address vault) {
            vaults.push(vault);
            ghost_lastCumS[vault] = IPartnerVault(vault).getCumS();
        } catch {}
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Action 2: executeBuy
    // Mint USDC to vault owner, approve the vault, call vault.buy().
    // Updates ghost_lastCumS on success.
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
            1,                       // minAmountOut: must be > 0
            block.timestamp + 60,
            3000
        ) {
            // cumS is monotonically increasing — record last known value
            ghost_lastCumS[vault] = IPartnerVault(vault).getCumS();
        } catch {}
        vm.stopPrank();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Action 3: stakePSRE
    // Mint PSRE to actor, approve StakingVault, and stake.
    // ─────────────────────────────────────────────────────────────────────────

    function stakePSRE(uint256 actorSeed, uint256 amount) external {
        amount = bound(amount, 1e18, 1000e18);
        address actor = actors[actorSeed % actors.length];

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
    // ─────────────────────────────────────────────────────────────────────────

    function advanceTime(uint256 seconds_) external {
        seconds_ = bound(seconds_, 1, 8 days);
        vm.warp(block.timestamp + seconds_);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Action 5: snapshotAndFinalize
    // ─────────────────────────────────────────────────────────────────────────

    function snapshotAndFinalize() external {
        uint256 epochToFinalize;
        if (!rewardEngine.firstEpochFinalized()) {
            epochToFinalize = 0;
        } else {
            epochToFinalize = rewardEngine.lastFinalizedEpoch() + 1;
        }

        if (rewardEngine.currentEpochId() <= epochToFinalize) return;

        try rewardEngine.finalizeEpoch(epochToFinalize) {
            ghost_lastEpoch++;

            // Refresh cumS snapshots for all known vaults
            for (uint256 i = 0; i < vaults.length; i++) {
                ghost_lastCumS[vaults[i]] = IPartnerVault(vaults[i]).getCumS();
            }
        } catch {}
    }

    // ─────────────────────────────────────────────────────────────────────────
    // View helpers
    // ─────────────────────────────────────────────────────────────────────────

    function getVaults() external view returns (address[] memory) {
        return vaults;
    }

    function getActors() external view returns (address[] memory) {
        return actors;
    }
}
