# Prospereum Protocol (PSRE)

**Proof of Prosperity**

Prospereum is a decentralized behavioral mining protocol on [Base](https://base.org) (EVM).

## Overview

Partners (ecommerce brands) purchase PSRE tokens to distribute as customer loyalty rewards. The protocol mints reward emissions based on provable, on-chain economic activity — specifically, the net growth of PSRE held within a partner's registered vault ecosystem.

Key properties:
- **Progressive scarcity** — emission rate decreases asymptotically as total supply approaches the 21M cap
- **Anti-wash-trading** — cumulative high-water-mark (cumS) ratchet prevents reward recycling
- **Anti-inflation** — effectiveCumS deduction excludes minted rewards from future reward calculations
- **Commerce-aligned** — rewards only flow when a partner's ecosystem genuinely grows

## Contracts

| Contract | Description |
|----------|-------------|
| `PSRE.sol` | ERC-20 token, 21M hard cap, MINTER_ROLE gated, immutable |
| `PartnerVaultFactory.sol` | EIP-1167 clone factory, deploys PartnerVaults |
| `PartnerVault.sol` | Per-partner vault — tracks cumS, executes USDC→PSRE swaps via Uniswap v3 |
| `CustomerVault.sol` | Lightweight holding contract deployed by partner for their customers |
| `RewardEngine.sol` | Epoch math, cumS reward formula, EMA tier scoring, scarcity curve. UUPS upgradeable. |
| `StakingVault.sol` | Time-weighted PSRE + LP staking, flash-stake resistant |

## Documentation

- [Whitepaper v3.2](docs/whitepaper-v3.2-DRAFT.md)
- [Developer Spec v3.2](docs/dev-spec-v3.2-DRAFT.md)
- [Deployed Contracts](docs/deployments.md)
- [Protocol Decisions](docs/decisions.md)

## Development

**Prerequisites:** [Foundry](https://book.getfoundry.sh/)

```bash
# Install dependencies
forge install

# Build
forge build

# Test
forge test

# Test with verbosity
forge test -vv
```

## Deployments

See [docs/deployments.md](docs/deployments.md) for all deployed contract addresses.

**Current:** Base Sepolia testnet (v2.3 — v3.2 rebuild in progress)

## License

MIT
