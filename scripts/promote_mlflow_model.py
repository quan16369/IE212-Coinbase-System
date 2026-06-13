#!/usr/bin/env python
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

import mlflow
from mlflow import MlflowClient


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Point an MLflow model alias at a model version.")
    parser.add_argument(
        "--tracking-uri",
        default=os.getenv("MLFLOW_TRACKING_URI", "http://localhost:5000"),
        help="MLflow tracking server URI.",
    )
    parser.add_argument(
        "--model-name",
        default=os.getenv("MLFLOW_REGISTERED_MODEL_NAME", "coinbase-price-lightgbm"),
        help="Registered MLflow model name.",
    )
    parser.add_argument(
        "--version",
        default=os.getenv("MODEL_VERSION", ""),
        help="Registered model version to promote. Defaults to the newest version.",
    )
    parser.add_argument(
        "--alias",
        default=os.getenv("MLFLOW_MODEL_ALIAS") or os.getenv("MODEL_ALIAS", "champion"),
        help="Alias to point at the model version.",
    )
    parser.add_argument("--min-return-r2", type=float, default=float(os.getenv("MIN_RETURN_R2", "0")))
    parser.add_argument(
        "--min-direction-accuracy", type=float, default=float(os.getenv("MIN_DIRECTION_ACCURACY", "0.5"))
    )
    parser.add_argument(
        "--min-mae-improvement-vs-naive",
        type=float,
        default=float(os.getenv("MIN_MAE_IMPROVEMENT_VS_NAIVE", "0")),
    )
    parser.add_argument(
        "--min-rmse-improvement-vs-naive",
        type=float,
        default=float(os.getenv("MIN_RMSE_IMPROVEMENT_VS_NAIVE", "0")),
    )
    parser.add_argument(
        "--report",
        default=os.getenv("MODEL_VALIDATION_REPORT", ""),
        help="Optional JSON report path for CI artifacts.",
    )
    return parser.parse_args()


def write_report(path: str, payload: dict) -> None:
    if not path:
        return
    report_path = Path(path)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


def main() -> None:
    args = parse_args()
    mlflow.set_tracking_uri(args.tracking_uri)
    client = MlflowClient()
    if args.version:
        version = client.get_model_version(args.model_name, args.version)
    else:
        versions = client.search_model_versions(f"name='{args.model_name}'")
        if not versions:
            raise SystemExit(f"No registered versions found for {args.model_name}.")
        version = max(versions, key=lambda item: int(item.version))

    metrics = client.get_run(version.run_id).data.metrics
    gates = {
        "return_r2": (metrics.get("return_r2"), args.min_return_r2),
        "direction_accuracy": (metrics.get("direction_accuracy"), args.min_direction_accuracy),
        "mae_improvement_vs_naive": (
            metrics.get("mae_improvement_vs_naive"),
            args.min_mae_improvement_vs_naive,
        ),
        "rmse_improvement_vs_naive": (
            metrics.get("rmse_improvement_vs_naive"),
            args.min_rmse_improvement_vs_naive,
        ),
    }
    failures = {
        name: {"actual": actual, "required": required}
        for name, (actual, required) in gates.items()
        if actual is None or actual < required
    }
    report = {
        "model_name": args.model_name,
        "model_version": version.version,
        "run_id": version.run_id,
        "alias": args.alias,
        "decision": "rejected" if failures else "promoted",
        "gates": {
            name: {"actual": actual, "required": required, "passed": actual is not None and actual >= required}
            for name, (actual, required) in gates.items()
        },
    }
    write_report(args.report, report)
    client.set_model_version_tag(args.model_name, version.version, "validation_gate", "rejected" if failures else "passed")
    client.set_model_version_tag(args.model_name, version.version, "validation_gate_metrics", json.dumps(metrics))
    if failures:
        raise SystemExit(f"Model {args.model_name} version {version.version} rejected: {json.dumps(failures)}")

    client.set_registered_model_alias(args.model_name, args.alias, version.version)
    client.set_model_version_tag(args.model_name, version.version, "deployment_alias", args.alias)

    print(f"Promoted {args.model_name} version {version.version} to alias {args.alias}.")
    print(f"Validation gates passed: {json.dumps({name: actual for name, (actual, _) in gates.items()})}")
    print(f"Serve it with MLOPS_MODEL_URI=models:/{args.model_name}@{args.alias}.")


if __name__ == "__main__":
    main()
