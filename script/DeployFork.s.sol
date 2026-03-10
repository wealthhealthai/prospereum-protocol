// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/core/PSRE.sol";
import "../contracts/core/PartnerVault.sol";
import "../contracts/core/PartnerVaultFactory.sol";
import "../contracts/periphery/StakingVault.sol";
import "../contracts/periphery/RewardEngine.sol";
import "../contracts/periphery/TeamVesting.sol";
import "../test/mocks/MockERC20.sol";
import "../test/mocks/MockSwapRouter.sol";

/**
 * @title DeployFork
 * @notice Local fork smoke test for the Prospereum protocol.
 *         Deploys all 6 contracts against a local anvil node (no real ETH/transactions).
 *         Uses MockERC20 for USDC and MockSwapRouter for the Uniswap router.
 *
 * USAGE:
 *   anvil --block-time 1 &
 *   forge script script/DeployFork.s.sol:DeployFork \
 *     --rpc-url http://127.0.0.1:8545 \
 *     --broadcast \
 *     -vvvv
 */
contract DeployFork is Script {

    // Anvil default pre-funded account
    uint256 constant DEPLOYER_PK      = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    address constant DEPLOYER_ADDRESS = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    uint256 constant PSRE_PER_BUY = 1_000e18;
    uint256 constant EPOCH        = 7 days;

    function run() external {
        address deployer = DEPLOYER_ADDRESS;
        uint256 genesis  = block.timestamp;

        console.log("=== PROSPEREUM LOCAL FORK DEPLOY ===");
        console.log("Deployer:  ", deployer);
        console.log("Genesis:   ", genesis);

        vm.startBroadcast(DEPLOYER_PK);

        // ── 1. Deploy Mocks ──────────────────────────────────────────────────
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        console.log("MockUSDC:          ", address(usdc));

        // ── 2. Deploy TeamVesting placeholder ───────────────────────────────
        //    We pre-deploy a TeamVesting-shaped address recipient by using deployer
        //    temporarily, then deploying TeamVesting with the real PSRE address later.
        //    Pattern from Deploy.s.sol: deploy PSRE with deployer as teamVesting
        //    placeholder, then deploy TeamVesting, then transfer tokens.

        // ── 3. Deploy PSRE ───────────────────────────────────────────────────
        //    admin = deployer, treasury = deployer, teamVesting placeholder = deployer
        PSRE psre = new PSRE(
            deployer,   // admin (DEFAULT_ADMIN_ROLE + PAUSER_ROLE)
            deployer,   // treasury receives 4.2M at genesis
            deployer,   // placeholder for teamVesting — deployer receives team tokens
            genesis
        );
        console.log("PSRE:              ", address(psre));
        console.log("PSRE totalSupply:  ", psre.totalSupply());

        // ── 4. Deploy TeamVesting ─────────────────────────────────────────
        address[] memory bens   = new address[](1);
        uint256[] memory allocs = new uint256[](1);
        bens[0]   = deployer;
        allocs[0] = 4_200_000e18;

        TeamVesting teamVesting = new TeamVesting(
            address(psre),
            genesis,
            bens,
            allocs
        );
        console.log("TeamVesting:       ", address(teamVesting));

        // Transfer team allocation from deployer to TeamVesting
        psre.transfer(address(teamVesting), 4_200_000e18);
        console.log("Team tokens transferred to TeamVesting");

        // ── 5. Deploy MockSwapRouter ─────────────────────────────────────────
        //    The router needs PSRE to return on swaps. We fund it after deploy.
        MockSwapRouter router = new MockSwapRouter(address(psre), PSRE_PER_BUY);
        console.log("MockSwapRouter:    ", address(router));

        // Fund router with PSRE so it can return tokens on exactInputSingle.
        // Deployer holds 4.2M from treasury mint. Transfer 500k to router.
        psre.transfer(address(router), 500_000e18);
        console.log("Router funded with 500,000 PSRE");

        // ── 6. Deploy PartnerVault implementation ────────────────────────────
        PartnerVault vaultImpl = new PartnerVault();
        console.log("PartnerVault impl: ", address(vaultImpl));

        // ── 7. Deploy PartnerVaultFactory ────────────────────────────────────
        PartnerVaultFactory factory = new PartnerVaultFactory(
            address(vaultImpl),
            address(psre),
            address(router),
            address(usdc),
            deployer   // admin = deployer for local fork
        );
        console.log("Factory:           ", address(factory));

        // ── 8. Deploy StakingVault ───────────────────────────────────────────
        //    LP token = USDC mock as placeholder (matches Integration test pattern)
        StakingVault stakingVault = new StakingVault(
            address(psre),
            address(usdc),   // LP token placeholder
            genesis,
            deployer         // admin = deployer
        );
        console.log("StakingVault:      ", address(stakingVault));

        // ── 9. Deploy RewardEngine ───────────────────────────────────────────
        RewardEngine rewardEngine = new RewardEngine(
            address(psre),
            address(factory),
            address(stakingVault),
            genesis,
            deployer   // admin = deployer
        );
        console.log("RewardEngine:      ", address(rewardEngine));

        // ── 10. Wire up ──────────────────────────────────────────────────────
        factory.setRewardEngine(address(rewardEngine));
        console.log("Factory.rewardEngine set");

        stakingVault.setRewardEngine(address(rewardEngine));
        console.log("StakingVault.rewardEngine set");

        psre.grantRole(psre.MINTER_ROLE(), address(rewardEngine));
        console.log("PSRE: MINTER_ROLE granted to RewardEngine");

        // ── 11. Print deployment summary ─────────────────────────────────────
        console.log("\n=== DEPLOYED ADDRESSES ===");
        console.log("PSRE:          ", address(psre));
        console.log("TeamVesting:   ", address(teamVesting));
        console.log("VaultImpl:     ", address(vaultImpl));
        console.log("Factory:       ", address(factory));
        console.log("StakingVault:  ", address(stakingVault));
        console.log("RewardEngine:  ", address(rewardEngine));
        console.log("==========================");

        // ════════════════════════════════════════════════════════════════════
        // SMOKE TESTS
        // ════════════════════════════════════════════════════════════════════

        console.log("\n=== SMOKE TESTS ===");

        // ── (a) Verify PSRE totalSupply == 8,400,000e18 ──────────────────────
        uint256 supply = psre.totalSupply();
        require(supply == 8_400_000e18, "SMOKE FAIL: PSRE totalSupply != 8.4M");
        console.log("[PASS] PSRE totalSupply == 8.4M:", supply);

        // ── (b) Create a PartnerVault via factory (partner = deployer) ────────
        address vault = factory.createVault();
        require(vault != address(0),                      "SMOKE FAIL: vault is zero");
        require(factory.vaultOf(deployer) == vault,       "SMOKE FAIL: vaultOf mismatch");
        console.log("[PASS] PartnerVault created:", vault);

        // ── (c) Call buy() on the vault ───────────────────────────────────────
        //    Mint USDC to deployer and approve vault
        usdc.mint(deployer, 1_000_000e6);
        usdc.approve(vault, type(uint256).max);

        PartnerVault(vault).buy(100e6, 1, block.timestamp + 1 hours, 3000);
        console.log("[PASS] buy() executed");

        // ── (d) Verify vault.cumBuy() == 1000e18 ─────────────────────────────
        uint256 cumBuy = PartnerVault(vault).cumBuy();
        require(cumBuy == PSRE_PER_BUY, "SMOKE FAIL: cumBuy != 1000e18");
        console.log("[PASS] vault.cumBuy() == 1000 PSRE:", cumBuy);

        // ── (e) Stake 500e18 PSRE in StakingVault ────────────────────────────
        psre.approve(address(stakingVault), type(uint256).max);
        stakingVault.stakePSRE(500e18);
        console.log("[PASS] Staked 500 PSRE in StakingVault");

        // ── (f) Warp 7 days + 1 second ───────────────────────────────────────
        //    NOTE: vm.warp is only available in Test context, not Script context.
        //    In a broadcast script we cannot warp time. Instead, we call
        //    recordStakeTime and finalizeEpoch at the natural block timestamp.
        //    To test epoch finalization we need to either:
        //    (1) Use vm.warp in a non-broadcast context, or
        //    (2) Actually wait 7 days (not practical)
        //    Solution: run smoke tests in a non-broadcast section after stopBroadcast,
        //    using vm.warp in the off-chain simulation path.
        //
        //    We stop broadcast here to run time-warped simulation checks.
        vm.stopBroadcast();

        // ── (f) Warp 7 days + 1 second (simulation — no broadcast) ───────────
        vm.warp(genesis + EPOCH + 1);
        console.log("[PASS] Time warped to epoch 1 boundary");

        // Checkpoint staker accumulator before recording stakeTime
        // Unstake 1 wei to trigger _checkpointUser
        vm.startPrank(deployer);
        stakingVault.unstakePSRE(1);
        // Record stakeTime for epoch 0
        stakingVault.recordStakeTime(0);
        vm.stopPrank();
        console.log("[PASS] StakeTime recorded for epoch 0");

        // ── (g) Call rewardEngine.finalizeEpoch(0) ────────────────────────────
        rewardEngine.finalizeEpoch(0);
        console.log("[PASS] Epoch 0 finalized");

        // ── (h) Verify epoch 0 is finalized ──────────────────────────────────
        require(rewardEngine.epochFinalized(0), "SMOKE FAIL: epoch 0 not finalized");
        console.log("[PASS] Epoch 0 is marked finalized");

        // ── (i) Call claimPartner(0, vault) and verify vault received PSRE ────
        uint256 owed = rewardEngine.owedPartner(vault);
        require(owed > 0, "SMOKE FAIL: owedPartner == 0 (no partner reward computed)");
        console.log("[INFO] owedPartner:", owed);

        uint256 vaultBalBefore = psre.balanceOf(vault);
        rewardEngine.claimPartner(0, vault);
        uint256 vaultBalAfter = psre.balanceOf(vault);
        require(vaultBalAfter - vaultBalBefore == owed, "SMOKE FAIL: vault PSRE balance mismatch after claim");
        console.log("[PASS] Partner reward claimed, vault received PSRE:", vaultBalAfter - vaultBalBefore);

        // ── (j) All assertions passed ─────────────────────────────────────────
        console.log("\n===========================================");
        console.log("           SMOKE TEST PASSED");
        console.log("===========================================");

        console.log("\n=== FINAL DEPLOYMENT SUMMARY ===");
        console.log("PSRE:          ", address(psre));
        console.log("TeamVesting:   ", address(teamVesting));
        console.log("VaultImpl:     ", address(vaultImpl));
        console.log("Factory:       ", address(factory));
        console.log("StakingVault:  ", address(stakingVault));
        console.log("RewardEngine:  ", address(rewardEngine));
        console.log("================================");
    }
}
