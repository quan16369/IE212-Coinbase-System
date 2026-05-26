#!/usr/bin/env python
from __future__ import annotations

import argparse
import os

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
        help="Registered model version to promote. Can also be passed with MODEL_VERSION=.",
    )
    parser.add_argument(
        "--alias",
        default=os.getenv("MLFLOW_MODEL_ALIAS") or os.getenv("MODEL_ALIAS", "champion"),
        help="Alias to point at the model version.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if not args.version:
        raise SystemExit("Missing model version. Use MODEL_VERSION=<version> make mlops-promote-model.")

    mlflow.set_tracking_uri(args.tracking_uri)
    client = MlflowClient()
    version = client.get_model_version(args.model_name, args.version)
    client.set_registered_model_alias(args.model_name, args.alias, args.version)
    client.set_model_version_tag(args.model_name, args.version, "deployment_alias", args.alias)

    print(f"Promoted {args.model_name} version {version.version} to alias {args.alias}.")
    print(f"Serve it with MLOPS_MODEL_URI=models:/{args.model_name}@{args.alias}.")


if __name__ == "__main__":
    main()
