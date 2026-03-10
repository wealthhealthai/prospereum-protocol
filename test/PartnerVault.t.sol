// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/core/PartnerVault.sol";
import "../contracts/core/PSRE.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockSwapRouter.sol";

contract PartnerVaultTest is Test {
    PartnerVault    public vault;
    PSRE            public psre;
    MockERC20       public usdc;
    MockSwapRouter  public router;

    address public admin        = makeAddr("admin");
    address public treasury     = makeAddr("treasury");
    address public teamVesting  = makeAddr("teamVesting");
    address public partner      = makeAddr("partner");
    address public partnerNew   = makeAddr("partnerNew");
    address public rewardEngine = makeAddr("rewardEngine");
    address public other        = makeAddr("other");

    uint256 public constant PSRE_OUT = 1000e18;
    uint256 public genesis;

    function setUp() public {
        genesis = block.timestamp;

        // Deploy PSRE
        psre = new PSRE(admin, treasury, teamVesting, genesis);

        // Deploy mock USDC
        usdc = new MockERC20("USD Coin", "USDC", 6);

        // Deploy mock router — it will send PSRE_OUT PSRE on each swap
        router = new MockSwapRouter(address(psre), PSRE_OUT);

        // Fund router with PSRE so it can deliver tokens
        // (router sends from its own balance)
        deal(address(psre), address(router), 100_000e18);

        // Deploy a raw PartnerVault implementation (not via factory — direct initialize)
        vault = new PartnerVault();
        vault.initialize(partner, address(psre), address(router), address(usdc), rewardEngine);

        // Give partner USDC to spend
        usdc.mint(partner, 100_000e6);

        // Approve vault to pull USDC from partner
        vm.prank(partner);
        usdc.approve(address(vault), type(uint256).max);
    }

    // ────────────────────────────────────────────────────────────────────────
    // initialize()
    // ────────────────────────────────────────────────────────────────────────

    function test_initialize_onlyOnce() public {
        vm.expectRevert("PartnerVault: already initialized");
        vault.initialize(other, address(psre), address(router), address(usdc), rewardEngine);
    }

    function test_initialize_setsOwner() public view {
        assertEq(vault.owner(), partner);
    }

    function test_initialize_setsAddresses() public view {
        assertEq(vault.psre(),         address(psre));
        assertEq(vault.router(),       address(router));
        assertEq(vault.inputToken(),   address(usdc));
        assertEq(vault.rewardEngine(), rewardEngine);
    }

    // ────────────────────────────────────────────────────────────────────────
    // buy()
    // ────────────────────────────────────────────────────────────────────────

    function test_buy_onlyOwner() public {
        vm.prank(other);
        vm.expectRevert("PartnerVault: not owner");
        vault.buy(100e6, 1, block.timestamp + 1 hours, 3000);
    }

    function test_buy_revertsIfMinAmountOutZero() public {
        vm.prank(partner);
        vm.expectRevert("PartnerVault: slippage protection required");
        vault.buy(100e6, 0, block.timestamp + 1 hours, 3000);
    }

    function test_buy_revertsIfAmountInZero() public {
        vm.prank(partner);
        vm.expectRevert("PartnerVault: zero amountIn");
        vault.buy(0, 1, block.timestamp + 1 hours, 3000);
    }

    function test_buy_revertsIfExpiredDeadline() public {
        vm.prank(partner);
        vm.expectRevert("PartnerVault: expired deadline");
        vault.buy(100e6, 1, block.timestamp - 1, 3000);
    }

    function test_buy_increasesCumBuy() public {
        vm.prank(partner);
        vault.buy(100e6, 1, block.timestamp + 1 hours, 3000);
        assertEq(vault.cumBuy(), PSRE_OUT, "cumBuy should equal psreOut");
    }

    function test_buy_cumBuyMonotonicallyIncreases() public {
        uint256 prev = 0;
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(partner);
            vault.buy(100e6, 1, block.timestamp + 1 hours, 3000);
            uint256 curr = vault.cumBuy();
            assertGt(curr, prev, "cumBuy must be strictly increasing");
            prev = curr;
        }
        assertEq(vault.cumBuy(), PSRE_OUT * 5, "cumBuy should accumulate all buys");
    }

    function test_buy_psreBalanceIncreasesOnVault() public {
        uint256 before = psre.balanceOf(address(vault));
        vm.prank(partner);
        vault.buy(100e6, 1, block.timestamp + 1 hours, 3000);
        assertEq(psre.balanceOf(address(vault)), before + PSRE_OUT);
    }

    // ────────────────────────────────────────────────────────────────────────
    // distribute()
    // ────────────────────────────────────────────────────────────────────────

    function test_distribute_transfersPSRE() public {
        // First buy to get PSRE into vault
        vm.prank(partner);
        vault.buy(100e6, 1, block.timestamp + 1 hours, 3000);

        uint256 vaultBal = psre.balanceOf(address(vault));
        uint256 recipientBefore = psre.balanceOf(other);

        vm.prank(partner);
        vault.distribute(other, vaultBal);

        assertEq(psre.balanceOf(other), recipientBefore + vaultBal, "recipient should receive PSRE");
        assertEq(psre.balanceOf(address(vault)), 0, "vault should be emptied");
    }

    function test_distribute_doesNotChangeCumBuy() public {
        vm.prank(partner);
        vault.buy(100e6, 1, block.timestamp + 1 hours, 3000);

        uint256 cumBuyBefore = vault.cumBuy();

        vm.prank(partner);
        vault.distribute(other, PSRE_OUT / 2);

        assertEq(vault.cumBuy(), cumBuyBefore, "distribute must not change cumBuy");
    }

    function test_distribute_onlyOwner() public {
        // Buy some PSRE first
        vm.prank(partner);
        vault.buy(100e6, 1, block.timestamp + 1 hours, 3000);

        vm.prank(other);
        vm.expectRevert("PartnerVault: not owner");
        vault.distribute(other, 1e18);
    }

    // ────────────────────────────────────────────────────────────────────────
    // Ownership transfer (two-step)
    // ────────────────────────────────────────────────────────────────────────

    function test_updateOwner_setsPendingOwner() public {
        vm.prank(partner);
        vault.updateOwner(partnerNew);
        assertEq(vault.pendingOwner(), partnerNew);
    }

    function test_updateOwner_onlyCurrentOwner() public {
        vm.prank(other);
        vm.expectRevert("PartnerVault: not owner");
        vault.updateOwner(other);
    }

    function test_acceptOwnership_setsNewOwner() public {
        vm.prank(partner);
        vault.updateOwner(partnerNew);

        vm.prank(partnerNew);
        vault.acceptOwnership();

        assertEq(vault.owner(), partnerNew, "owner should be updated");
        assertEq(vault.pendingOwner(), address(0), "pendingOwner should be cleared");
    }

    function test_acceptOwnership_onlyPendingOwner() public {
        vm.prank(partner);
        vault.updateOwner(partnerNew);

        vm.prank(other);
        vm.expectRevert("PartnerVault: not pending owner");
        vault.acceptOwnership();
    }

    function test_oldOwnerCannotActAfterTransfer() public {
        // Transfer ownership
        vm.prank(partner);
        vault.updateOwner(partnerNew);
        vm.prank(partnerNew);
        vault.acceptOwnership();

        // Old owner tries to use vault
        usdc.mint(partner, 100e6);
        vm.prank(partner);
        usdc.approve(address(vault), type(uint256).max);

        vm.prank(partner);
        vm.expectRevert("PartnerVault: not owner");
        vault.buy(100e6, 1, block.timestamp + 1 hours, 3000);
    }

    function test_newOwnerCanBuyAfterTransfer() public {
        vm.prank(partner);
        vault.updateOwner(partnerNew);
        vm.prank(partnerNew);
        vault.acceptOwnership();

        // New owner needs USDC and approval
        usdc.mint(partnerNew, 100e6);
        vm.prank(partnerNew);
        usdc.approve(address(vault), type(uint256).max);

        vm.prank(partnerNew);
        vault.buy(100e6, 1, block.timestamp + 1 hours, 3000);
        assertEq(vault.cumBuy(), PSRE_OUT);
    }

    // ────────────────────────────────────────────────────────────────────────
    // psreBalance()
    // ────────────────────────────────────────────────────────────────────────

    function test_psreBalance_reflectsActualBalance() public {
        vm.prank(partner);
        vault.buy(100e6, 1, block.timestamp + 1 hours, 3000);
        assertEq(vault.psreBalance(), PSRE_OUT);
    }
}
