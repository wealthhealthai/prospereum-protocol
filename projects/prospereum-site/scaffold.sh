#!/bin/bash
# Prospereum site scaffold — run once from this directory
# Usage: bash scaffold.sh

set -e
SITE_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SITE_DIR"

echo "→ Scaffolding Vite React/TS app..."
npm create vite@latest . -- --template react-ts --yes 2>/dev/null || true

echo "→ Installing deps..."
npm install
npm install tailwindcss @tailwindcss/vite framer-motion lucide-react clsx three @types/three

echo "→ Writing vite.config.ts..."
cat > vite.config.ts << 'EOF'
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
EOF

echo "→ Writing src/index.css (Tailwind v4, correct import order)..."
cat > src/index.css << 'EOF'
/* ⚠️ IMPORT ORDER CRITICAL — Google Fonts must precede @import "tailwindcss" */
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800;900&display=swap');
@import "tailwindcss";

:root {
  font-family: 'Inter', sans-serif;
  background: #07070E;
  color: #f5f5f5;
}

* { box-sizing: border-box; margin: 0; padding: 0; }
html, body, #root { height: 100%; }
EOF

echo ""
echo "✅ Done! Next steps:"
echo "   1. Read KIN-HANDOFF.md for patterns + debugging guide"
echo "   2. Start dev server: npm run dev"
echo "   3. Visit http://localhost:7802/"
echo ""
echo "   Reference: ~/.openclaw/workspace-shiro/projects/prometheus-site/"
