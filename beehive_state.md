# Beehive — live code snapshot
_generated: 2026-06-23T03:59:12Z_

## File tree
```
bridge/consumer.py
bridge/__init__.py
bridge/main.py
bridge/routes/anomalies.py
bridge/routes/attacks.py
bridge/routes/__init__.py
frontend/src/App.jsx
frontend/src/components/alerts/AlertLogStream.jsx
frontend/src/components/charts/BubbleCluster.jsx
frontend/src/components/charts/EnsembleGauge.jsx
frontend/src/components/charts/RadarChart.jsx
frontend/src/components/charts/TrendChart.jsx
frontend/src/components/shell/Rail.jsx
frontend/src/components/shell/Shell.jsx
frontend/src/components/shell/Topbar.jsx
frontend/src/components/ui/KpiCard.jsx
frontend/src/components/ui/StatusStrip.jsx
frontend/src/constants/attacks.js
frontend/src/constants/models.js
frontend/src/constants/nav.js
frontend/src/lib/api.js
frontend/src/lib/format.js
frontend/src/lib/stream.js
frontend/src/main.jsx
frontend/src/pages/Alerts.jsx
frontend/src/pages/Flows.jsx
frontend/src/pages/Models.jsx
frontend/src/pages/Overview.jsx
frontend/src/pages/Research.jsx
frontend/src/pages/Settings.jsx
frontend/src/pages/Topology.jsx
frontend/src/providers/LiveDataProvider.jsx
frontend/src/store/alertStore.js
frontend/src/store/anomalyStore.js
frontend/src/styles/globals.css
frontend/src/styles/shell.css
frontend/src/styles/tokens.css
```

## File contents

### `bridge/consumer.py`
```python
"""
Redis XREAD tailing consumer (broadcast / fan-out).

Each SSE connection calls stream_events() independently and gets its OWN
cursor — so EVERY connected client receives EVERY message. This is the
correct model for a dashboard.

(The previous group-consumer approach used competing consumers: a message
went to only one connection, so a second browser tab would see nothing.)

No acking, no consumer groups. Starts at "0" to replay recent history on
connect, then tails live.
"""
import json
import os
import redis.asyncio as aioredis

REDIS_URL      = os.getenv("REDIS_URL", "redis://127.0.0.1:6379/0")
BLOCK_MS       = 5_000
SOCKET_TIMEOUT = BLOCK_MS / 1000 + 5


async def stream_events(stream: str, start_id: str = "0"):
    """Async generator: yields JSON strings or None (heartbeat tick).

    start_id "0"  → replay all retained history then tail
    start_id "$"  → live only (skip history)
    """
    r = await aioredis.from_url(
        REDIS_URL,
        socket_timeout=SOCKET_TIMEOUT,
        decode_responses=True,
    )

    cursor = start_id
    while True:
        try:
            results = await r.xread({stream: cursor}, count=20, block=BLOCK_MS)
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
                cursor = msg_id                  # advance this connection's cursor
                raw = fields.get("data", "{}")
                try:
                    json.loads(raw)
                except json.JSONDecodeError:
                    continue
                yield raw
```

### `bridge/__init__.py`
```python
```

### `bridge/main.py`
```python
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
```

### `bridge/routes/anomalies.py`
```python
import os
from fastapi import APIRouter, Request
from sse_starlette.sse import EventSourceResponse
from consumer import stream_events

router = APIRouter()
STREAM = os.getenv("IDS_ANOMALIES_STREAM", "ids:anomalies")


@router.get("/stream/anomalies")
async def anomalies_sse(request: Request):
    async def generator():
        async for payload in stream_events(STREAM, "0"):
            if await request.is_disconnected():
                break
            if payload is None:
                yield {"comment": "heartbeat"}
            else:
                yield {"event": "anomaly", "data": payload}
    return EventSourceResponse(generator())
```

### `bridge/routes/attacks.py`
```python
import os
from fastapi import APIRouter, Request
from sse_starlette.sse import EventSourceResponse
from consumer import stream_events

router = APIRouter()
STREAM = os.getenv("IDS_ATTACKS_STREAM", "ids:attacks")


@router.get("/stream/attacks")
async def attacks_sse(request: Request):
    async def generator():
        async for payload in stream_events(STREAM, "0"):
            if await request.is_disconnected():
                break
            if payload is None:
                yield {"comment": "heartbeat"}
            else:
                yield {"event": "attack", "data": payload}
    return EventSourceResponse(generator())
```

### `bridge/routes/__init__.py`
```python
```

### `frontend/src/App.jsx`
```jsx
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
```

### `frontend/src/components/alerts/AlertLogStream.jsx`
```jsx
/**
 * AlertLogStream — vertical event log matching the VIGIL prototype.
 * Structure: .log > .log-row > (.log-rail[icon+line]) + (.log-body[top+meta]).
 * Severity drives the icon colour only.
 */
import { fmt }        from '../../lib/format'
import { severityOf } from '../../constants/attacks'

const ALERT_ICON = '<line x1="12" y1="6" x2="12" y2="13"/><circle cx="12" cy="17" r="1" fill="currentColor" stroke="none"/>'
const CHECK_ICON = '<path d="M6 12l4 4 8-9"/>'

function railClass(sev) {
  if (sev === 'critical' || sev === 'high') return 'crit'
  if (sev === 'medium')                     return 'warn'
  return 'ok'
}

function Row({ alert, isLast }) {
  const label = alert.prediction?.label ?? 'Unknown'
  const sev   = severityOf(label)
  const cls   = railClass(sev)
  const icon  = cls === 'ok' ? CHECK_ICON : ALERT_ICON

  return (
    <div className="log-row">
      <div className="log-rail">
        <span className={`log-icon ${cls}`}>
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor"
               strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"
               width="11" height="11"
               dangerouslySetInnerHTML={{ __html: icon }} />
        </span>
        {!isLast && <span className="log-line" />}
      </div>

      <div className="log-body">
        <div className="log-top">
          <span className="log-title">{label}</span>
          <span className="log-time">{fmt.time(alert.timestamp)}</span>
        </div>
        <div className="log-meta">
          {alert.identity ? fmt.flow(alert.identity) : (alert.flow_id ?? '—')}
          {alert.prediction?.confidence != null && (
            <> {' · '}<span style={{ color: 'var(--lime)' }}>{fmt.pct(alert.prediction.confidence)}</span></>
          )}
        </div>
      </div>
    </div>
  )
}

export default function AlertLogStream({ alerts, maxRows = 6 }) {
  const rows = alerts.slice(0, maxRows)

  if (rows.length === 0) {
    return (
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center',
        height: 140, color: 'var(--muted-2)', fontFamily: 'var(--f-mono)', fontSize: 12 }}>
        no alerts — sensor idle
      </div>
    )
  }

  return (
    <div className="log">
      {rows.map((a, i) => (
        <Row key={a.flow_id ?? i} alert={a} isLast={i === rows.length - 1} />
      ))}
    </div>
  )
}
```

### `frontend/src/components/charts/BubbleCluster.jsx`
```jsx
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
```

### `frontend/src/components/charts/EnsembleGauge.jsx`
```jsx
/**
 * EnsembleGauge — featured visualisation.
 * Five concentric rings (outer→inner: RF → XGB → LGB → CNN → AE).
 * Rings closing the circle = consensus. Centre shows agreement fraction;
 * predicted label sits in a severity pill below.
 *
 * Radii pushed outward into a tighter band ([96..40]) so the centre number
 * has clear breathing room from the innermost (AE) ring.
 */
import { MODELS, AE_THRESHOLD } from '../../constants/models'
import { severityOf }           from '../../constants/attacks'

const CX = 110, CY = 110
const RADII = [96, 82, 68, 54, 40]   // RF → XGB → LGB → CNN → AE
const SW = 6

function Arc({ r, pct, color, animate }) {
  const circ = 2 * Math.PI * r
  const dash = circ * Math.min(Math.max(pct, 0), 1)
  return (
    <>
      <circle cx={CX} cy={CY} r={r}
        fill="none" stroke="var(--border)" strokeWidth={SW} />
      <circle cx={CX} cy={CY} r={r}
        fill="none" stroke={color} strokeWidth={SW} strokeLinecap="round"
        strokeDasharray={`${dash.toFixed(2)} ${circ.toFixed(2)}`}
        transform={`rotate(-90 ${CX} ${CY})`}
        style={{ transition: animate ? 'stroke-dasharray .7s cubic-bezier(.4,0,.2,1)' : 'none' }} />
    </>
  )
}

function arcPct(id, votes) {
  if (!votes) return 0
  const v = votes[id]
  if (!v) return 0
  if (id === 'autoencoder') return Math.min((v.anomaly_score ?? 0) / AE_THRESHOLD, 1)
  return v.confidence ?? 0
}

export default function EnsembleGauge({ votes, agreement, label }) {
  const hasData  = !!votes
  const arcs     = MODELS.map((m, i) => ({ ...m, r: RADII[i], pct: arcPct(m.id, votes) }))
  const isAttack = hasData && !!label && label !== 'Benign'
  const sev      = label ? severityOf(label) : 'low'

  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 14 }}>
      <svg width="100%" viewBox="0 0 220 220" style={{ maxWidth: 210 }}>
        {arcs.map(a => (
          <Arc key={a.id} r={a.r} pct={a.pct} color={a.color} animate={hasData} />
        ))}

        <text x={CX} y={CY - 5}
          textAnchor="middle" dominantBaseline="middle"
          fontFamily="var(--f-display)" fontSize="25" fontWeight="600"
          fill={hasData ? (agreement?.consensus ? 'var(--lime)' : 'var(--amber)') : 'var(--muted-2)'}>
          {agreement ? `${agreement.agreeing}/${agreement.total}` : '—'}
        </text>
        <text x={CX} y={CY + 14}
          textAnchor="middle"
          fontFamily="var(--f-mono)" fontSize="8" letterSpacing="2"
          fill="var(--muted)" style={{ textTransform: 'uppercase' }}>
          {hasData ? 'agree' : 'idle'}
        </text>
      </svg>

      <span className={`pill ${isAttack ? sev : 'ok'}`}
        style={{ maxWidth: '100%', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
        {hasData ? (label ?? 'Unknown') : 'awaiting alert'}
      </span>

      <div style={{ display: 'flex', flexWrap: 'wrap', gap: '6px 14px', justifyContent: 'center' }}>
        {arcs.map(a => (
          <span key={a.id} style={{ display: 'flex', alignItems: 'center', gap: 5,
            fontSize: 10, fontFamily: 'var(--f-mono)', color: 'var(--muted)' }}>
            <span style={{ width: 7, height: 7, borderRadius: '50%', background: a.color, flexShrink: 0 }} />
            {a.short}
            <span style={{ color: 'var(--muted-2)' }}>
              {hasData ? `${(a.pct * 100).toFixed(0)}%` : '--'}
            </span>
          </span>
        ))}
      </div>
    </div>
  )
}
```

### `frontend/src/components/charts/RadarChart.jsx`
```jsx
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
```

### `frontend/src/components/charts/TrendChart.jsx`
```jsx
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
```

### `frontend/src/components/shell/Rail.jsx`
```jsx
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
```

### `frontend/src/components/shell/Shell.jsx`
```jsx
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
```

### `frontend/src/components/shell/Topbar.jsx`
```jsx
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
```

### `frontend/src/components/ui/KpiCard.jsx`
```jsx
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
```

### `frontend/src/components/ui/StatusStrip.jsx`
```jsx
/**
 * StatusStrip — connector line passes through icon centres.
 * Line is drawn only in the gaps between circles (.sstrip-cell::after), so no
 * segment sits behind a circle. svg width/height are set as ATTRIBUTES too, so
 * icons can never blow up even if the stylesheet fails to load.
 */
import { MODELS } from '../../constants/models'

const ICONS = {
  sensor: '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3.6" fill="currentColor" stroke="none" opacity="0.18"/><circle cx="12" cy="12" r="3.6"/><circle cx="12" cy="12" r="0.6" fill="currentColor" stroke="none"/>',
  inference: '<circle cx="12" cy="12" r="2.8"/><circle cx="12" cy="4.5" r="1.5" fill="currentColor" stroke="none"/><circle cx="4.5" cy="12" r="1.5" fill="currentColor" stroke="none"/><circle cx="19.5" cy="12" r="1.5" fill="currentColor" stroke="none"/><circle cx="12" cy="19.5" r="1.5" fill="currentColor" stroke="none"/><circle cx="6.2" cy="6.2" r="1.5" fill="currentColor" stroke="none"/><circle cx="17.8" cy="17.8" r="1.5" fill="currentColor" stroke="none"/><line x1="12" y1="7.6" x2="12" y2="9.2"/><line x1="7.6" y1="12" x2="9.2" y2="12"/><line x1="14.8" y1="12" x2="16.4" y2="12"/><line x1="12" y1="14.8" x2="12" y2="16.4"/><line x1="7.7" y1="7.7" x2="10" y2="10"/><line x1="14" y1="14" x2="16.3" y2="16.3"/>',
  bridge:   '<line x1="6.7" y1="7.3" x2="10.6" y2="11.7"/><line x1="17.3" y1="7.3" x2="13.4" y2="11.7"/><line x1="11" y1="14.5" x2="7" y2="17.7"/><line x1="13" y1="14.5" x2="17" y2="17.7"/><circle cx="5" cy="6" r="2.1" fill="currentColor" stroke="none"/><circle cx="19" cy="6" r="2.1" fill="currentColor" stroke="none"/><circle cx="12" cy="13" r="2.3" fill="currentColor" stroke="none"/><circle cx="6" cy="19" r="2.1" fill="currentColor" stroke="none"/><circle cx="18" cy="19" r="2.1" fill="currentColor" stroke="none"/>',
  redis:    '<path d="M7 17a4 4 0 010-8 5 5 0 019.6-1.5A4.5 4.5 0 0117 17H7z"/>',
}

const SERVICES = [
  { key: 'sensor',    label: 'Sensor',    icon: ICONS.sensor,    color: 'var(--lime)'   },
  { key: 'inference', label: 'Inference', icon: ICONS.inference, color: 'var(--cyan)'   },
  { key: 'bridge',    label: 'Bridge',    icon: ICONS.bridge,    color: 'var(--violet)' },
  { key: 'redis',     label: 'Redis',     icon: ICONS.redis,     color: 'var(--amber)'  },
]

function Cell({ icon, color, label }) {
  return (
    <div className="sstrip-cell">
      <span className="sstrip-icon" style={{ color }}>
        <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor"
             strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"
             dangerouslySetInnerHTML={{ __html: icon }} />
      </span>
      <span className="sstrip-label">{label}</span>
    </div>
  )
}

export default function StatusStrip() {
  return (
    <div className="sstrip">
      <div className="sstrip-rail">
        {SERVICES.map(s => (
          <Cell key={s.key} icon={s.icon} color={s.color} label={s.label} />
        ))}
        <div className="sstrip-cell">
          <span className="sstrip-more">+{MODELS.length}</span>
          <span className="sstrip-label">Models</span>
        </div>
      </div>

      <div className="sstrip-models">
        {MODELS.map(m => (
          <div key={m.id} className="sstrip-model">
            <span className="sstrip-model-dot" style={{ background: m.color }} />
            <span className="sstrip-model-name">{m.label}</span>
            <span className="sstrip-model-stat">loaded</span>
          </div>
        ))}
      </div>
    </div>
  )
}
```

### `frontend/src/constants/attacks.js`
```jsx
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
```

### `frontend/src/constants/models.js`
```jsx
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
```

### `frontend/src/constants/nav.js`
```jsx
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
```

### `frontend/src/lib/api.js`
```jsx
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
```

### `frontend/src/lib/format.js`
```jsx
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
```

### `frontend/src/lib/stream.js`
```jsx
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
```

### `frontend/src/main.jsx`
```jsx
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
```

### `frontend/src/pages/Alerts.jsx`
```jsx
import Shell from '../components/shell/Shell'

export default function Alerts() {
  return (
    <Shell title="Alerts">
      <p style={{ color: 'var(--muted)', fontFamily: 'var(--f-mono)', fontSize: 13, padding: '8px 0' }}>
        {/* Alerts — content coming in its own build session */}
      </p>
    </Shell>
  )
}
```

### `frontend/src/pages/Flows.jsx`
```jsx
import Shell from '../components/shell/Shell'

export default function Flows() {
  return (
    <Shell title="Flows">
      <p style={{ color: 'var(--muted)', fontFamily: 'var(--f-mono)', fontSize: 13, padding: '8px 0' }}>
        {/* Flows — content coming in its own build session */}
      </p>
    </Shell>
  )
}
```

### `frontend/src/pages/Models.jsx`
```jsx
import Shell from '../components/shell/Shell'

export default function Models() {
  return (
    <Shell title="Models">
      <p style={{ color: 'var(--muted)', fontFamily: 'var(--f-mono)', fontSize: 13, padding: '8px 0' }}>
        {/* Models — content coming in its own build session */}
      </p>
    </Shell>
  )
}
```

### `frontend/src/pages/Overview.jsx`
```jsx
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
```

### `frontend/src/pages/Research.jsx`
```jsx
import Shell from '../components/shell/Shell'

export default function Research() {
  return (
    <Shell title="Research / AE">
      <p style={{ color: 'var(--muted)', fontFamily: 'var(--f-mono)', fontSize: 13, padding: '8px 0' }}>
        {/* Research / AE — content coming in its own build session */}
      </p>
    </Shell>
  )
}
```

### `frontend/src/pages/Settings.jsx`
```jsx
import Shell from '../components/shell/Shell'

export default function Settings() {
  return (
    <Shell title="Settings">
      <p style={{ color: 'var(--muted)', fontFamily: 'var(--f-mono)', fontSize: 13, padding: '8px 0' }}>
        {/* Settings — content coming in its own build session */}
      </p>
    </Shell>
  )
}
```

### `frontend/src/pages/Topology.jsx`
```jsx
import Shell from '../components/shell/Shell'

export default function Topology() {
  return (
    <Shell title="Topology">
      <p style={{ color: 'var(--muted)', fontFamily: 'var(--f-mono)', fontSize: 13, padding: '8px 0' }}>
        {/* Topology — content coming in its own build session */}
      </p>
    </Shell>
  )
}
```

### `frontend/src/providers/LiveDataProvider.jsx`
```jsx
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
```

### `frontend/src/store/alertStore.js`
```jsx
import { create } from 'zustand'

const RING = 200   // max supervised-attack alerts in memory

export const useAlertStore = create((set) => ({
  alerts: [],
  push:  (a) => set((s) => ({ alerts: [a, ...s.alerts].slice(0, RING) })),
  clear: ()  => set({ alerts: [] }),
}))
```

### `frontend/src/store/anomalyStore.js`
```jsx
import { create } from 'zustand'

// AE flags ~75% of local-benign (domain-shift finding) — keep a larger window.
const RING = 500

export const useAnomalyStore = create((set) => ({
  anomalies: [],
  push:  (a) => set((s) => ({ anomalies: [a, ...s.anomalies].slice(0, RING) })),
  clear: ()  => set({ anomalies: [] }),
}))
```

### `frontend/src/styles/globals.css`
```css
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
```

### `frontend/src/styles/shell.css`
```css
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

/* ── KPI top row (label + icon, added by patch_overview) ── */
.kpi-top {
  display: flex; align-items: center; justify-content: space-between;
  margin-bottom: 4px;
}

/* ===== Beehive scale + status-strip pass ===== */

/* ── Single scale knob ──
   Bakes in the 125% look. RESET your browser zoom to 100% (Ctrl+0) first,
   or it doubles. Change this one number to taste; everything scales together. */
html { zoom: 1.25; }

/* ── Delta / KPI chips: never inherit near-white body text ── */
.delta      { color: var(--muted); }
.delta.good { color: var(--green); background: var(--green-soft); }
.delta.bad  { color: var(--amber); background: var(--amber-soft); }
.delta.crit { color: var(--red);   background: var(--red-soft);   }

/* ── Alert log feed — ported verbatim from VIGIL prototype ── */
.log        { display: flex; flex-direction: column; margin-top: 2px; }
.log-row    { display: flex; gap: 12px; }
.log-rail   { display: flex; flex-direction: column; align-items: center; width: 24px; flex-shrink: 0; }
.log-icon   { width: 22px; height: 22px; border-radius: 50%; display: flex;
              align-items: center; justify-content: center; flex-shrink: 0;
              background: var(--glass-bg-2); border: 1px solid var(--border-strong); }
.log-icon svg     { width: 11px; height: 11px; }
.log-icon.crit    { color: var(--red);   border-color: rgba(255,77,94,0.45); }
.log-icon.warn    { color: var(--amber); border-color: rgba(255,176,32,0.45); }
.log-icon.ok      { color: var(--green); border-color: rgba(52,211,153,0.45); }
.log-line   { width: 1px; flex: 1; background: var(--border-strong); margin: 4px 0; min-height: 18px; }
.log-row:last-child .log-line { display: none; }
.log-body   { flex: 1; padding-bottom: 17px; }
.log-row:last-child .log-body { padding-bottom: 0; }
.log-top    { display: flex; justify-content: space-between; align-items: baseline; gap: 8px; }
.log-title  { font-size: 12.5px; color: var(--text); font-weight: 500; }
.log-time   { font-family: var(--f-mono); font-size: 10px; color: var(--muted-2); flex-shrink: 0; }
.log-meta   { font-family: var(--f-mono); font-size: 10.5px; color: var(--muted-2); margin-top: 3px; }

/* ── StatusStrip: line lives only in the gaps between circles (no masking) ── */
.sstrip            { margin-top: 8px; }
.sstrip-rail       { display: flex; align-items: flex-start; padding: 8px 0 4px; }
.sstrip-cell       { flex: 1; display: flex; flex-direction: column;
                     align-items: center; gap: 8px; position: relative; }
.sstrip-cell:not(:last-child)::after {
  content: ''; position: absolute;
  top: 18px;
  left: calc(50% + 18px);
  width: calc(100% - 36px);
  height: 2px;
  background: var(--border-strong);
  transform: translateY(-50%);
  z-index: 0;
}
.sstrip-icon {
  width: 36px; height: 36px; border-radius: 50%;
  background: var(--glass-bg-2);
  border: 1px solid var(--border-strong);
  display: flex; align-items: center; justify-content: center;
  position: relative; z-index: 1; flex-shrink: 0;
}
.sstrip-icon svg   { width: 16px; height: 16px; }
.sstrip-label      { font-size: 9.5px; color: var(--muted-2);
                     font-family: var(--f-mono); letter-spacing: 0.3px; }
.sstrip-more {
  width: 36px; height: 36px; border-radius: 50%;
  display: flex; align-items: center; justify-content: center;
  font-size: 10px; color: var(--muted-2);
  background: var(--glass-bg-2);
  border: 1px dashed var(--border-strong);
  font-family: var(--f-mono);
  position: relative; z-index: 1; flex-shrink: 0;
}
.sstrip-models     { border-top: 1px solid var(--border); padding-top: 14px;
                     margin-top: 6px; display: flex; flex-direction: column; gap: 9px; }
.sstrip-model      { display: flex; align-items: center; gap: 10px; }
.sstrip-model-dot  { width: 7px; height: 7px; border-radius: 50%; flex-shrink: 0; }
.sstrip-model-name { font-size: 12.5px; flex: 1; }
.sstrip-model-stat { font-size: 10px; font-family: var(--f-mono); color: var(--green); }

/* ── KPI card parity with VIGIL bible (patch_cards) ── */
.kpi-top    { margin-bottom: 16px; }
.kpi-label  { font-size: 10px; letter-spacing: 1px; text-transform: uppercase;
              color: var(--muted-2); font-weight: 600; }
.kpi-value  { font-family: var(--f-display); font-size: 32px; font-weight: 600;
              letter-spacing: -0.5px; line-height: 1; }
.kpi-foot   { margin-top: 12px; }

/* Featured (lime) card: muted-dark label + dark delta pill, not full black */
.kpi.featured .kpi-label { color: rgba(10,10,10,0.62); }
.kpi.featured .kpi-value { color: #0a0a0a; }
.kpi.featured .delta     { background: rgba(10,10,10,0.14); color: #0a0a0a; }
```

### `frontend/src/styles/tokens.css`
```css
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
```
