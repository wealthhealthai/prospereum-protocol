# Prospereum — Deployed Contracts

**Update this file every time anything is deployed. No exceptions.**

---

## Status: Base Sepolia Testnet — LIVE ✅

All 6 core protocol contracts deployed and verified on Base Sepolia.

**Target chain:** Base (EVM)
**GitHub:** https://github.com/wealthhealthai/prospereum-protocol (private)

---

## Contract Registry

| Contract | Network | Address | Deployed | Tx Hash |
|----------|---------|---------|----------|---------|
| PSRE (ERC-20) | Base Sepolia | `0xAB86B29fEcf144Bd0E824B6f703E0111cE5baDC2` | 2026-03-10 | `0x2d4d3ae19451dd6465970ccca3d3a1039168f61e19dfb8f7b89408a623b7695d` |
| TeamVesting | Base Sepolia | `0x90122C87fFFb4Ea81A8F1C20B864371FbCb714a9` | 2026-03-10 | `0xbf658eae8a1985caf10339db6f982c0bf0be93e1de02e53035931d692a7bacb5` |
| PartnerVault (impl) | Base Sepolia | `0xF65FC55e29479CA548506229AEaeD77643BED0DE` | 2026-03-10 | `0x96c8e65d831651b5e9a76fb1e41b6a5823a70bb22bff94b8314cda071a9b15e6` |
| PartnerVaultFactory | Base Sepolia | `0xdB95C8c288e9Bb888C15537C671edF350a46A124` | 2026-03-10 | `0xf094e01e562c683cb7bc1078d3f9e11bba42ed0bd401145d45189d63bd6539cb` |
| StakingVault | Base Sepolia | `0x1de0fd78ee178E06920121355B57735F7520aFE8` | 2026-03-10 | `0x12102ad8ff4dd09d1811c52ae1ddc477eb3b3b4a6463c6c978a8ca95f204b202` |
| RewardEngine | Base Sepolia | `0xa37B3d28fB0E4942256c2c93A39aBA80063ECF4e` | 2026-03-10 | `0x1f97ff506734652b26c9eba4536adfee947c9e80efd3f4e63a074a660d5715d0` |

---

## Deployment Log

### 2026-03-10 — Base Sepolia Full Protocol Deploy

**Network:** Base Sepolia (chainId: 84532)
**Deployer:** `0x117876aA935b4f18f929eD9F550df8785c9A9bd1`
**Admin / Treasury / Team Beneficiary:** `0x117876aA935b4f18f929eD9F550df8785c9A9bd1` (deployer == admin for testnet)
**Genesis Timestamp:** `1773195158`
**Deploy Script:** `script/Deploy.s.sol:Deploy`
**Broadcast file:** `broadcast/Deploy.s.sol/84532/run-latest.json`

#### PSRE (ERC-20)
- **Address:** `0xAB86B29fEcf144Bd0E824B6f703E0111cE5baDC2`
- **Tx Hash:** `0x2d4d3ae19451dd6465970ccca3d3a1039168f61e19dfb8f7b89408a623b7695d`
- **Notes:** Genesis supply 8,400,000 PSRE minted. 4.2M to treasury (deployer placeholder), 4.2M to deployer as temp teamVesting holder. MINTER_ROLE granted to RewardEngine post-deploy.

#### TeamVesting
- **Address:** `0x90122C87fFFb4Ea81A8F1C20B864371FbCb714a9`
- **Tx Hash:** `0xbf658eae8a1985caf10339db6f982c0bf0be93e1de02e53035931d692a7bacb5`
- **Notes:** 4,200,000 PSRE transferred from deployer (team allocation). Single beneficiary: deployer address. 1-year cliff, 4-year vest.

#### PartnerVault (implementation / clone base)
- **Address:** `0xF65FC55e29479CA548506229AEaeD77643BED0DE`
- **Tx Hash:** `0x96c8e65d831651b5e9a76fb1e41b6a5823a70bb22bff94b8314cda071a9b15e6`
- **Notes:** Logic-only contract. Not initialized. Used as EIP-1167 clone implementation by PartnerVaultFactory.

#### PartnerVaultFactory
- **Address:** `0xdB95C8c288e9Bb888C15537C671edF350a46A124`
- **Tx Hash:** `0xf094e01e562c683cb7bc1078d3f9e11bba42ed0bd401145d45189d63bd6539cb`
- **Notes:** Owns PartnerVault clone creation. `vaultImplementation` = PartnerVault impl above. `inputToken` = USDC (Base mainnet addr used as placeholder on testnet). `router` = Uniswap V3 SwapRouter (Base mainnet addr, placeholder on testnet). RewardEngine wired via `setRewardEngine()`.

#### StakingVault
- **Address:** `0x1de0fd78ee178E06920121355B57735F7520aFE8`
- **Tx Hash:** `0x12102ad8ff4dd09d1811c52ae1ddc477eb3b3b4a6463c6c978a8ca95f204b202`
- **Notes:** `lpToken` = PSRE address (placeholder — no real LP pool on testnet yet). RewardEngine wired via `setRewardEngine()`.

#### RewardEngine
- **Address:** `0xa37B3d28fB0E4942256c2c93A39aBA80063ECF4e`
- **Tx Hash:** `0x1f97ff506734652b26c9eba4536adfee947c9e80efd3f4e63a074a660d5715d0`
- **Notes:** Core emission engine. Wired to PSRE, PartnerVaultFactory, and StakingVault. Holds MINTER_ROLE on PSRE.

#### Wire-up transactions
| Action | Contract | Tx Hash |
|--------|----------|---------|
| `setRewardEngine()` | PartnerVaultFactory | `0xc13afd815837edbf76a51f948caed40f409efc3b19df6443aa08f00cfd635c16` |
| `setRewardEngine()` | StakingVault | `0xa07df75aebfaa7a9018942179432181c2b0659982594db475163680c7e65a5ad` |
| `grantRole(MINTER_ROLE)` | PSRE → RewardEngine | `0x359e8f1c33ca4fead6b9917d3575b0710983bbb73df004d4b916559ee661f70e` |

#### On-chain Verification (cast code)
| Contract | Result |
|----------|--------|
| PSRE | ✅ PASS (8430 chars bytecode) |
| TeamVesting | ✅ PASS (3368 chars bytecode) |
| PartnerVault impl | ✅ PASS (7386 chars bytecode) |
| PartnerVaultFactory | ✅ PASS (5710 chars bytecode) |
| StakingVault | ✅ PASS (9080 chars bytecode) |
| RewardEngine | ✅ PASS (19156 chars bytecode) |

#### Post-Deploy Notes
- ⚠️ LP token is set to PSRE address as testnet placeholder — replace with real LP token when PSRE/USDC Uniswap pool is deployed
- ⚠️ USDC and Uniswap Router addresses are Base **mainnet** addresses — fine for testnet simulation but no real swaps will execute
- ℹ️ Admin = deployer for testnet. On mainnet, deployer should be a CI key and admin should be a Gnosis Safe multisig
- ℹ️ Deployer ETH balance after deploy: **0.009958522305984856 ETH** (started with 0.01 ETH, gas cost ~0.0000415 ETH)
