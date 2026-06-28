#!/usr/bin/env bash
# Portscan HELD-OUT tool: rustscan. A fast rust connect-scanner with a very different
# timing/batching fingerprint from nmap and pyscan, reserved for the held-out-tool
# generalization test (never trained on). Connect mode only (unprivileged), against live
# fleet hosts so probes complete >=2 packet flows. Randomizes batch size and timeout per
# run. Prints TOOL / START_EPOCH / END_EPOCH. No em dashes.
set -euo pipefail
TARGET=""; SEED="${SEED:-$$}"
while [ $# -gt 0 ]; do case "$1" in
  --target) TARGET="${2:?}"; shift 2;;
  --seed) SEED="${2:?}"; shift 2;;
  *) shift;; esac; done
[ -n "$TARGET" ] || { echo "usage: $0 --target <ip> [--seed n]" >&2; exit 2; }

command -v rustscan >/dev/null 2>&1 || { echo "SKIP rustscan not installed" >&2; exit 3; }

# Deterministic-from-seed but varied param choices.
BATCHES=(1500 3000 4500 6000)
TIMEOUTS=(800 1200 1600)
BATCH="${BATCHES[$((SEED % ${#BATCHES[@]}))]}"
TIMEOUT="${TIMEOUTS[$((SEED % ${#TIMEOUTS[@]}))]}"
RANGES=("1-10000" "1-65535" "1-20000")
RANGE="${RANGES[$((SEED % ${#RANGES[@]}))]}"

echo "TOOL rustscan -a ${TARGET} --range ${RANGE} -b ${BATCH} -t ${TIMEOUT} (connect)"
echo "START_EPOCH $(date +%s)"
# -b batch size, -t per-port timeout ms, --range port range, -g greppable, -n no-config.
# Tell rustscan not to hand off to nmap (-- ...) so this stays a pure connect scan.
rustscan -a "$TARGET" --range "$RANGE" -b "$BATCH" -t "$TIMEOUT" -g --no-config 2>/dev/null || true
echo "END_EPOCH $(date +%s)"
