#!/usr/bin/env bash
# Bruteforce training tool: medusa against sshd. Each credential attempt is a short
# completed TCP session (>=2 packet flow). Distinct from hydra (different connection and
# timing behavior), giving the bruteforce class a second trained tool. Volume comes from
# wordlist length, not re-runs. NO early stop on success (no -f equivalent) so the whole
# list is attempted. Prints TOOL / START_EPOCH / END_EPOCH. No em dashes.
set -euo pipefail
TARGET=""; USER_NAME="${USER_NAME:-labuser}"; WORDLIST="${WORDLIST:-/collect/wordlists/passwords_1000.txt}"; TASKS="${TASKS:-4}"
while [ $# -gt 0 ]; do case "$1" in
  --target) TARGET="${2:?}"; shift 2;;
  --user) USER_NAME="${2:?}"; shift 2;;
  --wordlist) WORDLIST="${2:?}"; shift 2;;
  --tasks) TASKS="${2:?}"; shift 2;;
  *) shift;; esac; done
[ -n "$TARGET" ] || { echo "usage: $0 --target <ip> [--user n] [--wordlist f] [--tasks n]" >&2; exit 2; }

command -v medusa >/dev/null 2>&1 || { echo "SKIP medusa not installed" >&2; exit 3; }
[ -f "$WORDLIST" ] || { echo "SKIP wordlist missing: $WORDLIST" >&2; exit 3; }

echo "TOOL medusa -h ${TARGET} -u ${USER_NAME} -P ${WORDLIST} -M ssh -t ${TASKS}"
echo "START_EPOCH $(date +%s)"
# -h host, -u user, -P password file, -M module, -t parallel logins, -F = stop after first
# found across hosts; we deliberately OMIT -f/-F so the full list is attempted.
medusa -h "$TARGET" -u "$USER_NAME" -P "$WORDLIST" -M ssh -t "$TASKS" 2>&1 | tail -20 || true
echo "END_EPOCH $(date +%s)"
