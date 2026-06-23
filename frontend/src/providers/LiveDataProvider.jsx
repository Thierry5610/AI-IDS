/**
 * Mounts both SSE streams once when the app loads.
 * All pages read the shared Zustand stores — no per-page stream setup.
 */
import { useEffect } from 'react'
import { createStream }    from '../lib/stream'
import { useAlertStore }   from '../store/alertStore'
import { useAnomalyStore } from '../store/anomalyStore'

export default function LiveDataProvider({ children }) {
  const pushAlert   = useAlertStore(s => s.push)
  const pushAnomaly = useAnomalyStore(s => s.push)

  useEffect(() => {
    const unA = createStream('/stream/attacks',   'attack',  pushAlert,
                             m => console.warn('[attacks stream]', m))
    const unB = createStream('/stream/anomalies', 'anomaly', pushAnomaly,
                             m => console.warn('[anomalies stream]', m))
    return () => { unA(); unB() }
  }, [pushAlert, pushAnomaly])

  return children
}
