#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  Beehive IDS — Overview page patch
#  Run from repo root: bash scripts/patch_overview.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

G='\033[0;32m'; B='\033[0;34m'; N='\033[0m'
ok()   { echo -e "  ${G}✓${N}  $*"; }
step() { echo -e "\n${B}━━━ $* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"; }

mkdir -p \
  frontend/src/store \
  frontend/src/providers \
  frontend/src/components/{ui,charts,alerts}


# ═══════════════════════════════════════════════════════════════════════
#  STORES
# ═══════════════════════════════════════════════════════════════════════
step "Stores"

cat > frontend/src/store/alertStore.js << 'EOF'
import { create } from 'zustand'

const RING = 200   // max supervised-attack alerts in memory

export const useAlertStore = create((set) => ({
  alerts: [],
  push:  (a) => set((s) => ({ alerts: [a, ...s.alerts].slice(0, RING) })),
  clear: ()  => set({ alerts: [] }),
}))
EOF
ok "alertStore.js"

cat > frontend/src/store/anomalyStore.js << 'EOF'
import { create } from 'zustand'

// AE flags ~75% of local-benign (domain-shift finding) — keep a larger window.
const RING = 500

export const useAnomalyStore = create((set) => ({
  anomalies: [],
  push:  (a) => set((s) => ({ anomalies: [a, ...s.anomalies].slice(0, RING) })),
  clear: ()  => set({ anomalies: [] }),
}))
EOF
ok "anomalyStore.js"


# ═══════════════════════════════════════════════════════════════════════
#  LIVE DATA PROVIDER  — mounts SSE once at app root
# ═══════════════════════════════════════════════════════════════════════
step "LiveDataProvider"

cat > frontend/src/providers/LiveDataProvider.jsx << 'EOF'
/**
 * Mounts both SSE streams once when the app loads.
 * All pages read the shared Zustand stores — no per-page stream setup.
 */
import { useEffect } from 'react'
import { createStream }    from '../lib/stream'
import { useAlertStore }   from '../store/alertStore'
import { useAnomalyStore } from '../store/anomalyStore'

export default function LiveDataProvider({ children }) {
  const pushAlert   = useAlertStore(s => s.push)
  const pushAnomaly = useAnomalyStore(s => s.push)

  useEffect(() => {
    const unA = createStream('/stream/attacks',   'attack',  pushAlert,
                             m => console.warn('[attacks stream]', m))
    const unB = createStream('/stream/anomalies', 'anomaly', pushAnomaly,
                             m => console.warn('[anomalies stream]', m))
    return () => { unA(); unB() }
  }, [pushAlert, pushAnomaly])

  return children
}
EOF
ok "LiveDataProvider.jsx"


# ═══════════════════════════════════════════════════════════════════════
#  APP.JSX — add LiveDataProvider wrapper
# ═══════════════════════════════════════════════════════════════════════
step "App.jsx"

cat > frontend/src/App.jsx << 'EOF'
import { BrowserRouter, Routes, Route } from 'react-router-dom'
import LiveDataProvider from './providers/LiveDataProvider'
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
      <LiveDataProvider>
        <Routes>
          <Route path="/"         element={<Overview />} />
          <Route path="/topology" element={<Topology />} />
          <Route path="/alerts"   element={<Alerts />}   />
          <Route path="/flows"    element={<Flows />}    />
          <Route path="/models"   element={<Models />}   />
          <Route path="/research" element={<Research />} />
          <Route path="/settings" element={<Settings />} />
        </Routes>
      </LiveDataProvider>
    </BrowserRouter>
  )
}
EOF
ok "App.jsx"


# ═══════════════════════════════════════════════════════════════════════
#  SHELL.CSS ADDENDUM — kpi-top row (missed in setup)
# ═══════════════════════════════════════════════════════════════════════
step "shell.css patch (kpi-top)"

# Append only if kpi-top not already present
if ! grep -q 'kpi-top' frontend/src/styles/shell.css; then
cat >> frontend/src/styles/shell.css << 'EOF'

/* ── KPI top row (label + icon, added by patch_overview) ── */
.kpi-top {
  display: flex; align-items: center; justify-content: space-between;
  margin-bottom: 4px;
}
EOF
fi
ok "kpi-top added to shell.css"


# ═══════════════════════════════════════════════════════════════════════
#  UI: KpiCard
# ═══════════════════════════════════════════════════════════════════════
step "UI components"

cat > frontend/src/components/ui/KpiCard.jsx << 'EOF'
/**
 * KpiCard
 * Props:
 *   featured  bool     — solid lime block; one per page max
 *   label     string
 *   value     string|number
 *   delta     { text: string, direction: 'good'|'bad'|'crit'|null }
 *   icon      string   — SVG path data for a 24x24 icon
 */
export default function KpiCard({ featured, label, value, delta, icon }) {
  return (
    <div className={`card kpi${featured ? ' featured' : ''}`}>
      <div className="kpi-top">
        <span className="kpi-label">{label}</span>
        {icon && (
          <span className="kpi-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor"
                 strokeLinecap="round" strokeLinejoin="round"
                 style={{ width: 15, height: 15 }}
                 dangerouslySetInnerHTML={{ __html: icon }} />
          </span>
        )}
      </div>
      <div className="kpi-value">{value}</div>
      {delta && (
        <div className="kpi-foot">
          <span className={`delta${delta.direction ? ' ' + delta.direction : ''}`}>
            {delta.text}
          </span>
        </div>
      )}
    </div>
  )
}
EOF
ok "KpiCard.jsx"


# ═══════════════════════════════════════════════════════════════════════
#  CHART: EnsembleGauge  — 5 concentric arcs, one per model
# ═══════════════════════════════════════════════════════════════════════
step "Charts"

cat > frontend/src/components/charts/EnsembleGauge.jsx << 'EOF'
/**
 * EnsembleGauge — featured visualisation.
 * Five concentric arcs, outer→inner: RF → XGB → LGB → CNN → AE.
 * Arc fill % = model confidence on the latest alert.
 * Ring closure = consensus. AE: fill = anomaly_score / threshold, capped at 1.
 *
 * Props:
 *   votes      object   model_votes from /predict (or null when idle)
 *   agreement  object   { consensus, agreeing, total }
 *   label      string   predicted attack label
 */
import { MODELS, AE_THRESHOLD } from '../../constants/models'

const CX = 110, CY = 110
const RADII = [90, 75, 60, 45, 30]   // RF → XGB → LGB → CNN → AE
const SW    = 7

function Arc({ r, pct, color, animate }) {
  const circ = 2 * Math.PI * r
  const dash  = circ * Math.min(Math.max(pct, 0), 1)
  return (
    <>
      <circle cx={CX} cy={CY} r={r}
        fill="none" stroke="var(--border-strong)" strokeWidth={SW} />
      <circle cx={CX} cy={CY} r={r}
        fill="none" stroke={color} strokeWidth={SW} strokeLinecap="round"
        strokeDasharray={`${dash.toFixed(2)} ${circ.toFixed(2)}`}
        transform={`rotate(-90 ${CX} ${CY})`}
        style={{ transition: animate ? 'stroke-dasharray 0.75s cubic-bezier(.4,0,.2,1)' : 'none' }} />
    </>
  )
}

function arcPct(modelId, votes) {
  if (!votes) return 0
  const v = votes[modelId]
  if (!v) return 0
  if (modelId === 'autoencoder') {
    return Math.min((v.anomaly_score ?? 0) / AE_THRESHOLD, 1)
  }
  return v.confidence ?? 0
}

export default function EnsembleGauge({ votes, agreement, label }) {
  const hasData  = !!votes
  const arcs     = MODELS.map((m, i) => ({ ...m, r: RADII[i], pct: arcPct(m.id, votes) }))
  const agreeStr = agreement ? `${agreement.agreeing}/${agreement.total} agree` : 'awaiting'
  const isAttack = hasData && !!label && label !== 'Benign'

  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 16 }}>
      <svg width="100%" viewBox="0 0 220 220" style={{ maxWidth: 220 }}>
        {arcs.map(arc => (
          <Arc key={arc.id} r={arc.r} pct={arc.pct} color={arc.color} animate={hasData} />
        ))}

        {/* Centre: attack label */}
        <text x={CX} y={CY - 9}
          textAnchor="middle" dominantBaseline="middle"
          fontFamily="var(--f-display)" fontSize="17" fontWeight="600"
          fill={isAttack ? 'var(--red)' : hasData ? 'var(--green)' : 'var(--muted-2)'}>
          {hasData ? (label ?? '?') : '—'}
        </text>

        {/* Centre: agreement */}
        <text x={CX} y={CY + 12}
          textAnchor="middle"
          fontFamily="var(--f-mono)" fontSize="9.5"
          fill={agreement?.consensus ? 'var(--lime)' : 'var(--muted)'}>
          {agreeStr}
        </text>
      </svg>

      {/* Legend row */}
      <div style={{
        display: 'flex', flexWrap: 'wrap', gap: '6px 14px',
        justifyContent: 'center', paddingBottom: 4,
      }}>
        {arcs.map(arc => (
          <span key={arc.id} style={{ display: 'flex', alignItems: 'center', gap: 5,
            fontSize: 10, fontFamily: 'var(--f-mono)', color: 'var(--muted)' }}>
            <span style={{ width: 7, height: 7, borderRadius: '50%',
              background: arc.color, flexShrink: 0 }} />
            {arc.short}
            <span style={{ color: 'var(--muted-2)' }}>
              {hasData ? `${(arc.pct * 100).toFixed(0)}%` : '--'}
            </span>
          </span>
        ))}
      </div>
    </div>
  )
}
EOF
ok "EnsembleGauge.jsx"

cat > frontend/src/components/charts/TrendChart.jsx << 'EOF'
/**
 * TrendChart — gradient-fill area chart with glow line.
 * Buckets the last 60 min of alerts into 12 × 5-min slots.
 * Shows a flat zero line when no alerts have arrived yet.
 *
 * Props: alerts (array from useAlertStore)
 */
import { useMemo } from 'react'

const W = 600, H = 200
const X0 = 30, X1 = 570, Y0 = 22, Y1 = 185
const N_BUCKETS    = 12
const WINDOW_MS    = 60 * 60 * 1000   // 60 min
const BUCKET_MS    = WINDOW_MS / N_BUCKETS

function bucket(alerts) {
  const now = Date.now()
  const b   = Array(N_BUCKETS).fill(0)
  alerts.forEach(a => {
    const ts  = new Date(a.timestamp).getTime()
    if (isNaN(ts)) return
    const age = now - ts
    if (age < 0 || age >= WINDOW_MS) return
    const idx = N_BUCKETS - 1 - Math.floor(age / BUCKET_MS)
    if (idx >= 0 && idx < N_BUCKETS) b[idx]++
  })
  return b
}

function toPoints(counts) {
  const max = Math.max(...counts, 1)
  return counts.map((v, i) => {
    const x = X0 + (i / (N_BUCKETS - 1)) * (X1 - X0)
    const y = Y1 - (v / max) * (Y1 - Y0)
    return [+x.toFixed(1), +y.toFixed(1)]
  })
}

function ptStr(pts) {
  return pts.map(([x, y]) => `${x},${y}`).join(' ')
}

const LABELS = ['−60m','−55m','−50m','−45m','−40m','−35m','−30m','−25m','−20m','−15m','−10m','Now']

export default function TrendChart({ alerts }) {
  const counts = useMemo(() => bucket(alerts), [alerts])
  const pts    = useMemo(() => toPoints(counts), [counts])

  const polyStr  = ptStr(pts)
  const areaStr  = `${polyStr} ${X1},${Y1} ${X0},${Y1}`

  // Peak point for tooltip
  const peakIdx  = counts.indexOf(Math.max(...counts))
  const [px, py] = pts[peakIdx] ?? [X1, Y1]
  const hasPeak  = counts[peakIdx] > 0

  const gridYs = [Y0, (Y0 + Y1) / 2, Y1]

  return (
    <div style={{ position: 'relative', marginTop: 4 }}>
      <svg viewBox={`0 0 ${W} ${H}`} width="100%" height="190" preserveAspectRatio="none">
        <defs>
          <linearGradient id="trendGrad" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%"   stopColor="var(--lime)" stopOpacity="0.32" />
            <stop offset="100%" stopColor="var(--lime)" stopOpacity="0" />
          </linearGradient>
          <filter id="trendGlow" x="-20%" y="-20%" width="140%" height="140%">
            <feGaussianBlur stdDeviation="3.5" />
          </filter>
        </defs>

        {/* Grid lines */}
        {gridYs.map(y => (
          <line key={y} x1={X0} y1={y} x2={X1} y2={y}
            stroke="var(--border)" strokeWidth="1" />
        ))}

        {/* Peak marker */}
        {hasPeak && (
          <line x1={px} y1={Y0} x2={px} y2={Y1}
            stroke="var(--border-strong)" strokeWidth="1" strokeDasharray="3 4" />
        )}

        {/* Area fill */}
        <polygon points={areaStr} fill="url(#trendGrad)" />

        {/* Glow line (blurred duplicate) */}
        <polyline points={polyStr} fill="none"
          stroke="var(--lime)" strokeWidth="5" opacity="0.38"
          strokeLinecap="round" strokeLinejoin="round"
          filter="url(#trendGlow)" />

        {/* Crisp line */}
        <polyline points={polyStr} fill="none"
          stroke="var(--lime)" strokeWidth="2.2"
          strokeLinecap="round" strokeLinejoin="round" />

        {/* Peak dot */}
        {hasPeak && (
          <circle cx={px} cy={py} r="3.5"
            fill="var(--bg)" stroke="var(--lime)" strokeWidth="2" />
        )}
      </svg>

      {/* Floating tooltip at peak */}
      {hasPeak && (
        <div style={{
          position: 'absolute',
          left: `${((px - X0) / (X1 - X0) * 100).toFixed(1)}%`,
          top:  `${((py - Y0) / (Y1 - Y0) * 100).toFixed(1)}%`,
          transform: 'translate(-50%, -130%)',
          background: 'var(--surface-2)', border: '1px solid var(--border-strong)',
          borderRadius: 10, padding: '6px 11px', whiteSpace: 'nowrap', pointerEvents: 'none',
        }}>
          <div style={{ fontFamily: 'var(--f-mono)', fontSize: 12, fontWeight: 600, color: 'var(--lime)' }}>
            {counts[peakIdx]} events
          </div>
          <div style={{ fontSize: 9, color: 'var(--muted-2)', marginTop: 1 }}>
            Peak · {LABELS[peakIdx]}
          </div>
        </div>
      )}

      {/* X-axis labels */}
      <div style={{
        display: 'flex', justifyContent: 'space-between',
        marginTop: 6, padding: '0 2px',
      }}>
        {LABELS.filter((_, i) => i % 2 === 0).map(l => (
          <span key={l} style={{ fontSize: 9.5, color: 'var(--muted-2)', fontFamily: 'var(--f-mono)' }}>
            {l}
          </span>
        ))}
      </div>
    </div>
  )
}
EOF
ok "TrendChart.jsx"

cat > frontend/src/components/charts/RadarChart.jsx << 'EOF'
/**
 * RadarChart — 8-axis threat-coverage polygon.
 * Axes map CICIDS2017 attack categories to ATT&CK-inspired tactics.
 * Values are normalised counts from the alert store (0–1 scale).
 *
 * Props: data  { [axisId]: number (0-1) }
 */

// Precomputed octagon points from VIGIL-THEME-SKILL (cx=110 cy=110)
const OUTER = '110,25 170.1,49.9 195,110 170.1,170.1 110,195 49.9,170.1 25,110 49.9,49.9'
const MID   = '110,54 149.6,70.4 166,110 149.6,149.6 110,166 70.4,149.6 54,110 70.4,70.4'
const INNER = '110,82 129.8,90.2 138,110 129.8,129.8 110,138 90.2,129.8 82,110 90.2,90.2'

const CX = 110, CY = 110, R = 85

// 8 axes in order: starting top (−90°), clockwise
const AXES = [
  { id: 'recon',    label: 'Recon',     anchor: 'middle', dx: 0,   dy: -6  },
  { id: 'bruteforce', label: 'Brute Force', anchor: 'start', dx: 5,  dy: 0   },
  { id: 'dos',      label: 'DoS',       anchor: 'start', dx: 5,   dy: 5   },
  { id: 'ddos',     label: 'DDoS',      anchor: 'start', dx: 5,   dy: 5   },
  { id: 'web',      label: 'Web Attack',  anchor: 'middle', dx: 0, dy: 10  },
  { id: 'bot',      label: 'Botnet',    anchor: 'end',   dx: -5,  dy: 5   },
  { id: 'exploit',  label: 'Exploit',   anchor: 'end',   dx: -5,  dy: 5   },
  { id: 'exfil',    label: 'Exfil',     anchor: 'end',   dx: -5,  dy: 0   },
]

// Compute a point on the radar for a given axis index and radius fraction (0-1)
function radarPt(axisIdx, frac) {
  const angle = -Math.PI / 2 + axisIdx * (2 * Math.PI / 8)
  const r     = R * frac
  return [CX + r * Math.cos(angle), CY + r * Math.sin(angle)]
}

// Label position — just outside the outer ring
function labelPt(axisIdx, axis) {
  const [x, y] = radarPt(axisIdx, 1.18)
  return [x + axis.dx, y + axis.dy]
}

export default function RadarChart({ data = {} }) {
  const dataPts = AXES.map((_, i) => radarPt(i, data[AXES[i].id] ?? 0))
  const dataStr = dataPts.map(([x, y]) => `${x.toFixed(1)},${y.toFixed(1)}`).join(' ')

  return (
    <div style={{ display: 'flex', justifyContent: 'center' }}>
      <svg width="220" height="220" viewBox="0 0 220 220">
        {/* Grid rings */}
        <polygon points={OUTER} fill="none" stroke="var(--border-strong)" strokeWidth="1" />
        <polygon points={MID}   fill="none" stroke="var(--border)"        strokeWidth="1" />
        <polygon points={INNER} fill="none" stroke="var(--border)"        strokeWidth="1" />

        {/* Axis spokes */}
        {AXES.map((_, i) => {
          const [ox, oy] = radarPt(i, 1)
          return (
            <line key={i} x1={CX} y1={CY} x2={ox.toFixed(1)} y2={oy.toFixed(1)}
              stroke="var(--border)" strokeWidth="1" />
          )
        })}

        {/* Data polygon */}
        <polygon points={dataStr}
          fill="var(--lime)" fillOpacity="0.16"
          stroke="var(--lime)" strokeWidth="1.8" />

        {/* Data dots */}
        {dataPts.map(([x, y], i) => (
          <circle key={i} cx={x.toFixed(1)} cy={y.toFixed(1)} r="2.8"
            fill="var(--lime)" />
        ))}

        {/* Axis labels */}
        {AXES.map((ax, i) => {
          const [lx, ly] = labelPt(i, ax)
          return (
            <text key={ax.id} x={lx.toFixed(1)} y={ly.toFixed(1)}
              textAnchor={ax.anchor}
              fontSize="7" letterSpacing="0.4"
              textTransform="uppercase"
              fill="var(--muted-2)"
              fontFamily="var(--f-body)"
              style={{ textTransform: 'uppercase' }}>
              {ax.label}
            </text>
          )
        })}
      </svg>
    </div>
  )
}
EOF
ok "RadarChart.jsx"

cat > frontend/src/components/charts/BubbleCluster.jsx << 'EOF'
/**
 * BubbleCluster — packed bubble chart for attack surface by vector.
 * Replaces a donut; 5 columns, 3 circles per column, decreasing radius.
 * Colors cycle lime → cyan → violet → off-white → amber.
 *
 * Props: data  [{ label: string, count: number }]  — up to 5 items
 */
const COLS   = [40, 100, 160, 220, 280]   // x centers in 320-wide viewBox
const COLORS = [
  'var(--lime)', 'var(--cyan)', 'var(--violet)',
  'var(--text)', 'var(--amber)',
]
const RADII3 = [16, 10, 7]   // 3 circles per column: largest → smallest

const DEFAULTS = [
  { label: 'DoS',        count: 0 },
  { label: 'PortScan',   count: 0 },
  { label: 'Brute Force',count: 0 },
  { label: 'Web Attack', count: 0 },
  { label: 'Botnet',     count: 0 },
]

export default function BubbleCluster({ data }) {
  const items = (data?.length ? data : DEFAULTS).slice(0, 5)

  return (
    <svg width="100%" height="170" viewBox="0 0 320 170" preserveAspectRatio="xMidYMid meet">
      {items.map((item, ci) => {
        const cx  = COLS[ci]
        const col = COLORS[ci]
        return (
          <g key={ci}>
            {RADII3.map((r, ri) => (
              <circle key={ri}
                cx={cx}
                cy={100 - ri * (RADII3[0] * 1.1 - r * 0.4)}
                r={r}
                fill={col}
                opacity={1 - ri * 0.2}
              />
            ))}
            <text x={cx} y={148}
              textAnchor="middle" fontSize="9"
              fill="var(--muted)" fontFamily="var(--f-body)">
              {item.label}
            </text>
            {item.count > 0 && (
              <text x={cx} y={160}
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
ok "BubbleCluster.jsx"


# ═══════════════════════════════════════════════════════════════════════
#  ALERT LOG STREAM
# ═══════════════════════════════════════════════════════════════════════
step "AlertLogStream"

cat > frontend/src/components/alerts/AlertLogStream.jsx << 'EOF'
/**
 * AlertLogStream — vertical event log feed.
 * Circular icon per row, connected by a thin line; mono metadata.
 * Severity colour = icon only, never a background wash.
 *
 * Props: alerts  array  — last N alerts from useAlertStore
 */
import { fmt }         from '../../lib/format'
import { severityOf }  from '../../constants/attacks'

const ALERT_ICON = '<circle cx="12" cy="12" r="8.5"/><line x1="12" y1="8" x2="12" y2="13"/><circle cx="12" cy="16.3" r="0.5" fill="currentColor" stroke="none"/>'
const CHECK_ICON = '<path d="M6 12l4 4 8-9"/>'

function severityClass(sev) {
  if (sev === 'critical' || sev === 'high') return 'crit'
  if (sev === 'medium')                     return 'warn'
  return 'ok'
}

function LogRow({ alert, isLast }) {
  const label = alert.prediction?.label ?? 'Unknown'
  const sev   = severityOf(label)
  const cls   = severityClass(sev)
  const icon  = cls === 'ok' ? CHECK_ICON : ALERT_ICON

  return (
    <div className="log-row">
      <div className="log-rail">
        <span className={`log-icon ${cls}`}>
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor"
               strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"
               style={{ width: 11, height: 11 }}
               dangerouslySetInnerHTML={{ __html: icon }} />
        </span>
        {!isLast && <span className="log-line" />}
      </div>
      <div className="log-body">
        <div className="log-top">
          <span className="log-title">{label}</span>
          <span className="log-time" style={{ fontFamily: 'var(--f-mono)', fontSize: 10, color: 'var(--muted-2)', flexShrink: 0 }}>
            {fmt.time(alert.timestamp)}
          </span>
        </div>
        <div className="log-meta">
          {alert.identity
            ? fmt.flow(alert.identity)
            : alert.flow_id ?? '—'
          }
          {' · '}
          <span style={{ color: 'var(--lime)' }}>
            {(alert.prediction?.confidence != null)
              ? fmt.pct(alert.prediction.confidence)
              : ''}
          </span>
        </div>
      </div>
    </div>
  )
}

export default function AlertLogStream({ alerts, maxRows = 6 }) {
  const rows = alerts.slice(0, maxRows)

  if (rows.length === 0) {
    return (
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        height: 140, color: 'var(--muted-2)',
        fontFamily: 'var(--f-mono)', fontSize: 12,
      }}>
        no alerts — sensor idle
      </div>
    )
  }

  return (
    <div className="log">
      {rows.map((a, i) => (
        <LogRow key={a.flow_id ?? i} alert={a} isLast={i === rows.length - 1} />
      ))}
    </div>
  )
}
EOF
ok "AlertLogStream.jsx"


# ═══════════════════════════════════════════════════════════════════════
#  OVERVIEW PAGE
# ═══════════════════════════════════════════════════════════════════════
step "Overview.jsx"

cat > frontend/src/pages/Overview.jsx << 'EOF'
/**
 * Overview — landing page of the Beehive dashboard.
 *
 * Layout (bento rows):
 *   KPI row    — Live Attacks (featured) · Anomalies · Models · Consensus rate
 *   Row A      — Live Alert Feed (log stream) + Ensemble Consensus Gauge
 *   Row B      — Threat Coverage Radar + Attack Surface Bubble Cluster
 *   Row C      — Detection Trend + System Status strip
 */
import { useMemo }         from 'react'
import Shell               from '../components/shell/Shell'
import KpiCard             from '../components/ui/KpiCard'
import EnsembleGauge       from '../components/charts/EnsembleGauge'
import TrendChart          from '../components/charts/TrendChart'
import RadarChart          from '../components/charts/RadarChart'
import BubbleCluster       from '../components/charts/BubbleCluster'
import AlertLogStream      from '../components/alerts/AlertLogStream'
import { useAlertStore }   from '../store/alertStore'
import { useAnomalyStore } from '../store/anomalyStore'
import { MODELS }          from '../constants/models'

// ── MITRE-style axis mapping for radar ───────────────────────────────────────
const RADAR_MAP = {
  recon:      ['portscan'],
  bruteforce: ['patator'],
  dos:        ['dos goldenye', 'dos hulk', 'dos slowhttptest', 'dos slowloris'],
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

// ── Bubble cluster: top-5 attack types by count ──────────────────────────────
const BUBBLE_FAMILIES = [
  { id: 'dos',        label: 'DoS',         matches: ['dos'] },
  { id: 'scan',       label: 'PortScan',    matches: ['portscan'] },
  { id: 'bruteforce', label: 'Brute Force', matches: ['patator'] },
  { id: 'web',        label: 'Web Attack',  matches: ['web attack'] },
  { id: 'ddos',       label: 'DDoS',        matches: ['ddos'] },
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

// ── Static system-status strip ────────────────────────────────────────────────
const SERVICES = [
  { label: 'Sensor',    icon: '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3.6" fill="currentColor" stroke="none" opacity="0.18"/><circle cx="12" cy="12" r="3.6"/><circle cx="12" cy="12" r="0.6" fill="currentColor" stroke="none"/>',   color: 'var(--lime)' },
  { label: 'Inference', icon: '<rect x="5" y="3" width="14" height="18" rx="2"/><rect x="8" y="13" width="2" height="5" fill="currentColor" stroke="none"/><rect x="11.3" y="10" width="2" height="8" fill="currentColor" stroke="none"/><rect x="14.6" y="7" width="2" height="11" fill="currentColor" stroke="none"/>',     color: 'var(--cyan)'  },
  { label: 'Bridge',    icon: '<line x1="6.7" y1="7.3" x2="10.6" y2="11.7"/><line x1="17.3" y1="7.3" x2="13.4" y2="11.7"/><line x1="11" y1="14.5" x2="7" y2="17.7"/><line x1="13" y1="14.5" x2="17" y2="17.7"/><circle cx="5" cy="6" r="2.1" fill="currentColor" stroke="none"/><circle cx="19" cy="6" r="2.1" fill="currentColor" stroke="none"/><circle cx="12" cy="13" r="2.3" fill="currentColor" stroke="none"/><circle cx="6" cy="19" r="2.1" fill="currentColor" stroke="none"/><circle cx="18" cy="19" r="2.1" fill="currentColor" stroke="none"/>', color: 'var(--violet)' },
  { label: 'Redis',     icon: '<path d="M7 17a4 4 0 010-8 5 5 0 019.6-1.5A4.5 4.5 0 0117 17H7z"/>',  color: 'var(--amber)' },
]

function StatusStrip() {
  return (
    <div style={{ marginTop: 8 }}>
      <div style={{ position: 'relative', display: 'flex', alignItems: 'center',
        justifyContent: 'space-around', padding: '14px 4px' }}>
        {/* dotted line */}
        <div style={{
          position: 'absolute', left: 22, right: 22, top: '50%', height: 1,
          backgroundImage: 'repeating-linear-gradient(90deg,var(--border-strong) 0 4px,transparent 4px 8px)',
        }} />
        {SERVICES.map(s => (
          <span key={s.label} style={{ position: 'relative', zIndex: 1, display: 'flex',
            flexDirection: 'column', alignItems: 'center', gap: 6 }}>
            <span style={{
              width: 34, height: 34, borderRadius: '50%',
              background: 'var(--glass-bg-2)', border: '1px solid var(--border-strong)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              color: s.color,
            }}>
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor"
                   strokeLinecap="round" strokeLinejoin="round"
                   style={{ width: 15, height: 15 }}
                   dangerouslySetInnerHTML={{ __html: s.icon }} />
            </span>
            <span style={{ fontSize: 9, color: 'var(--muted-2)', fontFamily: 'var(--f-mono)', letterSpacing: '0.3px' }}>
              {s.label}
            </span>
          </span>
        ))}
        <span style={{ position: 'relative', zIndex: 1, display: 'flex',
          flexDirection: 'column', alignItems: 'center', gap: 6 }}>
          <span style={{
            width: 34, height: 34, borderRadius: '50%',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            fontSize: 10, color: 'var(--muted-2)',
            border: '1px dashed var(--border-strong)',
            fontFamily: 'var(--f-mono)',
          }}>+{MODELS.length}</span>
          <span style={{ fontSize: 9, color: 'var(--muted-2)', fontFamily: 'var(--f-mono)' }}>
            Models
          </span>
        </span>
      </div>

      {/* Model list */}
      <div style={{ borderTop: '1px solid var(--border)', paddingTop: 14, display: 'flex', flexDirection: 'column', gap: 8 }}>
        {MODELS.map(m => (
          <div key={m.id} style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <span style={{ width: 7, height: 7, borderRadius: '50%', background: m.color, flexShrink: 0 }} />
            <span style={{ fontSize: 12, flex: 1 }}>{m.label}</span>
            <span style={{ fontSize: 10, fontFamily: 'var(--f-mono)', color: 'var(--green)' }}>
              loaded
            </span>
          </div>
        ))}
      </div>
    </div>
  )
}

// ── KPI icons (SVG path strings) ─────────────────────────────────────────────
const ICONS = {
  shield:  '<path d="M12 3l7.5 3v6.2c0 5.4-3.6 8.7-7.5 9.8-3.9-1.1-7.5-4.4-7.5-9.8V6L12 3z"/>',
  radar:   '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3.6" fill="currentColor" stroke="none" opacity="0.18"/><circle cx="12" cy="12" r="3.6"/><circle cx="12" cy="12" r="0.6" fill="currentColor" stroke="none"/>',
  report:  '<rect x="5" y="3" width="14" height="18" rx="2"/><rect x="8" y="13" width="2" height="5" fill="currentColor" stroke="none"/><rect x="11.3" y="10" width="2" height="8" fill="currentColor" stroke="none"/><rect x="14.6" y="7" width="2" height="11" fill="currentColor" stroke="none"/>',
  check:   '<path d="M6 12l4 4 8-9"/>',
}

// ── Page ─────────────────────────────────────────────────────────────────────
export default function Overview() {
  const alerts    = useAlertStore(s => s.alerts)
  const anomalies = useAnomalyStore(s => s.anomalies)

  const latest    = alerts[0] ?? null
  const radarData = useMemo(() => toRadarData(alerts), [alerts])
  const bubbles   = useMemo(() => toBubbleData(alerts), [alerts])
  const conRate   = useMemo(() => consensusRate(alerts), [alerts])

  return (
    <Shell title="Overview">

      {/* ── KPI Row ── */}
      <div className="kpi-grid">
        <KpiCard
          featured
          label="Live Attacks"
          value={alerts.length}
          icon={ICONS.shield}
          delta={alerts.length > 0 ? { text: 'ids:attacks stream', direction: null } : null}
        />
        <KpiCard
          label="Anomalies"
          value={anomalies.length}
          icon={ICONS.radar}
          delta={anomalies.length > 0 ? { text: 'ids:anomalies', direction: 'bad' } : null}
        />
        <KpiCard
          label="Models"
          value="5/5"
          icon={ICONS.report}
          delta={{ text: 'all loaded', direction: 'good' }}
        />
        <KpiCard
          label="Consensus Rate"
          value={conRate}
          icon={ICONS.check}
          delta={alerts.length > 0 ? { text: 'last session', direction: 'good' } : null}
        />
      </div>

      {/* ── Row A: live feed + ensemble gauge ── */}
      <div className="row-6535">
        <div className="card">
          <div className="card-header">
            <span className="card-title">Live Alert Feed</span>
            <span style={{
              fontFamily: 'var(--f-mono)', fontSize: 11, color: 'var(--lime)',
              background: 'var(--glass-bg-2)', border: '1px solid var(--border-strong)',
              padding: '4px 11px', borderRadius: 99,
            }}>
              {alerts.length} events
            </span>
          </div>
          <AlertLogStream alerts={alerts} />
        </div>

        <div className="card">
          <div className="card-header">
            <span className="card-title">Ensemble Consensus</span>
            <span style={{ fontSize: 11, color: 'var(--muted-2)' }}>latest alert</span>
          </div>
          <EnsembleGauge
            votes={latest?.model_votes}
            agreement={latest?.agreement}
            label={latest?.prediction?.label}
          />
        </div>
      </div>

      {/* ── Row B: radar + bubbles ── */}
      <div className="row-3565">
        <div className="card">
          <div className="card-header">
            <span className="card-title">Threat Coverage</span>
            <span style={{
              fontFamily: 'var(--f-mono)', fontSize: 11, color: 'var(--lime)',
              background: 'var(--glass-bg-2)', border: '1px solid var(--border-strong)',
              padding: '4px 11px', borderRadius: 99,
            }}>
              {Object.values(radarData).some(v => v > 0) ? 'active' : '—'}
            </span>
          </div>
          <RadarChart data={radarData} />
        </div>

        <div className="card">
          <div className="card-header">
            <span className="card-title">Attack Surface by Vector</span>
            <span style={{ fontSize: 11, color: 'var(--muted-2)' }}>flagged events, session</span>
          </div>
          <BubbleCluster data={bubbles} />
        </div>
      </div>

      {/* ── Row C: trend chart + system status ── */}
      <div className="row-6535">
        <div className="card">
          <div className="card-header">
            <div>
              <span className="card-title">Detection Trend</span>
              <div style={{ fontSize: 11, color: 'var(--muted-2)', marginTop: 2 }}>
                attacks detected, last 60 min
              </div>
            </div>
            <div style={{ display: 'flex', gap: 6, fontSize: 11, color: 'var(--muted)' }}>
              <span style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                <span style={{ width: 7, height: 7, borderRadius: '50%', background: 'var(--lime)' }} />
                Detected
              </span>
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
ok "Overview.jsx"


# ═══════════════════════════════════════════════════════════════════════
#  VALIDATION
# ═══════════════════════════════════════════════════════════════════════
step "Validation"

FILES=(
  "frontend/src/store/alertStore.js"
  "frontend/src/store/anomalyStore.js"
  "frontend/src/providers/LiveDataProvider.jsx"
  "frontend/src/App.jsx"
  "frontend/src/components/ui/KpiCard.jsx"
  "frontend/src/components/charts/EnsembleGauge.jsx"
  "frontend/src/components/charts/TrendChart.jsx"
  "frontend/src/components/charts/RadarChart.jsx"
  "frontend/src/components/charts/BubbleCluster.jsx"
  "frontend/src/components/alerts/AlertLogStream.jsx"
  "frontend/src/pages/Overview.jsx"
)
for f in "${FILES[@]}"; do
  [ -f "$f" ] && ok "$f" || { echo -e "  \033[0;31m✗\033[0m  MISSING: $f"; exit 1; }
done

echo ""
echo -e "${G}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo -e "${G}  Overview patch complete.${N}"
echo ""
echo -e "  Start dev server:"
echo -e "  cd frontend && npm run dev"
echo -e "  → http://localhost:5173"
echo ""
echo -e "  The page renders with empty/zero state until the sensor"
echo -e "  and bridge are running. To test the gauge immediately:"
echo -e ""
echo -e "  cd ebpf-sensor   # venv active"
echo -e "  python3 - <<'PY'"
echo -e "  from sensor.publisher import Publisher"
echo -e "  Publisher().publish_attack({"
echo -e '    "is_attack": True, "flow_id": "6-10.0.0.9:4444-10.0.0.1:22",'
echo -e '    "timestamp": "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'",'
echo -e '    "prediction": {"label": "PortScan", "confidence": 0.97},'
echo -e '    "source_model": "xgboost",'
echo -e '    "agreement": {"consensus": True, "agreeing": 4, "total": 4},'
echo -e '    "explanation": {"top_features": []},'
echo -e '    "model_votes": {'
echo -e '      "random_forest": {"label": "PortScan", "confidence": 0.95},'
echo -e '      "xgboost":       {"label": "PortScan", "confidence": 0.97},'
echo -e '      "lightgbm":      {"label": "PortScan", "confidence": 0.96},'
echo -e '      "cnn_lstm":      {"label": "PortScan", "confidence": 0.89},'
echo -e '      "autoencoder":   {"anomaly_score": 0.11, "threshold": 0.0726, "is_anomalous": True}'
echo -e '    },'
echo -e '    "identity": {"src_ip":"10.0.0.9","src_port":4444,"dst_ip":"10.0.0.1","dst_port":22,"protocol":6}'
echo -e "  })"
echo -e "  PY"
echo -e "${G}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
