"""FastAPI inference service.

Endpoints:
  GET  /health   - service + artifact status (works even in degraded mode)
  GET  /models   - per-model load status
  POST /predict  - validate a flow against the feature contract, run all models,
                   compute SHAP on alerts, return the single-alert response

The service boots even with no artifacts present (degraded mode) so you can see
exactly what it is waiting for. /predict returns 503 until the feature contract
and at least one classifier are loaded.
"""
import logging
from datetime import datetime, timezone

from fastapi import FastAPI, HTTPException

from . import config
from .features import FeatureContract
from .registry import ModelRegistry
from .schema import PredictRequest, PredictResponse
from .shap_engine import ShapEngine

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
log = logging.getLogger("inference")

app = FastAPI(title="AI-IDS Inference Service", version="0.1.0")

state: dict = {"contract": None, "registry": None, "shap": None, "contract_error": None}


def _is_benign(label) -> bool:
    return str(label).strip().upper() == config.BENIGN_LABEL.upper()


@app.on_event("startup")
def startup():
    registry = ModelRegistry()
    registry.load()
    state["registry"] = registry

    try:
        contract = FeatureContract.load()
        state["contract"] = contract
        state["shap"] = ShapEngine(registry, contract)
    except Exception as e:
        state["contract_error"] = str(e)
        log.warning("Degraded mode (no feature contract): %s", e)

    log.info("Startup complete. Model status: %s", registry.status)


@app.get("/health")
def health():
    reg: ModelRegistry = state["registry"]
    return {
        "status": "ok" if state["contract"] else "degraded",
        "feature_contract": "loaded" if state["contract"] else state["contract_error"],
        "models": reg.status if reg else {},
        "label_encoder": reg.label_encoder is not None if reg else False,
        "ae_scaler": reg.ae_scaler is not None if reg else False,
        "dl_scaler": reg.dl_scaler is not None if reg else False,
    }


@app.get("/models")
def models():
    reg: ModelRegistry = state["registry"]
    return {
        "status": reg.status,
        "tree_explainers": list(state["shap"].tree_explainers) if state["shap"] else [],
    }


@app.post("/predict", response_model=PredictResponse)
def predict(req: PredictRequest):
    contract: FeatureContract = state["contract"]
    reg: ModelRegistry = state["registry"]

    if contract is None:
        raise HTTPException(503, f"Feature contract not loaded: {state['contract_error']}")

    try:
        x = contract.validate_and_order(req.features)
    except ValueError as e:
        raise HTTPException(422, str(e))

    votes = reg.predict_all(x)

    classifiers = {k: v for k, v in votes.items() if v.get("confidence") is not None}
    if not classifiers:
        raise HTTPException(503, "No classifier models loaded.")

    # Source = highest-confidence supervised classifier (KB data flow).
    source_model = max(classifiers, key=lambda k: classifiers[k]["confidence"])
    pred = classifiers[source_model]
    is_attack = not _is_benign(pred["label"])

    explanation = None
    if state["shap"] and (is_attack or config.COMPUTE_SHAP_ON_BENIGN):
        explanation = state["shap"].explain(source_model, x, pred["label_index"])

    labels = [v["label"] for v in classifiers.values()]
    agreeing = sum(1 for label in labels if label == pred["label"])
    agreement = {
        "consensus": agreeing == len(labels),
        "agreeing": agreeing,
        "total": len(labels),
    }

    # NOTE (step 4): publish this response to the Redis Stream here, before
    # returning, so the dashboard and Telegram consume it asynchronously.

    return PredictResponse(
        flow_id=req.flow_id,
        timestamp=req.timestamp or datetime.now(timezone.utc).isoformat(),
        prediction=pred,
        source_model=source_model,
        is_attack=is_attack,
        model_votes=votes,
        explanation=explanation,
        agreement=agreement,
    )