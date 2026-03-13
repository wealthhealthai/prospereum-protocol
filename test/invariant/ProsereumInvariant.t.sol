// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "./handlers/ProtocolHandler.sol";

/**
 * @title ProsereumInvariantTest
 * @notice Phase 2 Foundry invariant (fuzz) tests for the Prospereum protocol.
 *
 * @dev The fuzzer randomly sequences calls to ProtocolHandler's action functions.
 *      Each invariant_* function is checked after every call sequence step.
 *
 *      Invariants verified:
 *        1. PSRE total supply never exceeds the 21M hard cap.
 *        2. cumBuy for any vault never decreases (monotonically non-decreasing).
 *        3. RewardEngine's current epoch ID never goes backwards.
 *        4. StakingVault is solvent: its PSRE balance >= total PSRE staked via handler.
 *
 *      Configuration ([invariant] in foundry.toml):
 *        runs  = 50   — quick smoke-test; increase to 500+ for deeper coverage
 *        depth = 20   — calls per run
 *        fail_on_revert = false — legitimate reverts (epoch caps, sequence errors) are expected
 *
 *  FIXES vs. original spec:
 *    - cap()            → MAX_SUPPLY()   (PSRE has no cap() function; MAX_SUPPLY is a public constant)
 *    - currentEpoch()   → currentEpochId() (correct RewardEngine function name)
 *    - totalPsreRewards() → handler.ghost_totalPsreStaked() (StakingVault has no such getter)
 */
contract ProsereumInvariantTest is Test {

    ProtocolHandler public handler;

    function setUp() public {
        handler = new ProtocolHandler();
        targetContract(address(handler));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Invariant 1: PSRE total supply never exceeds the 21M hard cap
    //
    // PSRE.MAX_SUPPLY = 21_000_000e18.
    // Supply starts at 8.4M (genesis mint) and grows via RewardEngine minting.
    // Any mint beyond MAX_SUPPLY would be a critical protocol bug.
    // ─────────────────────────────────────────────────────────────────────────

    function invariant_totalSupplyNeverExceedsCap() public view {
        assertLe(
            handler.psre().totalSupply(),
            handler.psre().MAX_SUPPLY(),
            "INVARIANT BROKEN: PSRE total supply exceeds 21M cap"
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Invariant 2: cumBuy for any vault never decreases
    //
    // PartnerVault.cumBuy is incremented by buy() and never decremented.
    // ghost_lastCumBuy[vault] records the last observed value after a buy or
    // finalization. If cumBuy ever drops below that snapshot, this fires.
    // ─────────────────────────────────────────────────────────────────────────

    function invariant_cumBuyNeverDecreases() public view {
        address[] memory vaults = handler.getVaults();
        for (uint256 i = 0; i < vaults.length; i++) {
            address vault   = vaults[i];
            uint256 current = IPartnerVault(vault).cumBuy();
            assertGe(
                current,
                handler.ghost_lastCumBuy(vault),
                "INVARIANT BROKEN: vault cumBuy decreased"
            );
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Invariant 3: Epoch counter only moves forward
    //
    // ghost_lastEpoch counts successfully finalized epochs (incremented by handler).
    // rewardEngine.currentEpochId() is the time-based epoch counter.
    // finalizeEpoch(N) requires currentEpochId() > N, so after N epochs are
    // finalized, currentEpochId() must be >= ghost_lastEpoch.
    // ─────────────────────────────────────────────────────────────────────────

    function invariant_epochOnlyIncreases() public view {
        assertGe(
            handler.rewardEngine().currentEpochId(),
            handler.ghost_lastEpoch(),
            "INVARIANT BROKEN: epoch went backwards"
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Invariant 4: StakingVault solvency — PSRE balance >= total staked
    //
    // handler.ghost_totalPsreStaked tracks net PSRE deposited via stakePSRE()
    // (handler never calls unstake, so this equals the vault's live balance).
    // If vaultBalance < ghost_totalPsreStaked, PSRE has been lost — critical bug.
    //
    // Note: StakingVault has no totalPsreStaked() getter; ghost variable used instead.
    // ─────────────────────────────────────────────────────────────────────────

    function invariant_stakingVaultSolvent() public view {
        uint256 vaultBalance = handler.psre().balanceOf(address(handler.stakingVault()));
        assertGe(
            vaultBalance,
            handler.ghost_totalPsreStaked(),
            "INVARIANT BROKEN: StakingVault PSRE balance < total staked (insolvent)"
        );
    }
}
