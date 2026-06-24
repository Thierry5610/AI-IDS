/**
 * Flows — live dense "tape" merging both streams (attacks + anomalies) into one
 * flow-level ledger, newest-first. Flagged flows only (no benign stream).
 * Distinct from the attack-centric Alerts page; danger vs warning stays strict.
 */
import { useMemo, useState } from 'react'
import Shell             from '../components/shell/Shell'
import FlowTape          from '../components/flows/FlowTape'
import '../components/flows/Flows.css'
import { mergeFlows }    from '../lib/flows'
import { useAlertStore }   from '../store/alertStore'
import { useAnomalyStore } from '../store/anomalyStore'

const SEARCH_ICON = '<circle cx="11" cy="11" r="7"/><line x1="21" y1="21" x2="16.5" y2="16.5"/>'

const FILTERS = [
  { id: 'all',     label: 'All' },
  { id: 'attack',  label: 'Attacks' },
  { id: 'anomaly', label: 'Anomalies' },
]

function matches(f, q) {
  const s = q.trim().toLowerCase()
  if (!s) return true
  const id = f.identity ?? {}
  return [f.label, f.flow_id, id.src_ip, id.dst_ip, id.src_port, id.dst_port]
    .some(x => x != null && String(x).toLowerCase().includes(s))
}

export default function Flows() {
  const alerts    = useAlertStore(s => s.alerts)
  const anomalies = useAnomalyStore(s => s.anomalies)

  const [cls, setCls] = useState('all')
  const [q, setQ]     = useState('')

  const merged = useMemo(() => mergeFlows(alerts, anomalies), [alerts, anomalies])
  const shown  = useMemo(
    () => merged.filter(f => (cls === 'all' || f.cls === cls) && matches(f, q)),
    [merged, cls, q],
  )

  const nAtk = alerts.length
  const nAno = anomalies.length

  return (
    <Shell title="Flows">
      <div className="card">
        <div className="card-header">
          <span className="card-title">Flow Tape</span>
          <span style={{ fontSize: 11, color: 'var(--muted-2)' }}>flagged flows · live</span>
        </div>

        <div className="filter-bar">
          <div style={{ display: 'inline-flex', gap: 4, padding: 3,
                        background: 'var(--glass-bg-2)', border: '1px solid var(--border-strong)',
                        borderRadius: 99 }}>
            {FILTERS.map(f => (
              <button key={f.id}
                className={`filter-pill ${cls === f.id ? 'active' : ''}`}
                style={{ border: 'none', background: cls === f.id ? undefined : 'transparent' }}
                onClick={() => setCls(f.id)}>
                {f.label}
              </button>
            ))}
          </div>

          <div className="search-box">
            <span style={{ color: 'var(--muted-2)', display: 'flex' }}>
              <svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor"
                   strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"
                   dangerouslySetInnerHTML={{ __html: SEARCH_ICON }} />
            </span>
            <input value={q} onChange={e => setQ(e.target.value)}
                   placeholder="Search IP, label, or flow id…" aria-label="Search flows" />
          </div>

          <div className="flow-counts">
            <span className="flow-chip"><b>{shown.length}</b> shown</span>
            <span className="flow-chip"><span className="dot" style={{ background: 'var(--lime)' }} /><b>{nAtk}</b> attacks</span>
            <span className="flow-chip"><span className="dot" style={{ background: 'var(--violet)' }} /><b>{nAno}</b> anomalies</span>
          </div>
        </div>

        <FlowTape flows={shown} />
      </div>
    </Shell>
  )
}
