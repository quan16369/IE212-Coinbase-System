.PHONY: ci deploy up down ps logs migrate backup restore jenkins-up jenkins-logs mlops-train mlops-promote-model mlops-build-bento mlops-push-bento mlops-up mlops-logs mlops-test-predict gke-deploy-bento gke-port-forward-bento helm-template-bento

ci:
	bash scripts/ci_check.sh

deploy:
	COMPOSE_PROFILES=ops bash scripts/deploy_compose.sh

up:
	docker compose --env-file .env up -d --build

down:
	docker compose --env-file .env down

ps:
	docker compose --env-file .env ps

logs:
	docker compose --env-file .env logs -f --tail=100

migrate:
	bash scripts/apply_cassandra_migrations.sh

backup:
	bash scripts/backup_cassandra.sh

restore:
	bash scripts/restore_cassandra.sh $(ARCHIVE)

jenkins-up:
	COMPOSE_PROFILES=ci docker compose --env-file .env up -d jenkins

jenkins-logs:
	docker compose --env-file .env logs -f --tail=120 jenkins

mlops-train:
	DATA="$(DATA)" bash scripts/train_ml_model.sh

mlops-promote-model:
	MODEL_VERSION="$(MODEL_VERSION)" MODEL_ALIAS="$(MODEL_ALIAS)" python scripts/promote_mlflow_model.py

mlops-build-bento:
	bash scripts/build_bento.sh

mlops-push-bento:
	PARAM_IMAGE_TAG="$(IMAGE_TAG)"; set -a; . ./.env; set +a; IMAGE_TAG="$${PARAM_IMAGE_TAG:-$${IMAGE_TAG:-dev}}" bash scripts/push_bento_image.sh

mlops-up:
	COMPOSE_PROFILES=mlops docker compose --env-file .env up -d --build mlflow bento-price-predictor

mlops-logs:
	docker compose --env-file .env logs -f --tail=100 mlflow bento-price-predictor

mlops-test-predict:
	DATA="$(DATA)" python scripts/test_bento_predict.py

gke-deploy-bento:
	bash scripts/deploy_bento_gke.sh

gke-port-forward-bento:
	kubectl -n app port-forward svc/bento-price-predictor $${PORT:-3001}:80

helm-template-bento:
	helm template bento-price-predictor charts/bento-price-predictor
