"""SHAP explainability.

Design decisions driven by the laptop CPU budget:
  - Only the tree models (RF, XGBoost, LightGBM) get the fast, exact
    TreeExplainer path. Neural SHAP (DeepExplainer) is intentionally left out of
    the per-alert path because DeepSHAP on a dual-core CPU is seconds per call.
  - Explanations are computed on alerts only (see COMPUTE_SHAP_ON_BENIGN),
    never on every benign flow.

Output is the single-alert JSON format the dashboard consumes: the top features
that drove the prediction, each with its value, signed SHAP contribution, and
direction.
"""
import logging

import numpy as np
import shap

from . import config

log = logging.getLogger("shap")


class ShapEngine:
    def __init__(self, registry, contract):
        self.registry = registry
        self.contract = contract
        self.tree_explainers = {}
        self._build_tree_explainers()

    def _build_tree_explainers(self):
        for name, model in self.registry.tree.items():
            try:
                self.tree_explainers[name] = shap.TreeExplainer(model)
                log.info("TreeExplainer ready: %s", name)
            except Exception as e:
                log.warning("TreeExplainer failed for %s: %s", name, e)

    def explain(self, model_name: str, x: np.ndarray, class_index: int):
        """Top-k SHAP features for the predicted class on one flow.

        Prefers the source model's own explainer, then falls back to any other
        available tree explainer (e.g. when XGBoost's explainer cannot be built
        under the installed library versions). All models share the same label
        encoding, so explaining the same class index with a different tree model
        is valid; the response's `model` field and `explained_source` flag record
        which model actually produced the explanation. Returns None only if no
        tree explainer can explain it (the alert is still emitted, without a
        SHAP panel).
        """
        order = [model_name] + [m for m in self.tree_explainers if m != model_name]
        for name in order:
            explainer = self.tree_explainers.get(name)
            if explainer is None:
                continue
            sv = self._shap_for_class(explainer, x, class_index)
            if sv is None:
                continue
            idx = np.argsort(np.abs(sv))[::-1][: config.SHAP_TOP_K]
            top = [
                {
                    "feature": self.contract.columns[i],
                    "value": float(x[0, i]),
                    "shap_value": float(sv[i]),
                    "direction": "increases_attack" if sv[i] > 0 else "decreases_attack",
                }
                for i in idx
            ]
            return {
                "model": name,
                "method": "TreeExplainer",
                "explained_source": name == model_name,
                "top_features": top,
            }
        return None

    @staticmethod
    def _shap_for_class(explainer, x, class_index):
        """Return the (n_features,) SHAP vector for the predicted class.

        Robust to shap version differences: shap_values may be a list (one array
        per class), a 3D array (samples, features, classes), or a 2D array.
        """
        out = explainer.shap_values(x)

        if isinstance(out, list):
            ci = class_index if class_index < len(out) else 0
            return np.asarray(out[ci])[0]

        out = np.asarray(out)
        if out.ndim == 3:
            ci = class_index if class_index < out.shape[2] else 0
            return out[0, :, ci]
        if out.ndim == 2:
            return out[0]
        return None