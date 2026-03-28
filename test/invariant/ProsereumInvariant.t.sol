// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "./handlers/ProtocolHandler.sol";

/**
 * @title ProsereumInvariantTest v3.2
 * @notice Phase 2 Foundry invariant (fuzz) tests for the Prospereum protocol.
 *
 * @dev The fuzzer randomly sequences calls to ProtocolHandler's action functions.
 *      Each invariant_* function is checked after every call sequence step.
 *
 *      Invariants verified (v3.2):
 *        1. PSRE total supply never exceeds the 21M hard cap.
 *        2. cumS for any vault never decreases (monotonically non-decreasing ratchet).
 *        3. RewardEngine's current epoch ID never goes backwards.
 *        4. StakingVault is solvent: its PSRE balance >= total PSRE staked via handler.
 *        5. T (total minted by RE) never exceeds S_EMISSION (12.6M).
 *
 *      Configuration ([invariant] in foundry.toml):
 *        runs  = 50   — quick smoke-test; increase to 500+ for deeper coverage
 *        depth = 20   — calls per run
 *        fail_on_revert = false — legitimate reverts are expected
 */
contract ProsereumInvariantTest is Test {

    ProtocolHandler public handler;

    function setUp() public {
        handler = new ProtocolHandler();
        targetContract(address(handler));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Invariant 1: PSRE total supply never exceeds the 21M hard cap
    // ─────────────────────────────────────────────────────────────────────────

    function invariant_totalSupplyNeverExceedsCap() public view {
        assertLe(
            handler.psre().totalSupply(),
            handler.psre().MAX_SUPPLY(),
            "INVARIANT BROKEN: PSRE total supply exceeds 21M cap"
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Invariant 2: cumS for any vault never decreases (ratchet property)
    //
    // v3.2: cumBuy replaced by cumS high-water-mark ratchet.
    // ghost_lastCumS[vault] records the last observed cumS after each buy or
    // finalization. cumS may only increase — any decrease is a critical bug.
    // ─────────────────────────────────────────────────────────────────────────

    function invariant_cumSNeverDecreases() public view {
        address[] memory vaults = handler.getVaults();
        for (uint256 i = 0; i < vaults.length; i++) {
            address vault   = vaults[i];
            uint256 current = IPartnerVault(vault).getCumS();
            assertGe(
                current,
                handler.ghost_lastCumS(vault),
                "INVARIANT BROKEN: vault cumS decreased (ratchet violated)"
            );
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Invariant 3: Epoch counter only moves forward
    // ─────────────────────────────────────────────────────────────────────────

    function invariant_epochOnlyIncreases() public view {
        assertGe(
            handler.rewardEngine().currentEpochId(),
            handler.ghost_lastEpoch(),
            "INVARIANT BROKEN: epoch went backwards"
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Invariant 4: StakingVault solvency
    // ─────────────────────────────────────────────────────────────────────────

    function invariant_stakingVaultSolvent() public view {
        uint256 vaultBalance = handler.psre().balanceOf(address(handler.stakingVault()));
        assertGe(
            vaultBalance,
            handler.ghost_totalPsreStaked(),
            "INVARIANT BROKEN: StakingVault PSRE balance < total staked (insolvent)"
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Invariant 5: RewardEngine total minted (T) never exceeds S_EMISSION
    // ─────────────────────────────────────────────────────────────────────────

    function invariant_totalMintedNeverExceedsEmission() public view {
        assertLe(
            handler.rewardEngine().T(),
            handler.rewardEngine().S_EMISSION(),
            "INVARIANT BROKEN: RewardEngine T > S_EMISSION"
        );
    }
}
