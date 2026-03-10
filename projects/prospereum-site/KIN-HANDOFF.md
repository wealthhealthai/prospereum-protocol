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
  plugins: [
    tailwindcss(),
    react(),
  ],
  server: {
    port: 7802,
  },
})
```

### src/index.css
⚠️ ORDER MATTERS — this is the #1 cause of blank white screens.
Google Fonts `@import` MUST come before `@import "tailwindcss"` or PostCSS throws a silent error.

```css
/* 1. External imports FIRST */
@import url('https://fonts.googleapis.com/css2?family=YOUR+FONT:wght@400;600;700;800;900&display=swap');

/* 2. Tailwind SECOND */
@import "tailwindcss";

/* 3. Custom globals after */
:root {
  font-family: 'YOUR FONT', sans-serif;
  background: #YOUR_BG;
  color: #YOUR_TEXT;
}

* { box-sizing: border-box; margin: 0; padding: 0; }
html, body, #root { height: 100%; }
```

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
