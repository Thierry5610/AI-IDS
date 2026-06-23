/** Display-formatting helpers — pure functions, no side effects. */

export const fmt = {
  ip:   (ip)   => ip   ?? '—',
  port: (p)    => p    != null ? String(p) : '—',

  /** "192.168.1.1:4444 → 10.0.0.1:22" */
  flow: ({ src_ip, src_port, dst_ip, dst_port } = {}) =>
    `${src_ip ?? '?'}:${src_port ?? '?'} → ${dst_ip ?? '?'}:${dst_port ?? '?'}`,

  /** HH:MM:SS from an ISO timestamp string */
  time: (iso) => {
    if (!iso) return '—'
    try { return new Date(iso).toLocaleTimeString('en-GB', { hour12: false }) }
    catch { return iso }
  },

  /** "97.3%" */
  pct: (c) => c != null ? `${(c * 100).toFixed(1)}%` : '—',

  /** 6→TCP, 17→UDP, 1→ICMP */
  proto: (n) => ({ 6: 'TCP', 17: 'UDP', 1: 'ICMP' }[n] ?? String(n ?? '?')),
}
