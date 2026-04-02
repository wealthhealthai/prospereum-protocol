# Prospereum — Genesis LP Pool Specification

**Author:** Kin  
**Date:** 2026-04-02  
**Status:** DRAFT — awaiting Jason + Shu review  
**Decisions referenced:** D4 (Shu, 2026-03-12), LP lock (Shu, 2026-03-12)

---

## 1. Summary

At mainnet launch, WealthHealth seeds the initial PSRE/USDC liquidity pool on Uniswap v3 on Base. This document specifies the pool parameters, seeding execution plan, LP lock procedure, and ongoing LP management considerations.

---

## 2. Pool Parameters (from decisions.md)

| Parameter | Value | Decided By |
|---|---|---|
| DEX | Uniswap v3 on Base | Shu, 2026-03-12 |
| Token pair | PSRE / USDC | Shu, 2026-03-12 |
| Launch price | $0.10 / PSRE | Shu, 2026-03-12 |
| Total liquidity | $40,000 ($20K USDC + 200K PSRE) | Shu, 2026-03-12 |
| Fee tier | 1% | Shu, 2026-03-12 |
| Price range | $0.04 – $0.50 | Shu, 2026-03-12 |
| LP lock duration | 24 months via Unicrypt | Shu, 2026-03-12 |
| LP lock platform | app.uncx.network | Shu, 2026-03-12 |
| LP funded from | Treasury Safe | Shu, 2026-03-12 |

---

## 3. Pool Math

### 3.1 Token Amounts at Launch Price

At launch price $0.10/PSRE with a $0.04–$0.50 concentrated range on Uniswap v3:

```
Launch price:  P = 0.10 USDC/PSRE
Range lower:   Pa = 0.04 USDC/PSRE
Range upper:   Pb = 0.50 USDC/PSRE

sqrt(P)  = 0.31623
sqrt(Pa) = 0.20000
sqrt(Pb) = 0.70711

For $20,000 USDC + 200,000 PSRE at price = $0.10:

Check: 200,000 PSRE × $0.10 = $20,000 USDC ✅ (balanced at launch price)

Total value at deployment: $40,000
```

This is a balanced deposit at the launch price — no leftover tokens if P is exactly $0.10 at pool creation.

### 3.2 Effective Depth

The 1% fee tier with $40K liquidity in a $0.04–$0.50 range gives meaningful depth for early trading. At launch:
- A $1K market buy moves price ~2.5% (within range)
- A $5K market buy moves price ~13% (still within range)
- A $10K market buy exhausts roughly half the USDC side

This is appropriate for a fair-launch token — enough depth to prevent trivial manipulation, but not so deep that price discovery is suppressed.

### 3.3 Out-of-Range Risk

If price exits the $0.04–$0.50 range:
- Below $0.04: all liquidity converts to PSRE (no USDC remaining in pool)
- Above $0.50: all liquidity converts to USDC (no PSRE remaining in pool)

The 24-month lock means LP cannot be adjusted after seeding. Range was chosen conservatively (0.4×–5× launch price) to survive significant early volatility.

---

## 4. Execution Plan

### 4.1 Prerequisites

Before seeding:
- [ ] Treasury Safe created (Shu + Jason, app.safe.global) — **CURRENTLY BLOCKING**
- [ ] Treasury Safe holds ≥ 200K PSRE from genesis allocation
- [ ] Treasury Safe holds ≥ $20K USDC (funded by Jason/Shu)
- [ ] Mainnet PSRE contract deployed and verified
- [ ] Uniswap v3 router address on Base mainnet confirmed: `0x2626664c2603336E57B271c5C0b26F421741e481`
- [ ] USDC address on Base mainnet: `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`

### 4.2 Pool Creation Steps

**Step 1 — Create pool (if not yet created)**
```
Uniswap v3 Factory: 0x33128a8fC17869897dcE68Ed026d694621f6FDfD (Base)
Call: createPool(PSRE_address, USDC_address, 10000)  // 10000 = 1% fee
```

**Step 2 — Initialize pool price**
```
sqrtPriceX96 for $0.10/PSRE:
= sqrt(0.10 × 10^(USDC_decimals - PSRE_decimals)) × 2^96
= sqrt(0.10 × 10^(6-18)) × 2^96
= sqrt(0.10 × 10^-12) × 2^96
≈ 2505414483750479311  (exact value to be computed pre-deploy)

Call: pool.initialize(sqrtPriceX96)
```

**Step 3 — Approve tokens (from Treasury Safe)**
```
PSRE.approve(NonfungiblePositionManager, 200_000e18)
USDC.approve(NonfungiblePositionManager, 20_000e6)
```

**Step 4 — Add liquidity (mint position)**
```
NonfungiblePositionManager: 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f9 (Base)

Call: mint({
  token0: USDC_address,        // lower address token
  token1: PSRE_address,        // higher address token
  fee: 10000,                  // 1%
  tickLower: <tick for $0.04>,
  tickUpper: <tick for $0.50>,
  amount0Desired: 20_000e6,    // 20K USDC
  amount1Desired: 200_000e18,  // 200K PSRE
  amount0Min: 19_800e6,        // 1% slippage tolerance
  amount1Min: 198_000e18,
  recipient: Treasury_Safe_address,
  deadline: block.timestamp + 1200
})
```

**Tick calculation:**
```
tickLower = floor(log(0.04) / log(1.0001)) = floor(-32197) = -32200 (nearest usable)
tickUpper = floor(log(0.50) / log(1.0001)) = floor(-6932)  = -6930  (nearest usable)
(exact values to be verified with Uniswap tick math before deploy)
```

**Step 5 — Record LP NFT token ID**
The `mint()` call returns a `tokenId` — this is the LP NFT that must be locked via Unicrypt.

### 4.3 Lock Procedure (Unicrypt)

1. Go to app.uncx.network → Liquidity Lockers → Uniswap v3
2. Connect Treasury Safe (via WalletConnect)
3. Select the LP NFT (tokenId from Step 5)
4. Set lock duration: **24 months** from deploy date
5. Beneficiary: Treasury Safe address
6. Confirm and sign from Treasury Safe (requires both signers: Jason + Shu)
7. Record: lock TX hash, unlock date, Unicrypt lock ID

**Unicrypt fee:** ~1% of LP value + small ETH gas fee. Budget ~$400–$500 for lock.

---

## 5. Treasury Funding Requirements

Before mainnet deploy:
| Item | Amount | Source |
|---|---|---|
| PSRE for LP | 200,000 PSRE | Treasury allocation (already minted at genesis) |
| USDC for LP | $20,000 USDC | Jason + Shu fund Treasury Safe |
| USDC for Unicrypt lock fee | ~$400–$500 | Jason + Shu fund Treasury Safe |
| ETH for gas (Base) | ~0.005 ETH | Ops wallet |

Total cash needed from team: **~$20,500 USDC** into Treasury Safe before mainnet.

---

## 6. Post-Launch LP Monitoring

### 6.1 Price Range Health
Monitor whether price stays within $0.04–$0.50:
- If price approaches $0.04 or $0.50, LP goes out of range — fees stop accruing
- LP is locked for 24 months — **cannot adjust range after locking**
- Range is wide enough that this should not be an issue at launch scale

### 6.2 Impermanent Loss
At 24-month lock with full volatility exposure:
- If PSRE trades at $0.50 at unlock: LP value ≈ $80K (IL offsets some gain)
- If PSRE trades at $0.04 at unlock: LP value ≈ $24K (significant IL)
- Fees earned over 24 months partially offset IL

This is the accepted trade-off for a 24-month lock. The goal is price stability and market credibility, not LP profit optimization.

### 6.3 Metrics to Watch
- Pool depth / TVL (Uniswap v3 analytics)
- 24h volume and fee income
- Price range utilization (active vs. out-of-range)
- Large wallet accumulation patterns

---

## 7. Open Questions

| # | Question | Recommendation |
|---|---|---|
| Q1 | Token0/Token1 order (PSRE vs USDC address ordering)? | Verify before deploy — lower address = token0 in Uniswap v3 |
| Q2 | Exact sqrtPriceX96 value? | Compute precisely pre-deploy, verify with Uniswap SDK |
| Q3 | Exact tick values for $0.04/$0.50? | Verify with Uniswap v3 tick math — must use tick spacing of 200 (1% pools) |
| Q4 | Treasury Safe address? | Not yet created — **Shu action item** |
| Q5 | USDC sourcing — where does the $20K come from? | Jason + Shu to confirm source and timing |
| Q6 | Timing relative to token deployment? | Seed LP within same deploy script or immediately after token deploy |

---

## 8. Pre-Mainnet Checklist

- [ ] Treasury Safe created (Shu + Jason)
- [ ] Treasury Safe funded: 200K PSRE + $20K USDC + ~$500 for fees
- [ ] Uniswap v3 pool addresses verified on Base mainnet
- [ ] sqrtPriceX96 computed and verified (Uniswap SDK)
- [ ] Tick values verified (tick spacing = 200 for 1% pools)
- [ ] LP seeding script written + tested on Base Sepolia (mock USDC)
- [ ] Unicrypt lock procedure rehearsed (testnet if possible)
- [ ] Treasury Safe signers (Jason + Shu) aligned on timing and process
