"""
Serve the local-baseline AE variant without editing any frozen code.

app.registry reads config.AE_THRESHOLD, config.ARTIFACT_DIR, config.ARTIFACTS and
config.AE_SCALER_FILE as module attributes at RUNTIME. So this launcher just imports the
frozen config module and rebinds those attributes before the app starts, pointing the
autoencoder model, AE scaler, and threshold at the local-baseline artifacts. The four
supervised models keep loading from the original artifact dir (an absolute right-hand path
overrides ARTIFACT_DIR via pathlib).

Nothing on disk is swapped and no frozen file is modified.
  Original system (default):  uvicorn app.main:app
  Local variant:              python scripts/serve_local.py [--host H] [--port P]

No em dashes.
"""
import argparse
import json
import sys
from pathlib import Path

INF = Path(__file__).resolve().parents[1]            # inference-service/
sys.path.insert(0, str(INF))
from app import config                               # frozen module, patched at runtime

LOCAL = INF / "models" / "local_baseline"
AE_LOCAL = LOCAL / "ae_local.pt"
SCALER_LOCAL = LOCAL / "ae_scaler_local.pkl"
THRESH_JSON = LOCAL / "ae_threshold_local.json"

for p in (AE_LOCAL, SCALER_LOCAL, THRESH_JSON):
    if not p.exists():
        sys.exit(f"missing local-baseline artifact: {p}. Run scripts/retrain_ae_local.py first.")

threshold = float(json.loads(THRESH_JSON.read_text())["chosen_threshold"])

# Rebind runtime-read config. ARTIFACT_DIR is made absolute so the supervised models load
# regardless of CWD; the AE model + scaler use absolute local paths that override it.
config.ARTIFACT_DIR = INF / "app" / "artifacts"
config.ARTIFACTS = {**config.ARTIFACTS, "autoencoder": str(AE_LOCAL)}
config.AE_SCALER_FILE = str(SCALER_LOCAL)
config.AE_THRESHOLD = threshold


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8000)
    args = ap.parse_args()
    print("[serve_local] local-baseline AE variant")
    print(f"[serve_local] AE model:  {AE_LOCAL}")
    print(f"[serve_local] AE scaler: {SCALER_LOCAL}")
    print(f"[serve_local] threshold: {config.AE_THRESHOLD}")
    print(f"[serve_local] supervised models from: {config.ARTIFACT_DIR}")
    import uvicorn
    from app.main import app
    uvicorn.run(app, host=args.host, port=args.port)


if __name__ == "__main__":
    main()
