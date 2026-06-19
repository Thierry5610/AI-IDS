#!/usr/bin/env python3
"""
calibrate_threshold.py — estimate a network-local autoencoder threshold from a
benign capture, and quantify the false-positive rate of the CICIDS2017 threshold.

The shipped AE threshold (0.0726) is the 95th percentile of reconstruction error on
CICIDS2017 *benign* traffic. On a different network it floods false positives. This
runs an (assumed-benign) pcap through the validated aggregator, scores every flow via
the running inference service, and reports:
  - what fraction the current threshold flags as anomalous (= the FP rate here), and
  - the p90/p95/p99 of the local scores (candidate local thresholds).

Run (inference service must be up):
    python3 calibrate_threshold.py test.pcap
    python3 calibrate_threshold.py benign_5min.pcap   # longer/representative = better

Capture a representative benign window first, e.g.:
    sudo tcpdump -i wlp1s0 -w benign_5min.pcap -G 300 -W 1
"""
import sys
import json
import urllib.request
import urllib.error

from sensor.flow_features import run_pcap

URL = "http://127.0.0.1:8000/predict"
CURRENT_THR = 0.0726


def _percentile(sorted_vals, p):
    if not sorted_vals:
        return float("nan")
    k = (len(sorted_vals) - 1) * (p / 100.0)
    lo = int(k)
    hi = min(lo + 1, len(sorted_vals) - 1)
    frac = k - lo
    return sorted_vals[lo] * (1 - frac) + sorted_vals[hi] * frac


def _score(features):
    body = json.dumps({"features": features}).encode()
    req = urllib.request.Request(URL, data=body,
                                 headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=15) as r:
        resp = json.loads(r.read())
    ae = (resp.get("model_votes") or {}).get("autoencoder") or {}
    return ae.get("anomaly_score")


def main(pcap: str) -> None:
    flows = []
    run_pcap(pcap, lambda f: flows.append(f))
    if not flows:
        print("no flows in capture")
        return
    print(f"{len(flows)} flows; scoring via {URL} ...")

    scores, errors = [], 0
    for i, f in enumerate(flows):
        try:
            s = _score(f)
            if s is not None:
                scores.append(float(s))
        except (urllib.error.URLError, Exception):
            errors += 1
        if (i + 1) % 50 == 0:
            print(f"  {i + 1}/{len(flows)}")

    if not scores:
        print(f"no scores collected (errors={errors}). Is the inference service up on :8000?")
        return

    scores.sort()
    flagged = sum(1 for s in scores if s > CURRENT_THR)
    fp_rate = 100.0 * flagged / len(scores)

    print(f"\nscored {len(scores)} flows (assumed benign), errors={errors}")
    print(f"current threshold {CURRENT_THR}: flags {flagged}/{len(scores)} = {fp_rate:.1f}% as anomalous")
    print("local score distribution:")
    print(f"  min={scores[0]:.4f}  median={_percentile(scores, 50):.4f}  max={scores[-1]:.4f}")
    for p in (90, 95, 99):
        print(f"  p{p} = {_percentile(scores, p):.4f}")
    print(f"\nsuggested local threshold (p95) = {_percentile(scores, 95):.4f}")
    print("If you adopt it, set the AE threshold in the inference-service config and note")
    print("the before/after FP rate — that comparison is a result worth reporting.")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: python3 calibrate_threshold.py <benign_capture.pcap>")
        sys.exit(1)
    main(sys.argv[1])
