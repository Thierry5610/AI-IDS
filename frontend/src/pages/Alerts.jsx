/**
 * Alerts — filterable, paginated table of the ids:attacks stream (supervised
 * "danger" verdicts). Reads the shared alertStore (no per-page stream setup).
 *
 * Live + paging: page 1 with no search streams live from the store. Searching or
 * leaving page 1 freezes a snapshot so rows don't shift under the cursor; a
 * "N new" pill jumps back to live. Anomalies (AE "warning") are NOT shown here.
 */
import { useMemo, useState } from 'react'
import Shell             from '../components/shell/Shell'
import AlertsTable       from '../components/alerts/AlertsTable'
import { useAlertStore } from '../store/alertStore'

const PAGE_SIZE = 15

const SEARCH_ICON = '<circle cx="11" cy="11" r="7"/><line x1="21" y1="21" x2="16.5" y2="16.5"/>'
const PREV_ICON   = '<path d="M15 5l-7 7 7 7"/>'
const NEXT_ICON   = '<path d="M9 5l7 7-7 7"/>'

function Icon({ path, size = 16 }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor"
         strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"
         width={size} height={size}
         dangerouslySetInnerHTML={{ __html: path }} />
  )
}

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

function filterAlerts(list, q) {
  const s = q.trim().toLowerCase()
  if (!s) return list
  return list.filter(a => {
    const id = a.identity ?? {}
    return [
      a.prediction?.label, a.flow_id,
      id.src_ip, id.dst_ip, id.src_port, id.dst_port,
    ].some(x => x != null && String(x).toLowerCase().includes(s))
  })
}

const sameAlert = (a, b) =>
  a && b && a.flow_id === b.flow_id && a.timestamp === b.timestamp

export default function Alerts() {
  const alerts = useAlertStore(s => s.alerts)

  const [q, setQ]               = useState('')
  const [page, setPage]         = useState(1)
  const [snapshot, setSnapshot] = useState(null)   // null = live

  const live    = snapshot === null
  const working = live ? alerts : snapshot

  const filtered   = useMemo(() => filterAlerts(working, q), [working, q])
  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE))
  const safePage   = Math.min(page, totalPages)
  const start      = (safePage - 1) * PAGE_SIZE
  const slice      = filtered.slice(start, start + PAGE_SIZE)

  // How many alerts have arrived since the snapshot was frozen.
  const newCount = useMemo(() => {
    if (live || !snapshot?.length) return 0
    const idx = alerts.findIndex(a => sameAlert(a, snapshot[0]))
    return idx >= 0 ? idx : alerts.length
  }, [live, snapshot, alerts])

  function onSearch(e) {
    const v = e.target.value
    if (v && snapshot === null) setSnapshot(alerts)   // freeze on first search
    setQ(v); setPage(1)
  }
  function goto(p) {
    if (p < 1 || p > totalPages) return
    if (p !== 1 && snapshot === null) setSnapshot(alerts)   // freeze on leaving page 1
    setPage(p)
  }
  function jumpLive() {
    setSnapshot(null); setQ(''); setPage(1)
  }

  const lo = filtered.length === 0 ? 0 : start + 1
  const hi = Math.min(start + PAGE_SIZE, filtered.length)

  return (
    <Shell title="Alerts">
      <div className="card">
        <div className="card-header">
          <span className="card-title">Attack Alerts</span>
          <Chip>{alerts.length} total{live ? ' · live' : ''}</Chip>
        </div>

        <div className="filter-bar">
          <div className="search-box">
            <span style={{ color: 'var(--muted-2)', display: 'flex' }}>
              <Icon path={SEARCH_ICON} size={15} />
            </span>
            <input
              value={q}
              onChange={onSearch}
              placeholder="Search IP, attack, or flow id…"
              aria-label="Search alerts"
            />
          </div>

          {!live && (newCount > 0
            ? <button className="new-pill" onClick={jumpLive}>
                <span className="dot" />{newCount} new
              </button>
            : <button className="btn btn-ghost" onClick={jumpLive}>Back to live</button>
          )}
        </div>

        <AlertsTable alerts={slice} />

        <div className="pagination">
          <div className="pg-info">
            Showing {lo}–{hi} of {filtered.length}
          </div>
          <button className="pg-btn" aria-label="Previous page"
                  disabled={safePage <= 1} onClick={() => goto(safePage - 1)}>
            <Icon path={PREV_ICON} size={14} />
          </button>
          <button className="pg-btn" aria-label="Next page"
                  disabled={safePage >= totalPages} onClick={() => goto(safePage + 1)}>
            <Icon path={NEXT_ICON} size={14} />
          </button>
        </div>
      </div>
    </Shell>
  )
}
