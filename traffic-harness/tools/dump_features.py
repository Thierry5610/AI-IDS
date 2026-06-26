"""
Companion to the frozen sensor: aggregate a benign pcap into the 56-feature matrix.

Lives outside ebpf-sensor/sensor (which is frozen). It imports run_pcap and
FEATURE_ORDER from the sensor and collects every emitted flow into a matrix in the
exact training feature order, plus a CSV for inspection.

Usage: dump_features.py <pcap> <out.npy> <out.csv>
No em dashes in this file.
"""
import sys
import numpy as np
import pandas as pd
from sensor.flow_features import run_pcap, FEATURE_ORDER


def main():
    if len(sys.argv) != 4:
        print("usage: dump_features.py <pcap> <out.npy> <out.csv>")
        sys.exit(1)
    pcap, out_npy, out_csv = sys.argv[1], sys.argv[2], sys.argv[3]

    rows = []
    ports = {}

    def on_flow(feat, identity):
        rows.append([feat[c] for c in FEATURE_ORDER])
        dp = identity.get("dst_port")
        if dp is not None:
            ports[dp] = ports.get(dp, 0) + 1

    pkts = run_pcap(pcap, on_flow)

    df = pd.DataFrame(rows, columns=FEATURE_ORDER)
    arr = df.to_numpy(dtype="float32")
    np.save(out_npy, arr)
    df.to_csv(out_csv, index=False)

    top = sorted(ports.items(), key=lambda kv: -kv[1])[:10]
    print(f"packets read:       {pkts}")
    print(f"flows captured:     {len(df)}")
    print(f"distinct dst ports: {len(ports)} -> {sorted(ports)}")
    print(f"top ports (port:flows): {top}")
    print(f"saved matrix: {out_npy} shape={arr.shape}")
    print(f"saved csv:    {out_csv}")


if __name__ == "__main__":
    main()
