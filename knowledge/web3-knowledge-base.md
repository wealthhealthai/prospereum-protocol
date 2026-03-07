# Web3 & Tokenomics Knowledge Base
_Last updated: 2026-03-06_
_Built by: SCOUT + Kin (Prospereum)_

---

## 1. Tokenomics Design

### 1.1 Emission Schedules

**Linear Emission:** Fixed number of tokens minted per block/epoch. Simple to model. Risk: inflation rate doesn't respond to demand. Example: early Synthetix SNX inflation.

**Exponential Decay:** Emission halves at intervals (Bitcoin halving model). Creates predictable scarcity. Rate = R₀ × (1 - d)^t where d is decay rate. CRV uses ~16% annual decay: started at 274M CRV/year in 2020, decreasing each year.

**Epoch-Based:** Tokens allocated per epoch (weekly, monthly). Protocol calculates reward pool at epoch close based on activity. Prosperm uses 7-day epochs. Key risk: epoch sandwiching — actors flood activity at epoch close to maximize reward share, then exit.

**Bonding Curves:** Price = f(supply). Bancor-style. Token price increases deterministically with supply. Used for continuous token models. Not typical for fixed-supply protocols.

**Scarcity Functions:** As emission reserve depletes, mint rate tightens. Example pattern:
```
remainingRatio = emissionReserveBalance / EMISSION_RESERVE_MAX
emissionBudget = baseRate × remainingRatio^k   // k > 1 for convex tightening
```
This creates a feedback loop: early adopters get more tokens per dollar of activity; late adopters get fewer. Drives early participation incentives.

### 1.2 Supply Mechanics

**Fixed Cap (Deflationary):** Total supply immutable. Bitcoin: 21M. PSRE: 21M. Scarcity is structural — no inflation possible after cap. Requires burn or lockup mechanisms to reduce circulating supply.

**Burn Mechanisms:** EIP-1559 burns ETH base fee. Buyback-and-burn (GMX: 27% of fees used to buy back GMX). Creates deflationary pressure proportional to protocol revenue.

**Inflationary (Governance-Controlled):** AAVE, early UNI — governance can vote to inflate. Risk: voter apathy leads to treasury raids. Best practice: hard cap on annual inflation rate in code.

**Vesting:** Team/investor tokens locked with cliff + linear vest. Standard: 1-year cliff, 3-4 year linear. PSRE: 1yr cliff, 4yr linear for team (4.2M tokens = 20% of supply). Cliff prevents immediate dump at TGE.

### 1.3 Token Distribution Best Practices

**Red Flags:**
- >40% to team/investors with short vests (<1yr)
- No lockup for advisor tokens
- Treasury controlled by single multisig without timelock
- FDV >> market cap at launch (massive unlock overhang)

**Best Practice Distribution (reference):**
- Community/emissions: 60%+
- Team: ≤20%, 4yr vest
- Treasury/liquidity: 15-20%, controlled by DAO or timelock
- No presale/ICO/private sale = cleaner token distribution

**PSRE Distribution:**
- 60% emission reserve (12.6M) — behavioral mining, NOT minted at genesis
- 20% team (4.2M) — 1yr cliff, 4yr vest
- 20% treasury/liquidity (4.2M) — minted at genesis

### 1.4 Protocol Precedents

**CRV (Curve Finance):**
- Total supply: 3.03B CRV
- 62% to community LPs, 30% to team/investors (2-4yr vest), 5% reserve, 3% employees
- Initial release: ~2M CRV/day at launch
- Decay: ~16% per year
- veCRV: lock CRV for up to 4 years → voting power + fee share + up to 2.5x boost
- Key mechanic: gauge weight votes direct emissions to pools — creates "Curve Wars" bribe ecosystem
- Protocol fee: 50% of trading fees → veCRV holders (as 3CRV)
- Source: https://resources.curve.finance/crv-token/overview/

**GMX:**
- Token: GMX (governance + fee share) + esGMX (escrowed, vests over 1yr)
- 27% of protocol fees used to buy back GMX on open market
- Staking power accrues continuously (time-weighted)
- GLP: multi-asset liquidity pool that earns 70% of fees
- Real yield model: fees come from actual trading, not inflation
- Arbitrum: 0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a
- Source: https://docs.gmx.io/docs/tokenomics/gmx-token/

**SNX (Synthetix):**
- Staking SNX collateralizes synthetic assets (Synths)
- 600% collateralization ratio (governance-controlled)
- Stakers earn trading fees from Synth exchanges
- Voting power proportional to staked SNX (Spartan Council elections)
- Real yield: fees from protocol activity, not pure inflation

**UNI (Uniswap):**
- Fixed supply: 1B UNI
- 60% community, 21.5% team, 18.5% investors — all with 4yr vest
- Fee switch: governance can vote to allocate trading fees to UNI holders (historically off)
- Governance token primarily — minimal direct yield

**AAVE:**
- Safety Module: AAVE staked as backstop for protocol insolvency events
- stkAAVE earns Safety Incentives (inflationary) + protocol fees
- AAVE can be slashed up to 30% in shortfall events
- Hard cap on inflation via governance

**CVX (Convex Finance):**
- Aggregates CRV voting power — "meta-governance" layer
- vlCVX (vote-locked CVX) directs gauge votes across Curve
- Earns portion of Curve fees + CVX emissions
- Bribing: protocols pay vlCVX holders to vote their gauge → creates sustainable bribe market

### 1.5 Behavioral Mining & Epoch Systems

**Proof of Net Economic Contribution (PSRE model):**
- Partners buy PSRE through PartnerVault → buy volume tracked on-chain
- At epoch end: protocol mints up to 10% of partner buy volume as reward
- Reward further capped by scarcity function (tightens as 12.6M reserve depletes)
- No real demand → no new tokens minted
- Partners are DTC brands, not individuals — reduces sybil risk significantly

**Epoch Sandwich Attack:**
- Attacker monitors mempool for epoch finalization tx
- Deposits large amount just before epoch close
- Claims disproportionate reward share
- Exits immediately after
- **Mitigation:** Time-weighted averaging (reward proportional to time-in-epoch, not just balance at snapshot), minimum hold period, or block.timestamp checks on deposits near epoch boundary.

**Wash Trading Prevention:**
- Require buy through protocol vault (not peer-to-peer)
- Track net buy (gross buy minus any redemptions/sells)
- Minimum buy threshold per epoch
- Partner whitelist: only approved entities can create vaults

---

## 2. Smart Contract Architecture

### 2.1 ERC-20 Patterns

**OpenZeppelin Standard:**
```solidity
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract PSRE is ERC20, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    uint256 public constant MAX_SUPPLY = 21_000_000e18;

    constructor() ERC20("Prospereum", "PSRE") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        require(totalSupply() + amount <= MAX_SUPPLY, "Cap exceeded");
        _mint(to, amount);
    }
}
```

**Key patterns:**
- `AccessControl` over `Ownable` for multi-role systems (MINTER_ROLE, PAUSER_ROLE, etc.)
- `Ownable2Step`: requires new owner to accept — prevents accidental ownership loss
- `Pausable`: emergency stop on transfers/mints
- Hard cap enforced in `mint()` — never rely on off-chain checks for supply cap
- Mint-only architecture (no burn in v1) keeps accounting simpler

### 2.2 Soulbound Tokens (EIP-5192)

EIP-5192 = Minimal Soulbound NFTs (Final status). Extends ERC-721.

```solidity
import {ERC5192} from "ERC5192/ERC5192.sol";

contract PartnerNFT is ERC5192 {
    bool private immutable IS_LOCKED = true;

    constructor() ERC5192("PartnerNFT", "PNFT", true) {}

    function safeMint(address to, uint256 tokenId) external {
        _safeMint(to, tokenId);
        emit Locked(tokenId); // EIP-5192 required event
    }
}
// transferFrom will revert — token is permanently bound to address
```

**Install:** `forge install https://github.com/attestate/ERC5192`
**Key:** Override `transferFrom`, `safeTransferFrom` to revert. Emit `Locked(tokenId)` on mint.
**Use case for PSRE:** PartnerNFT — one per entity, non-transferable, maps partnerId to vault.

### 2.3 Clone Factory (EIP-1167 Minimal Proxy)

Deploys minimal bytecode proxy pointing to implementation. Gas savings: ~10x cheaper than full deployment.

**Bytecode:** `363d3d373d3d3d363d73{implementation_address}5af43d82803e903d91602b57fd5bf3`

```solidity
import "@openzeppelin/contracts/proxy/Clones.sol";

contract PartnerVaultFactory {
    address public immutable vaultImplementation;
    mapping(uint256 => address) public partnerVaults;

    constructor(address _impl) {
        vaultImplementation = _impl;
    }

    function createVault(uint256 partnerId) external returns (address vault) {
        vault = Clones.clone(vaultImplementation);
        IPartnerVault(vault).initialize(partnerId, msg.sender);
        partnerVaults[partnerId] = vault;
    }
}
```

**Critical:** Implementation must use `initialize()` not `constructor()`. Use `initializer` modifier (OpenZeppelin Initializable) to prevent re-initialization attacks.

### 2.4 Proxy Upgrade Patterns

**Transparent Proxy:**
- Admin calls → go to ProxyAdmin (upgrade logic)
- Non-admin calls → delegatecall to implementation
- Simpler to reason about, more gas per call (admin check every call)
- Storage: EIP-1967 slots (`_IMPLEMENTATION_SLOT = 0x360894...`)

**UUPS (Universal Upgradeable Proxy Standard):**
- Upgrade logic lives in implementation, not proxy
- Proxy is simpler (cheaper calls)
- OZ recommends UUPS for new projects
- Risk: if implementation loses upgrade function, proxy is permanently stuck
- Must include `_authorizeUpgrade` override with access control

**PSRE recommendation:** For PartnerVault clones — use non-upgradeable (EIP-1167). For RewardEngine — consider UUPS with 48hr timelock on upgrades.

**Storage collision:** Use EIP-1967 storage slots for proxy variables. Never declare state variables in proxy contract that clash with implementation.

### 2.5 Staking & Reward Distribution (MasterChef Pattern)

The canonical reward-per-share accumulator (SushiSwap MasterChef):

```solidity
struct PoolInfo {
    uint256 accRewardPerShare; // accumulated reward per share, scaled 1e12
    uint256 lastRewardBlock;
    uint256 totalStaked;
}

struct UserInfo {
    uint256 amount;      // staked balance
    uint256 rewardDebt;  // already-accounted rewards
}

// On deposit/withdraw, update pool first:
function _updatePool(PoolInfo storage pool) internal {
    if (block.number <= pool.lastRewardBlock) return;
    if (pool.totalStaked == 0) {
        pool.lastRewardBlock = block.number;
        return;
    }
    uint256 blocks = block.number - pool.lastRewardBlock;
    uint256 reward = blocks * rewardPerBlock;
    pool.accRewardPerShare += reward * 1e12 / pool.totalStaked;
    pool.lastRewardBlock = block.number;
}

// Pending rewards for user:
function pendingReward(address user) public view returns (uint256) {
    return userInfo[user].amount * pool.accRewardPerShare / 1e12
           - userInfo[user].rewardDebt;
}

// On deposit:
userInfo[user].rewardDebt = userInfo[user].amount * pool.accRewardPerShare / 1e12;
```

**Why this works:** `rewardDebt` captures the baseline at deposit time. Pending = (current accRewardPerShare × stake) - debt. O(1) gas regardless of how many users.

**Pull vs Push:**
- Pull: user calls `claim()` — safer, no reentrancy from push callbacks
- Push: protocol pushes rewards to users — gas-inefficient at scale, reentrancy risk
- **Use pull-based for PSRE StakingVault**

### 2.6 Access Control

```solidity
// Hierarchy for PSRE:
bytes32 public constant ADMIN_ROLE = DEFAULT_ADMIN_ROLE;
bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
bytes32 public constant EPOCH_FINALIZER_ROLE = keccak256("EPOCH_FINALIZER_ROLE");
bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

// RewardEngine gets MINTER_ROLE on PSRE token
// Keeper/bot gets EPOCH_FINALIZER_ROLE on RewardEngine
// Multisig (Gnosis Safe) holds ADMIN_ROLE
```

**Ownable2Step** for single-admin contracts:
```solidity
function transferOwnership(address newOwner) public override onlyOwner {
    _pendingOwner = newOwner;
}
function acceptOwnership() public {
    require(msg.sender == _pendingOwner);
    _transferOwnership(msg.sender);
}
```

---

## 3. Web3 Security

### 3.1 Attack Vectors

**Reentrancy (most common critical):**
- Single-function: withdraw() sends ETH before updating balance → attacker fallback re-enters
- Cross-function: function A calls external, attacker re-enters function B (different storage slot)
- Read-only reentrancy: view function called during reentrancy returns stale state (used to manipulate oracle)

**Checks-Effects-Interactions (CEI) Pattern:**
```solidity
// WRONG:
function withdraw(uint256 amount) external {
    require(balances[msg.sender] >= amount);
    (bool ok,) = msg.sender.call{value: amount}(""); // INTERACTION before EFFECT
    balances[msg.sender] -= amount; // EFFECT after — reentrancy possible
}

// CORRECT:
function withdraw(uint256 amount) external {
    require(balances[msg.sender] >= amount); // CHECK
    balances[msg.sender] -= amount;           // EFFECT
    (bool ok,) = msg.sender.call{value: amount}(""); // INTERACTION last
}
```

**Flash Loan Attacks:**
- Borrow massive amount in single tx with no collateral
- Manipulate on-chain price oracle (spot price)
- Exploit protocol at manipulated price
- Repay loan
- **Mitigation:** Use TWAP oracles (Uniswap v3 TWAP, Chainlink), not spot prices. Require minimum hold periods.

**Oracle Manipulation:**
- Spot price from Uniswap v2/v3 easily manipulated in single block
- Use Chainlink (off-chain aggregated) or Uniswap v3 TWAP (time-weighted)
- TWAP over 30min window costs attacker millions to manipulate

**Integer Overflow/Underflow:**
- Solidity 0.8.x: built-in overflow protection (reverts on overflow)
- Solidity <0.8: use SafeMath or unchecked arithmetic carefully
- **Always use Solidity 0.8.x for new contracts**

**Front-Running (MEV):**
- Attacker sees pending tx in mempool, submits with higher gas
- Sandwich attack: buy before target, sell after
- Mitigation: commit-reveal schemes, slippage tolerance, private mempools (Flashbots Protect)

**Access Control Exploits:**
- Missing `onlyOwner` / `onlyRole` on sensitive functions
- Uninitialized proxies (attacker calls initialize() on uninitialized clone)
- `tx.origin` instead of `msg.sender` (phishing)
- **Always use `msg.sender`, never `tx.origin`**

**Signature Replay:**
- Same signed message accepted multiple times
- Mitigation: include nonce + chainId in signed payload (EIP-712)

### 3.2 Real Exploits & Post-Mortems

**The DAO Hack (2016) — $60M ETH:**
- Reentrancy on `splitDAO()` → attacker drained child DAO before balance update
- Led to Ethereum hard fork (ETH/ETC split)
- The canonical reentrancy example

**Poly Network (2021) — $611M:**
- Access control exploit: `_executeCrossChainTx` didn't validate callee
- Attacker passed EthCrossChainManager as callee, called `putCurEpochConPubKeyBytes`
- Replaced keeper public key with attacker's own — took full control
- Funds eventually returned

**Ronin Bridge (2022) — $625M:**
- 5 of 9 validator keys compromised (4 Axie Infinity + 1 Sky Mavis)
- Social engineering + Sky Mavis DAO approval misuse
- Not a smart contract bug — operational security failure
- **Lesson:** Multi-sig security is only as strong as key management

**Euler Finance (March 2023) — $197M:**
- Missing health check on `donateToReserves()` function
- Combined with flash loan + self-liquidation
- Attack: borrow → leverage up → donate to reserves → become insolvent → self-liquidate at discount → profit
- Root cause: new function added without full invariant analysis
- Funds eventually returned after on-chain negotiation

**Curve Finance Vyper Reentrancy (July 2023) — ~$70M across multiple pools:**
- Vyper compiler bug in versions 0.2.15, 0.2.16, 0.3.0
- Cross-function reentrancy: `add_liquidity` and `remove_liquidity` used separate storage slots for reentrancy locks (should be shared)
- Affected pools: Alchemix, JPEG'd, MetronomeDAO, CRV/ETH
- Loss: ~$52M confirmed at time
- **Lesson:** Compiler bugs exist. Audit at bytecode level for critical contracts. Stick to well-audited compiler versions.

### 3.3 Defensive Patterns

**ReentrancyGuard (OpenZeppelin):**
```solidity
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract StakingVault is ReentrancyGuard {
    function withdraw(uint256 amount) external nonReentrant {
        // safe
    }
}
```

**Timelock for Governance:**
```solidity
// All admin actions delayed by MIN_DELAY (e.g., 48 hours)
// Users can exit before malicious upgrade takes effect
// OpenZeppelin TimelockController: standard implementation
```

**Emergency Pause:**
```solidity
import "@openzeppelin/contracts/security/Pausable.sol";

function pause() external onlyRole(PAUSER_ROLE) { _pause(); }
function unpause() external onlyRole(ADMIN_ROLE) { _unpause(); }

function deposit(uint256 amount) external whenNotPaused { ... }
```

**Pull Payment Pattern:**
```solidity
mapping(address => uint256) public pendingWithdrawals;

function claim() external nonReentrant {
    uint256 amount = pendingWithdrawals[msg.sender];
    pendingWithdrawals[msg.sender] = 0; // effect before interaction
    token.transfer(msg.sender, amount);
}
```

**Gnosis Safe Multi-sig Best Practices:**
- Minimum 3-of-5 for treasury
- Hardware wallets for all signers
- Separate signing devices from daily use
- Test with small amounts before large operations
- Use Timelock as owner of protocol contracts (not Safe directly)

### 3.4 Security Tooling

**Slither (Trail of Bits):**
- Static analysis for Solidity
- Detects: reentrancy, uninitialized vars, incorrect ERC-20, shadowing, tx-origin
- `slither . --print human-summary`
- Run as part of CI

**Mythril:**
- Symbolic execution — finds code paths leading to exploits
- Slower but deeper than Slither
- `myth analyze contracts/PSRE.sol`

**Echidna (Trail of Bits):**
- Property-based fuzzing
- Write invariants: `function echidna_supply_never_exceeds_cap() public returns (bool) { return psre.totalSupply() <= MAX_SUPPLY; }`
- Fuzzer tries to violate invariant

**Foundry Invariant Tests:**
```solidity
function invariant_totalSupplyNeverExceedsCap() public {
    assertLe(psre.totalSupply(), psre.MAX_SUPPLY());
}
```
Run with `forge test --match-test invariant`

**Audit Firms (top tier):**
- Trail of Bits: deepest technical, symbolic execution focus
- OpenZeppelin Audits: standard/best practices focus
- Spearbit: boutique, senior-only auditors
- Sherlock/Code4rena: competitive audit platforms (crowdsourced)

### 3.5 Audit & Multi-sig Governance

**What auditors look for (top findings):**
1. Access control missing or incorrect
2. Reentrancy (especially cross-function)
3. Uninitialized proxies
4. Incorrect math (rounding, precision loss)
5. Missing input validation
6. Centralization risks (single admin key)
7. Front-running opportunities
8. Denial-of-service vectors

**Pre-audit checklist:**
- Full test coverage (>95% line coverage)
- Natspec comments on all public functions
- All TODOs resolved
- No admin keys on EOAs — use multi-sig
- Timelock on all upgrade/param-change functions

---

## 4. Token Market Dynamics

### 4.1 AMM Mechanics & Liquidity

**Uniswap v2 (x*y=k):**
- Constant product formula: x × y = k
- Price of token A = y/x (ratio of reserves)
- Infinite liquidity curve — always a price, but slippage increases with trade size
- LP earns 0.3% of every trade

**Impermanent Loss (IL):**
- If price ratio changes by factor r, IL = 2√r/(1+r) - 1
- Price doubles (r=2): IL = -5.7%
- Price 5x: IL = -25.5%
- Price 10x: IL = -42.5%
- LP only profitable if fee revenue > IL

**Uniswap v3 Concentrated Liquidity:**
- LPs select price range [Pa, Pb]
- Capital deployed only within that range
- ~4000x more efficient for stable pairs (narrow range)
- Out-of-range positions earn zero fees
- Used by: stablecoin pairs, correlated assets
- Source: https://docs.uniswap.org/concepts/protocol/concentrated-liquidity

**Curve (StableSwap):**
- Hybrid constant-sum + constant-product
- Flat price curve near 1:1 for stablecoins
- Much lower IL and slippage for pegged assets
- Better for PSRE/USDC pool if price expected to stay in range

### 4.2 Emission Impact on Price

**Dilution math:**
- New tokens minted = 100,000 PSRE
- Existing circulating = 2,000,000 PSRE
- Dilution = 100,000 / 2,000,000 = 5%
- If demand is constant, price drops ~5%
- In practice: emission drives sell pressure, but also incentivizes activity that creates buy pressure

**Key ratio:** Protocol Revenue / Emission Value
- If protocol generates more buy pressure (partner buys) than emission sell pressure → net positive
- PSRE design: emissions are capped at 10% of partner buys → by construction, buy pressure ≥ 10x emission pressure

**FDV vs Market Cap:**
- Market Cap = price × circulating supply
- FDV = price × total supply (including unlocked/unvested)
- FDV >> Market Cap signals massive unlock overhang — red flag for investors
- Example: token at $10 with 1M circulating, 100M total = $10M mktcap / $1B FDV
- Investors tracking FDV: they price in future dilution

### 4.3 Buy/Sell Pressure Mechanics

**Buy pressure sources:**
- Protocol utility (must buy to use = constant demand)
- Staking yields (APR attracts capital)
- Governance value (voting rights worth paying for — veToken model)
- LP incentives (earn more by providing liquidity)
- Speculative demand (narrative, momentum)

**Sell pressure sources:**
- Team/investor unlocks (calendar events → predictable dumps)
- Emission recipients selling rewards
- LP impermanent loss rebalancing
- Treasury diversification

**Mitigation strategies:**
- Vesting: slows team/investor selling
- Escrowed tokens (esGMX model): rewards vest over 1yr → reduces immediate sell pressure
- Staking lockups: lock tokens to earn yield → reduces circulating supply
- Burn mechanisms: reduces supply permanently
- Utility sinks: tokens consumed by protocol use (fees burned)

### 4.4 Protocol-Owned Liquidity (POL) vs Rented Liquidity

**Rented Liquidity (Liquidity Mining):**
- Protocol emits tokens to attract LPs
- LPs leave when emissions drop ("mercenary capital")
- Creates predictable dump when rewards end
- Example: most early DeFi protocols

**Protocol-Owned Liquidity (Olympus DAO model):**
- Protocol sells discounted tokens (5-10%) in exchange for LP tokens
- Protocol owns the LP position permanently
- No mercenary exit risk
- OHM bond mechanism: user gives DAI-OHM LP → receives OHM at discount after 5-day vest
- Risk: reflexivity — OHM value partly backed by OHM itself

**Curve Bribe Ecosystem:**
- Protocols pay vlCVX holders to vote gauge weight
- Creates sustainable (non-inflationary) way to attract liquidity
- Cost: ~$0.05-0.10 per $1 of CRV emissions directed

**PSRE recommendation:** Seed treasury/team liquidity as POL at launch. Use treasury allocation (4.2M) for initial liquidity provision. Avoid heavy liquidity mining emissions — they create sell pressure.

### 4.5 DTC Brand Token Precedents

**Starbucks Odyssey (2022-2024):**
- NFT-based loyalty on Polygon
- "Journey Stamps" = NFTs earned by completing activities
- Tradeable on secondary market
- Discontinued March 2024 — partner (Forum3) relationship ended
- **Lesson:** Web2 brand → Web3 loyalty requires committed infrastructure partner

**Nike .Swoosh:**
- Virtual wearables as NFTs
- Polygon-based
- Integration with physical products (token-gated)
- Revenue share with creators
- More sustainable model: tied to product purchases

**Reddit Collectible Avatars:**
- 10M+ wallets onboarded (largest Web3 consumer adoption)
- Polygon, low-cost
- Users don't even know it's blockchain
- Key insight: hide the blockchain, show the value

**Air Miles / Loyalty Points (Web2 precedent):**
- Programs work because: earn miles → aspirational reward → behavior change
- PSRE equivalent: earn PSRE → redeem for rewards → brand ecosystem lock-in
- Web3 advantage: interoperability, secondary market, user ownership

---

## 5. Behavioral Mining & Proof of Contribution

### 5.1 Proof-of-X Taxonomy

| Mechanism | What's Proven | Example |
|-----------|--------------|---------|
| Proof of Work | Computational effort | Bitcoin |
| Proof of Stake | Token holding | Ethereum, AAVE |
| Proof of Liquidity | LP provision | Tokemak |
| Proof of Burn | Token destruction | Counterparty (XCP) |
| Proof of Importance | Network activity score | NEM |
| Proof of Net Economic Contribution | Real buy volume | PSRE |

**Proof of Importance (NEM):**
- Score = f(staked balance, transaction history, network centrality)
- Rewards harvesters proportional to importance score
- Multi-factor: prevents pure stake concentration

**PSRE's Proof of Net Economic Contribution:**
- Partners buy PSRE through vault → buy volume recorded
- Net buy = gross buy - any returns/exits (v1: no sell, so cumBuy monotonically increases)
- Epoch reward proportional to partner's buy share of total epoch volume

### 5.2 Real Yield vs Inflationary Yield

**Inflationary Yield:**
- Rewards paid in newly minted tokens
- APR looks attractive but masks dilution
- Ponzi-adjacent: early stakers paid by later stakers' dilution
- Sustainable only if token has demand to absorb inflation

**Real Yield:**
- Rewards paid from actual protocol revenue (fees, spreads)
- GMX: 27% of trading/swap/borrow fees → GMX stakers (paid in ETH/AVAX)
- Synthetix: trading fees from Synths → SNX stakers
- Curve: 50% of swap fees → veCRV holders
- Sustainable: protocol must generate revenue > reward outflow
- **PSRE is partially real yield:** partner buys create actual demand; emissions are bounded by that demand

### 5.3 Anti-Gaming & Sybil Resistance

**Sybil Attack on Behavioral Mining:**
- Create 1000 wallets, each performs minimum activity
- Claim 1000× rewards vs legitimate single wallet
- Attack vector: if reward > cost of gas + minimum activity

**Mitigations:**
1. **Economic barriers:** Minimum buy threshold per epoch (e.g., $100 minimum buy to qualify)
2. **Whitelist gating:** Only approved partners (KYC'd entities) can create vaults
3. **Time-weighted averaging:** Reward based on time-weighted buy volume, not just epoch-end snapshot
4. **Non-transferable partner NFT:** 1 PartnerNFT per legal entity — prevents farm splitting
5. **Vault ↔ partner binding:** Each vault maps to exactly one PartnerNFT; can't create multiple vaults per partner

**For PSRE specifically:**
- Partners are DTC brands (legal entities) — not anonymous wallets
- PartnerNFT is non-transferable (EIP-5192) and permissionlessly mintable but 1-per-entity by design
- Wash trading: partner buying their own PSRE through vault = they're providing real capital, which is fine (they get it back as rewards + staking yield)

**Wash Trading Detection (if needed in v2):**
- Track buy-then-immediate-sell patterns
- Require minimum hold of purchased PSRE before epoch reward credited
- On-chain: check that PSRE bought through vault wasn't sold before epoch close

### 5.4 Partner Vault Accounting Patterns

**CumBuy Tracking (PSRE v1 design):**
```solidity
contract PartnerVault {
    uint256 public cumBuy;       // cumulative PSRE purchased through vault
    uint256 public epochBuyStart; // cumBuy at start of current epoch
    uint256 public partnerId;

    function buy(uint256 psreAmount) external {
        // Transfer USDC/ETH in, execute swap to PSRE
        // Record buy
        cumBuy += psreAmount;
        emit Buy(partnerId, psreAmount, block.timestamp);
    }

    function epochBuyVolume() external view returns (uint256) {
        return cumBuy - epochBuyStart;
    }
}

contract RewardEngine {
    mapping(uint256 => uint256) public partnerEpochBuy; // partnerId => epoch buy volume
    uint256 public totalEpochBuy;

    function finalizeEpoch() external onlyRole(EPOCH_FINALIZER_ROLE) {
        // snapshot all registered vaults
        // calculate each partner's share
        // mint rewards proportional to share, capped by scarcity function
        uint256 emissionBudget = calculateEmissionBudget();
        for each partner:
            reward = emissionBudget * partnerShare / totalEpochBuy
            psre.mint(partnerVault, reward)
        // reset epoch baselines
    }

    function calculateEmissionBudget() internal view returns (uint256) {
        uint256 remaining = emissionReserve.balanceOf(address(this));
        uint256 remainingRatio = remaining * 1e18 / EMISSION_RESERVE_MAX;
        uint256 baseReward = totalEpochBuy * BASE_REWARD_RATE / 1e18; // 10% of buys
        return baseReward * remainingRatio / 1e18; // scarcity tightening
    }
}
```

**Key invariants to test:**
- `cumBuy` can only increase (monotonic)
- Epoch reward never exceeds emission reserve balance
- Sum of all partner rewards == total minted in epoch
- Total minted never exceeds MAX_SUPPLY

---

## 6. Key References

### Documentation
- OpenZeppelin Contracts: https://docs.openzeppelin.com/contracts/
- OpenZeppelin Access Control: https://docs.openzeppelin.com/contracts/3.x/access-control
- EIP-1167 (Minimal Proxy): https://eips.ethereum.org/EIPS/eip-1167
- EIP-5192 (Soulbound): https://eips.ethereum.org/EIPS/eip-5192
- ERC-5192 Reference Impl: https://github.com/attestate/ERC5192
- Uniswap v3 Concentrated Liquidity: https://docs.uniswap.org/concepts/protocol/concentrated-liquidity
- Curve CRV Tokenomics: https://resources.curve.finance/crv-token/overview/
- GMX Tokenomics: https://docs.gmx.io/docs/tokenomics/gmx-token/

### Security Resources
- Cyfrin Reentrancy Guide: https://www.cyfrin.io/blog/what-is-a-reentrancy-attack-solidity-smart-contracts
- Euler Finance Hack Analysis: https://www.cyfrin.io/blog/how-did-the-euler-finance-hack-happen-hack-analysis
- Curve Vyper Reentrancy: https://medium.com/@zan.top/analysis-of-the-curve-reentrancy-attack-caused-by-a-vulnerability-in-the-vyper-compiler-72e89b056f93
- Sybil Resistance (Cyfrin): https://www.cyfrin.io/blog/understanding-sybil-attacks-in-blockchain-and-smart-contracts

### Staking Patterns
- MasterChef Staking Algorithm: https://dev.to/heymarkkop/understanding-sushiswaps-masterchef-staking-rewards-1m6f
- RareSkills Staking Algorithm: https://rareskills.io/post/staking-algorithm

### Protocol Analysis
- Olympus DAO POL: https://olympusdao.medium.com/a-primer-on-oly-bonds-9763f125c124
- Protocol Owned Liquidity (IQ.wiki): https://iq.wiki/wiki/pol-protocol-owned-liquidity
- GMX Tokenomics 101: https://content.forgd.com/p/tokenomics-101-gmx

### GitHub Repos
- OpenZeppelin Contracts: https://github.com/OpenZeppelin/openzeppelin-contracts
- ERC-5192 Reference: https://github.com/attestate/ERC5192
- SushiSwap MasterChef: https://github.com/sushiswap/sushiswap/blob/master/contracts/MasterChef.sol
- Euler Finance PoC: https://github.com/ciaranightingale/euler
