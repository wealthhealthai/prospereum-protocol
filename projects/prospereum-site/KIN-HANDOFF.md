# Prospereum Site — Stack Handoff from Shiro

This doc exists so you don't repeat the debugging I already did. Read it fully before touching any config.

---

## Stack

| Layer | Tool | Version | Notes |
|-------|------|---------|-------|
| Bundler | Vite | 7.x | via `npm create vite@latest` |
| UI | React 19 + TypeScript | — | `react-ts` template |
| Styling | Tailwind v4 | `tailwindcss@latest` + `@tailwindcss/vite` | **No tailwind.config.js** |
| Animation | Framer Motion | latest | use `animate` not `whileInView` to avoid blank sections |
| 3D | Three.js (vanilla) | `three` + `@types/three` | **Do NOT use react-three-fiber** — causes silent white screen |
| Icons | lucide-react | latest | |
| Utils | clsx | latest | |

---

## Scaffold Commands

```bash
cd ~/.openclaw/workspace-kin/projects/prospereum-site
npm create vite@latest . -- --template react-ts
npm install
npm install tailwindcss @tailwindcss/vite framer-motion lucide-react clsx three @types/three
```

---

## Critical Config Files (copy exactly)

### vite.config.ts
```ts
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  plugins: [react(), tailwindcss()],  // ⚠️ react() first, then tailwindcss() — this is the verified working order
  server: { port: 7802 },
})
```

### src/index.css
⚠️ ORDER MATTERS — this is the #1 cause of blank white screens.
Google Fonts `@import` MUST come before `@import "tailwindcss"` or PostCSS throws a silent error.

```css
/* 1. External imports FIRST — verified working pattern from Prometheus */
@import url('https://fonts.googleapis.com/css2?family=Geist:wght@300;400;500;600;700;800;900&display=swap');
/* swap Geist for whatever font Prospereum uses */

/* 2. Tailwind SECOND */
@import "tailwindcss";

/* 3. Custom globals after */
* { box-sizing: border-box; }

body {
  font-family: 'Geist', -apple-system, sans-serif;
  background: #YOUR_BG;
  color: #YOUR_TEXT;
  -webkit-font-smoothing: antialiased;
  overflow-x: hidden;
}
```
Note: no need for `html, body, #root { height: 100% }` — leave that out unless a specific component needs full viewport height (set it per-component with `min-h-screen` instead).

### src/main.tsx
Standard — no changes needed from Vite template default.

---

## 3D Animation — The Right Pattern

**Use vanilla Three.js in a `useEffect` with a canvas `ref`.** React Three Fiber (`@react-three/fiber`) causes silent crashes that blank the entire page with no console error.

```tsx
import { useEffect, useRef } from "react";
import * as THREE from "three";

export function MyThreeScene() {
  const mountRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const el = mountRef.current;
    if (!el) return;

    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(55, el.clientWidth / el.clientHeight, 0.1, 100);
    camera.position.set(0, 0, 8);

    const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
    renderer.setSize(el.clientWidth, el.clientHeight);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.setClearColor(0x000000, 0); // transparent bg
    el.appendChild(renderer.domElement);

    // ... build your scene ...

    let animId: number;
    const clock = new THREE.Clock();
    function animate() {
      animId = requestAnimationFrame(animate);
      // update objects
      renderer.render(scene, camera);
    }
    animate();

    const onResize = () => {
      camera.aspect = el.clientWidth / el.clientHeight;
      camera.updateProjectionMatrix();
      renderer.setSize(el.clientWidth, el.clientHeight);
    };
    window.addEventListener("resize", onResize);

    // IMPORTANT: always clean up or you'll get ghost canvases on hot reload
    return () => {
      cancelAnimationFrame(animId);
      window.removeEventListener("resize", onResize);
      renderer.dispose();
      if (el.contains(renderer.domElement)) el.removeChild(renderer.domElement);
    };
  }, []);

  return <div ref={mountRef} className="w-full h-full" />;
}
```

---

## Framer Motion — Don't Use whileInView for Hero

If you use `initial={{ opacity: 0 }}` + `whileInView={{ opacity: 1 }}` on sections, they appear blank until the user scrolls. For anything visible above the fold, use `animate` instead:

```tsx
// ✅ Hero — use animate (always visible)
<motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.6 }}>

// ✅ Below fold — whileInView is fine here
<motion.div initial={{ opacity: 0, y: 30 }} whileInView={{ opacity: 1, y: 0 }} viewport={{ once: true }}>
```

---

## Debugging Blank White Screen

In order of likelihood:
1. **CSS import order** — `@import url(...)` must precede `@import "tailwindcss"`
2. **R3F crash** — if using react-three-fiber, switch to vanilla Three.js (see above)
3. **Browser cache** — Cmd+Shift+R (hard refresh) or open in Incognito
4. **Vite HMR stale state** — kill vite, `rm -rf node_modules/.vite`, restart

Check if React is actually mounting:
```js
// In browser DevTools console:
document.getElementById('root')?.innerHTML?.length
// Should be > 0 if React rendered something
```

---

## Running the Dev Server

```bash
npm run dev -- --port 7802
# or put port in vite.config.ts (already done above)
nohup npm run dev > /tmp/vite-7802.log 2>&1 &
```

---

## Design Tooling — How to Find Great Components

### 21st.dev (primary component source)
This is where Shiro sourced the design patterns for Prometheus. Think of it as a curated library of production-quality React/Tailwind components — much higher quality than generic UI kits.

- **URL:** https://21st.dev/community/components
- **Best categories for a landing page:**
  - `Heroes` — sorted by Most Bookmarked is the best starting point
  - `Backgrounds` — shader animations, beam effects, particle fields
  - `Shaders` — GPU-based visual effects (heavy but stunning)
  - `Texts` — animated headlines, sparkle effects, gradient text
  - `Calls to Action`, `Features`, `Pricing`, `Testimonials`
- **How to use:** Browse, find a component you like, open it, grab the source code. Components are React + Tailwind — drop them straight into `src/components/`.
- **Sort tip:** "Most Bookmarked" surfaces the community-validated best work. "Newest" for cutting-edge stuff.

### UI/UX Pro Max skill (design intelligence CLI)
A design intelligence skill that gives you access to a searchable database of UI patterns, styles, typography, color systems, and component recommendations. Think of it as a design advisor you can query from the terminal.

**Install — two options:**

**Option A: npm CLI (easiest)**
```bash
npm install -g uipro-cli
cd ~/.openclaw/workspace-kin/projects/prospereum-site
uipro init --ai openclaw   # generates skill files in current dir
```
If `--ai openclaw` isn't recognized, use `--ai claude` (same file output, just rename the dir).

**Option B: git clone (manual, always works)**
```bash
cd ~/.openclaw/workspace-kin/projects/prospereum-site
git clone --depth 1 https://github.com/nextlevelbuilder/ui-ux-pro-max-skill .uipro
```
Then run scripts directly from `.uipro/src/ui-ux-pro-max/scripts/`.

**Usage (after install):**
```bash
# General component/pattern search
python3 .uipro/src/ui-ux-pro-max/scripts/search.py "dark landing page blockchain"

# Domain-specific searches
python3 .uipro/src/ui-ux-pro-max/scripts/search.py "glassmorphism" --domain style
python3 .uipro/src/ui-ux-pro-max/scripts/search.py "gold accent dark theme" --domain colors
python3 .uipro/src/ui-ux-pro-max/scripts/search.py "serif display heading" --domain typography

# Generate a full design system for the project
python3 .uipro/src/ui-ux-pro-max/scripts/search.py "DeSci protocol token" --design-system -p "Prospereum"

# Stack-specific patterns
python3 .uipro/src/ui-ux-pro-max/scripts/search.py "hero animation" --stack react
```

**What `--design-system` does:** Generates a full structured recommendation — layout pattern, color palette, typography, section order, CTA placement — based on your project description. Run this early to get a design brief before touching code.

**Requires Python 3:** `python3 --version` to confirm. Install via `brew install python3` if needed.

### How to extract code from 21st.dev
1. Open a component page (e.g. `https://21st.dev/community/components/serafimcloud/interactive-3d-hero/default`)
2. You'll see a live preview on the right and a code panel on the left/bottom
3. Click the **"Code"** tab to see the full source
4. Some components have a **"Dependencies"** section — install those first (`npm install <pkg>`)
5. Copy the component into `src/components/YourComponent.tsx` and adjust:
   - Colors → swap hardcoded hex values to match Prospereum's palette
   - Copy/text → replace placeholder strings
   - Sizes → tweak `h-screen`, padding, etc. to fit your layout
6. If a component uses `shadcn/ui` imports (`@/components/ui/...`), you'll need to init shadcn first: `npx shadcn@latest init`. Most 21st.dev components do NOT require this.

### Recommended workflow for Prospereum
1. **Run the design system generator first:**
   ```bash
   python3 .uipro/src/ui-ux-pro-max/scripts/search.py "DeSci protocol token staking dark" --design-system -p "Prospereum"
   ```
   This gives you a design brief: layout pattern, colors, fonts, section order. Use it as your north star.
2. Browse https://21st.dev/community/components?tags=Heroes&sort=most_bookmarked — look for dark/moody hero candidates
3. Also check `Backgrounds` and `Shaders` categories for hero animation options
4. Screenshot 3–4 candidates, pick the one that fits the DeSci/protocol aesthetic
5. Extract code, adapt to Prospereum brand, drop into `src/components/`
6. Use UI/UX Pro Max CLI for typography and color decisions: `--domain colors`, `--domain typography`

---

## Prometheus Reference

Shiro's Prometheus site is a working example of this entire stack:
- **Location:** `~/.openclaw/workspace-shiro/projects/prometheus-site/`
- **Running at:** http://localhost:7801/
- Key files to reference: `src/App.tsx`, `src/components/ProspectNetwork.tsx` (vanilla Three.js 3D), `src/index.css`

You can copy components directly but adjust brand colors — Prometheus uses `#E8510A` (orange) and `#08080F` (near-black). Prospereum will have its own identity.

---

## Notes for Prospereum Specifically

Things to think through before coding:
- **Color palette** — what's the Prospereum brand? (Check whitepaper/dev spec for any color references)
- **3D concept** — Prometheus uses a prospect network graph. Prospereum might suit a molecular/DNA helix, data globe, or protocol node network — something that evokes decentralized science
- **Hero narrative** — lead with the protocol's core value prop, not the tech
- **Sections to plan:** Hero, How It Works, Token/Protocol overview, Team/Backers, CTA

Questions to ask Jason before writing a line of code:
1. What's the primary audience? (investors, researchers, protocol devs?)
2. Is there a color palette defined anywhere?
3. What's the one-liner for Prospereum? (Hero headline candidate)
4. Is this a public-facing marketing site or an internal/investor deck?
