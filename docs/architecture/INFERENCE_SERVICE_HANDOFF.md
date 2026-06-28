# AI-IDS — Inference Service: Resume-Work Handoff

Purpose: enough context to resume work in a fresh chat (next up: the eBPF
sensor). Engineering notes only, not defense prose.

---

## Status

The inference service is **built, tested, and validated faithful**, and committed
to the repo. `validate_serving.py` on 500 real CICIDS2017 rows:

- Reconstruction failures: 0
- Order-invariance failures: 0
- HTTP-vs-direct mismatches: none (serving reproduces the models exactly)
- Accuracy vs ground truth: RF 1.000, XGBoost 1.000, LightGBM 1.000, CNN-LSTM 0.986
- RESULT: SERVING FAITHFUL

The serving layer is locked. No further work needed on it unless a contract below changes.

---

## Repo + how to run

- Repo root: `/media/thierry/TempStorage/AI-IDS/` (monorepo, private GitHub `ai-ids`).
- Service lives in `inference-service/`. Layout:
  ```
  inference-service/
    app/{config,architectures,features,registry,shap_engine,schema,main}.py
    app/__init__.py
    app/artifacts/        (gitignored; holds the model files, fetched from Kaggle)
    validate_serving.py
    requirements.txt
    Dockerfile
    README.md
  ```
- Boot (venv already exists at `inference-service/.venv`):
  ```bash
  cd inference-service && source .venv/bin/activate
  uvicorn app.main:app --port 8000
  curl localhost:8000/health     # expect status ok, all 5 models loaded
  ```
- Endpoints: `GET /health`, `GET /models`, `POST /predict`.

---

## Environment (must match for artifacts to load)

Kaggle training stack, pinned in `requirements.txt`:
`scikit-learn 1.6.1, xgboost 3.2.0, lightgbm 4.6.0, numpy 2.4.6, torch 2.10.0(+cpu), shap 0.52.0`.
Service layer: `fastapi 0.115.0, uvicorn 0.30.6, pydantic 2.9.2`.
Python: 3.13 local venv / 3.11 on Kaggle (no issues observed; if any per-model
accuracy ever drifts from Kaggle, this gap is a suspect).

---

## Contracts the rest of the system MUST honor

These are the interfaces the sensor and dashboard build against. Do not change
without re-validating.

### 1. The 56-feature contract (the fidelity gate)
- Loaded from `feature_cols_clean.pkl` (pickled python list, 56 names, training order).
- The sensor must emit a JSON dict `{feature_name: value}` containing **all 56
  names, exact spelling, raw values and units** (the same the models trained on).
- **All four supervised models take RAW features — no scaling.** Only the
  autoencoder is scaled (see #4). The CNN-LSTM relies on internal BatchNorm, so
  raw magnitudes matter: the sensor must reproduce units, not just feature identity.
- The 56 features, in exact contract order (index = position in the vector):

  ```
   0  Protocol
   1  Flow Duration
   2  Total Fwd Packets
   3  Total Backward Packets
   4  Fwd Packets Length Total
   5  Bwd Packets Length Total
   6  Fwd Packet Length Max
   7  Fwd Packet Length Min
   8  Fwd Packet Length Mean
   9  Fwd Packet Length Std
  10  Bwd Packet Length Max
  11  Bwd Packet Length Min
  12  Bwd Packet Length Mean
  13  Bwd Packet Length Std
  14  Flow Bytes/s
  15  Flow Packets/s
  16  Flow IAT Mean
  17  Flow IAT Std
  18  Flow IAT Max
  19  Flow IAT Min
  20  Fwd IAT Mean
  21  Fwd IAT Std
  22  Fwd IAT Min
  23  Bwd IAT Total
  24  Bwd IAT Mean
  25  Bwd IAT Std
  26  Bwd IAT Max
  27  Bwd IAT Min
  28  Fwd Packets/s
  29  Bwd Packets/s
  30  Packet Length Min
  31  Packet Length Max
  32  Packet Length Mean
  33  Packet Length Std
  34  Packet Length Variance
  35  FIN Flag Count
  36  SYN Flag Count
  37  RST Flag Count
  38  PSH Flag Count
  39  ACK Flag Count
  40  URG Flag Count
  41  CWE Flag Count
  42  ECE Flag Count
  43  Down/Up Ratio
  44  Init Fwd Win Bytes
  45  Init Bwd Win Bytes
  46  Fwd Act Data Packets
  47  Fwd Seg Size Min
  48  Active Mean
  49  Active Std
  50  Active Max
  51  Active Min
  52  Idle Mean
  53  Idle Std
  54  Idle Max
  55  Idle Min
  ```

  These are CICFlowMeter-style bidirectional flow features (forward = the
  direction of the first packet in the flow). The sensor must reproduce each
  one's exact definition and units, since the models learned raw magnitudes.
  The service validates names + order at runtime, so the dict keys must match
  these strings exactly (spaces, slashes, capitalization).

  These are CICFlowMeter-style bidirectional flow features (forward = source→dest
  of the first packet). The sensor must reproduce each one's exact definition and
  units, since the models learned raw magnitudes.

### 2. Label map (15 classes, from label_encoder.pkl)
0 Benign · 1 Bot · 2 DDoS · 3 DoS GoldenEye · 4 DoS Hulk · 5 DoS Slowhttptest ·
6 DoS slowloris · 7 FTP-Patator · 8 Heartbleed · 9 Infiltration · 10 PortScan ·
11 SSH-Patator · 12 Web Attack - Brute Force · 13 Web Attack - Sql Injection ·
14 Web Attack - XSS.
Benign = "Benign", index 0. `is_attack` = anything not Benign (case-insensitive).

### 3. /predict request + response schema
Request:
```json
{ "features": { "<name>": <float>, ... all 56 ... }, "flow_id": "optional", "timestamp": "optional" }
```
Response (single-alert format the Redis stream + dashboard consume):
```json
{
  "flow_id": "...", "timestamp": "...",
  "prediction": {"label": "...", "label_index": N, "confidence": 0.x},
  "source_model": "xgboost|random_forest|lightgbm|cnn_lstm",
  "is_attack": true,
  "model_votes": {
    "random_forest": {"label","label_index","confidence"},
    "xgboost": {...}, "lightgbm": {...}, "cnn_lstm": {...},
    "autoencoder": {"anomaly_score": x, "threshold": 0.0726, "is_anomalous": bool}
  },
  "explanation": {"model","method":"TreeExplainer","explained_source":bool,
                  "top_features":[{"feature","value","shap_value","direction"}]} | null,
  "agreement": {"consensus":bool, "agreeing":N, "total":N}
}
```
- Source model = highest-confidence supervised classifier.
- SHAP computed on alerts only (not benign); tree TreeExplainer; source-preferred
  with fallback to RF/LightGBM. Neural SHAP intentionally omitted (too slow on CPU).

### 4. Autoencoder (zero-day path)
- Input scaled with `ae_scaler.pkl` (StandardScaler fit on benign training rows only).
- Anomaly threshold 0.0726 (95th percentile of benign reconstruction error). Fixed.
- Runs in parallel as anomaly detector; not a classifier (no label_index).

---

## Artifacts (in app/artifacts/, gitignored, from Kaggle processed/)
rf_model.pkl · xgb_model.json · lgb_model.txt · cnn_lstm_model.pt ·
autoencoder_model.pt · feature_cols_clean.pkl · label_encoder.pkl · ae_scaler.pkl ·
plus X_test_sample.npy + y_test_sample.npy (for validate_serving).

---

## Gotchas already solved (don't re-hit)
- **config.py filenames**: must use the real names above (rf_model.pkl, xgb_model.json,
  lgb_model.txt, *_model.pt) and FEATURE_COLUMNS_FILE=feature_cols_clean.pkl. An older
  config with placeholder names caused every model to report "missing".
- **ae_scaler.pkl exported as 0 bytes from Kaggle.** Regenerate:
  `StandardScaler().fit(X_train_clean[y_train==0])`, dump to ae_scaler.pkl.
- **xgboost 3.x breaks shap < 0.52** (base_score parse error). Pinned shap 0.52.0;
  RF/LightGBM SHAP fallback exists as a safety net.
- **Loaders per format**: RF=pickle, XGB=XGBClassifier().load_model(.json),
  LGB=lgb.Booster(model_file=.txt) (booster, no predict_proba), neural=state_dict.

## Outstanding minor cleanup (non-blocking)
- torch: the default install pulled the ~5GB CUDA build; CPU fallback works but
  wastes disk. To reclaim: uninstall torch + nvidia-* + triton + cuda-*, then
  `pip install torch==2.10.0 --index-url https://download.pytorch.org/whl/cpu`.
- requirements.txt torch line → make it reproducible for clones/Docker:
  `torch==2.10.0+cpu` with `--extra-index-url https://download.pytorch.org/whl/cpu`.
- pydantic warning on `model_votes` (protected namespace): cosmetic. Fix if desired:
  `model_config = ConfigDict(protected_namespaces=())` in PredictResponse.

---

## Locked decisions (don't relitigate)
- Redis Streams over Kafka.
- Develop locally (venv + Docker Compose); Azure for short-lived demo only ($100 cap);
  Oracle conditional/late and ARM-risk (re-test sensor if migrating).
- venv = local dev truth; Docker image = deploy + full-stack integration truth.
- Monorepo, private GitHub, model artifacts gitignored (regenerable from Kaggle).

---

## NEXT: eBPF sensor (`ebpf-sensor/`)

This is the next component and the project's **primary technical risk**: the sensor
must reproduce the exact CICIDS2017/CICFlowMeter-derived feature definitions the
models trained on. Suggested first moves in the sensor chat:

1. Dump the 56 feature names (see #1) and classify each: flow-level vs packet-level
   vs timing/statistical.
2. Map each feature to an eBPF-extractable computation.
3. Build the sensor, then **validate its feature distributions against CICIDS2017
   BEFORE wiring it to /predict** — this isolates sensor fidelity from everything else.
4. Sensor POSTs the 56-feature dict to `POST /predict`.

After the sensor: Redis Streams publish (step 4; hook marked in `app/main.py` predict),
then React dashboard, then k8s manifests + Terraform.

Open this in a new chat with the notebook + inference-service code in project knowledge.
