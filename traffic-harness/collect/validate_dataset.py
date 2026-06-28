#!/usr/bin/env python3
"""Final validation gate for the assembled dataset (spec section 7).

Checks, against collect/dataset/:
  1. No NaN/inf anywhere in X.npy.
  2. Packet Length Max plausible (<= ~1500); Flow Bytes/s not in the billions (< 1e9).
  3. meta.csv aligns 1:1 with X.npy / y.npy (same N, same order assumed by construction).
  4. Each attack class has >=3 distinct tools present, and exactly one held-out tool, with
     zero rows leaking between the held-out tool and the trained tools.
  5. Prints final per-class and per-tool counts and the class balance.

Exits 0 if all checks pass, 1 otherwise. No em dashes.

Usage: validate_dataset.py --dir collect/dataset
"""
import argparse
import json
import os
import sys
from collections import Counter, defaultdict

import numpy as np
import pandas as pd

ATTACK_CLASSES = {"portscan", "dos", "bruteforce"}
PKTLEN_COL = "Packet Length Max"
BPS_COL = "Flow Bytes/s"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    ap.add_argument("--max-pktlen", type=float, default=1500.0)
    ap.add_argument("--max-bps", type=float, default=1e9)
    args = ap.parse_args()

    d = args.dir
    X = np.load(os.path.join(d, "X.npy"))
    y = np.load(os.path.join(d, "y.npy"))
    meta = pd.read_csv(os.path.join(d, "meta.csv"))
    with open(os.path.join(d, "label_map.json")) as fh:
        label_map = {int(k): v for k, v in json.load(fh).items()}

    fails = []

    # 1. NaN/inf
    n_nan = int(np.isnan(X).sum())
    n_inf = int(np.isinf(X).sum())
    if n_nan or n_inf:
        fails.append(f"X has {n_nan} NaN and {n_inf} inf values")

    # 2. fidelity on the assembled matrix
    cols = list(pd.read_csv(os.path.join(d, "dataset.csv"), nrows=0).columns)
    two = pd.read_csv(os.path.join(d, "dataset.csv"), usecols=[PKTLEN_COL, BPS_COL])
    pkt_hi = float(pd.to_numeric(two[PKTLEN_COL], errors="coerce").max())
    bps_hi = float(pd.to_numeric(two[BPS_COL], errors="coerce")
                   .replace([np.inf, -np.inf], np.nan).max(skipna=True))
    if not (pkt_hi <= args.max_pktlen):
        fails.append(f"Packet Length Max {pkt_hi} > {args.max_pktlen}")
    if not (bps_hi < args.max_bps):
        fails.append(f"Flow Bytes/s max {bps_hi} >= {args.max_bps}")

    # 3. alignment
    if not (X.shape[0] == y.shape[0] == len(meta)):
        fails.append(f"row mismatch X={X.shape[0]} y={y.shape[0]} meta={len(meta)}")
    if X.shape[1] != 56:
        fails.append(f"X has {X.shape[1]} cols, expected 56")

    # 4. tools per attack class + held-out integrity
    meta = meta.copy()
    meta["holdout"] = meta["holdout"].astype(str).str.lower().isin(["true", "1"])
    for cls in ATTACK_CLASSES:
        sub = meta[meta["class_name"] == cls]
        tools = sorted(sub["tool"].unique().tolist())
        held = sorted(sub[sub["holdout"]]["tool"].unique().tolist())
        trained = sorted(sub[~sub["holdout"]]["tool"].unique().tolist())
        if len(tools) < 3:
            fails.append(f"class {cls}: only {len(tools)} distinct tools ({tools}); need >=3")
        if len(held) != 1:
            fails.append(f"class {cls}: {len(held)} held-out tools ({held}); need exactly 1")
        leak = set(held) & set(trained)
        if leak:
            fails.append(f"class {cls}: tool(s) {sorted(leak)} appear as BOTH held-out and trained")

    # 5. report
    class_counts = Counter(label_map[int(v)] for v in y)
    total = int(X.shape[0])
    print("=== assembled dataset ===")
    print(f"X={X.shape} y={y.shape} meta={len(meta)} rows")
    print(f"pkt_len_max={pkt_hi}  flow_bps_max={bps_hi}  nan={n_nan} inf={n_inf}")
    print("\nper-class counts (label: name = count, balance):")
    for lbl in sorted(label_map):
        nm = label_map[lbl]
        c = class_counts.get(nm, 0)
        print(f"  {lbl} {nm:11s} {c:8d}  {c/total:.3f}")
    print("\nper-tool counts (class / tool [HOLDOUT] = count):")
    by = defaultdict(Counter)
    for _, r in meta.iterrows():
        by[r["class_name"]][(r["tool"], bool(r["holdout"]))] += 1
    for cls in sorted(by):
        for (tool, hold), c in sorted(by[cls].items(), key=lambda kv: -kv[1]):
            tag = " [HOLDOUT]" if hold else ""
            print(f"  {cls:11s} {tool:16s}{tag:10s} {c:8d}")

    print()
    if fails:
        print("VALIDATION: FAIL")
        for f in fails:
            print("  - " + f)
        sys.exit(1)
    print("VALIDATION: PASS")
    sys.exit(0)


if __name__ == "__main__":
    main()
