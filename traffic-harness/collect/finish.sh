#!/usr/bin/env bash
# Post-collection: assemble the per-window matrices into the labeled dataset, validate it,
# back up the (small) dataset artifacts off the external drive, and gzip the pcaps in place.
# Safe to re-run. No em dashes.
set -euo pipefail
SELF="$(cd "$(dirname "$0")" && pwd)"
REPO="$(git -C "$SELF" rev-parse --show-toplevel)"
TH="$REPO/traffic-harness"
SENSOR="$REPO/ebpf-sensor"
PY="$SENSOR/.venv/bin/python"
SENSOR_COMMIT="$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)"

DATA_DIR="$TH/data/collect"
OUT_DIR="$TH/collect/dataset"
BACKUP="${BACKUP:-$HOME/aiids-eval-backup/v2-dataset}"

echo "=== assemble ==="
PYTHONPATH="$SENSOR" "$PY" "$TH/collect/assemble_dataset.py" \
  --data-dir "$DATA_DIR" --out-dir "$OUT_DIR" --sensor-commit "$SENSOR_COMMIT"

echo; echo "=== validate ==="
PYTHONPATH="$SENSOR" "$PY" "$TH/collect/validate_dataset.py" --dir "$OUT_DIR"
vrc=$?

echo; echo "=== report ==="
"$PY" "$TH/collect/make_report.py" --dataset "$OUT_DIR" --data-dir "$DATA_DIR" \
  --out "$TH/collect/COLLECTION_REPORT.md"

echo; echo "=== backup dataset (small) to $BACKUP ==="
# Root fs is tight; back up only the assembled dataset, NOT the multi-GB pcaps. The pcaps
# stay on the external drive (gzipped below).
mkdir -p "$BACKUP"
cp -rv "$OUT_DIR"/. "$BACKUP"/ | tail -8

echo; echo "=== gzip pcaps in place (keep on drive; do not fill root fs) ==="
find "$DATA_DIR/pcaps" -name '*.pcap' -print0 2>/dev/null | xargs -0r gzip -f || true
du -sh "$DATA_DIR/pcaps" 2>/dev/null || true

echo; echo "finish: dataset at $OUT_DIR ; backup at $BACKUP"
exit "$vrc"
