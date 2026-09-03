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
