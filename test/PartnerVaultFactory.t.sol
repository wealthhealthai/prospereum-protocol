// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/core/PartnerVaultFactory.sol";
import "../contracts/core/PartnerVault.sol";
import "../contracts/core/CustomerVault.sol";
import "../contracts/core/PSRE.sol";
import "./mocks/MockRewardEngine.sol";

/**
 * @title PartnerVaultFactoryTest v3.3
 * @notice Tests for PartnerVaultFactory (PSRE-native, DEX-agnostic partner entry).
 *         Partners deposit PSRE directly — no router, no USDC, no fee-tier whitelist.
 */
contract PartnerVaultFactoryTest is Test {
    PartnerVaultFactory public factory;
    PartnerVault        public vaultImpl;
    CustomerVault       public cvImpl;
    MockRewardEngine    public reEngine;
    PSRE                public psre;

    address public admin      = makeAddr("admin");
    address public treasury   = makeAddr("treasury");
    address public teamVesting = makeAddr("teamVesting");
    address public partner    = makeAddr("partner");
    address public partner2   = makeAddr("partner2");
    address public other      = makeAddr("other");

    uint256 public constant PSRE_MIN      = 5_000e18;   // factory default psreMin
    uint256 public constant BELOW_MIN     = 4_999e18;   // just under psreMin
    uint256 public genesis;

    function setUp() public {
        genesis = block.timestamp;

        psre = new PSRE(admin, treasury, teamVesting, genesis);

        // Deploy implementations
        vaultImpl = new PartnerVault();
        cvImpl    = new CustomerVault();

        // Deploy mock RewardEngine
        reEngine = new MockRewardEngine();

        // Deploy factory (PSRE-native)
        factory = new PartnerVaultFactory(
            address(vaultImpl),
            address(cvImpl),
            address(psre),
            admin
        );

        // Wire up rewardEngine
        vm.prank(admin);
        factory.setRewardEngine(address(reEngine));

        // Fund partners with PSRE and approve factory
        deal(address(psre), partner,  10_000_000e18);
        deal(address(psre), partner2, 10_000_000e18);
        deal(address(psre), other,    10_000_000e18);
        vm.prank(partner);
        psre.approve(address(factory), type(uint256).max);
        vm.prank(partner2);
        psre.approve(address(factory), type(uint256).max);
        vm.prank(other);
        psre.approve(address(factory), type(uint256).max);
    }

    // ────────────────────────────────────────────────────────────────────────
    // psreMin
    // ────────────────────────────────────────────────────────────────────────

    function test_psreMin_defaultValue() public view {
        assertEq(factory.psreMin(), PSRE_MIN, "default psreMin should be 5000 PSRE");
    }

    function test_setPsreMin_updatesValue() public {
        vm.prank(admin);
        factory.setPsreMin(10_000e18);
        assertEq(factory.psreMin(), 10_000e18);
    }

    function test_setPsreMin_onlyOwner() public {
        vm.prank(other);
        vm.expectRevert();
        factory.setPsreMin(10_000e18);
    }

    function test_setPsreMin_revertsOnZero() public {
        vm.prank(admin);
        vm.expectRevert("Factory: zero psreMin");
        factory.setPsreMin(0);
    }

    // ────────────────────────────────────────────────────────────────────────
    // createVault()
    // ────────────────────────────────────────────────────────────────────────

    function test_createVault_revertsIfBelowPsreMin() public {
        vm.prank(partner);
        vm.expectRevert("Factory: below psreMin");
        factory.createVault(BELOW_MIN);
    }

    function test_createVault_revertsIfZero() public {
        vm.prank(partner);
        vm.expectRevert("Factory: below psreMin");
        factory.createVault(0);
    }

    function test_createVault_succeedsAtExactlyPsreMin() public {
        vm.prank(partner);
        address vault = factory.createVault(PSRE_MIN);
        assertTrue(vault != address(0), "vault should be deployed");
    }

    function test_createVault_revertsIfRewardEngineNotSet() public {
        // Deploy a fresh factory without setting rewardEngine
        PartnerVaultFactory fresh = new PartnerVaultFactory(
            address(vaultImpl),
            address(cvImpl),
            address(psre),
            admin
        );
        vm.prank(other);
        psre.approve(address(fresh), type(uint256).max);

        vm.prank(other);
        vm.expectRevert("Factory: rewardEngine not set");
        fresh.createVault(PSRE_MIN);
    }

    function test_createVault_revertsIfVaultAlreadyExists() public {
        vm.prank(partner);
        factory.createVault(PSRE_MIN);

        vm.prank(partner);
        vm.expectRevert("Factory: vault already exists");
        factory.createVault(PSRE_MIN);
    }

    function test_createVault_registersVaultInMappings() public {
        vm.prank(partner);
        address vault = factory.createVault(PSRE_MIN);

        assertEq(factory.vaultOf(partner), vault);
        assertEq(factory.partnerOf(vault), partner);
        assertEq(factory.allVaults(0), vault);
        assertEq(factory.vaultCount(), 1);
    }

    function test_createVault_transfersPSREToVault() public {
        uint256 partnerBefore = psre.balanceOf(partner);

        vm.prank(partner);
        address vault = factory.createVault(PSRE_MIN);

        assertEq(psre.balanceOf(vault), PSRE_MIN,     "vault should hold deposited PSRE");
        assertEq(psre.balanceOf(partner), partnerBefore - PSRE_MIN, "factory pulls PSRE from partner");
    }

    function test_createVault_setsInitialCumSInVault() public {
        vm.prank(partner);
        address vault = factory.createVault(PSRE_MIN);

        PartnerVault pv = PartnerVault(vault);
        assertEq(pv.initialCumS(), PSRE_MIN,    "initialCumS should equal deposit");
        assertEq(pv.cumS(),         PSRE_MIN,    "cumS starts at initialCumS");
        assertEq(pv.ecosystemBalance(), PSRE_MIN, "ecosystemBalance equals deposit");
        assertFalse(pv.qualified(), "vault should not be qualified yet");
    }

    function test_createVault_registersInRewardEngine() public {
        vm.prank(partner);
        address vault = factory.createVault(PSRE_MIN);

        assertEq(reEngine.registeredInitialCumS(vault), PSRE_MIN,
            "RE should record initialCumS");
        assertEq(reEngine.getRegisteredVaultCount(), 1);
    }

    function test_createVault_multiplePartners() public {
        vm.prank(partner);
        address vault1 = factory.createVault(PSRE_MIN);

        vm.prank(partner2);
        address vault2 = factory.createVault(PSRE_MIN);

        assertNotEq(vault1, vault2, "different partners get different vaults");
        assertEq(factory.vaultCount(), 2);
        assertEq(factory.vaultOf(partner), vault1);
        assertEq(factory.vaultOf(partner2), vault2);
    }

    function test_createVault_revertsAtMaxPartners() public {
        vm.prank(admin);
        factory.setMaxPartners(1);

        vm.prank(partner);
        factory.createVault(PSRE_MIN);

        vm.prank(partner2);
        vm.expectRevert("Factory: max partners reached");
        factory.createVault(PSRE_MIN);
    }

    // ────────────────────────────────────────────────────────────────────────
    // isRegisteredVault()
    // ────────────────────────────────────────────────────────────────────────

    function test_isRegisteredVault_trueForCreatedVault() public {
        vm.prank(partner);
        address vault = factory.createVault(PSRE_MIN);
        assertTrue(factory.isRegisteredVault(vault));
    }

    function test_isRegisteredVault_falseForUnknownAddress() public view {
        assertFalse(factory.isRegisteredVault(other));
    }

    // ────────────────────────────────────────────────────────────────────────
    // deployCustomerVault()
    // ────────────────────────────────────────────────────────────────────────

    function test_deployCustomerVault_deploysAndRegisters() public {
        vm.prank(partner);
        address vault = factory.createVault(PSRE_MIN);

        vm.prank(partner);
        address cv = factory.deployCustomerVault(vault, makeAddr("customer"));

        assertTrue(cv != address(0), "CV should be deployed");
        assertTrue(PartnerVault(vault).registeredCustomerVaults(cv), "CV should be registered in vault");
    }

    function test_deployCustomerVault_setsCorrectParent() public {
        vm.prank(partner);
        address vault = factory.createVault(PSRE_MIN);

        address customerAddr = makeAddr("customer");
        vm.prank(partner);
        address cv = factory.deployCustomerVault(vault, customerAddr);

        assertEq(CustomerVault(cv).parentVault(), vault,
            "CV parentVault should be the partner vault");
        assertEq(CustomerVault(cv).partnerOwner(), partner);
        assertEq(CustomerVault(cv).psre(), address(psre));
        assertEq(CustomerVault(cv).intendedCustomer(), customerAddr,
            "intendedCustomer must be stored at initialization to block front-run attacks");
    }

    function test_deployCustomerVault_recordsInFactory() public {
        vm.prank(partner);
        address vault = factory.createVault(PSRE_MIN);

        vm.prank(partner);
        address cv = factory.deployCustomerVault(vault, makeAddr("customer"));

        assertEq(factory.customerVaultParent(cv), vault);
        assertEq(factory.customerVaultCount(), 1);
    }

    function test_deployCustomerVault_revertsIfNotVaultOwner() public {
        vm.prank(partner);
        address vault = factory.createVault(PSRE_MIN);

        vm.prank(other);
        vm.expectRevert("Factory: not vault owner");
        factory.deployCustomerVault(vault, makeAddr("customer"));
    }

    function test_deployCustomerVault_multiplePerVault() public {
        vm.prank(partner);
        address vault = factory.createVault(PSRE_MIN);

        vm.prank(partner);
        address cv1 = factory.deployCustomerVault(vault, makeAddr("customer1"));
        vm.prank(partner);
        address cv2 = factory.deployCustomerVault(vault, makeAddr("customer2"));

        assertNotEq(cv1, cv2);
        assertEq(factory.customerVaultCount(), 2);
        assertEq(PartnerVault(vault).getCustomerVaultCount(), 2);
    }

    function test_deployCustomerVault_isRegisteredCustomerVault() public {
        vm.prank(partner);
        address vault = factory.createVault(PSRE_MIN);

        vm.prank(partner);
        address cv = factory.deployCustomerVault(vault, makeAddr("customer"));

        assertEq(factory.isRegisteredCustomerVault(cv), vault,
            "isRegisteredCustomerVault should return parent vault");
    }

    // ────────────────────────────────────────────────────────────────────────
    // Admin
    // ────────────────────────────────────────────────────────────────────────

    function test_setRewardEngine_revertsIfAlreadySet() public {
        vm.prank(admin);
        vm.expectRevert("Factory: already set");
        factory.setRewardEngine(address(reEngine));
    }

    function test_setMaxPartners_updatesValue() public {
        vm.prank(admin);
        factory.setMaxPartners(50);
        assertEq(factory.maxPartners(), 50);
    }

    function test_setMaxPartners_onlyOwner() public {
        vm.prank(other);
        vm.expectRevert();
        factory.setMaxPartners(50);
    }

    function test_renounceOwnership_revertsInFactory() public {
        // Fix #3: renounceOwnership is disabled to prevent permanent protocol halt
        vm.prank(admin);
        vm.expectRevert("Factory: renounce disabled -- transfer to new owner instead");
        factory.renounceOwnership();
    }

    // ────────────────────────────────────────────────────────────────────────
    // getAllVaults()
    // ────────────────────────────────────────────────────────────────────────

    function test_getAllVaults_returnsAllVaults() public {
        vm.prank(partner);
        address vault1 = factory.createVault(PSRE_MIN);
        vm.prank(partner2);
        address vault2 = factory.createVault(PSRE_MIN);

        address[] memory vaults = factory.getAllVaults();
        assertEq(vaults.length, 2);
        assertEq(vaults[0], vault1);
        assertEq(vaults[1], vault2);
    }
}
