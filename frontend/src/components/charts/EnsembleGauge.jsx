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
