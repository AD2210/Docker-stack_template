#!/usr/bin/env bash
set -euo pipefail
TAG="${1:?Release tag required}"
# Prereleases need an explicit preproduction workflow, never implicit promotion.
if [[ ! "$TAG" =~ ^V(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo 'Invalid stable SemVer tag.' >&2
    exit 1
fi
# checkout fetch-depth: 0 already provides tags and origin/main; credentials are intentionally not persisted.
SHA="$(git rev-parse --verify "refs/tags/$TAG^{commit}")"
git merge-base --is-ancestor "$SHA" refs/remotes/origin/main || {
    echo 'Release commit is not reachable from main.' >&2
    exit 1
}
printf 'tag=%s\nsha=%s\n' "$TAG" "$SHA"
