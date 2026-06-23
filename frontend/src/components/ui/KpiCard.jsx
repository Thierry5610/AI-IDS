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
