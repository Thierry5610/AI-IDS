#!/usr/bin/env bash
# Benign ssh logins, commands, and occasional scp transfers against the ssh node.
set -euo pipefail
DURATION="${1:-1800}"
END=$(( $(date +%s) + DURATION ))
CMDS=( "ls -la /" "cat /etc/hostname" "uptime" "df -h" "ps aux" )
export SSHPASS="${SSH_PASS:-labpass}"
USER="${SSH_USER:-labuser}"
SSH_OPTS=( -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 )
while [ "$(date +%s)" -lt "$END" ]; do
  c="${CMDS[$RANDOM % ${#CMDS[@]}]}"
  sshpass -e ssh "${SSH_OPTS[@]}" "${USER}@ssh" "$c" >/dev/null 2>&1 || true
  # occasional file transfer for a bulk flow
  if [ $(( RANDOM % 5 )) -eq 0 ]; then
    head -c "$(( (RANDOM % 900 + 100) * 1024 ))" /dev/urandom > /tmp/xfer.bin
    sshpass -e scp "${SSH_OPTS[@]}" /tmp/xfer.bin "${USER}@ssh:/tmp/xfer.bin" >/dev/null 2>&1 || true
  fi
  sleep "$(( RANDOM % 5 + 1 ))"
done
