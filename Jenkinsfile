pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  triggers {
    githubPush()
  }

  parameters {
    booleanParam(name: 'BUILD_ALL_IMAGES', defaultValue: false, description: 'Build every Docker Compose image.')
    booleanParam(name: 'RUN_SONARQUBE_SCAN', defaultValue: false, description: 'Run SonarQube code quality scan.')
    string(name: 'SONARQUBE_URL', defaultValue: '', description: 'SonarQube URL. If empty, Jenkins uses SONAR_HOST_URL from .env.')
    string(name: 'SONARQUBE_TOKEN_CREDENTIALS_ID', defaultValue: 'sonarqube-token', description: 'Jenkins Secret text credential ID for SonarQube token.')
    booleanParam(name: 'BUILD_MLOPS_IMAGE', defaultValue: true, description: 'Build the BentoML predictor image.')
    booleanParam(name: 'RUN_TRIVY_IMAGE_SCAN', defaultValue: false, description: 'Run Trivy vulnerability scan on the BentoML image.')
    booleanParam(name: 'TRIVY_FAIL_ON_FINDINGS', defaultValue: false, description: 'Fail the build when Trivy finds HIGH or CRITICAL issues.')
    string(name: 'TRIVY_SEVERITY', defaultValue: 'HIGH,CRITICAL', description: 'Trivy severity filter.')
    booleanParam(name: 'PUSH_BENTO_IMAGE', defaultValue: false, description: 'Push the BentoML image to GCP Artifact Registry.')
    string(name: 'IMAGE_TAG', defaultValue: '', description: 'Optional image tag. If empty, Jenkins uses build-${BUILD_NUMBER}-${GIT_COMMIT_SHORT}.')
    string(name: 'GCP_PROJECT_ID', defaultValue: 'awesome-pilot-494017-u5', description: 'GCP project ID used for Artifact Registry and GKE deploy.')
    string(name: 'GAR_LOCATION', defaultValue: 'asia-southeast1', description: 'Artifact Registry location.')
    string(name: 'GAR_REPOSITORY', defaultValue: 'coinbase-mlops', description: 'Artifact Registry Docker repository.')
    string(name: 'BENTO_IMAGE_NAME', defaultValue: 'coinbase-bento-price-predictor', description: 'Artifact Registry image name for the BentoML predictor.')
    string(name: 'IMAGE_URI', defaultValue: '', description: 'Optional full Bento image URI for GKE deploy. If empty, deploy uses the image pushed by this build.')
    booleanParam(name: 'TRAIN_MLOPS_MODEL', defaultValue: false, description: 'Train the CPU ML model during this build.')
    string(name: 'MLOPS_TRAINING_CSV', defaultValue: '', description: 'Optional override. If empty, Jenkins uses MLOPS_TRAINING_CSV from .env.')
    booleanParam(name: 'PROMOTE_MODEL', defaultValue: false, description: 'Promote an MLflow registered model version to an alias.')
    string(name: 'MODEL_VERSION', defaultValue: '', description: 'Required when PROMOTE_MODEL=true. Example: 4')
    string(name: 'MODEL_ALIAS', defaultValue: 'champion', description: 'MLflow model alias to update.')
    booleanParam(name: 'DEPLOY_BENTO', defaultValue: false, description: 'Restart the BentoML predictor service after build or promotion.')
    booleanParam(name: 'DEPLOY_GKE', defaultValue: false, description: 'Deploy the BentoML predictor to GKE with Helm.')
    booleanParam(name: 'ENABLE_BENTO_INGRESS', defaultValue: false, description: 'Expose the BentoML predictor through the nginx ingress controller.')
    booleanParam(name: 'SMOKE_GKE_PUBLIC', defaultValue: false, description: 'Smoke test the public nginx ingress endpoint after GKE deploy.')
    string(name: 'BENTO_PUBLIC_URL', defaultValue: '', description: 'Optional public Bento URL for smoke tests. If empty, Jenkins uses the nginx LoadBalancer address.')
    string(name: 'GCP_CREDENTIALS_ID', defaultValue: 'gcp-jenkins-sa-key', description: 'Jenkins Secret file credential ID for the GCP service account key.')
    string(name: 'GKE_CLUSTER', defaultValue: '', description: 'GKE cluster name. If empty, Jenkins uses GKE_CLUSTER from .env.')
    string(name: 'GKE_REGION', defaultValue: '', description: 'GKE region. If empty, Jenkins uses GKE_REGION from .env.')
    booleanParam(name: 'DEPLOY_COMPOSE', defaultValue: false, description: 'Deploy the local Compose stack after a successful build.')
  }

  environment {
    COMPOSE_PROJECT_NAME = 'coinbase_streaming'
    ENV_FILE = '.env'
  }

  stages {
    stage('Prepare') {
      steps {
        dir("${env.WORKSPACE}") {
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
        dir("${env.WORKSPACE}") {
          sh 'bash scripts/ci_check.sh'
        }
      }
    }

    stage('SonarQube Scan') {
      when {
        expression { return params.RUN_SONARQUBE_SCAN }
      }
      steps {
        dir("${env.WORKSPACE}") {
          withCredentials([string(credentialsId: params.SONARQUBE_TOKEN_CREDENTIALS_ID, variable: 'SONAR_TOKEN')]) {
            sh '''
              PARAM_SONARQUBE_URL="$SONARQUBE_URL"
              CREDENTIAL_SONAR_TOKEN="$SONAR_TOKEN"

              set -a
              . "./$ENV_FILE"
              set +a
              ENV_SONAR_HOST_URL="${SONAR_HOST_URL:-}"

              SONAR_HOST_URL="$(printf '%s' "$PARAM_SONARQUBE_URL" | xargs)"
              if [ -z "$SONAR_HOST_URL" ]; then
                SONAR_HOST_URL="$(printf '%s' "$ENV_SONAR_HOST_URL" | xargs)"
              fi

              if [ -z "$SONAR_HOST_URL" ]; then
                echo "SONAR_HOST_URL is required for RUN_SONARQUBE_SCAN=true."
                echo "Set it in .env or pass the Jenkins SONARQUBE_URL parameter."
                exit 1
              fi

              SONAR_REQUIRED=true SONAR_HOST_URL="$SONAR_HOST_URL" SONAR_TOKEN="$CREDENTIAL_SONAR_TOKEN" bash scripts/sonarqube_scan.sh
            '''
          }
        }
      }
    }

    stage('Build Images') {
      when {
        expression { return params.BUILD_ALL_IMAGES }
      }
      steps {
        dir("${env.WORKSPACE}") {
          sh 'docker compose --env-file "$ENV_FILE" build'
        }
      }
    }

    stage('Train CPU ML Model') {
      when {
        expression { return params.TRAIN_MLOPS_MODEL }
      }
      steps {
        dir("${env.WORKSPACE}") {
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
        dir("${env.WORKSPACE}") {
          sh 'COMPOSE_PROFILES=mlops docker compose --env-file "$ENV_FILE" build bento-price-predictor'
        }
      }
    }

    stage('Trivy Image Scan') {
      when {
        expression { return params.RUN_TRIVY_IMAGE_SCAN }
      }
      steps {
        dir("${env.WORKSPACE}") {
          sh '''
            if [ "$TRIVY_FAIL_ON_FINDINGS" = "true" ]; then
              TRIVY_EXIT_CODE=1
            else
              TRIVY_EXIT_CODE=0
            fi

            TRIVY_REQUIRED=true \
              TRIVY_SEVERITY="$TRIVY_SEVERITY" \
              TRIVY_EXIT_CODE="$TRIVY_EXIT_CODE" \
              bash scripts/trivy_image_scan.sh
          '''
          archiveArtifacts artifacts: 'artifacts/security/trivy-image-scan.txt', fingerprint: true, allowEmptyArchive: true
        }
      }
    }

    stage('Push BentoML Image') {
      when {
        expression { return params.PUSH_BENTO_IMAGE }
      }
      steps {
        dir("${env.WORKSPACE}") {
          withCredentials([file(credentialsId: params.GCP_CREDENTIALS_ID, variable: 'GOOGLE_APPLICATION_CREDENTIALS')]) {
            sh '''
              PARAM_IMAGE_TAG="$IMAGE_TAG"
              PARAM_GCP_PROJECT_ID="$GCP_PROJECT_ID"
              PARAM_GAR_LOCATION="$GAR_LOCATION"
              PARAM_GAR_REPOSITORY="$GAR_REPOSITORY"
              PARAM_BENTO_IMAGE_NAME="$BENTO_IMAGE_NAME"

              set -a
              . "./$ENV_FILE"
              set +a

              ENV_GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
              ENV_GAR_LOCATION="${GAR_LOCATION:-}"
              ENV_GAR_REPOSITORY="${GAR_REPOSITORY:-}"
              ENV_BENTO_IMAGE_NAME="${BENTO_IMAGE_NAME:-}"

              IMAGE_TAG="$PARAM_IMAGE_TAG"
              if [ -z "$IMAGE_TAG" ]; then
                GIT_COMMIT_SHORT="$(git rev-parse --short HEAD 2>/dev/null || true)"
                if [ -n "$GIT_COMMIT_SHORT" ]; then
                  IMAGE_TAG="build-${BUILD_NUMBER}-${GIT_COMMIT_SHORT}"
                else
                  IMAGE_TAG="build-${BUILD_NUMBER}"
                fi
              fi

              GCP_PROJECT_ID="$PARAM_GCP_PROJECT_ID"
              if [ -z "$GCP_PROJECT_ID" ]; then
                GCP_PROJECT_ID="$ENV_GCP_PROJECT_ID"
              fi

              GAR_LOCATION="$PARAM_GAR_LOCATION"
              if [ -z "$GAR_LOCATION" ]; then
                GAR_LOCATION="$ENV_GAR_LOCATION"
              fi

              GAR_REPOSITORY="$PARAM_GAR_REPOSITORY"
              if [ -z "$GAR_REPOSITORY" ]; then
                GAR_REPOSITORY="$ENV_GAR_REPOSITORY"
              fi

              BENTO_IMAGE_NAME="$PARAM_BENTO_IMAGE_NAME"
              if [ -z "$BENTO_IMAGE_NAME" ]; then
                BENTO_IMAGE_NAME="$ENV_BENTO_IMAGE_NAME"
              fi

              if [ -z "${GCP_PROJECT_ID:-}" ] || [ -z "${GAR_LOCATION:-}" ] || [ -z "${GAR_REPOSITORY:-}" ]; then
                echo "GCP_PROJECT_ID, GAR_LOCATION, and GAR_REPOSITORY are required for PUSH_BENTO_IMAGE=true."
                exit 1
              fi

              gcloud auth activate-service-account --key-file="$GOOGLE_APPLICATION_CREDENTIALS"
              gcloud config set project "$GCP_PROJECT_ID"
              gcloud auth configure-docker "${GAR_LOCATION}-docker.pkg.dev" --quiet

              IMAGE_TAG="$IMAGE_TAG" bash scripts/push_bento_image.sh
            '''
          }
          archiveArtifacts artifacts: 'artifacts/mlops/bento_image_uri.txt', fingerprint: true, allowEmptyArchive: false
        }
      }
    }

    stage('Promote Model') {
      when {
        expression { return params.PROMOTE_MODEL }
      }
      steps {
        dir("${env.WORKSPACE}") {
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
        dir("${env.WORKSPACE}") {
          sh '''
            COMPOSE_PROFILES=mlops docker compose --env-file "$ENV_FILE" up -d --build bento-price-predictor
            docker compose --env-file "$ENV_FILE" ps bento-price-predictor
          '''
        }
      }
    }

    stage('Deploy GKE') {
      when {
        expression { return params.DEPLOY_GKE }
      }
      steps {
        dir("${env.WORKSPACE}") {
          withCredentials([file(credentialsId: params.GCP_CREDENTIALS_ID, variable: 'GOOGLE_APPLICATION_CREDENTIALS')]) {
            sh '''
              PARAM_GKE_CLUSTER="$GKE_CLUSTER"
              PARAM_GKE_REGION="$GKE_REGION"
              PARAM_GCP_PROJECT_ID="$GCP_PROJECT_ID"
              PARAM_GAR_LOCATION="$GAR_LOCATION"
              PARAM_GAR_REPOSITORY="$GAR_REPOSITORY"
              PARAM_ENABLE_BENTO_INGRESS="$ENABLE_BENTO_INGRESS"
              PARAM_BENTO_PUBLIC_URL="$BENTO_PUBLIC_URL"
              PARAM_IMAGE_URI="$IMAGE_URI"

              set -a
              . "./$ENV_FILE"
              set +a

              ENV_GKE_CLUSTER="${GKE_CLUSTER:-}"
              ENV_GKE_REGION="${GKE_REGION:-}"
              ENV_GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
              ENV_GAR_LOCATION="${GAR_LOCATION:-}"
              ENV_GAR_REPOSITORY="${GAR_REPOSITORY:-}"

              GKE_CLUSTER="$PARAM_GKE_CLUSTER"
              if [ -z "$GKE_CLUSTER" ]; then
                GKE_CLUSTER="$ENV_GKE_CLUSTER"
              fi

              GKE_REGION="$PARAM_GKE_REGION"
              if [ -z "$GKE_REGION" ]; then
                GKE_REGION="$ENV_GKE_REGION"
              fi

              GCP_PROJECT_ID="$PARAM_GCP_PROJECT_ID"
              if [ -z "$GCP_PROJECT_ID" ]; then
                GCP_PROJECT_ID="$ENV_GCP_PROJECT_ID"
              fi

              GAR_LOCATION="$PARAM_GAR_LOCATION"
              if [ -z "$GAR_LOCATION" ]; then
                GAR_LOCATION="$ENV_GAR_LOCATION"
              fi

              GAR_REPOSITORY="$PARAM_GAR_REPOSITORY"
              if [ -z "$GAR_REPOSITORY" ]; then
                GAR_REPOSITORY="$ENV_GAR_REPOSITORY"
              fi

              if [ -z "${GCP_PROJECT_ID:-}" ] || [ -z "$GKE_CLUSTER" ] || [ -z "$GKE_REGION" ]; then
                echo "GCP_PROJECT_ID, GKE_CLUSTER, and GKE_REGION are required for DEPLOY_GKE=true."
                echo "Set them in .env or pass the Jenkins parameters."
                exit 1
              fi

              if [ -n "$PARAM_IMAGE_URI" ]; then
                export IMAGE_URI="$PARAM_IMAGE_URI"
              elif [ "$PUSH_BENTO_IMAGE" != "true" ]; then
                echo "DEPLOY_GKE requires PUSH_BENTO_IMAGE=true or an explicit IMAGE_URI."
                echo "This prevents deploying a stale image tag from artifacts/mlops/bento_image_uri.txt."
                exit 1
              fi

              if [ "$PARAM_ENABLE_BENTO_INGRESS" = "true" ]; then
                export BENTO_INGRESS_ENABLED=true
                export BENTO_INGRESS_CLASS="${BENTO_INGRESS_CLASS:-nginx}"
              fi

              if [ -n "$PARAM_BENTO_PUBLIC_URL" ]; then
                export BENTO_PUBLIC_URL="$PARAM_BENTO_PUBLIC_URL"
              fi

              gcloud auth activate-service-account --key-file="$GOOGLE_APPLICATION_CREDENTIALS"
              gcloud config set project "$GCP_PROJECT_ID"
              gcloud container clusters get-credentials "$GKE_CLUSTER" --region="$GKE_REGION"
              bash scripts/deploy_bento_gke.sh
              bash scripts/smoke_bento_gke.sh
              if [ "$SMOKE_GKE_PUBLIC" = "true" ]; then
                bash scripts/smoke_bento_public.sh
              fi
              kubectl -n app get pods
              kubectl -n app get svc
            '''
          }
        }
      }
    }

    stage('Deploy') {
      when {
        expression { return params.DEPLOY_COMPOSE && (env.BRANCH_NAME == 'main' || env.BRANCH_NAME == 'master' || env.BRANCH_NAME == null) }
      }
      steps {
        dir("${env.WORKSPACE}") {
          sh 'bash scripts/deploy_compose.sh'
        }
      }
    }
  }

  post {
    always {
      dir("${env.WORKSPACE}") {
        sh 'docker compose --env-file "$ENV_FILE" ps || true'
      }
    }
  }
}
