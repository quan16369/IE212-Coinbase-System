.PHONY: ci deploy up down ps logs migrate backup restore terraform-fmt terraform-init terraform-plan terraform-validate jenkins-up jenkins-logs mlops-train mlops-promote-model mlops-build-bento mlops-push-bento mlops-up mlops-logs mlops-test-predict gke-deploy-bento gke-ingress-bento gke-expose-bento gke-unexpose-bento gke-public-url-bento gke-ingress-url-bento gke-history-bento gke-rollback-bento gke-status-bento gke-logs-bento gke-follow-logs-bento gke-events-bento gke-smoke-bento gke-smoke-in-cluster-bento gke-port-forward-bento helm-template-bento

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

terraform-fmt:
	terraform -chdir=infra/terraform fmt

terraform-init:
	terraform -chdir=infra/terraform init

terraform-validate:
	terraform -chdir=infra/terraform validate

terraform-plan:
	terraform -chdir=infra/terraform plan

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
	PARAM_IMAGE_TAG="$(IMAGE_TAG)"; set -a; . ./.env; set +a; GIT_IMAGE_TAG="$$(git rev-parse --short HEAD 2>/dev/null || echo dev)"; IMAGE_TAG="$${PARAM_IMAGE_TAG:-$${GIT_IMAGE_TAG}}" bash scripts/push_bento_image.sh

mlops-up:
	COMPOSE_PROFILES=mlops docker compose --env-file .env up -d --build mlflow bento-price-predictor

mlops-logs:
	docker compose --env-file .env logs -f --tail=100 mlflow bento-price-predictor

mlops-test-predict:
	DATA="$(DATA)" python scripts/test_bento_predict.py

gke-deploy-bento:
	bash scripts/deploy_bento_gke.sh

gke-ingress-bento:
	BENTO_INGRESS_ENABLED=true bash scripts/deploy_bento_gke.sh

gke-expose-bento:
	BENTO_SERVICE_TYPE=LoadBalancer bash scripts/deploy_bento_gke.sh

gke-unexpose-bento:
	BENTO_SERVICE_TYPE=ClusterIP bash scripts/deploy_bento_gke.sh

gke-public-url-bento:
	kubectl -n app get svc bento-price-predictor -o jsonpath='http://{.status.loadBalancer.ingress[0].ip}{"\n"}'

gke-ingress-url-bento:
	kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='http://{.status.loadBalancer.ingress[0].ip}{"\n"}'

gke-history-bento:
	helm -n app history bento-price-predictor

gke-rollback-bento:
	test -n "$(REVISION)"
	helm -n app rollback bento-price-predictor $(REVISION)
	kubectl -n app rollout status deployment/bento-price-predictor --timeout=180s

gke-status-bento:
	kubectl -n app get deploy,po,svc -l app.kubernetes.io/name=bento-price-predictor

gke-logs-bento:
	kubectl -n app logs deploy/bento-price-predictor --tail=$${TAIL:-120}

gke-follow-logs-bento:
	kubectl -n app logs deploy/bento-price-predictor --tail=$${TAIL:-120} -f

gke-events-bento:
	kubectl -n app get events --sort-by=.lastTimestamp

gke-smoke-bento:
	curl -fsS http://localhost:$${PORT:-3001}/readyz
	curl -fsS -X POST http://localhost:$${PORT:-3001}/health

gke-smoke-in-cluster-bento:
	bash scripts/smoke_bento_gke.sh

gke-port-forward-bento:
	kubectl -n app port-forward svc/bento-price-predictor $${PORT:-3001}:80

helm-template-bento:
	helm template bento-price-predictor charts/bento-price-predictor
