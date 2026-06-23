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
