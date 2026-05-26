from __future__ import annotations

import argparse
import json
import logging
import os
from pathlib import Path
from typing import Any

import joblib
import mlflow
import mlflow.sklearn
import numpy as np
from lightgbm import LGBMRegressor
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score

from mlops.features import FeatureConfig, load_ohlcv_csv, make_supervised_dataset


LOGGER = logging.getLogger(__name__)
DEFAULT_MODEL_NAME = "coinbase_price_lightgbm"
MODEL_FAMILY = "lightgbm_regressor"
DEFAULT_OUTPUT = "artifacts/mlops/coinbase_ml_model.joblib"


def _smape(y_true: np.ndarray, y_pred: np.ndarray) -> float:
    denominator = np.abs(y_true) + np.abs(y_pred)
    denominator = np.where(denominator == 0, 1.0, denominator)
    return float(np.mean(2.0 * np.abs(y_pred - y_true) / denominator))


def _direction_accuracy(y_true: np.ndarray, y_pred: np.ndarray, previous_close: np.ndarray) -> float:
    actual_direction = np.sign(y_true - previous_close)
    predicted_direction = np.sign(y_pred - previous_close)
    return float(np.mean(actual_direction == predicted_direction))


def _regression_metrics(
    y_true: np.ndarray,
    y_pred: np.ndarray,
    previous_close: np.ndarray,
    prefix: str = "",
) -> dict[str, float]:
    mse = mean_squared_error(y_true, y_pred)
    return {
        f"{prefix}mae": float(mean_absolute_error(y_true, y_pred)),
        f"{prefix}rmse": float(np.sqrt(mse)),
        f"{prefix}r2": float(r2_score(y_true, y_pred)),
        f"{prefix}smape": _smape(y_true, y_pred),
        f"{prefix}direction_accuracy": _direction_accuracy(y_true, y_pred, previous_close),
    }


def _relative_improvement(model_metric: float, baseline_metric: float) -> float:
    if baseline_metric == 0:
        return 0.0
    return float((baseline_metric - model_metric) / baseline_metric)


def _train_validation_split(X, target_return, target_close, validation_ratio: float):
    split_idx = int(len(X) * (1.0 - validation_ratio))
    split_idx = max(1, min(split_idx, len(X) - 1))
    return (
        X.iloc[:split_idx],
        X.iloc[split_idx:],
        target_return.iloc[:split_idx],
        target_return.iloc[split_idx:],
        target_close.iloc[:split_idx],
        target_close.iloc[split_idx:],
    )


def _build_model(random_state: int) -> LGBMRegressor:
    return LGBMRegressor(
        objective="regression",
        n_estimators=100,
        learning_rate=0.1,
        max_depth=6,
        subsample=0.8,
        random_state=random_state,
        n_jobs=-1,
        verbosity=-1,
    )


def _log_to_mlflow(
    model: Any,
    metrics: dict[str, float],
    params: dict[str, Any],
    metadata: dict[str, Any],
    tracking_uri: str,
    experiment_name: str,
    registered_model_name: str,
) -> None:
    try:
        mlflow.set_tracking_uri(tracking_uri)
        mlflow.set_experiment(experiment_name)
        with mlflow.start_run(run_name=params["model_name"]):
            mlflow.log_params(params)
            mlflow.log_metrics(metrics)
            try:
                mlflow.log_text(json.dumps(metadata, indent=2), "model_metadata.json")
                mlflow.sklearn.log_model(
                    model,
                    name="model",
                    registered_model_name=registered_model_name or None,
                    metadata=metadata,
                )
            except Exception as exc:
                mlflow.set_tag("artifact_logging_status", "failed")
                mlflow.set_tag("artifact_logging_error", str(exc)[:500])
                LOGGER.warning("MLflow artifact logging skipped: %s", exc)
    except Exception as exc:
        LOGGER.warning("MLflow logging skipped: %s", exc)


def _save_to_bentoml(model: Any, model_name: str, metadata: dict[str, Any]) -> None:
    try:
        import bentoml
        import bentoml.sklearn

        bentoml.sklearn.save_model(
            model_name,
            model,
            signatures={"predict": {"batchable": True}},
            labels={"project": "coinbase-streaming", "runtime": "cpu"},
            custom_objects={"metadata": metadata},
        )
        LOGGER.info("Saved model to BentoML model store as %s:latest", model_name)
    except Exception as exc:
        LOGGER.warning("BentoML model-store save skipped: %s", exc)


def train(args: argparse.Namespace) -> dict[str, Any]:
    feature_config = FeatureConfig(
        horizon=args.horizon,
        freq_minutes=args.freq_minutes,
        lags=tuple(args.lags),
        rolling_windows=tuple(args.rolling_windows),
    )

    df = load_ohlcv_csv(args.data)
    X, target_return, target_close, feature_columns = make_supervised_dataset(df, feature_config)
    if len(X) < args.min_rows:
        raise ValueError(f"Need at least {args.min_rows} supervised rows, got {len(X)}")

    X_train, X_valid, y_train, y_valid, _, future_close_valid = _train_validation_split(
        X,
        target_return,
        target_close,
        args.validation_ratio,
    )
    model = _build_model(args.random_state)
    model.fit(X_train, y_train)

    predicted_returns = model.predict(X_valid)
    previous_close = X_valid["close"].to_numpy()
    predictions = previous_close * (1.0 + predicted_returns)
    future_close_values = future_close_valid.to_numpy()
    naive_predictions = previous_close
    metrics = {
        **_regression_metrics(future_close_values, predictions, previous_close),
        **_regression_metrics(future_close_values, naive_predictions, previous_close, prefix="naive_"),
        **_regression_metrics(y_valid.to_numpy(), predicted_returns, np.zeros_like(predicted_returns), prefix="return_"),
        "train_rows": float(len(X_train)),
        "validation_rows": float(len(X_valid)),
    }
    metrics.update(
        {
            "mae_improvement_vs_naive": _relative_improvement(metrics["mae"], metrics["naive_mae"]),
            "rmse_improvement_vs_naive": _relative_improvement(metrics["rmse"], metrics["naive_rmse"]),
            "smape_improvement_vs_naive": _relative_improvement(metrics["smape"], metrics["naive_smape"]),
        }
    )

    metadata = {
        "model_name": args.model_name,
        "model_family": MODEL_FAMILY,
        "target": "future_return",
        "prediction_reconstruction": "predicted_close_equals_current_close_times_one_plus_predicted_return",
        "naive_baseline": "future_return_equals_zero",
        "horizon": args.horizon,
        "freq_minutes": args.freq_minutes,
        "lags": list(args.lags),
        "rolling_windows": list(args.rolling_windows),
        "feature_columns": feature_columns,
        "metrics": metrics,
        "training_rows": len(X),
        "source_data": str(Path(args.data).resolve()),
    }

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    joblib.dump({"model": model, "metadata": metadata}, output_path)
    output_path.with_suffix(".metadata.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")

    params = {
        "model_name": args.model_name,
        "model_family": MODEL_FAMILY,
        "horizon": args.horizon,
        "freq_minutes": args.freq_minutes,
        "validation_ratio": args.validation_ratio,
        "random_state": args.random_state,
    }
    _log_to_mlflow(
        model,
        metrics,
        params,
        metadata,
        args.mlflow_tracking_uri,
        args.experiment_name,
        args.mlflow_registered_model_name,
    )
    _save_to_bentoml(model, args.model_name, metadata)

    LOGGER.info("Saved model artifact to %s", output_path)
    LOGGER.info("Validation metrics: %s", json.dumps(metrics, indent=2))
    return metadata


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train the CPU-friendly Coinbase price model.")
    parser.add_argument("--data", default=os.getenv("MLOPS_TRAINING_CSV"), help="OHLCV CSV path")
    parser.add_argument("--output", default=os.getenv("MLOPS_MODEL_OUTPUT", DEFAULT_OUTPUT))
    parser.add_argument("--model-name", default=os.getenv("MLOPS_MODEL_NAME", DEFAULT_MODEL_NAME))
    parser.add_argument("--horizon", type=int, default=int(os.getenv("MLOPS_HORIZON", "4")))
    parser.add_argument("--freq-minutes", type=int, default=int(os.getenv("MLOPS_FREQ_MINUTES", "60")))
    parser.add_argument("--lags", type=int, nargs="+", default=[1, 2, 3, 6, 12, 24])
    parser.add_argument("--rolling-windows", type=int, nargs="+", default=[3, 6, 12, 24])
    parser.add_argument("--validation-ratio", type=float, default=float(os.getenv("MLOPS_VALIDATION_RATIO", "0.2")))
    parser.add_argument("--min-rows", type=int, default=int(os.getenv("MLOPS_MIN_ROWS", "200")))
    parser.add_argument("--random-state", type=int, default=int(os.getenv("MLOPS_RANDOM_STATE", "42")))
    parser.add_argument("--experiment-name", default=os.getenv("MLFLOW_EXPERIMENT_NAME", "coinbase-price-forecasting"))
    parser.add_argument("--mlflow-tracking-uri", default=os.getenv("MLFLOW_TRACKING_URI", "sqlite:///mlflow.db")) # http://localhost:5000
    parser.add_argument(
        "--mlflow-registered-model-name",
        default=os.getenv("MLFLOW_REGISTERED_MODEL_NAME", "coinbase-price-lightgbm"),
    )
    return parser.parse_args()


def main() -> None:
    logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"), format="%(asctime)s %(levelname)s %(name)s - %(message)s")
    args = parse_args()
    if not args.data:
        raise SystemExit("Missing --data or MLOPS_TRAINING_CSV")
    train(args)


if __name__ == "__main__":
    main()
