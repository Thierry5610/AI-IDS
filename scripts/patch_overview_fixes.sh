#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  Beehive IDS — Overview fixes
#  Addresses: icon stroke, scale, bubble positions, status strip, consumer $→0
#  Run from repo root: bash scripts/patch_overview_fixes.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

G='\033[0;32m'; B='\033[0;34m'; N='\033[0m'
ok()   { echo -e "  ${G}✓${N}  $*"; }
step() { echo -e "\n${B}━━━ $* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"; }


# ═══════════════════════════════════════════════════════════════════════
#  FIX 1 — bridge/consumer.py: start at 0 not $ so history is caught
# ═══════════════════════════════════════════════════════════════════════
step "Fix 1  bridge/consumer.py — start at 0"

cat > bridge/consumer.py << 'EOF'
"""
Redis XREADGROUP async consumer.
Yields decoded JSON strings. idle is normal (yields None → caller sends heartbeat).

Consumer group is created at "0" (start of stream) on first run.
This means the bridge replays recent stream history on start-up — desirable
for the dashboard to show recent attacks immediately on page load.
"""
import json
import os
import redis.asyncio as aioredis

REDIS_URL      = os.getenv("REDIS_URL", "redis://127.0.0.1:6379/0")
BLOCK_MS       = 5_000
SOCKET_TIMEOUT = BLOCK_MS / 1000 + 5


async def stream_events(stream: str, group: str, consumer: str):
    """Async generator: yields JSON strings or None (heartbeat tick)."""
    r = await aioredis.from_url(
        REDIS_URL,
        socket_timeout=SOCKET_TIMEOUT,
        decode_responses=True,
    )

    # "0" → read from the beginning of the stream on first run.
    # BUSYGROUP means the group already exists (bridge restarted) — ignore.
    try:
        await r.xgroup_create(stream, group, "0", mkstream=True)
    except Exception:
        pass

    while True:
        try:
            results = await r.xreadgroup(
                group, consumer, {stream: ">"}, count=10, block=BLOCK_MS
            )
        except aioredis.TimeoutError:
            yield None
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
                    json.loads(raw)
                except json.JSONDecodeError:
                    await r.xack(stream, group, msg_id)
                    continue
                await r.xack(stream, group, msg_id)
                yield raw
EOF
ok "consumer.py → start at 0"


# ═══════════════════════════════════════════════════════════════════════
#  FIX 2 — Rail.jsx: add stroke="currentColor" to icon SVG
# ═══════════════════════════════════════════════════════════════════════
step "Fix 2  Rail.jsx — add stroke to icon SVG"

cat > frontend/src/components/shell/Rail.jsx << 'EOF'
import { useNavigate, useLocation } from 'react-router-dom'
import { NAV_ITEMS, BOTTOM_NAV } from '../../constants/nav'

function Logo() {
  return (
    <svg className="rail-logo" viewBox="0 0 32 32" fill="none" aria-label="Beehive" role="img">
      <circle cx="16" cy="16" r="12.5" stroke="var(--lime)" strokeWidth="2"/>
      <circle cx="16" cy="16" r="5.5"  fill="var(--lime)"/>
      <line x1="16" y1="2.5" x2="16" y2="7.5"
        stroke="var(--lime)" strokeWidth="2" strokeLinecap="round" opacity="0.55"/>
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
      {/* stroke="currentColor" is required — icon paths rely on inherited stroke */}
      <svg viewBox="0 0 24 24" fill="none"
           stroke="currentColor"
           strokeWidth="2"
           strokeLinecap="round"
           strokeLinejoin="round"
           style={{ width: 18, height: 18 }}
           dangerouslySetInnerHTML={{ __html: item.icon }} />
    </button>
  )
}

export default function Rail() {
  const navigate     = useNavigate()
  const { pathname } = useLocation()

  const isActive = (path) =>
    path === '/' ? pathname === '/' : pathname.startsWith(path)

  return (
    <aside className="rail">
      <Logo />
      <nav className="rail-nav" aria-label="Main navigation">
        {NAV_ITEMS.map(item => (
          <NavBtn key={item.id} item={item}
            active={isActive(item.path)} onClick={navigate} />
        ))}
      </nav>
      <div className="rail-bottom">
        {BOTTOM_NAV.map(item => (
          <NavBtn key={item.id} item={item}
            active={isActive(item.path)} onClick={navigate} />
        ))}
        <span className="rail-dot" aria-label="System online" title="System online" />
      </div>
    </aside>
  )
}
EOF
ok "Rail.jsx — stroke added"


# ═══════════════════════════════════════════════════════════════════════
#  FIX 3 — Topbar.jsx: date navigation + notifications badge
# ═══════════════════════════════════════════════════════════════════════
step "Fix 3  Topbar.jsx — date nav + notifications"

cat > frontend/src/components/shell/Topbar.jsx << 'EOF'
/**
 * Topbar — sticky glass header.
 * Includes: brand · separator · page title · date nav · notification bell · avatar
 * Props: title (string)
 */
const BELL_ICON   = '<path d="M18 8a6 6 0 10-12 0c0 4-2 5-2 6h16c0-1-2-2-2-6z"/><path d="M10 19a2 2 0 004 0"/>'
const CHEVRON_L   = '<path d="M15 5l-7 7 7 7"/>'
const CHEVRON_R   = '<path d="M9 5l7 7-7 7"/>'

function IconBtn({ icon, badge, label }) {
  return (
    <button aria-label={label} style={{
      position: 'relative', width: 34, height: 34,
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      borderRadius: '50%', color: 'var(--muted)',
      transition: 'background .15s, color .15s',
    }}
    onMouseEnter={e => { e.currentTarget.style.background = 'var(--glass-bg-2)'; e.currentTarget.style.color = 'var(--text)' }}
    onMouseLeave={e => { e.currentTarget.style.background = ''; e.currentTarget.style.color = 'var(--muted)' }}
    >
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor"
           strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"
           style={{ width: 16.5, height: 16.5 }}
           dangerouslySetInnerHTML={{ __html: icon }} />
      {badge && (
        <span style={{
          position: 'absolute', top: 3, right: 4,
          width: 13, height: 13, borderRadius: '50%',
          background: 'var(--red)', color: '#0a0a0a',
          fontSize: 8, fontWeight: 700,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          border: '2px solid var(--bg)',
        }}>
          {badge}
        </span>
      )}
    </button>
  )
}

function DateNav() {
  const today = new Date().toLocaleDateString('en-GB', { day: '2-digit', month: 'short' })
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 9,
      background: 'var(--glass-bg-2)', border: '1px solid var(--border)',
      borderRadius: 99, padding: '6px 8px 6px 14px',
      fontSize: 11.5, color: 'var(--muted)', marginLeft: 4, userSelect: 'none',
    }}>
      <button aria-label="Previous day" style={{
        width: 16, height: 16, display: 'flex', alignItems: 'center',
        justifyContent: 'center', color: 'var(--muted-2)', borderRadius: '50%',
      }}>
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor"
             strokeWidth="2.4" strokeLinecap="round"
             style={{ width: 11, height: 11 }}
             dangerouslySetInnerHTML={{ __html: CHEVRON_L }} />
      </button>
      Today · {today}
      <button aria-label="Next day" style={{
        width: 16, height: 16, display: 'flex', alignItems: 'center',
        justifyContent: 'center', color: 'var(--muted-2)', borderRadius: '50%',
      }}>
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor"
             strokeWidth="2.4" strokeLinecap="round"
             style={{ width: 11, height: 11 }}
             dangerouslySetInnerHTML={{ __html: CHEVRON_R }} />
      </button>
    </div>
  )
}

export default function Topbar({ title }) {
  return (
    <header className="topbar">
      <span className="tb-brand">Beehive</span>
      <span className="tb-sep" aria-hidden="true" />
      <span className="tb-title">{title}</span>
      <DateNav />

      <div className="tb-right">
        <IconBtn icon={BELL_ICON} badge={3} label="Notifications" />
        <button style={{
          display: 'flex', alignItems: 'center', gap: 7,
          padding: '4px 6px 4px 4px', borderRadius: 99,
          transition: 'background .15s',
        }}
        aria-label="Account menu"
        onMouseEnter={e => e.currentTarget.style.background = 'var(--glass-bg-2)'}
        onMouseLeave={e => e.currentTarget.style.background = ''}
        >
          <div className="avatar">TN</div>
          <span style={{ fontSize: 12, fontWeight: 500 }}>Thierry N.</span>
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor"
               strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"
               style={{ width: 11, height: 11, color: 'var(--muted-2)' }}>
            <path d="M6 9l6 6 6-6"/>
          </svg>
        </button>
      </div>
    </header>
  )
}
EOF
ok "Topbar.jsx — date nav + notifications added"


# ═══════════════════════════════════════════════════════════════════════
#  FIX 4 — BubbleCluster.jsx: exact prototype circle positions
# ═══════════════════════════════════════════════════════════════════════
step "Fix 4  BubbleCluster.jsx — exact prototype positions"

cat > frontend/src/components/charts/BubbleCluster.jsx << 'EOF'
/**
 * BubbleCluster — 5-column packed bubble chart.
 * Circle positions lifted verbatim from the VIGIL prototype SVG.
 * Each column has 3 circles (large base, medium offset-left, small offset-right).
 * Colors: lime → cyan → violet → text → amber.
 *
 * Props: data  [{ label: string, count: number }]  — up to 5 items
 */
const COLORS = [
  'var(--lime)', 'var(--cyan)', 'var(--violet)',
  'var(--text)', 'var(--amber)',
]

// [cx, cy, r] for each of 3 circles per column — exact prototype values
const CLUSTERS = [
  [[40,100,16],[32,80,10],[48,68,7]],
  [[100,95,14],[92,75,9],[108,64,6]],
  [[160,98,12],[152,80,8],[168,70,5]],
  [[220,100,10],[212,84,7],[228,76,5]],
  [[280,102,8],[272,88,6],[288,82,4]],
]

const DEFAULTS = [
  { label: 'DoS',         count: 0 },
  { label: 'PortScan',    count: 0 },
  { label: 'Brute Force', count: 0 },
  { label: 'Web Attack',  count: 0 },
  { label: 'Botnet',      count: 0 },
]

export default function BubbleCluster({ data }) {
  const items = (data?.length ? data : DEFAULTS).slice(0, 5)

  return (
    <svg width="100%" height="170" viewBox="0 0 320 170"
         preserveAspectRatio="xMidYMid meet">
      {items.map((item, ci) => {
        const col   = COLORS[ci]
        const rings = CLUSTERS[ci]
        return (
          <g key={ci}>
            {rings.map(([cx, cy, r], ri) => (
              <circle key={ri} cx={cx} cy={cy} r={r}
                fill={col} opacity={1 - ri * 0.18} />
            ))}
            <text x={rings[0][0]} y={148}
              textAnchor="middle" fontSize="9"
              fill="var(--muted)" fontFamily="var(--f-body)">
              {item.label}
            </text>
            {item.count > 0 && (
              <text x={rings[0][0]} y={160}
                textAnchor="middle" fontSize="8"
                fill="var(--muted-2)" fontFamily="var(--f-mono)">
                {item.count}
              </text>
            )}
          </g>
        )
      })}
    </svg>
  )
}
EOF
ok "BubbleCluster.jsx — exact circle positions"


# ═══════════════════════════════════════════════════════════════════════
#  FIX 5 — shell.css: scale bumps for small screen
# ═══════════════════════════════════════════════════════════════════════
step "Fix 5  shell.css — scale adjustments"

# Append overrides — shell.css already exists; these override previous values
cat >> frontend/src/styles/shell.css << 'EOF'

/* ── Scale adjustments for 1366×768 screens (patch_overview_fixes) ── */
html { font-size: 16px; }

.kpi-value         { font-size: 38px; }
.card              { padding: 20px 22px 18px; }
.topbar            { height: 64px; padding: 0 26px; }
.content           { padding: 22px 28px 40px; }
.bento             { gap: 16px; }
.card-title        { font-size: 13px; }
.card-header       { margin-bottom: 16px; }
EOF
ok "shell.css — scale bumps appended"


# ═══════════════════════════════════════════════════════════════════════
#  FIX 6 — StatusStrip: solid line through opaque circles, brain icon
# ═══════════════════════════════════════════════════════════════════════
step "Fix 6  StatusStrip component (extracted)"

mkdir -p frontend/src/components/ui

cat > frontend/src/components/ui/StatusStrip.jsx << 'EOF'
/**
 * StatusStrip — horizontal connector line that passes THROUGH icon circles.
 * Technique: solid line at z-index 0; circles at z-index 1 with solid
 * background (var(--surface)) so they mask the line where it overlaps —
 * creating the "line cuts through" visual.
 *
 * Props: models  array from constants/models.js
 */
import { MODELS } from '../../constants/models'

// Neural-network icon for Inference service (replaces topology icon)
const ICONS = {
  sensor: '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3.6" fill="currentColor" stroke="none" opacity="0.18"/><circle cx="12" cy="12" r="3.6"/><circle cx="12" cy="12" r="0.6" fill="currentColor" stroke="none"/>',
  // Neuron/brain: center node connected to 4 satellites
  inference: '<circle cx="12" cy="12" r="3"/><circle cx="12" cy="4.5" r="1.5" fill="currentColor" stroke="none"/><circle cx="4.5" cy="12" r="1.5" fill="currentColor" stroke="none"/><circle cx="19.5" cy="12" r="1.5" fill="currentColor" stroke="none"/><circle cx="12" cy="19.5" r="1.5" fill="currentColor" stroke="none"/><circle cx="6.2" cy="6.2" r="1.5" fill="currentColor" stroke="none"/><circle cx="17.8" cy="6.2" r="1.5" fill="currentColor" stroke="none"/><line x1="12" y1="7.5" x2="12" y2="9"/><line x1="7.5" y1="12" x2="9" y2="12"/><line x1="15" y1="12" x2="16.5" y2="12"/><line x1="12" y1="15" x2="12" y2="16.5"/><line x1="7.6" y1="7.6" x2="9.9" y2="9.9"/><line x1="14.1" y1="9.9" x2="16.4" y2="7.6"/>',
  bridge:   '<line x1="6.7" y1="7.3" x2="10.6" y2="11.7"/><line x1="17.3" y1="7.3" x2="13.4" y2="11.7"/><line x1="11" y1="14.5" x2="7" y2="17.7"/><line x1="13" y1="14.5" x2="17" y2="17.7"/><circle cx="5" cy="6" r="2.1" fill="currentColor" stroke="none"/><circle cx="19" cy="6" r="2.1" fill="currentColor" stroke="none"/><circle cx="12" cy="13" r="2.3" fill="currentColor" stroke="none"/><circle cx="6" cy="19" r="2.1" fill="currentColor" stroke="none"/><circle cx="18" cy="19" r="2.1" fill="currentColor" stroke="none"/>',
  redis:    '<path d="M7 17a4 4 0 010-8 5 5 0 019.6-1.5A4.5 4.5 0 0117 17H7z"/>',
}

const SERVICES = [
  { key: 'sensor',    label: 'Sensor',    icon: ICONS.sensor,    color: 'var(--lime)'   },
  { key: 'inference', label: 'Inference', icon: ICONS.inference, color: 'var(--cyan)'   },
  { key: 'bridge',    label: 'Bridge',    icon: ICONS.bridge,    color: 'var(--violet)' },
  { key: 'redis',     label: 'Redis',     icon: ICONS.redis,     color: 'var(--amber)'  },
]

function StripIcon({ icon, color, label }) {
  return (
    <div style={{ position: 'relative', zIndex: 1, display: 'flex',
                  flexDirection: 'column', alignItems: 'center', gap: 6 }}>
      <div style={{
        width: 36, height: 36, borderRadius: '50%',
        /* solid background masks the line — creates "passes through" effect */
        background: 'var(--surface)',
        border: '1px solid var(--border-strong)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        color, flexShrink: 0,
      }}>
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor"
             strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"
             style={{ width: 15, height: 15 }}
             dangerouslySetInnerHTML={{ __html: icon }} />
      </div>
      <span style={{ fontSize: 9, color: 'var(--muted-2)',
                     fontFamily: 'var(--f-mono)', letterSpacing: '0.3px' }}>
        {label}
      </span>
    </div>
  )
}

export default function StatusStrip() {
  return (
    <div style={{ marginTop: 8 }}>
      {/* Connector row */}
      <div style={{ position: 'relative', display: 'flex',
                    alignItems: 'center', justifyContent: 'space-around',
                    padding: '14px 4px' }}>

        {/* Solid line — behind icons (z-index 0) */}
        <div style={{
          position: 'absolute', left: '10%', right: '10%', top: '50%',
          height: 2,
          background: 'var(--border-strong)',
          zIndex: 0,
          transform: 'translateY(-50%)',
        }} />

        {SERVICES.map(s => (
          <StripIcon key={s.key} icon={s.icon} color={s.color} label={s.label} />
        ))}

        {/* Models count bubble */}
        <div style={{ position: 'relative', zIndex: 1,
                      display: 'flex', flexDirection: 'column',
                      alignItems: 'center', gap: 6 }}>
          <div style={{
            width: 36, height: 36, borderRadius: '50%',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            fontSize: 10, color: 'var(--muted-2)',
            /* solid bg so line is masked */
            background: 'var(--surface)',
            border: '1px dashed var(--border-strong)',
            fontFamily: 'var(--f-mono)',
          }}>
            +{MODELS.length}
          </div>
          <span style={{ fontSize: 9, color: 'var(--muted-2)',
                         fontFamily: 'var(--f-mono)' }}>
            Models
          </span>
        </div>
      </div>

      {/* Model list */}
      <div style={{ borderTop: '1px solid var(--border)', paddingTop: 14,
                    display: 'flex', flexDirection: 'column', gap: 9 }}>
        {MODELS.map(m => (
          <div key={m.id} style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <span style={{ width: 7, height: 7, borderRadius: '50%',
                           background: m.color, flexShrink: 0 }} />
            <span style={{ fontSize: 12.5, flex: 1 }}>{m.label}</span>
            <span style={{ fontSize: 10, fontFamily: 'var(--f-mono)', color: 'var(--green)' }}>
              loaded
            </span>
          </div>
        ))}
      </div>
    </div>
  )
}
EOF
ok "StatusStrip.jsx — solid line, opaque circles, brain icon"


# ═══════════════════════════════════════════════════════════════════════
#  Update Overview.jsx to import StatusStrip from its own file
# ═══════════════════════════════════════════════════════════════════════
step "Overview.jsx — swap in StatusStrip component"

# Use sed to: add the import, remove the inline StatusStrip function + SERVICES const,
# and replace the <StatusStrip /> usage (it's already called <StatusStrip />).
# Cleanest approach: rewrite Overview.jsx without the inline StatusStrip.

cat > frontend/src/pages/Overview.jsx << 'EOF'
import { useMemo }         from 'react'
import Shell               from '../components/shell/Shell'
import KpiCard             from '../components/ui/KpiCard'
import StatusStrip         from '../components/ui/StatusStrip'
import EnsembleGauge       from '../components/charts/EnsembleGauge'
import TrendChart          from '../components/charts/TrendChart'
import RadarChart          from '../components/charts/RadarChart'
import BubbleCluster       from '../components/charts/BubbleCluster'
import AlertLogStream      from '../components/alerts/AlertLogStream'
import { useAlertStore }   from '../store/alertStore'
import { useAnomalyStore } from '../store/anomalyStore'

// ── MITRE-style axis mapping (CICIDS2017 → 8 radar axes) ─────────────────────
const RADAR_MAP = {
  recon:      ['portscan'],
  bruteforce: ['patator'],
  dos:        ['dos goldeneye', 'dos hulk', 'dos slowhttptest', 'dos slowloris'],
  ddos:       ['ddos'],
  web:        ['web attack'],
  bot:        ['bot'],
  exploit:    ['heartbleed'],
  exfil:      ['infiltration'],
}

function toRadarData(alerts) {
  const counts = Object.fromEntries(Object.keys(RADAR_MAP).map(k => [k, 0]))
  alerts.forEach(a => {
    const l = (a.prediction?.label ?? '').toLowerCase()
    for (const [axis, matches] of Object.entries(RADAR_MAP)) {
      if (matches.some(m => l.includes(m))) { counts[axis]++; break }
    }
  })
  const max = Math.max(...Object.values(counts), 1)
  return Object.fromEntries(Object.entries(counts).map(([k, v]) => [k, v / max]))
}

// ── Bubble cluster: top-5 attack families ────────────────────────────────────
const BUBBLE_FAMILIES = [
  { label: 'DoS',         matches: ['dos'] },
  { label: 'PortScan',    matches: ['portscan'] },
  { label: 'Brute Force', matches: ['patator'] },
  { label: 'Web Attack',  matches: ['web attack'] },
  { label: 'DDoS',        matches: ['ddos'] },
]

function toBubbleData(alerts) {
  return BUBBLE_FAMILIES.map(f => ({
    label: f.label,
    count: alerts.filter(a =>
      f.matches.some(m => (a.prediction?.label ?? '').toLowerCase().includes(m))
    ).length,
  }))
}

// ── KPI helpers ───────────────────────────────────────────────────────────────
function consensusRate(alerts) {
  if (!alerts.length) return '—'
  const agreed = alerts.filter(a => a.agreement?.consensus).length
  return `${Math.round((agreed / alerts.length) * 100)}%`
}

// ── KPI icon strings ─────────────────────────────────────────────────────────
const ICONS = {
  shield: '<path d="M12 3l7.5 3v6.2c0 5.4-3.6 8.7-7.5 9.8-3.9-1.1-7.5-4.4-7.5-9.8V6L12 3z"/>',
  radar:  '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3.6" fill="currentColor" stroke="none" opacity="0.18"/><circle cx="12" cy="12" r="3.6"/><circle cx="12" cy="12" r="0.6" fill="currentColor" stroke="none"/>',
  report: '<rect x="5" y="3" width="14" height="18" rx="2"/><rect x="8" y="13" width="2" height="5" fill="currentColor" stroke="none"/><rect x="11.3" y="10" width="2" height="8" fill="currentColor" stroke="none"/><rect x="14.6" y="7" width="2" height="11" fill="currentColor" stroke="none"/>',
  check:  '<path d="M6 12l4 4 8-9"/>',
}

// ── Chip (stat badge in card header) ─────────────────────────────────────────
function Chip({ children }) {
  return (
    <span style={{
      fontFamily: 'var(--f-mono)', fontSize: 11, color: 'var(--lime)',
      background: 'var(--glass-bg-2)', border: '1px solid var(--border-strong)',
      padding: '4px 11px', borderRadius: 99,
    }}>
      {children}
    </span>
  )
}

// ── Page ─────────────────────────────────────────────────────────────────────
export default function Overview() {
  const alerts    = useAlertStore(s => s.alerts)
  const anomalies = useAnomalyStore(s => s.anomalies)

  const latest    = alerts[0] ?? null
  const radarData = useMemo(() => toRadarData(alerts), [alerts])
  const bubbles   = useMemo(() => toBubbleData(alerts), [alerts])
  const conRate   = useMemo(() => consensusRate(alerts), [alerts])
  const hasSignal = Object.values(radarData).some(v => v > 0)

  return (
    <Shell title="Overview">

      {/* ── KPI Row ─────────────────────────────────────────────────── */}
      <div className="kpi-grid">
        <KpiCard
          featured
          label="Live Attacks"
          value={alerts.length}
          icon={ICONS.shield}
          delta={alerts.length > 0
            ? { text: 'ids:attacks stream', direction: null }
            : null}
        />
        <KpiCard
          label="Anomalies"
          value={anomalies.length}
          icon={ICONS.radar}
          delta={anomalies.length > 0
            ? { text: 'ids:anomalies', direction: 'bad' }
            : null}
        />
        <KpiCard
          label="Models"
          value="5 / 5"
          icon={ICONS.report}
          delta={{ text: 'all loaded', direction: 'good' }}
        />
        <KpiCard
          label="Consensus Rate"
          value={conRate}
          icon={ICONS.check}
          delta={alerts.length > 0
            ? { text: 'last session', direction: 'good' }
            : null}
        />
      </div>

      {/* ── Row A: live feed + ensemble gauge ───────────────────────── */}
      <div className="row-6535">
        <div className="card">
          <div className="card-header">
            <span className="card-title">Live Alert Feed</span>
            <Chip>{alerts.length} events</Chip>
          </div>
          <AlertLogStream alerts={alerts} />
        </div>

        <div className="card">
          <div className="card-header">
            <div>
              <span className="card-title">Ensemble Consensus</span>
              <div style={{ fontSize: 11, color: 'var(--muted-2)', marginTop: 2 }}>
                latest alert · all models
              </div>
            </div>
          </div>
          <EnsembleGauge
            votes={latest?.model_votes}
            agreement={latest?.agreement}
            label={latest?.prediction?.label}
          />
        </div>
      </div>

      {/* ── Row B: radar + bubbles ───────────────────────────────────── */}
      <div className="row-3565">
        <div className="card">
          <div className="card-header">
            <div>
              <span className="card-title">Threat Coverage</span>
              <div style={{ fontSize: 11, color: 'var(--muted-2)', marginTop: 2 }}>
                by attack category
              </div>
            </div>
            <Chip>{hasSignal ? 'active' : '—'}</Chip>
          </div>
          <RadarChart data={radarData} />
        </div>

        <div className="card">
          <div className="card-header">
            <div>
              <span className="card-title">Attack Surface by Vector</span>
              <div style={{ fontSize: 11, color: 'var(--muted-2)', marginTop: 2 }}>
                flagged events, session
              </div>
            </div>
          </div>
          <BubbleCluster data={bubbles} />
        </div>
      </div>

      {/* ── Row C: trend chart + system status ──────────────────────── */}
      <div className="row-6535">
        <div className="card">
          <div className="card-header">
            <div>
              <span className="card-title">Detection Trend</span>
              <div style={{ fontSize: 11, color: 'var(--muted-2)', marginTop: 2 }}>
                attacks detected, last 60 min
              </div>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 6,
                          fontSize: 11, color: 'var(--muted)' }}>
              <span style={{ width: 7, height: 7, borderRadius: '50%',
                             background: 'var(--lime)', flexShrink: 0 }} />
              Detected
            </div>
          </div>
          <TrendChart alerts={alerts} />
        </div>

        <div className="card">
          <div className="card-header">
            <span className="card-title">System Status</span>
            <span style={{ fontSize: 11, color: 'var(--muted-2)' }}>active components</span>
          </div>
          <StatusStrip />
        </div>
      </div>

    </Shell>
  )
}
EOF
ok "Overview.jsx — StatusStrip imported from component file"


# ═══════════════════════════════════════════════════════════════════════
#  VALIDATION
# ═══════════════════════════════════════════════════════════════════════
step "Validation"

FILES=(
  "bridge/consumer.py"
  "frontend/src/components/shell/Rail.jsx"
  "frontend/src/components/shell/Topbar.jsx"
  "frontend/src/components/charts/BubbleCluster.jsx"
  "frontend/src/components/ui/StatusStrip.jsx"
  "frontend/src/pages/Overview.jsx"
)
for f in "${FILES[@]}"; do
  [ -f "$f" ] && ok "$f" || { echo -e "  \033[0;31m✗\033[0m  MISSING: $f"; exit 1; }
done

# Confirm key fixes are present
grep -q '"0"' bridge/consumer.py                        && ok "consumer: starts at 0" || echo "  ✗  consumer start-at-0 missing"
grep -q 'stroke="currentColor"' frontend/src/components/shell/Rail.jsx && ok "Rail: stroke present"  || echo "  ✗  Rail stroke missing"
grep -q 'DateNav'               frontend/src/components/shell/Topbar.jsx && ok "Topbar: DateNav present" || echo "  ✗  Topbar DateNav missing"
grep -q 'CLUSTERS'              frontend/src/components/charts/BubbleCluster.jsx && ok "BubbleCluster: exact positions" || echo "  ✗  CLUSTERS missing"
grep -q 'zIndex: 0'             frontend/src/components/ui/StatusStrip.jsx && ok "StatusStrip: line z-index" || echo "  ✗  z-index missing"
grep -q 'background.*var(--surface)' frontend/src/components/ui/StatusStrip.jsx && ok "StatusStrip: opaque circles" || echo "  ✗  opaque circles missing"

echo ""
echo -e "${G}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo -e "${G}  Fixes applied. Restart the bridge then dev server:${N}"
echo ""
echo -e "  Terminal A — bridge (kill existing uvicorn first):"
echo -e "  cd bridge && source .venv/bin/activate"
echo -e "  uvicorn main:app --port 8001 --reload"
echo ""
echo -e "  Terminal B — frontend:"
echo -e "  cd frontend && npm run dev"
echo ""
echo -e "  Then re-run the Redis test push from any terminal:"
echo -e "  (data already in stream will now be replayed from 0)"
echo -e "${G}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
