#!/usr/bin/env bash
# Aggregate a benign pcap into the 56-feature matrix using the frozen sensor core.
# Runs under the sensor .venv (dpkt, numpy, pandas) with the sensor on PYTHONPATH so
# the companion can import run_pcap and FEATURE_ORDER. Does not modify the sensor.
set -euo pipefail
pcap="${1:?usage: to_features.sh <pcap>}"
here="$(cd "$(dirname "$0")/.." && pwd)"          # traffic-harness/
sensor_root="$(cd "$here/.." && pwd)/ebpf-sensor"
src="$(cd "$(dirname "$pcap")" && pwd)/$(basename "$pcap")"
mkdir -p "$here/data"
PYTHONPATH="$sensor_root" "$sensor_root/.venv/bin/python" \
  "$here/tools/dump_features.py" "$src" \
  "$here/data/X_benign_local.npy" "$here/data/X_benign_local.csv"
