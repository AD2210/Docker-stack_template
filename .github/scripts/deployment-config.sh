#!/usr/bin/env bash
set -euo pipefail
: "${GITHUB_REPOSITORY:?}"
: "${COMPOSE_ENVIRONMENT:?}"
: "${IMAGE_TAG:?}"
[[ "$COMPOSE_ENVIRONMENT" = preprod || "$COMPOSE_ENVIRONMENT" = prod ]] || exit 2
[[ "$IMAGE_TAG" =~ ^V(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || exit 2
export COMPOSE_PROJECT_BASE="${GITHUB_REPOSITORY##*/}"
COMPOSE_PROJECT_BASE="${COMPOSE_PROJECT_BASE,,}"
[[ "$COMPOSE_PROJECT_BASE" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || exit 2
export IMAGES_PREFIX="ghcr.io/${GITHUB_REPOSITORY,,}-"
export RELEASE_SERVICE="$(make --no-print-directory -s deployment-service)"
make --no-print-directory -s deployment-config-json | python3 -c '
import json, os, sys
c = json.load(sys.stdin)
service = os.environ["RELEASE_SERVICE"]
image = c["services"][service]["image"]
suffix = ":" + os.environ["IMAGE_TAG"]
assert image.endswith(suffix), "Compose image does not use release tag"
assert "\n" not in image and "\n" not in service
print("COMPOSE_PROJECT_NAME=" + c["name"])
print("RELEASE_SERVICE=" + service)
print("RELEASE_IMAGE=" + image[:-len(suffix)])
'
