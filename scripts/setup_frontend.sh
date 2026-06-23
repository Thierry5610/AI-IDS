#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  Beehive IDS — Frontend + Bridge scaffold
#  Run from repo root: bash scripts/setup_frontend.sh
#  Idempotent: safe to re-run (will overwrite generated files, skip venv/npm
#  if already present and valid).
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# ── Colour helpers ────────────────────────────────────────────────────────────
G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; B='\033[0;34m'; N='\033[0m'
ok()   { echo -e "  ${G}✓${N}  $*"; }
step() { echo -e "\n${B}━━━ $* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"; }
fail() { echo -e "\n${R}✗  $*${N}"; exit 1; }

# ── 0. Prerequisites ──────────────────────────────────────────────────────────
step "0  Prerequisites"

command -v node    >/dev/null 2>&1 || fail "node not found — install Node.js 18+ (e.g. nvm install 20)"
command -v npm     >/dev/null 2>&1 || fail "npm not found"
command -v python3 >/dev/null 2>&1 || fail "python3 not found"

NODE_MAJOR=$(node -v | tr -d 'v' | cut -d'.' -f1)
[ "$NODE_MAJOR" -ge 18 ] || fail "Node.js 18+ required (found $(node -v))"

ok "node $(node -v)   npm $(npm -v)   python3 $(python3 --version | cut -d' ' -f2)"


# ═════════════════════════════════════════════════════════════════════════════
#  1  BRIDGE SERVICE   (Redis → SSE → browser)
# ═════════════════════════════════════════════════════════════════════════════
step "1  Bridge service"
mkdir -p bridge/routes
touch bridge/__init__.py bridge/routes/__init__.py

# ── requirements.txt ─────────────────────────────────────────────────────────
cat > bridge/requirements.txt << 'EOF'
fastapi==0.115.0
uvicorn[standard]==0.30.6
redis==8.0.0
sse-starlette==2.1.3
python-dotenv==1.0.1
EOF
ok "bridge/requirements.txt"

# ── .env.example ─────────────────────────────────────────────────────────────
cat > bridge/.env.example << 'EOF'
REDIS_URL=redis://127.0.0.1:6379/0
IDS_ATTACKS_STREAM=ids:attacks
IDS_ANOMALIES_STREAM=ids:anomalies
BRIDGE_PORT=8001
CORS_ORIGIN=http://localhost:5173
EOF
ok "bridge/.env.example"

# ── consumer.py ──────────────────────────────────────────────────────────────
cat > bridge/consumer.py << 'EOF'
"""
Redis XREADGROUP async consumer.
Yields decoded JSON strings. idle is normal (yields None → caller sends heartbeat).
Consumer group is created at $ on first run — pre-existing stream history is skipped.
Mirrors the notifier pattern: ack-on-successful-yield, at-least-once delivery.
"""
import json
import os
import redis.asyncio as aioredis

REDIS_URL      = os.getenv("REDIS_URL", "redis://127.0.0.1:6379/0")
BLOCK_MS       = 5_000
SOCKET_TIMEOUT = BLOCK_MS / 1000 + 5   # must exceed block duration (redis-py 8 gotcha)


async def stream_events(stream: str, group: str, consumer: str):
    """Async generator: yields JSON strings or None (heartbeat tick)."""
    r = await aioredis.from_url(
        REDIS_URL,
        socket_timeout=SOCKET_TIMEOUT,
        decode_responses=True,
    )

    # Create consumer group — ignore BUSYGROUP if it already exists.
    try:
        await r.xgroup_create(stream, group, "$", mkstream=True)
    except Exception:
        pass

    while True:
        try:
            results = await r.xreadgroup(
                group, consumer, {stream: ">"}, count=10, block=BLOCK_MS
            )
        except aioredis.TimeoutError:
            yield None          # idle — caller sends SSE comment to keep connection alive
            continue
        except Exception:
            yield None
            continue

        if not results:
            yield None
            continue

        for _, messages in results:
            for msg_id, fields in messages:
                raw = fields.get("data", "{}")
                try:
                    json.loads(raw)             # validate JSON before acking
                except json.JSONDecodeError:
                    await r.xack(stream, group, msg_id)
                    continue
                await r.xack(stream, group, msg_id)
                yield raw
EOF
ok "bridge/consumer.py"

# ── routes/attacks.py ────────────────────────────────────────────────────────
cat > bridge/routes/attacks.py << 'EOF'
import os, socket
from fastapi import APIRouter, Request
from sse_starlette.sse import EventSourceResponse
from consumer import stream_events

router   = APIRouter()
STREAM   = os.getenv("IDS_ATTACKS_STREAM", "ids:attacks")
GROUP    = "dashboard-attacks"
CONSUMER = f"bridge-{socket.gethostname()}"


@router.get("/stream/attacks")
async def attacks_sse(request: Request):
    async def generator():
        async for payload in stream_events(STREAM, GROUP, CONSUMER):
            if await request.is_disconnected():
                break
            if payload is None:
                yield {"comment": "heartbeat"}
            else:
                yield {"event": "attack", "data": payload}
    return EventSourceResponse(generator())
EOF
ok "bridge/routes/attacks.py"

# ── routes/anomalies.py ──────────────────────────────────────────────────────
cat > bridge/routes/anomalies.py << 'EOF'
import os, socket
from fastapi import APIRouter, Request
from sse_starlette.sse import EventSourceResponse
from consumer import stream_events

router   = APIRouter()
STREAM   = os.getenv("IDS_ANOMALIES_STREAM", "ids:anomalies")
GROUP    = "dashboard-anomalies"
CONSUMER = f"bridge-{socket.gethostname()}"


@router.get("/stream/anomalies")
async def anomalies_sse(request: Request):
    async def generator():
        async for payload in stream_events(STREAM, GROUP, CONSUMER):
            if await request.is_disconnected():
                break
            if payload is None:
                yield {"comment": "heartbeat"}
            else:
                yield {"event": "anomaly", "data": payload}
    return EventSourceResponse(generator())
EOF
ok "bridge/routes/anomalies.py"

# ── main.py ──────────────────────────────────────────────────────────────────
cat > bridge/main.py << 'EOF'
import os
from dotenv import load_dotenv
load_dotenv()

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from routes.attacks   import router as attacks_router
from routes.anomalies import router as anomalies_router

app = FastAPI(title="Beehive Bridge", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=[os.getenv("CORS_ORIGIN", "http://localhost:5173")],
    allow_methods=["GET"],
    allow_headers=["*"],
)

app.include_router(attacks_router)
app.include_router(anomalies_router)


@app.get("/health")
async def health():
    return {"status": "ok", "service": "beehive-bridge"}
EOF
ok "bridge/main.py"

# ── venv + install ────────────────────────────────────────────────────────────
if [ ! -d bridge/.venv ]; then
    python3 -m venv bridge/.venv
    ok "bridge/.venv created"
fi
bridge/.venv/bin/pip install -q --upgrade pip
bridge/.venv/bin/pip install -q -r bridge/requirements.txt
ok "bridge deps installed"

# ── .env (copy from example if missing) ──────────────────────────────────────
[ -f bridge/.env ] || { cp bridge/.env.example bridge/.env; ok "bridge/.env created (edit if needed)"; }


# ═════════════════════════════════════════════════════════════════════════════
#  2  FRONTEND   (React + Vite)
# ═════════════════════════════════════════════════════════════════════════════
step "2  Frontend scaffold"
mkdir -p frontend/src/{styles,pages,hooks,store,lib,constants}
mkdir -p frontend/src/components/{shell,ui,charts,alerts,topology,models}

# ── package.json ─────────────────────────────────────────────────────────────
cat > frontend/package.json << 'EOF'
{
  "name": "beehive-dashboard",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "dev":     "vite",
    "build":   "vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "react":            "^18.3.1",
    "react-dom":        "^18.3.1",
    "react-router-dom": "^6.26.0",
    "zustand":          "^4.5.5"
  },
  "devDependencies": {
    "@vitejs/plugin-react": "^4.3.1",
    "vite":                 "^5.4.2"
  }
}
EOF
ok "frontend/package.json"

# ── vite.config.js ───────────────────────────────────────────────────────────
cat > frontend/vite.config.js << 'EOF'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      // /api/*  → inference service (strip /api prefix — service has no such prefix)
      '/api': {
        target:      'http://localhost:8000',
        changeOrigin: true,
        rewrite:     path => path.replace(/^\/api/, ''),
      },
      // /stream/* → bridge
      '/stream': {
        target:      'http://localhost:8001',
        changeOrigin: true,
      },
    },
  },
})
EOF
ok "frontend/vite.config.js"

# ── index.html ───────────────────────────────────────────────────────────────
cat > frontend/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Beehive IDS</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@500;600;700&family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
</head>
<body>
  <div id="root"></div>
  <script type="module" src="/src/main.jsx"></script>
</body>
</html>
EOF
ok "frontend/index.html"


# ── STYLES ────────────────────────────────────────────────────────────────────
step "2a Styles"

cat > frontend/src/styles/tokens.css << 'EOF'
/* ── Beehive design tokens ── do not edit values here directly;
   source of truth is VIGIL-THEME-SKILL.md in project knowledge ── */
:root {
  --bg:           #070707;
  --surface:      #0e0e0e;
  --surface-2:    #161616;
  --glass-bg:     rgba(20,21,18,0.5);
  --glass-bg-2:   rgba(255,255,255,0.04);
  --border:       rgba(255,255,255,0.08);
  --border-strong:rgba(255,255,255,0.16);
  --text:         #f3f3ef;
  --muted:        #9a9a93;
  --muted-2:      #5c5c56;
  --lime:         #d4ff3d;
  --lime-dim:     rgba(212,255,61,0.14);
  --cyan:         #3de8ff;
  --violet:       #b26eff;
  --green:        #34d399;
  --green-soft:   rgba(52,211,153,0.14);
  --amber:        #ffb020;
  --amber-soft:   rgba(255,176,32,0.14);
  --red:          #ff4d5e;
  --red-soft:     rgba(255,77,94,0.14);
  --r-lg:         16px;
  --r-md:         12px;
  --r-sm:         9px;
  --f-display:    'Space Grotesk', sans-serif;
  --f-body:       'Inter', sans-serif;
  --f-mono:       'JetBrains Mono', monospace;
}
EOF
ok "styles/tokens.css"

cat > frontend/src/styles/globals.css << 'EOF'
/* ── Reset + base ── */
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
button { font-family: inherit; cursor: pointer; background: none; border: none; color: inherit; }
a      { color: inherit; text-decoration: none; }
svg    { stroke-width: 2; }

:focus-visible {
  outline: 2px solid var(--lime);
  outline-offset: 2px;
  border-radius: 6px;
}

/* ── Ambient glow body (fixed so it doesn't scroll) ── */
html, body {
  color:        var(--text);
  font-family:  var(--f-body);
  -webkit-font-smoothing: antialiased;
  background:
    radial-gradient(620px circle at 10% 15%,  rgba(212,255,61,0.09),  transparent 60%),
    radial-gradient(680px circle at 90% 10%,  rgba(61,232,255,0.07),  transparent 60%),
    radial-gradient(720px circle at 75% 90%,  rgba(178,110,255,0.08), transparent 60%),
    radial-gradient(500px circle at 20% 85%,  rgba(212,255,61,0.05),  transparent 60%),
    var(--bg);
  background-attachment: fixed;
  min-height: 100vh;
}

/* ── Honour reduced-motion preference ── */
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration:        0.01ms !important;
    animation-iteration-count: 1      !important;
    transition-duration:       0.01ms !important;
  }
}
EOF
ok "styles/globals.css"

cat > frontend/src/styles/shell.css << 'EOF'
/* ── App shell — identical on every page; do not diverge per-page ── */

.app  { display: flex; min-height: 100vh; }
.main { flex: 1; min-width: 0; display: flex; flex-direction: column; }

/* ── Rail (icon-only, 64px, sticky) ── */
.rail {
  width: 64px; flex-shrink: 0;
  background: rgba(14,14,14,0.65);
  backdrop-filter: blur(16px); -webkit-backdrop-filter: blur(16px);
  border-right: 1px solid var(--border);
  display: flex; flex-direction: column; align-items: center;
  padding: 18px 0;
  position: sticky; top: 0; height: 100vh;
  z-index: 10;
}
.rail-logo { width: 26px; height: 26px; margin-bottom: 28px; flex-shrink: 0; }
.rail-nav  { display: flex; flex-direction: column; gap: 4px; flex: 1; }

.rail-item {
  position: relative;
  width: 38px; height: 38px;
  display: flex; align-items: center; justify-content: center;
  border-radius: 50%;
  color: var(--muted-2);
  transition: color .15s, background .15s;
}
.rail-item svg      { width: 18px; height: 18px; }
.rail-item:hover    { color: var(--text); background: rgba(255,255,255,0.04); }
.rail-item.active   { color: var(--lime); background: var(--lime-dim); }
.rail-item.active::before {
  content: ''; position: absolute; left: -12px; top: 50%; transform: translateY(-50%);
  width: 4px; height: 16px; border-radius: 3px; background: var(--lime);
}

.rail-bottom { display: flex; flex-direction: column; align-items: center; gap: 14px; }

.rail-dot {
  width: 7px; height: 7px; border-radius: 50%;
  background: var(--green);
  animation: pulse-dot 2.2s infinite;
}
@keyframes pulse-dot {
  0%,100% { box-shadow: 0 0 0 0   rgba(52,211,153,0.0); }
  50%     { box-shadow: 0 0 0 5px rgba(52,211,153,0.0); }
}

/* ── Topbar (sticky, glass) ── */
.topbar {
  height: 62px; flex-shrink: 0;
  display: flex; align-items: center; gap: 14px;
  padding: 0 24px;
  border-bottom: 1px solid var(--border);
  position: sticky; top: 0; z-index: 5;
  background: rgba(7,7,7,0.55);
  backdrop-filter: blur(14px); -webkit-backdrop-filter: blur(14px);
}
.tb-brand { font-family: var(--f-display); font-weight: 700; font-size: 14.5px; letter-spacing: 0.3px; }
.tb-sep   { width: 1px; height: 18px; background: var(--border-strong); flex-shrink: 0; }
.tb-title { font-size: 13px; color: var(--muted); font-weight: 500; }
.tb-right { margin-left: auto; display: flex; align-items: center; gap: 10px; }

/* Avatar (topbar + tables) — never a gradient fill */
.avatar {
  width: 26px; height: 26px; border-radius: 50%;
  background: var(--surface-2); border: 1px solid var(--border-strong);
  display: flex; align-items: center; justify-content: center;
  font-family: var(--f-display); font-size: 10px; font-weight: 700;
  color: var(--lime); user-select: none; flex-shrink: 0;
}

/* ── Content area + bento grid ── */
.content { padding: 24px 26px 40px; max-width: 1380px; width: 100%; margin: 0 auto; }
.bento   { display: flex; flex-direction: column; gap: 18px; }

/* Row helpers — use as needed per page */
.row-2 { display: grid; grid-template-columns: 1fr 1fr;           gap: 18px; }
.row-3 { display: grid; grid-template-columns: 1fr 1fr 1fr;       gap: 18px; }
.row-4 { display: grid; grid-template-columns: 1fr 1fr 1fr 1fr;   gap: 18px; }
.row-6535 { display: grid; grid-template-columns: 65fr 35fr;      gap: 18px; }
.row-3565 { display: grid; grid-template-columns: 35fr 65fr;      gap: 18px; }

/* ── Glass card (every card on every page) ── */
.card {
  background: var(--glass-bg);
  backdrop-filter: blur(18px) saturate(140%); -webkit-backdrop-filter: blur(18px) saturate(140%);
  border: 1px solid var(--border-strong);
  border-radius: var(--r-lg);
  padding: 18px 18px 16px;
  box-shadow: inset 0 1px 0 rgba(255,255,255,0.05), 0 10px 28px -16px rgba(0,0,0,0.6);
}
.card-header {
  display: flex; align-items: center; justify-content: space-between;
  margin-bottom: 14px;
}
.card-title {
  font-size: 12px; font-weight: 600; letter-spacing: 0.6px;
  text-transform: uppercase; color: var(--muted);
}

/* ── KPI cards ── */
.kpi-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 18px; }
.kpi { display: flex; flex-direction: column; gap: 6px; }

.kpi-icon {
  width: 32px; height: 32px; border-radius: 50%;
  border: 1px solid var(--border-strong); background: var(--glass-bg-2);
  display: flex; align-items: center; justify-content: center;
  color: var(--muted);
}
.kpi-value { font-family: var(--f-display); font-size: 32px; font-weight: 600; letter-spacing: -0.5px; line-height: 1; }
.kpi-label { font-size: 12px; color: var(--muted); margin-top: 2px; }

.delta { font-size: 11px; font-weight: 600; padding: 3px 9px; border-radius: 99px; display: inline-block; }
.delta.good { color: var(--green); background: var(--green-soft); }
.delta.bad  { color: var(--amber); background: var(--amber-soft); }
.delta.crit { color: var(--red);   background: var(--red-soft);   }

/* Featured KPI — solid lime block, one per page */
.kpi.featured {
  background: var(--lime);
  backdrop-filter: none; -webkit-backdrop-filter: none;
  border-color: var(--lime);
  border-radius: var(--r-lg);
  padding: 18px;
  animation: lime-pulse 2.6s ease-in-out infinite;
}
.kpi.featured .kpi-value,
.kpi.featured .kpi-label { color: #0a0a0a; }
.kpi.featured .kpi-icon  { background: rgba(0,0,0,0.12); border-color: rgba(0,0,0,0.15); color: #0a0a0a; }

@keyframes lime-pulse {
  0%,100% { box-shadow: 0 0 0  0 rgba(212,255,61,0.0); }
  50%     { box-shadow: 0 0 18px 1px rgba(212,255,61,0.4); }
}

/* ── Status/severity pills ── */
.pill {
  display: inline-flex; align-items: center; gap: 5px;
  font-size: 11px; font-weight: 600; padding: 3px 9px; border-radius: 99px;
  white-space: nowrap;
}
.pill::before { content: ''; width: 5px; height: 5px; border-radius: 50%; flex-shrink: 0; }

.pill.critical { color: var(--red);   background: var(--red-soft);   } .pill.critical::before { background: var(--red); }
.pill.high     { color: var(--amber); background: var(--amber-soft); } .pill.high::before     { background: var(--amber); }
.pill.medium   { color: var(--cyan);  background: rgba(61,232,255,0.12); } .pill.medium::before  { background: var(--cyan); }
.pill.low      { color: var(--muted); background: rgba(255,255,255,0.06); } .pill.low::before   { background: var(--muted); }
.pill.ok, .pill.benign  { color: var(--green); background: var(--green-soft); } .pill.ok::before { background: var(--green); }
.pill.anomaly  { color: var(--violet); background: rgba(178,110,255,0.12); } .pill.anomaly::before { background: var(--violet); }

/* ── Pill buttons ── */
.btn { padding: 7px 16px; border-radius: 99px; font-size: 13px; font-weight: 600; transition: opacity .15s; }
.btn:hover { opacity: 0.85; }
.btn-primary { background: var(--lime); color: #0a0a0a; }
.btn-ghost   { background: var(--glass-bg-2); border: 1px solid var(--border-strong); color: var(--muted); }
.btn-ghost:hover { color: var(--text); }

/* ── Data tables ── */
.table-wrap { overflow-x: auto; }
table       { width: 100%; border-collapse: collapse; }
thead th    { font-size: 11px; font-weight: 600; letter-spacing: 0.5px; text-transform: uppercase;
              color: var(--muted-2); padding: 0 12px 10px; text-align: left; }
tbody tr    { border-top: 1px solid var(--border); }
tbody td    { padding: 11px 12px; font-size: 13px; vertical-align: middle; }
tbody tr:hover td { background: rgba(255,255,255,0.02); }

.mono       { font-family: var(--f-mono); font-size: 12px; }

/* ── Search / filter bar ── */
.filter-bar { display: flex; align-items: center; gap: 10px; margin-bottom: 16px; flex-wrap: wrap; }
.search-box {
  display: flex; align-items: center; gap: 8px;
  background: var(--glass-bg-2); border: 1px solid var(--border-strong);
  border-radius: 99px; padding: 7px 14px; flex: 1; min-width: 180px;
}
.search-box input {
  background: none; border: none; outline: none;
  color: var(--text); font-family: var(--f-body); font-size: 13px; width: 100%;
}
.search-box input::placeholder { color: var(--muted-2); }
.filter-pill {
  padding: 6px 14px; border-radius: 99px; font-size: 12px; font-weight: 600;
  background: var(--glass-bg-2); border: 1px solid var(--border-strong);
  color: var(--muted); cursor: pointer; transition: all .15s;
}
.filter-pill.active { background: var(--lime-dim); border-color: var(--lime); color: var(--lime); }

/* ── Pagination ── */
.pagination { display: flex; align-items: center; gap: 10px; padding-top: 14px; }
.pg-info    { font-size: 12px; color: var(--muted); margin-right: auto; }
.pg-btn {
  width: 30px; height: 30px; border-radius: 50%;
  display: flex; align-items: center; justify-content: center;
  background: var(--glass-bg-2); border: 1px solid var(--border-strong);
  color: var(--muted); transition: color .15s, background .15s;
}
.pg-btn:hover   { color: var(--text); background: rgba(255,255,255,0.06); }
.pg-btn:disabled { opacity: 0.3; cursor: not-allowed; }

/* ── Log stream (alert feed) ── */
.log-stream { display: flex; flex-direction: column; }
.log-row    { display: flex; gap: 12px; position: relative; }
.log-row:not(:last-child) .log-line { flex: 1; }
.log-icon { width: 22px; height: 22px; border-radius: 50%; flex-shrink: 0;
            background: var(--glass-bg-2); border: 1px solid var(--border-strong);
            display: flex; align-items: center; justify-content: center; }
.log-icon.crit { color: var(--red); }
.log-icon.warn { color: var(--amber); }
.log-icon.ok   { color: var(--green); }
.log-line  { width: 1px; background: var(--border-strong); min-height: 18px; margin: 2px 0 2px 10px; }
.log-body  { flex: 1; padding-bottom: 16px; }
.log-title { font-size: 13px; font-weight: 500; }
.log-meta  { font-family: var(--f-mono); font-size: 11px; color: var(--muted); margin-top: 3px; }

/* ── Responsive floor ── */
@media (max-width: 1180px) {
  .row-4    { grid-template-columns: 1fr 1fr; }
  .kpi-grid { grid-template-columns: 1fr 1fr; }
}
@media (max-width: 760px) {
  .rail          { display: none; }
  .row-6535,
  .row-3565,
  .row-3,
  .row-2         { grid-template-columns: 1fr; }
  .kpi-grid      { grid-template-columns: 1fr 1fr; }
}
@media (max-width: 560px) {
  .kpi-grid      { grid-template-columns: 1fr; }
}
EOF
ok "styles/shell.css"


# ── CONSTANTS ─────────────────────────────────────────────────────────────────
step "2b Constants"

cat > frontend/src/constants/nav.js << 'EOF'
/**
 * Single source of truth for the rail navigation.
 * icon: inline SVG path string (24x24 viewBox, stroke-width 2, round caps/joins).
 * Sourced verbatim from VIGIL-THEME-SKILL.md icon library.
 */
export const NAV_ITEMS = [
  {
    id: 'overview', path: '/', label: 'Overview',
    icon: '<rect x="3" y="3" width="9" height="9" rx="2"/><rect x="14" y="3" width="7" height="4" rx="1.6"/><rect x="14" y="9" width="7" height="3" rx="1.4"/><rect x="3" y="14" width="18" height="7" rx="2"/>',
  },
  {
    id: 'topology', path: '/topology', label: 'Topology',
    icon: '<line x1="6.7" y1="7.3" x2="10.6" y2="11.7"/><line x1="17.3" y1="7.3" x2="13.4" y2="11.7"/><line x1="11" y1="14.5" x2="7" y2="17.7"/><line x1="13" y1="14.5" x2="17" y2="17.7"/><circle cx="5" cy="6" r="2.1" fill="currentColor" stroke="none"/><circle cx="19" cy="6" r="2.1" fill="currentColor" stroke="none"/><circle cx="12" cy="13" r="2.3" fill="currentColor" stroke="none"/><circle cx="6" cy="19" r="2.1" fill="currentColor" stroke="none"/><circle cx="18" cy="19" r="2.1" fill="currentColor" stroke="none"/>',
  },
  {
    id: 'alerts', path: '/alerts', label: 'Alerts',
    icon: '<circle cx="12" cy="12" r="8.5"/><line x1="12" y1="8" x2="12" y2="13"/><circle cx="12" cy="16.3" r="0.5" fill="currentColor" stroke="none"/>',
  },
  {
    id: 'flows', path: '/flows', label: 'Flows',
    icon: '<path d="M4 12h12M13 8l4 4-4 4"/><circle cx="4" cy="12" r="1.5" fill="currentColor" stroke="none"/>',
  },
  {
    id: 'models', path: '/models', label: 'Models',
    icon: '<rect x="5" y="3" width="14" height="18" rx="2"/><rect x="8" y="13" width="2" height="5" fill="currentColor" stroke="none"/><rect x="11.3" y="10" width="2" height="8" fill="currentColor" stroke="none"/><rect x="14.6" y="7" width="2" height="11" fill="currentColor" stroke="none"/>',
  },
  {
    id: 'research', path: '/research', label: 'Research',
    icon: '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3.6" fill="currentColor" stroke="none" opacity="0.18"/><circle cx="12" cy="12" r="3.6"/><circle cx="12" cy="12" r="0.6" fill="currentColor" stroke="none"/>',
  },
]

export const BOTTOM_NAV = [
  {
    id: 'settings', path: '/settings', label: 'Settings',
    icon: '<line x1="4" y1="7" x2="20" y2="7"/><circle cx="9" cy="7" r="2.1" fill="var(--surface)"/><line x1="4" y1="12.5" x2="20" y2="12.5"/><circle cx="16" cy="12.5" r="2.1" fill="var(--surface)"/><line x1="4" y1="18" x2="20" y2="18"/><circle cx="12" cy="18" r="2.1" fill="var(--surface)"/>',
  },
]
EOF
ok "constants/nav.js"

cat > frontend/src/constants/models.js << 'EOF'
/**
 * Five model identifiers — match the id strings in /predict response exactly.
 * Colors: lime/cyan/violet/amber are CHART-ONLY categorical colors (not UI chrome).
 * AE is anomaly-only; the four supervised models produce label + confidence votes.
 */
export const MODELS = [
  { id: 'random_forest', label: 'Random Forest', short: 'RF',  color: 'var(--lime)'   },
  { id: 'xgboost',       label: 'XGBoost',       short: 'XGB', color: 'var(--cyan)'   },
  { id: 'lightgbm',      label: 'LightGBM',       short: 'LGB', color: 'var(--violet)' },
  { id: 'cnn_lstm',      label: 'CNN-LSTM',        short: 'CNN', color: 'var(--amber)'  },
  { id: 'autoencoder',   label: 'Autoencoder',     short: 'AE',  color: 'var(--red)'    },
]

export const SUPERVISED = MODELS.filter(m => m.id !== 'autoencoder')
export const AE_MODEL   = MODELS.find(m => m.id === 'autoencoder')

export const AE_THRESHOLD = 0.0726  // 95th-percentile benign reconstruction error — fixed

export function modelById(id) {
  return MODELS.find(m => m.id === id) ?? { id, label: id, short: id, color: 'var(--muted)' }
}
EOF
ok "constants/models.js"

cat > frontend/src/constants/attacks.js << 'EOF'
/**
 * CICIDS2017 attack labels (index = label_index from /predict).
 * Source: label_encoder.pkl — do not reorder.
 */
export const ATTACK_LABELS = [
  'Benign',                    // 0
  'Bot',                       // 1
  'DDoS',                      // 2
  'DoS GoldenEye',             // 3
  'DoS Hulk',                  // 4
  'DoS Slowhttptest',          // 5
  'DoS slowloris',             // 6
  'FTP-Patator',               // 7
  'Heartbleed',                // 8
  'Infiltration',              // 9
  'PortScan',                  // 10
  'SSH-Patator',               // 11
  'Web Attack - Brute Force',  // 12
  'Web Attack - Sql Injection',// 13
  'Web Attack - XSS',          // 14
]

/**
 * Coarse severity bucket → pill class.
 * Tuned for CICIDS2017 class semantics.
 */
export function severityOf(label) {
  if (!label || label === 'Benign') return 'ok'
  const l = label.toLowerCase()
  if (l.includes('ddos') || l.includes('heartbleed') || l.includes('infiltration')) return 'critical'
  if (l.includes('dos')  || l.includes('bot'))                                       return 'high'
  if (l.includes('patator') || l.includes('scan'))                                   return 'medium'
  return 'low'
}
EOF
ok "constants/attacks.js"


# ── LIB ───────────────────────────────────────────────────────────────────────
step "2c Lib"

cat > frontend/src/lib/api.js << 'EOF'
/**
 * Thin fetch wrappers for the inference service.
 * All paths are relative — Vite proxies /api/* → localhost:8000 in dev,
 * stripping the /api prefix so the service sees its native routes.
 */
const BASE = '/api'

export async function fetchHealth() {
  const r = await fetch(`${BASE}/health`)
  if (!r.ok) throw new Error(`health check failed (${r.status})`)
  return r.json()
}

export async function fetchModels() {
  const r = await fetch(`${BASE}/models`)
  if (!r.ok) throw new Error(`/models failed (${r.status})`)
  return r.json()
}

/**
 * Direct predict call — used by the Research page for manual feature submission.
 * Normal traffic takes the eBPF → emitter → Redis path; this is a dev/debug shortcut.
 */
export async function predict(features, flowId = '') {
  const r = await fetch(`${BASE}/predict`, {
    method:  'POST',
    headers: { 'Content-Type': 'application/json' },
    body:    JSON.stringify({ features, flow_id: flowId }),
  })
  if (!r.ok) throw new Error(`/predict failed (${r.status})`)
  return r.json()
}
EOF
ok "lib/api.js"

cat > frontend/src/lib/stream.js << 'EOF'
/**
 * SSE client factory with exponential-backoff reconnect.
 * Vite proxies /stream/* → bridge (localhost:8001) in dev.
 *
 * Usage:
 *   const unsub = createStream('/stream/attacks', 'attack', onMessage, onError)
 *   unsub()   // close & stop reconnecting
 */
export function createStream(path, eventName, onMessage, onError) {
  let es
  let stopped  = false
  let retryMs  = 1_000
  const MAX_MS = 30_000

  function connect() {
    if (stopped) return
    es = new EventSource(path)

    es.addEventListener(eventName, (e) => {
      retryMs = 1_000                    // reset backoff on successful message
      try { onMessage(JSON.parse(e.data)) }
      catch (err) { console.warn('[stream] parse error', path, err) }
    })

    es.onerror = () => {
      es.close()
      if (stopped) return
      onError?.(`[stream] ${path} lost — retry in ${retryMs}ms`)
      const delay = retryMs
      retryMs = Math.min(retryMs * 2, MAX_MS)
      setTimeout(connect, delay)
    }
  }

  connect()
  return () => { stopped = true; es?.close() }
}
EOF
ok "lib/stream.js"

cat > frontend/src/lib/format.js << 'EOF'
/** Display-formatting helpers — pure functions, no side effects. */

export const fmt = {
  ip:   (ip)   => ip   ?? '—',
  port: (p)    => p    != null ? String(p) : '—',

  /** "192.168.1.1:4444 → 10.0.0.1:22" */
  flow: ({ src_ip, src_port, dst_ip, dst_port } = {}) =>
    `${src_ip ?? '?'}:${src_port ?? '?'} → ${dst_ip ?? '?'}:${dst_port ?? '?'}`,

  /** HH:MM:SS from an ISO timestamp string */
  time: (iso) => {
    if (!iso) return '—'
    try { return new Date(iso).toLocaleTimeString('en-GB', { hour12: false }) }
    catch { return iso }
  },

  /** "97.3%" */
  pct: (c) => c != null ? `${(c * 100).toFixed(1)}%` : '—',

  /** 6→TCP, 17→UDP, 1→ICMP */
  proto: (n) => ({ 6: 'TCP', 17: 'UDP', 1: 'ICMP' }[n] ?? String(n ?? '?')),
}
EOF
ok "lib/format.js"


# ── SHELL COMPONENTS ──────────────────────────────────────────────────────────
step "2d Shell components"

cat > frontend/src/components/shell/Rail.jsx << 'EOF'
import { useNavigate, useLocation } from 'react-router-dom'
import { NAV_ITEMS, BOTTOM_NAV } from '../../constants/nav'

/** Beehive logo mark — verbatim from VIGIL-THEME-SKILL.md */
function Logo() {
  return (
    <svg
      className="rail-logo"
      viewBox="0 0 32 32"
      fill="none"
      aria-label="Beehive"
      role="img"
    >
      <circle cx="16" cy="16" r="12.5" stroke="var(--lime)" strokeWidth="2"/>
      <circle cx="16" cy="16" r="5.5"  fill="var(--lime)"/>
      <line
        x1="16" y1="2.5" x2="16" y2="7.5"
        stroke="var(--lime)" strokeWidth="2" strokeLinecap="round" opacity="0.55"
      />
    </svg>
  )
}

function NavBtn({ item, active, onClick }) {
  return (
    <button
      className={`rail-item${active ? ' active' : ''}`}
      onClick={() => onClick(item.path)}
      aria-label={item.label}
      aria-current={active ? 'page' : undefined}
      title={item.label}
    >
      <svg
        viewBox="0 0 24 24"
        fill="none"
        strokeLinecap="round"
        strokeLinejoin="round"
        dangerouslySetInnerHTML={{ __html: item.icon }}
      />
    </button>
  )
}

export default function Rail() {
  const navigate      = useNavigate()
  const { pathname }  = useLocation()

  /** Exact match for '/', prefix match for everything else */
  const isActive = (path) =>
    path === '/' ? pathname === '/' : pathname.startsWith(path)

  return (
    <aside className="rail">
      <Logo />

      <nav className="rail-nav" aria-label="Main navigation">
        {NAV_ITEMS.map(item => (
          <NavBtn
            key={item.id}
            item={item}
            active={isActive(item.path)}
            onClick={navigate}
          />
        ))}
      </nav>

      <div className="rail-bottom">
        {BOTTOM_NAV.map(item => (
          <NavBtn
            key={item.id}
            item={item}
            active={isActive(item.path)}
            onClick={navigate}
          />
        ))}
        <span className="rail-dot" aria-label="System online" title="System online" />
      </div>
    </aside>
  )
}
EOF
ok "Rail.jsx"

cat > frontend/src/components/shell/Topbar.jsx << 'EOF'
/**
 * Topbar — sticky glass header, identical on every page.
 * Props:
 *   title (string) — current page name (set per page, injected by Shell)
 */
export default function Topbar({ title }) {
  return (
    <header className="topbar">
      <span className="tb-brand">Beehive</span>
      <span className="tb-sep" aria-hidden="true" />
      <span className="tb-title">{title}</span>

      <div className="tb-right">
        {/* Placeholder avatar — expands post-auth implementation */}
        <div className="avatar" aria-label="User menu">TN</div>
      </div>
    </header>
  )
}
EOF
ok "Topbar.jsx"

cat > frontend/src/components/shell/Shell.jsx << 'EOF'
/**
 * Shell — wraps every page.
 * Props:
 *   title (string) — forwarded to Topbar
 *   children       — page content, rendered inside .bento
 */
import Rail   from './Rail'
import Topbar from './Topbar'

export default function Shell({ title, children }) {
  return (
    <div className="app">
      <Rail />
      <div className="main">
        <Topbar title={title} />
        <div className="content">
          <div className="bento">
            {children}
          </div>
        </div>
      </div>
    </div>
  )
}
EOF
ok "Shell.jsx"


# ── PLACEHOLDER PAGES ─────────────────────────────────────────────────────────
step "2e Placeholder pages"

write_page() {
  local COMPONENT="$1"
  local TITLE="$2"
  cat > "frontend/src/pages/${COMPONENT}.jsx" << PAGEOF
import Shell from '../components/shell/Shell'

export default function ${COMPONENT}() {
  return (
    <Shell title="${TITLE}">
      <p style={{ color: 'var(--muted)', fontFamily: 'var(--f-mono)', fontSize: 13, padding: '8px 0' }}>
        {/* ${TITLE} — content coming in its own build session */}
      </p>
    </Shell>
  )
}
PAGEOF
  ok "pages/${COMPONENT}.jsx"
}

write_page "Overview"  "Overview"
write_page "Topology"  "Topology"
write_page "Alerts"    "Alerts"
write_page "Flows"     "Flows"
write_page "Models"    "Models"
write_page "Research"  "Research / AE"
write_page "Settings"  "Settings"


# ── APP + ENTRY ───────────────────────────────────────────────────────────────
step "2f App + entry"

cat > frontend/src/App.jsx << 'EOF'
import { BrowserRouter, Routes, Route } from 'react-router-dom'
import Overview from './pages/Overview'
import Topology from './pages/Topology'
import Alerts   from './pages/Alerts'
import Flows    from './pages/Flows'
import Models   from './pages/Models'
import Research from './pages/Research'
import Settings from './pages/Settings'

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/"         element={<Overview />} />
        <Route path="/topology" element={<Topology />} />
        <Route path="/alerts"   element={<Alerts />}   />
        <Route path="/flows"    element={<Flows />}    />
        <Route path="/models"   element={<Models />}   />
        <Route path="/research" element={<Research />} />
        <Route path="/settings" element={<Settings />} />
      </Routes>
    </BrowserRouter>
  )
}
EOF
ok "App.jsx"

cat > frontend/src/main.jsx << 'EOF'
/* Global styles — order matters: tokens first, then reset, then shell layout */
import './styles/tokens.css'
import './styles/globals.css'
import './styles/shell.css'

import { StrictMode }  from 'react'
import { createRoot }  from 'react-dom/client'
import App             from './App'

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <App />
  </StrictMode>
)
EOF
ok "main.jsx"


# ── NPM INSTALL ───────────────────────────────────────────────────────────────
step "3  npm install"
cd frontend
npm install --silent
cd ..
ok "node_modules ready"


# ── VALIDATION ────────────────────────────────────────────────────────────────
step "4  Validation"

# npm packages
[ -f frontend/node_modules/react/package.json ]             && ok "react installed"            || fail "react missing — npm install may have failed"
[ -f frontend/node_modules/react-router-dom/package.json ]  && ok "react-router-dom installed" || fail "react-router-dom missing"
[ -f frontend/node_modules/zustand/package.json ]           && ok "zustand installed"          || fail "zustand missing"
[ -f frontend/node_modules/vite/package.json ]              && ok "vite installed"             || fail "vite missing"

# bridge Python imports
bridge/.venv/bin/python3 -c "import fastapi, redis, sse_starlette, dotenv" \
  && ok "bridge Python deps importable" \
  || fail "bridge Python import failed — check bridge/.venv"

# key files exist
for f in \
  frontend/src/styles/tokens.css \
  frontend/src/components/shell/Shell.jsx \
  frontend/src/components/shell/Rail.jsx \
  bridge/main.py bridge/consumer.py
do
  [ -f "$f" ] && ok "$f" || fail "$f missing"
done


# ── DONE ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${G}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo -e "${G}  Beehive scaffold complete.${N}"
echo ""
echo -e "  Start order (one terminal each):"
echo ""
echo -e "  ${Y}1${N}  Redis"
echo -e "     docker start ids-redis"
echo ""
echo -e "  ${Y}2${N}  Inference service"
echo -e "     cd inference-service && source .venv/bin/activate"
echo -e "     uvicorn app.main:app --port 8000"
echo ""
echo -e "  ${Y}3${N}  Bridge"
echo -e "     cd bridge && source .venv/bin/activate"
echo -e "     uvicorn main:app --port 8001 --reload"
echo ""
echo -e "  ${Y}4${N}  Frontend"
echo -e "     cd frontend && npm run dev"
echo -e "     → http://localhost:5173"
echo ""
echo -e "  ${Y}5${N}  Sensor  (optional — for live traffic)"
echo -e "     cd ebpf-sensor && sudo /usr/bin/python3 sensor/loader.py wlp1s0"
echo -e "${G}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
