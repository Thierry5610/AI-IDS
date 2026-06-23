#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  Beehive IDS — Round 3 fixes
#   1. bridge: XREAD fan-out (every client sees every event)
#   2. shell.css: zoom knob (125%), VIGIL .log block, .delta colour fix
#   3. EnsembleGauge: agreement in centre, label pill below, polished rings
#   4. AlertLogStream: faithful VIGIL structure
#   5. StatusStrip: defensive svg sizing
#  Run from repo root: bash scripts/patch_round3.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

G='\033[0;32m'; B='\033[0;34m'; N='\033[0m'
ok()   { echo -e "  ${G}✓${N}  $*"; }
step() { echo -e "\n${B}━━━ $* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"; }

SHELL_CSS="frontend/src/styles/shell.css"


# ═══════════════════════════════════════════════════════════════════════
#  1  BRIDGE — XREAD fan-out (replaces group-consumer competing-consumers)
# ═══════════════════════════════════════════════════════════════════════
step "1  bridge — XREAD fan-out"

cat > bridge/consumer.py << 'EOF'
"""
Redis XREAD tailing consumer (broadcast / fan-out).

Each SSE connection calls stream_events() independently and gets its OWN
cursor — so EVERY connected client receives EVERY message. This is the
correct model for a dashboard.

(The previous group-consumer approach used competing consumers: a message
went to only one connection, so a second browser tab would see nothing.)

No acking, no consumer groups. Starts at "0" to replay recent history on
connect, then tails live.
"""
import json
import os
import redis.asyncio as aioredis

REDIS_URL      = os.getenv("REDIS_URL", "redis://127.0.0.1:6379/0")
BLOCK_MS       = 5_000
SOCKET_TIMEOUT = BLOCK_MS / 1000 + 5


async def stream_events(stream: str, start_id: str = "0"):
    """Async generator: yields JSON strings or None (heartbeat tick).

    start_id "0"  → replay all retained history then tail
    start_id "$"  → live only (skip history)
    """
    r = await aioredis.from_url(
        REDIS_URL,
        socket_timeout=SOCKET_TIMEOUT,
        decode_responses=True,
    )

    cursor = start_id
    while True:
        try:
            results = await r.xread({stream: cursor}, count=20, block=BLOCK_MS)
        except aioredis.TimeoutError:
            yield None
            continue
        except Exception:
            yield None
            continue

        if not results:
            yield None
            continue

        for _, messages in results:
            for msg_id, fields in messages:
                cursor = msg_id                  # advance this connection's cursor
                raw = fields.get("data", "{}")
                try:
                    json.loads(raw)
                except json.JSONDecodeError:
                    continue
                yield raw
EOF
ok "consumer.py → XREAD fan-out"

cat > bridge/routes/attacks.py << 'EOF'
import os
from fastapi import APIRouter, Request
from sse_starlette.sse import EventSourceResponse
from consumer import stream_events

router = APIRouter()
STREAM = os.getenv("IDS_ATTACKS_STREAM", "ids:attacks")


@router.get("/stream/attacks")
async def attacks_sse(request: Request):
    async def generator():
        async for payload in stream_events(STREAM, "0"):
            if await request.is_disconnected():
                break
            if payload is None:
                yield {"comment": "heartbeat"}
            else:
                yield {"event": "attack", "data": payload}
    return EventSourceResponse(generator())
EOF
ok "routes/attacks.py"

cat > bridge/routes/anomalies.py << 'EOF'
import os
from fastapi import APIRouter, Request
from sse_starlette.sse import EventSourceResponse
from consumer import stream_events

router = APIRouter()
STREAM = os.getenv("IDS_ANOMALIES_STREAM", "ids:anomalies")


@router.get("/stream/anomalies")
async def anomalies_sse(request: Request):
    async def generator():
        async for payload in stream_events(STREAM, "0"):
            if await request.is_disconnected():
                break
            if payload is None:
                yield {"comment": "heartbeat"}
            else:
                yield {"event": "anomaly", "data": payload}
    return EventSourceResponse(generator())
EOF
ok "routes/anomalies.py"


# ═══════════════════════════════════════════════════════════════════════
#  2  shell.css — strip prior overrides, append fresh region
# ═══════════════════════════════════════════════════════════════════════
step "2  shell.css — zoom, log block, delta fix"

sed -i '/Scale adjustments for 1366/,$d'        "$SHELL_CSS" || true
sed -i '/Beehive scale . status-strip pass/,$d' "$SHELL_CSS" || true
sed -i -e :a -e '/^\n*$/{$d;N;ba}' "$SHELL_CSS" 2>/dev/null || true

cat >> "$SHELL_CSS" << 'EOF'

/* ===== Beehive scale + status-strip pass ===== */

/* ── Single scale knob ──
   Bakes in the 125% look. RESET your browser zoom to 100% (Ctrl+0) first,
   or it doubles. Change this one number to taste; everything scales together. */
html { zoom: 1.25; }

/* ── Delta / KPI chips: never inherit near-white body text ── */
.delta      { color: var(--muted); }
.delta.good { color: var(--green); background: var(--green-soft); }
.delta.bad  { color: var(--amber); background: var(--amber-soft); }
.delta.crit { color: var(--red);   background: var(--red-soft);   }

/* ── Alert log feed — ported verbatim from VIGIL prototype ── */
.log        { display: flex; flex-direction: column; margin-top: 2px; }
.log-row    { display: flex; gap: 12px; }
.log-rail   { display: flex; flex-direction: column; align-items: center; width: 24px; flex-shrink: 0; }
.log-icon   { width: 22px; height: 22px; border-radius: 50%; display: flex;
              align-items: center; justify-content: center; flex-shrink: 0;
              background: var(--glass-bg-2); border: 1px solid var(--border-strong); }
.log-icon svg     { width: 11px; height: 11px; }
.log-icon.crit    { color: var(--red);   border-color: rgba(255,77,94,0.45); }
.log-icon.warn    { color: var(--amber); border-color: rgba(255,176,32,0.45); }
.log-icon.ok      { color: var(--green); border-color: rgba(52,211,153,0.45); }
.log-line   { width: 1px; flex: 1; background: var(--border-strong); margin: 4px 0; min-height: 18px; }
.log-row:last-child .log-line { display: none; }
.log-body   { flex: 1; padding-bottom: 17px; }
.log-row:last-child .log-body { padding-bottom: 0; }
.log-top    { display: flex; justify-content: space-between; align-items: baseline; gap: 8px; }
.log-title  { font-size: 12.5px; color: var(--text); font-weight: 500; }
.log-time   { font-family: var(--f-mono); font-size: 10px; color: var(--muted-2); flex-shrink: 0; }
.log-meta   { font-family: var(--f-mono); font-size: 10.5px; color: var(--muted-2); margin-top: 3px; }

/* ── StatusStrip: line lives only in the gaps between circles (no masking) ── */
.sstrip            { margin-top: 8px; }
.sstrip-rail       { display: flex; align-items: flex-start; padding: 8px 0 4px; }
.sstrip-cell       { flex: 1; display: flex; flex-direction: column;
                     align-items: center; gap: 8px; position: relative; }
.sstrip-cell:not(:last-child)::after {
  content: ''; position: absolute;
  top: 18px;
  left: calc(50% + 18px);
  width: calc(100% - 36px);
  height: 2px;
  background: var(--border-strong);
  transform: translateY(-50%);
  z-index: 0;
}
.sstrip-icon {
  width: 36px; height: 36px; border-radius: 50%;
  background: var(--glass-bg-2);
  border: 1px solid var(--border-strong);
  display: flex; align-items: center; justify-content: center;
  position: relative; z-index: 1; flex-shrink: 0;
}
.sstrip-icon svg   { width: 16px; height: 16px; }
.sstrip-label      { font-size: 9.5px; color: var(--muted-2);
                     font-family: var(--f-mono); letter-spacing: 0.3px; }
.sstrip-more {
  width: 36px; height: 36px; border-radius: 50%;
  display: flex; align-items: center; justify-content: center;
  font-size: 10px; color: var(--muted-2);
  background: var(--glass-bg-2);
  border: 1px dashed var(--border-strong);
  font-family: var(--f-mono);
  position: relative; z-index: 1; flex-shrink: 0;
}
.sstrip-models     { border-top: 1px solid var(--border); padding-top: 14px;
                     margin-top: 6px; display: flex; flex-direction: column; gap: 9px; }
.sstrip-model      { display: flex; align-items: center; gap: 10px; }
.sstrip-model-dot  { width: 7px; height: 7px; border-radius: 50%; flex-shrink: 0; }
.sstrip-model-name { font-size: 12.5px; flex: 1; }
.sstrip-model-stat { font-size: 10px; font-family: var(--f-mono); color: var(--green); }
EOF
ok "shell.css — region appended (zoom + log + delta + sstrip)"


# ═══════════════════════════════════════════════════════════════════════
#  3  EnsembleGauge — agreement centre, label pill, polished rings
# ═══════════════════════════════════════════════════════════════════════
step "3  EnsembleGauge.jsx"

cat > frontend/src/components/charts/EnsembleGauge.jsx << 'EOF'
/**
 * EnsembleGauge — featured visualisation.
 * Five concentric rings (outer→inner: RF → XGB → LGB → CNN → AE).
 * Ring fill = model confidence; rings closing the circle = consensus.
 * Centre shows the agreement fraction (always fits); the predicted attack
 * label sits in a severity pill BELOW the gauge (handles long names cleanly).
 */
import { MODELS, AE_THRESHOLD } from '../../constants/models'
import { severityOf }           from '../../constants/attacks'

const CX = 110, CY = 110
const RADII = [92, 76, 60, 44, 28]   // RF → XGB → LGB → CNN → AE
const SW = 6

function Arc({ r, pct, color, animate }) {
  const circ = 2 * Math.PI * r
  const dash = circ * Math.min(Math.max(pct, 0), 1)
  return (
    <>
      <circle cx={CX} cy={CY} r={r}
        fill="none" stroke="var(--border)" strokeWidth={SW} />
      <circle cx={CX} cy={CY} r={r}
        fill="none" stroke={color} strokeWidth={SW} strokeLinecap="round"
        strokeDasharray={`${dash.toFixed(2)} ${circ.toFixed(2)}`}
        transform={`rotate(-90 ${CX} ${CY})`}
        style={{ transition: animate ? 'stroke-dasharray .7s cubic-bezier(.4,0,.2,1)' : 'none' }} />
    </>
  )
}

function arcPct(id, votes) {
  if (!votes) return 0
  const v = votes[id]
  if (!v) return 0
  if (id === 'autoencoder') return Math.min((v.anomaly_score ?? 0) / AE_THRESHOLD, 1)
  return v.confidence ?? 0
}

export default function EnsembleGauge({ votes, agreement, label }) {
  const hasData  = !!votes
  const arcs     = MODELS.map((m, i) => ({ ...m, r: RADII[i], pct: arcPct(m.id, votes) }))
  const isAttack = hasData && !!label && label !== 'Benign'
  const sev      = label ? severityOf(label) : 'low'

  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 14 }}>
      <svg width="100%" viewBox="0 0 220 220" style={{ maxWidth: 210 }}>
        {arcs.map(a => (
          <Arc key={a.id} r={a.r} pct={a.pct} color={a.color} animate={hasData} />
        ))}

        {/* Centre: agreement fraction */}
        <text x={CX} y={CY - 6}
          textAnchor="middle" dominantBaseline="middle"
          fontFamily="var(--f-display)" fontSize="26" fontWeight="600"
          fill={hasData ? (agreement?.consensus ? 'var(--lime)' : 'var(--amber)') : 'var(--muted-2)'}>
          {agreement ? `${agreement.agreeing}/${agreement.total}` : '—'}
        </text>
        <text x={CX} y={CY + 14}
          textAnchor="middle"
          fontFamily="var(--f-mono)" fontSize="8.5" letterSpacing="1.5"
          fill="var(--muted)" style={{ textTransform: 'uppercase' }}>
          {hasData ? 'agree' : 'idle'}
        </text>
      </svg>

      {/* Predicted label as a severity pill — handles long names */}
      <span className={`pill ${isAttack ? sev : 'ok'}`}
        style={{ maxWidth: '100%', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
        {hasData ? (label ?? 'Unknown') : 'awaiting alert'}
      </span>

      {/* Per-model legend */}
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: '6px 14px', justifyContent: 'center' }}>
        {arcs.map(a => (
          <span key={a.id} style={{ display: 'flex', alignItems: 'center', gap: 5,
            fontSize: 10, fontFamily: 'var(--f-mono)', color: 'var(--muted)' }}>
            <span style={{ width: 7, height: 7, borderRadius: '50%', background: a.color, flexShrink: 0 }} />
            {a.short}
            <span style={{ color: 'var(--muted-2)' }}>
              {hasData ? `${(a.pct * 100).toFixed(0)}%` : '--'}
            </span>
          </span>
        ))}
      </div>
    </div>
  )
}
EOF
ok "EnsembleGauge.jsx"


# ═══════════════════════════════════════════════════════════════════════
#  4  AlertLogStream — faithful VIGIL structure
# ═══════════════════════════════════════════════════════════════════════
step "4  AlertLogStream.jsx"

cat > frontend/src/components/alerts/AlertLogStream.jsx << 'EOF'
/**
 * AlertLogStream — vertical event log matching the VIGIL prototype.
 * Structure: .log > .log-row > (.log-rail[icon+line]) + (.log-body[top+meta]).
 * Severity drives the icon colour only.
 */
import { fmt }        from '../../lib/format'
import { severityOf } from '../../constants/attacks'

const ALERT_ICON = '<line x1="12" y1="6" x2="12" y2="13"/><circle cx="12" cy="17" r="1" fill="currentColor" stroke="none"/>'
const CHECK_ICON = '<path d="M6 12l4 4 8-9"/>'

function railClass(sev) {
  if (sev === 'critical' || sev === 'high') return 'crit'
  if (sev === 'medium')                     return 'warn'
  return 'ok'
}

function Row({ alert, isLast }) {
  const label = alert.prediction?.label ?? 'Unknown'
  const sev   = severityOf(label)
  const cls   = railClass(sev)
  const icon  = cls === 'ok' ? CHECK_ICON : ALERT_ICON

  return (
    <div className="log-row">
      <div className="log-rail">
        <span className={`log-icon ${cls}`}>
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor"
               strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"
               width="11" height="11"
               dangerouslySetInnerHTML={{ __html: icon }} />
        </span>
        {!isLast && <span className="log-line" />}
      </div>

      <div className="log-body">
        <div className="log-top">
          <span className="log-title">{label}</span>
          <span className="log-time">{fmt.time(alert.timestamp)}</span>
        </div>
        <div className="log-meta">
          {alert.identity ? fmt.flow(alert.identity) : (alert.flow_id ?? '—')}
          {alert.prediction?.confidence != null && (
            <> {' · '}<span style={{ color: 'var(--lime)' }}>{fmt.pct(alert.prediction.confidence)}</span></>
          )}
        </div>
      </div>
    </div>
  )
}

export default function AlertLogStream({ alerts, maxRows = 6 }) {
  const rows = alerts.slice(0, maxRows)

  if (rows.length === 0) {
    return (
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center',
        height: 140, color: 'var(--muted-2)', fontFamily: 'var(--f-mono)', fontSize: 12 }}>
        no alerts — sensor idle
      </div>
    )
  }

  return (
    <div className="log">
      {rows.map((a, i) => (
        <Row key={a.flow_id ?? i} alert={a} isLast={i === rows.length - 1} />
      ))}
    </div>
  )
}
EOF
ok "AlertLogStream.jsx"


# ═══════════════════════════════════════════════════════════════════════
#  5  StatusStrip — defensive svg sizing (width/height attrs)
# ═══════════════════════════════════════════════════════════════════════
step "5  StatusStrip.jsx"

cat > frontend/src/components/ui/StatusStrip.jsx << 'EOF'
/**
 * StatusStrip — connector line passes through icon centres.
 * Line is drawn only in the gaps between circles (.sstrip-cell::after), so no
 * segment sits behind a circle. svg width/height are set as ATTRIBUTES too, so
 * icons can never blow up even if the stylesheet fails to load.
 */
import { MODELS } from '../../constants/models'

const ICONS = {
  sensor: '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3.6" fill="currentColor" stroke="none" opacity="0.18"/><circle cx="12" cy="12" r="3.6"/><circle cx="12" cy="12" r="0.6" fill="currentColor" stroke="none"/>',
  inference: '<circle cx="12" cy="12" r="2.8"/><circle cx="12" cy="4.5" r="1.5" fill="currentColor" stroke="none"/><circle cx="4.5" cy="12" r="1.5" fill="currentColor" stroke="none"/><circle cx="19.5" cy="12" r="1.5" fill="currentColor" stroke="none"/><circle cx="12" cy="19.5" r="1.5" fill="currentColor" stroke="none"/><circle cx="6.2" cy="6.2" r="1.5" fill="currentColor" stroke="none"/><circle cx="17.8" cy="17.8" r="1.5" fill="currentColor" stroke="none"/><line x1="12" y1="7.6" x2="12" y2="9.2"/><line x1="7.6" y1="12" x2="9.2" y2="12"/><line x1="14.8" y1="12" x2="16.4" y2="12"/><line x1="12" y1="14.8" x2="12" y2="16.4"/><line x1="7.7" y1="7.7" x2="10" y2="10"/><line x1="14" y1="14" x2="16.3" y2="16.3"/>',
  bridge:   '<line x1="6.7" y1="7.3" x2="10.6" y2="11.7"/><line x1="17.3" y1="7.3" x2="13.4" y2="11.7"/><line x1="11" y1="14.5" x2="7" y2="17.7"/><line x1="13" y1="14.5" x2="17" y2="17.7"/><circle cx="5" cy="6" r="2.1" fill="currentColor" stroke="none"/><circle cx="19" cy="6" r="2.1" fill="currentColor" stroke="none"/><circle cx="12" cy="13" r="2.3" fill="currentColor" stroke="none"/><circle cx="6" cy="19" r="2.1" fill="currentColor" stroke="none"/><circle cx="18" cy="19" r="2.1" fill="currentColor" stroke="none"/>',
  redis:    '<path d="M7 17a4 4 0 010-8 5 5 0 019.6-1.5A4.5 4.5 0 0117 17H7z"/>',
}

const SERVICES = [
  { key: 'sensor',    label: 'Sensor',    icon: ICONS.sensor,    color: 'var(--lime)'   },
  { key: 'inference', label: 'Inference', icon: ICONS.inference, color: 'var(--cyan)'   },
  { key: 'bridge',    label: 'Bridge',    icon: ICONS.bridge,    color: 'var(--violet)' },
  { key: 'redis',     label: 'Redis',     icon: ICONS.redis,     color: 'var(--amber)'  },
]

function Cell({ icon, color, label }) {
  return (
    <div className="sstrip-cell">
      <span className="sstrip-icon" style={{ color }}>
        <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor"
             strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"
             dangerouslySetInnerHTML={{ __html: icon }} />
      </span>
      <span className="sstrip-label">{label}</span>
    </div>
  )
}

export default function StatusStrip() {
  return (
    <div className="sstrip">
      <div className="sstrip-rail">
        {SERVICES.map(s => (
          <Cell key={s.key} icon={s.icon} color={s.color} label={s.label} />
        ))}
        <div className="sstrip-cell">
          <span className="sstrip-more">+{MODELS.length}</span>
          <span className="sstrip-label">Models</span>
        </div>
      </div>

      <div className="sstrip-models">
        {MODELS.map(m => (
          <div key={m.id} className="sstrip-model">
            <span className="sstrip-model-dot" style={{ background: m.color }} />
            <span className="sstrip-model-name">{m.label}</span>
            <span className="sstrip-model-stat">loaded</span>
          </div>
        ))}
      </div>
    </div>
  )
}
EOF
ok "StatusStrip.jsx"


# ═══════════════════════════════════════════════════════════════════════
#  VALIDATION
# ═══════════════════════════════════════════════════════════════════════
step "Validation"

grep -q 'xread'            bridge/consumer.py                                   && ok "bridge: XREAD fan-out"        || { echo "  ✗ xread missing"; exit 1; }
grep -q 'xreadgroup(' bridge/consumer.py                            && { echo "  ✗ xreadgroup still present"; exit 1; } || ok "bridge: no group consumer"
grep -q 'zoom: 1.25'       "$SHELL_CSS"                                         && ok "css: zoom knob"               || { echo "  ✗ zoom missing"; exit 1; }
grep -q '.log-top'         "$SHELL_CSS"                                         && ok "css: VIGIL log block"         || { echo "  ✗ log block missing"; exit 1; }
grep -q '.delta      { color: var(--muted)' "$SHELL_CSS"                        && ok "css: delta base colour"       || { echo "  ✗ delta colour missing"; exit 1; }
grep -q 'agreement.agreeing'  frontend/src/components/charts/EnsembleGauge.jsx  && ok "gauge: agreement centre"      || { echo "  ✗ gauge centre missing"; exit 1; }
grep -q 'log-rail'         frontend/src/components/alerts/AlertLogStream.jsx    && ok "feed: VIGIL structure"        || { echo "  ✗ feed structure missing"; exit 1; }
grep -q 'width="16"'       frontend/src/components/ui/StatusStrip.jsx           && ok "strip: defensive svg size"    || { echo "  ✗ svg size attr missing"; exit 1; }

COUNT=$(grep -c 'Beehive scale . status-strip pass' "$SHELL_CSS" || true)
[ "$COUNT" -eq 1 ] && ok "css: single override region" || echo "  ⚠ override regions: $COUNT"

echo ""
echo -e "${G}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo -e "${G}  Round 3 applied.${N}"
echo ""
echo -e "  ${B}1${N}  Restart the bridge (required — consumer logic changed):"
echo -e "     cd bridge && source .venv/bin/activate"
echo -e "     uvicorn main:app --port 8001 --reload"
echo ""
echo -e "  ${B}2${N}  In the browser: reset zoom to 100% (Ctrl+0), then hard"
echo -e "     refresh (Ctrl+Shift+R). Confirm the URL is the DEV server:"
echo -e "     http://localhost:5173   (from 'npm run dev', not preview)"
echo ""
echo -e "  ${B}3${N}  Re-push test data — every open tab now receives all of it:"
echo -e "     (run the redis xadd loop again from any terminal)"
echo ""
echo -e "  Diagnose SSE: DevTools → Network → filter 'stream' →"
echo -e "  /stream/attacks should be status 200, type eventsource, pending."
echo -e "${G}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
