#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  Beehive IDS — Scale + StatusStrip fixes (round 2)
#  - Real scale pass: widen content, firmer size bumps (kills side margins)
#  - StatusStrip: line in gaps only (no masking), light circles, icon-centred
#  Run from repo root: bash scripts/patch_scale_status.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

G='\033[0;32m'; B='\033[0;34m'; N='\033[0m'
ok()   { echo -e "  ${G}✓${N}  $*"; }
step() { echo -e "\n${B}━━━ $* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"; }

SHELL_CSS="frontend/src/styles/shell.css"


# ═══════════════════════════════════════════════════════════════════════
#  1  shell.css — strip prior override regions, append fresh scale + strip
# ═══════════════════════════════════════════════════════════════════════
step "1  shell.css — scale + status-strip CSS"

# Remove any previously appended override region (keeps script idempotent).
# Both markers are handled so re-runs and the earlier patch are cleaned.
sed -i '/Scale adjustments for 1366/,$d'        "$SHELL_CSS" || true
sed -i '/Beehive scale . status-strip pass/,$d' "$SHELL_CSS" || true

# Trim trailing blank lines
sed -i -e :a -e '/^\n*$/{$d;N;ba}' "$SHELL_CSS" 2>/dev/null || true

cat >> "$SHELL_CSS" << 'EOF'

/* ===== Beehive scale + status-strip pass ===== */

/* ── Scale: wider content kills side margins; firmer sizes read well on FHD ── */
.content        { max-width: 1640px; padding: 26px 40px 48px; }
.bento          { gap: 20px; }
.kpi-grid,
.row-2, .row-3, .row-4,
.row-6535, .row-3565 { gap: 20px; }

.card           { padding: 22px 24px 20px; border-radius: 18px; }
.card-header    { margin-bottom: 18px; }
.card-title     { font-size: 14.5px; }

.kpi-value      { font-size: 44px; letter-spacing: -1px; }
.kpi-label      { font-size: 11px; }
.kpi-icon       { width: 36px; height: 36px; }
.kpi-icon svg   { width: 16px; height: 16px; }

.topbar         { height: 68px; padding: 0 28px; }
.tb-brand       { font-size: 16px; }
.tb-title       { font-size: 14px; }

.rail           { width: 70px; }
.rail-item      { width: 40px; height: 40px; }
.rail-item svg  { width: 19px; height: 19px; }
.rail-logo      { width: 28px; height: 28px; }

tbody td        { font-size: 13.5px; padding: 12px; }
.log-title      { font-size: 13px; }
.mono           { font-size: 12.5px; }

/* On very wide screens, allow a touch more width before centring */
@media (min-width: 1800px) {
  .content { max-width: 1720px; }
}

/* ── StatusStrip: line lives only in the gaps between circles ──
   No masking; circles keep the light translucent fill.
   Segment runs from this circle's right edge to the next circle's left edge,
   pinned to the icon's vertical centre (top:18px for a 36px icon). ── */
.sstrip            { margin-top: 8px; }
.sstrip-rail       { display: flex; align-items: flex-start; padding: 8px 0 4px; }
.sstrip-cell       { flex: 1; display: flex; flex-direction: column;
                     align-items: center; gap: 8px; position: relative; }
.sstrip-cell:not(:last-child)::after {
  content: ''; position: absolute;
  top: 18px;                       /* icon centre (36px tall, cell-top aligned) */
  left: calc(50% + 18px);          /* this circle's right edge */
  width: calc(100% - 36px);        /* … to next circle's left edge */
  height: 2px;
  background: var(--border-strong);
  transform: translateY(-50%);
  z-index: 0;
}
.sstrip-icon {
  width: 36px; height: 36px; border-radius: 50%;
  background: var(--glass-bg-2);            /* light translucent — original look */
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
ok "shell.css — scale + sstrip classes appended"


# ═══════════════════════════════════════════════════════════════════════
#  2  StatusStrip.jsx — use CSS classes, light circles, gap line
# ═══════════════════════════════════════════════════════════════════════
step "2  StatusStrip.jsx"

cat > frontend/src/components/ui/StatusStrip.jsx << 'EOF'
/**
 * StatusStrip — connector line passes through icon centres.
 * The line is drawn ONLY in the gaps between circles (see .sstrip-cell::after
 * in shell.css), so no segment ever sits behind a circle — circles keep their
 * light translucent fill and nothing needs masking.
 */
import { MODELS } from '../../constants/models'

const ICONS = {
  sensor: '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3.6" fill="currentColor" stroke="none" opacity="0.18"/><circle cx="12" cy="12" r="3.6"/><circle cx="12" cy="12" r="0.6" fill="currentColor" stroke="none"/>',
  // Neuron: centre node + satellites with spokes (Inference)
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
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor"
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
        {/* Models bubble — last cell, no trailing line */}
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
ok "StatusStrip.jsx — gap line, light circles"


# ═══════════════════════════════════════════════════════════════════════
#  VALIDATION
# ═══════════════════════════════════════════════════════════════════════
step "Validation"

[ -f "$SHELL_CSS" ] && ok "$SHELL_CSS" || { echo "  ✗  shell.css missing"; exit 1; }
[ -f frontend/src/components/ui/StatusStrip.jsx ] && ok "StatusStrip.jsx" || { echo "  ✗  StatusStrip missing"; exit 1; }

grep -q 'max-width: 1640px'    "$SHELL_CSS" && ok "scale: content widened"      || echo "  ✗  max-width missing"
grep -q 'sstrip-cell::after'   "$SHELL_CSS" && ok "strip: gap-line rule"        || echo "  ✗  gap-line rule missing"
grep -q 'glass-bg-2'           frontend/src/components/ui/StatusStrip.jsx 2>/dev/null || true
grep -q 'sstrip-icon'          frontend/src/components/ui/StatusStrip.jsx && ok "strip: uses CSS classes" || echo "  ✗  sstrip classes not used"

# Confirm no leftover dark-mask fill in StatusStrip
if grep -q "var(--surface)'" frontend/src/components/ui/StatusStrip.jsx; then
  echo "  ✗  StatusStrip still has dark surface fill"; exit 1
else
  ok "strip: no dark mask fill"
fi

# Confirm only ONE override region in shell.css (idempotency check)
COUNT=$(grep -c 'Beehive scale . status-strip pass' "$SHELL_CSS" || true)
[ "$COUNT" -eq 1 ] && ok "shell.css: single override region ($COUNT)" || echo "  ⚠  override regions: $COUNT"

echo ""
echo -e "${G}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo -e "${G}  Scale + status strip patched.${N}"
echo ""
echo -e "  Vite HMR should hot-reload automatically. If not:"
echo -e "  cd frontend && npm run dev"
echo ""
echo -e "  Scale: content now 1640px wide (was 1380) + larger type."
echo -e "  If still too small/large, tell me a target — I can dial"
echo -e "  the whole UI with one multiplier."
echo -e "${G}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
