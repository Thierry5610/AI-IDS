#!/usr/bin/env bash
# DoS training tool: ApacheBench (ab). High-concurrency volumetric HTTP load against live
# nginx. Distinct from goldeneye/hulk: ab issues a fixed huge request count at a set
# concurrency with its own connection-reuse pattern, a third distinct volumetric
# fingerprint in the dos class. Every request completes a real HTTP flow (>=2 packets).
# Randomizes concurrency / request count per run. Prints TOOL / START_EPOCH / END_EPOCH.
# No em dashes.
set -euo pipefail
TARGET=""; PORT="${PORT:-80}"; SEED="${SEED:-$$}"; REQ_CLI=""
while [ $# -gt 0 ]; do case "$1" in
  --target) TARGET="${2:?}"; shift 2;;
  --port) PORT="${2:?}"; shift 2;;
  --seed) SEED="${2:?}"; shift 2;;
  --reqs) REQ_CLI="${2:?}"; shift 2;;
  *) shift;; esac; done
[ -n "$TARGET" ] || { echo "usage: $0 --target <ip> [--port n] [--seed n] [--reqs n]" >&2; exit 2; }

command -v ab >/dev/null 2>&1 || { echo "SKIP ab (apache2-utils) not installed" >&2; exit 3; }

CONCS=(50 100 150 200)
REQS=(5000 8000 12000 16000)
CONC="${CONCS[$((SEED % ${#CONCS[@]}))]}"
REQ="${REQS[$((SEED % ${#REQS[@]}))]}"
# Explicit --reqs overrides the seed-chosen count (target-driven sizing / smoke).
[ -n "$REQ_CLI" ] && REQ="$REQ_CLI"
# NOTE: no keep-alive. ab -k reuses one TCP connection for many requests, which collapses
# thousands of requests into a handful of flows (measured: 5000 reqs -> 50 flows). Without
# -k each request is its own connection = its own flow, which is what the dos class needs.

echo "TOOL ab -n ${REQ} -c ${CONC} http://${TARGET}:${PORT}/"
echo "START_EPOCH $(date +%s)"
# -n total requests, -c concurrency, -s socket timeout, -r continue on error.
ab -n "$REQ" -c "$CONC" -s 10 -r "http://${TARGET}:${PORT}/" 2>&1 | tail -20 || true
echo "END_EPOCH $(date +%s)"
