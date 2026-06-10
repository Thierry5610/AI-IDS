"""Central configuration. Single authoritative source for paths and constants.

Anything that the rest of the service treats as fixed (feature count, class
count, artifact filenames, the autoencoder threshold) lives here so there is
exactly one place to change it.
"""
import os
from pathlib import Path

# Directory holding the artifacts exported from the Kaggle pipeline.
ARTIFACT_DIR = Path(os.getenv("ARTIFACT_DIR", "app/artifacts"))

# Shape contract. Both come straight from the training pipeline.
NUM_FEATURES = 56
NUM_CLASSES = 15

# Label for benign traffic in the trained label encoder. Anything else = attack.
BENIGN_LABEL = "BENIGN"

# Autoencoder anomaly threshold: 95th percentile of benign reconstruction error.
AE_THRESHOLD = 0.0726

# Model artifact filenames expected inside ARTIFACT_DIR.
ARTIFACTS = {
    "random_forest": "random_forest.pkl",
    "xgboost": "xgboost.pkl",
    "lightgbm": "lightgbm.pkl",
    "cnn_lstm": "cnn_lstm.pt",       # state_dict
    "autoencoder": "autoencoder.pt",  # state_dict
}

# Supporting artifacts.
LABEL_ENCODER_FILE = "label_encoder.pkl"
FEATURE_COLUMNS_FILE = "feature_columns.json"   # ordered list of the 56 features
AE_SCALER_FILE = "ae_scaler.pkl"                # scaler used for the autoencoder

# Scaler applied to neural-net inputs (CNN-LSTM). OPEN QUESTION: confirm which
# scaler the CNN-LSTM was trained with. If it was trained on scaled features and
# this is absent, its predictions will be wrong. See README.
DL_SCALER_FILE = "dl_scaler.pkl"

# Model groupings.
TREE_MODELS = ["random_forest", "xgboost", "lightgbm"]
SUPERVISED_MODELS = ["random_forest", "xgboost", "lightgbm", "cnn_lstm"]

# SHAP / explainability.
SHAP_TOP_K = 10
COMPUTE_SHAP_ON_BENIGN = False              # explain alerts only (CPU budget)
SHAP_BACKGROUND_FILE = "shap_background.npy"  # optional, for future neural SHAP