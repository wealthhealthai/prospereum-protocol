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
 * @title PartnerVaultTest v3.2
 * @notice Tests for PartnerVault cumS tracking, ecosystem balance,
 *         CustomerVault integration, and v3.2 mechanics.
 */
contract PartnerVaultTest is Test {
    PartnerVault   public vault;
    PSRE           public psre;
    MockERC20      public usdc;
    MockSwapRouter public router;

    address public admin        = makeAddr("admin");
    address public treasury     = makeAddr("treasury");
    address public teamVesting  = makeAddr("teamVesting");
    address public partner      = makeAddr("partner");
    address public partnerNew   = makeAddr("partnerNew");
    address public rewardEngine = makeAddr("rewardEngine");
    MockVaultFactory public factoryStub;
    address public factory;
    address public other        = makeAddr("other");

    uint256 public constant PSRE_OUT     = 1000e18;
    uint256 public constant INITIAL_PSRE = 500e18;
    uint256 public genesis;

    function setUp() public {
        genesis = block.timestamp;

        psre   = new PSRE(admin, treasury, teamVesting, genesis);
        usdc   = new MockERC20("USD Coin", "USDC", 6);
        router = new MockSwapRouter(address(psre), PSRE_OUT);
        deal(address(psre), address(router), 100_000e18);

        factoryStub = new MockVaultFactory();
        factory = address(factoryStub);

        vault = new PartnerVault();
        vm.prank(factory);
        vault.initialize(partner, address(psre), address(router), address(usdc), rewardEngine, factory);

        // Simulate factoryInit: give vault the initial PSRE, then call factoryInit
        deal(address(psre), address(vault), INITIAL_PSRE);
        vm.prank(factory);
        vault.factoryInit(INITIAL_PSRE);

        usdc.mint(partner, 100_000e6);
        vm.prank(partner);
        usdc.approve(address(vault), type(uint256).max);
    }

    // ── Helper: deploy a fresh CustomerVault ─────────────────────────────────
    function _deployCV() internal returns (CustomerVault cv) {
        cv = new CustomerVault();
        // address(0) = platform-managed vault (no specific intended customer required here)
        cv.initialize(address(vault), address(psre), partner, address(0));
        // Simulate factory-deployed CV: tell the mock factory this CV belongs to `vault`.
        // Required for PartnerVault.registerCustomerVault() factory-origin check (MAJOR-1).
        factoryStub.setIsCustomerVaultOf(address(cv), address(vault));
    }

    // ── Helper: buy PSRE + register a fresh CV ───────────────────────────────
    function _buyAndRegisterCV() internal returns (CustomerVault cv) {
        vm.prank(partner);
        vault.buy(100e6, 1, block.timestamp + 1 hours, 3000);
        cv = _deployCV();
        vm.prank(partner);
        vault.registerCustomerVault(address(cv));
    }

    // ────────────────────────────────────────────────────────────────────────
    // initialize()
    // ────────────────────────────────────────────────────────────────────────

    function test_initialize_onlyOnce() public {
        vm.expectRevert("PartnerVault: already initialized");
        vm.prank(factory);
        vault.initialize(other, address(psre), address(router), address(usdc), rewardEngine, factory);
    }

    function test_initialize_setsOwner() public view {
        assertEq(vault.owner(), partner);
    }

    function test_initialize_setsAddresses() public view {
        assertEq(vault.psre(),         address(psre));
        assertEq(vault.router(),       address(router));
        assertEq(vault.inputToken(),   address(usdc));
        assertEq(vault.rewardEngine(), rewardEngine);
        assertEq(vault.factory(),      factory);
    }

    // ────────────────────────────────────────────────────────────────────────
    // factoryInit()
    // ────────────────────────────────────────────────────────────────────────

    function test_factoryInit_setsInitialCumS() public view {
        assertEq(vault.initialCumS(), INITIAL_PSRE);
    }

    function test_factoryInit_setsCumS() public view {
        assertEq(vault.cumS(), INITIAL_PSRE);
    }

    function test_factoryInit_setsEcosystemBalance() public view {
        assertEq(vault.ecosystemBalance(), INITIAL_PSRE);
    }

    function test_factoryInit_setsLastEpochCumS() public view {
        assertEq(vault.lastEpochCumS(), INITIAL_PSRE);
    }

    function test_factoryInit_qualifiedFalse() public view {
        assertFalse(vault.qualified());
    }

    function test_factoryInit_onlyOnce() public {
        vm.prank(factory);
        vm.expectRevert("PartnerVault: already init'd with buy");
        vault.factoryInit(100e18);
    }

    function test_factoryInit_onlyFactory() public {
        PartnerVault fresh = new PartnerVault();
        vm.prank(factory);
        fresh.initialize(partner, address(psre), address(router), address(usdc), rewardEngine, factory);
        deal(address(psre), address(fresh), 100e18);

        vm.prank(partner);
        vm.expectRevert("PartnerVault: only factory");
        fresh.factoryInit(100e18);
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

    function test_buy_increasesEcosystemBalance() public {
        uint256 ecoBefore = vault.ecosystemBalance();
        vm.prank(partner);
        vault.buy(100e6, 1, block.timestamp + 1 hours, 3000);
        assertEq(vault.ecosystemBalance(), ecoBefore + PSRE_OUT);
    }

    function test_buy_increasesCumS() public {
        uint256 cumSBefore = vault.cumS();
        vm.prank(partner);
        vault.buy(100e6, 1, block.timestamp + 1 hours, 3000);
        assertEq(vault.cumS(), cumSBefore + PSRE_OUT);
    }

    function test_buy_cumSMonotonicallyIncreases() public {
        uint256 prev = vault.cumS();
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(partner);
            vault.buy(100e6, 1, block.timestamp + 1 hours, 3000);
            uint256 curr = vault.cumS();
            assertGt(curr, prev, "cumS must strictly increase");
            prev = curr;
        }
        assertEq(vault.cumS(), INITIAL_PSRE + PSRE_OUT * 5);
    }

    function test_buy_psreBalanceIncreasesOnVault() public {
        uint256 before = psre.balanceOf(address(vault));
        vm.prank(partner);
        vault.buy(100e6, 1, block.timestamp + 1 hours, 3000);
        assertEq(psre.balanceOf(address(vault)), before + PSRE_OUT);
    }

    // ────────────────────────────────────────────────────────────────────────
    // distributeToCustomer()
    // ────────────────────────────────────────────────────────────────────────

    function test_distributeToCustomer_transfersPSRE() public {
        CustomerVault cv = _buyAndRegisterCV();
        uint256 dist = 100e18;

        vm.prank(partner);
        vault.distributeToCustomer(address(cv), dist);

        assertEq(psre.balanceOf(address(cv)), dist);
    }

    function test_distributeToCustomer_doesNotChangeEcosystemBalance() public {
        CustomerVault cv = _buyAndRegisterCV();
        uint256 ecoBefore = vault.ecosystemBalance();

        vm.prank(partner);
        vault.distributeToCustomer(address(cv), 100e18);

        assertEq(vault.ecosystemBalance(), ecoBefore,
            "distributeToCustomer must NOT change ecosystemBalance");
    }

    function test_distributeToCustomer_doesNotChangeCumS() public {
        CustomerVault cv = _buyAndRegisterCV();
        uint256 cumSBefore = vault.cumS();

        vm.prank(partner);
        vault.distributeToCustomer(address(cv), 100e18);

        assertEq(vault.cumS(), cumSBefore);
    }

    function test_distributeToCustomer_onlyOwner() public {
        CustomerVault cv = _buyAndRegisterCV();
        vm.prank(other);
        vm.expectRevert("PartnerVault: not owner");
        vault.distributeToCustomer(address(cv), 1e18);
    }

    function test_distributeToCustomer_revertsForUnregisteredCV() public {
        vm.prank(partner);
        vault.buy(100e6, 1, block.timestamp + 1 hours, 3000);

        CustomerVault unregistered = _deployCV();
        vm.prank(partner);
        vm.expectRevert("PartnerVault: CV not registered");
        vault.distributeToCustomer(address(unregistered), 100e18);
    }

    // ────────────────────────────────────────────────────────────────────────
    // transferOut()
    // ────────────────────────────────────────────────────────────────────────

    function test_transferOut_decreasesEcosystemBalance() public {
        vm.prank(partner);
        vault.buy(100e6, 1, block.timestamp + 1 hours, 3000);

        uint256 ecoBefore = vault.ecosystemBalance();
        uint256 amt = 100e18;

        vm.prank(partner);
        vault.transferOut(other, amt);

        assertEq(vault.ecosystemBalance(), ecoBefore - amt);
    }

    function test_transferOut_doesNotDecreaseCumS() public {
        vm.prank(partner);
        vault.buy(100e6, 1, block.timestamp + 1 hours, 3000);

        uint256 cumSPeak = vault.cumS();

        uint256 bal = psre.balanceOf(address(vault));
        vm.prank(partner);
        vault.transferOut(other, bal);

        assertEq(vault.cumS(), cumSPeak, "cumS ratchet must NOT decrease after transferOut");
    }

    function test_transferOut_revertsForRegisteredCV() public {
        CustomerVault cv = _buyAndRegisterCV();

        vm.prank(partner);
        vm.expectRevert("PartnerVault: use distributeToCustomer for CVs");
        vault.transferOut(address(cv), 1e18);
    }

    // ────────────────────────────────────────────────────────────────────────
    // reportLeakage()
    // ────────────────────────────────────────────────────────────────────────

    function test_reportLeakage_decreasesEcosystemBalance() public {
        CustomerVault cv = _buyAndRegisterCV();
        vm.prank(partner);
        vault.distributeToCustomer(address(cv), 200e18);

        uint256 ecoBefore = vault.ecosystemBalance();

        vm.prank(address(cv));
        vault.reportLeakage(50e18);

        assertEq(vault.ecosystemBalance(), ecoBefore - 50e18);
    }

    function test_reportLeakage_doesNotDecreaseCumS() public {
        CustomerVault cv = _buyAndRegisterCV();
        vm.prank(partner);
        vault.distributeToCustomer(address(cv), 200e18);

        uint256 cumSBefore = vault.cumS();

        vm.prank(address(cv));
        vault.reportLeakage(50e18);

        assertEq(vault.cumS(), cumSBefore, "cumS must not decrease on leakage");
    }

    function test_reportLeakage_onlyRegisteredCV() public {
        vm.prank(other);
        vm.expectRevert("PartnerVault: caller not registered CV");
        vault.reportLeakage(1e18);
    }

    // ────────────────────────────────────────────────────────────────────────
    // registerCustomerVault()
    // ────────────────────────────────────────────────────────────────────────

    function test_registerCustomerVault_registers() public {
        CustomerVault cv = _deployCV();
        vm.prank(partner);
        vault.registerCustomerVault(address(cv));

        assertTrue(vault.registeredCustomerVaults(address(cv)));
        assertEq(vault.getCustomerVaultCount(), 1);
    }

    function test_registerCustomerVault_onlyOwner() public {
        CustomerVault cv = _deployCV();
        vm.prank(other);
        vm.expectRevert("PartnerVault: not owner");
        vault.registerCustomerVault(address(cv));
    }

    function test_registerCustomerVault_noDoubleRegister() public {
        CustomerVault cv = _deployCV();
        vm.prank(partner);
        vault.registerCustomerVault(address(cv));

        vm.prank(partner);
        vm.expectRevert("PartnerVault: CV already registered");
        vault.registerCustomerVault(address(cv));
    }

    function test_registerCustomerVault_maxCapRevert() public {
        // Register exactly MAX_CUSTOMER_VAULTS (1000) CustomerVaults
        for (uint256 i = 1; i <= 1000; i++) {
            address cv = address(uint160(0xC0FFEE0000 + i));
            // Simulate factory-deployed CV for this vault
            factoryStub.setIsCustomerVaultOf(cv, address(vault));
            vm.prank(partner);
            vault.registerCustomerVault(cv);
        }
        assertEq(vault.getCustomerVaultCount(), 1000);

        // The 1001st registration must revert
        address cvExtra = address(uint160(0xC0FFEE0000 + 1001));
        factoryStub.setIsCustomerVaultOf(cvExtra, address(vault));
        vm.prank(partner);
        vm.expectRevert("PartnerVault: max CVs reached");
        vault.registerCustomerVault(cvExtra);
    }

    // ────────────────────────────────────────────────────────────────────────
    // snapshotEpoch()
    // ────────────────────────────────────────────────────────────────────────

    function test_snapshotEpoch_onlyRewardEngine() public {
        vm.prank(other);
        vm.expectRevert("PartnerVault: only rewardEngine");
        vault.snapshotEpoch();
    }

    function test_snapshotEpoch_returnsZeroWhenNoGrowthSinceFactoryInit() public {
        // lastEpochCumS = INITIAL_PSRE, cumS = INITIAL_PSRE → delta = 0
        vm.prank(rewardEngine);
        uint256 delta = vault.snapshotEpoch();
        assertEq(delta, 0);
    }

    function test_snapshotEpoch_returnsDeltaAfterBuy() public {
        vm.prank(partner);
        vault.buy(100e6, 1, block.timestamp + 1 hours, 3000);

        vm.prank(rewardEngine);
        uint256 delta = vault.snapshotEpoch();
        assertEq(delta, PSRE_OUT, "delta should equal cumS growth since last snapshot");
    }

    function test_snapshotEpoch_updatesLastEpochCumS() public {
        vm.prank(partner);
        vault.buy(100e6, 1, block.timestamp + 1 hours, 3000);
        uint256 cumSAfterBuy = vault.cumS();

        vm.prank(rewardEngine);
        vault.snapshotEpoch();

        assertEq(vault.lastEpochCumS(), cumSAfterBuy);
    }

    function test_snapshotEpoch_zeroDeltaAfterSecondSnapshot() public {
        vm.prank(partner);
        vault.buy(100e6, 1, block.timestamp + 1 hours, 3000);

        vm.prank(rewardEngine);
        vault.snapshotEpoch();

        vm.prank(rewardEngine);
        uint256 delta2 = vault.snapshotEpoch();
        assertEq(delta2, 0, "second snapshot without new growth, delta = 0");
    }

    // ────────────────────────────────────────────────────────────────────────
    // _updateCumS: direct ERC-20 transfer to vault captured
    // ────────────────────────────────────────────────────────────────────────

    function test_directTransferToVault_capturedBySnapshotEpoch() public {
        uint256 directAmt = 300e18;
        deal(address(psre), partner, directAmt);
        vm.prank(partner);
        // Direct ERC-20 transfer to vault address (customer paying partner)
        IERC20(address(psre)).transfer(address(vault), directAmt);

        uint256 cumSBefore = vault.cumS(); // = INITIAL_PSRE

        vm.prank(rewardEngine);
        uint256 delta = vault.snapshotEpoch();

        // _updateCumS scans balanceOf(vault) and captures the direct transfer
        assertGt(vault.cumS(), cumSBefore, "cumS should capture direct ERC-20 transfer");
        assertEq(delta, directAmt, "delta should equal the direct transfer amount");
    }

    // ────────────────────────────────────────────────────────────────────────
    // _updateCumS: customer vault balance captured
    // ────────────────────────────────────────────────────────────────────────

    function test_customerVaultBalance_capturedByCumS() public {
        CustomerVault cv = _deployCV();
        vm.prank(partner);
        vault.registerCustomerVault(address(cv));

        // Buy PSRE then distribute to CV
        vm.prank(partner);
        vault.buy(100e6, 1, block.timestamp + 1 hours, 3000);
        vm.prank(partner);
        vault.distributeToCustomer(address(cv), 200e18);

        // Snapshot should see full ecosystem including CV balance
        // ecosystemBalance = INITIAL_PSRE + PSRE_OUT (distributeToCustomer doesn't change it)
        // cumS = INITIAL_PSRE + PSRE_OUT (updated on buy)
        // lastEpochCumS = INITIAL_PSRE
        // delta = PSRE_OUT
        vm.prank(rewardEngine);
        uint256 delta = vault.snapshotEpoch();
        assertEq(delta, PSRE_OUT, "delta should reflect buy growth");
    }

    function test_directTransferToCV_capturedByCumS() public {
        CustomerVault cv = _deployCV();
        vm.prank(partner);
        vault.registerCustomerVault(address(cv));

        // Someone directly transfers PSRE to CV address
        uint256 cvDirectAmt = 400e18;
        deal(address(psre), other, cvDirectAmt);
        vm.prank(other);
        IERC20(address(psre)).transfer(address(cv), cvDirectAmt);

        uint256 cumSBefore = vault.cumS(); // = INITIAL_PSRE

        // snapshotEpoch → _updateCumS scans CV balance too
        vm.prank(rewardEngine);
        uint256 delta = vault.snapshotEpoch();

        assertGt(vault.cumS(), cumSBefore, "cumS should capture direct transfer to CV");
        assertEq(delta, cvDirectAmt, "delta should equal CV direct transfer amount");
    }

    // ────────────────────────────────────────────────────────────────────────
    // cumS ratchet invariant
    // ────────────────────────────────────────────────────────────────────────

    function test_ratchet_cumSNeverDecreasesOnTransferOut() public {
        vm.prank(partner);
        vault.buy(100e6, 1, block.timestamp + 1 hours, 3000);
        uint256 cumSPeak = vault.cumS();

        uint256 bal = psre.balanceOf(address(vault));
        vm.prank(partner);
        vault.transferOut(other, bal);

        assertEq(vault.cumS(), cumSPeak, "cumS ratchet must hold after transferOut");
    }

    function test_ratchet_rebuyRequiredForNewDelta() public {
        vm.prank(partner);
        vault.buy(100e6, 1, block.timestamp + 1 hours, 3000);

        // Snapshot sets lastEpochCumS = cumS
        vm.prank(rewardEngine);
        vault.snapshotEpoch();

        // Transfer out some PSRE (cumS stays at peak)
        vm.prank(partner);
        vault.transferOut(other, PSRE_OUT / 2);

        // Next snapshot: no growth above peak → delta = 0
        vm.prank(rewardEngine);
        uint256 delta = vault.snapshotEpoch();
        assertEq(delta, 0, "after transferOut without rebuy, delta = 0");

        // Rebuy past the peak to earn again
        vm.prank(partner);
        vault.buy(100e6, 1, block.timestamp + 1 hours, 3000);

        vm.prank(rewardEngine);
        uint256 deltaAfterRebuy = vault.snapshotEpoch();
        assertGt(deltaAfterRebuy, 0, "after rebuy past peak, delta > 0");
    }

    // ────────────────────────────────────────────────────────────────────────
    // View helpers
    // ────────────────────────────────────────────────────────────────────────

    function test_getCumS() public view {
        assertEq(vault.getCumS(), INITIAL_PSRE);
    }

    function test_getInitialCumS() public view {
        assertEq(vault.getInitialCumS(), INITIAL_PSRE);
    }

    function test_isQualified_falseByDefault() public view {
        assertFalse(vault.isQualified());
    }

    // ────────────────────────────────────────────────────────────────────────
    // Ownership (two-step)
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
        assertEq(vault.owner(), partnerNew);
        assertEq(vault.pendingOwner(), address(0));
    }

    function test_acceptOwnership_onlyPendingOwner() public {
        vm.prank(partner);
        vault.updateOwner(partnerNew);
        vm.prank(other);
        vm.expectRevert("PartnerVault: not pending owner");
        vault.acceptOwnership();
    }

    function test_ownershipTransfer_newOwnerCanBuy() public {
        vm.prank(partner);
        vault.updateOwner(partnerNew);
        vm.prank(partnerNew);
        vault.acceptOwnership();

        usdc.mint(partnerNew, 100e6);
        vm.prank(partnerNew);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(partnerNew);
        vault.buy(100e6, 1, block.timestamp + 1 hours, 3000);

        assertEq(vault.cumS(), INITIAL_PSRE + PSRE_OUT);
    }
}
