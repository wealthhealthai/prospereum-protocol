## PHOENIX — discord-channel-1479357527010578432 — 2026-03-30

**Status:** active — major milestone hit, audit sourcing in progress

---

## What Was Done

### v3.2 Deployed to Base Sepolia ✅
- Jason confirmed UPGRADE_TIMELOCK = **7 days** (over 2-day placeholder)
- Updated `RewardEngine.sol`: `UPGRADE_TIMELOCK = 7 days`
- Updated 2 tests that hardcoded 2-day values → 7-day values; 219/219 passing
- Deployed all 8 v3.2 contracts to Base Sepolia (chainId: 84532), all **Sourcify verified (exact_match)**
- `deployments.md` updated with full v3.2 registry + deploy log
- `decisions.md` updated with timelock + deploy decisions
- Committed & pushed: `7e96ba9` (deploy), `5922902` (goodnight)

**v3.2 Contract Addresses (Base Sepolia):**
| Contract | Address |
|---|---|
| PSRE | `0x1Dd17Ef4f289A915b20b50DaeE5D575541472EF0` |
| TeamVesting | `0xc13C0323B68015300E5d555e65D25E14D8A4d992` |
| PartnerVault impl | `0x6950b527955E8bEEC285c22948b83bc803b253cA` |
| CustomerVault impl | `0xa803577dB01987C8B556470Bf4C07046Eb0deb0F` |
| PartnerVaultFactory | `0x697026dE9e6ccc2e5a7481DA80B2332eD468B4c0` |
| StakingVault | `0x3ed7998F623A703E11970ADe5551e8E386A38aDb` |
| RewardEngine impl | `0xd8cCc356D51B54F779744F1e68D457fbCC2DdC85` |
| RewardEngine proxy | `0xe668fE9DbCE8CBbc8b3590100e8c31aA12F5C697` |

### Audit Sourcing
- **Cantina call (Shu):** Human review = $20–30K (over budget). They offer AI audit alternative — price TBD. Cantina does not offer competitive audits.
- **BlockApex contacted:** Confirmed they can meet $5K budget + April 3 deadline. Formal proposal incoming.
- **Pashov Audit Group contacted:** Awaiting quote. Preferred option if timeline + price work out.
- **Audit brief drafted:** Technical memo prepared for Shu to send to auditors — priority areas, scope, commit hash, delivery requirements.

### Audit Research
- Evaluated BlockApex: legitimate mid-tier firm, 4+ years, 30+ public reports. Yellow flag: lead auditor vuln directory showed 0 public findings. Acceptable for budget/timeline, not top-tier.
- Recommended decision framework: take Pashov if responds today, sign BlockApex if not.

---

## Open Items / Blockers

- **Pashov quote pending** — hard deadline: EOD 2026-03-30. If no response, sign BlockApex.
- **BlockApex formal proposal pending** — review when received, confirm April 3 delivery + named auditor in writing
- **Cantina AI audit pricing** — not yet received; may still be worth layering on top of human audit
- **Gnosis Safe creation** — Shu said he'd create today (Founder Safe + Treasury Safe at app.safe.global). Not confirmed complete yet.
- **Audit must kick off 2026-03-31 at latest** to hit April 3 results + April 4–7 mainnet window

---

## Needs Jason or Shu

- **Shu:** Confirm Gnosis Safes created (Founder + Treasury) — needed before mainnet deploy script can be finalized
- **Shu:** Sign audit contract (BlockApex or Pashov) — needs to happen first thing March 31
- **Shu:** Share BlockApex formal proposal with Kin for review before signing if there's anything unusual in the terms
