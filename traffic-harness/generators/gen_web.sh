#!/usr/bin/env bash
# Benign HTTP and HTTPS requests of varied sizes against the web node.
set -euo pipefail
DURATION="${1:-1800}"
END=$(( $(date +%s) + DURATION ))
PATHS=( "/" "/small.txt" "/medium.bin" "/large.bin" )
while [ "$(date +%s)" -lt "$END" ]; do
  p="${PATHS[$RANDOM % ${#PATHS[@]}]}"
  curl -s -o /dev/null "http://web${p}"     || true
  curl -s -k -o /dev/null "https://web${p}" || true
  sleep "0.$(( RANDOM % 9 ))$(( RANDOM % 9 ))"            # sub second jitter
  [ $(( RANDOM % 7 )) -eq 0 ] && sleep "$(( RANDOM % 4 ))" # occasional longer pause
done
