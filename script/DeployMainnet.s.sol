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
 * @title DeployMainnet
 * @notice Production deployment script for Prospereum on Base mainnet.
 *
 * ┌─────────────────────────────────────────────────────────┐
 * │  JASON + SHU MUST COMPLETE BEFORE RUNNING THIS SCRIPT  │
 * │                                                         │
 * │  1. Create Founder Safe on app.safe.global              │
 * │     -> Set FOUNDER_SAFE in .env                         │
 * │  2. Create Treasury Safe on app.safe.global             │
 * │     -> Set TREASURY_SAFE in .env                        │
 * │  3. Deploy Uniswap v3 PSRE/USDC pool (1% fee)          │
 * │     -> Set LP_TOKEN_ADDRESS in .env                      │
 * │  4. Fund ops wallet with ≥ 0.05 ETH for gas            │
 * │  5. BlockApex final report received and clean           │
 * └─────────────────────────────────────────────────────────┘
 *
 * DECISIONS LOCKED (decisions.md):
 *   - TeamVesting.sol NOT deployed on mainnet — Shu uses Sablier
 *     Founder tokens go to FOUNDER_SAFE at genesis; Shu sets up Sablier stream
 *   - Founder Safe = governance/upgrade admin
 *   - Treasury Safe = PSRE treasury + LP seeding
 *   - Genesis LP: $40K ($20K USDC + 200K PSRE), Uniswap v3 1%, $0.10 launch
 *   - UPGRADE_TIMELOCK = 7 days (RewardEngine UUPS)
 *
 * USAGE (requires Jason approval — DO NOT RUN without explicit go):
 *   forge script script/DeployMainnet.s.sol:DeployMainnet \
 *     --rpc-url $BASE_RPC \
 *     --broadcast \
 *     --verify \
 *     -vvvv
 *
 * REQUIRED ENVIRONMENT VARIABLES:
 *   DEPLOYER_PK       — ops wallet private key (NOT the Gnosis Safe key)
 *   FOUNDER_SAFE      — Founder Gnosis Safe address (governance + upgrades)
 *   TREASURY_SAFE     — Treasury Gnosis Safe address (PSRE treasury + LP)
 *   LP_TOKEN_ADDRESS  — PSRE/USDC Uniswap v3 LP NFT position token address
 *                       (address of the NonfungiblePositionManager or pool)
 *   BASE_RPC          — Base mainnet RPC URL
 *
 * POST-DEPLOY CHECKLIST (manual steps after script):
 *   1. Record all addresses in projects/prospereum/deployments.md
 *   2. Transfer 200K PSRE from Treasury Safe -> Uniswap v3 pool (genesis LP)
 *   3. Lock LP NFT on Unicrypt (app.uncx.network) for 24 months
 *   4. Shu: set up Sablier stream from Founder Safe for vesting schedule
 *   5. Update keeper cron: swap Base Sepolia RPC/key for mainnet
 *   6. Confirm with BlockApex: share final deployed commit hash
 */
contract DeployMainnet is Script {

    // ─────────────────────────────────────────────────────────────────────────
    // Base mainnet addresses (immutable — do not change)
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Uniswap v3 SwapRouter on Base mainnet
    address constant UNISWAP_V3_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;

    /// @dev USDC on Base mainnet (6 decimals)
    address constant USDC              = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    // ─────────────────────────────────────────────────────────────────────────
    // Deploy
    // ─────────────────────────────────────────────────────────────────────────

    function run() external {
        // ── Read environment ─────────────────────────────────────────────────
        uint256 deployerPk   = vm.envUint("DEPLOYER_PK");
        address founderSafe  = vm.envAddress("FOUNDER_SAFE");
        address treasurySafe = vm.envAddress("TREASURY_SAFE");
        address lpToken      = vm.envAddress("LP_TOKEN_ADDRESS");

        address deployer = vm.addr(deployerPk);

        // ── Sanity checks ────────────────────────────────────────────────────
        require(founderSafe  != address(0), "DeployMainnet: FOUNDER_SAFE not set");
        require(treasurySafe != address(0), "DeployMainnet: TREASURY_SAFE not set");
        require(lpToken      != address(0), "DeployMainnet: LP_TOKEN_ADDRESS not set");
        require(founderSafe  != deployer,   "DeployMainnet: founder safe != deployer");
        require(treasurySafe != deployer,   "DeployMainnet: treasury safe != deployer");

        uint256 genesis = block.timestamp; // set at deploy time

        console.log("\n=== PROSPEREUM MAINNET PRE-DEPLOY CHECK ===");
        console.log("Deployer (ops wallet):", deployer);
        console.log("Founder Safe:         ", founderSafe);
        console.log("Treasury Safe:        ", treasurySafe);
        console.log("LP Token:             ", lpToken);
        console.log("USDC:                 ", USDC);
        console.log("Uniswap Router:       ", UNISWAP_V3_ROUTER);
        console.log("Genesis timestamp:    ", genesis);
        console.log("==========================================\n");

        vm.startBroadcast(deployerPk);

        // ── 1. Deploy PSRE ───────────────────────────────────────────────────
        // On mainnet: teamVesting placeholder = deployer (ops key).
        // After deploy, deployer transfers 4.2M to Founder Safe for Sablier.
        // PSRE constructor mints:
        //   - 4.2M to treasury (Treasury Safe)
        //   - 4.2M to teamVesting param (deployer, then manually sent to Founder Safe)
        PSRE psre = new PSRE(
            founderSafe,  // admin (DEFAULT_ADMIN_ROLE, PAUSER_ROLE, UPGRADER_ROLE)
            treasurySafe, // treasury — receives 4.2M PSRE at genesis
            deployer,     // temp: deployer holds team allocation, transfers to Founder Safe below
            genesis
        );
        console.log("PSRE deployed:        ", address(psre));

        // Transfer team allocation (4.2M) from deployer -> Founder Safe
        // Shu will set up Sablier stream from Founder Safe for vesting
        psre.transfer(founderSafe, 4_200_000e18);
        console.log("Team tokens (4.2M) -> Founder Safe");

        // ── 2. Deploy PartnerVault + CustomerVault implementations ───────────
        PartnerVault vaultImpl = new PartnerVault();
        CustomerVault cvImpl   = new CustomerVault();
        console.log("PartnerVault impl:    ", address(vaultImpl));
        console.log("CustomerVault impl:   ", address(cvImpl));

        // ── 3. Deploy PartnerVaultFactory ────────────────────────────────────
        // admin = Founder Safe (governance/upgrades)
        PartnerVaultFactory factory = new PartnerVaultFactory(
            address(vaultImpl),
            address(cvImpl),
            address(psre),
            UNISWAP_V3_ROUTER,
            USDC,
            founderSafe  // owner = Founder Safe
        );
        console.log("PartnerVaultFactory:  ", address(factory));

        // ── 4. Deploy StakingVault ───────────────────────────────────────────
        StakingVault stakingVault = new StakingVault(
            address(psre),
            lpToken,
            genesis,
            founderSafe  // owner = Founder Safe
        );
        console.log("StakingVault:         ", address(stakingVault));

        // ── 5. Deploy RewardEngine via UUPS proxy ────────────────────────────
        RewardEngine reImpl = new RewardEngine();
        bytes memory reInitData = abi.encodeCall(
            RewardEngine.initialize,
            (address(psre), address(factory), address(stakingVault), genesis, founderSafe)
        );
        ERC1967Proxy reProxy      = new ERC1967Proxy(address(reImpl), reInitData);
        RewardEngine rewardEngine = RewardEngine(address(reProxy));
        console.log("RewardEngine impl:    ", address(reImpl));
        console.log("RewardEngine proxy:   ", address(reProxy));

        // ── 6. Wire up ───────────────────────────────────────────────────────
        factory.setRewardEngine(address(rewardEngine));
        stakingVault.setRewardEngine(address(rewardEngine));
        psre.grantRole(psre.MINTER_ROLE(), address(rewardEngine));
        console.log("Wire-up complete: RE set on factory + SV, MINTER_ROLE granted");

        // ── 7. Transfer factory + stakingVault ownership to Founder Safe ─────
        // Contracts are deployed with founderSafe as owner already (passed to constructor).
        // If Ownable2Step: deployer never owned it — the founderSafe is already the owner.
        // No acceptOwnership() step needed since we passed founderSafe directly.
        console.log("Ownership: Founder Safe is owner of Factory + StakingVault + RE");

        vm.stopBroadcast();

        // ── Deployment summary ───────────────────────────────────────────────
        console.log("\n=== PROSPEREUM MAINNET DEPLOYMENT COMPLETE ===");
        console.log("Network:              Base mainnet (chainId: 8453)");
        console.log("Genesis timestamp:    ", genesis);
        console.log("---");
        console.log("PSRE:                 ", address(psre));
        console.log("PartnerVault impl:    ", address(vaultImpl));
        console.log("CustomerVault impl:   ", address(cvImpl));
        console.log("PartnerVaultFactory:  ", address(factory));
        console.log("StakingVault:         ", address(stakingVault));
        console.log("RewardEngine impl:    ", address(reImpl));
        console.log("RewardEngine proxy:   ", address(reProxy));
        console.log("---");
        console.log("Founder Safe (admin): ", founderSafe);
        console.log("Treasury Safe:        ", treasurySafe);
        console.log("Ops wallet:           ", deployer);
        console.log("==============================================\n");
        console.log("NEXT STEPS:");
        console.log("  1. Record all addresses in deployments.md IMMEDIATELY");
        console.log("  2. Treasury Safe: seed $40K Uniswap v3 LP (200K PSRE + $20K USDC)");
        console.log("  3. Lock LP NFT on Unicrypt for 24 months");
        console.log("  4. Shu: set up Sablier vesting stream from Founder Safe");
        console.log("  5. Update keeper cron with mainnet RPC + ops wallet key");
        console.log("  6. Send final commit hash to BlockApex to close audit");
        console.log("  7. Announce launch");
    }
}
