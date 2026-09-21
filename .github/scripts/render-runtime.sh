#!/usr/bin/env bash
# Compose accepts JSON as YAML; jq preserves escaping and unrelated settings.
set -euo pipefail
[[ $# = 2 ]] || { echo 'Usage: render-runtime.sh SOURCE TARGET' >&2; exit 2; }
command -v jq >/dev/null || { echo 'Missing prerequisite: jq' >&2; exit 1; }
jq -e '
    if type != "object" or (.name | type) != "string" or (.name | length) == 0
        then error("Compose project name missing") else . end
    | reduce ["php", "messenger", "scheduler"][] as $service (.;
        if (.services[$service] | type) != "object"
            then error("Compose application service missing: " + $service)
        else .services[$service].image = "${PHP_IMAGE:?Missing release image}:${PHP_SHA_CURRENT:?Missing release tag}"
            | del(.services[$service].build)
        end)
    | .services.php.environment.MERCURE_JWT_SECRET = "${MERCURE_JWT_SECRET:?Missing Mercure JWT secret}"
    | .services.php.environment.MERCURE_PUBLISHER_JWT_KEY = "${MERCURE_JWT_SECRET:?Missing Mercure JWT secret}"
    | .services.php.environment.MERCURE_SUBSCRIBER_JWT_KEY = "${MERCURE_JWT_SECRET:?Missing Mercure JWT secret}"
' "$1" > "$2"
