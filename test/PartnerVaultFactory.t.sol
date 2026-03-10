// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/core/PartnerVaultFactory.sol";
import "../contracts/core/PartnerVault.sol";
import "../contracts/core/PSRE.sol";
import "./mocks/MockERC20.sol";

contract PartnerVaultFactoryTest is Test {
    PartnerVaultFactory public factory;
    PartnerVault        public vaultImpl;
    PSRE                public psre;
    MockERC20           public usdc;

    address public admin        = makeAddr("admin");
    address public treasury     = makeAddr("treasury");
    address public teamVesting  = makeAddr("teamVesting");
    address public rewardEngine = makeAddr("rewardEngine");
    address public router       = makeAddr("router");
    address public partner1     = makeAddr("partner1");
    address public partner2     = makeAddr("partner2");
    address public partner3     = makeAddr("partner3");

    uint256 public genesis;

    function setUp() public {
        genesis = block.timestamp;

        // Deploy PSRE
        psre = new PSRE(admin, treasury, teamVesting, genesis);

        // Deploy mock USDC
        usdc = new MockERC20("USD Coin", "USDC", 6);

        // Deploy PartnerVault implementation
        vaultImpl = new PartnerVault();

        // Deploy factory
        factory = new PartnerVaultFactory(
            address(vaultImpl),
            address(psre),
            router,
            address(usdc),
            admin
        );
    }

    // ────────────────────────────────────────────────────────────────────────
    // createVault() — basic functionality
    // ────────────────────────────────────────────────────────────────────────

    function test_createVault_revertsIfRewardEngineNotSet() public {
        vm.prank(partner1);
        vm.expectRevert("Factory: rewardEngine not set");
        factory.createVault();
    }

    function test_setRewardEngine_onlyOnce() public {
        vm.prank(admin);
        factory.setRewardEngine(rewardEngine);
        assertEq(factory.rewardEngine(), rewardEngine);

        // Second call should revert
        vm.prank(admin);
        vm.expectRevert("Factory: already set");
        factory.setRewardEngine(rewardEngine);
    }

    function test_createVault_deploysClone() public {
        vm.prank(admin);
        factory.setRewardEngine(rewardEngine);

        vm.prank(partner1);
        address vault = factory.createVault();

        // Vault should be a valid contract (not zero)
        assertTrue(vault != address(0), "vault address should be non-zero");
        assertTrue(vault.code.length > 0, "vault should have code (clone)");
    }

    function test_createVault_initializesVaultCorrectly() public {
        vm.prank(admin);
        factory.setRewardEngine(rewardEngine);

        vm.prank(partner1);
        address vaultAddr = factory.createVault();

        PartnerVault v = PartnerVault(vaultAddr);
        assertEq(v.owner(),        partner1,            "owner should be partner1");
        assertEq(v.psre(),         address(psre),       "psre mismatch");
        assertEq(v.router(),       router,              "router mismatch");
        assertEq(v.inputToken(),   address(usdc),       "inputToken mismatch");
        assertEq(v.rewardEngine(), rewardEngine,        "rewardEngine mismatch");
    }

    function test_createVault_onlyOnePerAddress() public {
        vm.prank(admin);
        factory.setRewardEngine(rewardEngine);

        vm.prank(partner1);
        factory.createVault();

        vm.prank(partner1);
        vm.expectRevert("Factory: vault already exists");
        factory.createVault();
    }

    // ────────────────────────────────────────────────────────────────────────
    // Mappings: vaultOf / partnerOf
    // ────────────────────────────────────────────────────────────────────────

    function test_vaultOf_mapping() public {
        vm.prank(admin);
        factory.setRewardEngine(rewardEngine);

        vm.prank(partner1);
        address vault = factory.createVault();

        assertEq(factory.vaultOf(partner1), vault, "vaultOf[partner1] should map to vault");
    }

    function test_partnerOf_mapping() public {
        vm.prank(admin);
        factory.setRewardEngine(rewardEngine);

        vm.prank(partner1);
        address vault = factory.createVault();

        assertEq(factory.partnerOf(vault), partner1, "partnerOf[vault] should map to partner1");
    }

    function test_bidirectional_mappings_multiplePartners() public {
        vm.prank(admin);
        factory.setRewardEngine(rewardEngine);

        vm.prank(partner1);
        address v1 = factory.createVault();

        vm.prank(partner2);
        address v2 = factory.createVault();

        assertEq(factory.vaultOf(partner1),  v1);
        assertEq(factory.vaultOf(partner2),  v2);
        assertEq(factory.partnerOf(v1), partner1);
        assertEq(factory.partnerOf(v2), partner2);
        assertTrue(v1 != v2, "vaults should be distinct");
    }

    // ────────────────────────────────────────────────────────────────────────
    // getAllVaults()
    // ────────────────────────────────────────────────────────────────────────

    function test_getAllVaults_empty() public {
        vm.prank(admin);
        factory.setRewardEngine(rewardEngine);

        address[] memory vaults = factory.getAllVaults();
        assertEq(vaults.length, 0);
    }

    function test_getAllVaults_returnsAllAfterCreation() public {
        vm.prank(admin);
        factory.setRewardEngine(rewardEngine);

        vm.prank(partner1);
        address v1 = factory.createVault();
        vm.prank(partner2);
        address v2 = factory.createVault();
        vm.prank(partner3);
        address v3 = factory.createVault();

        address[] memory vaults = factory.getAllVaults();
        assertEq(vaults.length, 3);
        assertEq(vaults[0], v1);
        assertEq(vaults[1], v2);
        assertEq(vaults[2], v3);
    }

    function test_vaultCount() public {
        vm.prank(admin);
        factory.setRewardEngine(rewardEngine);

        assertEq(factory.vaultCount(), 0);

        vm.prank(partner1);
        factory.createVault();
        assertEq(factory.vaultCount(), 1);

        vm.prank(partner2);
        factory.createVault();
        assertEq(factory.vaultCount(), 2);
    }

    // ────────────────────────────────────────────────────────────────────────
    // maxPartners cap
    // ────────────────────────────────────────────────────────────────────────

    function test_createVault_revertsWhenMaxPartnersReached() public {
        // Set maxPartners to 2
        vm.prank(admin);
        factory.setMaxPartners(2);

        vm.prank(admin);
        factory.setRewardEngine(rewardEngine);

        vm.prank(partner1);
        factory.createVault();
        vm.prank(partner2);
        factory.createVault();

        // Third should revert
        vm.prank(partner3);
        vm.expectRevert("Factory: max partners reached");
        factory.createVault();
    }

    function test_setMaxPartners_onlyOwner() public {
        vm.prank(partner1);
        vm.expectRevert();
        factory.setMaxPartners(10);
    }

    // ────────────────────────────────────────────────────────────────────────
    // Immutables
    // ────────────────────────────────────────────────────────────────────────

    function test_immutables() public view {
        assertEq(factory.vaultImplementation(), address(vaultImpl));
        assertEq(factory.psre(),                address(psre));
        assertEq(factory.router(),              router);
        assertEq(factory.inputToken(),          address(usdc));
    }
}
