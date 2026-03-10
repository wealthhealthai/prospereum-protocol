// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/periphery/TeamVesting.sol";
import "../contracts/core/PSRE.sol";
import "./mocks/MockERC20.sol";

contract TeamVestingTest is Test {
    TeamVesting public vesting;
    PSRE        public psre;

    address public admin       = makeAddr("admin");
    address public treasury    = makeAddr("treasury");
    address public beneficiary1 = makeAddr("beneficiary1");
    address public beneficiary2 = makeAddr("beneficiary2");
    address public outsider    = makeAddr("outsider");

    uint256 public genesis;

    // Total allocation = 4,200,000e18
    uint256 public constant TOTAL_TEAM_ALLOC = 4_200_000e18;
    uint256 public alloc1 = 2_100_000e18; // 50% each
    uint256 public alloc2 = 2_100_000e18;

    uint256 public CLIFF; // genesis + 365 days
    uint256 public VEST_END; // cliff + 4*365 days

    function setUp() public {
        genesis = block.timestamp;

        // Deploy PSRE with TeamVesting address as receiver — but we need TeamVesting first.
        // Trick: deploy TeamVesting independently with its own PSRE reference.
        // In production, PSRE constructor mints to teamVesting address.
        // In tests: deploy a standalone PSRE with treasury=treasury, teamVesting=address(vesting)
        // But we don't have vesting address yet. Use two-step: deploy then fund.

        // Deploy PSRE with a placeholder teamVesting address (treasury for now)
        psre = new PSRE(admin, treasury, treasury, genesis); // treasury receives both allocations

        // Setup beneficiaries
        address[] memory bens = new address[](2);
        bens[0] = beneficiary1;
        bens[1] = beneficiary2;

        uint256[] memory allocs = new uint256[](2);
        allocs[0] = alloc1;
        allocs[1] = alloc2;

        vesting = new TeamVesting(address(psre), genesis, bens, allocs);

        CLIFF    = vesting.cliffEnd();
        VEST_END = vesting.vestEnd();

        // Fund the vesting contract with PSRE (simulate what PSRE constructor would do)
        // In test, treasury received the tokens; transfer them to vesting
        vm.prank(treasury);
        psre.transfer(address(vesting), TOTAL_TEAM_ALLOC);

        assertEq(psre.balanceOf(address(vesting)), TOTAL_TEAM_ALLOC, "vesting should hold team alloc");
    }

    // ────────────────────────────────────────────────────────────────────────
    // Cliff period (0 to 1 year)
    // ────────────────────────────────────────────────────────────────────────

    function test_noTokensClaimableBeforeCliff() public view {
        // At genesis — cliff hasn't started
        assertEq(vesting.claimableOf(beneficiary1), 0, "nothing claimable at genesis");
        assertEq(vesting.claimableOf(beneficiary2), 0);
    }

    function test_noTokensClaimableJustBeforeCliff() public {
        vm.warp(CLIFF - 1);
        assertEq(vesting.claimableOf(beneficiary1), 0, "nothing claimable 1 second before cliff end");
    }

    function test_claimRevertsBeforeCliff() public {
        vm.warp(genesis + 30 days);
        vm.prank(beneficiary1);
        vm.expectRevert("TeamVesting: still in cliff period");
        vesting.claim();
    }

    // ────────────────────────────────────────────────────────────────────────
    // At cliff end: linear vesting begins (0 tokens from cliff period itself)
    // ────────────────────────────────────────────────────────────────────────

    function test_atCliffEnd_zeroVested() public {
        // At exact cliff end: 0 time has passed in vesting period → 0 vested
        vm.warp(CLIFF);
        assertEq(vesting.claimableOf(beneficiary1), 0, "at exact cliff end: 0 vested (linear begins from cliffEnd)");
    }

    function test_atCliffEnd_plus1Second_tinyAmount() public {
        vm.warp(CLIFF + 1);
        uint256 claimable = vesting.claimableOf(beneficiary1);
        // vested = alloc1 * 1 / VEST_DURATION
        uint256 expected = (alloc1 * 1) / vesting.VEST_DURATION();
        assertEq(claimable, expected, "1 second into vest period: tiny amount");
    }

    // ────────────────────────────────────────────────────────────────────────
    // At vest end: 100% claimable
    // ────────────────────────────────────────────────────────────────────────

    function test_atVestEnd_100pctClaimable() public {
        vm.warp(VEST_END);
        assertEq(vesting.claimableOf(beneficiary1), alloc1, "at vestEnd: full allocation claimable");
        assertEq(vesting.claimableOf(beneficiary2), alloc2, "at vestEnd: full allocation claimable");
    }

    function test_afterVestEnd_100pctClaimable() public {
        vm.warp(VEST_END + 365 days);
        assertEq(vesting.claimableOf(beneficiary1), alloc1, "after vestEnd: still full allocation");
    }

    function test_atVestEnd_canClaimFull() public {
        vm.warp(VEST_END);
        vm.prank(beneficiary1);
        vesting.claim();
        assertEq(psre.balanceOf(beneficiary1), alloc1);
    }

    // ────────────────────────────────────────────────────────────────────────
    // Linear interpolation at 50% through vest period
    // ────────────────────────────────────────────────────────────────────────

    function test_linear_50pct_of_vestPeriod() public {
        uint256 VEST_DURATION = vesting.VEST_DURATION();
        vm.warp(CLIFF + VEST_DURATION / 2);

        uint256 claimable = vesting.claimableOf(beneficiary1);
        uint256 expected  = alloc1 / 2; // 50% vested at 50% of vest duration

        // Allow 1 wei rounding
        assertApproxEqAbs(claimable, expected, 1, "50% through vest period: ~50% claimable");
    }

    function test_linear_25pct_of_vestPeriod() public {
        uint256 VEST_DURATION = vesting.VEST_DURATION();
        vm.warp(CLIFF + VEST_DURATION / 4);

        uint256 claimable = vesting.claimableOf(beneficiary1);
        uint256 expected  = alloc1 / 4;
        assertApproxEqAbs(claimable, expected, 1, "25% through vest period: ~25% claimable");
    }

    // ────────────────────────────────────────────────────────────────────────
    // Non-beneficiary cannot claim
    // ────────────────────────────────────────────────────────────────────────

    function test_nonBeneficiary_cannotClaim() public {
        vm.warp(VEST_END);
        vm.prank(outsider);
        vm.expectRevert("TeamVesting: not a beneficiary");
        vesting.claim();
    }

    function test_nonBeneficiary_claimableIsZero() public view {
        assertEq(vesting.claimableOf(outsider), 0);
    }

    // ────────────────────────────────────────────────────────────────────────
    // Double-claim only returns newly vested amount
    // ────────────────────────────────────────────────────────────────────────

    function test_doubleClaim_returnsOnlyNewlyVested() public {
        uint256 VEST_DURATION = vesting.VEST_DURATION();

        // Claim at 25% vest
        vm.warp(CLIFF + VEST_DURATION / 4);
        vm.prank(beneficiary1);
        vesting.claim();
        uint256 firstClaim = psre.balanceOf(beneficiary1);

        // Advance to 75% vest
        vm.warp(CLIFF + (VEST_DURATION * 3) / 4);
        vm.prank(beneficiary1);
        vesting.claim();
        uint256 secondClaim = psre.balanceOf(beneficiary1) - firstClaim;

        // Second claim = 75% - 25% = 50% of alloc
        uint256 expectedSecond = alloc1 / 2;
        assertApproxEqAbs(secondClaim, expectedSecond, 2, "second claim should be ~50% (75%-25%)");
    }

    function test_claim_revertsIfNothingNewlyVested() public {
        uint256 VEST_DURATION = vesting.VEST_DURATION();

        // Claim once
        vm.warp(CLIFF + VEST_DURATION / 2);
        vm.prank(beneficiary1);
        vesting.claim();

        // Immediately try to claim again (no time passed, nothing new vested)
        vm.prank(beneficiary1);
        vm.expectRevert("TeamVesting: nothing to claim");
        vesting.claim();
    }

    function test_doubleClaim_atVestEnd_fullThenZero() public {
        vm.warp(VEST_END);
        vm.prank(beneficiary1);
        vesting.claim();
        assertEq(psre.balanceOf(beneficiary1), alloc1);

        // Second claim at vest end: everything already claimed
        vm.prank(beneficiary1);
        vm.expectRevert("TeamVesting: nothing to claim");
        vesting.claim();
    }

    // ────────────────────────────────────────────────────────────────────────
    // Multiple beneficiaries act independently
    // ────────────────────────────────────────────────────────────────────────

    function test_twoBeneficiaries_independent() public {
        uint256 VEST_DURATION = vesting.VEST_DURATION();

        // b1 claims at 50%
        vm.warp(CLIFF + VEST_DURATION / 2);
        vm.prank(beneficiary1);
        vesting.claim();

        // b2 claims nothing yet
        assertEq(psre.balanceOf(beneficiary2), 0, "b2 hasn't claimed");

        // b2 claims at vest end
        vm.warp(VEST_END);
        vm.prank(beneficiary2);
        vesting.claim();
        assertEq(psre.balanceOf(beneficiary2), alloc2, "b2 should receive full allocation");
    }

    // ────────────────────────────────────────────────────────────────────────
    // Constructor validation
    // ────────────────────────────────────────────────────────────────────────

    function test_constructor_revertsIfAllocsDontSum() public {
        address[] memory bens = new address[](1);
        bens[0] = beneficiary1;
        uint256[] memory allocs = new uint256[](1);
        allocs[0] = 1000e18; // not 4.2M

        vm.expectRevert("TeamVesting: allocations must sum to 4.2M PSRE");
        new TeamVesting(address(psre), genesis, bens, allocs);
    }

    function test_constructor_revertsOnLengthMismatch() public {
        address[] memory bens = new address[](2);
        bens[0] = beneficiary1;
        bens[1] = beneficiary2;
        uint256[] memory allocs = new uint256[](1);
        allocs[0] = TOTAL_TEAM_ALLOC;

        vm.expectRevert("TeamVesting: length mismatch");
        new TeamVesting(address(psre), genesis, bens, allocs);
    }

    function test_cliffAndVestEndTimestamps() public view {
        assertEq(vesting.cliffEnd(), genesis + 365 days,          "cliffEnd = genesis + 1yr");
        assertEq(vesting.vestEnd(),  genesis + 365 days + 4 * 365 days, "vestEnd = genesis + 5yr");
    }
}
