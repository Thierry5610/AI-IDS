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
