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
