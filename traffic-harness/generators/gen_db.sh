#!/usr/bin/env bash
# Benign mysql queries (select and insert) against the db node.
set -euo pipefail
DURATION="${1:-1800}"
END=$(( $(date +%s) + DURATION ))
USER="${DB_USER:-labuser}"; PASS="${DB_PASS:-labpass}"; DBN="${DB_NAME:-labdb}"
Q=(
  "SELECT COUNT(*) FROM events;"
  "SELECT * FROM events ORDER BY id DESC LIMIT 20;"
  "INSERT INTO events (msg) VALUES ('ping');"
  "SELECT msg FROM events WHERE id % 3 = 0 LIMIT 50;"
)
while [ "$(date +%s)" -lt "$END" ]; do
  q="${Q[$RANDOM % ${#Q[@]}]}"
  mysql -h db -u "$USER" -p"$PASS" "$DBN" -e "$q" >/dev/null 2>&1 || true
  sleep "0.$(( RANDOM % 9 ))$(( RANDOM % 9 ))"
  [ $(( RANDOM % 6 )) -eq 0 ] && sleep "$(( RANDOM % 3 ))"
done
