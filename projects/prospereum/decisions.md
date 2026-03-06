# Prospereum — Protocol Decisions Log

**Record every significant decision here: what was decided, why, and by whom.**

---

## Locked Design Decisions (from Dev Spec v2.10)

These are FROZEN. Do not deviate without Jason's explicit approval.

| Decision | Value | Rationale |
|----------|-------|-----------|
| Emission model | Epoch-based (weekly), not per-claim | Predictable, gas-efficient |
| Mining primitive | Vault-executed PSRE buys only | Proof of real demand |
| Vault sells | Disabled in v1 | Prevents buy/sell cycle gaming |
| Price oracle | None — no USD normalization | Eliminates oracle manipulation vector |
| Scarcity function | x = T/S_emission only | Pure on-chain, no external dependency |
| Revenue split | 70% partners / 30% stakers | Partners drive demand, stakers provide liquidity |
| Staker rewards | Time-weighted (anti flash-stake) | Prevents capital efficiency exploits |
| Partner status | Rolling EMA with tier multipliers | Smooth, manipulation-resistant |
| Launch policy | No presale, no ICO, no private sale | Fair launch, treasury seeds LP |
| Team vesting | 1-year cliff, 4-year linear | Standard alignment |

---

## In-Progress Decisions

_(add items here as they arise)_

---

## Completed Decisions

_(move items here once decided and implemented)_
