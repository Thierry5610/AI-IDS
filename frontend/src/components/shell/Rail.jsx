import { useNavigate, useLocation } from 'react-router-dom'
import { NAV_ITEMS, BOTTOM_NAV } from '../../constants/nav'

function Logo() {
  return (
    <svg className="rail-logo" viewBox="0 0 32 32" fill="none" aria-label="Beehive" role="img">
      <circle cx="16" cy="16" r="12.5" stroke="var(--lime)" strokeWidth="2"/>
      <circle cx="16" cy="16" r="5.5"  fill="var(--lime)"/>
      <line x1="16" y1="2.5" x2="16" y2="7.5"
        stroke="var(--lime)" strokeWidth="2" strokeLinecap="round" opacity="0.55"/>
    </svg>
  )
}

function NavBtn({ item, active, onClick }) {
  return (
    <button
      className={`rail-item${active ? ' active' : ''}`}
      onClick={() => onClick(item.path)}
      aria-label={item.label}
      aria-current={active ? 'page' : undefined}
      title={item.label}
    >
      {/* stroke="currentColor" is required — icon paths rely on inherited stroke */}
      <svg viewBox="0 0 24 24" fill="none"
           stroke="currentColor"
           strokeWidth="2"
           strokeLinecap="round"
           strokeLinejoin="round"
           style={{ width: 18, height: 18 }}
           dangerouslySetInnerHTML={{ __html: item.icon }} />
    </button>
  )
}

export default function Rail() {
  const navigate     = useNavigate()
  const { pathname } = useLocation()

  const isActive = (path) =>
    path === '/' ? pathname === '/' : pathname.startsWith(path)

  return (
    <aside className="rail">
      <Logo />
      <nav className="rail-nav" aria-label="Main navigation">
        {NAV_ITEMS.map(item => (
          <NavBtn key={item.id} item={item}
            active={isActive(item.path)} onClick={navigate} />
        ))}
      </nav>
      <div className="rail-bottom">
        {BOTTOM_NAV.map(item => (
          <NavBtn key={item.id} item={item}
            active={isActive(item.path)} onClick={navigate} />
        ))}
        <span className="rail-dot" aria-label="System online" title="System online" />
      </div>
    </aside>
  )
}
