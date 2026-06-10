"""Replay-validation: prove the serving layer is faithful.

Feeds known CICIDS2017 test rows (the exact cleaned 56-feature matrix from the
Kaggle pipeline) into a running inference service and checks three things, from
cheapest to strongest:

  1. RECONSTRUCTION  - dict -> contract -> ordered array round-trips a row exactly
                       (catches feature-ordering / dtype bugs).
  2. ORDER-INVARIANCE - sending the same row with shuffled JSON keys yields the
                       same prediction (catches service-side ordering bugs over
                       HTTP, and JSON float-precision surprises).
  3. ACCURACY        - per-model accuracy vs ground-truth labels over the sample
                       (should track what you saw on Kaggle).
  4. PARITY (opt-in) - HTTP prediction == the same model's prediction computed
                       directly on the raw array in-process, per row. The
                       strongest check; loads the models a second time, so gate
                       it behind --parity and run when RAM allows.

This isolates "is serving faithful" from "is the sensor faithful": run it before
the eBPF sensor exists, and any later mismatch is the sensor's fault, not this.

Data needed (from /kaggle/working/processed/):
  X_test_clean.npy  (or X_test_sample.npy)   - cleaned 56-feature test matrix
  y_test.npy        (or y_test_sample.npy)   - integer labels
  feature_cols_clean.pkl, label_encoder.pkl  - already in app/artifacts/

If the full test arrays are too big to copy off Kaggle, save a sample there:

  import numpy as np
  idx = np.random.RandomState(0).choice(len(X_test_clean), 2000, replace=False)
  np.save('X_test_sample.npy', X_test_clean[idx])
  np.save('y_test_sample.npy', y_test[idx])

Usage:
  python validate_serving.py --data-dir app/artifacts --n 500
  python validate_serving.py --data-dir app/artifacts --n 500 --parity
"""
import argparse
import json
import os
import pickle
import sys
import urllib.error
import urllib.request

import numpy as np


def post_predict(base_url, features, flow_id=None):
    body = json.dumps({"flow_id": flow_id, "features": features}).encode()
    req = urllib.request.Request(
        f"{base_url}/predict", data=body, headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())


def load_array(data_dir, primary, fallback):
    for name in (primary, fallback):
        p = os.path.join(data_dir, name)
        if os.path.exists(p):
            return np.load(p), name
    raise FileNotFoundError(f"Need {primary} or {fallback} in {data_dir}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", default="http://localhost:8000")
    ap.add_argument("--data-dir", default="app/artifacts")
    ap.add_argument("--n", type=int, default=500)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--parity", action="store_true",
                    help="also compare HTTP vs in-process direct prediction (loads models again)")
    args = ap.parse_args()

    # The contract is loaded from the same artifact the service uses.
    os.environ.setdefault("ARTIFACT_DIR", args.data_dir)
    from app.features import FeatureContract  # noqa: E402
    contract = FeatureContract.load()

    le = pickle.load(open(os.path.join(args.data_dir, "label_encoder.pkl"), "rb"))
    X, xname = load_array(args.data_dir, "X_test_clean.npy", "X_test_sample.npy")
    y, yname = load_array(args.data_dir, "y_test.npy", "y_test_sample.npy")
    X = np.asarray(X, dtype=np.float32)
    print(f"Loaded {xname} {X.shape}, {yname} {y.shape}; contract {len(contract.columns)} features")

    if X.shape[1] != len(contract.columns):
        sys.exit(f"FATAL: data has {X.shape[1]} columns, contract expects {len(contract.columns)}")

    rng = np.random.RandomState(args.seed)
    n = min(args.n, len(X))
    idx = rng.choice(len(X), n, replace=False)

    reg = None
    if args.parity:
        from app.registry import ModelRegistry  # noqa: E402
        reg = ModelRegistry(); reg.load()
        print("Parity mode: models loaded in-process for direct comparison")

    recon_fail = 0
    order_fail = 0
    http_vs_direct_fail = {}     # model -> mismatch count
    correct = {}                 # model -> correct count vs ground truth
    seen = {}                    # model -> rows seen
    source_correct = 0

    cols = contract.columns
    for k, i in enumerate(idx):
        row = X[i]
        feats = {c: float(row[j]) for j, c in enumerate(cols)}

        # 1. reconstruction
        x = contract.validate_and_order(feats)
        if not np.allclose(x[0], row, rtol=1e-5, atol=1e-6):
            recon_fail += 1

        # HTTP prediction
        resp = post_predict(args.base_url, feats, flow_id=f"replay-{i}")
        votes = resp["model_votes"]

        # 2. order-invariance: shuffle dict key order, must not change source pred
        shuffled = dict(sorted(feats.items(), key=lambda kv: rng.random()))
        resp2 = post_predict(args.base_url, shuffled)
        if resp2["prediction"]["label"] != resp["prediction"]["label"]:
            order_fail += 1

        # 3. accuracy vs ground truth
        truth = int(y[i])
        if resp["prediction"].get("label_index") == truth:
            source_correct += 1
        for m, v in votes.items():
            if v.get("label_index") is None:
                continue
            seen[m] = seen.get(m, 0) + 1
            if v["label_index"] == truth:
                correct[m] = correct.get(m, 0) + 1

        # 4. parity
        if reg is not None:
            direct = reg.predict_all(row.reshape(1, -1))
            for m, v in votes.items():
                if v.get("label_index") is None or m not in direct:
                    continue
                if direct[m].get("label_index") != v["label_index"]:
                    http_vs_direct_fail[m] = http_vs_direct_fail.get(m, 0) + 1

        if (k + 1) % 100 == 0:
            print(f"  ...{k + 1}/{n}")

    print("\n================ SERVING FIDELITY REPORT ================")
    print(f"rows checked: {n}")
    print(f"[1] reconstruction failures : {recon_fail}  (want 0)")
    print(f"[2] order-invariance failures: {order_fail}  (want 0)")
    if reg is not None:
        if http_vs_direct_fail:
            print(f"[4] HTTP-vs-direct mismatches: {http_vs_direct_fail}  (want empty)")
        else:
            print("[4] HTTP-vs-direct mismatches: none  (serving reproduces models exactly)")
    print(f"\n[3] accuracy vs ground truth (sample of {n}):")
    print(f"    source-model selection: {source_correct / n:.4f}")
    for m in sorted(seen):
        print(f"    {m:<16} {correct.get(m, 0) / seen[m]:.4f}")
    print("=========================================================")

    ok = recon_fail == 0 and order_fail == 0 and not http_vs_direct_fail
    print("RESULT:", "SERVING FAITHFUL" if ok else "DISCREPANCIES FOUND - investigate above")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()