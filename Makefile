.PHONY: ci security-check trivy-image-scan image-sbom sonar-up sonar-logs sonar-scan deploy up down ps logs migrate backup restore terraform-fmt terraform-init terraform-plan terraform-validate terraform-destroy jenkins-up jenkins-logs mlops-train mlops-promote-model mlops-build-bento mlops-push-bento mlops-up mlops-logs mlops-test-predict data-validation-build data-validation-push data-validation-deploy data-validation-delete data-validation-status data-validation-logs data-validation-events data-validation-port-forward data-validation-smoke data-validation-run-telemetry-producer feature-platform-build feature-platform-push feature-platform-deploy feature-platform-delete feature-platform-status feature-platform-logs feature-platform-events feature-platform-port-forward feature-platform-smoke alert-rule-engine-build alert-rule-engine-push alert-rule-engine-deploy alert-rule-engine-delete alert-rule-engine-status alert-rule-engine-logs alert-rule-engine-events alert-rule-engine-port-forward alert-rule-engine-smoke alert-index-build alert-index-push alert-index-deploy alert-index-delete alert-index-status alert-index-logs alert-index-events alert-index-port-forward alert-index-smoke inference-orchestrator-build inference-orchestrator-push inference-orchestrator-deploy inference-orchestrator-ingress inference-orchestrator-delete inference-orchestrator-status inference-orchestrator-ingress-status inference-orchestrator-logs inference-orchestrator-events inference-orchestrator-port-forward inference-orchestrator-smoke inference-orchestrator-public-url inference-orchestrator-smoke-public gke-install-ingress-nginx gke-uninstall-ingress-nginx gke-deploy-bento gke-delete-bento gke-ingress-bento gke-expose-bento gke-unexpose-bento gke-public-url-bento gke-ingress-url-bento gke-history-bento gke-rollback-bento gke-status-bento gke-describe-bento gke-top-bento gke-ingress-status-bento gke-observe-bento gke-logs-bento gke-follow-logs-bento gke-cloud-logs-bento gke-events-bento gke-smoke-bento gke-smoke-in-cluster-bento gke-smoke-public-bento gke-run-synthetic-probe-bento gke-port-forward-bento gke-install-monitoring gke-uninstall-monitoring gke-monitoring-status gke-monitoring-grafana gke-monitoring-prometheus gke-monitoring-alertmanager gke-install-logging gke-uninstall-logging gke-logging-status gke-logging-loki gke-install-tracing gke-uninstall-tracing gke-tracing-status gke-tracing-tempo helm-template-bento helm-template-data-validation helm-template-feature-platform helm-template-alert-rule-engine helm-template-alert-index helm-template-inference-orchestrator

ci:
	bash scripts/ci_check.sh

security-check:
	CHECKOV_REQUIRED=true bash scripts/security_check.sh

trivy-image-scan:
	TRIVY_REQUIRED=true bash scripts/trivy_image_scan.sh

image-sbom:
	SBOM_REQUIRED=true bash scripts/generate_image_sbom.sh

sonar-up:
	COMPOSE_PROFILES=ci docker compose --env-file .env up -d sonarqube

sonar-logs:
	docker compose --env-file .env logs -f --tail=120 sonarqube

sonar-scan:
	SONAR_REQUIRED=true bash scripts/sonarqube_scan.sh

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

terraform-destroy:
	terraform -chdir=infra/terraform destroy

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

data-validation-build:
	docker build -f services/data_validation/Dockerfile -t coinbase-data-validation:latest .

data-validation-push:
	PARAM_IMAGE_TAG="$(IMAGE_TAG)"; set -a; . ./.env; set +a; GIT_IMAGE_TAG="$$(git rev-parse --short HEAD 2>/dev/null || echo dev)"; IMAGE_TAG="$${PARAM_IMAGE_TAG:-$${GIT_IMAGE_TAG}}" bash scripts/push_data_validation_image.sh

data-validation-deploy:
	bash scripts/deploy_data_validation_gke.sh

data-validation-delete:
	helm -n data-ingestion uninstall data-validation

data-validation-status:
	kubectl -n data-ingestion get deploy,po,svc,hpa,pdb,cronjob,job -l app.kubernetes.io/name=data-validation -o wide

data-validation-logs:
	kubectl -n data-ingestion logs deploy/data-validation --tail=$${TAIL:-120}

data-validation-events:
	kubectl -n data-ingestion get events --sort-by=.lastTimestamp

data-validation-port-forward:
	kubectl -n data-ingestion port-forward svc/data-validation $${PORT:-8089}:80

data-validation-smoke:
	python scripts/smoke_data_validation.py

data-validation-run-telemetry-producer:
	kubectl -n data-ingestion create job --from=cronjob/data-validation-telemetry-producer data-validation-telemetry-producer-manual-$$(date +%s)

feature-platform-build:
	docker build -f services/feature_platform/Dockerfile -t coinbase-feature-platform:latest .

feature-platform-push:
	PARAM_IMAGE_TAG="$(IMAGE_TAG)"; set -a; . ./.env; set +a; GIT_IMAGE_TAG="$$(git rev-parse --short HEAD 2>/dev/null || echo dev)"; IMAGE_TAG="$${PARAM_IMAGE_TAG:-$${GIT_IMAGE_TAG}}" bash scripts/push_feature_platform_image.sh

feature-platform-deploy:
	bash scripts/deploy_feature_platform_gke.sh

feature-platform-delete:
	helm -n feature-platform uninstall feature-platform

feature-platform-status:
	kubectl -n feature-platform get deploy,po,svc,hpa,pdb -l app.kubernetes.io/name=feature-platform -o wide

feature-platform-logs:
	kubectl -n feature-platform logs deploy/feature-platform --tail=$${TAIL:-120}

feature-platform-events:
	kubectl -n feature-platform get events --sort-by=.lastTimestamp

feature-platform-port-forward:
	kubectl -n feature-platform port-forward svc/feature-platform $${PORT:-8090}:80

feature-platform-smoke:
	python scripts/smoke_feature_platform.py

alert-rule-engine-build:
	docker build -f services/alert_rule_engine/Dockerfile -t coinbase-alert-rule-engine:latest .

alert-rule-engine-push:
	PARAM_IMAGE_TAG="$(IMAGE_TAG)"; set -a; . ./.env; set +a; GIT_IMAGE_TAG="$$(git rev-parse --short HEAD 2>/dev/null || echo dev)"; IMAGE_TAG="$${PARAM_IMAGE_TAG:-$${GIT_IMAGE_TAG}}" bash scripts/push_alert_rule_engine_image.sh

alert-rule-engine-deploy:
	bash scripts/deploy_alert_rule_engine_gke.sh

alert-rule-engine-delete:
	helm -n alert-routing uninstall alert-rule-engine

alert-rule-engine-status:
	kubectl -n alert-routing get deploy,po,svc,hpa,pdb -l app.kubernetes.io/name=alert-rule-engine -o wide

alert-rule-engine-logs:
	kubectl -n alert-routing logs deploy/alert-rule-engine --tail=$${TAIL:-120}

alert-rule-engine-events:
	kubectl -n alert-routing get events --sort-by=.lastTimestamp

alert-rule-engine-port-forward:
	kubectl -n alert-routing port-forward svc/alert-rule-engine $${PORT:-8092}:80

alert-rule-engine-smoke:
	python scripts/smoke_alert_rule_engine.py

alert-index-build:
	docker build -f services/alert_index/Dockerfile -t coinbase-alert-index:latest .

alert-index-push:
	PARAM_IMAGE_TAG="$(IMAGE_TAG)"; set -a; . ./.env; set +a; GIT_IMAGE_TAG="$$(git rev-parse --short HEAD 2>/dev/null || echo dev)"; IMAGE_TAG="$${PARAM_IMAGE_TAG:-$${GIT_IMAGE_TAG}}" bash scripts/push_alert_index_image.sh

alert-index-deploy:
	bash scripts/deploy_alert_index_gke.sh

alert-index-delete:
	helm -n alert-routing uninstall alert-index

alert-index-status:
	kubectl -n alert-routing get deploy,po,svc,hpa,pdb -l app.kubernetes.io/name=alert-index -o wide

alert-index-logs:
	kubectl -n alert-routing logs deploy/alert-index --tail=$${TAIL:-120}

alert-index-events:
	kubectl -n alert-routing get events --sort-by=.lastTimestamp

alert-index-port-forward:
	kubectl -n alert-routing port-forward svc/alert-index $${PORT:-8093}:80

alert-index-smoke:
	python scripts/smoke_alert_index.py

inference-orchestrator-build:
	docker build -f services/inference_orchestrator/Dockerfile -t coinbase-inference-orchestrator:latest .

inference-orchestrator-push:
	PARAM_IMAGE_TAG="$(IMAGE_TAG)"; set -a; . ./.env; set +a; GIT_IMAGE_TAG="$$(git rev-parse --short HEAD 2>/dev/null || echo dev)"; IMAGE_TAG="$${PARAM_IMAGE_TAG:-$${GIT_IMAGE_TAG}}" bash scripts/push_inference_orchestrator_image.sh

inference-orchestrator-deploy:
	bash scripts/deploy_inference_orchestrator_gke.sh

inference-orchestrator-ingress:
	INFERENCE_ORCHESTRATOR_INGRESS_ENABLED=true bash scripts/deploy_inference_orchestrator_gke.sh

inference-orchestrator-delete:
	helm -n model-serving uninstall inference-orchestrator

inference-orchestrator-status:
	kubectl -n model-serving get deploy,po,svc,hpa,pdb -l app.kubernetes.io/name=inference-orchestrator -o wide

inference-orchestrator-ingress-status:
	kubectl -n model-serving get ingress inference-orchestrator -o wide

inference-orchestrator-logs:
	kubectl -n model-serving logs deploy/inference-orchestrator --tail=$${TAIL:-120}

inference-orchestrator-events:
	kubectl -n model-serving get events --sort-by=.lastTimestamp

inference-orchestrator-port-forward:
	kubectl -n model-serving port-forward svc/inference-orchestrator $${PORT:-8091}:80

inference-orchestrator-smoke:
	python scripts/smoke_inference_orchestrator.py

inference-orchestrator-public-url:
	kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='http://{.status.loadBalancer.ingress[0].ip}{"\n"}'

inference-orchestrator-smoke-public:
	INFERENCE_ORCHESTRATOR_URL="$$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='http://{.status.loadBalancer.ingress[0].ip}')" python scripts/smoke_inference_orchestrator.py

gke-install-ingress-nginx:
	bash scripts/install_ingress_nginx.sh

gke-uninstall-ingress-nginx:
	helm -n ingress-nginx uninstall ingress-nginx

gke-deploy-bento:
	bash scripts/deploy_bento_gke.sh

gke-delete-bento:
	helm -n app uninstall bento-price-predictor

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
	kubectl -n app get deploy,po,svc,ingress,hpa,pdb,cronjob,job -l app.kubernetes.io/name=bento-price-predictor -o wide

gke-describe-bento:
	kubectl -n app describe deploy/bento-price-predictor
	kubectl -n app describe pod -l app.kubernetes.io/name=bento-price-predictor

gke-top-bento:
	kubectl -n app top pod -l app.kubernetes.io/name=bento-price-predictor

gke-ingress-status-bento:
	kubectl -n ingress-nginx get deploy,po,svc -l app.kubernetes.io/name=ingress-nginx -o wide
	kubectl -n app get ingress bento-price-predictor -o wide

gke-observe-bento:
	bash scripts/observe_bento_gke.sh

gke-logs-bento:
	kubectl -n app logs deploy/bento-price-predictor --tail=$${TAIL:-120}

gke-follow-logs-bento:
	kubectl -n app logs deploy/bento-price-predictor --tail=$${TAIL:-120} -f

gke-cloud-logs-bento:
	bash scripts/gke_cloud_logs_bento.sh

gke-events-bento:
	kubectl -n app get events --sort-by=.lastTimestamp

gke-smoke-bento:
	curl -fsS http://localhost:$${PORT:-3001}/readyz
	curl -fsS -X POST http://localhost:$${PORT:-3001}/health

gke-smoke-in-cluster-bento:
	bash scripts/smoke_bento_gke.sh

gke-smoke-public-bento:
	bash scripts/smoke_bento_public.sh

gke-run-synthetic-probe-bento:
	kubectl -n app create job --from=cronjob/bento-price-predictor-synthetic-probe bento-price-predictor-synthetic-probe-manual-$$(date +%s)

gke-port-forward-bento:
	kubectl -n app port-forward svc/bento-price-predictor $${PORT:-3001}:80

gke-install-monitoring:
	bash scripts/install_gke_monitoring.sh

gke-uninstall-monitoring:
	helm -n monitoring uninstall kube-prometheus-stack

gke-monitoring-status:
	kubectl -n monitoring get pods,svc

gke-monitoring-grafana:
	kubectl -n monitoring wait --for=condition=ready pod -l app.kubernetes.io/name=grafana --timeout=180s
	kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana $${PORT:-3000}:80

gke-monitoring-prometheus:
	kubectl -n monitoring wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus --timeout=180s
	kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus $${PORT:-9090}:9090

gke-monitoring-alertmanager:
	kubectl -n monitoring wait --for=condition=ready pod -l alertmanager=kube-prometheus-stack-alertmanager --timeout=180s
	kubectl -n monitoring port-forward svc/kube-prometheus-stack-alertmanager $${PORT:-9093}:9093

gke-install-logging:
	bash scripts/install_gke_logging.sh

gke-uninstall-logging:
	helm -n logging uninstall loki

gke-logging-status:
	kubectl -n logging get pods,svc

gke-logging-loki:
	kubectl -n logging wait --for=condition=ready pod -l app.kubernetes.io/name=loki --timeout=180s
	kubectl -n logging port-forward svc/loki $${PORT:-3100}:3100

gke-install-tracing:
	bash scripts/install_gke_tracing.sh

gke-uninstall-tracing:
	helm -n tracing uninstall otel-collector
	helm -n tracing uninstall tempo

gke-tracing-status:
	kubectl -n tracing get pods,svc

gke-tracing-tempo:
	kubectl -n tracing wait --for=condition=ready pod -l app.kubernetes.io/name=tempo --timeout=180s
	kubectl -n tracing port-forward svc/tempo $${PORT:-3200}:3200

helm-template-bento:
	helm template bento-price-predictor charts/bento-price-predictor

helm-template-data-validation:
	helm template data-validation charts/data-validation

helm-template-feature-platform:
	helm template feature-platform charts/feature-platform

helm-template-alert-rule-engine:
	helm template alert-rule-engine charts/alert-rule-engine

helm-template-alert-index:
	helm template alert-index charts/alert-index

helm-template-inference-orchestrator:
	helm template inference-orchestrator charts/inference-orchestrator
