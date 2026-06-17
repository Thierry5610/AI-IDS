"""Central configuration. Single authoritative source for paths and constants.

Filenames and formats below match exactly what the Kaggle phase-1 notebook
writes to /kaggle/working/processed/. Do not rename without changing the
notebook's save cells too.
"""
import os
from pathlib import Path

ARTIFACT_DIR = Path(os.getenv("ARTIFACT_DIR", "app/artifacts"))

NUM_FEATURES = 56
NUM_CLASSES = 15

# Benign class string in the label encoder (confirmed from le.classes_, index 0).
# Detection is case-insensitive (see main.is_benign).
BENIGN_LABEL = "Benign"

# Autoencoder anomaly threshold: 95th percentile of benign reconstruction error.
AE_THRESHOLD = 0.0726

# Model artifacts, each with the loader its format requires (see registry.py):
#   rf_model.pkl        -> pickle
#   xgb_model.json      -> XGBClassifier().load_model()
#   lgb_model.txt       -> lgb.Booster(model_file=...)   (booster, not wrapper)
#   *_model.pt          -> torch state_dict
ARTIFACTS = {
    "random_forest": "rf_model.pkl",
    "xgboost": "xgb_model.json",
    "lightgbm": "lgb_model.txt",
    "cnn_lstm": "cnn_lstm_model.pt",
    "autoencoder": "autoencoder_model.pt",
}

LABEL_ENCODER_FILE = "label_encoder.pkl"
FEATURE_COLUMNS_FILE = "feature_cols_clean.pkl"   # pickled python list, 56 names
AE_SCALER_FILE = "ae_scaler.pkl"                  # StandardScaler (benign-fit)

# NOT used: the CNN-LSTM trained on raw features (Cell 23 reshapes X_train_clean
# directly, no scaler). Kept optional only so a future retrain on scaled input
# can be supported without code change. Leave this file absent.
DL_SCALER_FILE = "dl_scaler.pkl"

TREE_MODELS = ["random_forest", "xgboost", "lightgbm"]
SUPERVISED_MODELS = ["random_forest", "xgboost", "lightgbm", "cnn_lstm"]

SHAP_TOP_K = 10
COMPUTE_SHAP_ON_BENIGN = False
SHAP_BACKGROUND_FILE = "shap_background.npy"