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
