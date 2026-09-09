# ==============================================================================
# Docker Compose
# ==============================================================================

COMPOSE := docker compose
COMPOSE_PROJECT_BASE ?= myapp
RELEASE_SERVICE := php

COMPOSE_DEV := $(COMPOSE) \
-p $(COMPOSE_PROJECT_BASE)-dev \
-f compose.yaml \
-f docker/override/dev.yaml

COMPOSE_PREPROD := $(COMPOSE) \
-p $(COMPOSE_PROJECT_BASE)-preprod \
-f compose.yaml \
-f docker/override/preprod.yaml

COMPOSE_PROD := $(COMPOSE) \
-p $(COMPOSE_PROJECT_BASE)-prod \
-f compose.yaml \
-f docker/override/prod.yaml


# ==============================================================================
# DEV
# ==============================================================================

.PHONY: dev-up dev-down dev-logs dev-config dev-reset dev-exec

dev-config:
	$(COMPOSE_DEV) config

dev-up:
	$(COMPOSE_DEV) up -d --wait

dev-down:
	$(COMPOSE_DEV) down

dev-reset:
	$(COMPOSE_DEV) down --remove-orphans

dev-logs:
	$(COMPOSE_DEV) logs -f

dev-exec:
	$(COMPOSE_DEV) exec

# ==============================================================================
# PREPROD
# ==============================================================================

.PHONY: preprod-up preprod-down preprod-logs preprod-config preprod-reset

preprod-config:
	$(COMPOSE_PREPROD) config

preprod-up:
	$(COMPOSE_PREPROD) up -d --wait

preprod-down:
	$(COMPOSE_PREPROD) down

preprod-reset:
	$(COMPOSE_PREPROD) down --remove-orphans

preprod-logs:
	$(COMPOSE_PREPROD) logs -f


# ==============================================================================
# PROD
# ==============================================================================

.PHONY: prod-up prod-down prod-logs prod-config prod-reset

prod-config:
	$(COMPOSE_PROD) config

prod-up:
	$(COMPOSE_PROD) up -d --wait

prod-down:
	$(COMPOSE_PROD) down

prod-reset:
	$(COMPOSE_PROD) down --remove-orphans

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

# Build and deployment use the same modular Compose image definitions.
.PHONY: preprod-build preprod-push prod-build prod-push
preprod-build:
	$(COMPOSE_PREPROD) build --pull $(RELEASE_SERVICE)
preprod-push:
	$(COMPOSE_PREPROD) push $(RELEASE_SERVICE)
prod-build:
	$(COMPOSE_PROD) build --pull $(RELEASE_SERVICE)
prod-push:
	$(COMPOSE_PROD) push $(RELEASE_SERVICE)

# CD resolves image names from the same Compose source as build/push.
.PHONY: deployment-config-json deployment-service deploy-source-config deploy-compose
deployment-config-json:
	@$(COMPOSE) -p "$(COMPOSE_PROJECT_BASE)-$(COMPOSE_ENVIRONMENT)" -f compose.yaml -f "docker/override/$(COMPOSE_ENVIRONMENT).yaml" config --format json --no-env-resolution
deployment-service:
	@echo $(RELEASE_SERVICE)
deploy-source-config:
	@$(COMPOSE) --project-name "$(COMPOSE_PROJECT_NAME)" --env-file "docker/env/$(COMPOSE_ENVIRONMENT).env" --env-file "$(CANDIDATE)" -f compose.yaml -f "docker/override/$(COMPOSE_ENVIRONMENT).yaml" config --format json
deploy-compose: SHELL := /bin/bash
deploy-compose:
	@eval "set -- $$COMPOSE_ARGUMENTS"; $(COMPOSE) --env-file "$(CANDIDATE)" -f "$(MANIFEST)" "$$@"
