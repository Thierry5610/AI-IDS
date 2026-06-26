#!/usr/bin/env bash
# Benign dns lookups (udp) against the dns node, for protocol variety.
set -euo pipefail
DURATION="${1:-1800}"
END=$(( $(date +%s) + DURATION ))
NAMES=( web db ssh mail lab.local app.lab.local )
while [ "$(date +%s)" -lt "$END" ]; do
  n="${NAMES[$RANDOM % ${#NAMES[@]}]}"
  dig @dns "$n" +short +timeout=2 >/dev/null 2>&1 || true
  sleep "$(( RANDOM % 3 + 1 ))"
done
