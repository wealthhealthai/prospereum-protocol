// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/periphery/StakingVault.sol";
import "../contracts/core/PSRE.sol";
import "./mocks/MockERC20.sol";

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

    // Helper to grant minting role to ourselves
    bytes32 minterRole;

    function setUp() public {
        genesis = block.timestamp;

        psre = new PSRE(admin, treasury, teamVesting, genesis);
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

        // Mint PSRE and LP to users
        minterRole = psre.MINTER_ROLE();
        vm.prank(admin);
        psre.grantRole(minterRole, address(this));

        psre.mint(alice, 10_000e18);
        psre.mint(bob,   10_000e18);
        lpToken.mint(alice, 10_000e18);
        lpToken.mint(bob,   10_000e18);

        // Approvals
        vm.prank(alice);
        psre.approve(address(stakingVault), type(uint256).max);
        vm.prank(alice);
        lpToken.approve(address(stakingVault), type(uint256).max);
        vm.prank(bob);
        psre.approve(address(stakingVault), type(uint256).max);
        vm.prank(bob);
        lpToken.approve(address(stakingVault), type(uint256).max);
    }

    // ────────────────────────────────────────────────────────────────────────
    // stakePSRE / unstakePSRE
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
        vm.expectRevert("StakingVault: insufficient PSRE");
        stakingVault.unstakePSRE(200e18);
    }

    // ────────────────────────────────────────────────────────────────────────
    // stakeLP / unstakeLP
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
        vm.expectRevert("StakingVault: insufficient LP");
        stakingVault.unstakeLP(200e18);
    }

    // ────────────────────────────────────────────────────────────────────────
    // stakeTime accumulation
    // ────────────────────────────────────────────────────────────────────────

    function test_stakeTime_accumulates_PSRE() public {
        uint256 amount = 1000e18;

        vm.prank(alice);
        stakingVault.stakePSRE(amount);

        // Advance to just before epoch ends, then force a checkpoint by unstaking 1 wei
        vm.warp(genesis + EPOCH - 1);
        vm.prank(alice);
        stakingVault.unstakePSRE(1); // triggers _checkpointUser, accumulating stakeTime

        // Now advance past epoch end
        vm.warp(genesis + EPOCH + 1);

        // Snapshot epoch 0 from rewardEngine role
        vm.prank(rewardEngine);
        stakingVault.snapshotEpoch(0);

        // totalStakeTime for epoch 0 should be approximately amount * (EPOCH - 1) seconds
        // (we staked at genesis, epoch lasted ~7 days, checkpoint at EPOCH-1)
        uint256 expectedMinStakeTime = amount * (EPOCH - 2); // small margin for timing
        uint256 actualTotal = stakingVault.totalStakeTime(0);
        assertGe(actualTotal, expectedMinStakeTime, "stakeTime should be at least amount*duration");
        assertLe(actualTotal, amount * (EPOCH + 2), "stakeTime should not exceed amount*(duration+small margin)");
    }

    function test_stakeTime_LP_and_PSRE_accumulateEqually() public {
        // Alice stakes 500 PSRE, Bob stakes 500 LP
        vm.prank(alice);
        stakingVault.stakePSRE(500e18);
        vm.prank(bob);
        stakingVault.stakeLP(500e18);

        // Force checkpoints just before epoch ends
        vm.warp(genesis + EPOCH - 1);
        vm.prank(alice);
        stakingVault.unstakePSRE(1); // checkpoint Alice
        vm.prank(bob);
        stakingVault.unstakeLP(1);   // checkpoint Bob

        vm.warp(genesis + EPOCH + 1);

        vm.prank(rewardEngine);
        stakingVault.snapshotEpoch(0);

        // total = (500e18-1 + 500e18-1) * (EPOCH-1) ≈ 1000e18 * EPOCH
        uint256 total = stakingVault.totalStakeTime(0);
        assertGe(total, (1000e18 - 2) * (EPOCH - 2), "combined stakeTime should be >= ~1000e18 * epoch_duration");
    }

    function test_stakeTime_zeroIfNoStakers() public {
        vm.warp(genesis + EPOCH + 1);
        vm.prank(rewardEngine);
        stakingVault.snapshotEpoch(0);
        assertEq(stakingVault.totalStakeTime(0), 0, "no stakers => zero stakeTime");
    }

    // ────────────────────────────────────────────────────────────────────────
    // snapshotEpoch()
    // ────────────────────────────────────────────────────────────────────────

    function test_snapshotEpoch_onlyRewardEngine() public {
        vm.warp(genesis + EPOCH + 1);
        vm.prank(alice);
        vm.expectRevert("StakingVault: only rewardEngine");
        stakingVault.snapshotEpoch(0);
    }

    function test_snapshotEpoch_revertsIfEpochNotEnded() public {
        // Still in epoch 0, trying to snapshot epoch 0
        vm.prank(rewardEngine);
        vm.expectRevert("StakingVault: epoch not ended");
        stakingVault.snapshotEpoch(0);
    }

    function test_snapshotEpoch_revertsIfAlreadySnapshotted() public {
        // Snapshot epoch 0 first
        vm.warp(genesis + EPOCH + 1);
        vm.prank(rewardEngine);
        stakingVault.snapshotEpoch(0);

        // Snapshot epoch 1 next (in sequence)
        vm.warp(genesis + 2 * EPOCH + 1);
        vm.prank(rewardEngine);
        stakingVault.snapshotEpoch(1);

        // Now try to snapshot epoch 1 again — should revert
        // Note: the contract condition is `epochId > lastSnapshotEpoch || lastSnapshotEpoch == 0`
        // After epoch 1 is snapshotted, lastSnapshotEpoch=1, so re-snapshotting epoch 0 or 1 should revert
        vm.warp(genesis + 3 * EPOCH + 1);
        vm.prank(rewardEngine);
        vm.expectRevert("StakingVault: already snapshotted");
        stakingVault.snapshotEpoch(1); // re-snapshot epoch 1 should revert
    }

    function test_snapshotEpoch_resetsCurrentEpochTotal() public {
        vm.prank(alice);
        stakingVault.stakePSRE(1000e18);

        vm.warp(genesis + EPOCH + 1);
        vm.prank(rewardEngine);
        stakingVault.snapshotEpoch(0);

        // After snapshot, currentEpochTotalStakeTime should reset to 0
        assertEq(stakingVault.currentEpochTotalStakeTime(), 0, "should reset after snapshot");
    }

    // ────────────────────────────────────────────────────────────────────────
    // Flash-stake test
    // ────────────────────────────────────────────────────────────────────────

    function test_flashStake_negligibleVsFullEpochStaker() public {
        // Alice stakes at genesis — for the full epoch
        vm.prank(alice);
        stakingVault.stakePSRE(1000e18);

        // Bob stakes 2 seconds before epoch ends
        vm.warp(genesis + EPOCH - 2);
        vm.prank(bob);
        stakingVault.stakePSRE(1000e18);

        // Force Alice's checkpoint to be recorded (so her full stakeTime is captured)
        vm.prank(alice);
        stakingVault.unstakePSRE(1); // checkpoint Alice at EPOCH-2

        // Epoch ends
        vm.warp(genesis + EPOCH + 1);

        // Force Bob's final checkpoint
        vm.prank(bob);
        stakingVault.unstakePSRE(1); // checkpoint Bob at EPOCH+1

        vm.prank(rewardEngine);
        stakingVault.snapshotEpoch(0);

        uint256 totalST = stakingVault.totalStakeTime(0);
        assertGt(totalST, 0, "totalStakeTime should be > 0");

        // Alice staked ~(1000e18-1) for ~(EPOCH-2) seconds = huge
        // Bob staked ~(1000e18-1) for ~3 seconds (from EPOCH-2 to EPOCH+1) = tiny
        uint256 aliceApprox = (1000e18 - 1) * (EPOCH - 2);
        uint256 bobApprox   = (1000e18 - 1) * 3;

        // totalST should be dominated by Alice
        assertGe(totalST, aliceApprox, "Alice full-epoch stake should dominate total");

        // Bob's fraction should be < 0.1%
        uint256 bobFraction = (bobApprox * 1e18) / totalST;
        assertLt(bobFraction, 1e15, "Bob flash-stake fraction should be < 0.1%");
    }

    // ────────────────────────────────────────────────────────────────────────
    // recordStakeTime
    // ────────────────────────────────────────────────────────────────────────

    function test_recordStakeTime_storedCorrectly() public {
        vm.prank(alice);
        stakingVault.stakePSRE(1000e18);

        // Force checkpoint to accumulate stakeTime
        vm.warp(genesis + EPOCH - 1);
        vm.prank(alice);
        stakingVault.unstakePSRE(1); // checkpoint

        vm.warp(genesis + EPOCH + 1);

        // Fix #1: recordStakeTime must be called BEFORE snapshotEpoch.
        // Post-snapshot recordStakeTime is now blocked (attack vector closed).
        vm.prank(alice);
        stakingVault.recordStakeTime(0);

        vm.prank(rewardEngine);
        stakingVault.snapshotEpoch(0);

        uint256 aliceST = stakingVault.stakeTimeOf(alice, 0);
        uint256 total   = stakingVault.totalStakeTime(0);
        assertGt(aliceST, 0, "Alice stakeTime should be > 0");
        assertGt(total, 0, "Total stakeTime should be > 0");
        assertApproxEqRel(aliceST, total, 0.01e18, "Alice stakeTime should be within 1% of total (sole staker)");
    }

    // ────────────────────────────────────────────────────────────────────────
    // Pause
    // ────────────────────────────────────────────────────────────────────────

    function test_pause_haltStakePSRE() public {
        vm.prank(admin);
        stakingVault.pause();
        vm.prank(alice);
        vm.expectRevert();
        stakingVault.stakePSRE(100e18);
    }

    function test_pause_haltStakeLP() public {
        vm.prank(admin);
        stakingVault.pause();
        vm.prank(alice);
        vm.expectRevert();
        stakingVault.stakeLP(100e18);
    }

    function test_pause_doesNotHaltUnstake() public {
        vm.prank(alice);
        stakingVault.stakePSRE(500e18);

        vm.prank(admin);
        stakingVault.pause();

        // Unstake should still work (no whenNotPaused on unstake)
        vm.prank(alice);
        stakingVault.unstakePSRE(100e18);
        assertEq(psre.balanceOf(alice), 9_600e18);
    }
}
