"""Build the attack-eval summary table (Instrument A centerpiece).

Reads every <attack>.flows.jsonl in a results dir and emits summary.csv + summary.md,
one row per attack (plus the benign control). Stdlib only. The table is valid whether
percentages are high or low: silence on the danger lane with the AE firing is the
two-lane thesis, not a failed test. No em dashes in this file.

Usage: tabulate.py --indir <dir> --tools tools.json --out-csv summary.csv --out-md summary.md
"""
import argparse
import csv
import glob
import json
import os

BENIGN = "benign"

COLS = ["attack", "flows", "RF fire%", "XGB fire%", "LGBM fire%", "CNN-LSTM fire%",
        "ensemble is_attack%", "mean consensus", "AE anomalous%", "mean AE error", "tool/flags"]


def pct(num, den):
    return round(100.0 * num / den, 1) if den else 0.0


def is_fire(v):
    lab = (v or {}).get("label")
    return bool(lab) and lab.strip().lower() != BENIGN


def summarize(path, attack, tool):
    recs = []
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            r = json.loads(line)
            if "error" in r:
                continue
            recs.append(r)
    n = len(recs)
    if n == 0:
        return dict(zip(COLS, [attack, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, tool]))

    rf = sum(is_fire(r["model_votes"]["random_forest"]) for r in recs)
    xgb = sum(is_fire(r["model_votes"]["xgboost"]) for r in recs)
    lgbm = sum(is_fire(r["model_votes"]["lightgbm"]) for r in recs)
    cnn = sum(is_fire(r["model_votes"]["cnn_lstm"]) for r in recs)
    ens = sum(1 for r in recs if r.get("is_attack"))

    cons_vals = []
    ae_anom = 0
    ae_errs = []
    for r in recs:
        ag = r.get("agreement") or {}
        tot = ag.get("total") or 0
        if tot:
            cons_vals.append((ag.get("agreeing") or 0) / tot)
        ae = r["model_votes"]["autoencoder"]
        if ae.get("is_anomalous"):
            ae_anom += 1
        if ae.get("anomaly_score") is not None:
            ae_errs.append(ae["anomaly_score"])

    mean_cons = round(sum(cons_vals) / len(cons_vals), 3) if cons_vals else 0.0
    mean_ae = round(sum(ae_errs) / len(ae_errs), 4) if ae_errs else 0.0

    return dict(zip(COLS, [
        attack, n, pct(rf, n), pct(xgb, n), pct(lgbm, n), pct(cnn, n),
        pct(ens, n), mean_cons, pct(ae_anom, n), mean_ae, tool,
    ]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--indir", required=True)
    ap.add_argument("--tools", default="")
    ap.add_argument("--out-csv", required=True)
    ap.add_argument("--out-md", required=True)
    a = ap.parse_args()

    tools = {}
    if a.tools and os.path.exists(a.tools):
        with open(a.tools) as fh:
            tools = json.load(fh)

    rows = []
    for path in sorted(glob.glob(os.path.join(a.indir, "*.flows.jsonl"))):
        attack = os.path.basename(path)[: -len(".flows.jsonl")]
        rows.append(summarize(path, attack, tools.get(attack, "")))

    with open(a.out_csv, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=COLS)
        w.writeheader()
        w.writerows(rows)

    with open(a.out_md, "w") as fh:
        fh.write("| " + " | ".join(COLS) + " |\n")
        fh.write("|" + "|".join("---" for _ in COLS) + "|\n")
        for r in rows:
            fh.write("| " + " | ".join(str(r[c]) for c in COLS) + " |\n")

    print(f"[tabulate] {len(rows)} rows -> {a.out_csv}, {a.out_md}")


if __name__ == "__main__":
    main()
