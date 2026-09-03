# ==============================================================================
# Docker Compose
# ==============================================================================

COMPOSE := docker compose

COMPOSE_DEV := $(COMPOSE) \
-p myapp-dev \
-f compose.yaml \
-f docker/override/dev.yaml

COMPOSE_PREPROD := $(COMPOSE) \
-p myapp-preprod \
-f compose.yaml \
-f docker/override/preprod.yaml

COMPOSE_PROD := $(COMPOSE) \
-p myapp-prod \
-f compose.yaml \
-f docker/override/prod.yaml


# ==============================================================================
# DEV
# ==============================================================================

.PHONY: dev-up dev-down dev-logs

dev-up:
	$(COMPOSE_DEV) up -d --wait

dev-down:
	$(COMPOSE_DEV) down

dev-logs:
	$(COMPOSE_DEV) logs -f


# ==============================================================================
# PREPROD
# ==============================================================================

.PHONY: preprod-up preprod-down preprod-logs

preprod-up:
	$(COMPOSE_PREPROD) up -d --wait

preprod-down:
	$(COMPOSE_PREPROD) down

preprod-logs:
	$(COMPOSE_PREPROD) logs -f


# ==============================================================================
# PROD
# ==============================================================================

.PHONY: prod-up prod-down prod-logs

prod-up:
	$(COMPOSE_PROD) up -d --wait

prod-down:
	$(COMPOSE_PROD) down

prod-logs:
	$(COMPOSE_PROD) logs -f

# ==============================================================================
# Quality
# ==============================================================================

.PHONY: \
	precommit \
	check-compose \
	check-caddy-host \
	check-caddy-frankenphp \
	lint \
	test \
	qa

check-compose:
	$(COMPOSE_DEV) config --quiet
	$(COMPOSE_PREPROD) config --quiet
	$(COMPOSE_PROD) config --quiet

lint:
	composer validate --strict
	vendor/bin/php-cs-fixer check --diff
	vendor/bin/phpstan analyse
	php bin/console lint:container
	php bin/console lint:yaml config
	php bin/console lint:twig templates

test:
	php bin/phpunit

check-caddy-host:
	caddy validate \
		--config ./Caddyfile \
		--adapter caddyfile

check-caddy-frankenphp:
	docker run --rm \
		-v "$(CURDIR)/frankenphp/Caddyfile:/etc/frankenphp/Caddyfile:ro" \
		dunglas/frankenphp:1-php8.5 \
		frankenphp validate \
		--config /etc/frankenphp/Caddyfile \
		--adapter caddyfile

precommit: check-compose check-caddy-host check-caddy-frankenphp

qa: precommit lint test
