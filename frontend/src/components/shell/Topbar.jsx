/**
 * Topbar — sticky glass header.
 * Includes: brand · separator · page title · date nav · notification bell · avatar
 * Props: title (string)
 */
const BELL_ICON   = '<path d="M18 8a6 6 0 10-12 0c0 4-2 5-2 6h16c0-1-2-2-2-6z"/><path d="M10 19a2 2 0 004 0"/>'
const CHEVRON_L   = '<path d="M15 5l-7 7 7 7"/>'
const CHEVRON_R   = '<path d="M9 5l7 7-7 7"/>'

function IconBtn({ icon, badge, label }) {
  return (
    <button aria-label={label} style={{
      position: 'relative', width: 34, height: 34,
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      borderRadius: '50%', color: 'var(--muted)',
      transition: 'background .15s, color .15s',
    }}
    onMouseEnter={e => { e.currentTarget.style.background = 'var(--glass-bg-2)'; e.currentTarget.style.color = 'var(--text)' }}
    onMouseLeave={e => { e.currentTarget.style.background = ''; e.currentTarget.style.color = 'var(--muted)' }}
    >
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor"
           strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"
           style={{ width: 16.5, height: 16.5 }}
           dangerouslySetInnerHTML={{ __html: icon }} />
      {badge && (
        <span style={{
          position: 'absolute', top: 3, right: 4,
          width: 13, height: 13, borderRadius: '50%',
          background: 'var(--red)', color: '#0a0a0a',
          fontSize: 8, fontWeight: 700,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          border: '2px solid var(--bg)',
        }}>
          {badge}
        </span>
      )}
    </button>
  )
}

function DateNav() {
  const today = new Date().toLocaleDateString('en-GB', { day: '2-digit', month: 'short' })
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 9,
      background: 'var(--glass-bg-2)', border: '1px solid var(--border)',
      borderRadius: 99, padding: '6px 8px 6px 14px',
      fontSize: 11.5, color: 'var(--muted)', marginLeft: 4, userSelect: 'none',
    }}>
      <button aria-label="Previous day" style={{
        width: 16, height: 16, display: 'flex', alignItems: 'center',
        justifyContent: 'center', color: 'var(--muted-2)', borderRadius: '50%',
      }}>
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor"
             strokeWidth="2.4" strokeLinecap="round"
             style={{ width: 11, height: 11 }}
             dangerouslySetInnerHTML={{ __html: CHEVRON_L }} />
      </button>
      Today · {today}
      <button aria-label="Next day" style={{
        width: 16, height: 16, display: 'flex', alignItems: 'center',
        justifyContent: 'center', color: 'var(--muted-2)', borderRadius: '50%',
      }}>
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor"
             strokeWidth="2.4" strokeLinecap="round"
             style={{ width: 11, height: 11 }}
             dangerouslySetInnerHTML={{ __html: CHEVRON_R }} />
      </button>
    </div>
  )
}

export default function Topbar({ title }) {
  return (
    <header className="topbar">
      <span className="tb-brand">Beehive</span>
      <span className="tb-sep" aria-hidden="true" />
      <span className="tb-title">{title}</span>
      <DateNav />

      <div className="tb-right">
        <IconBtn icon={BELL_ICON} badge={3} label="Notifications" />
        <button style={{
          display: 'flex', alignItems: 'center', gap: 7,
          padding: '4px 6px 4px 4px', borderRadius: 99,
          transition: 'background .15s',
        }}
        aria-label="Account menu"
        onMouseEnter={e => e.currentTarget.style.background = 'var(--glass-bg-2)'}
        onMouseLeave={e => e.currentTarget.style.background = ''}
        >
          <div className="avatar">TN</div>
          <span style={{ fontSize: 12, fontWeight: 500 }}>Thierry N.</span>
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor"
               strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"
               style={{ width: 11, height: 11, color: 'var(--muted-2)' }}>
            <path d="M6 9l6 6 6-6"/>
          </svg>
        </button>
      </div>
    </header>
  )
}
