#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  Beehive IDS — Card styling parity + gauge centre
#   - KPI cards matched to VIGIL spec (uppercase label, spacing, featured colours)
#   - EnsembleGauge: wider centre hole so the agreement number breathes
#   - Adds scripts/dump_state.sh (uploadable snapshot of live code)
#  Run from repo root: bash scripts/patch_cards.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

G='\033[0;32m'; B='\033[0;34m'; N='\033[0m'
ok()   { echo -e "  ${G}✓${N}  $*"; }
step() { echo -e "\n${B}━━━ $* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"; }

SHELL_CSS="frontend/src/styles/shell.css"


# ═══════════════════════════════════════════════════════════════════════
#  1  EnsembleGauge — widen centre hole
# ═══════════════════════════════════════════════════════════════════════
step "1  EnsembleGauge.jsx — wider centre hole"

cat > frontend/src/components/charts/EnsembleGauge.jsx << 'EOF'
/**
 * EnsembleGauge — featured visualisation.
 * Five concentric rings (outer→inner: RF → XGB → LGB → CNN → AE).
 * Rings closing the circle = consensus. Centre shows agreement fraction;
 * predicted label sits in a severity pill below.
 *
 * Radii pushed outward into a tighter band ([96..40]) so the centre number
 * has clear breathing room from the innermost (AE) ring.
 */
import { MODELS, AE_THRESHOLD } from '../../constants/models'
import { severityOf }           from '../../constants/attacks'

const CX = 110, CY = 110
const RADII = [96, 82, 68, 54, 40]   // RF → XGB → LGB → CNN → AE
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

        <text x={CX} y={CY - 5}
          textAnchor="middle" dominantBaseline="middle"
          fontFamily="var(--f-display)" fontSize="25" fontWeight="600"
          fill={hasData ? (agreement?.consensus ? 'var(--lime)' : 'var(--amber)') : 'var(--muted-2)'}>
          {agreement ? `${agreement.agreeing}/${agreement.total}` : '—'}
        </text>
        <text x={CX} y={CY + 14}
          textAnchor="middle"
          fontFamily="var(--f-mono)" fontSize="8" letterSpacing="2"
          fill="var(--muted)" style={{ textTransform: 'uppercase' }}>
          {hasData ? 'agree' : 'idle'}
        </text>
      </svg>

      <span className={`pill ${isAttack ? sev : 'ok'}`}
        style={{ maxWidth: '100%', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
        {hasData ? (label ?? 'Unknown') : 'awaiting alert'}
      </span>

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
ok "EnsembleGauge.jsx — radii [96..40]"


# ═══════════════════════════════════════════════════════════════════════
#  2  shell.css — KPI card parity (append to existing override region)
# ═══════════════════════════════════════════════════════════════════════
step "2  shell.css — KPI card parity"

# These rules are appended AFTER the existing override region, so they win.
# They restore the VIGIL kpi spec that the earlier patches diverged from.
cat >> "$SHELL_CSS" << 'EOF'

/* ── KPI card parity with VIGIL bible (patch_cards) ── */
.kpi-top    { margin-bottom: 16px; }
.kpi-label  { font-size: 10px; letter-spacing: 1px; text-transform: uppercase;
              color: var(--muted-2); font-weight: 600; }
.kpi-value  { font-family: var(--f-display); font-size: 32px; font-weight: 600;
              letter-spacing: -0.5px; line-height: 1; }
.kpi-foot   { margin-top: 12px; }

/* Featured (lime) card: muted-dark label + dark delta pill, not full black */
.kpi.featured .kpi-label { color: rgba(10,10,10,0.62); }
.kpi.featured .kpi-value { color: #0a0a0a; }
.kpi.featured .delta     { background: rgba(10,10,10,0.14); color: #0a0a0a; }
EOF
ok "shell.css — kpi label/top/foot + featured overrides"


# ═══════════════════════════════════════════════════════════════════════
#  3  dump_state.sh — uploadable snapshot of live code
# ═══════════════════════════════════════════════════════════════════════
step "3  scripts/dump_state.sh"

cat > scripts/dump_state.sh << 'DUMP'
#!/usr/bin/env bash
# Produce a single uploadable snapshot of the live frontend + bridge code.
# Usage: bash scripts/dump_state.sh   →   writes beehive_state.md at repo root.
# Upload that file before asking for a patch so the diff is against reality.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
OUT="beehive_state.md"

{
  echo "# Beehive — live code snapshot"
  echo "_generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)_"
  echo

  echo "## File tree"
  echo '```'
  find frontend/src bridge \
    -type d \( -name node_modules -o -name .venv -o -name __pycache__ \) -prune -o \
    -type f \( -name '*.jsx' -o -name '*.js' -o -name '*.css' -o -name '*.py' -o -name '*.html' \) -print \
    | sort
  echo '```'
  echo

  echo "## File contents"
  while IFS= read -r f; do
    echo
    echo "### \`$f\`"
    case "$f" in
      *.py)   lang=python ;;
      *.css)  lang=css ;;
      *.html) lang=html ;;
      *)      lang=jsx ;;
    esac
    echo "\`\`\`$lang"
    cat "$f"
    echo "\`\`\`"
  done < <(
    find frontend/src bridge \
      -type d \( -name node_modules -o -name .venv -o -name __pycache__ \) -prune -o \
      -type f \( -name '*.jsx' -o -name '*.js' -o -name '*.css' -o -name '*.py' \) -print \
      | sort
  )
} > "$OUT"

echo "Wrote $OUT  ($(wc -l < "$OUT") lines, $(du -h "$OUT" | cut -f1))"
echo "Upload it before the next patch request."
DUMP
chmod +x scripts/dump_state.sh
ok "scripts/dump_state.sh"


# ═══════════════════════════════════════════════════════════════════════
#  VALIDATION
# ═══════════════════════════════════════════════════════════════════════
step "Validation"

grep -q 'RADII = \[96, 82, 68, 54, 40\]' frontend/src/components/charts/EnsembleGauge.jsx && ok "gauge: radii widened" || { echo "  ✗ radii"; exit 1; }
grep -q 'text-transform: uppercase' "$SHELL_CSS"        && ok "css: kpi-label uppercase"     || { echo "  ✗ uppercase"; exit 1; }
grep -q '.kpi-top    { margin-bottom: 16px' "$SHELL_CSS" && ok "css: kpi-top 16px"            || { echo "  ✗ kpi-top margin"; exit 1; }
grep -q 'featured .delta' "$SHELL_CSS"                   && ok "css: featured delta override" || { echo "  ✗ featured delta"; exit 1; }
[ -x scripts/dump_state.sh ]                            && ok "dump_state.sh executable"      || { echo "  ✗ dump_state"; exit 1; }

echo ""
echo -e "${G}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo -e "${G}  Card parity + gauge centre applied.${N}"
echo ""
echo -e "  Vite hot-reloads CSS + the gauge automatically."
echo ""
echo -e "  ${B}Going forward${N}, before asking me for a change, run:"
echo -e "     bash scripts/dump_state.sh"
echo -e "  and upload  beehive_state.md  — I'll patch against your"
echo -e "  real files instead of my assumptions."
echo -e "${G}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
