"""
validate_sensor.py — scale/sanity gate for the flow aggregator.

Runs a pcap through sensor/flow_features.py and prints a side-by-side table of every
feature's distribution (min/median/mean/max) next to the training sample
(X_test_sample.npy). Run from the ebpf-sensor/ root:

    python3 validate_sensor.py test.pcap
    python3 validate_sensor.py test.pcap ../inference-service/app/artifacts

NOTE: a live laptop capture is NOT CICIDS2017, so values differ by design. What this
checks is STRUCTURAL: units/scales in the same band, no NaN/inf, payload-based lengths
under ~1500, Init Win showing -1s. Order-of-magnitude mismatch = a unit/definition bug.
Per-flow fidelity is a separate later test (CICIDS2017 pcap vs reference CICFlowMeter).
"""
import sys
import pickle
import numpy as np
import pandas as pd

from sensor.flow_features import run_pcap, FEATURE_ORDER


def _stats(df: pd.DataFrame) -> pd.DataFrame:
    return pd.DataFrame({
        "min": df.min(), "median": df.median(), "mean": df.mean(), "max": df.max(),
    })


def main(pcap: str, art: str = "../inference-service/app/artifacts") -> None:
    flows = []
    n_pkts = run_pcap(pcap, lambda f, ident: flows.append(f))
    if not flows:
        print(f"No flows emitted (packets read: {n_pkts}). "
              "Capture may be too short or have no TCP/UDP traffic.")
        return

    sensor = pd.DataFrame(flows)[FEATURE_ORDER].astype(float)

    cols = pickle.load(open(f"{art}/feature_cols_clean.pkl", "rb"))
    ref = pd.DataFrame(np.load(f"{art}/X_test_sample.npy"), columns=cols)[FEATURE_ORDER].astype(float)

    table = pd.concat({"SENSOR": _stats(sensor), "DATASET": _stats(ref)}, axis=1)

    pd.set_option("display.width", 200)
    pd.set_option("display.max_rows", 60)
    pd.set_option("display.float_format", lambda x: f"{x:,.2f}")

    print(f"\nflows emitted: {len(flows)}   packets read: {n_pkts}\n")
    print(table.to_string())

    # structural red flags (these would indicate real bugs, not traffic differences)
    bad = sensor.columns[~np.isfinite(sensor).all()].tolist()
    const = sensor.columns[sensor.nunique() <= 1].tolist()
    print()
    if bad:
        print("⚠ NaN/inf present in sensor output (BUG):", bad)
    else:
        print("✓ no NaN/inf in sensor output")
    if const:
        print("ℹ constant in this capture (often fine for small/uniform traffic):", const)

    print("\nReading guide: focus on whether SENSOR and DATASET sit in the same magnitude band")
    print("per feature. Same band = structurally faithful. 1000x off on Flow Duration / IAT = a")
    print("microsecond/nanosecond unit slip. Packet Length max near 1500 = frame length leaking in")
    print("instead of L4 payload. Init Win columns should show -1 among the values.")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: python3 validate_sensor.py <capture.pcap> [artifacts_dir]")
        sys.exit(1)
    main(*sys.argv[1:])
