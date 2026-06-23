/**
 * Thin fetch wrappers for the inference service.
 * All paths are relative — Vite proxies /api/* → localhost:8000 in dev,
 * stripping the /api prefix so the service sees its native routes.
 */
const BASE = '/api'

export async function fetchHealth() {
  const r = await fetch(`${BASE}/health`)
  if (!r.ok) throw new Error(`health check failed (${r.status})`)
  return r.json()
}

export async function fetchModels() {
  const r = await fetch(`${BASE}/models`)
  if (!r.ok) throw new Error(`/models failed (${r.status})`)
  return r.json()
}

/**
 * Direct predict call — used by the Research page for manual feature submission.
 * Normal traffic takes the eBPF → emitter → Redis path; this is a dev/debug shortcut.
 */
export async function predict(features, flowId = '') {
  const r = await fetch(`${BASE}/predict`, {
    method:  'POST',
    headers: { 'Content-Type': 'application/json' },
    body:    JSON.stringify({ features, flow_id: flowId }),
  })
  if (!r.ok) throw new Error(`/predict failed (${r.status})`)
  return r.json()
}
