#!/usr/bin/env bash
# Sudo-less capture: run tcpdump inside a host-network container (root in the
# container), sniffing the ids-net bridge exactly like host tcpdump. Useful when
# passwordless host sudo is not available. Requires docker access.
set -euo pipefail
DURATION="${1:-1800}"
here="$(cd "$(dirname "$0")/.." && pwd)"
name="${2:-benign_baseline_$(date +%Y%m%d_%H%M%S).pcap}"
br="$("$here/capture/find_bridge.sh")"
mkdir -p "$here/data"

# Disable segmentation and receive offload on the capture path via a host-network
# NET_ADMIN container (no host sudo needed). With offload on, tcpdump records 64 KB
# super-segments instead of wire-sized frames, which inflates packet-length and
# byte-rate features and breaks fidelity. Covers the bridge and its enslaved veths.
ifaces="$br $(ip -o link | awk -v b="$br" '$0 ~ ("master " b)' | awk -F': ' '{print $2}' | sed 's/@.*//')"
docker run --rm --network host --cap-add NET_ADMIN nicolaka/netshoot:v0.13 \
  sh -c 'for ifc in '"$ifaces"'; do ethtool -K "$ifc" tso off gso off gro off 2>/dev/null || true; done' || true

echo "capturing on ${br} for ${DURATION}s into data/${name} (containerized tcpdump)"
docker run --rm --network host --cap-add NET_RAW --cap-add NET_ADMIN \
  -v "$here/data:/data" nicolaka/netshoot:v0.13 \
  timeout "$DURATION" tcpdump -i "$br" -w "/data/${name}" '(tcp or udp) and not arp' -s 0 || true
echo "saved data/${name}"
