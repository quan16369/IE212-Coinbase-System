import mlflow
import mlflow.pytorch
from typing import Dict, Any
import torch
import pandas as pd
import numpy as np
from datetime import datetime
import sys
import os

# Add project root to path
sys.path.append('/app/Crypto-TS-Model-master/src')

from cnn_lstm_attention_model import CNNLSTMAttentionModel
from data_loader import CryptoDataLoader

class MLflowModelManager:
    """Manages model lifecycle with MLflow"""
    
    def __init__(self, tracking_uri: str, experiment_name: str):
        mlflow.set_tracking_uri(tracking_uri)
        mlflow.set_experiment(experiment_name)
        self.experiment_name = experiment_name
        
    def log_training_run(
        self,
        model: torch.nn.Module,
        metrics: Dict[str, float],
        params: Dict[str, Any],
        artifacts_dir: str
    ) -> str:
        """Log a training run to MLflow"""
        
        with mlflow.start_run(run_name=f"training_{datetime.now().strftime('%Y%m%d_%H%M%S')}") as run:
            # Log parameters
            mlflow.log_params(params)
            
            # Log metrics
            mlflow.log_metrics(metrics)
            
            # Log model
            mlflow.pytorch.log_model(
                model,
                "model",
                registered_model_name="crypto-lstm-model",
                code_paths=["/app/Crypto-TS-Model-master/src"],
                pip_requirements=[
                    "torch>=2.0.0",
                    "numpy>=1.24.0",
                    "pandas>=2.0.0",
                    "scikit-learn>=1.3.0"
                ]
            )
            
            # Log artifacts (configs, plots, etc.)
            if os.path.exists(artifacts_dir):
                mlflow.log_artifacts(artifacts_dir, "artifacts")
            
            # Log system info
            mlflow.log_param("gpu_available", torch.cuda.is_available())
            if torch.cuda.is_available():
                mlflow.log_param("gpu_name", torch.cuda.get_device_name(0))
            
            return run.info.run_id
    
    def register_model(self, run_id: str, stage: str = "Staging") -> str:
        """Register model and transition to specified stage"""
        
        client = mlflow.tracking.MlflowClient()
        
        # Get model version
        model_uri = f"runs:/{run_id}/model"
        model_details = mlflow.register_model(model_uri, "crypto-lstm-model")
        
        # Transition to stage
        client.transition_model_version_stage(
            name="crypto-lstm-model",
            version=model_details.version,
            stage=stage,
            archive_existing_versions=False
        )
        
        return model_details.version
    
    def load_production_model(self) -> torch.nn.Module:
        """Load the current production model"""
        
        model_uri = "models:/crypto-lstm-model/Production"
        model = mlflow.pytorch.load_model(model_uri)
        return model
    
    def compare_models(self, new_run_id: str, baseline_stage: str = "Production") -> Dict[str, Any]:
        """Compare new model with baseline"""
        
        client = mlflow.tracking.MlflowClient()
        
        # Get baseline model metrics
        baseline_versions = client.search_model_versions(
            f"name='crypto-lstm-model' AND current_stage='{baseline_stage}'"
        )
        
        if not baseline_versions:
            return {"comparison": "no_baseline", "should_promote": True}
        
        baseline_run_id = baseline_versions[0].run_id
        baseline_metrics = client.get_run(baseline_run_id).data.metrics
        
        # Get new model metrics
        new_metrics = client.get_run(new_run_id).data.metrics
        
        # Compare key metrics
        comparison = {
            "baseline_mae": baseline_metrics.get("test_mae", float('inf')),
            "new_mae": new_metrics.get("test_mae", float('inf')),
            "baseline_rmse": baseline_metrics.get("test_rmse", float('inf')),
            "new_rmse": new_metrics.get("test_rmse", float('inf')),
            "improvement_mae": (baseline_metrics.get("test_mae", 0) - new_metrics.get("test_mae", 0)) / baseline_metrics.get("test_mae", 1),
            "improvement_rmse": (baseline_metrics.get("test_rmse", 0) - new_metrics.get("test_rmse", 0)) / baseline_metrics.get("test_rmse", 1)
        }
        
        # Promotion criteria: at least 2% improvement in MAE
        comparison["should_promote"] = comparison["improvement_mae"] > 0.02
        
        return comparison
    
    def auto_promote(self, run_id: str, comparison: Dict[str, Any]):
        """Automatically promote model if criteria met"""
        
        if comparison.get("should_promote", False):
            print(f"✅ Model improvement detected: {comparison['improvement_mae']*100:.2f}%")
            print(f"🚀 Promoting model to Production...")
            
            version = self.register_model(run_id, stage="Production")
            
            # Log promotion event
            client = mlflow.tracking.MlflowClient()
            client.set_model_version_tag(
                name="crypto-lstm-model",
                version=version,
                key="promotion_date",
                value=datetime.now().isoformat()
            )
            client.set_model_version_tag(
                name="crypto-lstm-model",
                version=version,
                key="improvement_mae",
                value=str(comparison['improvement_mae'])
            )
            
            print(f"✅ Model version {version} promoted to Production")
            return True
        else:
            print(f"❌ Model did not meet promotion criteria")
            print(f"   Improvement: {comparison.get('improvement_mae', 0)*100:.2f}% (required: 2%)")
            return False


class ContinuousLearningPipeline:
    """Handles continuous learning workflow"""
    
    def __init__(self, config: Dict[str, Any]):
        self.config = config
        self.model_manager = MLflowModelManager(
            tracking_uri=config['mlflow_tracking_uri'],
            experiment_name=config['experiment_name']
        )
    
    def retrain_model(self):
        """Retrain model with latest data"""
        
        print("🔄 Starting model retraining...")
        
        # Load latest data from Cassandra
        data_loader = CryptoDataLoader(
            cassandra_hosts=self.config['cassandra_hosts'],
            keyspace=self.config['cassandra_keyspace']
        )
        train_data, val_data, test_data = data_loader.load_and_split()
        
        # Initialize model
        model = CNNLSTMAttentionModel(
            input_size=self.config['input_size'],
            hidden_size=self.config['hidden_size'],
            num_layers=self.config['num_layers'],
            output_size=self.config['output_size']
        )
        
        # Train model
        trainer = ModelTrainer(model, train_data, val_data, self.config)
        metrics = trainer.train()
        
        # Log to MLflow
        run_id = self.model_manager.log_training_run(
            model=model,
            metrics=metrics,
            params=self.config,
            artifacts_dir=self.config['artifacts_dir']
        )
        
        # Compare with production model
        comparison = self.model_manager.compare_models(run_id)
        
        # Auto-promote if improved
        promoted = self.model_manager.auto_promote(run_id, comparison)
        
        return {
            "run_id": run_id,
            "metrics": metrics,
            "comparison": comparison,
            "promoted": promoted
        }


# Example usage
if __name__ == "__main__":
    config = {
        "mlflow_tracking_uri": "http://mlflow.crypto-mlops.svc.cluster.local:5000",
        "experiment_name": "crypto-continuous-learning",
        "cassandra_hosts": ["cassandra-0.cassandra.crypto-pipeline.svc.cluster.local"],
        "cassandra_keyspace": "crypto_data",
        "input_size": 10,
        "hidden_size": 128,
        "num_layers": 3,
        "output_size": 1,
        "artifacts_dir": "/tmp/artifacts"
    }
    
    pipeline = ContinuousLearningPipeline(config)
    result = pipeline.retrain_model()
    
    print("\n📊 Retraining Results:")
    print(f"   Run ID: {result['run_id']}")
    print(f"   Test MAE: {result['metrics']['test_mae']:.4f}")
    print(f"   Test RMSE: {result['metrics']['test_rmse']:.4f}")
    print(f"   Promoted: {result['promoted']}")
