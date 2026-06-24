/**
 * Models — five-model comparison, live behavioural only (no fabricated metrics).
 * Featured element: the concentric ensemble consensus gauge (latest alert).
 */
import { useMemo }        from 'react'
import Shell              from '../components/shell/Shell'
import KpiCard            from '../components/ui/KpiCard'
import EnsembleGauge      from '../components/charts/EnsembleGauge'
import { SupervisedCard, AutoencoderCard } from '../components/models/ModelCard'
import VoteMatrix         from '../components/models/VoteMatrix'
import '../components/models/Models.css'
import { SUPERVISED, AE_MODEL } from '../constants/models'
import { computeModelStats }    from '../lib/modelStats'
import { fmt }            from '../lib/format'
import { useAlertStore }  from '../store/alertStore'
import { useAnomalyStore } from '../store/anomalyStore'

const ICONS = {
  report: '<rect x="5" y="3" width="14" height="18" rx="2"/><rect x="8" y="13" width="2" height="5" fill="currentColor" stroke="none"/><rect x="11.3" y="10" width="2" height="8" fill="currentColor" stroke="none"/><rect x="14.6" y="7" width="2" height="11" fill="currentColor" stroke="none"/>',
  check:  '<path d="M6 12l4 4 8-9"/>',
  bolt:   '<path d="M13 3L5 13h5l-1 8 8-10h-5l1-8z"/>',
  radar:  '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3.6" fill="currentColor" stroke="none" opacity="0.18"/><circle cx="12" cy="12" r="3.6"/><circle cx="12" cy="12" r="0.6" fill="currentColor" stroke="none"/>',
}

export default function Models() {
  const alerts    = useAlertStore(s => s.alerts)
  const anomalies = useAnomalyStore(s => s.anomalies)

  const stats  = useMemo(() => computeModelStats(alerts, anomalies), [alerts, anomalies])
  const latest = alerts[0] ?? null
  const statById = useMemo(
    () => Object.fromEntries(stats.supervised.map(s => [s.id, s])),
    [stats],
  )
  const maxWin = Math.max(...stats.supervised.map(s => s.winRate), 0.0001)

  return (
    <Shell title="Models">

      {/* KPI row */}
      <div className="kpi-grid">
        <KpiCard
          label="Consensus Rate" featured
          value={stats.total ? fmt.pct(stats.consensusRate) : '—'}
          icon={ICONS.check}
          delta={stats.total ? { text: `${stats.total} decisions`, direction: null } : null}
        />
        <KpiCard
          label="Models" value="5 / 5" icon={ICONS.report}
          delta={{ text: '4 supervised · 1 AE', direction: 'good' }}
        />
        <KpiCard
          label="Decisions" value={stats.total} icon={ICONS.bolt}
          delta={stats.total ? { text: 'ids:attacks', direction: null } : null}
        />
        <KpiCard
          label="Anomalous Rate" value={anomalies.length ? fmt.pct(stats.ae.anomalousRate) : '—'}
          icon={ICONS.radar}
          delta={anomalies.length ? { text: `${stats.ae.samples} AE samples`, direction: 'bad' } : null}
        />
      </div>

      {/* Featured: ensemble gauge + source-model win distribution */}
      <div className="row-3565">
        <div className="card">
          <div className="card-header">
            <div>
              <span className="card-title">Ensemble Consensus</span>
              <div style={{ fontSize: 11, color: 'var(--muted-2)', marginTop: 2 }}>
                latest alert · all models
              </div>
            </div>
          </div>
          <EnsembleGauge
            votes={latest?.model_votes}
            agreement={latest?.agreement}
            label={latest?.prediction?.label}
          />
        </div>

        <div className="card">
          <div className="card-header">
            <div>
              <span className="card-title">Deciding Model</span>
              <div style={{ fontSize: 11, color: 'var(--muted-2)', marginTop: 2 }}>
                share of alerts where each model had the highest confidence
              </div>
            </div>
          </div>
          <div className="win-list">
            {SUPERVISED.map(m => {
              const s = statById[m.id]
              return (
                <div className="win-row" key={m.id}>
                  <span className="win-name">
                    <span className="m-dot" style={{ background: m.color }} />{m.label}
                  </span>
                  <span className="win-bar">
                    <i style={{ width: `${(s ? s.winRate / maxWin : 0) * 100}%`, background: m.color }} />
                  </span>
                  <span className="win-pct">{s ? fmt.pct(s.winRate) : '—'}</span>
                </div>
              )
            })}
          </div>
          <div className="win-consensus">
            <b>{stats.total ? fmt.pct(stats.consensusRate) : '—'}</b>
            <span>full consensus across {stats.total} decisions</span>
          </div>
        </div>
      </div>

      {/* Per-model cards */}
      <div className="models-grid">
        {SUPERVISED.map(m => (
          <SupervisedCard key={m.id} model={m} stat={statById[m.id]} />
        ))}
      </div>

      <AutoencoderCard model={AE_MODEL} ae={stats.ae} />

      {/* Vote matrix */}
      <div className="card">
        <div className="card-header">
          <span className="card-title">Recent Decisions · Model Votes</span>
          <span style={{ fontSize: 11, color: 'var(--muted-2)' }}>amber = disagrees with verdict</span>
        </div>
        <VoteMatrix alerts={alerts} />
      </div>

    </Shell>
  )
}
