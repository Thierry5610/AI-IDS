"""Companion to the frozen sensor for the attack eval (additive, sensor untouched).

Like tools/dump_features.py it imports run_pcap and FEATURE_ORDER and aggregates a
pcap into the 56-feature matrix in exact training order. It additionally emits a
parallel identities JSONL (one 5-tuple per matrix row, same order) so the offline
scorer can attribute every /predict response to its flow. tools/dump_features.py
drops identity, which is why this companion exists.

Usage: dump_attack_features.py <pcap> <out.npy> <out.csv> <identities.jsonl>
No em dashes in this file.
"""
import json
import sys

import numpy as np
import pandas as pd
from sensor.flow_features import run_pcap, FEATURE_ORDER


def main():
    if len(sys.argv) != 5:
        print("usage: dump_attack_features.py <pcap> <out.npy> <out.csv> <identities.jsonl>")
        sys.exit(1)
    pcap, out_npy, out_csv, out_ids = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

    rows = []
    idents = []

    def on_flow(feat, identity):
        rows.append([feat[c] for c in FEATURE_ORDER])
        idents.append(identity)

    pkts = run_pcap(pcap, on_flow)

    df = pd.DataFrame(rows, columns=FEATURE_ORDER)
    arr = df.to_numpy(dtype="float32")
    np.save(out_npy, arr)
    df.to_csv(out_csv, index=False)
    with open(out_ids, "w") as fh:
        for ident in idents:
            fh.write(json.dumps(ident) + "\n")

    print(f"packets read:   {pkts}")
    print(f"flows captured: {len(df)}")
    print(f"saved matrix:   {out_npy} shape={arr.shape}")
    print(f"saved csv:      {out_csv}")
    print(f"saved idents:   {out_ids} ({len(idents)} rows)")


if __name__ == "__main__":
    main()
