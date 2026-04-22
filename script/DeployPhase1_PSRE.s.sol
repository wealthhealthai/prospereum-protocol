// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/core/PSRE.sol";

/**
 * @title DeployPhase1_PSRE
 * @notice Phase 1 of two-phase mainnet deploy.
 *         Deploys PSRE token only so Shu can establish the
 *         Uniswap v3 PSRE/USDC LP pool before Phase 2.
 *
 * After running this script:
 *   1. Note the PSRE address printed below.
 *   2. Shu creates Uniswap v3 PSRE/USDC pool (1% fee) on Base mainnet.
 *   3. Get the LP token address (Uniswap v2 ERC-20 or wrapper).
 *   4. Add to .env:  PSRE_ADDRESS=<address>
 *                   LP_TOKEN_ADDRESS=<address>
 *   5. Run DeployPhase2_Contracts.s.sol
 *
 * USAGE:
 *   source .env
 *   forge script script/DeployPhase1_PSRE.s.sol:DeployPhase1_PSRE \
 *     --rpc-url $BASE_RPC \
 *     --broadcast \
 *     -vvvv
 */
contract DeployPhase1_PSRE is Script {

    /// @dev USDC on Base mainnet
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    function run() external {
        uint256 deployerPk   = vm.envUint("DEPLOYER_PK");
        address founderSafe  = vm.envAddress("FOUNDER_SAFE");
        address treasurySafe = vm.envAddress("TREASURY_SAFE");
        address deployer     = vm.addr(deployerPk);

        require(founderSafe  != address(0), "Phase1: FOUNDER_SAFE not set");
        require(treasurySafe != address(0), "Phase1: TREASURY_SAFE not set");
        require(founderSafe  != deployer,   "Phase1: safe cannot be deployer");
        require(treasurySafe != deployer,   "Phase1: safe cannot be deployer");

        uint256 genesis = block.timestamp;

        console.log("\n=== PROSPEREUM PHASE 1: PSRE DEPLOY ===");
        console.log("Deployer:      ", deployer);
        console.log("Founder Safe:  ", founderSafe);
        console.log("Treasury Safe: ", treasurySafe);
        console.log("Genesis:       ", genesis);

        vm.startBroadcast(deployerPk);

        // Deploy PSRE
        // Constructor mints:
        //   4.2M  -> treasury (Treasury Safe)
        //   4.2M  -> teamVesting param (deployer, immediately forwarded to Founder Safe)
        //   4.2M  -> stays in PSRE contract for ecosystem rewards (minted by RE over epochs)
        PSRE psre = new PSRE(
            founderSafe,  // admin: DEFAULT_ADMIN_ROLE, PAUSER_ROLE, UPGRADER_ROLE
            treasurySafe, // treasury: receives 4.2M at genesis
            deployer,     // temp team vesting holder; forwarded to Founder Safe below
            genesis
        );

        // Forward team allocation (4.2M) -> Founder Safe
        // Shu sets up Sablier vesting stream from Founder Safe
        psre.transfer(founderSafe, 4_200_000e18);

        vm.stopBroadcast();

        console.log("\n=== PHASE 1 COMPLETE ===");
        console.log("PSRE deployed:       ", address(psre));
        console.log("Treasury Safe holds: 4,200,000 PSRE");
        console.log("Founder Safe holds:  4,200,000 PSRE (set up Sablier vesting)");
        console.log("");
        console.log(">>> NEXT STEPS:");
        console.log("1. Shu: create Uniswap v3 PSRE/USDC pool (1% fee) at app.uniswap.org");
        console.log("2. Get LP token address");
        console.log("3. Add to .env:");
        console.log("     PSRE_ADDRESS=", address(psre));
        console.log("     LP_TOKEN_ADDRESS=<pool or wrapper address>");
        console.log("4. Run: forge script script/DeployPhase2_Contracts.s.sol ...");
        console.log("========================\n");
    }
}
