/**
 * Pure graph derivation for the Topology page.
 * Turns a list of alert/anomaly events (each with an `identity` 5-tuple) into a
 * passive typed graph: nodes = hosts (IPs), links = aggregated src→dst flows.
 * No layout/state here — react-force-graph owns positioning.
 */
import { severityOf }                    from '../constants/attacks'
import { hostTypeFromPorts, isInternalIp } from '../constants/hosts'

const SEV_RANK = { ok: -1, low: 0, medium: 1, high: 2, critical: 3 }
const maxSev = (a, b) => ((SEV_RANK[b] ?? -1) > (SEV_RANK[a] ?? -1) ? b : a)

/**
 * @param {Array} events  alerts or anomalies (newest-first is fine)
 * @param {'attacks'|'anomalies'} kind
 * @returns {{nodes: Array, links: Array}}
 */
export function buildGraph(events, kind) {
  const nodes = new Map()   // ip → node
  const links = new Map()   // "src>dst" → link

  const touch = (ip, port, label, ts, isDst) => {
    if (!ip) return
    let n = nodes.get(ip)
    if (!n) {
      n = { id: ip, ports: new Set(), count: 0, labels: {}, internal: isInternalIp(ip), lastSeen: ts }
      nodes.set(ip, n)
    }
    n.count++
    if (isDst && port != null) n.ports.add(port)
    if (label) n.labels[label] = (n.labels[label] || 0) + 1
    if (ts && (!n.lastSeen || ts > n.lastSeen)) n.lastSeen = ts
  }

  for (const e of events) {
    const id = e.identity || {}
    const label = e.prediction?.label
    const ts = e.timestamp
    touch(id.src_ip, id.src_port, label, ts, false)
    touch(id.dst_ip, id.dst_port, label, ts, true)

    if (id.src_ip && id.dst_ip) {
      const key = `${id.src_ip}>${id.dst_ip}`
      let l = links.get(key)
      if (!l) { l = { source: id.src_ip, target: id.dst_ip, count: 0, sev: 'low' }; links.set(key, l) }
      l.count++
      if (kind === 'attacks') l.sev = maxSev(l.sev, severityOf(label))
    }
  }

  const nodeArr = [...nodes.values()].map(n => ({
    id: n.id,
    ports: [...n.ports].sort((a, b) => a - b),
    count: n.count,
    internal: n.internal,
    lastSeen: n.lastSeen,
    type: hostTypeFromPorts([...n.ports]),
    topLabels: Object.entries(n.labels)
      .sort((a, b) => b[1] - a[1]).slice(0, 3)
      .map(([label, count]) => ({ label, count })),
  }))

  return { nodes: nodeArr, links: [...links.values()] }
}
