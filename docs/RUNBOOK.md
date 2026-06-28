# Beehive AI-IDS: Runbook

Boot the full stack end to end. Services start in dependency order: each needs the one
before it already running. No em dashes by convention.

## Resolve the repo path first (the drive remounts with a numeric suffix)

```bash
for p in /media/thierry/TempStorage*/AI-IDS; do
  git -C "$p" rev-parse --is-inside-work-tree >/dev/null 2>&1 && echo "$p"; done
```

Use that as `<repo>`. Invoke scripts as `bash script.sh`, not `./script.sh` (NTFS exec bits).

## Boot order

1. **Redis** (durable alert log; three things below connect to it on startup)
   ```bash
   docker run -d --name ids-redis --restart unless-stopped -p 6379:6379 redis:7-alpine
   docker exec ids-redis redis-cli ping   # -> PONG
   ```

2. **Lab fleet** (the network being monitored: web, ssh, db, dns, attacker)
   ```bash
   cd <repo>/traffic-harness && docker compose up -d --build && docker compose ps
   # wait for db to show healthy
   ```

3. **Inference service** (the brain; loads 5 models, answers /predict). Must precede the sensor.
   ```bash
   cd <repo>/inference-service
   .venv/bin/python scripts/serve_local.py      # local AE, threshold 0.379194
   # or, original CICIDS baseline (threshold 0.0726):
   # .venv/bin/uvicorn app.main:app --port 8000
   ```

4. **Telegram notifier** (optional; tails ids:attacks, pages your phone). Needs Redis.
   ```bash
   cd <repo>/notifier && set -a; source .env; set +a && python3 telegram_notifier.py
   ```

5. **Sensor** (eBPF capture; needs root for bcc + kernel access). Needs 3 and 1 up.
   ```bash
   cd <repo>/traffic-harness && bash capture/find_bridge.sh     # -> br-xxxxxxxx (lab)
   cd <repo>/ebpf-sensor && sudo /usr/bin/python3 sensor/loader.py br-xxxxxxxx
   # for live WiFi instead of the lab: ... loader.py wlp1s0
   # confirm: "redis: -> ids:attacks (attacks) | ids:anomalies (anomalies)", dropped=0
   ```

6. **Bridge** (translates Redis streams to browser SSE). Needs Redis.
   ```bash
   cd <repo>/bridge && .venv/bin/uvicorn main:app --port 8001 --host 127.0.0.1
   ```

7. **Frontend** (React dashboard). Needs the bridge.
   ```bash
   cd <repo>/frontend && npm run dev      # open http://localhost:5173
   ```

## Service reference

| Service           | Port | Python env                  | Root? |
|-------------------|------|-----------------------------|-------|
| Redis             | 6379 | (Docker)                    | no    |
| Inference service | 8000 | `inference-service/.venv`   | no    |
| Bridge (SSE)      | 8001 | `bridge/.venv`              | no    |
| Frontend (Vite)   | 5173 | (node)                      | no    |
| Sensor            |  -   | system `/usr/bin/python3`   | YES   |

Vite proxies `/stream/*` to the bridge (8001) and `/api/*` to the inference service (8000),
so the browser sees no cross-origin issues.

## Health checks

```bash
curl -s http://127.0.0.1:8000/health && echo            # inference: all models loaded
curl -s http://127.0.0.1:8001/health && echo            # bridge
docker exec ids-redis redis-cli XREVRANGE ids:attacks + - COUNT 3     # latest danger alerts
docker exec ids-redis redis-cli XREVRANGE ids:anomalies + - COUNT 3   # latest warning alerts
```

AE calibration sanity check (confirms the threshold is honest on its own training benign;
expect ~1%). Uses stdlib urllib, not requests. 300 rows keeps it under ~15s (SHAP is slow):

```bash
cd <repo>/inference-service && .venv/bin/python - <<'PY'
import numpy as np, json, urllib.request, sys
sys.path.insert(0, "../ebpf-sensor")
from sensor.flow_features import FEATURE_ORDER
X = np.load("../traffic-harness/data/X_benign_local.npy").astype(float)
def predict(v):
    body = json.dumps({"features": dict(zip(FEATURE_ORDER, v.tolist()))}).encode()
    req = urllib.request.Request("http://127.0.0.1:8000/predict", body,
                                 {"content-type": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=10))
fp = sum(predict(v)["model_votes"]["autoencoder"]["is_anomalous"] for v in X[:300])
print(f"AE FP on its own training benign: {100*fp/300:.1f}%  (expect ~1%)")
PY
```

Last measured: 0.8%. Serving path correct.

## Getting data on screen

The dashboard only shows what is already in Redis, so an empty stream renders a blank
(correct, not broken). Two ways to populate:

- **Live**: run the sensor (step 5) and drive traffic. Note: supervised models stay silent
  on benign traffic by design (the transfer-failure finding), so ids:attacks rarely fires
  without a real attack. Expect benign anomalies on ids:anomalies.
- **Synthetic** (demos/screenshots): `XADD ids:attacks * data '<json>'` with current
  timestamps and full model_votes (the ensemble gauge reads the latest alert's votes).

## Teardown

```bash
# Ctrl-C the foreground services (inference, notifier, bridge, frontend, sensor)
cd <repo>/traffic-harness && docker compose down -v       # remove the fleet
# leave ids-redis running (restart-persistent), or: docker rm -f ids-redis
```

## Known gotchas (this environment)

- **No passwordless sudo** in some shells. Only the sensor needs root.
- **Drive remounts** (`TempStorage` -> `TempStorage1` -> `TempStorage2`). Always resolve
  `<repo>` first.
- **Wedged containers**: a snap-docker quirk can leave `attacker-eval-*` containers the
  daemon cannot kill (they hold IPs, otherwise harmless). Clear with
  `sudo snap restart docker`.
- **/predict is slow** (~19 req/s) because SHAP runs per request. Batch scoring of full
  matrices takes minutes; sample if you only need a rate.
- **`dl_scaler: false`** in /health: the CNN-LSTM has no scaler loaded in this serving
  path. Investigate before trusting the neural model's votes; it may be a reason it never
  fires, separate from domain shift.
- **Benign control FP**: the 36% figure came from a short, attacker-contaminated control
  window, not a bug (AE calibration verified at 0.8%). Re-capture clean benign, no attack
  tooling running, before quoting any benign false-positive number.
