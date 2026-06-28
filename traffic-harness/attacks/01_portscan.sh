#!/usr/bin/env bash
# CICIDS PortScan. Connect scan (-sT): snap/unprivileged nmap cannot raw-SYN, and
# against responsive fleet hosts a connect scan completes handshakes / SYN+RST so
# every probe is a >=2 packet flow that reaches the classifier. No em dashes.
set -euo pipefail
TARGET=""
while [ $# -gt 0 ]; do case "$1" in --target) TARGET="${2:?}"; shift 2;; *) shift;; esac; done
[ -n "$TARGET" ] || { echo "usage: $0 --target <ip>" >&2; exit 2; }

echo "TOOL nmap -sT -p- -T4 ${TARGET}"
echo "START_EPOCH $(date +%s)"
nmap -sT -p- -T4 --max-retries 1 "$TARGET" || true
echo "END_EPOCH $(date +%s)"
