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
make --no-print-directory -s deployment-config-json | jq -er --arg service "$RELEASE_SERVICE" --arg tag "$IMAGE_TAG" '
    .services[$service].image as $image
    | if (.name | type) != "string" or (.name | test("^[a-z0-9][a-z0-9_-]*$") | not)
        then error("Invalid Compose project name") else . end
    | if ($service | test("^[a-z0-9][a-z0-9_-]*$") | not)
        then error("Invalid Compose service name") else . end
    | if ($image | type) != "string" or ($image | test("[\r\n]")) or ($image | endswith(":" + $tag) | not)
        then error("Compose image does not use release tag") else . end
    | "COMPOSE_PROJECT_NAME=" + .name,
      "RELEASE_SERVICE=" + $service,
      "RELEASE_IMAGE=" + ($image | rtrimstr(":" + $tag))
'
