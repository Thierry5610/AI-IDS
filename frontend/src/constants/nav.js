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
    icon: '<path d="M18 8.5a6 6 0 10-12 0c0 4.5-2 5.5-2 7h16c0-1.5-2-2.5-2-7z"/><path d="M10 19.5a2 2 0 004 0"/>',
  },
  {
    id: 'flows', path: '/flows', label: 'Flows',
    icon: '<path d="M4 8.5h12M13 5l4 3.5-4 3.5"/><path d="M20 15.5H8M11 12l-4 3.5 4 3.5"/>',
  },
  {
    id: 'models', path: '/models', label: 'Models',
    icon: '<rect x="7" y="7" width="10" height="10" rx="1.5"/><rect x="10" y="10" width="4" height="4" rx="0.6" fill="currentColor" stroke="none"/><path d="M10 3v2.5M14 3v2.5M10 18.5V21M14 18.5V21M3 10h2.5M3 14h2.5M18.5 10H21M18.5 14H21"/>',
  },
  {
    id: 'research', path: '/research', label: 'Research',
    icon: '<path d="M9.5 3h5M11 3v5.5L6 18a1.8 1.8 0 001.6 2.7h8.8A1.8 1.8 0 0018 18l-5-9.5V3"/><path d="M8 14.5h8"/>',
  },
]

export const BOTTOM_NAV = [
  {
    id: 'settings', path: '/settings', label: 'Settings',
    icon: '<line x1="4" y1="7" x2="20" y2="7"/><circle cx="9" cy="7" r="2.1" fill="var(--surface)"/><line x1="4" y1="12.5" x2="20" y2="12.5"/><circle cx="16" cy="12.5" r="2.1" fill="var(--surface)"/><line x1="4" y1="18" x2="20" y2="18"/><circle cx="12" cy="18" r="2.1" fill="var(--surface)"/>',
  },
]
