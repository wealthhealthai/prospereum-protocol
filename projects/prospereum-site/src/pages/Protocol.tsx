import { useRef } from "react";
import { motion, useInView } from "framer-motion";
import { LiquidMetal, liquidMetalPresets } from "@paper-design/shaders-react";

// ─── Motion variants ─────────────────────────────────────────────────────────
const fadeUp = {
  hidden: { opacity: 0, y: 28 },
  visible: {
    opacity: 1,
    y: 0,
    transition: { duration: 0.6, ease: [0.22, 1, 0.36, 1] as [number, number, number, number] },
  },
};

const stagger = {
  hidden: {},
  visible: { transition: { staggerChildren: 0.12 } },
};

// ─── Scroll-triggered section wrapper ────────────────────────────────────────
function Section({
  id,
  children,
  className = "",
}: {
  id?: string;
  children: React.ReactNode;
  className?: string;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const inView = useInView(ref, { once: true, margin: "-80px" });
  return (
    <motion.section
      id={id}
      ref={ref}
      variants={stagger}
      initial="hidden"
      animate={inView ? "visible" : "hidden"}
      className={`py-24 px-6 ${className}`}
    >
      {children}
    </motion.section>
  );
}

// ─── Hero ─────────────────────────────────────────────────────────────────────
function Hero() {
  return (
    <div className="relative h-screen overflow-hidden bg-black flex items-center justify-center">
      {/* Sphere — liquid metal clipped to a circle by shape:"circle" in the shader */}
      <div
        style={{
          width: "min(92vw, 78vh)",
          height: "min(92vw, 78vh)",
          position: "relative",
          flexShrink: 0,
        }}
      >
        <LiquidMetal
          {...liquidMetalPresets[2].params}
          shape="circle"
          colorBack="#000000"
          scale={0.9}
          worldWidth={900}
          worldHeight={900}
          style={{ width: "100%", height: "100%" }}
        />
      </div>

      {/* Content overlay — mix-blend-mode:difference auto-inverts text against the sphere */}
      <div
        className="absolute inset-0 z-10 flex flex-col items-center justify-center text-center px-6"
        style={{ mixBlendMode: "difference" }}
      >
        <motion.p
          initial={{ opacity: 0, y: 16 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, delay: 0.2 }}
          className="text-xs font-semibold tracking-[0.25em] uppercase text-white mb-4"
        >
          The Protocol
        </motion.p>
        <motion.h1
          initial={{ opacity: 0, y: 24 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.7, delay: 0.35 }}
          className="font-display text-3xl sm:text-4xl md:text-6xl xl:text-7xl font-bold text-white mb-4 leading-tight"
        >
          How Prospereum Works
        </motion.h1>
        <motion.p
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.65, delay: 0.5 }}
          className="text-base md:text-lg text-white max-w-xl leading-relaxed"
        >
          Proof of real economic demand, recorded on-chain, rewarded in PSRE.
        </motion.p>
      </div>

      {/* Scroll indicator */}
      <motion.div
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ duration: 0.8, delay: 1 }}
        className="absolute bottom-8 left-1/2 -translate-x-1/2 z-10 flex flex-col items-center gap-2"
      >
        <span className="text-xs tracking-widest uppercase text-[rgba(242,237,232,0.4)]">
          Scroll
        </span>
        <motion.svg
          animate={{ y: [0, 5, 0] }}
          transition={{ repeat: Infinity, duration: 1.6, ease: "easeInOut" }}
          width="20"
          height="20"
          viewBox="0 0 20 20"
          fill="none"
        >
          <path
            d="M10 4V16"
            stroke="rgba(212,175,55,0.6)"
            strokeWidth="1.5"
            strokeLinecap="round"
          />
          <path
            d="M5 11L10 16L15 11"
            stroke="rgba(212,175,55,0.6)"
            strokeWidth="1.5"
            strokeLinecap="round"
          />
        </motion.svg>
      </motion.div>
    </div>
  );
}

// ─── Simple Explanation ───────────────────────────────────────────────────────
const STEPS = [
  {
    num: 1,
    title: "A brand deploys a vault",
    body: "DTC brands on Prospereum deploy a PartnerVault on Base. This vault address is their permanent protocol identity — no NFT, no account, just an on-chain address.",
  },
  {
    num: 2,
    title: "The vault buys PSRE",
    body: "To earn rewards, vaults execute PSRE purchases through Uniswap v3. Every buy is cryptographically provable demand for the token. There's no gaming it — the protocol only counts real buys.",
  },
  {
    num: 3,
    title: "The RewardEngine scores activity",
    body: "Every 7 days, the RewardEngine snapshots each vault's cumulative buying activity. It calculates a score using an exponential moving average, assigns a tier (Bronze / Silver / Gold), and mints proportional PSRE rewards.",
  },
  {
    num: 4,
    title: "Rewards flow to customers",
    body: "Partners call distribute() to push earned PSRE to their end customers as loyalty rewards. The loop closes: customers spend, brands buy PSRE, rewards flow back to customers.",
  },
];

function SimpleExplanation() {
  return (
    <Section className="bg-[#0C0C0E]">
      <div className="max-w-3xl mx-auto">
        <motion.p
          variants={fadeUp}
          className="text-xs font-semibold tracking-[0.2em] uppercase text-[#D4AF37] mb-3"
        >
          Simple Explanation
        </motion.p>
        <motion.h2
          variants={fadeUp}
          className="font-display text-4xl md:text-5xl font-bold text-[#F2EDE8] mb-14"
        >
          In plain English
        </motion.h2>

        <div className="flex flex-col">
          {STEPS.map((step, idx) => (
            <motion.div key={step.num} variants={fadeUp}>
              <div className="flex gap-6 py-8">
                {/* Numbered circle */}
                <div className="flex-shrink-0 w-10 h-10 rounded-full border border-[#D4AF37] flex items-center justify-center">
                  <span className="font-display text-sm font-bold text-[#D4AF37]">
                    {step.num}
                  </span>
                </div>
                {/* Content */}
                <div>
                  <h3 className="font-display text-lg font-bold text-[#F2EDE8] mb-2">
                    {step.title}
                  </h3>
                  <p className="text-sm leading-relaxed text-[rgba(242,237,232,0.6)]">
                    {step.body}
                  </p>
                </div>
              </div>
              {/* Gold hairline divider — not after last item */}
              {idx < STEPS.length - 1 && (
                <div className="h-px bg-[rgba(212,175,55,0.12)]" />
              )}
            </motion.div>
          ))}
        </div>
      </div>
    </Section>
  );
}

// ─── Protocol Parameters ──────────────────────────────────────────────────────
const PARAMS = [
  { name: "Total PSRE Supply", value: "21,000,000" },
  { name: "Genesis Mint", value: "8,400,000 (40%)" },
  { name: "Emission Reserve", value: "12,600,000 (60%)" },
  { name: "Epoch Duration", value: "7 days" },
  { name: "Base Reward Rate", value: "8% Bronze / 10% Silver / 12% Gold" },
  { name: "Tier Multipliers", value: "1.0x / 1.25x / 1.5x" },
  { name: "Scarcity Function", value: "x = T_emitted / S_emission" },
  { name: "Network", value: "Base (EVM)" },
];

// ─── Contract Cards ───────────────────────────────────────────────────────────
const CONTRACTS = [
  {
    name: "PSRE Token",
    tag: "ERC-20 · Immutable",
    body: "21M hard cap · Epoch rate limiter prevents more than the scarcity-adjusted cap from being minted per epoch. MINTER_ROLE gated. Immutable — no proxy, no upgrade path.",
  },
  {
    name: "PartnerVault",
    tag: "Uniswap v3 · Upgradeable",
    body: "buy() executes PSRE purchases with slippage protection · distribute() pushes earned rewards to end users · Two-step updateOwner() for wallet migration without losing vault history.",
  },
  {
    name: "PartnerVaultFactory",
    tag: "EIP-1167 · Clone Factory",
    body: "Deploys gas-efficient PartnerVault proxies · 200 partner cap in v1 · Bidirectional registry: partner address ↔ vault address.",
  },
  {
    name: "RewardEngine",
    tag: "UUPS · Core Epoch Logic",
    body: "EMA-based partner scoring · Scarcity curve adjusts mint cap as supply fills · 48-hour timelock on governance parameter changes · UUPS upgradeable with multisig admin.",
  },
  {
    name: "StakingVault",
    tag: "Time-weighted · Flash-stake Resistant",
    body: "PSRE and LP token staking · Epoch snapshot system · Flash-stake resistant — rewards calculated on time held, not balance at snapshot · 30% of protocol rewards flow to stakers.",
  },
  {
    name: "TeamVesting",
    tag: "Immutable · 4-year Vest",
    body: "4.2M PSRE · 1-year cliff · 4-year linear vest · No governance override · Immutable — cannot be modified after deployment.",
  },
];

function TechnicalArchitecture() {
  return (
    <section className="bg-[#080809] py-24 px-6">
      <div className="max-w-5xl mx-auto">
        {/* Header */}
        <motion.div
          initial="hidden"
          whileInView="visible"
          viewport={{ once: true, margin: "-80px" }}
          variants={stagger}
        >
          <motion.p
            variants={fadeUp}
            className="text-xs font-semibold tracking-[0.2em] uppercase text-[#D4AF37] mb-3"
          >
            For Builders
          </motion.p>
          <motion.h2
            variants={fadeUp}
            className="font-display text-4xl md:text-5xl font-bold text-[#F2EDE8] mb-6"
          >
            Technical Architecture
          </motion.h2>
          <motion.p
            variants={fadeUp}
            className="text-sm md:text-base leading-relaxed text-[rgba(242,237,232,0.6)] max-w-3xl mb-16"
          >
            Prospereum is a set of six immutable and upgradeable smart contracts deployed on Base.
            The protocol is permissionless — any address can deploy a vault, any address can finalize
            an epoch. The team operates a keeper for convenience, not necessity.
          </motion.p>
        </motion.div>

        {/* Protocol Parameters */}
        <motion.div
          initial="hidden"
          whileInView="visible"
          viewport={{ once: true, margin: "-60px" }}
          variants={stagger}
          className="mb-16"
        >
          <motion.h3
            variants={fadeUp}
            className="font-display text-xl font-bold text-[#F2EDE8] mb-6"
          >
            Protocol Parameters
          </motion.h3>
          <motion.div
            variants={fadeUp}
            className="border border-[rgba(212,175,55,0.12)] rounded-2xl overflow-hidden"
          >
            {PARAMS.map((row, idx) => (
              <div
                key={row.name}
                className={`flex flex-col sm:flex-row sm:items-center gap-1 sm:gap-0 px-6 py-4 ${
                  idx < PARAMS.length - 1
                    ? "border-b border-[rgba(212,175,55,0.08)]"
                    : ""
                } ${idx % 2 === 0 ? "bg-[#0C0C0E]" : "bg-[#0f0f11]"}`}
              >
                <span className="text-xs font-semibold text-[#D4AF37] sm:w-56 flex-shrink-0">
                  {row.name}
                </span>
                <span className="font-mono text-sm text-[#F2EDE8]">{row.value}</span>
              </div>
            ))}
          </motion.div>
        </motion.div>

        {/* Contract Cards */}
        <motion.div
          initial="hidden"
          whileInView="visible"
          viewport={{ once: true, margin: "-60px" }}
          variants={stagger}
        >
          <motion.h3
            variants={fadeUp}
            className="font-display text-xl font-bold text-[#F2EDE8] mb-6"
          >
            Contract Architecture
          </motion.h3>
          <motion.div
            variants={stagger}
            className="grid grid-cols-1 md:grid-cols-2 gap-4"
          >
            {CONTRACTS.map((c) => (
              <motion.div
                key={c.name}
                variants={fadeUp}
                className="bg-[#131316] border border-[rgba(212,175,55,0.12)] rounded-2xl p-6 flex flex-col gap-3 hover:border-[rgba(212,175,55,0.3)] transition-colors duration-200"
              >
                <div>
                  <span className="font-display text-base font-bold text-[#D4AF37]">
                    {c.name}
                  </span>
                  <span className="ml-3 text-xs text-[rgba(242,237,232,0.35)] font-medium">
                    {c.tag}
                  </span>
                </div>
                <p className="text-sm leading-relaxed text-[rgba(242,237,232,0.6)]">{c.body}</p>
              </motion.div>
            ))}
          </motion.div>
        </motion.div>
      </div>
    </section>
  );
}

// ─── CTA ──────────────────────────────────────────────────────────────────────
function ProtocolCTA() {
  return (
    <section className="bg-[#0C0C0E] py-24 px-6">
      <motion.div
        initial="hidden"
        whileInView="visible"
        viewport={{ once: true, margin: "-80px" }}
        variants={stagger}
        className="max-w-3xl mx-auto text-center"
      >
        <motion.h2
          variants={fadeUp}
          className="font-display text-3xl md:text-4xl font-bold text-[#F2EDE8] mb-8"
        >
          Dig deeper into the protocol
        </motion.h2>
        <motion.div variants={fadeUp} className="flex flex-wrap justify-center gap-4">
          <a
            href="#"
            className="inline-flex items-center px-7 py-3 rounded-full font-semibold bg-[#D4AF37] text-[#0C0C0E] hover:bg-[#B8962E] transition-colors text-sm"
          >
            Read the full whitepaper
          </a>
          <a
            href="https://github.com/wealthhealthai/prospereum-protocol"
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center px-7 py-3 rounded-full font-semibold border border-[rgba(212,175,55,0.35)] text-[#D4AF37] hover:bg-[rgba(212,175,55,0.08)] transition-colors text-sm"
          >
            View on GitHub
          </a>
        </motion.div>
      </motion.div>
    </section>
  );
}

// ─── Protocol Page ────────────────────────────────────────────────────────────
export function Protocol() {
  return (
    <div className="min-h-screen bg-[#0C0C0E] text-[#F2EDE8]">
      <Hero />
      <SimpleExplanation />
      <TechnicalArchitecture />
      <ProtocolCTA />
    </div>
  );
}
