"""
Retrain a local-baseline autoencoder from scratch on locally captured benign traffic.

Reuses the original AE architecture exactly (imported from app.architectures, read only),
fits a fresh StandardScaler on local data, trains from random init (no warm start), and
sets a new threshold from the local benign reconstruction-error distribution. Produces a
parallel "local-baseline" variant; the frozen original is never written to.

Run under inference-service/.venv on CPU:
    cd inference-service && .venv/bin/python scripts/retrain_ae_local.py

No em dashes in this file.
"""
import copy
import datetime as dt
import hashlib
import json
import pickle
import subprocess
import sys
from pathlib import Path

import numpy as np
from sklearn.preprocessing import StandardScaler
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset

# ---- paths -----------------------------------------------------------------
INF = Path(__file__).resolve().parents[1]            # inference-service/
REPO = INF.parent
sys.path.insert(0, str(INF))                         # so "app" is importable
from app.architectures import Autoencoder            # exact architecture reuse
from app import config                               # read-only, for constants

DATA_DIR = REPO / "traffic-harness" / "data"
ART = INF / "app" / "artifacts"
ORIG_AE = ART / config.ARTIFACTS["autoencoder"]
ORIG_SCALER = ART / config.AE_SCALER_FILE
OUT = INF / "models" / "local_baseline"
OUT.mkdir(parents=True, exist_ok=True)
AE_LOCAL = OUT / "ae_local.pt"
SCALER_LOCAL = OUT / "ae_scaler_local.pkl"
THRESH_JSON = OUT / "ae_threshold_local.json"

SEED = 1337
NF = config.NUM_FEATURES                             # 56


def sha256_file(p: Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def git_commit() -> str:
    try:
        return subprocess.check_output(
            ["git", "-C", str(REPO), "rev-parse", "HEAD"], text=True).strip()
    except Exception:
        return "unknown"


def per_row_mse(model, Xs: np.ndarray) -> np.ndarray:
    """Reconstruction MSE per row, matching the service metric (mean over features)."""
    model.eval()
    with torch.no_grad():
        t = torch.tensor(Xs, dtype=torch.float32)
        recon = model(t).numpy()
    return np.mean((Xs - recon) ** 2, axis=1)


def main():
    print("=== paths ===")
    print(f"repo:           {REPO}")
    print(f"data dir:       {DATA_DIR}")
    print(f"original AE:    {ORIG_AE}")
    print(f"original scaler:{ORIG_SCALER}")
    print(f"output dir:     {OUT}")

    # sha256 of frozen originals BEFORE (must be unchanged at the end)
    orig_ae_sha_before = sha256_file(ORIG_AE)
    orig_scaler_sha_before = sha256_file(ORIG_SCALER)

    # ---- step 2: load + stack every benign matrix --------------------------
    files = sorted(DATA_DIR.glob("X_benign_local*.npy"))
    if not files:
        sys.exit(f"no X_benign_local*.npy in {DATA_DIR}")
    per_file = {}
    mats = []
    print("\n=== benign matrices ===")
    for f in files:
        a = np.load(f)
        if a.ndim != 2 or a.shape[1] != NF:
            sys.exit(f"shape mismatch in {f.name}: {a.shape}, expected (N,{NF})")
        a = a.astype(np.float32)
        per_file[f.name] = int(a.shape[0])
        mats.append(a)
        print(f"  {f.name}: {a.shape}")
    X = np.vstack(mats).astype(np.float32)
    total = int(X.shape[0])
    combined_sha = hashlib.sha256(np.ascontiguousarray(X).tobytes()).hexdigest()
    print(f"  combined: {X.shape}  sha256={combined_sha[:16]}...")

    # ---- step 3: architecture (imported, exact) ----------------------------
    print("\n=== architecture (reused from app.architectures.Autoencoder) ===")
    print(Autoencoder(input_dim=NF))
    print(f"original AE format: torch state_dict ({ORIG_AE.name})")

    # ---- step 4: fresh scaler on local data --------------------------------
    np.random.seed(SEED)
    torch.manual_seed(SEED)
    scaler = StandardScaler().fit(X)
    with open(SCALER_LOCAL, "wb") as fh:
        pickle.dump(scaler, fh)
    Xs = scaler.transform(X).astype(np.float32)

    # ---- step 5: train from scratch ----------------------------------------
    idx = np.arange(total)
    np.random.shuffle(idx)
    n_val = max(1, int(round(total * 0.20)))
    val_idx, train_idx = idx[:n_val], idx[n_val:]
    Xtr, Xval = Xs[train_idx], Xs[val_idx]
    n_train = int(Xtr.shape[0])
    print(f"\n=== train ===\nn_train={n_train}  n_val={n_val}  seed={SEED}")

    model = Autoencoder(input_dim=NF)
    opt = torch.optim.Adam(model.parameters(), lr=1e-3)
    loss_fn = nn.MSELoss()
    loader = DataLoader(TensorDataset(torch.tensor(Xtr)), batch_size=256,
                        shuffle=True, drop_last=True)   # drop_last keeps BatchNorm happy
    val_t = torch.tensor(Xval, dtype=torch.float32)

    best_val = float("inf")
    best_state = None
    patience, bad, max_epochs = 10, 0, 150
    for epoch in range(1, max_epochs + 1):
        model.train()
        for (xb,) in loader:
            opt.zero_grad()
            loss = loss_fn(model(xb), xb)
            loss.backward()
            opt.step()
        model.eval()
        with torch.no_grad():
            vloss = float(loss_fn(model(val_t), val_t))
        if vloss < best_val - 1e-6:
            best_val, best_state, bad = vloss, copy.deepcopy(model.state_dict()), 0
        else:
            bad += 1
        if epoch % 10 == 0 or bad == 0:
            print(f"  epoch {epoch:3d}  val_loss={vloss:.6f}  best={best_val:.6f}")
        if bad >= patience:
            print(f"  early stop at epoch {epoch}")
            break

    model.load_state_dict(best_state)
    torch.save(model.state_dict(), AE_LOCAL)
    final_val_loss = best_val
    print(f"saved {AE_LOCAL.name}  final_val_loss={final_val_loss:.6f}")

    # ---- step 6: threshold from benign val error ---------------------------
    val_err = per_row_mse(model, Xval)
    pct = {p: float(np.percentile(val_err, p)) for p in (95, 97.5, 99)}
    dist = {k: float(v) for k, v in {
        "min": val_err.min(), "median": np.median(val_err), "mean": val_err.mean(),
        "p95": pct[95], "p97_5": pct[97.5], "p99": pct[99], "max": val_err.max(),
    }.items()}
    threshold = pct[99]
    print("\n=== val reconstruction-error distribution ===")
    for k, v in dist.items():
        print(f"  {k:7s}= {v:.6f}")
    print(f"chosen threshold (p99) = {threshold:.6f}")

    # ---- step 7: after-FP on ALL stacked benign rows -----------------------
    all_err = per_row_mse(model, Xs)
    after_fp = float(np.mean(all_err > threshold))
    print(f"\n=== AFTER: local AE @ p99 threshold ===\nbenign FP rate = {after_fp*100:.2f}%")
    if after_fp >= 0.10:
        print("WARNING: after-FP is not single digits; stopping for review (no blind tuning).")

    # ---- step 8: before-FP, original AE + original scaler on local rows -----
    before_fp = None
    try:
        with open(ORIG_SCALER, "rb") as fh:
            orig_scaler = pickle.load(fh)
        orig_model = Autoencoder(input_dim=NF)
        orig_model.load_state_dict(torch.load(ORIG_AE, map_location="cpu"))
        Xo = orig_scaler.transform(X).astype(np.float32)
        orig_err = per_row_mse(orig_model, Xo)
        before_fp = float(np.mean(orig_err > config.AE_THRESHOLD))
        print(f"\n=== BEFORE: original AE @ {config.AE_THRESHOLD} on local rows ===")
        print(f"benign FP rate = {before_fp*100:.2f}%")
    except Exception as e:
        print(f"\nBEFORE measurement skipped (could not load original AE/scaler): {e}")

    # ---- step 6 (write): metadata json -------------------------------------
    meta = {
        "chosen_threshold": threshold,
        "percentile_used": 99,
        "candidate_percentiles": {"p95": pct[95], "p97_5": pct[97.5], "p99": pct[99]},
        "val_error_distribution": dist,
        "n_train": n_train, "n_val": n_val, "total_rows": total,
        "per_file_rows": per_file,
        "final_val_loss": final_val_loss,
        "seed": SEED,
        "source_folder": str(DATA_DIR),
        "combined_matrix_sha256": combined_sha,
        "after_benign_fp_rate": after_fp,
        "before_benign_fp_rate_local": before_fp,
        "original_threshold": config.AE_THRESHOLD,
        "framework": f"torch {torch.__version__}",
        "git_commit": git_commit(),
        "date_utc": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
    }
    with open(THRESH_JSON, "w") as fh:
        json.dump(meta, fh, indent=2)
    print(f"\nwrote {THRESH_JSON.name}")

    # ---- step 9: originals unchanged ---------------------------------------
    ae_ok = sha256_file(ORIG_AE) == orig_ae_sha_before
    sc_ok = sha256_file(ORIG_SCALER) == orig_scaler_sha_before
    print("\n=== originals unchanged (sha256) ===")
    print(f"  autoencoder_model.pt: {'UNCHANGED' if ae_ok else 'CHANGED!!'}")
    print(f"  ae_scaler.pkl:        {'UNCHANGED' if sc_ok else 'CHANGED!!'}")
    if not (ae_ok and sc_ok):
        sys.exit("FATAL: a frozen original artifact changed")

    print("\n=== SUMMARY ===")
    print(f"rows total={total} per_file={per_file}  n_train={n_train} n_val={n_val}")
    print(f"final_val_loss={final_val_loss:.6f}  threshold(p99)={threshold:.6f}")
    print(f"after_fp={after_fp*100:.2f}%  before_fp={'n/a' if before_fp is None else f'{before_fp*100:.2f}%'}")
    print(f"artifacts: {AE_LOCAL.name}, {SCALER_LOCAL.name}, {THRESH_JSON.name}")


if __name__ == "__main__":
    main()
