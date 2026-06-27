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

# Disable segmentation and receive offload on the WHOLE capture path so tcpdump
# records wire-sized frames, not 64 KB super-segments (which inflate packet-length
# and byte-rate features and break fidelity). Offload lives in three places: the
# bridge, its host-side veths, and each container eth0 (where TCP segmentation
# actually happens). All done via host-net / container-netns NET_ADMIN containers,
# so no host sudo is needed.
NET="nicolaka/netshoot:v0.13"
ifaces="$(printf '%s ' "$br"; ip -o link | awk -v b="$br" '$0 ~ ("master " b)' | awk -F': ' '{print $2}' | sed 's/@.*//' | tr '\n' ' ')"
docker run --rm --network host --cap-add NET_ADMIN -e IFACES="$ifaces" "$NET" \
  sh -c 'for ifc in $IFACES; do ethtool -K "$ifc" tso off gso off gro off 2>/dev/null || true; done' || true
for c in web ssh db client attacker dns; do
  docker run --rm --net "container:$c" --cap-add NET_ADMIN "$NET" \
    ethtool -K eth0 tso off gso off gro off >/dev/null 2>&1 || true
done

echo "capturing on ${br} for ${DURATION}s into data/${name} (containerized tcpdump)"
docker run --rm --network host --cap-add NET_RAW --cap-add NET_ADMIN \
  -v "$here/data:/data" "$NET" \
  timeout "$DURATION" tcpdump -i "$br" -w "/data/${name}" '(tcp or udp) and not arp' -s 0 || true
echo "saved data/${name}"
