/**
 * Pure flow merge for the Flows tape.
 * Combines the two streams into one chronological, flow-level ledger. There is no
 * benign-flow stream, so this is flagged flows only. danger (attack) vs warning
 * (anomaly) is preserved on every row — never merged into one class.
 */
import { severityOf }  from '../constants/attacks'
import { AE_THRESHOLD } from '../constants/models'

const ms = ts => { const t = new Date(ts).getTime(); return Number.isNaN(t) ? 0 : t }

/**
 * @returns Array<{ ts, cls:'attack'|'anomaly', identity, label, metric, metricKind, severity, flow_id, key }>
 *          newest-first.
 */
export function mergeFlows(alerts, anomalies, cap = 120) {
  const rows = []

  alerts.forEach((a, i) => {
    rows.push({
      ts: a.timestamp, _t: ms(a.timestamp),
      cls: 'attack',
      identity: a.identity,
      label: a.prediction?.label ?? 'Unknown',
      metric: a.prediction?.confidence ?? null,
      metricKind: 'conf',
      severity: severityOf(a.prediction?.label),
      flow_id: a.flow_id,
      key: `atk-${a.flow_id ?? 'a'}-${a.timestamp ?? ''}-${i}`,
    })
  })

  anomalies.forEach((x, i) => {
    rows.push({
      ts: x.timestamp, _t: ms(x.timestamp),
      cls: 'anomaly',
      identity: x.identity,
      label: 'Anomaly',
      metric: x.model_votes?.autoencoder?.anomaly_score ?? null,
      metricKind: 'score',
      severity: 'anomaly',
      flow_id: x.flow_id,
      key: `ano-${x.flow_id ?? 'a'}-${x.timestamp ?? ''}-${i}`,
    })
  })

  rows.sort((a, b) => b._t - a._t)
  return rows.slice(0, cap)
}

export { AE_THRESHOLD }
