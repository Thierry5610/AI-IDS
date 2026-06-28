#!/usr/bin/env python3
"""Per-window fidelity gate for the collection driver.

After a capture is converted to the 56-feature matrix, re-assert the two checks that
prove NIC offload was actually off and tcpdump recorded wire-sized frames (not 64 KB
super-segments that inflate length/byte-rate features):

  1. max(Packet Length Max) <= ~1500   (a real Ethernet MTU frame; offload-on shows >> 1500)
  2. max(Flow Bytes/s) < 1e9            (no flow byte-rate in the billions)

Reads the per-window X.csv (the 56-feature CSV from dump_features). Prints a one-line JSON
summary and exits 0 on PASS, 1 on FAIL. An empty matrix (no flows) is treated as a PASS
with flows=0 so a short window does not abort the whole run; the driver records the count.
No em dashes.

Usage: fidelity_gate.py <X.csv> [--max-pktlen 1500] [--max-bps 1e9]
"""
import argparse
import json
import sys

import pandas as pd

PKTLEN_COL = "Packet Length Max"
BPS_COL = "Flow Bytes/s"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("csv")
    ap.add_argument("--max-pktlen", type=float, default=1500.0)
    ap.add_argument("--max-bps", type=float, default=1e9)
    args = ap.parse_args()

    try:
        df = pd.read_csv(args.csv)
    except Exception as exc:
        print(json.dumps({"fidelity": "fail", "reason": f"unreadable: {exc}", "flows": 0}))
        sys.exit(1)

    if len(df) == 0:
        print(json.dumps({"fidelity": "pass", "flows": 0, "note": "empty matrix"}))
        sys.exit(0)

    # numeric coercion; inf/nan handled explicitly
    pktmax = pd.to_numeric(df[PKTLEN_COL], errors="coerce")
    bps = pd.to_numeric(df[BPS_COL], errors="coerce").replace([float("inf"), float("-inf")], float("nan"))
    pkt_hi = float(pktmax.max())
    bps_hi = float(bps.max(skipna=True)) if bps.notna().any() else 0.0

    ok_pkt = pkt_hi <= args.max_pktlen
    ok_bps = bps_hi < args.max_bps
    passed = ok_pkt and ok_bps

    out = {
        "fidelity": "pass" if passed else "fail",
        "flows": int(len(df)),
        "pkt_len_max": round(pkt_hi, 2),
        "flow_bps_max": round(bps_hi, 2),
        "ok_pkt_len": ok_pkt,
        "ok_flow_bps": ok_bps,
    }
    print(json.dumps(out))
    sys.exit(0 if passed else 1)


if __name__ == "__main__":
    main()
