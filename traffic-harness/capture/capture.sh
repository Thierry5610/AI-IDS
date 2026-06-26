#!/usr/bin/env bash
# Capture benign traffic on the ids-net bridge for DURATION seconds (host tcpdump).
# Needs sudo for tcpdump. If you cannot use sudo, see capture_docker.sh.
set -euo pipefail
DURATION="${1:-1800}"
here="$(cd "$(dirname "$0")/.." && pwd)"
out="${2:-$here/data/benign_baseline_$(date +%Y%m%d_%H%M%S).pcap}"
br="$("$here/capture/find_bridge.sh")"
mkdir -p "$here/data"

# Disable segmentation and receive offload on the capture path first. With offload
# on, virtual interfaces hand tcpdump 64 KB super-segments instead of wire-sized
# frames, which inflates packet-length and byte-rate features and breaks fidelity
# against the dataset (validate_sensor would show packet lengths far above 1500).
# Best effort; needs privileges. Covers the bridge and its enslaved veths.
ifaces="$br $(ip -o link | awk -v b="$br" '$0 ~ ("master " b)' | awk -F': ' '{print $2}' | sed 's/@.*//')"
for ifc in $ifaces; do sudo ethtool -K "$ifc" tso off gso off gro off 2>/dev/null || true; done

echo "capturing on ${br} for ${DURATION}s into ${out}"
sudo timeout "$DURATION" tcpdump -i "$br" -w "$out" '(tcp or udp) and not arp' -s 0
echo "saved ${out}"
