from __future__ import annotations

import os
from datetime import timedelta
from pathlib import Path
from typing import Any

import bentoml
import bentoml.sklearn
import joblib
import mlflow
import mlflow.sklearn
import pandas as pd
from mlflow.models import Model

from mlops.features import FeatureConfig, make_latest_features


DEFAULT_MODEL_PATH = "/models/coinbase_ml_model.joblib"
DEFAULT_MODEL_TAG = "coinbase_price_lightgbm:latest"


def _load_model_bundle() -> tuple[Any, dict[str, Any], str]:
    model_uri = os.getenv("MLOPS_MODEL_URI")
    if model_uri:
        mlflow.set_tracking_uri(os.getenv("MLFLOW_TRACKING_URI", "http://mlflow:5000"))
        model = mlflow.sklearn.load_model(model_uri)
        model_metadata = Model.load(model_uri).metadata or {}
        return model, model_metadata, model_uri

    model_path = Path(os.getenv("MLOPS_MODEL_PATH", DEFAULT_MODEL_PATH))
    if model_path.exists():
        bundle = joblib.load(model_path)
        if isinstance(bundle, dict) and "model" in bundle:
            return bundle["model"], bundle.get("metadata", {}), str(model_path)
        return bundle, {}, str(model_path)

    model_tag = os.getenv("BENTOML_MODEL_TAG", DEFAULT_MODEL_TAG)
    try:
        model = bentoml.sklearn.load_model(model_tag)
        bento_model = bentoml.models.get(model_tag)
        metadata = bento_model.custom_objects.get("metadata", {}) if bento_model.custom_objects else {}
        return model, metadata, model_tag
    except Exception as exc:
        raise RuntimeError(
            "No MLOps model is available. Train one with "
            "`make mlops-train DATA=/path/to/ohlcv.csv` or mount MLOPS_MODEL_PATH."
        ) from exc


@bentoml.service(
    resources={"cpu": "1"},
    traffic={"timeout": 30},
)
class CoinbasePriceService:
    def __init__(self) -> None:
        self.model, self.metadata, self.model_source = _load_model_bundle()
        self.feature_columns = self.metadata.get("feature_columns", [])
        if not self.feature_columns:
            raise RuntimeError("Model metadata must include feature_columns")

        self.config = FeatureConfig(
            horizon=int(self.metadata.get("horizon", os.getenv("MLOPS_HORIZON", "4"))),
            freq_minutes=int(self.metadata.get("freq_minutes", os.getenv("MLOPS_FREQ_MINUTES", "60"))),
            lags=tuple(int(item) for item in self.metadata.get("lags", [1, 2, 3, 6, 12, 24])),
            rolling_windows=tuple(int(item) for item in self.metadata.get("rolling_windows", [3, 6, 12, 24])),
        )

    @bentoml.api
    def health(self) -> dict[str, Any]:
        return {
            "status": "ok",
            "model_source": self.model_source,
            "model_name": self.metadata.get("model_name", "unknown"),
        }

    @bentoml.api
    def model_info(self) -> dict[str, Any]:
        return {
            "model_source": self.model_source,
            "metadata": self.metadata,
            "required_model_history_rows": max(max(self.config.lags), max(self.config.rolling_windows)) + 1,
        }

    @bentoml.api
    def predict(self, records: list[dict[str, Any]]) -> dict[str, Any]:
        features, latest_timestamp = make_latest_features(records, self.feature_columns, self.config)
        predicted_return = float(self.model.predict(features)[0])
        current_close = float(features["close"].iloc[0])
        predicted_close = current_close * (1.0 + predicted_return)
        target_time = pd.Timestamp(latest_timestamp) + timedelta(minutes=self.config.freq_minutes * self.config.horizon)

        return {
            "model_name": self.metadata.get("model_name", "coinbase_price_lightgbm"),
            "model_family": self.metadata.get("model_family", "lightgbm_regressor"),
            "horizon": self.config.horizon,
            "freq_minutes": self.config.freq_minutes,
            "latest_timestamp": pd.Timestamp(latest_timestamp).isoformat(),
            "prediction": {
                "target_time": target_time.isoformat(),
                "current_close": current_close,
                "predicted_return": predicted_return,
                "predicted_close": predicted_close,
            },
        }
