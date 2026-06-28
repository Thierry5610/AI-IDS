"""Offline scorer for the attack eval (Instrument A).

Reads a 56-feature CSV (FEATURE_ORDER header) and a parallel identities JSONL, POSTs
every row to the inference service /predict, and writes one JSONL line per flow with
the full vote. Stdlib only (urllib + csv) so it runs under any python3, independent of
the sensor or service venvs. No em dashes in this file.

Usage:
  score_flows.py --csv X.csv --identities ids.jsonl --attack portscan \
                 --url http://127.0.0.1:8000/predict --out flows.jsonl
"""
import argparse
import csv
import json
import os
import random
import sys
import urllib.error
import urllib.request


def post_predict(url, features, flow_id, timeout=30):
    body = json.dumps({"features": features, "flow_id": flow_id}).encode()
    req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode())


def vote(mv, name):
    v = (mv or {}).get(name) or {}
    return {"label": v.get("label"), "confidence": v.get("confidence")}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", required=True)
    ap.add_argument("--identities", required=True)
    ap.add_argument("--attack", required=True)
    ap.add_argument("--url", default="http://127.0.0.1:8000/predict")
    ap.add_argument("--out", required=True)
    ap.add_argument("--max-flows", type=int, default=0,
                    help="if >0 and captured flows exceed it, score a uniform random "
                         "sample of this many (seeded, reproducible). 0 = score all.")
    a = ap.parse_args()

    with open(a.identities) as fh:
        idents = [json.loads(line) for line in fh if line.strip()]

    with open(a.csv) as fh:
        reader = csv.DictReader(fh)
        rows = list(reader)
    total = len(rows)

    # Uniform sampling for pathologically large windows (e.g. a -p- portscan emits
    # ~65k near-identical 2-packet probes). Seeded so the run is reproducible. The
    # sampled count is what the summary reports; the full pcap/matrix stay on disk.
    indices = list(range(total))
    sampled = False
    if a.max_flows and total > a.max_flows:
        random.seed(0)
        indices = sorted(random.sample(indices, a.max_flows))
        sampled = True

    n_ok = n_err = 0
    with open(a.out, "w") as out:
        for i in indices:
            row = rows[i]
            features = {k: float(v) for k, v in row.items()}
            ident = idents[i] if i < len(idents) else {}
            flow_id = f"{a.attack}-{i}"
            try:
                r = post_predict(a.url, features, flow_id)
            except (urllib.error.URLError, ValueError) as e:
                n_err += 1
                out.write(json.dumps({"attack": a.attack, "flow_id": flow_id,
                                      "identity": ident, "error": str(e)}) + "\n")
                continue
            mv = r.get("model_votes", {})
            ae = (mv or {}).get("autoencoder") or {}
            rec = {
                "attack": a.attack,
                "flow_id": r.get("flow_id", flow_id),
                "identity": ident,
                "prediction": r.get("prediction"),
                "is_attack": r.get("is_attack"),
                "model_votes": {
                    "random_forest": vote(mv, "random_forest"),
                    "xgboost": vote(mv, "xgboost"),
                    "lightgbm": vote(mv, "lightgbm"),
                    "cnn_lstm": vote(mv, "cnn_lstm"),
                    "autoencoder": {
                        "anomaly_score": ae.get("anomaly_score"),
                        "threshold": ae.get("threshold"),
                        "is_anomalous": ae.get("is_anomalous"),
                    },
                },
                "agreement": r.get("agreement"),
            }
            out.write(json.dumps(rec) + "\n")
            n_ok += 1

    meta = {"attack": a.attack, "captured": total, "scored": n_ok,
            "errors": n_err, "sampled": sampled, "max_flows": a.max_flows}
    with open(os.path.splitext(a.out)[0] + ".meta.json", "w") as mh:
        json.dump(meta, mh)
    note = f"sampled {n_ok} of {total}" if sampled else f"all {n_ok}"
    print(f"[score] {a.attack}: {note} captured, errors={n_err} -> {a.out}")
    if n_ok == 0:
        print(f"[score] WARNING: no flows scored for {a.attack}", file=sys.stderr)


if __name__ == "__main__":
    main()
