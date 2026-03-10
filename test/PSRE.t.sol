// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/core/PSRE.sol";

contract PSRETest is Test {
    PSRE    public psre;

    address public admin    = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public minter   = makeAddr("minter");
    address public alice    = makeAddr("alice");

    // TeamVesting is just an address in this context — it receives the team mint
    address public teamVesting = makeAddr("teamVesting");

    uint256 public genesis;

    function setUp() public {
        genesis = block.timestamp;
        psre = new PSRE(admin, treasury, teamVesting, genesis);
        // Grant MINTER_ROLE to test minter
        // Read constant before prank so the staticcall doesn't consume it
        bytes32 minterRole = psre.MINTER_ROLE();
        vm.prank(admin);
        psre.grantRole(minterRole, minter);
    }

    // ────────────────────────────────────────────────────────────────────────
    // Constructor / genesis minting
    // ────────────────────────────────────────────────────────────────────────

    function test_constructor_totalSupply() public view {
        assertEq(psre.totalSupply(), 8_400_000e18, "totalSupply should be 8.4M at genesis");
    }

    function test_constructor_teamAlloc() public view {
        assertEq(psre.balanceOf(teamVesting), 4_200_000e18, "teamVesting should hold 4.2M");
    }

    function test_constructor_treasuryAlloc() public view {
        assertEq(psre.balanceOf(treasury), 4_200_000e18, "treasury should hold 4.2M");
    }

    function test_remainingMintable_initial() public view {
        assertEq(psre.remainingMintable(), 12_600_000e18, "remaining mintable should be 12.6M");
    }

    // ────────────────────────────────────────────────────────────────────────
    // mint() — role guard
    // ────────────────────────────────────────────────────────────────────────

    function test_mint_onlyMinterRole() public {
        // Non-minter reverts
        vm.prank(alice);
        vm.expectRevert();
        psre.mint(alice, 1e18);
    }

    function test_mint_byMinter_succeeds() public {
        vm.prank(minter);
        psre.mint(alice, 1000e18);
        assertEq(psre.balanceOf(alice), 1000e18);
    }

    // ────────────────────────────────────────────────────────────────────────
    // mint() — global supply cap
    // ────────────────────────────────────────────────────────────────────────

    function test_mint_revertsIfExceedsMaxSupply() public {
        // remainingMintable = 12,600,000e18, but MAX_MINT_PER_EPOCH = 25,200e18
        // To hit global cap without epoch cap, we warp through many epochs
        uint256 epochCap = psre.MAX_MINT_PER_EPOCH(); // 25,200e18
        uint256 remaining = psre.remainingMintable();  // 12,600,000e18

        // Mint most of the supply epoch by epoch
        uint256 epochsNeeded = remaining / epochCap;
        for (uint256 i = 0; i < epochsNeeded; i++) {
            vm.warp(genesis + (i + 1) * 7 days + 1);
            vm.prank(minter);
            psre.mint(alice, epochCap);
        }

        // Now try to mint enough to exceed max supply
        vm.warp(genesis + (epochsNeeded + 2) * 7 days + 1);
        uint256 tooMuch = psre.remainingMintable() + 1;
        vm.prank(minter);
        vm.expectRevert("PSRE: exceeds max supply");
        psre.mint(alice, tooMuch);
    }

    // ────────────────────────────────────────────────────────────────────────
    // mint() — epoch rate limiter
    // ────────────────────────────────────────────────────────────────────────

    function test_mint_revertsIfEpochCapExceeded() public {
        uint256 epochCap = psre.MAX_MINT_PER_EPOCH();

        vm.prank(minter);
        psre.mint(alice, epochCap); // fills epoch cap

        vm.prank(minter);
        vm.expectRevert("PSRE: epoch mint cap exceeded");
        psre.mint(alice, 1); // even 1 wei more reverts
    }

    function test_mint_epochCapResetsNextEpoch() public {
        uint256 epochCap = psre.MAX_MINT_PER_EPOCH();

        vm.prank(minter);
        psre.mint(alice, epochCap); // fills epoch 0

        vm.warp(genesis + 7 days + 1); // advance to epoch 1

        vm.prank(minter);
        psre.mint(alice, epochCap); // should succeed in epoch 1
        assertEq(psre.balanceOf(alice), epochCap * 2);
    }

    // ────────────────────────────────────────────────────────────────────────
    // Pause: halts transfers but NOT mint
    // ────────────────────────────────────────────────────────────────────────

    function test_pause_haltsTransfers() public {
        // Give alice some tokens
        vm.prank(minter);
        psre.mint(alice, 1000e18);

        // Pause
        vm.prank(admin);
        psre.pause();

        // Transfer reverts
        vm.prank(alice);
        vm.expectRevert("PSRE: transfers paused");
        psre.transfer(treasury, 100e18);
    }

    function test_pause_doesNotHaltMint() public {
        vm.prank(admin);
        psre.pause();

        // Mint should still work while paused
        vm.prank(minter);
        psre.mint(alice, 1000e18);
        assertEq(psre.balanceOf(alice), 1000e18);
    }

    function test_unpause_restoresTransfers() public {
        vm.prank(minter);
        psre.mint(alice, 1000e18);

        vm.prank(admin);
        psre.pause();

        vm.prank(admin);
        psre.unpause();

        vm.prank(alice);
        psre.transfer(treasury, 500e18);
        assertEq(psre.balanceOf(alice), 500e18);
    }

    // ────────────────────────────────────────────────────────────────────────
    // currentEpochId() — time warp
    // ────────────────────────────────────────────────────────────────────────

    function test_currentEpochId_startsAtZero() public view {
        assertEq(psre.currentEpochId(), 0);
    }

    function test_currentEpochId_incrementsAfterOneWeek() public {
        vm.warp(genesis + 7 days);
        assertEq(psre.currentEpochId(), 1);
    }

    function test_currentEpochId_epoch10() public {
        vm.warp(genesis + 70 days);
        assertEq(psre.currentEpochId(), 10);
    }

    function test_currentEpochId_justBefore7Days_stillEpoch0() public {
        vm.warp(genesis + 7 days - 1);
        assertEq(psre.currentEpochId(), 0);
    }

    // ────────────────────────────────────────────────────────────────────────
    // epochMinted tracking
    // ────────────────────────────────────────────────────────────────────────

    function test_epochMinted_tracksCorrectly() public {
        uint256 amount = 5000e18;
        vm.prank(minter);
        psre.mint(alice, amount);
        assertEq(psre.epochMinted(0), amount);
    }

    function test_remainingEpochMintable_decreasesAfterMint() public {
        uint256 before = psre.remainingEpochMintable();
        vm.prank(minter);
        psre.mint(alice, 1000e18);
        assertEq(psre.remainingEpochMintable(), before - 1000e18);
    }
}
