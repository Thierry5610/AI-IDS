/**
 * Settings — read-only configuration & live ingest status.
 * No mutations: the AE threshold, model roster, and stream split are fixed config;
 * this page surfaces them plus whether the live pipeline is currently flowing.
 */
import { useMemo }        from 'react'
import Shell              from '../components/shell/Shell'
import KpiCard            from '../components/ui/KpiCard'
import StatusStrip        from '../components/ui/StatusStrip'
import '../components/settings/Settings.css'
import { MODELS, SUPERVISED, AE_MODEL, AE_THRESHOLD } from '../constants/models'
import { fmt }            from '../lib/format'
import { useAlertStore }   from '../store/alertStore'
import { useAnomalyStore } from '../store/anomalyStore'

const ICONS = {
  shield: '<path d="M12 3l7.5 3v6.2c0 5.4-3.6 8.7-7.5 9.8-3.9-1.1-7.5-4.4-7.5-9.8V6L12 3z"/>',
  radar:  '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3.6" fill="currentColor" stroke="none" opacity="0.18"/><circle cx="12" cy="12" r="3.6"/><circle cx="12" cy="12" r="0.6" fill="currentColor" stroke="none"/>',
  gauge:  '<path d="M12 13l4-4"/><circle cx="12" cy="13" r="0.6" fill="currentColor" stroke="none"/><path d="M4 16a8 8 0 1116 0"/>',
  report: '<rect x="5" y="3" width="14" height="18" rx="2"/><rect x="8" y="13" width="2" height="5" fill="currentColor" stroke="none"/><rect x="11.3" y="10" width="2" height="8" fill="currentColor" stroke="none"/><rect x="14.6" y="7" width="2" height="11" fill="currentColor" stroke="none"/>',
}

function Row({ k, v, accent }) {
  return (
    <div className="set-row">
      <span className="set-k">{k}</span>
      <span className={`set-v${accent ? ' accent' : ''}`}>{v}</span>
    </div>
  )
}

export default function Settings() {
  const alerts    = useAlertStore(s => s.alerts)
  const anomalies = useAnomalyStore(s => s.anomalies)

  const lastEvent = useMemo(() => {
    const ts = [...alerts, ...anomalies].map(e => new Date(e.timestamp).getTime()).filter(t => !Number.isNaN(t))
    return ts.length ? new Date(Math.max(...ts)).toISOString() : null
  }, [alerts, anomalies])

  const flowing = alerts.length > 0 || anomalies.length > 0

  return (
    <Shell title="Settings">

      {/* Live ingest snapshot */}
      <div className="kpi-grid">
        <KpiCard
          label="Live Pipeline" featured
          value={flowing ? 'Active' : 'Idle'}
          icon={ICONS.gauge}
          delta={lastEvent ? { text: `last ${fmt.time(lastEvent)}`, direction: null } : null}
        />
        <KpiCard label="Alerts Received" value={alerts.length} icon={ICONS.shield}
          delta={{ text: 'ids:attacks', direction: null }} />
        <KpiCard label="Anomalies Received" value={anomalies.length} icon={ICONS.radar}
          delta={{ text: 'ids:anomalies', direction: anomalies.length ? 'bad' : null }} />
        <KpiCard label="Models" value="5 / 5" icon={ICONS.report}
          delta={{ text: 'all loaded', direction: 'good' }} />
      </div>

      {/* Detection config + pipeline */}
      <div className="row-2">
        <div className="card">
          <div className="card-header"><span className="card-title">Detection Configuration</span></div>
          <div className="set-kv">
            <Row k="Autoencoder threshold" v={AE_THRESHOLD} accent />
            <Row k="Threshold basis" v="95th-pct benign error · fixed" />
            <Row k="Supervised features" v="raw (unscaled)" />
            <Row k="Autoencoder features" v="StandardScaler" />
            <Row k="Danger class" v="is_attack → ids:attacks · pages" />
            <Row k="Warning class" v="is_anomalous → dashboard only" />
          </div>
          <div className="set-note">
            danger and warning are distinct and never merged. The AE threshold is fixed for
            the original system (the cross-dataset false-positive rate is a research finding,
            not a defect).
          </div>
        </div>

        <div className="card">
          <div className="card-header"><span className="card-title">Pipeline</span></div>
          <StatusStrip />
          <div className="set-note">
            eBPF sensor → publisher → Redis Streams → bridge (SSE) → dashboard.
            Inference service serves the five models; the notifier pages Telegram on danger.
          </div>
        </div>
      </div>

      {/* Models + streams/buffers */}
      <div className="row-2">
        <div className="card">
          <div className="card-header"><span className="card-title">Model Roster</span></div>
          <div className="set-models">
            {SUPERVISED.map(m => (
              <div className="set-model" key={m.id}>
                <span className="set-model-dot" style={{ background: m.color }} />
                <span className="set-model-name">{m.label}</span>
                <span className="set-model-role">classifier · raw features</span>
              </div>
            ))}
            <div className="set-model">
              <span className="set-model-dot" style={{ background: AE_MODEL.color }} />
              <span className="set-model-name">{AE_MODEL.label}</span>
              <span className="set-model-role">anomaly detector · scaled</span>
            </div>
          </div>
        </div>

        <div className="card">
          <div className="card-header"><span className="card-title">Streams &amp; Buffers</span></div>
          <div className="set-kv">
            <Row k="Attack stream" v="ids:attacks" />
            <Row k="Anomaly stream" v="ids:anomalies" />
            <Row k="Bridge endpoints" v="/stream/attacks · /stream/anomalies" />
            <Row k="Alert buffer" v="200 (ring)" />
            <Row k="Anomaly buffer" v="500 (ring)" />
            <Row k="Transport" v="SSE · XREAD fan-out" />
          </div>
          <div className="set-note">
            Each browser tails the streams independently from history, so every client
            receives every event (broadcast, not a shared consumer group).
          </div>
        </div>
      </div>

    </Shell>
  )
}
