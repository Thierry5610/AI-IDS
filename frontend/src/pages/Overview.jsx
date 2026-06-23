import { useMemo }         from 'react'
import Shell               from '../components/shell/Shell'
import KpiCard             from '../components/ui/KpiCard'
import StatusStrip         from '../components/ui/StatusStrip'
import EnsembleGauge       from '../components/charts/EnsembleGauge'
import TrendChart          from '../components/charts/TrendChart'
import RadarChart          from '../components/charts/RadarChart'
import BubbleCluster       from '../components/charts/BubbleCluster'
import AlertLogStream      from '../components/alerts/AlertLogStream'
import { useAlertStore }   from '../store/alertStore'
import { useAnomalyStore } from '../store/anomalyStore'

// ── MITRE-style axis mapping (CICIDS2017 → 8 radar axes) ─────────────────────
const RADAR_MAP = {
  recon:      ['portscan'],
  bruteforce: ['patator'],
  dos:        ['dos goldeneye', 'dos hulk', 'dos slowhttptest', 'dos slowloris'],
  ddos:       ['ddos'],
  web:        ['web attack'],
  bot:        ['bot'],
  exploit:    ['heartbleed'],
  exfil:      ['infiltration'],
}

function toRadarData(alerts) {
  const counts = Object.fromEntries(Object.keys(RADAR_MAP).map(k => [k, 0]))
  alerts.forEach(a => {
    const l = (a.prediction?.label ?? '').toLowerCase()
    for (const [axis, matches] of Object.entries(RADAR_MAP)) {
      if (matches.some(m => l.includes(m))) { counts[axis]++; break }
    }
  })
  const max = Math.max(...Object.values(counts), 1)
  return Object.fromEntries(Object.entries(counts).map(([k, v]) => [k, v / max]))
}

// ── Bubble cluster: top-5 attack families ────────────────────────────────────
const BUBBLE_FAMILIES = [
  { label: 'DoS',         matches: ['dos'] },
  { label: 'PortScan',    matches: ['portscan'] },
  { label: 'Brute Force', matches: ['patator'] },
  { label: 'Web Attack',  matches: ['web attack'] },
  { label: 'DDoS',        matches: ['ddos'] },
]

function toBubbleData(alerts) {
  return BUBBLE_FAMILIES.map(f => ({
    label: f.label,
    count: alerts.filter(a =>
      f.matches.some(m => (a.prediction?.label ?? '').toLowerCase().includes(m))
    ).length,
  }))
}

// ── KPI helpers ───────────────────────────────────────────────────────────────
function consensusRate(alerts) {
  if (!alerts.length) return '—'
  const agreed = alerts.filter(a => a.agreement?.consensus).length
  return `${Math.round((agreed / alerts.length) * 100)}%`
}

// ── KPI icon strings ─────────────────────────────────────────────────────────
const ICONS = {
  shield: '<path d="M12 3l7.5 3v6.2c0 5.4-3.6 8.7-7.5 9.8-3.9-1.1-7.5-4.4-7.5-9.8V6L12 3z"/>',
  radar:  '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3.6" fill="currentColor" stroke="none" opacity="0.18"/><circle cx="12" cy="12" r="3.6"/><circle cx="12" cy="12" r="0.6" fill="currentColor" stroke="none"/>',
  report: '<rect x="5" y="3" width="14" height="18" rx="2"/><rect x="8" y="13" width="2" height="5" fill="currentColor" stroke="none"/><rect x="11.3" y="10" width="2" height="8" fill="currentColor" stroke="none"/><rect x="14.6" y="7" width="2" height="11" fill="currentColor" stroke="none"/>',
  check:  '<path d="M6 12l4 4 8-9"/>',
}

// ── Chip (stat badge in card header) ─────────────────────────────────────────
function Chip({ children }) {
  return (
    <span style={{
      fontFamily: 'var(--f-mono)', fontSize: 11, color: 'var(--lime)',
      background: 'var(--glass-bg-2)', border: '1px solid var(--border-strong)',
      padding: '4px 11px', borderRadius: 99,
    }}>
      {children}
    </span>
  )
}

// ── Page ─────────────────────────────────────────────────────────────────────
export default function Overview() {
  const alerts    = useAlertStore(s => s.alerts)
  const anomalies = useAnomalyStore(s => s.anomalies)

  const latest    = alerts[0] ?? null
  const radarData = useMemo(() => toRadarData(alerts), [alerts])
  const bubbles   = useMemo(() => toBubbleData(alerts), [alerts])
  const conRate   = useMemo(() => consensusRate(alerts), [alerts])
  const hasSignal = Object.values(radarData).some(v => v > 0)

  return (
    <Shell title="Overview">

      {/* ── KPI Row ─────────────────────────────────────────────────── */}
      <div className="kpi-grid">
        <KpiCard
          featured
          label="Live Attacks"
          value={alerts.length}
          icon={ICONS.shield}
          delta={alerts.length > 0
            ? { text: 'ids:attacks stream', direction: null }
            : null}
        />
        <KpiCard
          label="Anomalies"
          value={anomalies.length}
          icon={ICONS.radar}
          delta={anomalies.length > 0
            ? { text: 'ids:anomalies', direction: 'bad' }
            : null}
        />
        <KpiCard
          label="Models"
          value="5 / 5"
          icon={ICONS.report}
          delta={{ text: 'all loaded', direction: 'good' }}
        />
        <KpiCard
          label="Consensus Rate"
          value={conRate}
          icon={ICONS.check}
          delta={alerts.length > 0
            ? { text: 'last session', direction: 'good' }
            : null}
        />
      </div>

      {/* ── Row A: live feed + ensemble gauge ───────────────────────── */}
      <div className="row-6535">
        <div className="card">
          <div className="card-header">
            <span className="card-title">Live Alert Feed</span>
            <Chip>{alerts.length} events</Chip>
          </div>
          <AlertLogStream alerts={alerts} />
        </div>

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
      </div>

      {/* ── Row B: radar + bubbles ───────────────────────────────────── */}
      <div className="row-3565">
        <div className="card">
          <div className="card-header">
            <div>
              <span className="card-title">Threat Coverage</span>
              <div style={{ fontSize: 11, color: 'var(--muted-2)', marginTop: 2 }}>
                by attack category
              </div>
            </div>
            <Chip>{hasSignal ? 'active' : '—'}</Chip>
          </div>
          <RadarChart data={radarData} />
        </div>

        <div className="card">
          <div className="card-header">
            <div>
              <span className="card-title">Attack Surface by Vector</span>
              <div style={{ fontSize: 11, color: 'var(--muted-2)', marginTop: 2 }}>
                flagged events, session
              </div>
            </div>
          </div>
          <BubbleCluster data={bubbles} />
        </div>
      </div>

      {/* ── Row C: trend chart + system status ──────────────────────── */}
      <div className="row-6535">
        <div className="card">
          <div className="card-header">
            <div>
              <span className="card-title">Detection Trend</span>
              <div style={{ fontSize: 11, color: 'var(--muted-2)', marginTop: 2 }}>
                attacks detected, last 60 min
              </div>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 6,
                          fontSize: 11, color: 'var(--muted)' }}>
              <span style={{ width: 7, height: 7, borderRadius: '50%',
                             background: 'var(--lime)', flexShrink: 0 }} />
              Detected
            </div>
          </div>
          <TrendChart alerts={alerts} />
        </div>

        <div className="card">
          <div className="card-header">
            <span className="card-title">System Status</span>
            <span style={{ fontSize: 11, color: 'var(--muted-2)' }}>active components</span>
          </div>
          <StatusStrip />
        </div>
      </div>

    </Shell>
  )
}
