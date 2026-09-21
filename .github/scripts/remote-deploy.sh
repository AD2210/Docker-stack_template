#!/usr/bin/env bash
# Parse the complete SSH script before running commands; children must not consume it.
{
set -euo pipefail
umask 077
: "${APP_PATH:?}"
: "${COMPOSE_PROJECT_NAME:?}"
: "${COMPOSE_ENVIRONMENT:?}"
: "${RELEASE_TAG:?}"
: "${RELEASE_SERVICE:?}"
: "${RELEASE_IMAGE:?}"
: "${GHCR_USERNAME:?}"
: "${GHCR_TOKEN:?}"
: "${APP_URL:?}"
[[ "$APP_PATH" = /* && "$APP_PATH" != / ]] || exit 2
[[ "$COMPOSE_PROJECT_NAME" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || exit 2
[[ "$RELEASE_SERVICE" = php ]] || exit 2
[[ "$COMPOSE_ENVIRONMENT" = preprod || "$COMPOSE_ENVIRONMENT" = prod ]] || exit 2
[[ "$RELEASE_TAG" =~ ^V(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || exit 2
[[ "$RELEASE_IMAGE" =~ ^ghcr.io/[a-z0-9._/-]+$ ]] || exit 2
[[ "$APP_URL" = https://* ]] || { echo "APP_URL must start with https://" >&2; exit 2; }
ARCHIVE="/tmp/${COMPOSE_PROJECT_NAME}-${RELEASE_TAG}.tar.gz"
CANDIDATE=''
MANIFEST=''
RESOLVED=''
REGISTRY_CONFIG=''
cleanup() {
    rm -f "$ARCHIVE"
    [[ -z "$REGISTRY_CONFIG" ]] || rm -rf "$REGISTRY_CONFIG"
    for temporary in "$CANDIDATE" "$MANIFEST" "$RESOLVED"; do
        [[ -z "$temporary" ]] || rm -f "$temporary"
    done
}
trap cleanup EXIT
# Renderer and Make must be provisioned before any runtime mutation.
command -v make >/dev/null || { echo "Missing server prerequisite: make (SSH user PATH)" >&2; exit 1; }
command -v jq >/dev/null || { echo "Missing server prerequisite: jq (SSH user PATH)" >&2; exit 1; }
# Server provisioning owns secrets; fail before backup or deployment changes.
for secret in "$APP_PATH/secrets/postgres_password" "$APP_PATH/secrets/mercure_jwt_secret" "$APP_PATH/config/secrets/${COMPOSE_ENVIRONMENT}/${COMPOSE_ENVIRONMENT}.decrypt.private.php"; do
    [[ -s "$secret" && -r "$secret" ]] || { echo "Missing or unreadable runtime secret: $secret" >&2; exit 1; }
done
MERCURE_JWT_SECRET="$(tr -d '\r\n' < "$APP_PATH/secrets/mercure_jwt_secret")"
[[ "$MERCURE_JWT_SECRET" =~ ^[A-Za-z0-9._~+/=-]{32,}$ ]] || { echo 'Invalid runtime secret: mercure_jwt_secret must contain at least 32 safe characters' >&2; exit 1; }
# Never treat a missing manifest on an existing installation as a fresh install.
if [[ -f "$APP_PATH/compose.runtime.yaml" ]]; then
    server-release init "$APP_PATH" "$RELEASE_SERVICE" "$RELEASE_IMAGE"
    sudo -n /usr/local/lib/server-setup/backup-databases.sh
else
    if [[ -f "$APP_PATH/.env.prod.local" ]] && grep -Eq '^PHP_SHA_CURRENT=.+$' "$APP_PATH/.env.prod.local"; then
        echo 'Recorded release exists but runtime manifest is missing' >&2; exit 1
    fi
    existing_containers="$(docker ps -aq --filter "label=com.docker.compose.project=$COMPOSE_PROJECT_NAME")"
    existing_volumes="$(docker volume ls -q --filter "label=com.docker.compose.project=$COMPOSE_PROJECT_NAME")"
    [[ -z "$existing_containers" && -z "$existing_volumes" ]] || { echo 'Existing Docker resources without runtime manifest; reconciliation required' >&2; exit 1; }
    server-release init "$APP_PATH" "$RELEASE_SERVICE" "$RELEASE_IMAGE"
    echo 'First installation: no existing project resources to back up'
fi
tar -xzf "$ARCHIVE" -C "$APP_PATH"
CANDIDATE="$(mktemp "$APP_PATH/.candidate.XXXXXX")"
RESOLVED="$(mktemp "$APP_PATH/.resolved.XXXXXX")"
MANIFEST="$(mktemp "$APP_PATH/.runtime.XXXXXX.yaml")"
printf 'PHP_IMAGE=%s\nPHP_SHA_CURRENT=%s\nIMAGE_TAG=%s\nMERCURE_JWT_SECRET=%s\n' "$RELEASE_IMAGE" "$RELEASE_TAG" "$RELEASE_TAG" "$MERCURE_JWT_SECRET" > "$CANDIDATE"
REGISTRY_CONFIG="$(mktemp -d)"
export DOCKER_CONFIG="$REGISTRY_CONFIG"
printf '%s' "$GHCR_TOKEN" | docker login ghcr.io --username "$GHCR_USERNAME" --password-stdin
cd "$APP_PATH"
export CANDIDATE MANIFEST
make --no-print-directory -s deploy-source-config > "$RESOLVED"
bash "$APP_PATH/deploy/render-runtime.sh" "$RESOLVED" "$MANIFEST"
compose() { COMPOSE_ARGUMENTS="$(printf '%q ' "$@")" make --no-print-directory -s deploy-compose; }
compose config --quiet
compose pull
# Validate effective secret visibility using the final image/user before stopping old services.
compose run --rm --no-deps --entrypoint php --user 33 php -r 'foreach (["/run/secrets/postgres_password", "/app/config/secrets/".getenv("APP_ENV")."/".getenv("APP_ENV").".decrypt.private.php"] as $path) { if (!is_readable($path)) { fwrite(STDERR, "Required runtime secret is unreadable\n"); exit(1); } }'
compose up --detach --wait database
# Failures after this point need reconciliation; no blind rollback of schema/data.
compose stop messenger scheduler
compose up --detach --wait --remove-orphans
sudo -n bash "$APP_PATH/deploy/update-caddy.sh" "$COMPOSE_PROJECT_NAME" "$APP_PATH/caddy/apps/application.caddy"
curl --fail-with-body --show-error --silent --connect-timeout 10 --max-time 20 --retry 5 --retry-delay 5 --retry-max-time 120 --retry-all-errors "${APP_URL%/}/health"
mv "$MANIFEST" "$APP_PATH/compose.runtime.yaml"
MANIFEST=''
server-release record "$APP_PATH" "$RELEASE_SERVICE" "$RELEASE_TAG" "$RELEASE_IMAGE"
echo "Release $RELEASE_TAG recorded after successful readiness check."
} </dev/null
