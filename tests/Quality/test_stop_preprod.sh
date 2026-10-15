#!/usr/bin/env bash
# Run the real shutdown script with a fake Docker CLI; never contact a daemon.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
script="$root/.github/scripts/stop-preprod.sh"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

exercise() {
    local scenario="$1" expected_status="$2" status=0 configuration containers calls
    local folder="$temporary/$scenario" project=example-preprod
    local image=ghcr.io/owner/example-app-php-preprod:V1.2.3
    mkdir -p "$folder/bin" "$folder/app with spaces"
    [[ "$scenario" != production ]] || project=example-prod
    configuration="$(jq -n --arg project "$project" --arg image "$image" '{name:$project,services:{php:{image:$image}}}')"
    containers="$(jq -n --arg project "$project" --arg image "$image" '["php","messenger","scheduler","database"] | map(. as $service | {Config:{Image:(if $service == "database" then "postgres:16" else $image end),Labels:{"com.docker.compose.project":$project,"com.docker.compose.service":$service}}})')"
    case "$scenario" in
        newer-manifest) configuration="$(jq '.services.php.image |= sub("V1.2.3$";"V1.2.4")' <<< "$configuration")" ;;
        newer-container) containers="$(jq '.[0].Config.Image |= sub("V1.2.3$";"V1.2.4")' <<< "$containers")" ;;
        partial-deployment) containers="$(jq '.[1].Config.Image |= sub("V1.2.3$";"V1.2.4")' <<< "$containers")" ;;
        wrong-project) containers="$(jq '.[0].Config.Labels["com.docker.compose.project"] = "example-prod"' <<< "$containers")" ;;
        wrong-manifest) configuration="$(jq '.name = "example-prod"' <<< "$configuration")" ;;
        bad-json) configuration='{' ;;
    esac
    printf '%s\n' "$configuration" > "$folder/config"
    printf '%s\n' "$containers" > "$folder/containers"
    [[ "$scenario" = no-manifest ]] || printf '{}\n' > "$folder/app with spaces/compose.runtime.yaml"
    [[ "$scenario" = no-env ]] || printf 'PHP_SHA_CURRENT=V1.2.3\n' > "$folder/app with spaces/.env.prod.local"
    cat > "$folder/bin/docker" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$FIXTURES/calls"
[[ "$SCENARIO" != docker-failure ]] || exit 9
if [[ "$1" = inspect ]]; then cat "$FIXTURES/containers"; exit 0; fi
case "$*" in
    *'config --format json'*) [[ "$SCENARIO" != config-failure ]] || exit 9; cat "$FIXTURES/config" ;;
    *'ps --all --quiet'*)
        [[ "$SCENARIO" != ps-failure ]] || exit 9
        if [[ "$SCENARIO" != no-containers ]]; then printf 'container-1\ncontainer-2\n'; fi ;;
    *'stop --timeout 30 php messenger scheduler')
        [[ "$SCENARIO" != stop-failure ]] || exit 9
        cat >/dev/null ;;
    *) exit 88 ;;
esac
MOCK
    chmod 700 "$folder/bin/docker"
    (
        export PATH="$folder/bin:$PATH" FIXTURES="$folder" SCENARIO="$scenario"
        export APP_PATH="$folder/app with spaces" COMPOSE_PROJECT_NAME="$project"
        export RELEASE_IMAGE="${image%:*}" RELEASE_TAG=V1.2.3
        if [[ "$scenario" = ssh-stdin ]]; then bash -s < "$script"; else bash "$script"; fi
    ) > "$folder/output" 2>&1 || status=$?
    if [[ "$status" != "$expected_status" ]]; then
        cat "$folder/output" >&2
        fail "$scenario: expected exit $expected_status, got $status"
    fi
    calls=''
    [[ ! -f "$folder/calls" ]] || calls="$(cat "$folder/calls")"
    case "$scenario" in
        current|ssh-stdin|stop-failure)
            [[ "$calls" = *'stop --timeout 30 php messenger scheduler' ]] || fail "$scenario: application was not stopped"
            [[ "$calls" = *$'inspect '*$'\n'*'stop --timeout'* ]] || fail "$scenario: containers not inspected before stop" ;;
        *) [[ "$calls" != *'stop --timeout'* ]] || fail "$scenario: unexpected shutdown" ;;
    esac
    [[ "$calls" != *' down'* && "$calls" != *' rm'* && "$calls" != *'scheduler database'* ]] || fail "$scenario: destructive or database operation"
    if [[ "$scenario" != no-manifest ]]; then
        [[ "$(cat "$folder/app with spaces/compose.runtime.yaml")" = '{}' ]] || fail "$scenario: runtime manifest modified"
    fi
    printf 'OK: %s\n' "$scenario"
}

exercise current 0
exercise ssh-stdin 0
exercise newer-manifest 0
exercise newer-container 0
exercise partial-deployment 0
exercise no-manifest 0
exercise no-containers 0
exercise production 2
exercise wrong-project 1
exercise wrong-manifest 1
exercise no-env 1
exercise bad-json 1
exercise docker-failure 9
exercise config-failure 9
exercise ps-failure 9
exercise stop-failure 9
