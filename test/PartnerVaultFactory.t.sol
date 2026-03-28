// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/core/PartnerVaultFactory.sol";
import "../contracts/core/PartnerVault.sol";
import "../contracts/core/CustomerVault.sol";
import "../contracts/core/PSRE.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockSwapRouter.sol";
import "./mocks/MockRewardEngine.sol";

/**
 * @title PartnerVaultFactoryTest v3.2
 * @notice Tests for PartnerVaultFactory: S_MIN enforcement, createVault,
 *         deployCustomerVault, and registry functions.
 */
contract PartnerVaultFactoryTest is Test {
    PartnerVaultFactory public factory;
    PartnerVault        public vaultImpl;
    CustomerVault       public cvImpl;
    MockRewardEngine    public reEngine;
    PSRE                public psre;
    MockERC20           public usdc;
    MockSwapRouter      public router;

    address public admin   = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public teamVesting = makeAddr("teamVesting");
    address public partner = makeAddr("partner");
    address public partner2 = makeAddr("partner2");
    address public other   = makeAddr("other");

    uint256 public constant PSRE_PER_SWAP = 1000e18;  // mock router fixed output
    uint256 public constant BELOW_S_MIN   = 499_000_000; // 499 USDC (< S_MIN)
    uint256 public constant ABOVE_S_MIN   = 500_000_000; // exactly S_MIN = 500 USDC
    uint256 public genesis;

    function setUp() public {
        genesis = block.timestamp;

        psre = new PSRE(admin, treasury, teamVesting, genesis);
        usdc = new MockERC20("USD Coin", "USDC", 6);

        // Mock router returns PSRE_PER_SWAP PSRE to recipient
        router = new MockSwapRouter(address(psre), PSRE_PER_SWAP);
        deal(address(psre), address(router), 10_000_000e18);

        // Deploy implementations
        vaultImpl = new PartnerVault();
        cvImpl    = new CustomerVault();

        // Deploy mock RewardEngine
        reEngine = new MockRewardEngine();

        // Deploy factory
        factory = new PartnerVaultFactory(
            address(vaultImpl),
            address(cvImpl),
            address(psre),
            address(router),
            address(usdc),
            admin
        );

        // Wire up rewardEngine
        vm.prank(admin);
        factory.setRewardEngine(address(reEngine));

        // Fund partners with USDC and approve factory
        usdc.mint(partner,  10_000e6);
        usdc.mint(partner2, 10_000e6);
        vm.prank(partner);
        usdc.approve(address(factory), type(uint256).max);
        vm.prank(partner2);
        usdc.approve(address(factory), type(uint256).max);
    }

    // ────────────────────────────────────────────────────────────────────────
    // S_MIN constant
    // ────────────────────────────────────────────────────────────────────────

    function test_sMin_isCorrect() public view {
        assertEq(factory.S_MIN(), 500_000_000, "S_MIN should be 500e6 (500 USDC)");
    }

    // ────────────────────────────────────────────────────────────────────────
    // createVault()
    // ────────────────────────────────────────────────────────────────────────

    function test_createVault_revertsIfBelowSMin() public {
        vm.prank(partner);
        vm.expectRevert("Factory: below S_MIN ($500 USDC)");
        factory.createVault(BELOW_S_MIN, 1, block.timestamp + 1 hours, 3000);
    }

    function test_createVault_revertsIfExactlyBelowSMin() public {
        vm.prank(partner);
        vm.expectRevert("Factory: below S_MIN ($500 USDC)");
        factory.createVault(ABOVE_S_MIN - 1, 1, block.timestamp + 1 hours, 3000);
    }

    function test_createVault_succeedsAtExactlySMin() public {
        vm.prank(partner);
        address vault = factory.createVault(ABOVE_S_MIN, 1, block.timestamp + 1 hours, 3000);
        assertTrue(vault != address(0), "vault should be deployed");
    }

    function test_createVault_revertsIfRewardEngineNotSet() public {
        // Deploy a fresh factory without setting rewardEngine
        PartnerVaultFactory fresh = new PartnerVaultFactory(
            address(vaultImpl), address(cvImpl),
            address(psre), address(router), address(usdc), admin
        );
        usdc.mint(other, 10_000e6);
        vm.prank(other);
        usdc.approve(address(fresh), type(uint256).max);

        vm.prank(other);
        vm.expectRevert("Factory: rewardEngine not set");
        fresh.createVault(ABOVE_S_MIN, 1, block.timestamp + 1 hours, 3000);
    }

    function test_createVault_revertsIfVaultAlreadyExists() public {
        vm.prank(partner);
        factory.createVault(ABOVE_S_MIN, 1, block.timestamp + 1 hours, 3000);

        vm.prank(partner);
        vm.expectRevert("Factory: vault already exists");
        factory.createVault(ABOVE_S_MIN, 1, block.timestamp + 1 hours, 3000);
    }

    function test_createVault_revertsIfExpiredDeadline() public {
        vm.prank(partner);
        vm.expectRevert("Factory: expired deadline");
        factory.createVault(ABOVE_S_MIN, 1, block.timestamp - 1, 3000);
    }

    function test_createVault_registersVaultInMappings() public {
        vm.prank(partner);
        address vault = factory.createVault(ABOVE_S_MIN, 1, block.timestamp + 1 hours, 3000);

        assertEq(factory.vaultOf(partner), vault);
        assertEq(factory.partnerOf(vault), partner);
        assertEq(factory.allVaults(0), vault);
        assertEq(factory.vaultCount(), 1);
    }

    function test_createVault_executesInitialBuy() public {
        vm.prank(partner);
        address vault = factory.createVault(ABOVE_S_MIN, 1, block.timestamp + 1 hours, 3000);

        // Vault should hold PSRE from initial buy
        assertEq(psre.balanceOf(vault), PSRE_PER_SWAP, "vault should hold psreOut from initial buy");
    }

    function test_createVault_setsInitialCumSInVault() public {
        vm.prank(partner);
        address vault = factory.createVault(ABOVE_S_MIN, 1, block.timestamp + 1 hours, 3000);

        PartnerVault pv = PartnerVault(vault);
        assertEq(pv.initialCumS(), PSRE_PER_SWAP, "initialCumS should equal psreOut");
        assertEq(pv.cumS(),         PSRE_PER_SWAP, "cumS should equal initialCumS");
        assertEq(pv.ecosystemBalance(), PSRE_PER_SWAP);
        assertFalse(pv.qualified(),  "vault should not be qualified yet");
    }

    function test_createVault_registersInRewardEngine() public {
        vm.prank(partner);
        address vault = factory.createVault(ABOVE_S_MIN, 1, block.timestamp + 1 hours, 3000);

        assertEq(reEngine.registeredInitialCumS(vault), PSRE_PER_SWAP,
            "RE should record initialCumS");
        assertEq(reEngine.getRegisteredVaultCount(), 1);
    }

    function test_createVault_pullsUSDCFromPartner() public {
        uint256 usdcBefore = usdc.balanceOf(partner);

        vm.prank(partner);
        factory.createVault(ABOVE_S_MIN, 1, block.timestamp + 1 hours, 3000);

        assertEq(usdc.balanceOf(partner), usdcBefore - ABOVE_S_MIN,
            "factory should pull USDC from partner");
    }

    function test_createVault_multiplePartners() public {
        vm.prank(partner);
        address vault1 = factory.createVault(ABOVE_S_MIN, 1, block.timestamp + 1 hours, 3000);

        vm.prank(partner2);
        address vault2 = factory.createVault(ABOVE_S_MIN, 1, block.timestamp + 1 hours, 3000);

        assertNotEq(vault1, vault2, "different partners get different vaults");
        assertEq(factory.vaultCount(), 2);
        assertEq(factory.vaultOf(partner), vault1);
        assertEq(factory.vaultOf(partner2), vault2);
    }

    function test_createVault_revertsAtMaxPartners() public {
        vm.prank(admin);
        factory.setMaxPartners(1);

        vm.prank(partner);
        factory.createVault(ABOVE_S_MIN, 1, block.timestamp + 1 hours, 3000);

        vm.prank(partner2);
        vm.expectRevert("Factory: max partners reached");
        factory.createVault(ABOVE_S_MIN, 1, block.timestamp + 1 hours, 3000);
    }

    // ────────────────────────────────────────────────────────────────────────
    // isRegisteredVault()
    // ────────────────────────────────────────────────────────────────────────

    function test_isRegisteredVault_trueForCreatedVault() public {
        vm.prank(partner);
        address vault = factory.createVault(ABOVE_S_MIN, 1, block.timestamp + 1 hours, 3000);
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
        address vault = factory.createVault(ABOVE_S_MIN, 1, block.timestamp + 1 hours, 3000);

        vm.prank(partner);
        address cv = factory.deployCustomerVault(vault, makeAddr("customer"));

        assertTrue(cv != address(0), "CV should be deployed");
        assertTrue(PartnerVault(vault).registeredCustomerVaults(cv), "CV should be registered in vault");
    }

    function test_deployCustomerVault_setsCorrectParent() public {
        vm.prank(partner);
        address vault = factory.createVault(ABOVE_S_MIN, 1, block.timestamp + 1 hours, 3000);

        vm.prank(partner);
        address cv = factory.deployCustomerVault(vault, makeAddr("customer"));

        assertEq(CustomerVault(cv).parentVault(), vault,
            "CV parentVault should be the partner vault");
        assertEq(CustomerVault(cv).partnerOwner(), partner);
        assertEq(CustomerVault(cv).psre(), address(psre));
    }

    function test_deployCustomerVault_recordsInFactory() public {
        vm.prank(partner);
        address vault = factory.createVault(ABOVE_S_MIN, 1, block.timestamp + 1 hours, 3000);

        vm.prank(partner);
        address cv = factory.deployCustomerVault(vault, makeAddr("customer"));

        assertEq(factory.customerVaultParent(cv), vault);
        assertEq(factory.customerVaultCount(), 1);
    }

    function test_deployCustomerVault_revertsIfNotVaultOwner() public {
        vm.prank(partner);
        address vault = factory.createVault(ABOVE_S_MIN, 1, block.timestamp + 1 hours, 3000);

        vm.prank(other);
        vm.expectRevert("Factory: not vault owner");
        factory.deployCustomerVault(vault, makeAddr("customer"));
    }

    function test_deployCustomerVault_multiplePerVault() public {
        vm.prank(partner);
        address vault = factory.createVault(ABOVE_S_MIN, 1, block.timestamp + 1 hours, 3000);

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
        address vault = factory.createVault(ABOVE_S_MIN, 1, block.timestamp + 1 hours, 3000);

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

    // ────────────────────────────────────────────────────────────────────────
    // getAllVaults()
    // ────────────────────────────────────────────────────────────────────────

    function test_getAllVaults_returnsAllVaults() public {
        vm.prank(partner);
        address vault1 = factory.createVault(ABOVE_S_MIN, 1, block.timestamp + 1 hours, 3000);
        vm.prank(partner2);
        address vault2 = factory.createVault(ABOVE_S_MIN, 1, block.timestamp + 1 hours, 3000);

        address[] memory vaults = factory.getAllVaults();
        assertEq(vaults.length, 2);
        assertEq(vaults[0], vault1);
        assertEq(vaults[1], vault2);
    }
}
