#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


KEY_METRICS = (
    "mae",
    "rmse",
    "r2",
    "smape",
    "direction_accuracy",
    "naive_mae",
    "naive_rmse",
    "naive_smape",
    "mae_improvement_vs_naive",
    "rmse_improvement_vs_naive",
    "smape_improvement_vs_naive",
    "train_rows",
    "validation_rows",
)


def _fmt(value: Any) -> str:
    if isinstance(value, float):
        return f"{value:.8g}"
    return str(value)


def build_summary(metadata: dict[str, Any]) -> tuple[str, dict[str, Any]]:
    metrics = metadata.get("metrics", {})
    selected_metrics = {key: metrics[key] for key in KEY_METRICS if key in metrics}
    warnings = []

    for key in ("mae_improvement_vs_naive", "rmse_improvement_vs_naive", "smape_improvement_vs_naive"):
        value = metrics.get(key)
        if isinstance(value, (int, float)) and value < 0:
            warnings.append(f"{key} is negative ({value:.6g}); model underperforms the naive baseline.")

    report = {
        "model_name": metadata.get("model_name"),
        "model_family": metadata.get("model_family"),
        "target": metadata.get("target"),
        "horizon": metadata.get("horizon"),
        "freq_minutes": metadata.get("freq_minutes"),
        "training_rows": metadata.get("training_rows"),
        "source_data": metadata.get("source_data"),
        "metrics": selected_metrics,
        "warnings": warnings,
    }

    lines = [
        "# MLOps Training Summary",
        "",
        f"- Model: `{report['model_name']}`",
        f"- Family: `{report['model_family']}`",
        f"- Target: `{report['target']}`",
        f"- Horizon: `{report['horizon']}`",
        f"- Frequency minutes: `{report['freq_minutes']}`",
        f"- Training rows: `{report['training_rows']}`",
        f"- Source data: `{report['source_data']}`",
        "",
        "## Metrics",
        "",
        "| Metric | Value |",
        "| --- | ---: |",
    ]
    lines.extend(f"| `{key}` | {_fmt(value)} |" for key, value in selected_metrics.items())

    if warnings:
        lines.extend(["", "## Warnings", ""])
        lines.extend(f"- {warning}" for warning in warnings)

    return "\n".join(lines) + "\n", report


def main() -> None:
    parser = argparse.ArgumentParser(description="Create Jenkins-friendly MLOps training summaries.")
    parser.add_argument("--metadata", required=True, help="Path to coinbase_ml_model.metadata.json")
    parser.add_argument("--markdown-output", required=True, help="Path to write a markdown summary")
    parser.add_argument("--json-output", required=True, help="Path to write a compact JSON summary")
    args = parser.parse_args()

    metadata_path = Path(args.metadata)
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    markdown, report = build_summary(metadata)

    markdown_output = Path(args.markdown_output)
    json_output = Path(args.json_output)
    markdown_output.parent.mkdir(parents=True, exist_ok=True)
    json_output.parent.mkdir(parents=True, exist_ok=True)
    markdown_output.write_text(markdown, encoding="utf-8")
    json_output.write_text(json.dumps(report, indent=2), encoding="utf-8")

    print(markdown)


if __name__ == "__main__":
    main()
