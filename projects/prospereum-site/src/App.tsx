import { useRef, useState } from "react";
import { BrowserRouter, Routes, Route, Link } from "react-router-dom";
import { motion, useInView } from "framer-motion";
import { FuturisticHero } from "./components/FuturisticHero";
import { Protocol } from "./pages/Protocol";
import logoSrc from "./assets/logo.png";
import "./index.css";

// ─── Motion variants ────────────────────────────────────────────────────────
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

// ─── Section wrapper with scroll trigger ────────────────────────────────────
function Section({ id, children, className = "" }: { id?: string; children: React.ReactNode; className?: string }) {
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

// ─── Nav ─────────────────────────────────────────────────────────────────────
function Nav() {
  const [open, setOpen] = useState(false);
  const navLinks = [
    { label: "How It Works", to: "/#how-it-works", internal: true },
    { label: "Protocol", to: "/protocol", internal: true },
    { label: "Whitepaper", to: "#", internal: false },
  ];

  return (
    <>
      <nav className="fixed top-0 left-0 right-0 z-[100] flex items-center justify-between px-5 py-4 backdrop-blur-md bg-[#0C0C0E]/80 border-b border-[rgba(212,175,55,0.10)]">
        {/* Logo */}
        <Link to="/" className="flex items-center gap-2" onClick={() => setOpen(false)}>
          <img src={logoSrc} alt="Prospereum" className="h-7 w-auto" />
        </Link>

        {/* Desktop links */}
        <div className="hidden md:flex items-center gap-8">
          {navLinks.map((l) =>
            l.internal ? (
              <Link key={l.label} to={l.to} className="text-sm font-medium text-[rgba(242,237,232,0.65)] hover:text-[#F2EDE8] transition-colors">
                {l.label}
              </Link>
            ) : (
              <a key={l.label} href={l.to} className="text-sm font-medium text-[rgba(242,237,232,0.65)] hover:text-[#F2EDE8] transition-colors">
                {l.label}
              </a>
            )
          )}
        </div>

        {/* Desktop CTA */}
        <a href="#" className="hidden md:inline-flex items-center px-5 py-2 rounded-full text-sm font-semibold bg-[#D4AF37] text-[#0C0C0E] hover:bg-[#B8962E] transition-colors">
          Read Whitepaper
        </a>

        {/* Mobile hamburger */}
        <button
          className="md:hidden flex flex-col justify-center gap-[5px] w-8 h-8 cursor-pointer"
          onClick={() => setOpen(!open)}
          aria-label="Menu"
        >
          <span className={`block h-[2px] bg-[#F2EDE8] transition-all duration-300 ${open ? "rotate-45 translate-y-[7px]" : ""}`} />
          <span className={`block h-[2px] bg-[#F2EDE8] transition-all duration-300 ${open ? "opacity-0" : ""}`} />
          <span className={`block h-[2px] bg-[#F2EDE8] transition-all duration-300 ${open ? "-rotate-45 -translate-y-[7px]" : ""}`} />
        </button>
      </nav>

      {/* Mobile drawer */}
      {open && (
        <div className="fixed inset-0 z-[99] md:hidden" onClick={() => setOpen(false)}>
          <div
            className="absolute top-[61px] left-0 right-0 bg-[#0C0C0E]/95 backdrop-blur-xl border-b border-[rgba(212,175,55,0.12)] px-6 py-6 flex flex-col gap-5"
            onClick={(e) => e.stopPropagation()}
          >
            {navLinks.map((l) =>
              l.internal ? (
                <Link key={l.label} to={l.to} className="text-base font-medium text-[#F2EDE8]" onClick={() => setOpen(false)}>
                  {l.label}
                </Link>
              ) : (
                <a key={l.label} href={l.to} className="text-base font-medium text-[#F2EDE8]" onClick={() => setOpen(false)}>
                  {l.label}
                </a>
              )
            )}
            <a href="#" className="mt-2 inline-flex justify-center items-center px-6 py-3 rounded-full font-semibold bg-[#D4AF37] text-[#0C0C0E] text-sm">
              Read Whitepaper
            </a>
          </div>
        </div>
      )}
    </>
  );
}

// ─── HowItWorks ──────────────────────────────────────────────────────────────
const STEPS = [
  {
    num: "01",
    title: "Register a Vault",
    body: "DTC brands deploy a PartnerVault on Base. The vault address becomes their permanent protocol identity.",
  },
  {
    num: "02",
    title: "Buy PSRE",
    body: "Vaults execute PSRE buys through Uniswap v3. Every buy is proof of real economic demand.",
  },
  {
    num: "03",
    title: "Earn Rewards",
    body: "The RewardEngine scores each vault's buying activity each epoch and mints proportional PSRE rewards.",
  },
  {
    num: "04",
    title: "Distribute",
    body: "Partners distribute earned PSRE to their customers as loyalty rewards, closing the behavioral loop.",
  },
];

function HowItWorks() {
  return (
    <Section id="how-it-works">
      <div className="max-w-5xl mx-auto">
        <motion.p variants={fadeUp} className="text-xs font-semibold tracking-[0.2em] text-[#D4AF37] uppercase mb-3">
          The Protocol
        </motion.p>
        <motion.h2 variants={fadeUp} className="font-display text-4xl md:text-5xl font-bold text-[#F2EDE8] mb-14">
          How It Works
        </motion.h2>

        <motion.div
          variants={stagger}
          className="grid grid-cols-1 md:grid-cols-4 gap-px bg-[rgba(212,175,55,0.05)] rounded-2xl overflow-hidden border border-[rgba(212,175,55,0.10)]"
        >
          {STEPS.map((step) => (
            <motion.div
              key={step.num}
              variants={fadeUp}
              className="bg-[#0C0C0E] p-5 md:p-8 flex flex-col gap-3 hover:bg-[#131316] transition-colors"
            >
              <span className="font-display text-5xl font-extrabold text-[#D4AF37] opacity-40">
                {step.num}
              </span>
              <h3 className="font-display text-lg font-bold text-[#F2EDE8]">{step.title}</h3>
              <p className="text-sm leading-relaxed text-[rgba(242,237,232,0.6)]">{step.body}</p>
            </motion.div>
          ))}
        </motion.div>
      </div>
    </Section>
  );
}

// ─── Protocol Stats ───────────────────────────────────────────────────────────
const STATS = [
  { value: "21M", label: "Total PSRE Supply" },
  { value: "7 Days", label: "Epoch Duration" },
  { value: "3", label: "Partner Tiers" },
  { value: "Base", label: "Network" },
];

function ProtocolStats() {
  return (
    <Section id="protocol" className="bg-[#0C0C0E]">
      <div className="max-w-5xl mx-auto">
        <motion.p variants={fadeUp} className="text-xs font-semibold tracking-[0.2em] text-[#D4AF37] uppercase mb-3">
          By the Numbers
        </motion.p>
        <motion.h2 variants={fadeUp} className="font-display text-4xl md:text-5xl font-bold text-[#F2EDE8] mb-14">
          Protocol
        </motion.h2>

        <motion.div variants={stagger} className="grid grid-cols-2 md:grid-cols-4 gap-6">
          {STATS.map((stat) => (
            <motion.div
              key={stat.label}
              variants={fadeUp}
              className="bg-[#131316] border border-[rgba(212,175,55,0.15)] rounded-2xl p-7 flex flex-col gap-2 hover:border-[rgba(212,175,55,0.30)] transition-colors"
            >
              <span className="font-display text-5xl font-extrabold text-[#D4AF37]">{stat.value}</span>
              <span className="text-sm text-[rgba(242,237,232,0.55)] font-medium">{stat.label}</span>
            </motion.div>
          ))}
        </motion.div>
      </div>
    </Section>
  );
}

// ─── Tiers ────────────────────────────────────────────────────────────────────
const TIERS = [
  {
    name: "Bronze",
    rate: "8%",
    label: "base reward rate",
    multiplier: null,
    desc: "Entry level. Begin earning from epoch one.",
    accent: "#CD7F32",
  },
  {
    name: "Silver",
    rate: "10%",
    label: "base reward rate",
    multiplier: "1.25× tier multiplier",
    desc: "Sustained activity. Unlock enhanced scoring.",
    accent: "#C0C0C0",
  },
  {
    name: "Gold",
    rate: "12%",
    label: "base reward rate",
    multiplier: "1.5× tier multiplier",
    desc: "Top performers. Maximum protocol rewards.",
    accent: "#D4AF37",
  },
];

function Tiers() {
  return (
    <Section id="tiers">
      <div className="max-w-5xl mx-auto">
        <motion.p variants={fadeUp} className="text-xs font-semibold tracking-[0.2em] text-[#D4AF37] uppercase mb-3">
          Partner Program
        </motion.p>
        <motion.h2 variants={fadeUp} className="font-display text-4xl md:text-5xl font-bold text-[#F2EDE8] mb-14">
          Partner Tiers
        </motion.h2>

        <motion.div variants={stagger} className="grid grid-cols-1 md:grid-cols-3 gap-6">
          {TIERS.map((tier) => (
            <motion.div
              key={tier.name}
              variants={fadeUp}
              className="bg-[#131316] border border-[rgba(212,175,55,0.15)] rounded-2xl p-7 flex flex-col gap-4 hover:border-[rgba(212,175,55,0.30)] transition-colors"
            >
              {/* Tier name with accent color */}
              <div className="flex items-center gap-3">
                <span
                  className="w-3 h-3 rounded-full flex-shrink-0"
                  style={{ background: tier.accent }}
                />
                <span
                  className="font-display text-xl font-bold"
                  style={{ color: tier.accent }}
                >
                  {tier.name}
                </span>
              </div>

              {/* Rate */}
              <div>
                <span className="font-display text-5xl font-extrabold text-[#F2EDE8]">{tier.rate}</span>
                <span className="ml-2 text-sm text-[rgba(242,237,232,0.5)]">{tier.label}</span>
              </div>

              {/* Multiplier badge */}
              {tier.multiplier && (
                <span
                  className="inline-flex w-fit px-3 py-1 rounded-full text-xs font-semibold"
                  style={{
                    background: `${tier.accent}18`,
                    color: tier.accent,
                    border: `1px solid ${tier.accent}40`,
                  }}
                >
                  {tier.multiplier}
                </span>
              )}

              {/* Description */}
              <p className="text-sm leading-relaxed text-[rgba(242,237,232,0.6)]">{tier.desc}</p>
            </motion.div>
          ))}
        </motion.div>
      </div>
    </Section>
  );
}

// ─── CTA ──────────────────────────────────────────────────────────────────────
function CTA() {
  return (
    <Section id="cta" className="bg-[#0C0C0E]">
      <div className="max-w-3xl mx-auto text-center">
        <motion.h2
          variants={fadeUp}
          className="font-display text-4xl md:text-5xl font-bold text-[#F2EDE8] mb-5"
        >
          Ready to mine economic contribution?
        </motion.h2>
        <motion.p
          variants={fadeUp}
          className="text-base md:text-lg text-[rgba(242,237,232,0.6)] leading-relaxed mb-10"
        >
          Deploy your PartnerVault on Base and start earning PSRE rewards for every dollar your customers spend.
        </motion.p>
        <motion.div variants={fadeUp} className="flex flex-wrap justify-center gap-4">
          <a
            href="#partner"
            className="inline-flex items-center px-7 py-3 rounded-full font-semibold bg-[#D4AF37] text-[#0C0C0E] hover:bg-[#B8962E] transition-colors text-sm"
          >
            Become a Partner
          </a>
          <a
            href="#whitepaper"
            className="inline-flex items-center px-7 py-3 rounded-full font-semibold border border-[rgba(212,175,55,0.35)] text-[#D4AF37] hover:bg-[rgba(212,175,55,0.08)] transition-colors text-sm"
          >
            Read Whitepaper
          </a>
        </motion.div>
      </div>
    </Section>
  );
}

// ─── Footer ───────────────────────────────────────────────────────────────────
function Footer() {
  return (
    <footer className="border-t border-[rgba(212,175,55,0.10)] py-10 px-6">
      <div className="max-w-5xl mx-auto flex flex-col md:flex-row items-center justify-between gap-4">
        <div className="flex flex-col md:flex-row items-center gap-2 text-sm text-[rgba(242,237,232,0.45)]">
          <span className="font-display font-semibold text-[#D4AF37]">Prospereum</span>
          <span className="hidden md:inline">·</span>
          <span>by WealthHealth AI</span>
          <span className="hidden md:inline">·</span>
          <span>© 2026 WealthHealth AI Inc.</span>
        </div>
        <div className="flex items-center gap-6 text-sm text-[rgba(242,237,232,0.45)]">
          {["Whitepaper", "GitHub", "Dashboard"].map((link) => (
            <a
              key={link}
              href={`#${link.toLowerCase()}`}
              className="hover:text-[#D4AF37] transition-colors"
            >
              {link}
            </a>
          ))}
        </div>
      </div>
    </footer>
  );
}

// ─── Home Page ────────────────────────────────────────────────────────────────
function HomePage() {
  return (
    <div className="min-h-screen bg-[#0C0C0E] text-[#F2EDE8]">
      <FuturisticHero />
      <HowItWorks />
      <ProtocolStats />
      <Tiers />
      <CTA />
      <Footer />
    </div>
  );
}

// ─── App ──────────────────────────────────────────────────────────────────────
export default function App() {
  return (
    <BrowserRouter>
      <Nav />
      <Routes>
        <Route path="/" element={<HomePage />} />
        <Route path="/protocol" element={<Protocol />} />
      </Routes>
    </BrowserRouter>
  );
}
