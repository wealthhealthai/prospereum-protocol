// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/periphery/StakingVault.sol";
import "../contracts/core/PSRE.sol";
import "./mocks/MockERC20.sol";

/**
 * @title StakingVaultTest v2.0
 * @notice Tests for StakingVault epoch-aware checkpointing model.
 *
 *         Covers:
 *         - Basic staking/unstaking token transfers and balance tracking
 *         - Epoch-aware _checkpoint: correct time attribution per epoch
 *         - Epoch boundary attribution (no cross-epoch contamination)
 *         - Snapshot + distributeStakerRewards + claimStake full flow
 *         - Two separate sub-pools (PSRE and LP) — no dilution between them
 *         - Two-user proportional reward split
 *         - Post-snapshot contribution rejection
 *         - Double-claim prevention
 *         - Split governance (setSplit)
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
    uint256 public constant EPOCH = 7 days;
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

        // Grant minter role to this test contract
        minterRole = psre.MINTER_ROLE();
        vm.prank(admin);
        psre.grantRole(minterRole, address(this));

        // Mint tokens to users
        psre.mint(alice, 10_000e18);
        psre.mint(bob,   10_000e18);
        lpToken.mint(alice, 10_000e18);
        lpToken.mint(bob,   10_000e18);

        // Approvals for staking
        vm.prank(alice); psre.approve(address(stakingVault), type(uint256).max);
        vm.prank(alice); lpToken.approve(address(stakingVault), type(uint256).max);
        vm.prank(bob);   psre.approve(address(stakingVault), type(uint256).max);
        vm.prank(bob);   lpToken.approve(address(stakingVault), type(uint256).max);
    }

    // ────────────────────────────────────────────────────────────────────────
    // Helpers
    // ────────────────────────────────────────────────────────────────────────

    /// @dev Fund rewardEngine with PSRE and set up approvals for distributeStakerRewards.
    function _fundRewardEngine(uint256 amount) internal {
        psre.mint(rewardEngine, amount);
        vm.prank(rewardEngine);
        psre.approve(address(stakingVault), amount);
    }

    /// @dev Snapshot an epoch and distribute a reward pool.
    function _snapshotAndDistribute(uint256 epochId, uint256 rewardPool) internal {
        vm.prank(rewardEngine);
        stakingVault.snapshotEpoch(epochId);
        if (rewardPool > 0) {
            _fundRewardEngine(rewardPool);
            vm.prank(rewardEngine);
            stakingVault.distributeStakerRewards(epochId, rewardPool);
        }
    }

    // ────────────────────────────────────────────────────────────────────────
    // 1. Basic PSRE staking / unstaking
    // ────────────────────────────────────────────────────────────────────────

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
    }

    function test_unstakePSRE_revertsOnInsufficientBalance() public {
        vm.prank(alice);
        stakingVault.stakePSRE(100e18);
        vm.prank(alice);
        vm.expectRevert("StakingVault: insufficient balance");
        stakingVault.unstakePSRE(200e18);
    }

    // ────────────────────────────────────────────────────────────────────────
    // 2. Basic LP staking / unstaking
    // ────────────────────────────────────────────────────────────────────────

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

    // ────────────────────────────────────────────────────────────────────────
    // 3. test_stakePSRE_basic — stake, warp, checkpoint, verify stakeTime recorded
    // ────────────────────────────────────────────────────────────────────────

    function test_stakePSRE_basic() public {
        uint256 amount = 1000e18;

        // Stake at genesis
        vm.prank(alice);
        stakingVault.stakePSRE(amount);

        // Warp to just before end of epoch 0, trigger checkpoint
        vm.warp(genesis + EPOCH - 1);
        // checkpointUser to attribute time to epoch 0
        stakingVault.checkpointUser(alice);

        // Verify contribution is recorded for epoch 0 (not yet snapshotted)
        uint256 contribution = stakingVault.userPSREStakedTime(0, alice);
        uint256 totalContrib = stakingVault.totalPSREStakedTime(0);

        assertGt(contribution, 0, "Alice should have PSRE stakeTime in epoch 0");
        // Approximately amount * (EPOCH - 1) seconds
        assertApproxEqRel(contribution, amount * (EPOCH - 1), 0.01e18, "contribution ~= amount * elapsed");
        assertEq(contribution, totalContrib, "total should equal alice's (sole staker)");
    }

    // ────────────────────────────────────────────────────────────────────────
    // 4. test_stakeLP_basic — LP version of above
    // ────────────────────────────────────────────────────────────────────────

    function test_stakeLP_basic() public {
        uint256 amount = 1000e18;

        vm.prank(alice);
        stakingVault.stakeLP(amount);

        vm.warp(genesis + EPOCH - 1);
        stakingVault.checkpointUser(alice);

        uint256 contribution = stakingVault.userLPStakedTime(0, alice);
        uint256 totalContrib = stakingVault.totalLPStakedTime(0);

        assertGt(contribution, 0, "Alice should have LP stakeTime in epoch 0");
        assertApproxEqRel(contribution, amount * (EPOCH - 1), 0.01e18, "LP contribution ~= amount * elapsed");
        assertEq(contribution, totalContrib, "total should equal alice's (sole staker)");
    }

    // ────────────────────────────────────────────────────────────────────────
    // 5. test_epochBoundaryAttribution — verify time is split across epochs correctly
    // ────────────────────────────────────────────────────────────────────────

    function test_epochBoundaryAttribution() public {
        uint256 amount = 1000e18;

        // Alice stakes at genesis (epoch 0)
        vm.prank(alice);
        stakingVault.stakePSRE(amount);
        // First stake sets lastCheckpointTimestamp = genesis, no contribution yet.

        // Warp to middle of epoch 2 (well past epoch 0 and epoch 1)
        uint256 midEpoch2 = genesis + 2 * EPOCH + EPOCH / 2;
        vm.warp(midEpoch2);

        // Checkpoint to attribute time across epochs 0, 1, and 2
        stakingVault.checkpointUser(alice);

        // Epoch 0: full epoch = EPOCH seconds
        uint256 e0 = stakingVault.userPSREStakedTime(0, alice);
        // Epoch 1: full epoch = EPOCH seconds
        uint256 e1 = stakingVault.userPSREStakedTime(1, alice);
        // Epoch 2: partial = EPOCH/2 seconds
        uint256 e2 = stakingVault.userPSREStakedTime(2, alice);

        assertApproxEqRel(e0, amount * EPOCH,         0.01e18, "epoch 0: full epoch");
        assertApproxEqRel(e1, amount * EPOCH,         0.01e18, "epoch 1: full epoch");
        assertApproxEqRel(e2, amount * (EPOCH / 2),   0.01e18, "epoch 2: half epoch");

        // Cross-check totals
        assertEq(stakingVault.totalPSREStakedTime(0), e0, "total e0 == alice e0");
        assertEq(stakingVault.totalPSREStakedTime(1), e1, "total e1 == alice e1");
        assertEq(stakingVault.totalPSREStakedTime(2), e2, "total e2 == alice e2");
    }

    // ────────────────────────────────────────────────────────────────────────
    // 6. test_unstakeBeforeClaim — unstake before claiming; reward still correct
    // ────────────────────────────────────────────────────────────────────────

    function test_unstakeBeforeClaim() public {
        uint256 amount      = 1000e18;
        uint256 rewardPool  = 100e18;

        // Alice stakes the full epoch
        vm.prank(alice);
        stakingVault.stakePSRE(amount);

        // Warp to end of epoch 0 — checkpoint alice (records full epoch contribution)
        vm.warp(genesis + EPOCH + 1);
        stakingVault.checkpointUser(alice);

        // Alice unstakes before claiming
        vm.prank(alice);
        stakingVault.unstakePSRE(amount);

        // Snapshot + distribute rewards
        _snapshotAndDistribute(0, rewardPool);

        // Alice claims — she should still get 50% (psreSplit=50%) of rewardPool
        // (she's the sole PSRE staker, LP pool is unfunded since no LP stakers)
        uint256 balBefore = psre.balanceOf(alice);
        vm.prank(alice);
        stakingVault.claimStake(0);
        uint256 gained = psre.balanceOf(alice) - balBefore;

        // psrePool = rewardPool * psreSplit / PRECISION = 50e18
        uint256 expectedPSREPool = rewardPool * stakingVault.psreSplit() / PRECISION;
        assertApproxEqRel(gained, expectedPSREPool, 0.01e18, "sole PSRE staker gets full PSRE pool");
    }

    // ────────────────────────────────────────────────────────────────────────
    // 7. test_twoUsers_correctSplit — rewards proportional to stakeTime
    // ────────────────────────────────────────────────────────────────────────

    function test_twoUsers_correctSplit() public {
        uint256 rewardPool = 100e18;

        // Alice stakes 1000 PSRE, Bob stakes 500 PSRE — both at genesis
        vm.prank(alice); stakingVault.stakePSRE(1000e18);
        vm.prank(bob);   stakingVault.stakePSRE(500e18);

        // Warp to end of epoch 0 — checkpoint both users
        vm.warp(genesis + EPOCH + 1);
        stakingVault.checkpointUser(alice);
        stakingVault.checkpointUser(bob);

        // Snapshot + distribute
        _snapshotAndDistribute(0, rewardPool);

        // Alice should get ~2/3 of the PSRE pool (1000/(1000+500))
        // Bob should get ~1/3 of the PSRE pool (500/(1000+500))
        uint256 psrePool = rewardPool * stakingVault.psreSplit() / PRECISION;

        uint256 aliceBefore = psre.balanceOf(alice);
        vm.prank(alice); stakingVault.claimStake(0);
        uint256 aliceGained = psre.balanceOf(alice) - aliceBefore;

        uint256 bobBefore = psre.balanceOf(bob);
        vm.prank(bob); stakingVault.claimStake(0);
        uint256 bobGained = psre.balanceOf(bob) - bobBefore;

        // Allow 1% relative tolerance for integer math
        assertApproxEqRel(aliceGained, psrePool * 2 / 3, 0.01e18, "Alice gets 2/3 of psre pool");
        assertApproxEqRel(bobGained,   psrePool * 1 / 3, 0.01e18, "Bob gets 1/3 of psre pool");

        // Combined should equal psrePool (no LP stakers → LP pool unclaimed)
        assertApproxEqRel(aliceGained + bobGained, psrePool, 0.01e18, "total claimed = psrePool");
    }

    // ────────────────────────────────────────────────────────────────────────
    // 8. test_separatePools_noCompetition — PSRE and LP stakers don't dilute each other
    // ────────────────────────────────────────────────────────────────────────

    function test_separatePools_noCompetition() public {
        uint256 rewardPool = 100e18;

        // Alice stakes PSRE only, Bob stakes LP only — equal amounts
        vm.prank(alice); stakingVault.stakePSRE(1000e18);
        vm.prank(bob);   stakingVault.stakeLP(1000e18);

        vm.warp(genesis + EPOCH + 1);
        stakingVault.checkpointUser(alice);
        stakingVault.checkpointUser(bob);

        _snapshotAndDistribute(0, rewardPool);

        uint256 psrePool = rewardPool * stakingVault.psreSplit() / PRECISION;
        uint256 lpPool   = rewardPool * stakingVault.lpSplit()   / PRECISION;

        // Alice should get the full PSRE pool (sole PSRE staker)
        uint256 aliceBefore = psre.balanceOf(alice);
        vm.prank(alice); stakingVault.claimStake(0);
        uint256 aliceGained = psre.balanceOf(alice) - aliceBefore;

        // Bob should get the full LP pool (sole LP staker)
        uint256 bobBefore = psre.balanceOf(bob);
        vm.prank(bob); stakingVault.claimStake(0);
        uint256 bobGained = psre.balanceOf(bob) - bobBefore;

        assertApproxEqRel(aliceGained, psrePool, 0.01e18, "Alice (PSRE staker) gets full PSRE pool");
        assertApproxEqRel(bobGained,   lpPool,   0.01e18, "Bob (LP staker) gets full LP pool");

        // Alice's LP competition doesn't affect her PSRE reward, and vice versa
        assertApproxEqRel(aliceGained, bobGained, 0.01e18, "equal amounts earned with 50/50 split");
    }

    // ────────────────────────────────────────────────────────────────────────
    // 9. test_claimStake_afterSnapshot — claim only works after epochSnapshotted
    // ────────────────────────────────────────────────────────────────────────

    function test_claimStake_afterSnapshot() public {
        uint256 rewardPool = 100e18;

        vm.prank(alice); stakingVault.stakePSRE(1000e18);
        vm.warp(genesis + EPOCH + 1);
        stakingVault.checkpointUser(alice);

        // Distribute rewards but do NOT snapshot yet
        _fundRewardEngine(rewardPool);

        // Claiming before snapshot must revert
        vm.prank(alice);
        vm.expectRevert("StakingVault: epoch not finalized");
        stakingVault.claimStake(0);

        // Now snapshot + distribute
        _snapshotAndDistribute(0, rewardPool);

        // Now claim succeeds
        vm.prank(alice);
        stakingVault.claimStake(0);
        assertGt(psre.balanceOf(alice), 0, "alice should have received rewards");
    }

    // ────────────────────────────────────────────────────────────────────────
    // 10. test_doubleClaim_reverts — can't claim twice for the same epoch
    // ────────────────────────────────────────────────────────────────────────

    function test_doubleClaim_reverts() public {
        uint256 rewardPool = 100e18;

        vm.prank(alice); stakingVault.stakePSRE(1000e18);
        vm.warp(genesis + EPOCH + 1);
        stakingVault.checkpointUser(alice);
        _snapshotAndDistribute(0, rewardPool);

        // First claim succeeds
        vm.prank(alice);
        stakingVault.claimStake(0);

        // Second claim reverts
        vm.prank(alice);
        vm.expectRevert("StakingVault: already claimed");
        stakingVault.claimStake(0);
    }

    // ────────────────────────────────────────────────────────────────────────
    // 11. test_splitGovernance — setSplit works; must sum to 1e18
    // ────────────────────────────────────────────────────────────────────────

    function test_splitGovernance() public {
        // Default split is 50/50
        assertEq(stakingVault.psreSplit(), 0.5e18);
        assertEq(stakingVault.lpSplit(),   0.5e18);

        // Update to 70/30
        vm.prank(admin);
        stakingVault.setSplit(0.7e18, 0.3e18);
        assertEq(stakingVault.psreSplit(), 0.7e18);
        assertEq(stakingVault.lpSplit(),   0.3e18);

        // Splits not summing to 1e18 must revert
        vm.prank(admin);
        vm.expectRevert("StakingVault: splits must sum to 1e18");
        stakingVault.setSplit(0.6e18, 0.3e18);

        // Non-owner cannot change split
        vm.prank(alice);
        vm.expectRevert("StakingVault: not owner");
        stakingVault.setSplit(0.5e18, 0.5e18);
    }

    // ────────────────────────────────────────────────────────────────────────
    // 12. test_postSnapshot_noContribution — after snapshot, no new contributions recorded
    // ────────────────────────────────────────────────────────────────────────

    function test_postSnapshot_noContribution() public {
        // Alice stakes at genesis, checkpoint before snapshot
        vm.prank(alice);
        stakingVault.stakePSRE(1000e18);

        vm.warp(genesis + EPOCH - 1);
        stakingVault.checkpointUser(alice);

        // Record contribution for epoch 0 before snapshot
        uint256 contribBeforeSnapshot = stakingVault.userPSREStakedTime(0, alice);
        assertGt(contribBeforeSnapshot, 0, "Alice should have contribution before snapshot");

        // Snapshot epoch 0
        vm.warp(genesis + EPOCH + 1);
        vm.prank(rewardEngine);
        stakingVault.snapshotEpoch(0);

        // Try to checkpoint again — should not add to epoch 0
        vm.warp(genesis + EPOCH + 2);
        stakingVault.checkpointUser(alice);

        uint256 contribAfterSnapshot = stakingVault.userPSREStakedTime(0, alice);
        assertEq(contribAfterSnapshot, contribBeforeSnapshot,
            "Post-snapshot checkpoint must not change epoch 0 contribution");
    }

    // ────────────────────────────────────────────────────────────────────────
    // 13. snapshotEpoch access control
    // ────────────────────────────────────────────────────────────────────────

    function test_snapshotEpoch_onlyRewardEngine() public {
        vm.warp(genesis + EPOCH + 1);
        vm.prank(alice);
        vm.expectRevert("StakingVault: only rewardEngine");
        stakingVault.snapshotEpoch(0);
    }

    function test_snapshotEpoch_revertsIfAlreadySnapshotted() public {
        vm.warp(genesis + EPOCH + 1);
        vm.prank(rewardEngine);
        stakingVault.snapshotEpoch(0);

        vm.prank(rewardEngine);
        vm.expectRevert("StakingVault: already snapshotted");
        stakingVault.snapshotEpoch(0);
    }

    // ────────────────────────────────────────────────────────────────────────
    // 14. distributeStakerRewards access and invariants
    // ────────────────────────────────────────────────────────────────────────

    function test_distributeStakerRewards_onlyRewardEngine() public {
        vm.warp(genesis + EPOCH + 1);
        vm.prank(rewardEngine);
        stakingVault.snapshotEpoch(0);

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
        vm.warp(genesis + EPOCH + 1);
        vm.prank(rewardEngine);
        stakingVault.snapshotEpoch(0);

        _fundRewardEngine(200e18);
        vm.prank(rewardEngine);
        stakingVault.distributeStakerRewards(0, 100e18);

        vm.prank(rewardEngine);
        vm.expectRevert("StakingVault: already distributed");
        stakingVault.distributeStakerRewards(0, 100e18);
    }

    function test_distributeStakerRewards_splitPoolsCorrectly() public {
        uint256 totalPool = 100e18;
        uint256 psreSplit = stakingVault.psreSplit(); // 0.5e18
        uint256 lpSplit   = stakingVault.lpSplit();   // 0.5e18

        vm.warp(genesis + EPOCH + 1);
        vm.prank(rewardEngine);
        stakingVault.snapshotEpoch(0);

        _fundRewardEngine(totalPool);
        vm.prank(rewardEngine);
        stakingVault.distributeStakerRewards(0, totalPool);

        assertEq(stakingVault.epochPSREPool(0), totalPool * psreSplit / PRECISION,
            "PSRE pool should be 50% of totalPool");
        assertEq(stakingVault.epochLPPool(0),   totalPool * lpSplit   / PRECISION,
            "LP pool should be 50% of totalPool");

        // Tokens should be held by StakingVault
        assertEq(psre.balanceOf(address(stakingVault)), totalPool,
            "StakingVault should hold the full pool");
    }

    // ────────────────────────────────────────────────────────────────────────
    // 15. setRewardEngine governance
    // ────────────────────────────────────────────────────────────────────────

    function test_setRewardEngine_cannotSetTwice() public {
        vm.prank(admin);
        vm.expectRevert("StakingVault: already set");
        stakingVault.setRewardEngine(makeAddr("newRE"));
    }

    function test_setRewardEngine_onlyOwner() public {
        // Deploy a fresh vault without RE set
        StakingVault sv2 = new StakingVault(
            address(psre), address(lpToken), genesis, admin
        );
        vm.prank(alice);
        vm.expectRevert("StakingVault: not owner");
        sv2.setRewardEngine(rewardEngine);
    }

    // ────────────────────────────────────────────────────────────────────────
    // 16. Flash-stake test — late staker gets negligible share
    // ────────────────────────────────────────────────────────────────────────

    function test_flashStake_negligibleVsFullEpochStaker() public {
        uint256 rewardPool = 100e18;

        // Alice stakes for the full epoch
        vm.prank(alice);
        stakingVault.stakePSRE(1000e18);

        // Bob stakes 2 seconds before epoch ends
        vm.warp(genesis + EPOCH - 2);
        vm.prank(bob);
        stakingVault.stakePSRE(1000e18);

        // Warp past epoch end — checkpoint both
        vm.warp(genesis + EPOCH + 1);
        stakingVault.checkpointUser(alice);
        stakingVault.checkpointUser(bob);

        _snapshotAndDistribute(0, rewardPool);

        uint256 aliceContrib = stakingVault.userPSREStakedTime(0, alice);
        uint256 bobContrib   = stakingVault.userPSREStakedTime(0, bob);
        uint256 totalContrib = stakingVault.totalPSREStakedTime(0);

        assertGt(aliceContrib, 0, "Alice should have contribution");
        assertGt(bobContrib, 0,   "Bob should have a small contribution");
        assertGt(aliceContrib, bobContrib * 1000, "Alice >> Bob (flash staker)");

        // Bob's fraction < 0.1%
        uint256 bobFraction = (bobContrib * PRECISION) / totalContrib;
        assertLt(bobFraction, 1e15, "Bob flash-stake fraction should be < 0.1%");

        // Claim and verify proportional rewards
        uint256 psrePool = rewardPool * stakingVault.psreSplit() / PRECISION;

        uint256 aliceBefore = psre.balanceOf(alice);
        vm.prank(alice); stakingVault.claimStake(0);
        uint256 aliceReward = psre.balanceOf(alice) - aliceBefore;

        uint256 bobBefore = psre.balanceOf(bob);
        vm.prank(bob); stakingVault.claimStake(0);
        uint256 bobReward = psre.balanceOf(bob) - bobBefore;

        assertGt(aliceReward, bobReward * 1000, "Alice reward >> Bob reward");
        assertApproxEqRel(aliceReward + bobReward, psrePool, 0.01e18, "total claimed ~= psrePool");
    }

    // ────────────────────────────────────────────────────────────────────────
    // 17. checkpointUser is permissionless
    // ────────────────────────────────────────────────────────────────────────

    function test_checkpointUser_permissionless() public {
        vm.prank(alice);
        stakingVault.stakePSRE(1000e18);

        vm.warp(genesis + EPOCH - 1);

        // Bob can checkpoint Alice (keeper pattern)
        vm.prank(bob);
        stakingVault.checkpointUser(alice);

        uint256 contribution = stakingVault.userPSREStakedTime(0, alice);
        assertGt(contribution, 0, "checkpointUser by third party should record Alice's stakeTime");
    }

    // ────────────────────────────────────────────────────────────────────────
    // 18. claimStake: nothing to claim if no contribution
    // ────────────────────────────────────────────────────────────────────────

    function test_claimStake_revertsIfNothingToClaim() public {
        // Alice staked but Bob did not — Bob tries to claim
        vm.prank(alice);
        stakingVault.stakePSRE(1000e18);
        vm.warp(genesis + EPOCH + 1);
        stakingVault.checkpointUser(alice);
        _snapshotAndDistribute(0, 100e18);

        vm.prank(bob);
        vm.expectRevert("StakingVault: nothing to claim");
        stakingVault.claimStake(0);
    }

    // ────────────────────────────────────────────────────────────────────────
    // 19. epoch helpers correctness
    // ────────────────────────────────────────────────────────────────────────

    function test_epochHelpers() public view {
        assertEq(stakingVault.currentEpochId(), 0, "epoch 0 at genesis");
        assertEq(stakingVault.epochStart(0), genesis, "epoch 0 starts at genesis");
        assertEq(stakingVault.epochEnd(0),   genesis + EPOCH, "epoch 0 ends at genesis + EPOCH");
        assertEq(stakingVault.epochStart(1), genesis + EPOCH, "epoch 1 starts at genesis + EPOCH");
    }
}
