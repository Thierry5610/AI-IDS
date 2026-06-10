"""The feature contract: the inference-side fidelity gate.

The trained models expect exactly 56 features in a specific order, with the same
units used during training. The eBPF sensor must emit features that satisfy this
contract.

The contract is loaded from the same artifact the notebook produced
(feature_cols_clean.pkl, a pickled python list in training order), so the service
and the training pipeline cannot drift apart: the exact ordered list that built
the training matrix is the list enforced at inference.
"""
import pickle

import numpy as np

from . import config


class FeatureContract:
    def __init__(self, columns):
        self.columns = list(columns)
        self.index = {name: i for i, name in enumerate(self.columns)}

    @classmethod
    def load(cls):
        path = config.ARTIFACT_DIR / config.FEATURE_COLUMNS_FILE
        if not path.exists():
            raise FileNotFoundError(
                f"Feature contract missing: {path}. Copy feature_cols_clean.pkl "
                f"from the Kaggle pipeline into the artifacts directory."
            )
        with open(path, "rb") as f:
            columns = pickle.load(f)
        columns = list(columns)
        if len(columns) != config.NUM_FEATURES:
            raise ValueError(
                f"Feature contract has {len(columns)} features, expected "
                f"{config.NUM_FEATURES}. Sensor and models would be misaligned."
            )
        return cls(columns)

    def validate_and_order(self, payload: dict) -> np.ndarray:
        """Validate an incoming feature dict and return a (1, 56) ordered array.

        Extra keys (sensor metadata) are ignored. Missing or non-finite contract
        features are a hard error: this is where a bad sensor vector is caught
        before any model sees it.
        """
        missing = [c for c in self.columns if c not in payload]
        if missing:
            shown = ", ".join(missing[:10]) + (" ..." if len(missing) > 10 else "")
            raise ValueError(f"Missing {len(missing)} contract features: {shown}")

        vector = np.array([float(payload[c]) for c in self.columns], dtype=np.float32)

        if not np.all(np.isfinite(vector)):
            bad = [self.columns[i] for i in np.where(~np.isfinite(vector))[0]]
            raise ValueError(f"Non-finite values for: {', '.join(bad[:10])}")

        return vector.reshape(1, -1)