/**
 * CICIDS2017 attack labels (index = label_index from /predict).
 * Source: label_encoder.pkl — do not reorder.
 */
export const ATTACK_LABELS = [
  'Benign',                    // 0
  'Bot',                       // 1
  'DDoS',                      // 2
  'DoS GoldenEye',             // 3
  'DoS Hulk',                  // 4
  'DoS Slowhttptest',          // 5
  'DoS slowloris',             // 6
  'FTP-Patator',               // 7
  'Heartbleed',                // 8
  'Infiltration',              // 9
  'PortScan',                  // 10
  'SSH-Patator',               // 11
  'Web Attack - Brute Force',  // 12
  'Web Attack - Sql Injection',// 13
  'Web Attack - XSS',          // 14
]

/**
 * Coarse severity bucket → pill class.
 * Tuned for CICIDS2017 class semantics.
 */
export function severityOf(label) {
  if (!label || label === 'Benign') return 'ok'
  const l = label.toLowerCase()
  if (l.includes('ddos') || l.includes('heartbleed') || l.includes('infiltration')) return 'critical'
  if (l.includes('dos')  || l.includes('bot'))                                       return 'high'
  if (l.includes('patator') || l.includes('scan'))                                   return 'medium'
  return 'low'
}
