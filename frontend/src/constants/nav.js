/**
 * Single source of truth for the rail navigation.
 * icon: inline SVG path string (24x24 viewBox, stroke-width 2, round caps/joins).
 * Sourced verbatim from VIGIL-THEME-SKILL.md icon library.
 */
export const NAV_ITEMS = [
  {
    id: 'overview', path: '/', label: 'Overview',
    icon: '<rect x="3" y="3" width="9" height="9" rx="2"/><rect x="14" y="3" width="7" height="4" rx="1.6"/><rect x="14" y="9" width="7" height="3" rx="1.4"/><rect x="3" y="14" width="18" height="7" rx="2"/>',
  },
  {
    id: 'topology', path: '/topology', label: 'Topology',
    icon: '<line x1="6.7" y1="7.3" x2="10.6" y2="11.7"/><line x1="17.3" y1="7.3" x2="13.4" y2="11.7"/><line x1="11" y1="14.5" x2="7" y2="17.7"/><line x1="13" y1="14.5" x2="17" y2="17.7"/><circle cx="5" cy="6" r="2.1" fill="currentColor" stroke="none"/><circle cx="19" cy="6" r="2.1" fill="currentColor" stroke="none"/><circle cx="12" cy="13" r="2.3" fill="currentColor" stroke="none"/><circle cx="6" cy="19" r="2.1" fill="currentColor" stroke="none"/><circle cx="18" cy="19" r="2.1" fill="currentColor" stroke="none"/>',
  },
  {
    id: 'alerts', path: '/alerts', label: 'Alerts',
    icon: '<circle cx="12" cy="12" r="8.5"/><line x1="12" y1="8" x2="12" y2="13"/><circle cx="12" cy="16.3" r="0.5" fill="currentColor" stroke="none"/>',
  },
  {
    id: 'flows', path: '/flows', label: 'Flows',
    icon: '<path d="M4 12h12M13 8l4 4-4 4"/><circle cx="4" cy="12" r="1.5" fill="currentColor" stroke="none"/>',
  },
  {
    id: 'models', path: '/models', label: 'Models',
    icon: '<rect x="5" y="3" width="14" height="18" rx="2"/><rect x="8" y="13" width="2" height="5" fill="currentColor" stroke="none"/><rect x="11.3" y="10" width="2" height="8" fill="currentColor" stroke="none"/><rect x="14.6" y="7" width="2" height="11" fill="currentColor" stroke="none"/>',
  },
  {
    id: 'research', path: '/research', label: 'Research',
    icon: '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3.6" fill="currentColor" stroke="none" opacity="0.18"/><circle cx="12" cy="12" r="3.6"/><circle cx="12" cy="12" r="0.6" fill="currentColor" stroke="none"/>',
  },
]

export const BOTTOM_NAV = [
  {
    id: 'settings', path: '/settings', label: 'Settings',
    icon: '<line x1="4" y1="7" x2="20" y2="7"/><circle cx="9" cy="7" r="2.1" fill="var(--surface)"/><line x1="4" y1="12.5" x2="20" y2="12.5"/><circle cx="16" cy="12.5" r="2.1" fill="var(--surface)"/><line x1="4" y1="18" x2="20" y2="18"/><circle cx="12" cy="18" r="2.1" fill="var(--surface)"/>',
  },
]
