#!/usr/bin/env bash
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
[[ "$APP_URL" = https://* ]] || exit 2
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
command -v make >/dev/null
command -v python3 >/dev/null
# Server provisioning owns secrets; fail before backup or deployment changes.
for secret in postgres_password "${COMPOSE_ENVIRONMENT}.decrypt.private.php"; do
    [[ -s "$APP_PATH/secrets/$secret" && -r "$APP_PATH/secrets/$secret" ]] || { echo "Missing or unreadable runtime secret: $secret" >&2; exit 1; }
done
server-release init "$APP_PATH" "$RELEASE_SERVICE" "$RELEASE_IMAGE"
sudo /usr/local/lib/server-setup/backup-databases.sh
tar -xzf "$ARCHIVE" -C "$APP_PATH"
CANDIDATE="$(mktemp "$APP_PATH/.candidate.XXXXXX")"
RESOLVED="$(mktemp "$APP_PATH/.resolved.XXXXXX")"
MANIFEST="$(mktemp "$APP_PATH/.runtime.XXXXXX.yaml")"
printf 'PHP_IMAGE=%s\nPHP_SHA_CURRENT=%s\nIMAGE_TAG=%s\n' "$RELEASE_IMAGE" "$RELEASE_TAG" "$RELEASE_TAG" > "$CANDIDATE"
REGISTRY_CONFIG="$(mktemp -d)"
export DOCKER_CONFIG="$REGISTRY_CONFIG"
printf '%s' "$GHCR_TOKEN" | docker login ghcr.io --username "$GHCR_USERNAME" --password-stdin
cd "$APP_PATH"
export CANDIDATE MANIFEST
make --no-print-directory -s deploy-source-config > "$RESOLVED"
python3 "$APP_PATH/deploy/render-runtime.py" "$RESOLVED" "$MANIFEST"
compose() { COMPOSE_ARGUMENTS="$(printf '%q ' "$@")" make --no-print-directory -s deploy-compose; }
compose config --quiet
compose pull
# Validate effective secret visibility using the final image/user before stopping old services.
compose run --rm --no-deps --entrypoint php --user 33 php -r 'foreach (["/run/secrets/postgres_password", "/app/config/secrets/".getenv("APP_ENV")."/".getenv("APP_ENV").".decrypt.private.php"] as $path) { if (!is_readable($path)) { fwrite(STDERR, "Required runtime secret is unreadable\n"); exit(1); } }'
compose up --detach --wait database
# Failures after this point need reconciliation; no blind rollback of schema/data.
compose stop messenger scheduler
compose up --detach --wait --remove-orphans
curl --fail-with-body --show-error --silent --connect-timeout 10 --max-time 20 --retry 5 --retry-delay 5 --retry-max-time 120 --retry-all-errors "${APP_URL%/}/health"
mv "$MANIFEST" "$APP_PATH/compose.runtime.yaml"
MANIFEST=''
server-release record "$APP_PATH" "$RELEASE_SERVICE" "$RELEASE_TAG" "$RELEASE_IMAGE"
echo "Release $RELEASE_TAG recorded after successful readiness check."
