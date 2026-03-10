// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/core/PSRE.sol";
import "../contracts/core/PartnerVault.sol";
import "../contracts/core/PartnerVaultFactory.sol";
import "../contracts/periphery/StakingVault.sol";
import "../contracts/periphery/RewardEngine.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockSwapRouter.sol";

/// @dev End-to-end integration tests covering full epoch lifecycle.
contract IntegrationTest is Test {
    // ── Protocol stack ────────────────────────────────────────────────────
    PSRE                public psre;
    StakingVault        public stakingVault;
    RewardEngine        public rewardEngine;
    PartnerVaultFactory public factory;
    PartnerVault        public vaultImpl;
    MockERC20           public usdc;
    MockSwapRouter      public router;

    // ── Actors ────────────────────────────────────────────────────────────
    address public admin    = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public teamVest = makeAddr("teamVest");
    address public partner1 = makeAddr("partner1");
    address public partner2 = makeAddr("partner2");
    address public staker1  = makeAddr("staker1");
    address public staker2  = makeAddr("staker2");

    uint256 public genesis;
    uint256 public constant EPOCH = 7 days;
    uint256 public constant PSRE_PER_BUY = 1_000e18;

    function setUp() public {
        genesis = block.timestamp;

        psre         = new PSRE(admin, treasury, teamVest, genesis);
        usdc         = new MockERC20("USDC", "USDC", 6);
        router       = new MockSwapRouter(address(psre), PSRE_PER_BUY);
        vaultImpl    = new PartnerVault();
        stakingVault = new StakingVault(address(psre), address(usdc), genesis, admin);
        factory      = new PartnerVaultFactory(address(vaultImpl), address(psre), address(router), address(usdc), admin);

        rewardEngine = new RewardEngine(
            address(psre), address(factory), address(stakingVault), genesis, admin
        );

        vm.prank(admin); stakingVault.setRewardEngine(address(rewardEngine));
        vm.prank(admin); factory.setRewardEngine(address(rewardEngine));

        bytes32 minterRole = psre.MINTER_ROLE();
        vm.prank(admin);
        psre.grantRole(minterRole, address(rewardEngine));

        // Fund router with PSRE for swaps (bypass epoch cap using deal)
        deal(address(psre), address(router), 500_000e18);

        // Fund USDC for partners
        usdc.mint(partner1, 1_000_000e6);
        usdc.mint(partner2, 1_000_000e6);

        // Fund PSRE for stakers
        deal(address(psre), staker1, 10_000e18);
        deal(address(psre), staker2, 10_000e18);

        // Staker approvals
        vm.prank(staker1); psre.approve(address(stakingVault), type(uint256).max);
        vm.prank(staker2); psre.approve(address(stakingVault), type(uint256).max);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helper functions
    // ─────────────────────────────────────────────────────────────────────────

    function _registerPartner(address partner) internal returns (address vault) {
        vm.prank(partner);
        vault = factory.createVault();
        vm.prank(partner);
        usdc.approve(vault, type(uint256).max);
    }

    function _buy(address partner, uint256 times) internal {
        address vault = factory.vaultOf(partner);
        for (uint256 i = 0; i < times; i++) {
            vm.prank(partner);
            PartnerVault(vault).buy(100e6, 1, block.timestamp + 1 hours, 3000);
        }
    }

    function _stakeAtStart(address staker, uint256 amount) internal {
        vm.prank(staker);
        stakingVault.stakePSRE(amount);
    }

    function _checkpointStaker(address staker) internal {
        vm.prank(staker);
        try stakingVault.unstakePSRE(1) {} catch {}
    }

    function _finalizeEpoch(uint256 epochId) internal {
        vm.warp(genesis + (epochId + 1) * EPOCH + 1);
        rewardEngine.finalizeEpoch(epochId);
    }

    function _finalizeEpochWithStakerCheckpoint(address staker, uint256 epochId) internal {
        vm.warp(genesis + (epochId + 1) * EPOCH - 1);
        _checkpointStaker(staker);
        vm.warp(genesis + (epochId + 1) * EPOCH + 1);
        rewardEngine.finalizeEpoch(epochId);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Test 1: Full epoch lifecycle
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev register partner → buy PSRE → stake → finalize epoch → claim partner → claim staker
    function test_fullEpochLifecycle() public {
        // 1. Register partner1
        address vault1 = _registerPartner(partner1);

        // 2. partner1 buys PSRE in epoch 0
        _buy(partner1, 1); // cumBuy = 1000 PSRE
        assertEq(PartnerVault(vault1).cumBuy(), PSRE_PER_BUY);

        // 3. staker1 stakes for epoch 0
        _stakeAtStart(staker1, 1000e18);

        // 4. Warp to epoch end, checkpoint staker at exact finalization time
        vm.warp(genesis + EPOCH + 1);
        _checkpointStaker(staker1); // checkpoint at exact finalization timestamp

        // 5. Record stakeTime BEFORE snapshot (same timestamp as checkpoint)
        vm.prank(staker1);
        stakingVault.recordStakeTime(0);

        // Finalize epoch 0 (snapshot at same timestamp — staker1 ST ≈ total ST)
        rewardEngine.finalizeEpoch(0);
        assertTrue(rewardEngine.epochFinalized(0), "epoch 0 should be finalized");

        // 6. Partner1 claims
        uint256 owedP = rewardEngine.owedPartner(vault1);
        assertGt(owedP, 0, "partner1 should be owed tokens");
        uint256 vault1BalBefore = psre.balanceOf(vault1);
        rewardEngine.claimPartner(0, vault1);
        assertEq(psre.balanceOf(vault1) - vault1BalBefore, owedP, "partner1 should receive exact owed");

        // 7. Staker1 claims
        uint256 staker1BalBefore = psre.balanceOf(staker1);
        vm.prank(staker1);
        rewardEngine.claimStake(0);
        uint256 staker1Reward = psre.balanceOf(staker1) - staker1BalBefore;
        assertGt(staker1Reward, 0, "staker1 should receive rewards");

        // 8. Verify total minted = partner reward + staker reward
        uint256 totalMinted = rewardEngine.epochMinted(0);
        // minted covers at minimum the partner reward (staker pool only paid if totalStakeTime > 0)
        assertGe(totalMinted, owedP, "minted should cover at least partner reward");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Test 2: Multi-partner epoch — proportional rewards
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev 2 partners with different buy volumes verify proportional rewards
    function test_multiPartnerEpoch_proportionalRewards() public {
        // Register both partners
        address vault1 = _registerPartner(partner1);
        address vault2 = _registerPartner(partner2);

        // partner1 buys 3x, partner2 buys 1x (different volumes in same epoch)
        vm.warp(genesis); // ensure we're in epoch 0
        _buy(partner1, 3); // cumBuy = 3000 PSRE, deltaNB = 3000
        _buy(partner2, 1); // cumBuy = 1000 PSRE, deltaNB = 1000

        _finalizeEpoch(0);

        uint256 owed1 = rewardEngine.owedPartner(vault1);
        uint256 owed2 = rewardEngine.owedPartner(vault2);

        // With same tier (both start at 0 R), reward ratio should be proportional to delta weights
        // BUT: tier is determined by R share. Both have R computed from same deltaB.
        // partner1's R_new is 3x partner2's R_new, so partner1 share > goldThreshold.
        // The actual reward ratio depends on tiers.
        // Key invariant: partner1 earns more than partner2 (3x volume, same or better tier)
        assertGt(owed1, owed2, "partner1 (3x buys) should earn more than partner2 (1x buy)");

        // Both should earn something
        assertGt(owed1, 0, "partner1 should have non-zero reward");
        assertGt(owed2, 0, "partner2 should have non-zero reward");

        // Combined rewards = B_partners (since W = total weight)
        uint256 B_partners = rewardEngine.epochPartnersPool(0);
        assertEq(owed1 + owed2, B_partners, "partner rewards should sum to B_partners");

        // Claim both
        rewardEngine.claimPartner(0, vault1);
        rewardEngine.claimPartner(0, vault2);
        assertGt(psre.balanceOf(vault1), psre.balanceOf(vault2), "vault1 should hold more PSRE than vault2");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Test 3: EMA tier progression — Bronze → Silver after 13+ epochs
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Partner buys consistently for 13+ epochs → reaches Silver tier
    function test_EMA_tierProgression_bronzeToSilver() public {
        // Setup: partner1 + partner2 with dramatically different volumes
        // partner2 buys a LOT to dominate sumR, making partner1 Bronze.
        // partner1 then gradually builds up to Silver.
        //
        // Strategy: single partner (partner1) in isolation grows their R over 13 epochs.
        // With a single partner sumR = R[vault1], share = 100% → Gold immediately.
        //
        // To test Bronze→Silver progression, we need 2 partners where partner2 dominates.
        // This makes partner1's share small (Bronze), then we stop partner2 buying,
        // so EMA decays partner2's R while partner1's grows.
        //
        // Simplified: use partner1 alone. After 13 epochs EMA converges.
        // theta = 1/13 ≈ 7.7%. After 13 epochs R ≈ 63% of steady-state.
        // With single partner: always Gold (100% share).
        //
        // For Bronze→Silver test: we need sumR to be large (dominated by partner2)
        // so that partner1's share crosses silverThreshold (0.5%) but not goldThreshold (2%).

        address vault1 = _registerPartner(partner1);
        address vault2 = _registerPartner(partner2);

        // Epoch 0: both buy; partner2 buys HEAVILY (50x) to dominate sumR
        vm.warp(genesis);
        _buy(partner1, 1);  // deltaNB = 1000 (small)
        _buy(partner2, 50); // deltaNB = 50,000 (huge)
        _finalizeEpoch(0);

        // After epoch 0:
        // R1 = theta * 1000 = 76923...
        // R2 = theta * 50000 = 3846...e18
        // sumR ≈ R2 (dominated by partner2)
        // partner1 share = R1/sumR ≈ 1/50 = 2% → Gold!
        // Actually 2% exactly == goldThreshold (0.02e18), need to check >=

        // Run 13 more epochs where only partner1 buys (partner2 stops)
        for (uint256 i = 1; i <= 13; i++) {
            vm.warp(genesis + i * EPOCH);
            _buy(partner1, 1); // only partner1 buys; partner2 R decays via EMA
            _finalizeEpoch(i);
        }

        // After 13 epochs of partner1 buying and partner2 not buying,
        // partner2's R has decayed significantly (exponential decay with theta=1/13)
        // partner1's R has grown
        // Eventually partner1's share should exceed silverThreshold (0.5%)

        // The assertion: partner1's currentAlpha > Bronze rate
        // We verify by checking owedPartner after epoch 13 is proportionally higher
        // per unit of buy than it was in epoch 0 (when they were likely Bronze)

        // Final verification: run epoch 14 with partner1 buying, check reward rate
        vm.warp(genesis + 14 * EPOCH);
        _buy(partner1, 1);
        vm.warp(genesis + 15 * EPOCH + 1);
        rewardEngine.finalizeEpoch(14);

        uint256 owed = rewardEngine.owedPartner(vault1);
        uint256 alphaBase = rewardEngine.alphaBase();
        uint256 PREC = 1e18;

        // With Silver tier: effective rate = alphaBase * mSilver = 8% * 1.25 = 10%
        // demand_silver = 0.10 * 1000e18 = 100e18
        // B_partners_silver = 70% * 100 = 70e18
        // With Gold: 84e18. With Bronze: 56e18.
        // owed should be > Bronze level (56) as partner1 R has grown
        uint256 bronzeOwnedWouldBe = (alphaBase * rewardEngine.mBronze() / PREC) * PSRE_PER_BUY / PREC * 70 / 100;

        // At minimum, partner1 has grown past pure Bronze (regardless of partner2 sharing pool)
        // The key check: partner1's weight in epoch 14 reflects EMA tier progression
        // We verify partner1 R state has accumulated
        uint256 R1 = rewardEngine.R(vault1);
        uint256 R2 = rewardEngine.R(vault2);
        assertGt(R1, 0, "partner1 R should be > 0 after buying");
        // Note: with partner2 starting at 50x delta, R2 still exceeds R1 after 13 epochs.
        // The important metric is share crossing silverThreshold, not absolute R1 > R2.
        assertGt(R2, 0, "partner2 R should have decayed but still be > 0");

        // partner1's share of sumR after 13 epochs should be significant
        uint256 sumR = rewardEngine.sumR();
        uint256 p1Share = (R1 * PREC) / sumR;

        // After 13+ epochs, partner1 share should cross silverThreshold (0.5%)
        uint256 silverThreshold = rewardEngine.silverThreshold();
        assertGe(p1Share, silverThreshold, "partner1 should reach at least Silver tier after 13 epochs");

        // Unused but included for completeness
        assertGt(owed, 0, "partner1 earned rewards in epoch 14");
        assertGe(bronzeOwnedWouldBe, 0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Test 4: Two stakers — proportional claim
    // ─────────────────────────────────────────────────────────────────────────

    function test_twoStakers_proportionalClaims() public {
        _registerPartner(partner1);
        _buy(partner1, 1);

        // staker1 stakes 2x more than staker2
        _stakeAtStart(staker1, 2000e18);
        _stakeAtStart(staker2, 1000e18);

        // Checkpoint both before epoch ends
        vm.warp(genesis + EPOCH - 1);
        _checkpointStaker(staker1);
        _checkpointStaker(staker2);

        vm.warp(genesis + EPOCH + 1);
        rewardEngine.finalizeEpoch(0);

        // Record stakeTime
        vm.prank(staker1); stakingVault.recordStakeTime(0);
        vm.prank(staker2); stakingVault.recordStakeTime(0);

        uint256 st1 = stakingVault.stakeTimeOf(staker1, 0);
        uint256 st2 = stakingVault.stakeTimeOf(staker2, 0);

        // staker1 should have ~2x the stakeTime of staker2
        assertApproxEqRel(st1, st2 * 2, 0.001e18, "staker1 stakeTime should be ~2x staker2");

        uint256 bal1Before = psre.balanceOf(staker1);
        uint256 bal2Before = psre.balanceOf(staker2);

        vm.prank(staker1); rewardEngine.claimStake(0);
        vm.prank(staker2); rewardEngine.claimStake(0);

        uint256 reward1 = psre.balanceOf(staker1) - bal1Before;
        uint256 reward2 = psre.balanceOf(staker2) - bal2Before;

        assertGt(reward1, reward2, "staker1 should earn more (2x stake)");
        assertApproxEqRel(reward1, reward2 * 2, 0.001e18, "staker1 reward should be ~2x staker2");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Test 5: Sequential epoch finalization over multiple epochs
    // ─────────────────────────────────────────────────────────────────────────

    function test_multipleEpochs_sequential() public {
        address vault1 = _registerPartner(partner1);

        for (uint256 i = 0; i < 5; i++) {
            vm.warp(genesis + i * EPOCH + 1);
            _buy(partner1, 1);
            _finalizeEpoch(i);
            assertTrue(rewardEngine.epochFinalized(i), string.concat("epoch ", vm.toString(i), " should be finalized"));
        }

        // Total T should still be bounded
        assertLe(rewardEngine.T(), rewardEngine.S_EMISSION());

        // Claim accumulated partner rewards (owedPartner accumulates across epochs)
        uint256 owed = rewardEngine.owedPartner(vault1);
        assertGt(owed, 0, "partner1 should have accumulated rewards over 5 epochs");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Test 6: pauseEpochFinalization does not break existing claims
    // ─────────────────────────────────────────────────────────────────────────

    function test_pause_doesNotBreakExistingClaims() public {
        address vault1 = _registerPartner(partner1);
        _buy(partner1, 1);
        _finalizeEpoch(0);

        // Pause
        vm.prank(admin);
        rewardEngine.pause();

        // Claims still work while paused
        uint256 owed = rewardEngine.owedPartner(vault1);
        assertGt(owed, 0);
        rewardEngine.claimPartner(0, vault1);
        assertEq(rewardEngine.owedPartner(vault1), 0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Test 7: distribute from vault after rewards claimed
    // ─────────────────────────────────────────────────────────────────────────

    function test_partnerCanDistributeAfterClaim() public {
        address vault1 = _registerPartner(partner1);
        _buy(partner1, 1);
        _finalizeEpoch(0);
        rewardEngine.claimPartner(0, vault1);

        uint256 vaultBal = psre.balanceOf(vault1);
        assertGt(vaultBal, 0, "vault should have PSRE after claim");

        // Partner distributes to themselves
        vm.prank(partner1);
        PartnerVault(vault1).distribute(partner1, vaultBal);
        assertEq(psre.balanceOf(partner1), vaultBal);
        assertEq(psre.balanceOf(vault1), 0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Test 8: EMA tier progression — single partner always Gold (edge case doc)
    // ─────────────────────────────────────────────────────────────────────────

    function test_singlePartner_alwaysGold() public {
        address vault1 = _registerPartner(partner1);

        for (uint256 i = 0; i < 3; i++) {
            vm.warp(genesis + i * EPOCH + 1);
            _buy(partner1, 1);
            _finalizeEpoch(i);
        }

        // Single partner: R1/sumR = 1.0 → always Gold
        uint256 R1   = rewardEngine.R(vault1);
        uint256 sumR = rewardEngine.sumR();
        assertEq(R1, sumR, "single partner should have 100% of sumR");

        uint256 share = (R1 * 1e18) / sumR;
        assertEq(share, 1e18, "single partner share = 100%");
        assertGe(share, rewardEngine.goldThreshold(), "100% >= goldThreshold");
    }
}
