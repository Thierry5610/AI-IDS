/**
 * FlowTape — dense terminal-style live feed of merged flows (newest-first).
 * Each row: time · class bar · src→dst · proto · label · metric.
 * Attack rows are severity-coloured; anomaly rows are violet. The left class bar
 * keeps danger vs warning scannable.
 */
import './Flows.css'
import { fmt } from '../../lib/format'

const SEV_COLOR = {
  critical: 'var(--red)', high: 'var(--amber)', medium: 'var(--cyan)',
  low: 'var(--lime)', anomaly: 'var(--violet)',
}

function Row({ flow }) {
  const accent = SEV_COLOR[flow.severity] ?? 'var(--muted)'
  const metric = flow.metric == null ? '—'
    : flow.metricKind === 'conf' ? fmt.pct(flow.metric) : fmt.num(flow.metric)

  return (
    <div className={`tape-row ${flow.cls}`}>
      <span className="tape-bar" style={{ background: accent }} />
      <span className="tape-time">{fmt.time(flow.ts)}</span>
      <span className="tape-cls" style={{ color: accent }}>
        {flow.cls === 'attack' ? 'ATK' : 'ANO'}
      </span>
      <span className="tape-flow">{flow.identity ? fmt.flow(flow.identity) : (flow.flow_id ?? '—')}</span>
      <span className="tape-proto">{fmt.proto(flow.identity?.protocol)}</span>
      <span className="tape-label" style={{ color: flow.cls === 'anomaly' ? 'var(--violet)' : 'var(--text)' }}>
        {flow.label}
      </span>
      <span className="tape-metric" style={{ color: accent }}>{metric}</span>
    </div>
  )
}

export default function FlowTape({ flows }) {
  if (flows.length === 0) {
    return <div className="tape-empty">no flows on the wire — sensor idle or filtered out</div>
  }
  return (
    <div className="tape">
      <div className="tape-head">
        <span className="tape-bar" />
        <span className="tape-time">time</span>
        <span className="tape-cls">cls</span>
        <span className="tape-flow">flow</span>
        <span className="tape-proto">proto</span>
        <span className="tape-label">label</span>
        <span className="tape-metric">metric</span>
      </div>
      <div className="tape-body">
        {flows.map(f => <Row key={f.key} flow={f} />)}
      </div>
    </div>
  )
}
