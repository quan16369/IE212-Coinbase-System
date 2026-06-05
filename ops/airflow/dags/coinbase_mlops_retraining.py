from __future__ import annotations

from datetime import datetime, timedelta
import json
import os
import urllib.request

from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.empty import EmptyOperator
from airflow.operators.python import BranchPythonOperator


PROJECT_DIR = os.environ.get("AIRFLOW_PROJ_DIR", "/workspace/Coinbase_Streaming")
FEATURE_PLATFORM_URL = os.environ.get("AIRFLOW_FEATURE_PLATFORM_URL", "http://feature-platform:8090")
TRAINING_CSV = os.environ.get("AIRFLOW_TRAINING_CSV", f"{PROJECT_DIR}/data/BTCUSDT_5m_full.csv")
PROMOTE_MODEL = os.environ.get("AIRFLOW_PROMOTE_MODEL", "false").lower() == "true"


def route_after_drift_check(**context) -> str:
    if os.environ.get("AIRFLOW_FORCE_RETRAIN", "false").lower() == "true":
        return "train_model"

    url = f"{FEATURE_PLATFORM_URL.rstrip('/')}/feedback/retraining-signal/BTCUSDT"
    with urllib.request.urlopen(url, timeout=15) as response:
        payload = json.loads(response.read().decode("utf-8"))
    context["ti"].xcom_push(key="retraining_signal", value=payload)
    return "train_model" if payload.get("should_retrain") else "skip_training"


with DAG(
    dag_id="coinbase_mlops_retraining",
    description="Drift-aware Coinbase price model retraining workflow.",
    start_date=datetime(2026, 1, 1),
    schedule="0 */6 * * *",
    catchup=False,
    max_active_runs=1,
    default_args={
        "owner": "mlops",
        "retries": 1,
        "retry_delay": timedelta(minutes=5),
    },
    tags=["coinbase", "mlops", "drift", "training"],
) as dag:
    check_feature_drift = BashOperator(
        task_id="check_feature_drift",
        bash_command=(
            f"cd {PROJECT_DIR} && "
            f"FEATURE_PLATFORM_URL={FEATURE_PLATFORM_URL} "
            "python scripts/check_feature_drift.py"
        ),
    )

    choose_path = BranchPythonOperator(
        task_id="choose_path",
        python_callable=route_after_drift_check,
    )

    skip_training = EmptyOperator(task_id="skip_training")

    train_model = BashOperator(
        task_id="train_model",
        bash_command=f"cd {PROJECT_DIR} && DATA={TRAINING_CSV} bash scripts/train_ml_model.sh",
    )

    create_version_manifest = BashOperator(
        task_id="create_version_manifest",
        bash_command=f"cd {PROJECT_DIR} && DATA={TRAINING_CSV} python scripts/create_data_version_manifest.py",
    )

    summarize_training = BashOperator(
        task_id="summarize_training",
        bash_command=f"cd {PROJECT_DIR} && python scripts/summarize_mlops_training.py",
    )

    promote_model = BashOperator(
        task_id="promote_model",
        bash_command=(
            f"cd {PROJECT_DIR} && "
            "if [ \"${AIRFLOW_PROMOTE_MODEL:-false}\" = \"true\" ] && [ -n \"${MODEL_VERSION:-}\" ]; then "
            "python scripts/promote_mlflow_model.py; "
            "else echo 'Model promotion skipped. Set AIRFLOW_PROMOTE_MODEL=true and MODEL_VERSION to promote.'; fi"
        ),
    )

    check_feature_drift >> choose_path
    choose_path >> skip_training
    choose_path >> train_model >> create_version_manifest >> summarize_training >> promote_model
