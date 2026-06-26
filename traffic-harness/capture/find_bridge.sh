#!/usr/bin/env bash
# Resolve the host bridge interface backing the ids-net network.
set -euo pipefail
net_id="$(docker network inspect ids-net -f '{{.Id}}')"
br="br-${net_id:0:12}"
if ip -o link show "$br" >/dev/null 2>&1; then
  echo "$br"
else
  ip -o link | grep -E 'br-|docker' >&2
  echo "could not auto-resolve br for ids-net" >&2
  exit 1
fi
