/**
 * VoteMatrix — recent alerts × the four supervised models.
 * Each cell shows a model's predicted label (abbrev) + confidence tint; cells that
 * disagree with the deciding (source/prediction) label are flagged. Surfaces
 * ensemble (dis)agreement concretely.
 */
import './Models.css'
import { SUPERVISED } from '../../constants/models'
import { fmt }        from '../../lib/format'

// Compact attack label for a dense grid cell.
function abbr(label) {
  if (!label) return '—'
  return label
    .replace(/^Web Attack - /, '')
    .replace('GoldenEye', 'GE').replace('Slowhttptest', 'Slow')
    .replace('slowloris', 'Slowl').replace('-Patator', '-Pat')
    .slice(0, 10)
}

export default function VoteMatrix({ alerts, max = 8 }) {
  const rows = alerts.slice(0, max)
  if (rows.length === 0) {
    return <div className="vm-empty">no decisions yet — sensor idle</div>
  }
  return (
    <div className="table-wrap">
      <table className="vote-matrix">
        <thead>
          <tr>
            <th>Flow</th>
            {SUPERVISED.map(m => <th key={m.id}>{m.short}</th>)}
            <th>Decided</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((a, i) => {
            const decided = a.prediction?.label
            return (
              <tr key={`${a.flow_id ?? 'a'}-${a.timestamp ?? ''}-${i}`}>
                <td className="mono vm-flow">{a.identity ? fmt.flow(a.identity) : (a.flow_id ?? '—')}</td>
                {SUPERVISED.map(m => {
                  const v = a.model_votes?.[m.id]
                  const dis = v?.label && decided && v.label !== decided
                  return (
                    <td key={m.id} className={`vm-cell ${dis ? 'vm-dis' : ''}`}>
                      <span className="vm-label">{abbr(v?.label)}</span>
                      <span className="vm-conf">{v?.confidence != null ? fmt.pct(v.confidence) : '—'}</span>
                    </td>
                  )
                })}
                <td><span className="vm-decided" style={{ color: 'var(--lime)' }}>{abbr(decided)}</span></td>
              </tr>
            )
          })}
        </tbody>
      </table>
    </div>
  )
}
