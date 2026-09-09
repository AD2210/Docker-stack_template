#!/usr/bin/env bash
# Run with sudo: deploy only this application's endpoint, never the server snippets.
set -euo pipefail
PROJECT="${1:?Compose project required}"
SOURCE="${2:?Application Caddy file required}"
[[ "$PROJECT" =~ ^[a-z0-9][a-z0-9_-]*$ && -s "$SOURCE" ]] || exit 2
CADDY_ROOT="${CADDY_ROOT:-/etc/caddy}"
[[ -d "$CADDY_ROOT/apps" && -f "$CADDY_ROOT/Caddyfile" ]] || exit 2
exec 9>"${CADDY_LOCK_FILE:-/run/lock/application-caddy.lock}"
flock -x -w 60 9
TARGET="$CADDY_ROOT/apps/$PROJECT.caddy"
TEMPORARY="$(mktemp -d)"
EXISTED=false
CHANGED=false
COMMITTED=false
cleanup() {
    status=$?
    trap - EXIT
    if $CHANGED && ! $COMMITTED; then
        if $EXISTED; then cp -p "$TEMPORARY/previous" "$TARGET"; else rm -f "$TARGET"; fi
        if ! caddy validate --config "$CADDY_ROOT/Caddyfile" --adapter caddyfile || ! systemctl reload caddy; then
            echo 'Previous Caddy configuration could not be reloaded; operator action required' >&2
        fi
    fi
    rm -rf "$TEMPORARY"
    exit "$status"
}
trap cleanup EXIT
if [[ -e "$TARGET" ]]; then
    cp -p "$TARGET" "$TEMPORARY/previous"
    EXISTED=true
fi
CHANGED=true
install -m 644 "$SOURCE" "$TARGET"
caddy validate --config "$CADDY_ROOT/Caddyfile" --adapter caddyfile
systemctl reload caddy
COMMITTED=true
