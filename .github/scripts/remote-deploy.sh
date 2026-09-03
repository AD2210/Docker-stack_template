#!/usr/bin/env bash
set -euo pipefail

: "${DEPLOY_PATH:?}"
: "${COMPOSE_PROJECT_NAME:?}"
: "${COMPOSE_ENVIRONMENT:?}"
: "${RELEASE_TAG:?}"
: "${IMAGE_PREFIX:?}"
: "${GHCR_USERNAME:?}"
: "${GHCR_TOKEN:?}"

ARCHIVE="/tmp/${COMPOSE_PROJECT_NAME}-${RELEASE_TAG}.tar.gz"
RELEASE_DIR="${DEPLOY_PATH}/releases/${RELEASE_TAG}"
CURRENT_LINK="${DEPLOY_PATH}/current"

mkdir -p "${RELEASE_DIR}"
tar -xzf "${ARCHIVE}" -C "${RELEASE_DIR}"
rm -f "${ARCHIVE}"
chmod 600 "${RELEASE_DIR}/secrets/"*

# Optional database backup before changing the running stack.
# Expected signature:
#   backup-script <compose-project> <release-tag> <preprod|prod>
if [[ -n "${BACKUP_SCRIPT:-}" ]]; then
    echo "Running database backup..."
    "${BACKUP_SCRIPT}" \
        "${COMPOSE_PROJECT_NAME}" \
        "${RELEASE_TAG}" \
        "${COMPOSE_ENVIRONMENT}"
fi

echo "${GHCR_TOKEN}" \
    | docker login ghcr.io --username "${GHCR_USERNAME}" --password-stdin

cd "${RELEASE_DIR}"

export IMAGE_TAG="${RELEASE_TAG}"
export IMAGES_PREFIX="${IMAGE_PREFIX}"

COMPOSE=(
    docker compose
    --project-name "${COMPOSE_PROJECT_NAME}"
    --env-file "docker/env/${COMPOSE_ENVIRONMENT}.env"
    --file compose.yaml
    --file "docker/override/${COMPOSE_ENVIRONMENT}.yaml"
)

"${COMPOSE[@]}" config --quiet
"${COMPOSE[@]}" pull
"${COMPOSE[@]}" up --detach --wait --remove-orphans

# The pointer moves only after Compose reports the new stack healthy.
ln -sfn "${RELEASE_DIR}" "${CURRENT_LINK}"

echo "Deployment ${RELEASE_TAG} (${COMPOSE_ENVIRONMENT}) is healthy."
