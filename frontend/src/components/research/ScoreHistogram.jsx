/**
 * ScoreHistogram — distribution of live AE anomaly scores with the fixed 0.0726
 * threshold marker. Bars left of the threshold read benign-like (muted), bars at
 * or past it are anomalous (violet). Pure SVG, inline binning.
 */
import { useMemo } from 'react'

const W = 600, H = 210
const PADL = 8, PADR = 8, PADT = 14, PADB = 26
const NBINS = 20

export default function ScoreHistogram({ scores, threshold }) {
  const { bins, domainMax, maxCount } = useMemo(() => {
    const dmax = Math.max(...scores, threshold, 0.0001) * 1.15
    const b = Array.from({ length: NBINS }, () => 0)
    for (const s of scores) {
      const idx = Math.min(Math.floor((s / dmax) * NBINS), NBINS - 1)
      if (idx >= 0) b[idx]++
    }
    return { bins: b, domainMax: dmax, maxCount: Math.max(...b, 1) }
  }, [scores, threshold])

  if (scores.length === 0) {
    return (
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center',
        height: 200, color: 'var(--muted-2)', fontFamily: 'var(--f-mono)', fontSize: 13 }}>
        no anomaly scores yet — AE idle
      </div>
    )
  }

  const plotW = W - PADL - PADR
  const plotH = H - PADT - PADB
  const bw = plotW / NBINS
  const threshX = PADL + (threshold / domainMax) * plotW
  const aboveCount = scores.filter(s => s >= threshold).length
  const abovePct = Math.round((aboveCount / scores.length) * 100)

  return (
    <div style={{ position: 'relative' }}>
      <svg viewBox={`0 0 ${W} ${H}`} width="100%" height="210" preserveAspectRatio="none">
        {/* baseline */}
        <line x1={PADL} y1={PADT + plotH} x2={W - PADR} y2={PADT + plotH}
          stroke="var(--border)" strokeWidth="1" />

        {/* bars */}
        {bins.map((c, i) => {
          const h = (c / maxCount) * plotH
          const x = PADL + i * bw
          const y = PADT + plotH - h
          const center = (i + 0.5) / NBINS * domainMax
          const above = center >= threshold
          return (
            <rect key={i} x={x + 1} y={y} width={Math.max(bw - 2, 1)} height={h}
              fill={above ? 'var(--violet)' : 'var(--muted-2)'}
              fillOpacity={above ? 0.85 : 0.5} rx="1" />
          )
        })}

        {/* threshold marker */}
        <line x1={threshX} y1={PADT - 4} x2={threshX} y2={PADT + plotH}
          stroke="var(--amber)" strokeWidth="1.4" strokeDasharray="3 3" />
        <text x={threshX + 4} y={PADT + 6} fontFamily="var(--f-mono)" fontSize="9"
          fill="var(--amber)">{threshold}</text>

        {/* axis ends */}
        <text x={PADL} y={H - 8} fontFamily="var(--f-mono)" fontSize="8" fill="var(--muted-2)">0</text>
        <text x={W - PADR} y={H - 8} textAnchor="end" fontFamily="var(--f-mono)" fontSize="8"
          fill="var(--muted-2)">{domainMax.toFixed(3)}</text>
        <text x={(PADL + plotW / 2)} y={H - 8} textAnchor="middle" fontFamily="var(--f-mono)"
          fontSize="8" fill="var(--muted-2)">reconstruction error</text>
      </svg>

      <div style={{ fontFamily: 'var(--f-mono)', fontSize: 11, color: 'var(--muted)', marginTop: 4 }}>
        <span style={{ color: 'var(--violet)' }}>{abovePct}%</span> of observed scores ≥ threshold
        ({aboveCount}/{scores.length})
      </div>
    </div>
  )
}
