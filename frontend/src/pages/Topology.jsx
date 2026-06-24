/**
 * Topology — passive typed network graph.
 * Nodes = hosts (IPs) from the stream identity payloads; edges = src→dst flows.
 * A 2-way toggle swaps the data set: Attacks (ids:attacks) ⇄ Anomalies (ids:anomalies).
 * Host type is inferred from observed dst ports. Read-only / passive only.
 */
import { useMemo, useState } from 'react'
import Shell                 from '../components/shell/Shell'
import TopologyGraph         from '../components/topology/TopologyGraph'
import '../components/topology/TopologyGraph.css'
import { buildGraph }        from '../lib/topology'
import { HOST_TYPES, GLYPHS } from '../constants/hosts'
import { fmt }               from '../lib/format'
import { useAlertStore }     from '../store/alertStore'
import { useAnomalyStore }   from '../store/anomalyStore'

function Glyph({ name, color = 'currentColor' }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke={color}
         strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"
         dangerouslySetInnerHTML={{ __html: `<path d="${GLYPHS[name]}"/>` }} />
  )
}

function Legend({ mode, graph }) {
  const internal = graph.nodes.filter(n => n.internal).length
  return (
    <>
      <div className="topo-side-title">Host types</div>
      <div className="topo-legend">
        {Object.entries(HOST_TYPES).map(([key, m]) => (
          <div className="legend-row" key={key}>
            <span className="legend-swatch">
              <Glyph name={m.glyph} color={`var(--${m.colorKey === 'muted' ? 'muted' : m.colorKey})`} />
            </span>
            {m.label}
          </div>
        ))}
      </div>
      <div className="legend-note" style={{ marginTop: 14 }}>
        ◯ accent ring = internal host (RFC1918) · ◯ muted ring = external<br />
        edge pulse = {mode === 'anomalies'
          ? <span style={{ color: 'var(--violet)' }}>anomaly (AE warning)</span>
          : <span>attack severity (red→amber→cyan)</span>}
      </div>
      <div className="topo-summary">
        <div className="topo-stat"><b>{graph.nodes.length}</b><span>Hosts</span></div>
        <div className="topo-stat"><b>{graph.links.length}</b><span>Flows</span></div>
        <div className="topo-stat"><b>{internal}</b><span>Internal</span></div>
      </div>
    </>
  )
}

function NodeDetail({ node, mode }) {
  const meta = HOST_TYPES[node.type] || HOST_TYPES.host
  return (
    <div className="node-detail">
      <div className="node-detail-head">
        <span className="legend-swatch">
          <Glyph name={meta.glyph} color={mode === 'anomalies' ? 'var(--violet)' : `var(--${meta.colorKey})`} />
        </span>
        <span className="node-detail-ip">{node.id}</span>
      </div>

      <div className="node-kv">
        <div className="node-kv-row">
          <span className="k">Scope</span>
          <span className="v">
            <span className={`pill ${node.internal ? 'ok' : 'low'}`}>
              {node.internal ? 'internal' : 'external'}
            </span>
          </span>
        </div>
        <div className="node-kv-row"><span className="k">Type</span><span className="v">{meta.label}</span></div>
        <div className="node-kv-row"><span className="k">{mode === 'anomalies' ? 'Anomalies' : 'Attacks'}</span><span className="v">{node.count}</span></div>
        <div className="node-kv-row"><span className="k">Last seen</span><span className="v">{fmt.time(node.lastSeen)}</span></div>
      </div>

      {node.ports.length > 0 && (
        <div>
          <div className="topo-side-title">Ports seen</div>
          <div className="node-ports">
            {node.ports.map(p => <span className="port-chip" key={p}>:{p}</span>)}
          </div>
        </div>
      )}

      {node.topLabels.length > 0 && (
        <div>
          <div className="topo-side-title">Top {mode === 'anomalies' ? 'flags' : 'attacks'}</div>
          <div className="node-labels">
            {node.topLabels.map(l => (
              <div className="node-label-row" key={l.label}>
                <b>{l.label}</b><span>{l.count}</span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}

export default function Topology() {
  const alerts    = useAlertStore(s => s.alerts)
  const anomalies = useAnomalyStore(s => s.anomalies)
  const [mode, setMode]   = useState('attacks')
  const [selId, setSelId] = useState(null)

  const events = mode === 'attacks' ? alerts : anomalies
  const graph  = useMemo(() => buildGraph(events, mode), [events, mode])
  const selected = useMemo(
    () => graph.nodes.find(n => n.id === selId) ?? null,
    [graph, selId],
  )

  return (
    <Shell title="Topology">
      <div className="row-6535">
        <div className="card">
          <div className="card-header">
            <span className="card-title">Network Topology</span>
            <div className="topo-toggle" role="tablist" aria-label="Stream">
              <button className={`attacks ${mode === 'attacks' ? 'active' : ''}`}
                      onClick={() => { setMode('attacks'); setSelId(null) }}
                      aria-selected={mode === 'attacks'}>Attacks</button>
              <button className={`anomalies ${mode === 'anomalies' ? 'active' : ''}`}
                      onClick={() => { setMode('anomalies'); setSelId(null) }}
                      aria-selected={mode === 'anomalies'}>Anomalies</button>
            </div>
          </div>

          <div className="topo-stage">
            <div className="topo-galaxy" />
            <TopologyGraph
              graph={graph}
              mode={mode}
              selectedId={selId}
              onSelect={n => setSelId(n ? n.id : null)}
            />
            {graph.nodes.length === 0 && (
              <div className="topo-empty">
                no {mode === 'anomalies' ? 'anomalies' : 'flows'} observed — sensor idle
              </div>
            )}
          </div>
        </div>

        <div className="card">
          {selected
            ? <NodeDetail node={selected} mode={mode} />
            : <Legend mode={mode} graph={graph} />}
        </div>
      </div>
    </Shell>
  )
}
