# Local-baseline Autoencoder

A parallel autoencoder variant retrained from scratch on locally captured benign traffic,
so the AE's idea of "normal" matches this environment instead of CICIDS2017. The frozen
original AE, its scaler, and its 0.0726 threshold are unchanged and still serve as the
default. This variant is a deployment-time improvement, not a replacement of the
dissertation's reported cross-dataset finding.

## What was produced

- `ae_local.pt` : new AE weights (torch state_dict), trained from random init.
- `ae_scaler_local.pkl` : StandardScaler fit on the local benign data.
- `ae_threshold_local.json` : threshold and full training metadata.
- Trainer: `inference-service/scripts/retrain_ae_local.py` (reproducible, seed recorded).
- Launcher: `inference-service/scripts/serve_local.py` (serves this variant, no frozen edits).

## Architecture

Reused exactly by importing `app.architectures.Autoencoder` (input_dim=56): encoder
56-128-64-32 with BatchNorm, ReLU, Dropout(0.2); decoder 32-64-128-56, linear output.
Weights are fresh (no warm start): the new scaler changes the input coordinate system, so
the original manifold no longer applies and warm-starting would also carry a CICIDS-flavored
prior we want to leave behind.

## Data and training

- Source: `traffic-harness/data/X_benign_local*.npy` (the trainer stacks all matches, so
  future captures can be added by dropping more files there).
- Rows: total 10219 (per file: `X_benign_local.npy` = 10219). n_train 8175, n_val 2044
  (80/20 split, seed 1337).
- Loss MSE, optimizer Adam (lr 1e-3, batch 256), early stopping on validation loss.
- Final validation reconstruction loss: 0.077411.

## Threshold

Per-row reconstruction MSE on benign validation rows (same metric the service uses,
mean over the 56 scaled features). Candidate percentiles: p95 = 0.090838,
p97.5 = 0.248293, p99 = 0.379194. **Chosen threshold = p99 = 0.379194.**

## Key result (measured, not estimated)

- After (local AE + local scaler at the p99 threshold), benign false-positive rate on all
  10219 local rows: **0.98%**.
- Before (original AE + original scaler at 0.0726) on the same local rows: **87.75%**.

So retraining on local normal takes the benign false-positive rate from about 88 percent
down to about 1 percent on this network's traffic.

## Switching between original and local at serve time

The original system is the default and is never modified:

```bash
cd inference-service
.venv/bin/python -m uvicorn app.main:app --port 8000      # ORIGINAL (threshold 0.0726)
.venv/bin/python scripts/serve_local.py --port 8000       # LOCAL  (threshold 0.379194)
```

How it works: `app.registry` reads `config.AE_THRESHOLD`, `config.ARTIFACTS["autoencoder"]`
and `config.AE_SCALER_FILE` as module attributes at runtime. `serve_local.py` imports the
frozen `app.config` module and rebinds those three (plus an absolute `ARTIFACT_DIR` so the
four supervised models still load from the original artifacts) before starting the app.
Nothing on disk is swapped and no frozen file is edited. Confirm the active variant by
POSTing to `/predict` and reading `model_votes.autoencoder.threshold` (0.0726 vs 0.379194).

Note: after the external drive remounted, the venv console script `.venv/bin/uvicorn` has a
stale shebang. Use `.venv/bin/python -m uvicorn ...` (the launcher already uses
`python` + `uvicorn.run`, so it is unaffected).

## Integrity

- Original `autoencoder_model.pt` and `ae_scaler.pkl` verified byte-for-byte unchanged
  (sha256 before and after the run).
- The model and scaler here are gitignored (like the originals); the JSON, scripts, and
  this note are committed.
- danger vs warning semantics unchanged: the AE remains the warning lane only.
