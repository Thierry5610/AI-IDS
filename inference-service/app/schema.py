"""Request and response schemas. The response is the single-alert contract the
Redis stream and React dashboard will consume downstream.
"""
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field


class PredictRequest(BaseModel):
    features: Dict[str, float] = Field(
        ..., description="Feature name -> value. Must include all 56 contract features."
    )
    flow_id: Optional[str] = None
    timestamp: Optional[str] = None


class ModelVote(BaseModel):
    # Classifier fields
    label: Optional[str] = None
    label_index: Optional[int] = None
    confidence: Optional[float] = None
    # Autoencoder fields
    anomaly_score: Optional[float] = None
    threshold: Optional[float] = None
    is_anomalous: Optional[bool] = None


class FeatureExplanation(BaseModel):
    feature: str
    value: float
    shap_value: float
    direction: str


class Explanation(BaseModel):
    model: str
    method: str
    top_features: List[FeatureExplanation]


class PredictResponse(BaseModel):
    flow_id: Optional[str]
    timestamp: Optional[str]
    prediction: ModelVote
    source_model: str
    is_attack: bool
    model_votes: Dict[str, ModelVote]
    explanation: Optional[Explanation] = None
    agreement: Dict[str, Any]