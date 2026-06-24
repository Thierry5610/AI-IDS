/**
 * Host typing for the passive Topology graph.
 * Host type is inferred from the destination ports observed for an IP in the
 * stream identity payloads (a host serving :443 is "web", :3306 "db", etc.).
 * Colour keys map to the resolved theme tokens (see useThemeColors in TopologyGraph).
 */

// Destination port → host type
export const PORT_TYPES = {
  80: 'web',   443: 'web',  8080: 'web', 8443: 'web',
  25: 'mail',  465: 'mail', 587: 'mail',
  3306: 'db',  5432: 'db',  1433: 'db',  27017: 'db', 6379: 'db',
  22: 'ssh',
  53: 'dns',
  21: 'ftp',
}

// When a host exposes several service ports, the most characteristic one wins.
const TYPE_PRIORITY = ['db', 'mail', 'web', 'dns', 'ftp', 'ssh']

// type → display meta. colorKey indexes the resolved theme-colour map.
export const HOST_TYPES = {
  web:  { label: 'Web',      colorKey: 'cyan',   glyph: 'globe'  },
  mail: { label: 'Mail',     colorKey: 'amber',  glyph: 'mail'   },
  db:   { label: 'Database', colorKey: 'violet', glyph: 'db'     },
  ssh:  { label: 'SSH host', colorKey: 'lime',   glyph: 'server' },
  dns:  { label: 'DNS',      colorKey: 'green',  glyph: 'globe'  },
  ftp:  { label: 'FTP',      colorKey: 'cyan',   glyph: 'server' },
  host: { label: 'Host',     colorKey: 'muted',  glyph: 'host'   },
}

// 24×24 stroke glyph paths (VIGIL idiom), drawn on canvas via Path2D.
export const GLYPHS = {
  globe:  'M12 3a9 9 0 100 18 9 9 0 000-18M3 12h18M12 3c3 4 3 14 0 18M12 3c-3 4-3 14 0 18',
  mail:   'M3 6h18v12H3zM3 7l9 6 9-6',
  db:     'M5 6c0-1.7 3.1-3 7-3s7 1.3 7 3-3.1 3-7 3-7-1.3-7-3zM5 6v12c0 1.7 3.1 3 7 3s7-1.3 7-3V6M5 12c0 1.7 3.1 3 7 3s7-1.3 7-3',
  server: 'M4 4h16v6H4zM4 14h16v6H4zM8 7h2M8 17h2',
  host:   'M4 5h16v10H4zM9 19h6M12 15v4',
}

/** Pick a host type from the set of observed destination ports. */
export function hostTypeFromPorts(ports) {
  const types = new Set((ports || []).map(p => PORT_TYPES[p]).filter(Boolean))
  for (const t of TYPE_PRIORITY) if (types.has(t)) return t
  return 'host'
}

/** RFC1918 / loopback / link-local → internal. */
export function isInternalIp(ip) {
  if (!ip) return false
  const o = String(ip).split('.').map(Number)
  if (o.length !== 4 || o.some(n => Number.isNaN(n))) return false
  const [a, b] = o
  if (a === 10) return true
  if (a === 172 && b >= 16 && b <= 31) return true
  if (a === 192 && b === 168) return true
  if (a === 127) return true
  if (a === 169 && b === 254) return true
  return false
}
