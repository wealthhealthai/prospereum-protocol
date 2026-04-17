# GOODNIGHT.md — 2026-04-17

## What Was Done Today

**BlockApex final report landed — 3 additional findings — all fixed same day.**

| Commit | What |
|---|---|
| `4ca5bfc` | Additional #1 (HIGH): O(1) Synthetix accumulator in StakingVault v3.1 |
| `4ca5bfc` | Additional #2 (HIGH): scarcityCeiling DoS clamp |
| `4ca5bfc` | Additional #3 (MEDIUM): zero-staker mint prevention |
| `1fdcf2f` | Audit CSV updated with all 3 additional findings |

**Tests: 247 → 249/249 ✅**
**Total findings resolved: 28 (22 original + 3 self-identified + 3 additional)**

## ⚠️ APRIL 18 IS TOMORROW

Epoch 2 closes at 19:43 UTC. Mainnet window opens.

**Gnosis Safe is the ONLY remaining blocker.** Still not created after 4+ weeks.
app.safe.global — Founder Safe + Treasury Safe — Jason + Shu — **tonight or first thing tomorrow.**

## Protocol State

- **Tests:** 249/249 ✅
- **All 28 findings:** Resolved ✅
- **StakingVault:** v3.1 — true O(1) Synthetix accumulator
- **DeployMainnet.s.sol:** Ready — needs FOUNDER_SAFE + TREASURY_SAFE env vars
- **Nadir:** Awaiting confirmation of additional fixes
- **Gnosis Safe:** ❌ Not created — zero mainnet deploy without it
- **Epoch 2 closes:** April 18 19:43 UTC — keeper auto-fires

## Sequence When Gnosis Safe Is Created

1. Fill `.env`: `FOUNDER_SAFE`, `TREASURY_SAFE`
2. Deploy Uniswap PSRE/USDC pool → get `LP_TOKEN_ADDRESS`
3. Give Kin explicit go: "deploy to Base Sepolia" → verify latest code on testnet
4. Give Kin explicit go: "deploy to mainnet" → `forge script script/DeployMainnet.s.sol`
5. Record all addresses in `deployments.md`
6. Treasury Safe seeds genesis LP ($40K Uniswap v3)
7. Lock LP NFT on Unicrypt (24 months)
8. Shu: Sablier vesting from Founder Safe
9. Close audit with Nadir (share mainnet commit hash)

## Notes for Tomorrow

1. Gnosis Safes → `.env` → everything else flows
2. Confirm Nadir accepted additional fixes (#1/#2/#3)
3. Epoch 2 keeper fires automatically at 20:00 UTC — no action needed
4. April 18–21 is a narrow window — every hour matters
