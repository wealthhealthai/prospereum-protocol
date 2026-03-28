// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/core/PartnerVaultFactory.sol";
import "../contracts/core/PartnerVault.sol";
import "../contracts/core/CustomerVault.sol";
import "../contracts/core/PSRE.sol";
import "../contracts/periphery/RewardEngine.sol";
import "../contracts/periphery/StakingVault.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockSwapRouter.sol";

/**
 * @title IntegrationTest v3.2
 * @notice Full lifecycle integration test:
 *         1. Deploy all contracts
 *         2. Create vault (initial buy earns zero)
 *         3. Deploy CustomerVaults
 *         4. Grow ecosystem (buys, direct ERC-20 transfers)
 *         5. First qualification → first reward
 *         6. Ongoing rewards across multiple epochs
 *         7. No reward compounding invariant
 *         8. Vault wash-trade resistance: sell → rebuy required
 *         9. Customer claims ownership + withdraws
 *        10. Two vaults competing for rewards
 */
contract IntegrationTest is Test {
    PartnerVaultFactory public factory;
    PartnerVault        public vaultImpl;
    CustomerVault       public cvImpl;
    RewardEngine        public re;
    StakingVault        public sv;
    PSRE                public psre;
    MockERC20           public usdc;
    MockERC20           public lpToken;
    MockSwapRouter      public router;

    address public admin      = makeAddr("admin");
    address public treasury   = makeAddr("treasury");
    address public teamVest   = makeAddr("teamVest");
    address public partner    = makeAddr("partner");
    address public partner2   = makeAddr("partner2");
    address public customer1  = makeAddr("customer1");
    address public other      = makeAddr("other");

    uint256 public constant PSRE_PER_SWAP = 1000e18;
    uint256 public constant S_MIN_USDC    = 500_000_000; // 500e6
    uint256 public genesis;

    PartnerVault pv1;
    PartnerVault pv2;

    // ── Deploy full protocol ──────────────────────────────────────────────────
    function setUp() public {
        genesis = block.timestamp;

        // Tokens
        psre    = new PSRE(admin, treasury, teamVest, genesis);
        usdc    = new MockERC20("USD Coin", "USDC", 6);
        lpToken = new MockERC20("PSRE-USDC LP", "LP", 18);
        router  = new MockSwapRouter(address(psre), PSRE_PER_SWAP);
        deal(address(psre), address(router), 100_000_000e18);

        // Implementations
        vaultImpl = new PartnerVault();
        cvImpl    = new CustomerVault();

        // StakingVault
        sv = new StakingVault(address(psre), address(lpToken), genesis, admin);

        // Factory
        factory = new PartnerVaultFactory(
            address(vaultImpl), address(cvImpl),
            address(psre), address(router), address(usdc),
            admin
        );

        // RewardEngine — deploy via UUPS proxy (MAJOR-3)
        {
            RewardEngine reImpl = new RewardEngine();
            bytes memory initData = abi.encodeCall(
                RewardEngine.initialize,
                (address(psre), address(factory), address(sv), genesis, admin)
            );
            ERC1967Proxy proxy = new ERC1967Proxy(address(reImpl), initData);
            re = RewardEngine(address(proxy));
        }

        // Wire up
        vm.prank(admin);
        factory.setRewardEngine(address(re));

        vm.prank(admin);
        sv.setRewardEngine(address(re));

        // Grant MINTER_ROLE to RewardEngine
        vm.startPrank(admin);
        psre.grantRole(psre.MINTER_ROLE(), address(re));
        vm.stopPrank();

        // Fund partners
        usdc.mint(partner,  100_000e6);
        usdc.mint(partner2, 100_000e6);
        vm.prank(partner);
        usdc.approve(address(factory), type(uint256).max);
        vm.prank(partner2);
        usdc.approve(address(factory), type(uint256).max);
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    function _advanceAndFinalize(uint256 epochId) internal {
        vm.warp(genesis + (epochId + 1) * 7 days + 1);
        re.finalizeEpoch(epochId);
    }

    function _buyViaBuy(address _partner, PartnerVault pv, uint256 psreAmt) internal {
        router.setPsreOut(psreAmt);
        usdc.mint(_partner, 100e6);
        vm.prank(_partner);
        usdc.approve(address(pv), type(uint256).max);
        vm.prank(_partner);
        pv.buy(100e6, 1, block.timestamp + 1 hours, 3000);
    }

    // ── Test: Full lifecycle ───────────────────────────────────────────────────

    /**
     * @notice Full lifecycle: deploy, initial buy, qualify, earn, claim, repeat.
     */
    function test_fullLifecycle_singlePartner() public {
        // ── 1. Create vault (initial buy = S_MIN_USDC) ──────────────────────
        router.setPsreOut(PSRE_PER_SWAP);
        vm.prank(partner);
        address vaultAddr = factory.createVault(S_MIN_USDC, 1, block.timestamp + 1 hours, 3000);
        pv1 = PartnerVault(vaultAddr);

        // Verify initial state
        assertEq(pv1.initialCumS(), PSRE_PER_SWAP, "initialCumS = initial buy");
        assertEq(pv1.cumS(),        PSRE_PER_SWAP, "cumS starts at initialCumS");
        assertFalse(pv1.qualified(), "not qualified initially");

        // ── 2. Epoch 0: initial buy — earns ZERO reward ──────────────────────
        _advanceAndFinalize(0);
        assertEq(re.owedPartner(vaultAddr), 0, "initial buy epoch earns zero");
        assertFalse(re.qualified(vaultAddr));

        // ── 3. Partner buys more PSRE → cumS grows above initialCumS ─────────
        _buyViaBuy(partner, pv1, PSRE_PER_SWAP);
        uint256 cumSAfterBuy = pv1.cumS();
        assertGt(cumSAfterBuy, pv1.initialCumS(), "cumS > initialCumS after buy");

        // ── 4. Epoch 1: first qualification → first reward ───────────────────
        _advanceAndFinalize(1);
        assertTrue(re.qualified(vaultAddr), "vault should be qualified after epoch 1");
        uint256 firstReward = re.owedPartner(vaultAddr);
        assertGt(firstReward, 0, "first reward should be > 0");

        // ── 5. Claim first reward ─────────────────────────────────────────────
        uint256 balBefore = psre.balanceOf(partner);
        vm.prank(partner);
        re.claimPartnerReward(vaultAddr);
        assertEq(psre.balanceOf(partner), balBefore + firstReward);
        assertEq(re.owedPartner(vaultAddr), 0);

        // ── 6. Epoch 2: another buy, another reward ───────────────────────────
        _buyViaBuy(partner, pv1, PSRE_PER_SWAP);
        _advanceAndFinalize(2);
        uint256 reward2 = re.owedPartner(vaultAddr);
        assertGt(reward2, 0, "epoch 2 reward > 0");

        // ── 7. Epoch 3: no buy → flat epoch → zero reward ────────────────────
        _advanceAndFinalize(3);
        uint256 reward3 = re.owedPartner(vaultAddr);
        assertEq(reward3, reward2, "flat epoch adds zero reward");

        // ── 8. Claim accumulated rewards ─────────────────────────────────────
        vm.prank(partner);
        re.claimPartnerReward(vaultAddr);
        assertEq(psre.balanceOf(partner), firstReward + reward2, "partner receives all rewards");
    }

    /**
     * @notice CustomerVault lifecycle: deploy CV, distribute, customer claims, withdraws.
     */
    function test_customerVault_lifecycle() public {
        router.setPsreOut(PSRE_PER_SWAP);
        vm.prank(partner);
        address vaultAddr = factory.createVault(S_MIN_USDC, 1, block.timestamp + 1 hours, 3000);
        pv1 = PartnerVault(vaultAddr);

        // ── Deploy CustomerVault ─────────────────────────────────────────────
        vm.prank(partner);
        address cvAddr = factory.deployCustomerVault(vaultAddr, customer1);
        CustomerVault cv = CustomerVault(cvAddr);

        // ── Grow ecosystem: buy PSRE ──────────────────────────────────────────
        _buyViaBuy(partner, pv1, PSRE_PER_SWAP);

        // ── Distribute to CustomerVault ──────────────────────────────────────
        uint256 dist = 300e18;
        vm.prank(partner);
        pv1.distributeToCustomer(cvAddr, dist);
        assertEq(psre.balanceOf(cvAddr), dist, "CV should hold distributed PSRE");

        // Distributing doesn't change ecosystemBalance (PSRE stays in ecosystem)
        assertEq(pv1.ecosystemBalance(), PSRE_PER_SWAP + PSRE_PER_SWAP,
            "ecosystemBalance unchanged by distribution");

        // ── Customer claims vault ownership ──────────────────────────────────
        vm.prank(customer1);
        cv.claimVault(customer1);
        assertTrue(cv.customerClaimed());
        assertEq(cv.customer(), customer1);

        // ── Customer withdraws PSRE ──────────────────────────────────────────
        uint256 customerBalBefore = psre.balanceOf(customer1);
        uint256 ecoBefore         = pv1.ecosystemBalance();

        vm.prank(customer1);
        cv.withdraw(dist);

        assertEq(psre.balanceOf(customer1), customerBalBefore + dist);
        assertEq(psre.balanceOf(cvAddr), 0);
        // ecosystemBalance should have decreased via reportLeakage
        assertEq(pv1.ecosystemBalance(), ecoBefore - dist,
            "withdrawal reduces parent ecosystemBalance");
        // cumS ratchet holds
        assertEq(pv1.cumS(), PSRE_PER_SWAP * 2, "cumS ratchet holds after withdrawal");
    }

    /**
     * @notice No compounding: reward PSRE deposited back into vault should not amplify rewards.
     */
    function test_noCompounding_invariant() public {
        router.setPsreOut(PSRE_PER_SWAP);
        vm.prank(partner);
        address vaultAddr = factory.createVault(S_MIN_USDC, 1, block.timestamp + 1 hours, 3000);
        pv1 = PartnerVault(vaultAddr);

        _advanceAndFinalize(0);
        _buyViaBuy(partner, pv1, PSRE_PER_SWAP);
        _advanceAndFinalize(1); // qualifies, earns reward

        uint256 reward1 = re.owedPartner(vaultAddr);
        assertGt(reward1, 0);

        // Partner claims reward
        vm.prank(partner);
        re.claimPartnerReward(vaultAddr);

        // Partner sends the reward PSRE back into the vault (compounding attempt)
        uint256 rewardReceived = psre.balanceOf(partner);
        vm.prank(partner);
        IERC20(address(psre)).transfer(vaultAddr, rewardReceived);

        // Advance epoch — the "re-deposited reward" might bump cumS, but
        // cumulativeRewardMinted deducts it from effectiveCumS
        _advanceAndFinalize(2);

        uint256 reward2 = re.owedPartner(vaultAddr);
        // reward2 should be approximately zero because:
        //   effectiveCumS before = lastEffectiveCumS
        //   cumS increased by rewardReceived (direct transfer)
        //   but cumulativeRewardMinted also increased by reward1
        //   so effectiveCumS ≈ unchanged → delta ≈ 0

        // Allow a small amount from rounding, but not multiplicative amplification
        uint256 maxAllowedCompound = reward1 / 10; // no more than 10% of first reward
        assertLe(reward2, maxAllowedCompound,
            "compounding attempt should not significantly amplify rewards");
    }

    /**
     * @notice Wash-trade resistance: sell → cumS ratchet holds → must rebuy past peak to earn.
     */
    function test_washTradeResistance() public {
        router.setPsreOut(PSRE_PER_SWAP);
        vm.prank(partner);
        address vaultAddr = factory.createVault(S_MIN_USDC, 1, block.timestamp + 1 hours, 3000);
        pv1 = PartnerVault(vaultAddr);

        _advanceAndFinalize(0);
        _buyViaBuy(partner, pv1, PSRE_PER_SWAP);

        uint256 cumSPeak = pv1.cumS();
        _advanceAndFinalize(1); // earns first reward

        uint256 reward1 = re.owedPartner(vaultAddr);
        assertGt(reward1, 0);

        // ── Simulated "sell": partner transfers out PSRE (exits ecosystem) ───
        uint256 ownBalance = psre.balanceOf(vaultAddr);
        vm.prank(partner);
        pv1.transferOut(other, ownBalance);

        // cumS ratchet holds at peak
        assertEq(pv1.cumS(), cumSPeak, "cumS ratchet holds after sell");

        // Epoch 2: no cumS growth → no reward
        _advanceAndFinalize(2);
        uint256 reward2 = re.owedPartner(vaultAddr);
        assertEq(reward2, reward1, "after sell without rebuy, no new reward");

        // ── Rebuy past the peak ──────────────────────────────────────────────
        // Buy just past the peak to get cumS > lastEpochCumS
        uint256 rebuyAmt = cumSPeak + 100e18; // slightly more than peak
        _buyViaBuy(partner, pv1, rebuyAmt);

        assertGt(pv1.cumS(), cumSPeak, "rebuy must bring cumS past prior peak");

        _advanceAndFinalize(3);
        uint256 reward3 = re.owedPartner(vaultAddr);
        assertGt(reward3, reward1, "new reward after rebuy past peak");
    }

    /**
     * @notice Direct ERC-20 transfer to vault address counts as S_eco growth.
     */
    function test_directTransfer_countedInSEco() public {
        router.setPsreOut(PSRE_PER_SWAP);
        vm.prank(partner);
        address vaultAddr = factory.createVault(S_MIN_USDC, 1, block.timestamp + 1 hours, 3000);
        pv1 = PartnerVault(vaultAddr);

        _advanceAndFinalize(0);

        // Customer pays partner directly via ERC-20 transfer to vault address
        uint256 directPmt = 600e18;
        deal(address(psre), customer1, directPmt);
        vm.prank(customer1);
        IERC20(address(psre)).transfer(vaultAddr, directPmt);

        // Epoch 1: snapshotEpoch detects direct transfer → cumS grows → qualifies
        _advanceAndFinalize(1);

        assertTrue(re.qualified(vaultAddr), "direct ERC-20 transfer should trigger qualification");
        assertGt(re.owedPartner(vaultAddr), 0, "direct transfer should earn reward");
    }

    /**
     * @notice S_MIN enforcement: vault creation reverts below $500 USDC.
     */
    function test_sMin_enforcement() public {
        uint256 below = 499_000_000; // 499 USDC < S_MIN

        vm.prank(partner);
        vm.expectRevert("Factory: below S_MIN ($500 USDC)");
        factory.createVault(below, 1, block.timestamp + 1 hours, 3000);
    }

    /**
     * @notice Two vaults: reward split proportional to effectiveCumS delta.
     */
    function test_twoVaults_proportionalRewards() public {
        router.setPsreOut(PSRE_PER_SWAP);

        vm.prank(partner);
        address vault1 = factory.createVault(S_MIN_USDC, 1, block.timestamp + 1 hours, 3000);
        pv1 = PartnerVault(vault1);

        vm.prank(partner2);
        address vault2 = factory.createVault(S_MIN_USDC, 1, block.timestamp + 1 hours, 3000);
        pv2 = PartnerVault(vault2);

        _advanceAndFinalize(0);

        // pv1 buys 2× more than pv2
        _buyViaBuy(partner,  pv1, PSRE_PER_SWAP * 2);
        _buyViaBuy(partner2, pv2, PSRE_PER_SWAP);

        _advanceAndFinalize(1);

        uint256 owed1 = re.owedPartner(vault1);
        uint256 owed2 = re.owedPartner(vault2);

        assertGt(owed1, 0);
        assertGt(owed2, 0);
        // pv1 should earn approximately 2× pv2 (both Bronze tier, same multiplier)
        // owed1 / owed2 ≈ 2 (allow ±5% tolerance)
        uint256 ratio = (owed1 * 100) / owed2;
        assertGe(ratio, 190, "pv1 should earn ~2x pv2 (with 5% tolerance)");
        assertLe(ratio, 210, "pv1 should earn ~2x pv2 (with 5% tolerance)");
    }

    /**
     * @notice Invariant: cumS >= initialCumS at all times.
     */
    function test_invariant_cumSAlwaysGeInitialCumS() public {
        router.setPsreOut(PSRE_PER_SWAP);
        vm.prank(partner);
        address vaultAddr = factory.createVault(S_MIN_USDC, 1, block.timestamp + 1 hours, 3000);
        pv1 = PartnerVault(vaultAddr);

        uint256 initCumS = pv1.initialCumS();

        // Multiple operations
        _advanceAndFinalize(0);
        _buyViaBuy(partner, pv1, PSRE_PER_SWAP);
        _advanceAndFinalize(1);
        uint256 sellAmt = psre.balanceOf(vaultAddr);
        vm.prank(partner);
        pv1.transferOut(other, sellAmt); // sell all
        _advanceAndFinalize(2);
        _buyViaBuy(partner, pv1, PSRE_PER_SWAP);
        _advanceAndFinalize(3);

        // cumS should always be >= initialCumS
        assertGe(pv1.cumS(), initCumS, "cumS >= initialCumS at all times");
    }

    /**
     * @notice Invariant: T (total minted) never exceeds S_EMISSION.
     */
    function test_invariant_totalMintedNeverExceedsEmission() public {
        router.setPsreOut(PSRE_PER_SWAP);
        vm.prank(partner);
        address vaultAddr = factory.createVault(S_MIN_USDC, 1, block.timestamp + 1 hours, 3000);
        pv1 = PartnerVault(vaultAddr);

        for (uint256 eid = 0; eid <= 10; eid++) {
            if (eid > 0) _buyViaBuy(partner, pv1, PSRE_PER_SWAP);
            _advanceAndFinalize(eid);
            assertLe(re.T(), re.S_EMISSION(), "T <= S_EMISSION");
        }
    }

    /**
     * @notice effectiveCumS >= 0 at all times.
     */
    function test_invariant_effectiveCumSNonNegative() public {
        router.setPsreOut(PSRE_PER_SWAP);
        vm.prank(partner);
        address vaultAddr = factory.createVault(S_MIN_USDC, 1, block.timestamp + 1 hours, 3000);
        pv1 = PartnerVault(vaultAddr);

        for (uint256 eid = 0; eid <= 5; eid++) {
            if (eid > 0 && eid % 2 == 0) _buyViaBuy(partner, pv1, PSRE_PER_SWAP);
            _advanceAndFinalize(eid);
            assertGe(re.effectiveCumSOf(vaultAddr), 0, "effectiveCumS >= 0");
        }
    }

    /**
     * @notice cumulativeRewardMinted is monotonically non-decreasing.
     */
    function test_invariant_cumulativeRewardMintedNonDecreasing() public {
        router.setPsreOut(PSRE_PER_SWAP);
        vm.prank(partner);
        address vaultAddr = factory.createVault(S_MIN_USDC, 1, block.timestamp + 1 hours, 3000);
        pv1 = PartnerVault(vaultAddr);

        uint256 prevCrm = 0;
        for (uint256 eid = 0; eid <= 5; eid++) {
            if (eid > 0) _buyViaBuy(partner, pv1, PSRE_PER_SWAP);
            _advanceAndFinalize(eid);

            uint256 crm = re.cumulativeRewardMinted(vaultAddr);
            assertGe(crm, prevCrm, "cumulativeRewardMinted is non-decreasing");
            prevCrm = crm;
        }
    }

    /**
     * @notice Factory S_MIN constant is correct (500 USDC, 6 decimals).
     */
    function test_factorySMin_isCorrect() public view {
        assertEq(factory.S_MIN(), 500_000_000);
    }
}
