# Prospereum — Deployed Contracts

**Update this file every time anything is deployed. No exceptions.**

---

## Status: Base Sepolia Testnet — v3.2 LIVE ✅

All 8 v3.2 protocol contracts deployed and verified on Base Sepolia (2026-03-28).
v2.3 contracts (2026-03-10) are superseded — do not use.

**Target chain:** Base (EVM)
**GitHub:** https://github.com/wealthhealthai/prospereum-protocol (private)

---

## Contract Registry — v3.2 (CURRENT)

| Contract | Network | Address | Deployed | Tx Hash |
|----------|---------|---------|----------|---------|
| PSRE (ERC-20) | Base Sepolia | `0x1Dd17Ef4f289A915b20b50DaeE5D575541472EF0` | 2026-03-28 | `0xcdd5a582c91662d72432d41b07f68009456670fe787af274c0cf0247ec1cc9e8` |
| TeamVesting | Base Sepolia | `0xc13C0323B68015300E5d555e65D25E14D8A4d992` | 2026-03-28 | `0x07539d2da6ee5bbe389738260c7ddb4a514f0bee7b845c40dada0f857c9b7eaf` |
| PartnerVault (impl) | Base Sepolia | `0x6950b527955E8bEEC285c22948b83bc803b253cA` | 2026-03-28 | `0x5d5bc47bd5f713442037c08eb7309d283e6db892f46406988d1175c9c00396eb` |
| CustomerVault (impl) | Base Sepolia | `0xa803577dB01987C8B556470Bf4C07046Eb0deb0F` | 2026-03-28 | `0xa216efb3a0a172eabf711458a40edeee2864573971dbdb2c3541ac4c7843fe8b` |
| PartnerVaultFactory | Base Sepolia | `0x697026dE9e6ccc2e5a7481DA80B2332eD468B4c0` | 2026-03-28 | `0x49984ce396fbbb4a769e8e178c5c69992ee7e09901d21900ad24e1c642bd986d` |
| StakingVault | Base Sepolia | `0x3ed7998F623A703E11970ADe5551e8E386A38aDb` | 2026-03-28 | `0xb6232d71e2460a35d0b47a5cfd69a63a46cc82baa9aa27d63adcda550891ea52` |
| RewardEngine (impl) | Base Sepolia | `0xd8cCc356D51B54F779744F1e68D457fbCC2DdC85` | 2026-03-28 | `0x1b55e0d9c0db85798ea87d242753aaba2e22f253e5dd030769c1f0e0fba584d6` |
| RewardEngine (proxy) | Base Sepolia | `0xe668fE9DbCE8CBbc8b3590100e8c31aA12F5C697` | 2026-03-28 | `0x11524d215e96175979562d38b14e61c69c4c82cbd1d4f5a0ad3db3b85cb7bcf5` |

---

## Contract Registry — v2.3 (SUPERSEDED — DO NOT USE)

---

## Deployment Log

### 2026-03-28 — Base Sepolia v3.2 Full Protocol Deploy

**Network:** Base Sepolia (chainId: 84532)
**Deployer:** `0x117876aA935b4f18f929eD9F550df8785c9A9bd1`
**Admin / Treasury / Team Beneficiary:** `0x117876aA935b4f18f929eD9F550df8785c9A9bd1` (deployer == admin for testnet)
**Genesis Timestamp:** `1774726994`
**Deploy Script:** `script/Deploy.s.sol:Deploy`
**Broadcast file:** `broadcast/Deploy.s.sol/84532/run-latest.json`
**Spec version:** v3.2 (frozen 2026-03-27 by Shu)
**Tests at deploy:** 219/219 passing
**Upgrade timelock:** 7 days (UPGRADE_TIMELOCK = 7 days, decided 2026-03-28 by Jason)

#### PSRE (ERC-20)
- **Address:** `0x1Dd17Ef4f289A915b20b50DaeE5D575541472EF0`
- **Tx Hash:** `0xcdd5a582c91662d72432d41b07f68009456670fe787af274c0cf0247ec1cc9e8`
- **Notes:** Genesis supply 8,400,000 PSRE. 4.2M to treasury (deployer placeholder), 4.2M to deployer then transferred to TeamVesting. MINTER_ROLE granted to RewardEngine proxy post-deploy.

#### TeamVesting
- **Address:** `0xc13C0323B68015300E5d555e65D25E14D8A4d992`
- **Tx Hash:** `0x07539d2da6ee5bbe389738260c7ddb4a514f0bee7b845c40dada0f857c9b7eaf`
- **Notes:** 4,200,000 PSRE transferred from deployer. Single beneficiary: deployer (testnet placeholder). 1-year cliff, 4-year linear vest. On mainnet: Sablier replaces this (see decisions.md).

#### PartnerVault (implementation)
- **Address:** `0x6950b527955E8bEEC285c22948b83bc803b253cA`
- **Tx Hash:** `0x5d5bc47bd5f713442037c08eb7309d283e6db892f46406988d1175c9c00396eb`
- **Notes:** Logic-only EIP-1167 clone base. Not initialized. Used by PartnerVaultFactory.

#### CustomerVault (implementation) — NEW in v3.2
- **Address:** `0xa803577dB01987C8B556470Bf4C07046Eb0deb0F`
- **Tx Hash:** `0xa216efb3a0a172eabf711458a40edeee2864573971dbdb2c3541ac4c7843fe8b`
- **Notes:** Logic-only clone base for CustomerVaults. Partners deploy CVs on behalf of customers. Not initialized.

#### PartnerVaultFactory
- **Address:** `0x697026dE9e6ccc2e5a7481DA80B2332eD468B4c0`
- **Tx Hash:** `0x49984ce396fbbb4a769e8e178c5c69992ee7e09901d21900ad24e1c642bd986d`
- **Notes:** Owns PartnerVault + CustomerVault clone creation. `vaultImpl` = PartnerVault above. `cvImpl` = CustomerVault above. `inputToken` = USDC (Base mainnet addr as testnet placeholder). `router` = Uniswap V3 SwapRouter (Base mainnet addr, placeholder). RewardEngine wired via `setRewardEngine()`.

#### StakingVault
- **Address:** `0x3ed7998F623A703E11970ADe5551e8E386A38aDb`
- **Tx Hash:** `0xb6232d71e2460a35d0b47a5cfd69a63a46cc82baa9aa27d63adcda550891ea52`
- **Notes:** `lpToken` = PSRE address (placeholder — no real LP pool on testnet). RewardEngine wired via `setRewardEngine()`.

#### RewardEngine (implementation)
- **Address:** `0xd8cCc356D51B54F779744F1e68D457fbCC2DdC85`
- **Tx Hash:** `0x1b55e0d9c0db85798ea87d242753aaba2e22f253e5dd030769c1f0e0fba584d6`
- **Notes:** UUPS logic contract. Do not interact directly — use the proxy below.

#### RewardEngine (ERC1967 proxy) — PRIMARY ADDRESS
- **Address:** `0xe668fE9DbCE8CBbc8b3590100e8c31aA12F5C697`
- **Tx Hash:** `0x11524d215e96175979562d38b14e61c69c4c82cbd1d4f5a0ad3db3b85cb7bcf5`
- **Notes:** Core emission engine proxy. Initialized with PSRE, Factory, StakingVault, genesis, admin. Holds MINTER_ROLE on PSRE. UPGRADE_TIMELOCK = 7 days.

#### Wire-up transactions
| Action | Contract | Tx Hash |
|--------|----------|---------|
| `setRewardEngine()` | PartnerVaultFactory | `0x22d99c19d9a4ee1d2e4f82fa4a70dddbec8447d4795b9251ecb56d5e0110b968` |
| `setRewardEngine()` | StakingVault | `0x5677af0ee439227848a406e1e0d95b4514e56d0d96a65ebfeead224779d10141` |
| `grantRole(MINTER_ROLE)` | PSRE → RewardEngine proxy | `0x068dec645b1b6aad799a0ea57e8fa3884a29bfb377f9027bb52f0ef32cffb4f2` |

#### On-chain Verification (Sourcify)
All 8 contracts: ✅ `exact_match` on Sourcify

#### Post-Deploy Notes
- ⚠️ LP token = PSRE address (testnet placeholder) — replace with real PSRE/USDC Uniswap LP token on mainnet
- ⚠️ USDC + Uniswap Router = Base mainnet addresses (fine for testnet, no real swaps execute)
- ℹ️ Admin = deployer for testnet. Mainnet: deployer = CI key, admin = Gnosis Founder Safe
- ℹ️ TeamVesting.sol included for testnet only. Mainnet team tokens will use Sablier streams.
- ℹ️ Cantina commit hash to reference: update after pushing this deploy to git

---

### 2026-03-10 — Base Sepolia Full Protocol Deploy (v2.3 — SUPERSEDED)

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

## Gnosis Safes (Base Mainnet)

### PSRE Founder Safe
- Address: 0xc59816CAC94A969E50EdFf7CF49ce727aec1489F
- Role: Protocol governance + upgrade admin (DEFAULT_ADMIN_ROLE, PAUSER_ROLE, UPGRADER_ROLE)
- Signers: Shu, Jason, + 1 cold backup wallet (2-of-3)
- Created: 2026-04-18

### PSRE Treasury Safe
- Address: 0xa9Fde837EBC15BEE101d0D895c41a296Ac2CAfCe
- Role: PSRE treasury (receives 4.2M PSRE at genesis) + LP seeding
- Signers: Shu, Jason, + 1 cold backup wallet (2-of-3)
- Created: 2026-04-18

---

## MAINNET DEPLOYMENTS — Base (chainId: 8453)

### Phase 1 — 2026-04-22

#### PSRE Token
- **Network:** Base mainnet
- **Address:** `0x2fE08f304f1Af799Bc29E3D4E210973291d96702`
- **Deploy tx:** `0x80f18bb09f2eca4e9352cbfdf56d3c2d58da862ae9e7d1e62f8ed19d58095c81`
- **Transfer tx (4.2M → Founder Safe):** `0xf2f08c96b4efccb6c376023929c8fbd6c83f4831c0cac80621535455517bac42`
- **Deployer:** `0xa3C082910FF91425d45EBf15C52120cBc97aFef5` (throwaway ops wallet)
- **Genesis timestamp:** 1776829977
- **Notes:** 4.2M minted to Treasury Safe, 4.2M transferred to Founder Safe (Sablier vesting). 12.6M emission reserve minted by RewardEngine over epochs.

### Phase 2 — PENDING (waiting on LP pool from Shu)

#### Phase 2 — 2026-04-22

| Contract | Address | Deploy Tx |
|---|---|---|
| PartnerVault (impl) | `0xa1BcD31cA51Ba796c73578d1C095c9EE0adb9F18` | `0x97c0b2...4b4b6` |
| CustomerVault (impl) | `0xAb5906f5a3f03576678416799570d0A0ceEc40f2` | `0xb5bfe7...8f5e3` |
| PartnerVaultFactory | `0xFF84408633f79b8f562314cC5A3bCaedA8f76902` | `0x98424f...6411` |
| StakingVault | `0x684BEA07e979CB5925d546b2E2099aA1c632ED2D` | `0x9d88f8...5c08` |
| RewardEngine (impl) | `0xE194EF5ABB93cb62089FB5a3b407B9B7f38F04f5` | `0x1522c0...2944` |
| RewardEngine (proxy) | `0x9Ab37Fc6D01B85491Ed0863B7F832784bE717EF5` | `0xefd098...cece7` |

**LP Token (PSRE/USDC 1% pool, pre-computed):** `0x0Adc6BE14E76b89584216fAd4E458df5F996D336`

**⚠️ WIRING PENDING — Founder Safe batch transaction required:**
1. `factory.setRewardEngine(0x9Ab37Fc6D01B85491Ed0863B7F832784bE717EF5)`
2. `stakingVault.setRewardEngine(0x9Ab37Fc6D01B85491Ed0863B7F832784bE717EF5)`
3. `psre.grantRole(0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6, 0x9Ab37Fc6D01B85491Ed0863B7F832784bE717EF5)`
