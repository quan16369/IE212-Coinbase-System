pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  parameters {
    booleanParam(name: 'BUILD_ALL_IMAGES', defaultValue: false, description: 'Build every Docker Compose image.')
    booleanParam(name: 'BUILD_MLOPS_IMAGE', defaultValue: true, description: 'Build the BentoML predictor image.')
    booleanParam(name: 'TRAIN_MLOPS_MODEL', defaultValue: false, description: 'Train the CPU ML model during this build.')
    string(name: 'MLOPS_TRAINING_CSV', defaultValue: '', description: 'Optional override. If empty, Jenkins uses MLOPS_TRAINING_CSV from .env.')
    booleanParam(name: 'PROMOTE_MODEL', defaultValue: false, description: 'Promote an MLflow registered model version to an alias.')
    string(name: 'MODEL_VERSION', defaultValue: '', description: 'Required when PROMOTE_MODEL=true. Example: 4')
    string(name: 'MODEL_ALIAS', defaultValue: 'champion', description: 'MLflow model alias to update.')
    booleanParam(name: 'DEPLOY_BENTO', defaultValue: false, description: 'Restart the BentoML predictor service after build or promotion.')
    booleanParam(name: 'DEPLOY_COMPOSE', defaultValue: false, description: 'Deploy the local Compose stack after a successful build.')
  }

  environment {
    COMPOSE_PROJECT_NAME = 'coinbase_streaming'
    ENV_FILE = '.env'
  }

  stages {
    stage('Prepare') {
      steps {
        dir('/workspace/Coinbase_Streaming') {
          sh '''
            if [ ! -f "$ENV_FILE" ]; then
              cp .env.example "$ENV_FILE"
            fi
          '''
        }
      }
    }

    stage('CI Checks') {
      steps {
        dir('/workspace/Coinbase_Streaming') {
          sh 'bash scripts/ci_check.sh'
        }
      }
    }

    stage('Build Images') {
      when {
        expression { return params.BUILD_ALL_IMAGES }
      }
      steps {
        dir('/workspace/Coinbase_Streaming') {
          sh 'docker compose --env-file "$ENV_FILE" build'
        }
      }
    }

    stage('Train CPU ML Model') {
      when {
        expression { return params.TRAIN_MLOPS_MODEL }
      }
      steps {
        dir('/workspace/Coinbase_Streaming') {
          sh '''
            PARAM_TRAINING_CSV="$MLOPS_TRAINING_CSV"

            set -a
            . "./$ENV_FILE"
            set +a

            TRAINING_CSV="$PARAM_TRAINING_CSV"
            if [ -z "$TRAINING_CSV" ]; then
              TRAINING_CSV="${MLOPS_TRAINING_CSV:-}"
            fi

            if [ -z "$TRAINING_CSV" ]; then
              echo "MLOPS_TRAINING_CSV is required when TRAIN_MLOPS_MODEL=true."
              echo "Set it in .env or pass the Jenkins parameter."
              echo "Example: /workspace/Coinbase_Streaming/data/BTCUSDT_5m_full.csv"
              exit 1
            fi

            python3 -m venv .venv-mlops
            . .venv-mlops/bin/activate
            python -m pip install --upgrade pip
            python -m pip install -r mlops/requirements.txt

            bash scripts/train_ml_model.sh "$TRAINING_CSV"
            python scripts/summarize_mlops_training.py \
              --metadata artifacts/mlops/coinbase_ml_model.metadata.json \
              --markdown-output artifacts/mlops/training_summary.md \
              --json-output artifacts/mlops/training_summary.json
          '''
          archiveArtifacts artifacts: 'artifacts/mlops/coinbase_ml_model.joblib,artifacts/mlops/coinbase_ml_model.metadata.json,artifacts/mlops/training_summary.md,artifacts/mlops/training_summary.json', fingerprint: true, allowEmptyArchive: false
        }
      }
    }

    stage('Build BentoML Image') {
      when {
        expression { return params.BUILD_MLOPS_IMAGE }
      }
      steps {
        dir('/workspace/Coinbase_Streaming') {
          sh 'COMPOSE_PROFILES=mlops docker compose --env-file "$ENV_FILE" build bento-price-predictor'
        }
      }
    }

    stage('Promote Model') {
      when {
        expression { return params.PROMOTE_MODEL }
      }
      steps {
        dir('/workspace/Coinbase_Streaming') {
          sh '''
            if [ -z "$MODEL_VERSION" ]; then
              echo "MODEL_VERSION is required when PROMOTE_MODEL=true."
              echo "Example: 4"
              exit 1
            fi

            set -a
            . "./$ENV_FILE"
            set +a

            python3 -m venv .venv-mlops
            . .venv-mlops/bin/activate
            python -m pip install --upgrade pip
            python -m pip install -r mlops/requirements.txt

            MODEL_VERSION="$MODEL_VERSION" MODEL_ALIAS="$MODEL_ALIAS" python scripts/promote_mlflow_model.py
          '''
        }
      }
    }

    stage('Deploy BentoML') {
      when {
        expression { return params.DEPLOY_BENTO }
      }
      steps {
        dir('/workspace/Coinbase_Streaming') {
          sh '''
            COMPOSE_PROFILES=mlops docker compose --env-file "$ENV_FILE" up -d --build bento-price-predictor
            docker compose --env-file "$ENV_FILE" ps bento-price-predictor
          '''
        }
      }
    }

    stage('Deploy') {
      when {
        expression { return params.DEPLOY_COMPOSE && (env.BRANCH_NAME == 'main' || env.BRANCH_NAME == 'master' || env.BRANCH_NAME == null) }
      }
      steps {
        dir('/workspace/Coinbase_Streaming') {
          sh 'bash scripts/deploy_compose.sh'
        }
      }
    }
  }

  post {
    always {
      dir('/workspace/Coinbase_Streaming') {
        sh 'docker compose --env-file "$ENV_FILE" ps || true'
      }
    }
  }
}
