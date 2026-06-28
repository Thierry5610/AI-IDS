#!/usr/bin/env python3
"""Generate COLLECTION_REPORT.md from the assembled dataset_manifest.json + tool_skips.

Reports what was collected: per-class and per-tool counts, the held-out tools, the fidelity
pass rate, tools that were skipped and why. No em dashes.

Usage: make_report.py --dataset collect/dataset --data-dir data/collect --out collect/COLLECTION_REPORT.md
"""
import argparse
import datetime as dt
import json
import os


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dataset", required=True)
    ap.add_argument("--data-dir", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    man = json.load(open(os.path.join(args.dataset, "dataset_manifest.json")))
    skips_path = os.path.join(args.data_dir, "tool_skips.txt")
    skips = [l.strip() for l in open(skips_path)] if os.path.exists(skips_path) else []

    targets = {"benign": 40000, "portscan": 12000, "dos": 12000, "bruteforce": 6000}
    cc = man.get("class_counts", {})
    tc = man.get("tool_counts", {})
    tpc = man.get("tools_per_class", {})
    holds = man.get("holdout_tools", [])

    L = []
    L.append("# Beehive v2 Collection Report")
    L.append("")
    L.append(f"Generated: {dt.datetime.now().isoformat(timespec='seconds')}")
    L.append(f"Capture date: {man.get('capture_date')}   Sensor commit: {man.get('sensor_commit')}")
    L.append(f"Total flows: {man.get('total_flows')}   Features: {man.get('n_features')}")
    L.append("")
    L.append("## Per-class counts (target)")
    L.append("")
    L.append("| label | class | flows | target | met | balance | tools present |")
    L.append("|------|-------|-------|--------|-----|---------|---------------|")
    lm = man.get("label_map", {})
    for lbl in sorted(lm, key=lambda k: int(k)):
        nm = lm[lbl]
        n = cc.get(nm, 0)
        t = targets.get(nm, 0)
        met = "yes" if n >= t else "NO"
        bal = man.get("class_balance", {}).get(nm, 0)
        tools = ", ".join(tpc.get(nm, []))
        L.append(f"| {lbl} | {nm} | {n} | {t} | {met} | {bal} | {tools} |")
    L.append("")
    L.append("## Per-tool counts")
    L.append("")
    L.append("| tool | flows | held-out |")
    L.append("|------|-------|----------|")
    for tool, n in sorted(tc.items(), key=lambda kv: -kv[1]):
        L.append(f"| {tool} | {n} | {'yes' if tool in holds else ''} |")
    L.append("")
    L.append("## Held-out tools (reserved, never trained)")
    L.append("")
    L.append(", ".join(holds) if holds else "(none)")
    L.append("")
    L.append("## Fidelity")
    L.append("")
    L.append(f"Windows passing fidelity gate: {man.get('fidelity_pass_windows')} / "
             f"{man.get('fidelity_total_windows')} "
             f"(rate {man.get('fidelity_pass_rate')}). Gate: packet length max <= 1500 and "
             f"Flow Bytes/s < 1e9 (offload off, wire-sized frames).")
    L.append(f"Windows included in dataset: {man.get('windows_included')}; "
             f"excluded (fidelity fail / empty): {man.get('windows_excluded')}.")
    L.append("")
    L.append("## Tool skips")
    L.append("")
    if skips:
        for s in skips:
            L.append(f"- {s}")
    else:
        L.append("None. All planned tools were available.")
    L.append("")

    with open(args.out, "w") as fh:
        fh.write("\n".join(L) + "\n")
    print("wrote", args.out)


if __name__ == "__main__":
    main()
