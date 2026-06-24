/**
 * Research / AE — the dissertation's headline finding.
 * The autoencoder's cross-dataset transfer failure (~75% of benign flagged
 * anomalous off-domain) is framed as the reported FINDING, not a defect.
 * The ~75% is a documented dissertation result (see project-decisions),
 * shown as "reported"; everything else is live-derived. No fabricated numbers.
 */
import { useMemo }        from 'react'
import Shell              from '../components/shell/Shell'
import KpiCard            from '../components/ui/KpiCard'
import ScoreHistogram     from '../components/research/ScoreHistogram'
import '../components/research/Research.css'
import { AE_THRESHOLD }   from '../constants/models'
import { fmt }            from '../lib/format'
import { useAlertStore }   from '../store/alertStore'
import { useAnomalyStore } from '../store/anomalyStore'

// Documented dissertation finding — reported cross-dataset benign false-positive
// rate at the fixed 0.0726 threshold. Not live-derived; labelled "reported".
const REPORTED_XDOMAIN_FP = 0.75

const ICONS = {
  radar:  '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3.6" fill="currentColor" stroke="none" opacity="0.18"/><circle cx="12" cy="12" r="3.6"/><circle cx="12" cy="12" r="0.6" fill="currentColor" stroke="none"/>',
  gauge:  '<path d="M12 13l4-4"/><circle cx="12" cy="13" r="0.6" fill="currentColor" stroke="none"/><path d="M4 16a8 8 0 1116 0"/>',
  bolt:   '<path d="M13 3L5 13h5l-1 8 8-10h-5l1-8z"/>',
  shield: '<path d="M12 3l7.5 3v6.2c0 5.4-3.6 8.7-7.5 9.8-3.9-1.1-7.5-4.4-7.5-9.8V6L12 3z"/>',
}

export default function Research() {
  const alerts    = useAlertStore(s => s.alerts)
  const anomalies = useAnomalyStore(s => s.anomalies)

  const scores = useMemo(() => {
    const out = []
    for (const x of anomalies) {
      const s = x.model_votes?.autoencoder?.anomaly_score
      if (s != null) out.push(s)
    }
    for (const a of alerts) {
      const s = a.model_votes?.autoencoder?.anomaly_score
      if (s != null) out.push(s)
    }
    return out
  }, [alerts, anomalies])

  const avgScore = scores.length ? scores.reduce((a, b) => a + b, 0) / scores.length : 0

  return (
    <Shell title="Research / AE">

      {/* KPI row */}
      <div className="kpi-grid">
        <KpiCard
          label="Cross-Dataset Benign FP" featured
          value={`~${Math.round(REPORTED_XDOMAIN_FP * 100)}%`}
          icon={ICONS.radar}
          delta={{ text: 'reported finding', direction: null }}
        />
        <KpiCard label="AE Threshold" value={AE_THRESHOLD} icon={ICONS.gauge}
          delta={{ text: 'fixed · 95th pct', direction: null }} />
        <KpiCard label="AE Events" value={anomalies.length} icon={ICONS.bolt}
          delta={{ text: 'ids:anomalies', direction: anomalies.length ? 'bad' : null }} />
        <KpiCard label="Avg Score (live)" value={scores.length ? fmt.num(avgScore) : '—'}
          icon={ICONS.shield}
          delta={scores.length ? { text: `${scores.length} samples`, direction: null } : null} />
      </div>

      {/* The finding */}
      <div className="card">
        <div className="card-header">
          <span className="card-title">The Finding<span className="rs-tag">reported result</span></span>
        </div>
        <p className="rs-finding">
          Trained on CICIDS2017 and evaluated <b>cross-dataset</b>, the autoencoder flags{' '}
          <span className="hl">~{Math.round(REPORTED_XDOMAIN_FP * 100)}% of benign traffic as anomalous</span>{' '}
          at the fixed {AE_THRESHOLD} threshold. This is the dissertation's <b>headline finding,
          not a defect</b>: it characterises the domain gap that most published IDS work avoids by
          never testing cross-dataset. A supervised retrain to "fix" the autoencoder is off the
          table — it would erase the very result being reported. The threshold stays fixed for the
          original system.
        </p>
      </div>

      {/* Distribution + supervised/AE split */}
      <div className="row-6535">
        <div className="card">
          <div className="card-header">
            <div>
              <span className="card-title">AE Score Distribution</span>
              <div style={{ fontSize: 11, color: 'var(--muted-2)', marginTop: 2 }}>
                live reconstruction error vs the fixed threshold
              </div>
            </div>
          </div>
          <ScoreHistogram scores={scores} threshold={AE_THRESHOLD} />
        </div>

        <div className="card">
          <div className="card-header"><span className="card-title">Two Signal Classes</span></div>
          <div className="rs-split">
            <div className="rs-split-cell danger">
              <div className="rs-split-head">
                <span className="rs-split-dot" style={{ background: 'var(--red)' }} />
                <span className="rs-split-title">Supervised</span>
              </div>
              <div className="rs-split-num" style={{ color: 'var(--red)' }}>{alerts.length}</div>
              <div className="rs-split-desc">
                is_attack → ids:attacks. Operational "danger" — pages Telegram. Quiet on benign.
              </div>
            </div>
            <div className="rs-split-cell warning">
              <div className="rs-split-head">
                <span className="rs-split-dot" style={{ background: 'var(--violet)' }} />
                <span className="rs-split-title">Autoencoder</span>
              </div>
              <div className="rs-split-num" style={{ color: 'var(--violet)' }}>{anomalies.length}</div>
              <div className="rs-split-desc">
                is_anomalous → ids:anomalies. Research "warning" — dashboard only, never pages.
              </div>
            </div>
          </div>
          <div className="rs-note">
            danger and warning are distinct classes and never merged. The high AE flag rate is the
            reported result; the supervised models carry the operational verdict.
          </div>
        </div>
      </div>

      {/* Method / threshold */}
      <div className="card">
        <div className="card-header"><span className="card-title">Threshold &amp; Method</span></div>
        <div className="rs-kv">
          <div className="rs-kv-row"><span className="k">Anomaly threshold</span><span className="v">{AE_THRESHOLD}</span></div>
          <div className="rs-kv-row"><span className="k">Basis</span><span className="v">95th percentile of benign reconstruction error</span></div>
          <div className="rs-kv-row"><span className="k">Scaling</span><span className="v">StandardScaler (benign-fit) — AE only</span></div>
          <div className="rs-kv-row"><span className="k">Adaptivity</span><span className="v">fixed for the original system</span></div>
          <div className="rs-kv-row"><span className="k">Training set</span><span className="v">CICIDS2017</span></div>
          <div className="rs-kv-row"><span className="k">Evaluation</span><span className="v">cross-dataset (domain transfer)</span></div>
        </div>
      </div>

    </Shell>
  )
}
