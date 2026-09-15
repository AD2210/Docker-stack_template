#!/usr/bin/env bash
# Require a tag/SHA-bound proof from a successful trusted release run.
set -euo pipefail
: "${GITHUB_REPOSITORY:?}"
: "${RELEASE_TAG:?}"
: "${RELEASE_SHA:?}"
[[ "$GITHUB_REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo 'Invalid repository' >&2; exit 2; }
[[ "$RELEASE_TAG" =~ ^V(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || { echo 'Invalid release tag' >&2; exit 2; }
[[ "$RELEASE_SHA" =~ ^[a-f0-9]{40}$ ]] || { echo 'Invalid release SHA' >&2; exit 2; }
for prerequisite in jq gh timeout; do
    command -v "$prerequisite" >/dev/null || { echo "Missing prerequisite: $prerequisite" >&2; exit 1; }
done
name="preprod-v2-${RELEASE_TAG}-${RELEASE_SHA}"
api() { timeout 30s gh api "$1"; }

trusted_run() {
    jq -e --arg repository "$GITHUB_REPOSITORY" --arg tag "$RELEASE_TAG" --arg sha "$RELEASE_SHA" --argjson id "$1" '
        .id == $id
        and (.path | type == "string")
        and (.path | split("@")[0] == ".github/workflows/release.yaml")
        and .status == "completed" and .conclusion == "success"
        and (.repository.full_name | ascii_downcase) == ($repository | ascii_downcase)
        and ((.event == "push" and .head_branch == $tag and .head_sha == $sha)
            or (.event == "workflow_dispatch" and .head_branch == "main"))
    ' >/dev/null <<< "$2"
}

# Bound pagination and calls; malformed API responses fail closed.
for ((page = 1; page <= 10; page++)); do
    response=$(api "repos/${GITHUB_REPOSITORY}/actions/artifacts?name=${name}&per_page=100&page=${page}")
    count=$(jq -er '.artifacts | if type == "array" then length else error("Invalid artifact response") end' <<< "$response")
    ids=$(jq -er --arg name "$name" '[.artifacts[] | select(.name == $name and .expired == false) | .workflow_run.id
        | if type == "number" and . > 0 and . == floor then . else error("Invalid workflow run ID") end] | map(tostring) | join("\n")' <<< "$response")
    while IFS= read -r id; do
        [[ -n "$id" ]] || continue
        run=$(api "repos/${GITHUB_REPOSITORY}/actions/runs/${id}")
        # Separate JSON validity from an ordinary untrusted run.
        jq -e 'type == "object"' >/dev/null <<< "$run"
        if trusted_run "$id" "$run"; then
            echo "Preproduction validated by release run $id; promoting existing production image"
            exit 0
        fi
    done <<< "$ids"
    ((count >= 100)) || break
done
echo 'No successful preproduction proof for this exact tag/SHA (proof may be expired)' >&2
exit 1
