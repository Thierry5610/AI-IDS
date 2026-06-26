#!/usr/bin/env bash
# Run every generator concurrently for DURATION seconds, from this box.
# Run on BOTH client and attacker at once so the attacker's benign behavior is in
# the baseline and flow density is realistic.
set -euo pipefail
DURATION="${1:-1800}"
here="$(cd "$(dirname "$0")" && pwd)"
echo "starting benign simulation for ${DURATION}s"
bash "$here/gen_web.sh" "$DURATION" &
bash "$here/gen_ssh.sh" "$DURATION" &
bash "$here/gen_db.sh"  "$DURATION" &
bash "$here/gen_dns.sh" "$DURATION" &
wait
echo "simulation complete"
