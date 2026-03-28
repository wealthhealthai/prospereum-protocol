// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/core/PSRE.sol";
import "../contracts/core/PartnerVault.sol";
import "../contracts/core/PartnerVaultFactory.sol";
import "../contracts/core/CustomerVault.sol";
import "../contracts/periphery/StakingVault.sol";
import "../contracts/periphery/RewardEngine.sol";
import "../contracts/periphery/TeamVesting.sol";

/**
 * @title Deploy
 * @notice Full Prospereum protocol deployment script.
 *
 * DEPLOYMENT ORDER (order matters — contracts depend on each other):
 *   1. TeamVesting     — needs PSRE address (deployed before PSRE via CREATE2 or deploy first then set)
 *                        Workaround: deploy TeamVesting with placeholder, then set PSRE after.
 *                        Simpler: deploy PSRE first, then TeamVesting.
 *   2. PSRE            — needs: admin, treasury, teamVesting, genesisTimestamp
 *   3. PartnerVault    — implementation contract (not initialized — clones use it)
 *   4. PartnerVaultFactory — needs: vaultImpl, psre, router, inputToken, admin
 *   5. StakingVault    — needs: psre, lpToken, genesisTimestamp, admin
 *   6. RewardEngine    — needs: psre, factory, stakingVault, genesisTimestamp, admin
 *   7. Wire up:
 *      - factory.setRewardEngine(rewardEngine)
 *      - stakingVault.setRewardEngine(rewardEngine)
 *      - psre.grantRole(MINTER_ROLE, rewardEngine)
 *
 * USAGE:
 *   Testnet (Base Sepolia):
 *     forge script script/Deploy.s.sol:Deploy \
 *       --rpc-url $BASE_SEPOLIA_RPC \
 *       --broadcast \
 *       --verify \
 *       -vvvv
 *
 *   Mainnet (BASE — Jason approval required):
 *     forge script script/Deploy.s.sol:Deploy \
 *       --rpc-url $BASE_RPC \
 *       --broadcast \
 *       --verify \
 *       -vvvv
 *
 * ENVIRONMENT VARIABLES REQUIRED:
 *   DEPLOYER_PK         — deployer private key (use hardware wallet for mainnet)
 *   ADMIN_ADDRESS       — Gnosis Safe multisig address (receives admin roles)
 *   TREASURY_ADDRESS    — Treasury Gnosis Safe address
 *   TEAM_VESTING_BENS   — comma-separated beneficiary addresses
 *   TEAM_VESTING_ALLOCS — comma-separated allocations (must sum to 4200000e18)
 *   USDC_ADDRESS        — USDC token address on Base
 *   LP_TOKEN_ADDRESS    — PSRE/USDC LP token address (deploy pool first, then set this)
 *   UNISWAP_ROUTER      — Uniswap v3 SwapRouter address on Base
 *   GENESIS_TIMESTAMP   — Unix timestamp for protocol genesis (typically block.timestamp at deploy)
 */
contract Deploy is Script {

    // ─────────────────────────────────────────────────────────────────────────
    // Known addresses on Base mainnet
    // ─────────────────────────────────────────────────────────────────────────

    // Uniswap v3 SwapRouter on Base mainnet
    address constant UNISWAP_V3_ROUTER_BASE = 0x2626664c2603336E57B271c5C0b26F421741e481;

    // USDC on Base mainnet
    address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    // ─────────────────────────────────────────────────────────────────────────
    // Deploy
    // ─────────────────────────────────────────────────────────────────────────

    function run() external {
        uint256 deployerPk    = vm.envUint("DEPLOYER_PK");
        address admin         = vm.envAddress("ADMIN_ADDRESS");
        address treasury      = vm.envAddress("TREASURY_ADDRESS");
        address usdcAddress   = vm.envOr("USDC_ADDRESS",   USDC_BASE);
        address routerAddress = vm.envOr("UNISWAP_ROUTER", UNISWAP_V3_ROUTER_BASE);
        uint256 genesis       = vm.envOr("GENESIS_TIMESTAMP", block.timestamp);

        // LP token address — set AFTER the Uniswap pool is created
        // For testnet, use a mock ERC20. For mainnet, deploy pool first.
        address lpToken = vm.envOr("LP_TOKEN_ADDRESS", address(0));

        address deployer = vm.addr(deployerPk);
        console.log("Deployer:  ", deployer);
        console.log("Admin:     ", admin);
        console.log("Treasury:  ", treasury);
        console.log("Genesis:   ", genesis);

        vm.startBroadcast(deployerPk);

        // ── 1. Deploy TeamVesting ────────────────────────────────────────────
        // Parse beneficiaries and allocations from env
        // For simplicity in the script, we support a single beneficiary.
        // For multi-beneficiary, extend this section.
        address[] memory bens   = new address[](1);
        uint256[] memory allocs = new uint256[](1);
        bens[0]   = vm.envOr("TEAM_BENEFICIARY", admin); // default to admin for testnet
        allocs[0] = 4_200_000e18;

        // TeamVesting is deployed BEFORE PSRE (it receives genesis mint)
        // We pass a placeholder PSRE address and update it... actually TeamVesting
        // takes PSRE address in constructor. We need PSRE first.
        // Deploy order: PSRE (without teamVesting addr) is impossible since PSRE
        // needs teamVesting address to mint to it.
        //
        // Solution: Deploy TeamVesting with deployer as temporary placeholder,
        // then deploy PSRE pointing to TeamVesting address.
        // TeamVesting constructor takes _psre so we need to pass PSRE address.
        //
        // Correct order: pre-compute PSRE address using CREATE2 or deploy PSRE
        // to a proxy first. Simpler: deploy a minimal TeamVesting wrapper that
        // accepts tokens via a separate initialize step.
        //
        // PRACTICAL SOLUTION for v1: Deploy PSRE with treasury as temp teamVesting,
        // then deploy TeamVesting separately, then transfer team tokens from treasury.
        // This avoids CREATE2 complexity.
        //
        // For this script: deploy PSRE pointing teamVesting = deployer,
        // then deploy TeamVesting, then treasury transfers 4.2M to TeamVesting.

        // ── 2. Deploy PSRE ───────────────────────────────────────────────────
        // teamVesting = deployer temporarily (will transfer to real TeamVesting)
        PSRE psre = new PSRE(
            admin,      // admin (DEFAULT_ADMIN_ROLE + PAUSER_ROLE)
            treasury,   // treasury receives 4.2M at genesis
            deployer,   // temporary teamVesting — deployer receives team tokens
            genesis
        );
        console.log("PSRE:              ", address(psre));
        console.log("PSRE totalSupply:  ", psre.totalSupply());

        // ── 3. Deploy TeamVesting ────────────────────────────────────────────
        TeamVesting teamVesting = new TeamVesting(
            address(psre),
            genesis,
            bens,
            allocs
        );
        console.log("TeamVesting:       ", address(teamVesting));

        // Transfer team allocation from deployer to TeamVesting
        // (deployer holds it since PSRE constructor minted to deployer as placeholder)
        psre.transfer(address(teamVesting), 4_200_000e18);
        console.log("Team tokens transferred to TeamVesting");

        // ── 4. Deploy PartnerVault + CustomerVault implementations ───────────
        PartnerVault vaultImpl = new PartnerVault();
        console.log("PartnerVault impl: ", address(vaultImpl));
        CustomerVault cvImpl = new CustomerVault();
        console.log("CustomerVault impl:", address(cvImpl));

        // ── 5. Deploy PartnerVaultFactory (v3.2: +CustomerVault impl, S_MIN) ─
        PartnerVaultFactory factory = new PartnerVaultFactory(
            address(vaultImpl),
            address(cvImpl),
            address(psre),
            routerAddress,
            usdcAddress,
            admin
        );
        console.log("Factory:           ", address(factory));

        // ── 6. Deploy StakingVault ───────────────────────────────────────────
        // LP token: if not set (testnet), use PSRE itself as placeholder
        if (lpToken == address(0)) {
            lpToken = address(psre);
            console.log("WARNING: LP token not set, using PSRE as placeholder for testnet");
        }
        StakingVault stakingVault = new StakingVault(
            address(psre),
            lpToken,
            genesis,
            admin
        );
        console.log("StakingVault:      ", address(stakingVault));

        // ── 7. Deploy RewardEngine ───────────────────────────────────────────
        RewardEngine rewardEngine = new RewardEngine(
            address(psre),
            address(factory),
            address(stakingVault),
            genesis,
            admin
        );
        console.log("RewardEngine:      ", address(rewardEngine));

        // ── 8. Wire up ───────────────────────────────────────────────────────
        // Factory: set rewardEngine
        factory.setRewardEngine(address(rewardEngine));
        console.log("Factory.rewardEngine set");

        // StakingVault: set rewardEngine
        stakingVault.setRewardEngine(address(rewardEngine));
        console.log("StakingVault.rewardEngine set");

        // PSRE: grant MINTER_ROLE to RewardEngine
        psre.grantRole(psre.MINTER_ROLE(), address(rewardEngine));
        console.log("PSRE: MINTER_ROLE granted to RewardEngine");

        // ── 9. Note on ownership ──────────────────────────────────────────────
        // Factory and StakingVault are deployed with `admin` as the initial owner
        // (passed directly to Ownable constructor — no pending transfer to accept).
        // If deployer != admin (e.g. a CI key deploys but multisig is admin),
        // transfer ownership after deploy: factory.transferOwnership(admin) then
        // admin calls acceptOwnership() from the Gnosis Safe.
        // For testnet with deployer == admin: no action needed.

        vm.stopBroadcast();

        // ── 10. Log deployment summary ───────────────────────────────────────
        console.log("\n=== PROSPEREUM DEPLOYMENT SUMMARY ===");
        console.log("Network:       Base");
        console.log("Genesis:       ", genesis);
        console.log("PSRE:          ", address(psre));
        console.log("TeamVesting:   ", address(teamVesting));
        console.log("VaultImpl:     ", address(vaultImpl));
        console.log("Factory:       ", address(factory));
        console.log("StakingVault:  ", address(stakingVault));
        console.log("RewardEngine:  ", address(rewardEngine));
        console.log("Admin:         ", admin);
        console.log("Treasury:      ", treasury);
        console.log("=====================================");
        console.log("IMPORTANT: Record all addresses in deployments.md");
        console.log("IMPORTANT: Admin must call acceptOwnership() on Factory and StakingVault");
        console.log("IMPORTANT: Grant PAUSER_ROLE on RewardEngine to admin if needed");
    }
}
