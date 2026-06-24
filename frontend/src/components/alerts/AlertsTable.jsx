/**
 * AlertsTable — paginated, expandable table of supervised attack alerts.
 * Presentational: receives an already-sliced page of alerts; owns only the
 * per-row expand state. Severity / formatting / model metadata are reused from
 * the shared constants + format helpers. Table chrome (.table, .pill, …) comes
 * from shell.css; only the new classes live in AlertsTable.css.
 */
import { useState }     from 'react'
import './AlertsTable.css'
import { fmt }          from '../../lib/format'
import { severityOf }   from '../../constants/attacks'
import { SUPERVISED, AE_THRESHOLD, modelById } from '../../constants/models'

const CHEVRON = '<path d="M6 9l6 6 6-6"/>'

/** "increases" → up (pushes toward attack), "decreases" → down */
function dirClass(direction) {
  return (direction ?? '').toLowerCase().startsWith('inc') ? 'up' : 'down'
}
function dirArrow(direction) {
  return dirClass(direction) === 'up' ? '↑' : '↓'
}

function topFactor(alert) {
  return alert.explanation?.top_features?.[0] ?? null
}

function ShapDetail({ alert }) {
  const feats = alert.explanation?.top_features ?? []
  if (feats.length === 0) {
    return <div className="shap-empty">no SHAP explanation for this alert</div>
  }
  const max = Math.max(...feats.map(f => Math.abs(Number(f.shap_value) || 0)), 1e-9)
  return (
    <div className="shap-list">
      {feats.map((f, i) => {
        const dc  = dirClass(f.direction)
        const pct = Math.min((Math.abs(Number(f.shap_value) || 0) / max) * 100, 100)
        return (
          <div className="shap-row" key={`${f.feature}-${i}`}>
            <span className="shap-feat">{f.feature}</span>
            <span className="shap-vals">
              val <b>{fmt.num(f.value)}</b> · shap <b>{fmt.num(f.shap_value)}</b>{' '}
              <span className={`shap-dir ${dc}`}>{dirArrow(f.direction)}</span>
            </span>
            <span className="shap-bar"><i className={dc} style={{ width: `${pct}%` }} /></span>
          </div>
        )
      })}
    </div>
  )
}

function VotesStrip({ alert }) {
  const votes = alert.model_votes ?? {}
  const ae    = votes.autoencoder
  return (
    <div className="votes">
      {SUPERVISED.map(m => {
        const v = votes[m.id]
        return (
          <div className="vote-row" key={m.id}>
            <span className="vote-dot" style={{ background: m.color }} />
            <span className="vote-name">{m.label}</span>
            <span className="vote-label">{v?.label ?? '—'}</span>
            <span className="vote-stat">{v ? fmt.pct(v.confidence) : '—'}</span>
          </div>
        )
      })}
      <div className="vote-row">
        <span className="vote-dot" style={{ background: modelById('autoencoder').color }} />
        <span className="vote-name">Autoencoder</span>
        <span className="vote-label">
          {ae ? `score ${fmt.num(ae.anomaly_score)} / ${ae.threshold ?? AE_THRESHOLD}` : '—'}
        </span>
        <span className={`vote-stat ${ae?.is_anomalous ? 'anomaly' : ''}`}>
          {ae ? (ae.is_anomalous ? 'anomalous' : 'normal') : '—'}
        </span>
      </div>
    </div>
  )
}

function AlertRow({ alert }) {
  const [open, setOpen] = useState(false)

  const label  = alert.prediction?.label ?? 'Unknown'
  const sev    = severityOf(label)
  const src    = modelById(alert.source_model)
  const tf     = topFactor(alert)
  const agree  = alert.agreement
  const full   = agree?.consensus

  return (
    <>
      <tr className={`alert-row ${open ? 'open' : ''}`}
          onClick={() => setOpen(o => !o)}>
        <td><span className={`pill ${sev}`}>{sev}</span></td>
        <td>{label}</td>
        <td className="mono">{fmt.flow(alert.identity)}</td>
        <td>
          <span className="verdict">
            <span className="verdict-dot" style={{ background: src.color }} />
            <span className="verdict-name">{src.short}</span>
            <span className="verdict-conf">{fmt.pct(alert.prediction?.confidence)}</span>
          </span>
        </td>
        <td>
          <span className={`consensus ${full ? 'full' : ''}`}>
            {agree ? `${agree.agreeing}/${agree.total}` : '—'}
          </span>
        </td>
        <td>
          {tf ? (
            <span className="shap-chip" title={`${tf.feature} (${tf.direction})`}>
              <span className={`shap-dir ${dirClass(tf.direction)}`}>{dirArrow(tf.direction)}</span>
              {tf.feature}
            </span>
          ) : (
            <span className="shap-chip none">no shap</span>
          )}
        </td>
        <td className="mono">{fmt.time(alert.timestamp)}</td>
        <td style={{ textAlign: 'right' }}>
          <span className="row-chevron">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor"
                 strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"
                 dangerouslySetInnerHTML={{ __html: CHEVRON }} />
          </span>
        </td>
      </tr>

      {open && (
        <tr className="alert-detail">
          <td className="detail-cell" colSpan={8}>
            <div className="detail-panel">
              <div>
                <div className="detail-block-title">Top SHAP factors</div>
                <ShapDetail alert={alert} />
              </div>
              <div>
                <div className="detail-block-title">Model votes</div>
                <VotesStrip alert={alert} />
              </div>
              <div className="detail-meta">
                <span>flow_id <b>{alert.flow_id ?? '—'}</b></span>
                <span>proto <b>{fmt.proto(alert.identity?.protocol)}</b></span>
                <span>source <b>{src.label}</b></span>
                <span>time <b>{alert.timestamp ?? '—'}</b></span>
              </div>
            </div>
          </td>
        </tr>
      )}
    </>
  )
}

export default function AlertsTable({ alerts }) {
  if (alerts.length === 0) {
    return <div className="alerts-empty">no alerts match — sensor idle or filtered out</div>
  }
  return (
    <div className="table-wrap">
      <table className="alerts-table">
        <thead>
          <tr>
            <th>Severity</th>
            <th>Attack</th>
            <th>Flow</th>
            <th>Verdict</th>
            <th>Consensus</th>
            <th>Top factor</th>
            <th>Time</th>
            <th aria-label="expand" />
          </tr>
        </thead>
        <tbody>
          {alerts.map((a, i) => (
            <AlertRow key={`${a.flow_id ?? 'a'}-${a.timestamp ?? ''}-${i}`} alert={a} />
          ))}
        </tbody>
      </table>
    </div>
  )
}
