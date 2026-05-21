.PHONY: ci deploy up down ps logs migrate backup restore

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
