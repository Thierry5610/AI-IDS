/**
 * Pure live-behavioural stats for the Models page.
 * Everything is derived from the streams — no static/fabricated metrics.
 *   alerts    : alertStore (each carries model_votes, agreement, source_model)
 *   anomalies : anomalyStore (AE warning class)
 */
import { SUPERVISED, AE_THRESHOLD } from '../constants/models'

const mean = arr => (arr.length ? arr.reduce((a, b) => a + b, 0) / arr.length : 0)

/**
 * @returns {{
 *   total:number, consensusRate:number,
 *   supervised: Array<{id,wins,winRate,votes,avgConfidence,agreeShare}>,
 *   ae: {anomalousCount:number, anomalousRate:number, avgScore:number, maxScore:number, threshold:number, samples:number}
 * }}
 */
export function computeModelStats(alerts, anomalies) {
  const total = alerts.length

  const supervised = SUPERVISED.map(m => {
    const confs = []
    let wins = 0, agree = 0
    for (const a of alerts) {
      const v = a.model_votes?.[m.id]
      if (v?.confidence != null) confs.push(v.confidence)
      if (a.source_model === m.id) wins++
      // does this model's label match the deciding (source/prediction) label?
      const decided = a.prediction?.label
      if (decided && v?.label === decided) agree++
    }
    return {
      id: m.id,
      votes: total,
      wins,
      winRate: total ? wins / total : 0,
      avgConfidence: mean(confs),
      agreeShare: total ? agree / total : 0,
    }
  })

  // Autoencoder: pull scores from the dedicated anomaly stream + the AE vote on alerts.
  const scores = []
  let anomalousCount = 0
  for (const x of anomalies) {
    const v = x.model_votes?.autoencoder
    if (v?.anomaly_score != null) { scores.push(v.anomaly_score); if (v.is_anomalous) anomalousCount++ }
  }
  for (const a of alerts) {
    const v = a.model_votes?.autoencoder
    if (v?.anomaly_score != null) scores.push(v.anomaly_score)
  }

  const ae = {
    anomalousCount,
    anomalousRate: anomalies.length ? anomalousCount / anomalies.length : 0,
    avgScore: mean(scores),
    maxScore: scores.length ? Math.max(...scores) : 0,
    threshold: AE_THRESHOLD,
    samples: scores.length,
  }

  const consensusRate = total
    ? alerts.filter(a => a.agreement?.consensus).length / total
    : 0

  return { total, consensusRate, supervised, ae }
}
