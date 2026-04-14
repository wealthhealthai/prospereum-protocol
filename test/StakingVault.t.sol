// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/periphery/StakingVault.sol";
import "../contracts/core/PSRE.sol";
import "./mocks/MockERC20.sol";

/**
 * @title StakingVaultTest v3.0
 * @notice Tests for StakingVault v3 -- Synthetix-style passive staking.
 *
 *         Key behaviors tested:
 *         - Passive staker: stake once, earn across multiple epochs (the v2 bug)
 *         - Two users: proportional reward split based on balance share
 *         - Unstake mid-epoch: balance change only affects future epochs
 *         - PSRE and LP separate pools: no dilution between them
 *         - No double-claim: pendingRewards zeroed on claim
 *         - Zero stakers: pool stays in contract (no division by zero)
 *         - claimStake works without pre-checkpoint (the v2 liveness failure)
 *         - Access control: snapshotEpoch, distributeStakerRewards, setSplit, setRewardEngine
 *         - Gas cap: lastSettledEpoch advances correctly across multiple settle calls
 */
contract StakingVaultTest is Test {
    StakingVault public stakingVault;
    PSRE         public psre;
    MockERC20    public lpToken;

    address public admin        = makeAddr("admin");
    address public treasury     = makeAddr("treasury");
    address public teamVesting  = makeAddr("teamVesting");
    address public rewardEngine = makeAddr("rewardEngine");
    address public alice        = makeAddr("alice");
    address public bob          = makeAddr("bob");

    uint256 public genesis;
    uint256 public constant EPOCH     = 7 days;
    uint256 public constant PRECISION = 1e18;

    bytes32 minterRole;

    function setUp() public {
        genesis = block.timestamp;

        psre    = new PSRE(admin, treasury, teamVesting, genesis);
        lpToken = new MockERC20("LP Token", "LP", 18);

        stakingVault = new StakingVault(
            address(psre),
            address(lpToken),
            genesis,
            admin
        );

        // Set reward engine
        vm.prank(admin);
        stakingVault.setRewardEngine(rewardEngine);

        // Grant minter role to test contract
        minterRole = psre.MINTER_ROLE();
        vm.prank(admin);
        psre.grantRole(minterRole, address(this));

        // Mint tokens to users
        psre.mint(alice, 10_000e18);
        psre.mint(bob,   10_000e18);
        lpToken.mint(alice, 10_000e18);
        lpToken.mint(bob,   10_000e18);

        // Approvals
        vm.prank(alice); psre.approve(address(stakingVault), type(uint256).max);
        vm.prank(alice); lpToken.approve(address(stakingVault), type(uint256).max);
        vm.prank(bob);   psre.approve(address(stakingVault), type(uint256).max);
        vm.prank(bob);   lpToken.approve(address(stakingVault), type(uint256).max);
    }

    // ------------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------------

    /// @dev Mint PSRE to rewardEngine and approve StakingVault.
    function _fundRewardEngine(uint256 amount) internal {
        psre.mint(rewardEngine, amount);
        vm.prank(rewardEngine);
        psre.approve(address(stakingVault), amount);
    }

    /// @dev Snapshot an epoch (records current total staked).
    function _snapshot(uint256 epochId) internal {
        vm.prank(rewardEngine);
        stakingVault.snapshotEpoch(epochId);
    }

    /// @dev Snapshot and distribute a reward pool for an epoch.
    function _snapshotAndDistribute(uint256 epochId, uint256 rewardPool) internal {
        _snapshot(epochId);
        if (rewardPool > 0) {
            _fundRewardEngine(rewardPool);
            vm.prank(rewardEngine);
            stakingVault.distributeStakerRewards(epochId, rewardPool);
        }
    }

    /// @dev Advance time past epoch boundary and finalize.
    function _advanceAndFinalize(uint256 epochId, uint256 rewardPool) internal {
        vm.warp(genesis + (epochId + 1) * EPOCH + 1);
        _snapshotAndDistribute(epochId, rewardPool);
    }

    // ------------------------------------------------------------------------
    // 1. Basic PSRE staking / unstaking
    // ------------------------------------------------------------------------

    function test_stakePSRE_transfersTokensIn() public {
        uint256 before = psre.balanceOf(address(stakingVault));
        vm.prank(alice);
        stakingVault.stakePSRE(500e18);
        assertEq(psre.balanceOf(address(stakingVault)), before + 500e18);
        assertEq(psre.balanceOf(alice), 10_000e18 - 500e18);
    }

    function test_stakePSRE_updatesUserBalance() public {
        vm.prank(alice);
        stakingVault.stakePSRE(500e18);
        (uint256 psreBal, ) = stakingVault.totalStakeOf(alice);
        assertEq(psreBal, 500e18);
        assertEq(stakingVault.totalPSREStaked(), 500e18);
    }

    function test_unstakePSRE_transfersTokensOut() public {
        vm.prank(alice);
        stakingVault.stakePSRE(500e18);
        uint256 before = psre.balanceOf(alice);
        vm.prank(alice);
        stakingVault.unstakePSRE(200e18);
        assertEq(psre.balanceOf(alice), before + 200e18);
    }

    function test_unstakePSRE_updatesUserBalance() public {
        vm.prank(alice);
        stakingVault.stakePSRE(500e18);
        vm.prank(alice);
        stakingVault.unstakePSRE(200e18);
        (uint256 psreBal, ) = stakingVault.totalStakeOf(alice);
        assertEq(psreBal, 300e18);
        assertEq(stakingVault.totalPSREStaked(), 300e18);
    }

    function test_unstakePSRE_revertsOnInsufficientBalance() public {
        vm.prank(alice);
        stakingVault.stakePSRE(100e18);
        vm.prank(alice);
        vm.expectRevert("StakingVault: insufficient balance");
        stakingVault.unstakePSRE(200e18);
    }

    // ------------------------------------------------------------------------
    // 2. Basic LP staking / unstaking
    // ------------------------------------------------------------------------

    function test_stakeLP_transfersTokensIn() public {
        uint256 before = lpToken.balanceOf(address(stakingVault));
        vm.prank(alice);
        stakingVault.stakeLP(300e18);
        assertEq(lpToken.balanceOf(address(stakingVault)), before + 300e18);
        assertEq(lpToken.balanceOf(alice), 10_000e18 - 300e18);
    }

    function test_stakeLP_updatesUserBalance() public {
        vm.prank(alice);
        stakingVault.stakeLP(300e18);
        (, uint256 lpBal) = stakingVault.totalStakeOf(alice);
        assertEq(lpBal, 300e18);
        assertEq(stakingVault.totalLPStaked(), 300e18);
    }

    function test_unstakeLP_transfersTokensOut() public {
        vm.prank(alice);
        stakingVault.stakeLP(300e18);
        uint256 before = lpToken.balanceOf(alice);
        vm.prank(alice);
        stakingVault.unstakeLP(100e18);
        assertEq(lpToken.balanceOf(alice), before + 100e18);
    }

    function test_unstakeLP_revertsOnInsufficientBalance() public {
        vm.prank(alice);
        stakingVault.stakeLP(100e18);
        vm.prank(alice);
        vm.expectRevert("StakingVault: insufficient balance");
        stakingVault.unstakeLP(200e18);
    }

    // ------------------------------------------------------------------------
    // 3. THE KEY V3 TEST: passive staker earns without pre-claim checkpoint
    //    This was the BlockApex liveness failure in v2.
    // ------------------------------------------------------------------------

    /**
     * @notice Alice stakes once at genesis. Zero interactions for 5 epochs.
     *         She should receive the full PSRE pool share for all 5 epochs.
     *         (This test FAILED with StakingVault v2 -- the whole reason we rewrote it.)
     */
    function test_passiveStaker_earns5Epochs() public {
        uint256 rewardPerEpoch = 100e18;

        // Alice stakes and never touches her position again.
        vm.prank(alice);
        stakingVault.stakePSRE(1000e18);

        // Finalize 5 epochs with equal reward pools.
        for (uint256 e = 0; e < 5; e++) {
            _advanceAndFinalize(e, rewardPerEpoch);
        }

        // Alice has never interacted since staking. She is the only staker.
        // She should receive the full PSRE pool for all 5 epochs.
        // psrePool per epoch = 100e18 * 50% = 50e18
        // Total expected = 5 * 50e18 = 250e18
        uint256 psrePool = rewardPerEpoch * stakingVault.psreSplit() / PRECISION;
        uint256 expected = 5 * psrePool;

        uint256 balBefore = psre.balanceOf(alice);
        vm.prank(alice);
        stakingVault.claimAll();
        uint256 received = psre.balanceOf(alice) - balBefore;

        assertApproxEqRel(received, expected, 0.001e18,
            "Passive staker must earn correct rewards across 5 epochs without prior interaction");
    }

    /**
     * @notice Same as above but using the backward-compatible claimStake(epochId).
     *         claimStake must work without any pre-checkpoint -- that was the v2 bug.
     */
    function test_passiveStaker_claimStake_works() public {
        uint256 rewardPerEpoch = 100e18;

        vm.prank(alice);
        stakingVault.stakePSRE(1000e18);

        for (uint256 e = 0; e < 3; e++) {
            _advanceAndFinalize(e, rewardPerEpoch);
        }

        uint256 psrePool = rewardPerEpoch * stakingVault.psreSplit() / PRECISION;
        uint256 expected = 3 * psrePool;

        uint256 balBefore = psre.balanceOf(alice);
        // claimStake with the last finalized epoch -- no pre-checkpoint needed
        vm.prank(alice);
        stakingVault.claimStake(2);
        uint256 received = psre.balanceOf(alice) - balBefore;

        assertApproxEqRel(received, expected, 0.001e18,
            "claimStake must work for passive staker without pre-checkpoint");
    }

    // ------------------------------------------------------------------------
    // 4. Two users: proportional reward split
    // ------------------------------------------------------------------------

    function test_twoUsers_proportionalSplit() public {
        uint256 rewardPool = 100e18;

        // Alice 1000, Bob 500 -- Alice should get 2/3, Bob 1/3
        vm.prank(alice); stakingVault.stakePSRE(1000e18);
        vm.prank(bob);   stakingVault.stakePSRE(500e18);

        _advanceAndFinalize(0, rewardPool);

        uint256 psrePool = rewardPool * stakingVault.psreSplit() / PRECISION;

        uint256 aliceBefore = psre.balanceOf(alice);
        vm.prank(alice); stakingVault.claimAll();
        uint256 aliceReceived = psre.balanceOf(alice) - aliceBefore;

        uint256 bobBefore = psre.balanceOf(bob);
        vm.prank(bob); stakingVault.claimAll();
        uint256 bobReceived = psre.balanceOf(bob) - bobBefore;

        assertApproxEqRel(aliceReceived, psrePool * 2 / 3, 0.01e18,
            "Alice should get 2/3 of PSRE pool");
        assertApproxEqRel(bobReceived, psrePool * 1 / 3, 0.01e18,
            "Bob should get 1/3 of PSRE pool");
        assertApproxEqRel(aliceReceived + bobReceived, psrePool, 0.001e18,
            "Combined claims == full PSRE pool");
    }

    // ------------------------------------------------------------------------
    // 5. Unstake mid-epoch: affects only future epochs
    // ------------------------------------------------------------------------

    function test_unstakeMidEpoch_onlyAffectsFutureEpochs() public {
        uint256 rewardPool = 100e18;

        // Alice stakes 1000, Bob stakes 1000
        vm.prank(alice); stakingVault.stakePSRE(1000e18);
        vm.prank(bob);   stakingVault.stakePSRE(1000e18);

        // Epoch 0 finalized: both hold 1000 → 50/50 split
        _advanceAndFinalize(0, rewardPool);

        // Alice unstakes (settlement for epoch 0 happens internally before balance change)
        vm.prank(alice); stakingVault.unstakePSRE(1000e18);

        // Epoch 1 finalized: only Bob has 1000 staked
        _advanceAndFinalize(1, rewardPool);

        uint256 psrePool = rewardPool * stakingVault.psreSplit() / PRECISION;

        // Alice: earned 50% of epoch 0, 0% of epoch 1
        uint256 aliceBefore = psre.balanceOf(alice);
        vm.prank(alice); stakingVault.claimAll();
        uint256 aliceReceived = psre.balanceOf(alice) - aliceBefore;

        // Bob: earned 50% of epoch 0, 100% of epoch 1
        uint256 bobBefore = psre.balanceOf(bob);
        vm.prank(bob); stakingVault.claimAll();
        uint256 bobReceived = psre.balanceOf(bob) - bobBefore;

        // Note: Alice also got back her 1000 PSRE stake
        assertApproxEqRel(aliceReceived, psrePool / 2, 0.01e18,
            "Alice earns 50% of epoch 0 only (unstaked before epoch 1)");
        assertApproxEqRel(bobReceived, psrePool / 2 + psrePool, 0.01e18,
            "Bob earns 50% of epoch 0 + 100% of epoch 1");
    }

    // ------------------------------------------------------------------------
    // 6. Separate pools: PSRE stakers and LP stakers don't dilute each other
    // ------------------------------------------------------------------------

    function test_separatePools_noCompetition() public {
        uint256 rewardPool = 100e18;

        // Alice stakes PSRE only, Bob stakes LP only
        vm.prank(alice); stakingVault.stakePSRE(1000e18);
        vm.prank(bob);   stakingVault.stakeLP(1000e18);

        _advanceAndFinalize(0, rewardPool);

        uint256 psrePool = rewardPool * stakingVault.psreSplit() / PRECISION;
        uint256 lpPool_  = rewardPool * stakingVault.lpSplit()   / PRECISION;

        uint256 aliceBefore = psre.balanceOf(alice);
        vm.prank(alice); stakingVault.claimAll();
        uint256 aliceReceived = psre.balanceOf(alice) - aliceBefore;

        uint256 bobBefore = psre.balanceOf(bob);
        vm.prank(bob); stakingVault.claimAll();
        uint256 bobReceived = psre.balanceOf(bob) - bobBefore;

        assertApproxEqRel(aliceReceived, psrePool, 0.001e18,
            "Alice (PSRE-only) gets full PSRE pool -- LP stakers don't compete");
        assertApproxEqRel(bobReceived, lpPool_, 0.001e18,
            "Bob (LP-only) gets full LP pool -- PSRE stakers don't compete");
    }

    // ------------------------------------------------------------------------
    // 7. No double-claim
    // ------------------------------------------------------------------------

    function test_claimAll_noDoubleClaim() public {
        vm.prank(alice); stakingVault.stakePSRE(1000e18);
        _advanceAndFinalize(0, 100e18);

        vm.prank(alice); stakingVault.claimAll();

        vm.prank(alice);
        vm.expectRevert("StakingVault: nothing to claim");
        stakingVault.claimAll();
    }

    function test_claimStake_noDoubleClaim() public {
        vm.prank(alice); stakingVault.stakePSRE(1000e18);
        _advanceAndFinalize(0, 100e18);

        vm.prank(alice); stakingVault.claimStake(0);

        vm.prank(alice);
        vm.expectRevert("StakingVault: nothing to claim");
        stakingVault.claimStake(0);
    }

    // ------------------------------------------------------------------------
    // 8. Zero stakers: pool stays in contract, no division by zero
    // ------------------------------------------------------------------------

    function test_zeroStakers_poolNotPulled() public {
        uint256 rewardPool = 100e18;

        // No stakers at all
        _advanceAndFinalize(0, rewardPool);

        // rewardPerToken = 0 (no stakers, no division)
        assertEq(stakingVault.epochPSRERewardPerToken(0), 0, "no div-by-zero");
        assertEq(stakingVault.epochLPRewardPerToken(0),   0, "no div-by-zero");

        // Pool NOT pulled into StakingVault — stays in RewardEngine (caller)
        assertEq(psre.balanceOf(address(stakingVault)), 0,
            "no tokens pulled when no stakers");

        // Epoch is marked distributed
        assertTrue(stakingVault.epochDistributed(0), "epoch marked distributed");

        // Any user trying to claim gets nothing
        vm.prank(alice);
        vm.expectRevert("StakingVault: nothing to claim");
        stakingVault.claimAll();
    }

    // ------------------------------------------------------------------------
    // 9. snapshotEpoch: access control and idempotency guard
    // ------------------------------------------------------------------------

    function test_snapshotEpoch_onlyRewardEngine() public {
        vm.warp(genesis + EPOCH + 1);
        vm.prank(alice);
        vm.expectRevert("StakingVault: only rewardEngine");
        stakingVault.snapshotEpoch(0);
    }

    function test_snapshotEpoch_revertsIfAlreadySnapshotted() public {
        vm.warp(genesis + EPOCH + 1);
        vm.prank(rewardEngine); stakingVault.snapshotEpoch(0);
        vm.prank(rewardEngine);
        vm.expectRevert("StakingVault: already snapshotted");
        stakingVault.snapshotEpoch(0);
    }

    function test_snapshotEpoch_recordsTotals() public {
        vm.prank(alice); stakingVault.stakePSRE(1000e18);
        vm.prank(bob);   stakingVault.stakeLP(500e18);

        vm.warp(genesis + EPOCH + 1);
        vm.prank(rewardEngine); stakingVault.snapshotEpoch(0);

        assertEq(stakingVault.epochTotalPSREStaked(0), 1000e18,
            "snapshot records totalPSREStaked at time of call");
        assertEq(stakingVault.epochTotalLPStaked(0), 500e18,
            "snapshot records totalLPStaked at time of call");
    }

    // ------------------------------------------------------------------------
    // 10. distributeStakerRewards: access, ordering, and pool split
    // ------------------------------------------------------------------------

    function test_distributeStakerRewards_onlyRewardEngine() public {
        _snapshot(0);
        _fundRewardEngine(100e18);
        vm.prank(alice);
        vm.expectRevert("StakingVault: only rewardEngine");
        stakingVault.distributeStakerRewards(0, 100e18);
    }

    function test_distributeStakerRewards_requiresSnapshot() public {
        _fundRewardEngine(100e18);
        vm.prank(rewardEngine);
        vm.expectRevert("StakingVault: not snapshotted");
        stakingVault.distributeStakerRewards(0, 100e18);
    }

    function test_distributeStakerRewards_cannotDistributeTwice() public {
        _snapshot(0);
        _fundRewardEngine(200e18);
        vm.prank(rewardEngine); stakingVault.distributeStakerRewards(0, 100e18);
        vm.prank(rewardEngine);
        vm.expectRevert("StakingVault: already distributed");
        stakingVault.distributeStakerRewards(0, 100e18);
    }

    function test_distributeStakerRewards_splitPoolsCorrectly() public {
        uint256 totalPool = 100e18;

        vm.prank(alice); stakingVault.stakePSRE(1000e18);
        _snapshotAndDistribute(0, totalPool);

        uint256 expectedPSREPool = totalPool * stakingVault.psreSplit() / PRECISION;
        uint256 expectedLPPool   = totalPool * stakingVault.lpSplit()   / PRECISION;

        assertEq(stakingVault.epochPSREPool(0), expectedPSREPool, "PSRE pool = 50%");
        assertEq(stakingVault.epochLPPool(0),   expectedLPPool,   "LP pool = 50%");
        assertEq(psre.balanceOf(address(stakingVault)), totalPool + 1000e18,
            "vault holds pool tokens + staked tokens");
    }

    function test_distributeStakerRewards_computesRewardPerToken() public {
        uint256 totalPool = 100e18;

        vm.prank(alice); stakingVault.stakePSRE(1000e18);
        _snapshotAndDistribute(0, totalPool);

        // psrePool = 50e18, totalPSRE = 1000e18
        // rewardPerToken = 50e18 * 1e36 / 1000e18 = 5e34
        uint256 expectedRPT = (50e18 * 1e36) / 1000e18;
        assertEq(stakingVault.epochPSRERewardPerToken(0), expectedRPT,
            "rewardPerToken correctly computed");
    }

    // ------------------------------------------------------------------------
    // 11. claimStake: requires epoch finalized
    // ------------------------------------------------------------------------

    function test_claimStake_revertsIfEpochNotFinalized() public {
        vm.prank(alice); stakingVault.stakePSRE(1000e18);

        vm.prank(alice);
        vm.expectRevert("StakingVault: epoch not finalized");
        stakingVault.claimStake(0);
    }

    function test_claimStake_revertsIfNothingToClaim() public {
        // Alice staked but Bob didn't -- Bob tries to claim
        vm.prank(alice); stakingVault.stakePSRE(1000e18);
        _advanceAndFinalize(0, 100e18);

        vm.prank(bob);
        vm.expectRevert("StakingVault: nothing to claim");
        stakingVault.claimStake(0);
    }

    // ------------------------------------------------------------------------
    // 12. setSplit governance
    // ------------------------------------------------------------------------

    function test_setSplit_default() public view {
        assertEq(stakingVault.psreSplit(), 0.5e18, "default PSRE split = 50%");
        assertEq(stakingVault.lpSplit(),   0.5e18, "default LP split = 50%");
    }

    function test_setSplit_updatesCorrectly() public {
        vm.prank(admin);
        stakingVault.setSplit(0.7e18, 0.3e18);
        assertEq(stakingVault.psreSplit(), 0.7e18);
        assertEq(stakingVault.lpSplit(),   0.3e18);
    }

    function test_setSplit_revertsIfNotSumTo1e18() public {
        vm.prank(admin);
        vm.expectRevert("StakingVault: splits must sum to 1e18");
        stakingVault.setSplit(0.6e18, 0.3e18);
    }

    function test_setSplit_onlyOwner() public {
        vm.prank(alice);
        vm.expectRevert("StakingVault: not owner");
        stakingVault.setSplit(0.5e18, 0.5e18);
    }

    // ------------------------------------------------------------------------
    // 13. setRewardEngine governance
    // ------------------------------------------------------------------------

    function test_setRewardEngine_cannotSetTwice() public {
        vm.prank(admin);
        vm.expectRevert("StakingVault: already set");
        stakingVault.setRewardEngine(makeAddr("newRE"));
    }

    function test_setRewardEngine_onlyOwner() public {
        StakingVault sv2 = new StakingVault(address(psre), address(lpToken), genesis, admin);
        vm.prank(alice);
        vm.expectRevert("StakingVault: not owner");
        sv2.setRewardEngine(rewardEngine);
    }

    // ------------------------------------------------------------------------
    // 14. checkpointUser: permissionless and idempotent
    // ------------------------------------------------------------------------

    function test_checkpointUser_permissionless() public {
        vm.prank(alice); stakingVault.stakePSRE(1000e18);
        _advanceAndFinalize(0, 100e18);

        // Bob can checkpoint Alice (keeper pattern) -- settles epoch 0 for her
        vm.prank(bob);
        stakingVault.checkpointUser(alice);

        // Alice's pendingRewards should now be populated
        uint256 pending = stakingVault.pendingRewards(alice);
        assertGt(pending, 0, "checkpointUser settles rewards into pendingRewards");

        // Alice can now claim without calling checkpointUser herself
        uint256 balBefore = psre.balanceOf(alice);
        vm.prank(alice); stakingVault.claimAll();
        assertGt(psre.balanceOf(alice) - balBefore, 0, "rewards paid after keeper checkpoint");
    }

    // ------------------------------------------------------------------------
    // 15. Multiple epochs, incremental claiming
    // ------------------------------------------------------------------------

    function test_multipleEpochs_incrementalClaiming() public {
        uint256 rewardPool = 100e18;

        vm.prank(alice); stakingVault.stakePSRE(1000e18);

        // Finalize 3 epochs
        _advanceAndFinalize(0, rewardPool);
        _advanceAndFinalize(1, rewardPool);
        _advanceAndFinalize(2, rewardPool);

        uint256 psrePool = rewardPool * stakingVault.psreSplit() / PRECISION;

        // First claim: should settle and pay all 3 epochs
        uint256 balBefore = psre.balanceOf(alice);
        vm.prank(alice); stakingVault.claimAll();
        uint256 received1 = psre.balanceOf(alice) - balBefore;

        assertApproxEqRel(received1, 3 * psrePool, 0.001e18,
            "first claim pays all 3 epochs");

        // Finalize epoch 3
        _advanceAndFinalize(3, rewardPool);

        // Second claim: only epoch 3
        balBefore = psre.balanceOf(alice);
        vm.prank(alice); stakingVault.claimAll();
        uint256 received2 = psre.balanceOf(alice) - balBefore;

        assertApproxEqRel(received2, psrePool, 0.001e18,
            "second claim pays only the new epoch");
    }

    // ------------------------------------------------------------------------
    // 16. Split affects reward proportions
    // ------------------------------------------------------------------------

    function test_customSplit_affectsRewards() public {
        // Set 70/30 split before staking
        vm.prank(admin); stakingVault.setSplit(0.7e18, 0.3e18);

        uint256 rewardPool = 100e18;

        // Alice stakes PSRE, Bob stakes LP
        vm.prank(alice); stakingVault.stakePSRE(1000e18);
        vm.prank(bob);   stakingVault.stakeLP(1000e18);

        _advanceAndFinalize(0, rewardPool);

        uint256 aliceBefore = psre.balanceOf(alice);
        vm.prank(alice); stakingVault.claimAll();
        uint256 aliceReceived = psre.balanceOf(alice) - aliceBefore;

        uint256 bobBefore = psre.balanceOf(bob);
        vm.prank(bob); stakingVault.claimAll();
        uint256 bobReceived = psre.balanceOf(bob) - bobBefore;

        // Alice (PSRE pool = 70e18), Bob (LP pool = 30e18)
        assertApproxEqRel(aliceReceived, 70e18, 0.001e18, "Alice gets 70% with 70/30 split");
        assertApproxEqRel(bobReceived,   30e18, 0.001e18, "Bob gets 30% with 70/30 split");
    }

    // ------------------------------------------------------------------------
    // 17. Epoch helpers
    // ------------------------------------------------------------------------

    function test_epochHelpers() public view {
        assertEq(stakingVault.currentEpochId(), 0,            "epoch 0 at genesis");
        assertEq(stakingVault.epochStart(0), genesis,         "epoch 0 starts at genesis");
        assertEq(stakingVault.epochEnd(0),   genesis + EPOCH, "epoch 0 ends at genesis + EPOCH");
        assertEq(stakingVault.epochStart(1), genesis + EPOCH, "epoch 1 starts at genesis + EPOCH");
    }

    // ------------------------------------------------------------------------
    // 18. lastFinalizedEpoch sentinel
    // ------------------------------------------------------------------------

    function test_lastFinalizedEpoch_sentinel_beforeAnyEpoch() public {
        // Before any epoch is finalized, lastFinalizedEpoch is the sentinel max uint
        assertEq(stakingVault.lastFinalizedEpoch(), type(uint256).max,
            "sentinel value before any epoch finalized");
    }

    function test_lastFinalizedEpoch_advancesOnDistribute() public {
        _advanceAndFinalize(0, 100e18);
        assertEq(stakingVault.lastFinalizedEpoch(), 0, "epoch 0 finalized");

        _advanceAndFinalize(1, 100e18);
        assertEq(stakingVault.lastFinalizedEpoch(), 1, "epoch 1 finalized");
    }

    // ------------------------------------------------------------------------
    // 19. Stake after some epochs are finalized
    // ------------------------------------------------------------------------

    function test_stakeAfterEpochs_noBackdatedRewards() public {
        uint256 rewardPool = 100e18;

        // Alice stakes in epoch 0
        vm.prank(alice); stakingVault.stakePSRE(1000e18);
        _advanceAndFinalize(0, rewardPool);

        // Bob stakes in epoch 1 (AFTER epoch 0 was already finalized)
        vm.prank(bob); stakingVault.stakePSRE(1000e18);
        _advanceAndFinalize(1, rewardPool);

        uint256 psrePool = rewardPool * stakingVault.psreSplit() / PRECISION;

        // Alice: earned epoch 0 (sole staker) + 50% of epoch 1
        uint256 aliceBefore = psre.balanceOf(alice);
        vm.prank(alice); stakingVault.claimAll();
        uint256 aliceReceived = psre.balanceOf(alice) - aliceBefore;

        // Bob: 0 from epoch 0 (wasn't staked), 50% from epoch 1
        uint256 bobBefore = psre.balanceOf(bob);
        vm.prank(bob); stakingVault.claimAll();
        uint256 bobReceived = psre.balanceOf(bob) - bobBefore;

        assertApproxEqRel(aliceReceived, psrePool + psrePool / 2, 0.01e18,
            "Alice gets epoch 0 full + 50% of epoch 1");
        assertApproxEqRel(bobReceived, psrePool / 2, 0.01e18,
            "Bob gets 50% of epoch 1 only (not backdated)");
    }

    // ------------------------------------------------------------------------
    // 20. lastSettledEpoch advances correctly
    // ------------------------------------------------------------------------

    function test_lastSettledEpoch_advancesAfterSettle() public {
        vm.prank(alice); stakingVault.stakePSRE(1000e18);
        _advanceAndFinalize(0, 100e18);
        _advanceAndFinalize(1, 100e18);

        // Before any settlement, lastSettledEpoch = 0 (initial)
        (,, uint256 settleBefore) = stakingVault.userStakes(alice);
        assertEq(settleBefore, 0, "initial lastSettledEpoch = 0");

        vm.prank(alice); stakingVault.claimAll();

        // After claiming, should have settled epochs 0 and 1 → lastSettledEpoch = 2
        (,, uint256 settleAfter) = stakingVault.userStakes(alice);
        assertEq(settleAfter, 2, "lastSettledEpoch = 2 after claiming epochs 0 and 1");
    }

    // ------------------------------------------------------------------------
    // 21. Staking both PSRE and LP simultaneously
    // ------------------------------------------------------------------------

    function test_stakeBoth_earnsFromBothPools() public {
        uint256 rewardPool = 100e18;

        // Alice stakes both PSRE and LP
        vm.prank(alice); stakingVault.stakePSRE(1000e18);
        vm.prank(alice); stakingVault.stakeLP(1000e18);

        _advanceAndFinalize(0, rewardPool);

        uint256 psrePool = rewardPool * stakingVault.psreSplit() / PRECISION; // 50e18
        uint256 lpPool_  = rewardPool * stakingVault.lpSplit()   / PRECISION; // 50e18

        uint256 balBefore = psre.balanceOf(alice);
        vm.prank(alice); stakingVault.claimAll();
        uint256 received = psre.balanceOf(alice) - balBefore;

        // Alice is sole staker in both pools → gets both full pools
        assertApproxEqRel(received, psrePool + lpPool_, 0.001e18,
            "sole staker in both pools earns 100% of total reward");
    }

    // ------------------------------------------------------------------------
    // 22. Epoch with no staker allocation (no distribute call)
    // ------------------------------------------------------------------------

    function test_epochWithNoDistribute_skippedInSettle() public {
        uint256 rewardPool = 100e18;

        vm.prank(alice); stakingVault.stakePSRE(1000e18);

        // Epoch 0: snapshot but NO distribute (simulates zero staker allocation)
        vm.warp(genesis + EPOCH + 1);
        _snapshot(0);
        // Do NOT call distributeStakerRewards -- no lastFinalizedEpoch update

        // Epoch 1: full distribute
        vm.warp(genesis + 2 * EPOCH + 1);
        _snapshotAndDistribute(1, rewardPool);

        // lastFinalizedEpoch should be 1 (set by epoch 1 distribution)
        assertEq(stakingVault.lastFinalizedEpoch(), 1);

        uint256 psrePool = rewardPool * stakingVault.psreSplit() / PRECISION;

        uint256 balBefore = psre.balanceOf(alice);
        vm.prank(alice); stakingVault.claimAll();
        uint256 received = psre.balanceOf(alice) - balBefore;

        // Only epoch 1 was distributed -- Alice gets only epoch 1 rewards
        assertApproxEqRel(received, psrePool, 0.001e18,
            "epoch 0 (no distribute) skipped; only epoch 1 rewards paid");
    }

    // ------------------------------------------------------------------------
    // 23. pendingRewards view reflects un-settled state correctly
    // ------------------------------------------------------------------------

    function test_pendingRewards_accumulatesAcrossEpochs() public {
        vm.prank(alice); stakingVault.stakePSRE(1000e18);

        _advanceAndFinalize(0, 100e18);
        // pendingRewards[alice] is still 0 (not yet settled)
        assertEq(stakingVault.pendingRewards(alice), 0,
            "pendingRewards is 0 before any settle call");

        // Trigger settlement via checkpointUser
        stakingVault.checkpointUser(alice);
        assertGt(stakingVault.pendingRewards(alice), 0,
            "pendingRewards populated after settle");

        uint256 pending = stakingVault.pendingRewards(alice);

        _advanceAndFinalize(1, 100e18);
        stakingVault.checkpointUser(alice);

        // Should now be 2× the single epoch amount
        assertApproxEqRel(stakingVault.pendingRewards(alice), pending * 2, 0.001e18,
            "pendingRewards doubles after second epoch settled");
    }
}
