# AI-IDS Inference Service

FastAPI service that loads the five trained models and scores live flow-feature
vectors. Runs all models in parallel for the comparison study, computes SHAP on
alerts, and returns a single-alert JSON payload for the dashboard and Redis
stream.

## Artifacts to drop in `app/artifacts/`

Export these from the Kaggle pipeline. The service boots without them (degraded
mode) and `/health` reports exactly which are missing.

| File | What it is | Required |
|---|---|---|
| `feature_columns.json` | Ordered list of the 56 training features (JSON array of names) | Yes |
| `random_forest.pkl` | RF estimator | one classifier minimum |
| `xgboost.pkl` | XGBoost estimator | " |
| `lightgbm.pkl` | LightGBM estimator | " |
| `cnn_lstm.pt` | CNN-LSTM `state_dict` | optional |
| `autoencoder.pt` | Autoencoder `state_dict` | optional |
| `label_encoder.pkl` | Fitted LabelEncoder (index -> class name) | strongly recommended |
| `ae_scaler.pkl` | Scaler used for the autoencoder | needed if AE loaded |
| `dl_scaler.pkl` | Scaler used for the CNN-LSTM input | see open question |

## Two things to confirm before you trust the output

1. **Library versions must match Kaggle.** The `.pkl` models are unpickled with
   whatever `scikit-learn` / `xgboost` / `lightgbm` versions are installed here.
   If they differ from your Kaggle training environment, loading may fail or, worse,
   load silently and misbehave. Check your Kaggle versions and pin
   `requirements.txt` to match.

2. **Open question: did the CNN-LSTM train on scaled features?** Tree models
   take raw features; neural nets usually take scaled ones. If the CNN-LSTM was
   trained on scaled input and you do not supply `dl_scaler.pkl`, its predictions
   will be wrong while everything still "runs". Confirm which scaler it used in
   training and export it as `dl_scaler.pkl`. If it genuinely used raw features,
   leave the file out.

## Run locally

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```

Then:

```bash
curl localhost:8000/health        # see what loaded
curl localhost:8000/models        # per-model status + active explainers
```

`POST /predict` expects every one of the 56 contract features by name:

```bash
curl -X POST localhost:8000/predict -H 'Content-Type: application/json' \
  -d '{"flow_id": "f1", "features": {"Flow Duration": 12345, ...all 56...}}'
```

## Run in Docker

```bash
docker build -t ids-inference .
docker run -p 8000:8000 -v "$PWD/app/artifacts:/service/app/artifacts" ids-inference
```

## Where the two priorities live

- **Feature fidelity**: `app/features.py`. The contract is loaded from
  `feature_columns.json`, so it cannot drift from training. Every vector is
  validated and ordered against it before any model sees it. This is the gate the
  eBPF sensor must satisfy.
- **SHAP**: `app/shap_engine.py`. Fast TreeExplainer path, computed on alerts
  only. Single-alert format for the dashboard.

## Not built yet (later steps)

- Redis Streams publish (step 4) - hook marked in `app/main.py`.
- Neural SHAP (DeepExplainer) - omitted from the per-alert path on purpose; too
  slow on CPU for live use.