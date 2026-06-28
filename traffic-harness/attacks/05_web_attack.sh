#!/usr/bin/env bash
# CICIDS Web Attack (directory brute force + SQLi probe). Expected to be the WEAKEST
# signal: the 56 flow features are statistical, not payload-aware, so dirb/sqlmap over
# HTTP look like ordinary small HTTP flows. If this stays silent on the danger lane that
# is the expected and correct result to report, not a bug to chase. No em dashes.
set -euo pipefail
TARGET=""
while [ $# -gt 0 ]; do case "$1" in --target) TARGET="${2:?}"; shift 2;; *) shift;; esac; done
[ -n "$TARGET" ] || { echo "usage: $0 --target <ip>" >&2; exit 2; }

echo "TOOL dirb http://${TARGET}:80/ + sqlmap probe"
echo "START_EPOCH $(date +%s)"
# Directory brute force (many small HTTP request/response flows).
dirb "http://${TARGET}:80/" /attacks/wordlist.txt -r -S || true
# Lightweight SQLi probe against a likely parameter (payload not visible at flow level).
sqlmap -u "http://${TARGET}:80/?id=1" --batch --crawl=0 --level=1 --risk=1 --flush-session 2>/dev/null || true
echo "END_EPOCH $(date +%s)"
