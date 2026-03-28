// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/core/PartnerVault.sol";
import "../contracts/core/CustomerVault.sol";
import "../contracts/core/PSRE.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockSwapRouter.sol";
import "./mocks/MockVaultFactory.sol";

/**
 * @title CustomerVaultTest v3.2
 * @notice Tests for CustomerVault: initialization, claimVault, withdraw, reclaimUnclaimed.
 */
contract CustomerVaultTest is Test {
    PartnerVault   public vault;
    CustomerVault  public cv;
    PSRE           public psre;
    MockERC20      public usdc;
    MockSwapRouter public router;

    address public admin        = makeAddr("admin");
    address public treasury     = makeAddr("treasury");
    address public teamVesting  = makeAddr("teamVesting");
    address public partner      = makeAddr("partner");
    address public customer     = makeAddr("customer");
    address public rewardEngine = makeAddr("rewardEngine");
    MockVaultFactory public factoryMock;
    address public factory;   // = address(factoryMock), set in setUp
    address public other        = makeAddr("other");

    uint256 public constant INITIAL_PSRE = 1000e18;
    uint256 public constant CV_DEPOSIT   = 200e18;
    uint256 public genesis;

    function setUp() public {
        genesis = block.timestamp;

        psre   = new PSRE(admin, treasury, teamVesting, genesis);
        usdc   = new MockERC20("USD Coin", "USDC", 6);
        router = new MockSwapRouter(address(psre), 1000e18);
        deal(address(psre), address(router), 100_000e18);

        // Use MockVaultFactory so isCustomerVaultOf() can be called (MAJOR-1)
        factoryMock = new MockVaultFactory();
        factory     = address(factoryMock);

        // Deploy and init PartnerVault
        vault = new PartnerVault();
        vm.prank(factory);
        vault.initialize(partner, address(psre), address(router), address(usdc), rewardEngine, factory);

        // Simulate initial buy via factoryInit
        deal(address(psre), address(vault), INITIAL_PSRE);
        vm.prank(factory);
        vault.factoryInit(INITIAL_PSRE);

        // Deploy CustomerVault and register it
        cv = new CustomerVault();
        cv.initialize(address(vault), address(psre), partner, customer);
        // Simulate factory-deployed CV: tell the mock factory this CV belongs to vault (MAJOR-1).
        factoryMock.setIsCustomerVaultOf(address(cv), address(vault));
        vm.prank(partner);
        vault.registerCustomerVault(address(cv));

        // Distribute some PSRE to the CV
        vm.prank(partner);
        vault.distributeToCustomer(address(cv), CV_DEPOSIT);
    }

    // ────────────────────────────────────────────────────────────────────────
    // initialize()
    // ────────────────────────────────────────────────────────────────────────

    function test_initialize_setsState() public view {
        assertEq(cv.parentVault(),      address(vault));
        assertEq(cv.psre(),             address(psre));
        assertEq(cv.partnerOwner(),     partner);
        assertEq(cv.intendedCustomer(), customer);     // FIX 1: stored on-chain
        assertEq(cv.customer(),         address(0));
        assertFalse(cv.customerClaimed());
    }

    function test_initialize_onlyOnce() public {
        vm.expectRevert("CustomerVault: already initialized");
        cv.initialize(address(vault), address(psre), partner, customer);
    }

    // ────────────────────────────────────────────────────────────────────────
    // claimVault()
    // ────────────────────────────────────────────────────────────────────────

    function test_claimVault_setsCustomer() public {
        vm.prank(customer);
        cv.claimVault(customer);

        assertEq(cv.customer(), customer);
        assertTrue(cv.customerClaimed());
    }

    function test_claimVault_requiresCallerIsIntendedCustomerOrPartner() public {
        // FIX 1: caller must be intendedCustomer or partnerOwner to prevent front-running
        vm.prank(other);
        vm.expectRevert("CustomerVault: unauthorized");
        cv.claimVault(customer);
    }

    function test_claimVault_cannotClaimTwice() public {
        vm.prank(customer);
        cv.claimVault(customer);

        vm.prank(customer);
        vm.expectRevert("CustomerVault: already claimed");
        cv.claimVault(customer);
    }

    function test_claimVault_cannotClaimWithZeroAddress() public {
        vm.prank(address(0));
        vm.expectRevert("CustomerVault: zero wallet");
        cv.claimVault(address(0));
    }

    // ────────────────────────────────────────────────────────────────────────
    // withdraw()
    // ────────────────────────────────────────────────────────────────────────

    function test_withdraw_transfersPSREToCustomer() public {
        vm.prank(customer);
        cv.claimVault(customer);

        uint256 withdrawAmt = 50e18;
        uint256 customerBalBefore = psre.balanceOf(customer);

        vm.prank(customer);
        cv.withdraw(withdrawAmt);

        assertEq(psre.balanceOf(customer), customerBalBefore + withdrawAmt);
        assertEq(psre.balanceOf(address(cv)), CV_DEPOSIT - withdrawAmt);
    }

    function test_withdraw_callsReportLeakageOnParent() public {
        vm.prank(customer);
        cv.claimVault(customer);

        uint256 ecoBefore = vault.ecosystemBalance();
        uint256 withdrawAmt = 50e18;

        vm.prank(customer);
        cv.withdraw(withdrawAmt);

        // reportLeakage should have reduced ecosystemBalance
        assertEq(vault.ecosystemBalance(), ecoBefore - withdrawAmt,
            "withdraw should reduce parent ecosystemBalance via reportLeakage");
    }

    function test_withdraw_doesNotDecreaseCumS() public {
        vm.prank(customer);
        cv.claimVault(customer);

        uint256 cumSBefore = vault.cumS();
        vm.prank(customer);
        cv.withdraw(50e18);

        assertEq(vault.cumS(), cumSBefore, "withdraw must not decrease cumS ratchet");
    }

    function test_withdraw_revertsForUnclaimedCustomer() public {
        // CV not yet claimed by customer
        vm.prank(customer);
        vm.expectRevert("CustomerVault: only customer");
        cv.withdraw(50e18);
    }

    function test_withdraw_revertsForNonCustomer() public {
        vm.prank(customer);
        cv.claimVault(customer);

        vm.prank(other);
        vm.expectRevert("CustomerVault: only customer");
        cv.withdraw(50e18);
    }

    function test_withdraw_revertsForZeroAmount() public {
        vm.prank(customer);
        cv.claimVault(customer);

        vm.prank(customer);
        vm.expectRevert("CustomerVault: zero amount");
        cv.withdraw(0);
    }

    function test_withdraw_revertsForInsufficientBalance() public {
        vm.prank(customer);
        cv.claimVault(customer);

        vm.prank(customer);
        vm.expectRevert("CustomerVault: insufficient balance");
        cv.withdraw(CV_DEPOSIT + 1);
    }

    function test_withdraw_fullAmount() public {
        vm.prank(customer);
        cv.claimVault(customer);

        vm.prank(customer);
        cv.withdraw(CV_DEPOSIT);

        assertEq(psre.balanceOf(address(cv)), 0);
        assertEq(psre.balanceOf(customer), CV_DEPOSIT);
    }

    // ────────────────────────────────────────────────────────────────────────
    // reclaimUnclaimed()
    // ────────────────────────────────────────────────────────────────────────

    function test_reclaimUnclaimed_returnsToParent() public {
        uint256 parentBalBefore = psre.balanceOf(address(vault));

        vm.prank(address(vault));
        cv.reclaimUnclaimed(CV_DEPOSIT);

        assertEq(psre.balanceOf(address(vault)), parentBalBefore + CV_DEPOSIT,
            "PSRE should return to parentVault");
        assertEq(psre.balanceOf(address(cv)), 0);
    }

    function test_reclaimUnclaimed_doesNotChangeEcosystemBalance() public {
        // PSRE returns to parent vault — ecosystemBalance unchanged (PSRE stays in ecosystem)
        uint256 ecoBefore = vault.ecosystemBalance();

        vm.prank(address(vault));
        cv.reclaimUnclaimed(CV_DEPOSIT);

        // ecosystemBalance should be unchanged (PSRE moved back to parent, still in ecosystem)
        // Note: after reclaim, the parent vault's balanceOf increases, but ecosystemBalance
        // is a running counter. The reclaim doesn't call reportLeakage — PSRE stayed inside.
        // However, ecosystemBalance won't auto-update until _updateCumS is called.
        // The test checks that reclaimUnclaimed does NOT call reportLeakage.
        assertEq(vault.ecosystemBalance(), ecoBefore,
            "reclaimUnclaimed must NOT reduce ecosystemBalance");
    }

    function test_reclaimUnclaimed_onlyParent() public {
        vm.prank(partner);
        vm.expectRevert("CustomerVault: only parentVault");
        cv.reclaimUnclaimed(CV_DEPOSIT);
    }

    function test_reclaimUnclaimed_revertsIfCustomerClaimed() public {
        vm.prank(customer);
        cv.claimVault(customer);

        vm.prank(address(vault));
        vm.expectRevert("CustomerVault: customer has claimed; cannot reclaim");
        cv.reclaimUnclaimed(CV_DEPOSIT);
    }

    // ────────────────────────────────────────────────────────────────────────
    // balanceOf captured by parent's _updateCumS
    // ────────────────────────────────────────────────────────────────────────

    function test_cvBalanceCapturedByParentSnapshot() public {
        // CV holds CV_DEPOSIT PSRE — already distributed in setUp
        // The parent vault's ecosystemBalance should already reflect this
        // (distributeToCustomer doesn't change ecosystemBalance)
        // But cumS should include CV balance when snapshotEpoch is called

        // Do a buy to grow cumS above lastEpochCumS=INITIAL_PSRE
        usdc.mint(partner, 100e6);
        vm.prank(partner);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(partner);
        vault.buy(100e6, 1, block.timestamp + 1 hours, 3000);

        // Snapshot
        vm.prank(rewardEngine);
        uint256 delta = vault.snapshotEpoch();

        // delta = cumS growth = 1000e18 (from buy)
        // CV balance doesn't add to delta since distributeToCustomer doesn't change ecosystemBalance
        assertEq(delta, 1000e18);
    }

    function test_directTransferToCV_capturedByParentSnapshot() public {
        // Direct ERC-20 transfer to CV (customer paying partner directly)
        uint256 directAmt = 500e18;
        deal(address(psre), other, directAmt);
        vm.prank(other);
        IERC20(address(psre)).transfer(address(cv), directAmt);

        uint256 cumSBefore = vault.cumS();

        // Parent snapshot should scan CV balance via _updateCumS
        vm.prank(rewardEngine);
        uint256 delta = vault.snapshotEpoch();

        assertGt(vault.cumS(), cumSBefore,
            "cumS should grow after direct ERC-20 transfer to CV");
        assertEq(delta, directAmt,
            "delta should equal direct transfer to CV");
    }

    // ────────────────────────────────────────────────────────────────────────
    // psreBalance()
    // ────────────────────────────────────────────────────────────────────────

    function test_psreBalance_returnsActualBalance() public view {
        assertEq(cv.psreBalance(), CV_DEPOSIT);
    }
}
