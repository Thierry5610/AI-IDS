/**
 * ModelCard — per-model live stat card.
 * Two variants: supervised classifier (win-rate, avg confidence) and the
 * autoencoder anomaly detector (score vs threshold, anomalous rate).
 */
import './Models.css'
import { fmt } from '../../lib/format'

function Bar({ pct, color }) {
  return (
    <div className="m-bar">
      <i style={{ width: `${Math.min(Math.max(pct, 0), 1) * 100}%`, background: color }} />
    </div>
  )
}

export function SupervisedCard({ model, stat }) {
  return (
    <div className="card m-card">
      <div className="m-head">
        <span className="m-dot" style={{ background: model.color }} />
        <span className="m-name">{model.label}</span>
        <span className="m-short">{model.short}</span>
      </div>
      <div className="m-role">Classifier · raw features</div>

      <div className="m-stat-row">
        <span className="m-k">Win rate</span>
        <span className="m-v">{stat ? fmt.pct(stat.winRate) : '—'}</span>
      </div>
      <Bar pct={stat?.winRate ?? 0} color={model.color} />

      <div className="m-stat-row" style={{ marginTop: 12 }}>
        <span className="m-k">Avg confidence</span>
        <span className="m-v">{stat ? fmt.pct(stat.avgConfidence) : '—'}</span>
      </div>
      <Bar pct={stat?.avgConfidence ?? 0} color="var(--muted)" />

      <div className="m-foot">
        <span><b>{stat?.wins ?? 0}</b> wins</span>
        <span><b>{stat?.votes ?? 0}</b> votes</span>
        <span><b>{stat ? fmt.pct(stat.agreeShare) : '—'}</b> agree</span>
      </div>
    </div>
  )
}

export function AutoencoderCard({ model, ae }) {
  const ratio = ae.threshold ? Math.min(ae.avgScore / ae.threshold, 1) : 0
  return (
    <div className="card m-card m-card-ae">
      <div className="m-head">
        <span className="m-dot" style={{ background: model.color }} />
        <span className="m-name">{model.label}</span>
        <span className="m-short">{model.short}</span>
        <span className="pill anomaly" style={{ marginLeft: 'auto' }}>warning class</span>
      </div>
      <div className="m-role">Anomaly detector · StandardScaler</div>

      <div className="m-stat-row">
        <span className="m-k">Avg score vs threshold</span>
        <span className="m-v">{fmt.num(ae.avgScore)} / {ae.threshold}</span>
      </div>
      <div className="m-bar m-bar-ae">
        <i style={{ width: `${ratio * 100}%` }} />
        <span className="m-threshold" title={`threshold ${ae.threshold}`} />
      </div>

      <div className="m-foot">
        <span><b>{ae.samples}</b> samples</span>
        <span><b>{fmt.num(ae.maxScore)}</b> max</span>
        <span><b>{fmt.pct(ae.anomalousRate)}</b> anomalous</span>
      </div>
    </div>
  )
}
