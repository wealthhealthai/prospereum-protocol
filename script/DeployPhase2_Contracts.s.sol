// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/core/PSRE.sol";
import "../contracts/core/PartnerVault.sol";
import "../contracts/core/PartnerVaultFactory.sol";
import "../contracts/core/CustomerVault.sol";
import "../contracts/periphery/StakingVault.sol";
import "../contracts/periphery/RewardEngine.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployPhase2_Contracts
 * @notice Phase 2 of two-phase mainnet deploy.
 *         Requires PSRE already deployed (Phase 1) and LP pool created by Shu.
 *
 * REQUIRED .env vars (in addition to Phase 1 vars):
 *   PSRE_ADDRESS      — from Phase 1 deploy output
 *   LP_TOKEN_ADDRESS  — Uniswap v3 pool or ERC-20 LP wrapper address
 *
 * USAGE:
 *   source .env
 *   forge script script/DeployPhase2_Contracts.s.sol:DeployPhase2_Contracts \
 *     --rpc-url $BASE_RPC \
 *     --broadcast \
 *     --verify \
 *     -vvvv
 */
contract DeployPhase2_Contracts is Script {

    address constant UNISWAP_V3_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;
    address constant USDC              = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    function run() external {
        uint256 deployerPk   = vm.envUint("DEPLOYER_PK");
        address founderSafe  = vm.envAddress("FOUNDER_SAFE");
        address treasurySafe = vm.envAddress("TREASURY_SAFE");
        address psreAddr     = vm.envAddress("PSRE_ADDRESS");
        address lpToken      = vm.envAddress("LP_TOKEN_ADDRESS");
        address deployer     = vm.addr(deployerPk);

        require(founderSafe  != address(0), "Phase2: FOUNDER_SAFE not set");
        require(treasurySafe != address(0), "Phase2: TREASURY_SAFE not set");
        require(psreAddr     != address(0), "Phase2: PSRE_ADDRESS not set");
        require(lpToken      != address(0), "Phase2: LP_TOKEN_ADDRESS not set");

        // Verify PSRE is deployed at the given address
        require(psreAddr.code.length > 0, "Phase2: PSRE not deployed at PSRE_ADDRESS");

        // Genesis: use PSRE deploy timestamp for consistency
        // We read it from the PSRE contract's genesisTimestamp
        uint256 genesis = PSRE(psreAddr).genesisTimestamp();

        console.log("\n=== PROSPEREUM PHASE 2: CONTRACTS DEPLOY ===");
        console.log("Deployer:         ", deployer);
        console.log("Founder Safe:     ", founderSafe);
        console.log("Treasury Safe:    ", treasurySafe);
        console.log("PSRE:             ", psreAddr);
        console.log("LP Token:         ", lpToken);
        console.log("Genesis:          ", genesis);
        console.log("============================================\n");

        vm.startBroadcast(deployerPk);

        PSRE psre = PSRE(psreAddr);

        // 1. Deploy PartnerVault + CustomerVault implementations
        PartnerVault vaultImpl = new PartnerVault();
        CustomerVault cvImpl   = new CustomerVault();
        console.log("PartnerVault impl:    ", address(vaultImpl));
        console.log("CustomerVault impl:   ", address(cvImpl));

        // 2. Deploy PartnerVaultFactory
        PartnerVaultFactory factory = new PartnerVaultFactory(
            address(vaultImpl),
            address(cvImpl),
            psreAddr,
            UNISWAP_V3_ROUTER,
            USDC,
            founderSafe
        );
        console.log("PartnerVaultFactory:  ", address(factory));

        // 3. Deploy StakingVault
        StakingVault stakingVault = new StakingVault(
            psreAddr,
            lpToken,
            genesis,
            founderSafe
        );
        console.log("StakingVault:         ", address(stakingVault));

        // 4. Deploy RewardEngine via UUPS proxy
        RewardEngine reImpl = new RewardEngine();
        bytes memory reInitData = abi.encodeCall(
            RewardEngine.initialize,
            (psreAddr, address(factory), address(stakingVault), genesis, founderSafe)
        );
        ERC1967Proxy reProxy      = new ERC1967Proxy(address(reImpl), reInitData);
        RewardEngine rewardEngine = RewardEngine(address(reProxy));
        console.log("RewardEngine impl:    ", address(reImpl));
        console.log("RewardEngine proxy:   ", address(reProxy));

        // 5. Wire-up NOTE: factory and stakingVault are owned by Founder Safe.
        // Wiring must be executed as a Safe batch after this deploy.
        // See POST-DEPLOY WIRING section below.

        vm.stopBroadcast();

        console.log("\n=== PROSPEREUM MAINNET DEPLOYMENT COMPLETE ===");
        console.log("Network:              Base mainnet (chainId: 8453)");
        console.log("Genesis timestamp:    ", genesis);
        console.log("---");
        console.log("PSRE:                 ", psreAddr);
        console.log("PartnerVault impl:    ", address(vaultImpl));
        console.log("CustomerVault impl:   ", address(cvImpl));
        console.log("PartnerVaultFactory:  ", address(factory));
        console.log("StakingVault:         ", address(stakingVault));
        console.log("RewardEngine impl:    ", address(reImpl));
        console.log("RewardEngine proxy:   ", address(reProxy));
        console.log("---");
        console.log("Founder Safe (admin): ", founderSafe);
        console.log("Treasury Safe:        ", treasurySafe);
        console.log("==============================================\n");
        console.log("POST-DEPLOY CHECKLIST:");
        console.log("[ ] 1. Founder Safe BATCH TRANSACTION (3 calls):");
        console.log("       a. factory.setRewardEngine(reProxy)");
        console.log("       b. stakingVault.setRewardEngine(reProxy)");
        console.log("       c. psre.grantRole(MINTER_ROLE, reProxy)");
        console.log("[ ] 2. Update deployments.md with all addresses");
        console.log("[ ] 3. Shu: create PSRE/USDC pool + add liquidity ($20K USDC + 200K PSRE)");
        console.log("[ ] 4. Lock LP via Unicrypt (24 months)");
        console.log("[ ] 5. Set up Sablier vesting stream from Founder Safe");
    }
}
