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
