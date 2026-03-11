import { useState, useEffect, useRef } from "react";

const PASSWORD = "wealthhealth";
const STORAGE_KEY = "psre_unlocked";

interface Props {
  children: React.ReactNode;
}

export function ComingSoon({ children }: Props) {
  const [unlocked, setUnlocked] = useState(false);
  const [input, setInput] = useState("");
  const [error, setError] = useState(false);
  const [shake, setShake] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  // Check localStorage on mount
  useEffect(() => {
    if (localStorage.getItem(STORAGE_KEY) === "1") {
      setUnlocked(true);
    } else {
      setTimeout(() => inputRef.current?.focus(), 400);
    }
  }, []);

  const attempt = () => {
    if (input === PASSWORD) {
      localStorage.setItem(STORAGE_KEY, "1");
      setUnlocked(true);
    } else {
      setError(true);
      setShake(true);
      setInput("");
      setTimeout(() => { setShake(false); setError(false); }, 600);
      inputRef.current?.focus();
    }
  };

  const onKey = (e: React.KeyboardEvent) => {
    if (e.key === "Enter") attempt();
  };

  if (unlocked) return <>{children}</>;

  return (
    <div
      className="min-h-screen flex flex-col items-center justify-center bg-[#0C0C0E] px-6"
      style={{ fontFamily: "'Inter', sans-serif" }}
    >
      {/* Subtle radial glow */}
      <div
        className="pointer-events-none absolute inset-0"
        style={{
          background:
            "radial-gradient(ellipse 60% 50% at 50% 50%, rgba(212,175,55,0.07), transparent)",
        }}
      />

      <div className="relative z-10 flex flex-col items-center text-center max-w-sm w-full">
        {/* Logo / wordmark */}
        <div className="mb-10">
          <p
            className="text-xs font-semibold tracking-[0.25em] uppercase mb-3"
            style={{ color: "rgba(212,175,55,0.6)" }}
          >
            Prospereum
          </p>
          <h1
            className="text-4xl font-bold tracking-tight"
            style={{
              fontFamily: "'Playfair Display', Georgia, serif",
              color: "#F2EDE8",
            }}
          >
            Coming Soon
          </h1>
          <p className="mt-3 text-sm" style={{ color: "rgba(242,237,232,0.4)" }}>
            The protocol is almost ready.
          </p>
        </div>

        {/* Divider */}
        <div
          className="w-px h-10 mb-8"
          style={{ background: "linear-gradient(to bottom, transparent, rgba(212,175,55,0.3), transparent)" }}
        />

        {/* Password box */}
        <div className={`w-full transition-transform ${shake ? "animate-shake" : ""}`}>
          <label
            className="block text-xs font-semibold tracking-[0.15em] uppercase mb-2 text-left"
            style={{ color: "rgba(212,175,55,0.7)" }}
          >
            Team access
          </label>
          <div
            className="flex items-center rounded-xl overflow-hidden"
            style={{
              border: `1px solid ${error ? "rgba(239,68,68,0.5)" : "rgba(212,175,55,0.2)"}`,
              background: "rgba(255,255,255,0.03)",
              transition: "border-color 0.2s",
            }}
          >
            <input
              ref={inputRef}
              type="password"
              value={input}
              onChange={(e) => { setInput(e.target.value); setError(false); }}
              onKeyDown={onKey}
              placeholder="Enter password"
              className="flex-1 bg-transparent px-4 py-3 text-sm outline-none"
              style={{
                color: "#F2EDE8",
                caretColor: "#D4AF37",
              }}
            />
            <button
              onClick={attempt}
              className="px-4 py-3 text-sm font-semibold transition-colors cursor-pointer"
              style={{
                color: "#D4AF37",
                borderLeft: "1px solid rgba(212,175,55,0.15)",
              }}
              onMouseEnter={(e) => (e.currentTarget.style.color = "#F2EDE8")}
              onMouseLeave={(e) => (e.currentTarget.style.color = "#D4AF37")}
            >
              Enter
            </button>
          </div>
          {error && (
            <p className="mt-2 text-xs text-red-400 text-left">
              Incorrect password.
            </p>
          )}
        </div>

        {/* Footer hint */}
        <p className="mt-12 text-xs" style={{ color: "rgba(242,237,232,0.2)" }}>
          Prospereum Protocol &mdash; Base Network
        </p>
      </div>

      <style>{`
        @keyframes shake {
          0%, 100% { transform: translateX(0); }
          20% { transform: translateX(-8px); }
          40% { transform: translateX(8px); }
          60% { transform: translateX(-5px); }
          80% { transform: translateX(5px); }
        }
        .animate-shake { animation: shake 0.4s ease; }
      `}</style>
    </div>
  );
}
