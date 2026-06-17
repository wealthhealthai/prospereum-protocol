# Security Audit — Prospereum Protocol
**Date:** 2026-06-17
**Triggered by:** Forge app secrets exposure incident — Jason's request
**Auditor:** Kin

---

## Summary

**Protocol funds are NOT at risk.** Gnosis Safes (Founder + Treasury) are protected by 2-of-3 multisig and were never exposed. Two actionable findings — both low-to-medium risk.

---

## Findings

### 🔴 Finding 1 — Mainnet Ops Wallet DEPLOYER_PK

| | |
|---|---|
| **Key** | `0x1668a648eecbb8b328589f7cf5e1067a9b25eb77b2b00432692e6e0f766e33d5` |
| **Wallet** | `0xa3C082910FF91425d45EBf15C52120cBc97aFef5` |
| **Balance** | ~0.05 ETH on Base mainnet (gas only) |
| **Location** | `.env` file only — gitignored, confirmed NOT in git history |
| **Capabilities** | Call `finalizeEpoch()` (permissionless anyway), drain ~0.05 ETH |
| **Protocol risk** | NONE — no admin roles, no protocol assets |
| **Action** | Rotate as precaution: new wallet → transfer ETH → update `.env` → update keeper cron |

### 🟠 Finding 2 — Basescan API Key in Git History

| | |
|---|---|
| **Key** | `AEMS8H7UYHQTUP7XBJZZN1W1QKBQF997IE` |
| **Location** | `memory/2026-03-12.md` (force-committed, publicly visible in repo) |
| **Access** | Read-only contract verification — no financial access |
| **Risk** | Low (free API key) |
| **Action** | Rotate at basescan.org/myapikey |

---

## Non-Issues

| Item | Why Not a Risk |
|---|---|
| `DeployFork.s.sol` key `0xac0974...` | Well-known Foundry/Anvil test account #0 (`0xf39Fd...`), local fork only (chainId 31337) |
| `forge-std` Infura key `b9794ad...` | Public Foundry demo key in the forge-rs/forge-std library — not WH's key |
| Broadcast files | Public addresses + calldata only, no private keys |
| Testnet deployer `0x117876...` | Throwaway testnet wallet, key never committed to git |

---

## Protocol Asset Security — All Clear

| Asset | Protection | Status |
|---|---|---|
| Founder Safe `0xc59816CA...` | 2-of-3 multisig (Jason + Shu + backup) | ✅ Secure |
| Treasury Safe `0xa9Fde837...` | 2-of-3 multisig | ✅ Secure |
| 8.4M PSRE (4.2M each Safe) | Multisig controlled | ✅ Secure |
| RewardEngine upgrade authority | Founder Safe only | ✅ Secure |
| PSRE MINTER_ROLE | RewardEngine proxy only | ✅ Secure |

---

## Recommended Actions

1. **🔴 Rotate DEPLOYER_PK** — generate new ops wallet, transfer ETH, update `.env`, update keeper cron `3fc22360`
2. **🟠 Rotate Basescan API key** — get new key at basescan.org/myapikey, update `.env`
3. **🟡 Optional** — `git filter-repo` to remove Basescan key from history (low priority)
