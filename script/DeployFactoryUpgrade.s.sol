// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../contracts/core/PartnerVault.sol";
import "../contracts/core/CustomerVault.sol";
import "../contracts/core/PartnerVaultFactory.sol";
import "../contracts/periphery/RewardEngine.sol";

/**
 * @title DeployFactoryUpgrade
 * @notice Deploys the new PSRE-native PartnerVaultFactory, new vault/CV implementations,
 *         and a new RewardEngine implementation (which adds scheduleSetFactory et al).
 *
 *         This script is DEPLOY-ONLY. No Safe transactions are sent here.
 *         After this script, execute the 3-step Safe workflow:
 *
 *         STEP 1 (Day 0) — Founder Safe:
 *           re.scheduleUpgrade(newReImpl)
 *           → starts 7-day upgrade timelock
 *
 *         STEP 2 (Day 7) — Founder Safe (single batch tx):
 *           re.executeUpgrade()                   → RE proxy now has scheduleSetFactory
 *           re.scheduleSetFactory(newFactory)     → starts 7-day factory timelock
 *
 *         STEP 3 (Day 14) — Founder Safe (single batch tx):
 *           re.pause()
 *           re.executeSetFactory()               → factory swapped
 *           re.clearVaultScores([])              → no-op at launch (0 vaults), call with
 *                                                   old vault list if migrating with active partners
 *           re.unpause()
 *
 *         Total time: 14 days (two sequential 7-day timelocks).
 *
 * @dev Run: forge script script/DeployFactoryUpgrade.s.sol --rpc-url base --broadcast
 *      Requires DEPLOYER_PK in .env
 */
contract DeployFactoryUpgrade is Script {

    // ── Mainnet constants (Base chainId 8453) ─────────────────────────────────
    address constant PSRE          = 0x2fE08f304f1Af799Bc29E3D4E210973291d96702;
    address constant FOUNDER_SAFE  = 0xc59816CAC94A969E50EdFf7CF49ce727aec1489F;
    address constant RE_PROXY      = 0x9Ab37Fc6D01B85491Ed0863B7F832784bE717EF5;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PK");
        address deployer    = vm.addr(deployerKey);

        console.log("=== DeployFactoryUpgrade ===");
        console.log("Deployer:    ", deployer);
        console.log("Chain ID:    ", block.chainid);
        console.log("RE Proxy:    ", RE_PROXY);
        console.log("Founder Safe:", FOUNDER_SAFE);
        console.log("");

        vm.startBroadcast(deployerKey);

        // 1. New vault implementations (PartnerVault interface changed — 4-arg initialize)
        PartnerVault  newVaultImpl = new PartnerVault();
        CustomerVault newCvImpl    = new CustomerVault();
        console.log("New PartnerVault impl: ", address(newVaultImpl));
        console.log("New CustomerVault impl:", address(newCvImpl));

        // 2. New PartnerVaultFactory (PSRE-native, owned by Founder Safe)
        PartnerVaultFactory newFactory = new PartnerVaultFactory(
            address(newVaultImpl),
            address(newCvImpl),
            PSRE,
            FOUNDER_SAFE   // owner = Founder Safe
        );
        console.log("New PartnerVaultFactory:", address(newFactory));
        console.log("  psreMin:              ", newFactory.psreMin());

        // 3. New RewardEngine implementation (adds scheduleSetFactory, clearVaultScores, etc.)
        RewardEngine newReImpl = new RewardEngine();
        console.log("New RewardEngine impl: ", address(newReImpl));

        vm.stopBroadcast();

        console.log("");
        console.log("=== NEXT STEPS ===");
        console.log("Paste these addresses into the Safe batch JSONs.");
        console.log("");
        console.log("STEP 1 (today, Founder Safe):");
        console.log("  re.scheduleUpgrade(", address(newReImpl), ")");
        console.log("");
        console.log("STEP 2 (in 7 days, Founder Safe batch):");
        console.log("  re.executeUpgrade()");
        console.log("  re.scheduleSetFactory(", address(newFactory), ")");
        console.log("");
        console.log("STEP 3 (in 14 days, Founder Safe batch):");
        console.log("  re.pause()");
        console.log("  re.executeSetFactory()");
        console.log("  re.clearVaultScores([])   // expand with old vault addresses if needed");
        console.log("  re.unpause()");
        console.log("");
        console.log("After STEP 3: wire new factory rewardEngine via factory.setRewardEngine(RE_PROXY)");
        console.log("  (Founder Safe owns newFactory — single tx, no timelock needed)");
    }
}
