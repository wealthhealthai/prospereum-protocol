# GOODNIGHT.md — 2026-04-23

## Prospereum is Operational on Base Mainnet ✅

Wiring complete (April 22, 12:18 PDT). Jason + Shu signed. Protocol is live.

**Wiring tx:** `0x66a1e7e131f55767b2a827e3a0cf0a8068d0d411da067660f4449b541371f6cd`

## Keeper

- Script: KEEPER_NETWORK=mainnet → `0x9Ab37Fc6D01B85491Ed0863B7F832784bE717EF5` ✅
- Cron: daily 05:00 UTC. Dry-run verified. ✅
- **⚠️ Ops wallet key needed:** `DEPLOYER_PK` in `.env` must be updated to mainnet ops wallet key before **April 29 05:00 UTC** (Epoch 0 finalization). Current `.env` has testnet throwaway key.
- **⚠️ Ops wallet funding:** `0xa3C082910FF91425d45EBf15C52120cBc97aFef5` needs ≥ 0.05 ETH on Base mainnet.

## Post-Deploy Checklist

| Item | Who | Status |
|---|---|---|
| Wiring batch | Jason + Shu | ✅ Done |
| Genesis LP seeding ($40K) | Jason + Shu | ⏳ |
| Unicrypt LP lock (24 months) | Jason + Shu | ⏳ |
| setSplit(1e18, 0) — disable LP staking | Founder Safe | ⏳ |
| Sablier vesting from Founder Safe | Shu | ⏳ |
| Basescan contract verification | Kin | ⏳ |
| Dashboard update (mainnet addresses) | Kin | ⏳ |
| Ops wallet key + funding for keeper | Jason | **⚠️ Before April 29** |
| Nadir final commit hash → audit closed | Jason | ⏳ |
| BlockApex badge on website | Jason | ⏳ |

## Epoch Schedule

- **Epoch 0 closes: April 29 03:52 UTC**
- Keeper fires: April 29 05:00 UTC (1h after close)
- Ops wallet must be funded and key updated before then

## Notes for Tomorrow

1. Get mainnet `DEPLOYER_PK` into `.env` and fund ops wallet on Base mainnet
2. LP seeding + Unicrypt lock (Treasury Safe)
3. setSplit call (Founder Safe)
4. Basescan verification + dashboard update
