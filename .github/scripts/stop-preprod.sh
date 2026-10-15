#!/usr/bin/env bash
# Parse the whole SSH script before child processes can consume stdin.
{
set -euo pipefail
: "${APP_PATH:?}"
: "${COMPOSE_PROJECT_NAME:?}"
: "${RELEASE_IMAGE:?}"
: "${RELEASE_TAG:?}"
[[ "$APP_PATH" = /* && "$APP_PATH" != / ]] || exit 2
[[ "$COMPOSE_PROJECT_NAME" =~ ^[a-z0-9][a-z0-9_-]*-preprod$ ]] || exit 2
[[ "$RELEASE_IMAGE" =~ ^ghcr.io/[a-z0-9._/-]+$ ]] || exit 2
[[ "$RELEASE_TAG" =~ ^V(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || exit 2
command -v jq >/dev/null || { echo 'Missing server prerequisite: jq' >&2; exit 1; }

if [[ ! -f "$APP_PATH/compose.runtime.yaml" ]]; then
    echo 'No preproduction runtime manifest; nothing to stop.'
    exit 0
fi
[[ -r "$APP_PATH/.env.prod.local" ]] || { echo 'Missing recorded preproduction release environment' >&2; exit 1; }
cd "$APP_PATH"
compose=(docker compose --project-name "$COMPOSE_PROJECT_NAME" --env-file "$APP_PATH/.env.prod.local" -f "$APP_PATH/compose.runtime.yaml")
configuration="$("${compose[@]}" config --format json --no-env-resolution)"
jq -e --arg project "$COMPOSE_PROJECT_NAME" '.name == $project and (.services.php.image | type == "string")' >/dev/null <<< "$configuration" || {
    echo 'Unexpected preproduction runtime configuration' >&2; exit 1;
}
expected_image="${RELEASE_IMAGE}:${RELEASE_TAG}"
if ! jq -e --arg image "$expected_image" '.services.php.image == $image' >/dev/null <<< "$configuration"; then
    echo 'Preproduction is on a different release; leaving it running.'
    exit 0
fi

# Check the actual containers too: a newer or partial deployment must be preserved.
ids="$("${compose[@]}" ps --all --quiet)"
if [[ -z "$ids" ]]; then
    echo 'No preproduction containers; nothing to stop.'
    exit 0
fi
mapfile -t container_ids <<< "$ids"
containers="$(docker inspect "${container_ids[@]}")"
jq -e --arg project "$COMPOSE_PROJECT_NAME" '
    type == "array" and length > 0
    and all(.[]; .Config.Labels["com.docker.compose.project"] == $project)
' >/dev/null <<< "$containers" || { echo 'Unexpected container project; refusing shutdown' >&2; exit 1; }
if ! jq -e --arg image "$expected_image" '
    [.[] | select(.Config.Labels["com.docker.compose.service"] as $service
        | ["php", "messenger", "scheduler"] | index($service))] as $apps
    | any($apps[]; .Config.Labels["com.docker.compose.service"] == "php")
      and all($apps[]; .Config.Image == $image)
' >/dev/null <<< "$containers"; then
    echo 'Preproduction containers are on a different or incomplete release; leaving them running.'
    exit 0
fi

# PostgreSQL stays running for scheduled backups and the next deployment backup.
"${compose[@]}" stop --timeout 30 php messenger scheduler
echo "Preproduction application $RELEASE_TAG stopped after successful production promotion; database and volumes retained."
} </dev/null
