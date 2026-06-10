"""Model registry: loads the five trained models in their real save formats and
runs them in parallel.

Loading is tolerant: a missing or unloadable artifact is reported via .status and
simply absent from predictions, never a silent wrong answer. The three tree
models are stored as SHAP-compatible objects so the explainer can use them
directly:
    random_forest -> sklearn RandomForestClassifier (pickle)
    xgboost       -> XGBClassifier (load_model on the .json)
    lightgbm      -> lgb.Booster   (model_file on the .txt)
"""
import logging
import pickle

import numpy as np

from . import config

log = logging.getLogger("registry")


def _load_pickle(path):
    with open(path, "rb") as f:
        return pickle.load(f)


def _proba(model, x):
    """Class-probability vector for one sample, format-agnostic.

    RF / XGBClassifier expose predict_proba; a LightGBM Booster returns the
    probability matrix straight from predict().
    """
    if hasattr(model, "predict_proba"):
        return np.asarray(model.predict_proba(x))[0]
    return np.asarray(model.predict(x))[0]


class ModelRegistry:
    def __init__(self):
        self.tree = {}            # name -> SHAP-compatible, proba-capable model
        self.cnn_lstm = None
        self.autoencoder = None
        self.label_encoder = None
        self.ae_scaler = None
        self.dl_scaler = None
        self.status = {}

    def load(self):
        d = config.ARTIFACT_DIR
        self._load_rf(d / config.ARTIFACTS["random_forest"])
        self._load_xgb(d / config.ARTIFACTS["xgboost"])
        self._load_lgb(d / config.ARTIFACTS["lightgbm"])
        self._load_cnn_lstm(d / config.ARTIFACTS["cnn_lstm"])
        self._load_autoencoder(d / config.ARTIFACTS["autoencoder"])
        self.label_encoder = self._opt(d / config.LABEL_ENCODER_FILE, "label_encoder")
        self.ae_scaler = self._opt(d / config.AE_SCALER_FILE, "ae_scaler")
        self.dl_scaler = self._opt(d / config.DL_SCALER_FILE, "dl_scaler")

    # ---- loaders (one per real save format) ------------------------------
    def _load_rf(self, path):
        if not path.exists():
            self.status["random_forest"] = "missing"; return
        try:
            self.tree["random_forest"] = _load_pickle(path)
            self.status["random_forest"] = "loaded"
        except Exception as e:
            self.status["random_forest"] = f"error: {e}"; log.warning("rf: %s", e)

    def _load_xgb(self, path):
        if not path.exists():
            self.status["xgboost"] = "missing"; return
        try:
            import xgboost as xgb
            m = xgb.XGBClassifier()
            m.load_model(str(path))
            self.tree["xgboost"] = m
            self.status["xgboost"] = "loaded"
        except Exception as e:
            self.status["xgboost"] = f"error: {e}"; log.warning("xgb: %s", e)

    def _load_lgb(self, path):
        if not path.exists():
            self.status["lightgbm"] = "missing"; return
        try:
            import lightgbm as lgb
            self.tree["lightgbm"] = lgb.Booster(model_file=str(path))
            self.status["lightgbm"] = "loaded"
        except Exception as e:
            self.status["lightgbm"] = f"error: {e}"; log.warning("lgb: %s", e)

    def _load_cnn_lstm(self, path):
        if not path.exists():
            self.status["cnn_lstm"] = "missing"; return
        try:
            import torch
            from .architectures import CNNLSTM
            model = CNNLSTM(num_classes=config.NUM_CLASSES)
            model.load_state_dict(torch.load(path, map_location="cpu"))
            model.eval()
            self.cnn_lstm = model
            self.status["cnn_lstm"] = "loaded"
        except Exception as e:
            self.status["cnn_lstm"] = f"error: {e}"; log.warning("cnn_lstm: %s", e)

    def _load_autoencoder(self, path):
        if not path.exists():
            self.status["autoencoder"] = "missing"; return
        try:
            import torch
            from .architectures import Autoencoder
            model = Autoencoder(input_dim=config.NUM_FEATURES)
            model.load_state_dict(torch.load(path, map_location="cpu"))
            model.eval()
            self.autoencoder = model
            self.status["autoencoder"] = "loaded"
        except Exception as e:
            self.status["autoencoder"] = f"error: {e}"; log.warning("autoencoder: %s", e)

    def _opt(self, path, label):
        if not path.exists():
            log.info("Optional artifact absent: %s", label); return None
        try:
            return _load_pickle(path)
        except Exception as e:
            log.warning("Failed to load %s: %s", label, e); return None

    # ---- inference -------------------------------------------------------
    def predict_all(self, x: np.ndarray) -> dict:
        """x: ordered (1, 56) float32 array (raw features, as in training)."""
        results = {}
        for name, model in self.tree.items():
            proba = _proba(model, x)
            idx = int(np.argmax(proba))
            results[name] = {
                "label": self._decode(idx),
                "label_index": idx,
                "confidence": float(proba[idx]),
            }
        if self.cnn_lstm is not None:
            results["cnn_lstm"] = self._predict_cnn_lstm(x)
        if self.autoencoder is not None:
            results["autoencoder"] = self._predict_autoencoder(x)
        return results

    def _predict_cnn_lstm(self, x):
        import torch
        import torch.nn.functional as F
        # Raw features, matching training. dl_scaler stays None unless a future
        # retrain on scaled input provides one.
        xi = self.dl_scaler.transform(x) if self.dl_scaler is not None else x
        t = torch.tensor(np.asarray(xi), dtype=torch.float32).reshape(1, config.NUM_FEATURES, 1)
        with torch.no_grad():
            proba = F.softmax(self.cnn_lstm(t), dim=1)[0].numpy()
        idx = int(np.argmax(proba))
        return {"label": self._decode(idx), "label_index": idx, "confidence": float(proba[idx])}

    def _predict_autoencoder(self, x):
        import torch
        xi = self.ae_scaler.transform(x) if self.ae_scaler is not None else x
        xi = np.asarray(xi, dtype=np.float32)
        t = torch.tensor(xi, dtype=torch.float32)
        with torch.no_grad():
            recon = self.autoencoder(t).numpy()
        mse = float(np.mean((xi - recon) ** 2))
        return {
            "anomaly_score": mse,
            "threshold": config.AE_THRESHOLD,
            "is_anomalous": mse > config.AE_THRESHOLD,
        }

    def _decode(self, idx: int) -> str:
        if self.label_encoder is not None:
            try:
                return str(self.label_encoder.inverse_transform([idx])[0])
            except Exception:
                return str(idx)
        return str(idx)