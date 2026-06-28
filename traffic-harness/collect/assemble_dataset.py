#!/usr/bin/env python3
"""Assemble all per-window matrices into one labeled, Kaggle-ready training set.

Reads data/collect/manifest.jsonl (one row per capture window) and the per-window
<window_id>.X.npy matrices the driver produced through the FROZEN sensor, and stacks them
in FEATURE_ORDER. Only windows that PASSED the fidelity gate and have a non-empty matrix
are included in X/y; every window stays in the manifest for the report.

Per-flow provenance (tool, window_id, holdout, class_name) is carried per row so the
held-out-tool split is possible at train time. Web/infiltration are never captured here,
so they cannot leak into y.

Outputs to collect/dataset/:
  X.npy  float32 (N,56)         y.npy int           meta.csv (tool,window_id,holdout,class_name)
  label_map.json               dataset.csv (56 feats + class + tool + holdout)
  dataset_manifest.json (per-class/per-tool counts, balance, held-out tools, fidelity rate)

No em dashes.

Usage: assemble_dataset.py --data-dir data/collect --out-dir collect/dataset
       [--sensor-commit 9bb5c4c]
"""
import argparse
import datetime as dt
import json
import os
from collections import Counter

import numpy as np
import pandas as pd

LABEL_MAP = {0: "benign", 1: "portscan", 2: "dos", 3: "bruteforce"}
NAME_TO_LABEL = {v: k for k, v in LABEL_MAP.items()}


def load_manifest(path):
    rows = []
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data-dir", required=True)
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--sensor-commit", default="unknown")
    args = ap.parse_args()

    man_path = os.path.join(args.data_dir, "manifest.jsonl")
    manifest = load_manifest(man_path)
    os.makedirs(args.out_dir, exist_ok=True)

    feat_cols = None
    X_parts, y_parts = [], []
    meta_rows = []
    incl, excl = 0, 0
    fidelity_pass = 0

    for w in manifest:
        wid = w["window_id"]
        cls = w["class"]
        if w.get("fidelity") == "pass":
            fidelity_pass += 1
        npy = os.path.join(args.data_dir, f"{wid}.X.npy")
        csv = os.path.join(args.data_dir, f"{wid}.X.csv")
        if not os.path.exists(npy):
            excl += 1
            continue
        # exclude fidelity failures and empty matrices from the training set
        if w.get("fidelity") != "pass":
            excl += 1
            continue
        arr = np.load(npy)
        if arr.shape[0] == 0:
            excl += 1
            continue
        if feat_cols is None and os.path.exists(csv):
            feat_cols = list(pd.read_csv(csv, nrows=0).columns)
        if arr.shape[1] != 56:
            raise SystemExit(f"window {wid}: matrix has {arr.shape[1]} cols, expected 56")
        n = arr.shape[0]
        label = NAME_TO_LABEL[cls]
        X_parts.append(arr.astype("float32"))
        y_parts.append(np.full(n, label, dtype="int64"))
        hold = bool(w.get("holdout", False))
        tool = w.get("tool", "unknown")
        meta_rows.extend([(tool, wid, hold, cls)] * n)
        incl += 1

    if not X_parts:
        raise SystemExit("no included windows; nothing to assemble")
    if feat_cols is None or len(feat_cols) != 56:
        raise SystemExit("could not resolve 56 feature column names from any X.csv")

    X = np.vstack(X_parts)
    y = np.concatenate(y_parts)
    meta = pd.DataFrame(meta_rows, columns=["tool", "window_id", "holdout", "class_name"])
    assert len(meta) == X.shape[0] == y.shape[0], "row count mismatch X/y/meta"

    np.save(os.path.join(args.out_dir, "X.npy"), X)
    np.save(os.path.join(args.out_dir, "y.npy"), y)
    meta.to_csv(os.path.join(args.out_dir, "meta.csv"), index=False)
    with open(os.path.join(args.out_dir, "label_map.json"), "w") as fh:
        json.dump({str(k): v for k, v in LABEL_MAP.items()}, fh, indent=2)

    # combined inspection table: 56 features + class + tool + holdout
    ds = pd.DataFrame(X, columns=feat_cols)
    ds["class"] = [LABEL_MAP[int(v)] for v in y]
    ds["tool"] = meta["tool"].values
    ds["holdout"] = meta["holdout"].values
    ds.to_csv(os.path.join(args.out_dir, "dataset.csv"), index=False)

    # per-class / per-tool counts and held-out tools
    class_counts = Counter(LABEL_MAP[int(v)] for v in y)
    tool_counts = Counter(meta["tool"].tolist())
    holdout_tools = sorted({w.get("tool") for w in manifest
                            if w.get("holdout") and w.get("fidelity") == "pass"})
    # tools present per class (training only) for the >=3 check downstream
    tools_per_class = {}
    for cls in LABEL_MAP.values():
        sub = meta[meta["class_name"] == cls]
        tools_per_class[cls] = sorted(sub["tool"].unique().tolist())

    total = int(X.shape[0])
    manifest_out = {
        "capture_date": dt.date.today().isoformat(),
        "sensor_commit": args.sensor_commit,
        "total_flows": total,
        "n_features": 56,
        "label_map": LABEL_MAP,
        "class_counts": dict(class_counts),
        "class_balance": {k: round(v / total, 4) for k, v in class_counts.items()},
        "tool_counts": dict(tool_counts),
        "tools_per_class": tools_per_class,
        "holdout_tools": holdout_tools,
        "windows_included": incl,
        "windows_excluded": excl,
        "fidelity_pass_windows": fidelity_pass,
        "fidelity_total_windows": len(manifest),
        "fidelity_pass_rate": round(fidelity_pass / max(1, len(manifest)), 4),
    }
    with open(os.path.join(args.out_dir, "dataset_manifest.json"), "w") as fh:
        json.dump(manifest_out, fh, indent=2)

    print(f"assembled X={X.shape} y={y.shape} from {incl} windows ({excl} excluded)")
    print("class_counts:", dict(class_counts))
    print("tool_counts: ", dict(tool_counts))
    print("holdout_tools:", holdout_tools)
    print(f"wrote dataset to {args.out_dir}")


if __name__ == "__main__":
    main()
