/**
 * SSE client factory with exponential-backoff reconnect.
 * Vite proxies /stream/* → bridge (localhost:8001) in dev.
 *
 * Usage:
 *   const unsub = createStream('/stream/attacks', 'attack', onMessage, onError)
 *   unsub()   // close & stop reconnecting
 */
export function createStream(path, eventName, onMessage, onError) {
  let es
  let stopped  = false
  let retryMs  = 1_000
  const MAX_MS = 30_000

  function connect() {
    if (stopped) return
    es = new EventSource(path)

    es.addEventListener(eventName, (e) => {
      retryMs = 1_000                    // reset backoff on successful message
      try { onMessage(JSON.parse(e.data)) }
      catch (err) { console.warn('[stream] parse error', path, err) }
    })

    es.onerror = () => {
      es.close()
      if (stopped) return
      onError?.(`[stream] ${path} lost — retry in ${retryMs}ms`)
      const delay = retryMs
      retryMs = Math.min(retryMs * 2, MAX_MS)
      setTimeout(connect, delay)
    }
  }

  connect()
  return () => { stopped = true; es?.close() }
}
