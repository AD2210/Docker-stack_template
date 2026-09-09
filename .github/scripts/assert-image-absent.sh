#!/usr/bin/env bash
set -euo pipefail
: "${GHCR_USERNAME:?}"
: "${GHCR_TOKEN:?}"
IMAGE="${1:?Image required}"
TAG="${2:?Tag required}"
[[ "$IMAGE" =~ ^ghcr.io/[a-z0-9._/-]+$ ]] || exit 2
[[ "$TAG" =~ ^V(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || exit 2
# Credentials enter curl through stdin rather than process arguments.
[[ "$GHCR_USERNAME" =~ ^[a-zA-Z0-9_-]+$ && "$GHCR_TOKEN" =~ ^[a-zA-Z0-9_]+$ ]] || exit 2
TOKEN_JSON="$(printf 'user = "%s:%s"\n' "$GHCR_USERNAME" "$GHCR_TOKEN" | curl --config - --fail --silent --show-error --connect-timeout 10 --max-time 30 --get --data-urlencode "scope=repository:${IMAGE#ghcr.io/}:pull" https://ghcr.io/token)"
TOKEN="$(printf '%s' "$TOKEN_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])')"
[[ "$TOKEN" =~ ^[a-zA-Z0-9._=-]+$ ]] || exit 2
STATUS="$(printf 'header = "Authorization: Bearer %s"\n' "$TOKEN" | curl --config - --silent --show-error --head --header "Accept: application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json" --output /dev/null --write-out '%{http_code}' --connect-timeout 10 --max-time 30 "https://ghcr.io/v2/${IMAGE#ghcr.io/}/manifests/${TAG}")"
case "$STATUS" in
    404) echo "Unpublished image tag confirmed: $IMAGE:$TAG" ;;
    200) echo 'Refusing to overwrite an existing image tag.' >&2; exit 1 ;;
    *) echo "Unable to establish tag absence (HTTP $STATUS); refusing publication." >&2; exit 1 ;;
esac
