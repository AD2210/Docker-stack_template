#!/usr/bin/env bash
# Compose accepts JSON as YAML; jq preserves escaping and unrelated settings.
#
# Which services run the release image, and which variables the deployment must
# overwrite, are declared by the project in runtime.json. They are read from the
# resolved Compose file rather than listed here, and the difference matters: a name
# written in this script belongs to the template, so a project that renames a
# service has to edit a script it does not own; worse, a name that no longer
# matches anything fails silently, and a service left on its old image is exactly
# what a deployment must never produce without saying so.
set -euo pipefail
[[ $# = 3 ]] || { echo 'Usage: render-runtime.sh SOURCE TARGET DECLARATION' >&2; exit 2; }
command -v jq >/dev/null || { echo 'Missing prerequisite: jq' >&2; exit 1; }
[[ -r "$3" ]] || { echo "Missing or unreadable runtime declaration: $3" >&2; exit 1; }

RELEASE_IMAGE='${PHP_IMAGE:?Missing release image}:${PHP_SHA_CURRENT:?Missing release tag}'

# The image stays interpolated: the manifest is written before the deployment runs,
# and the values come from the same candidate environment compose will read later.
# Resolving them here would freeze a tag into a file that rollback reads again.
jq -e --arg image "$RELEASE_IMAGE" --slurpfile contrat "$3" '
    def exiger($tenu; $raison): if $tenu then . else error($raison) end;

    exiger(type == "object"; "Resolved Compose is not an object")
    | exiger((.name | type) == "string" and (.name | length) > 0; "Compose project name missing")
    | exiger((.services | type) == "object"; "Resolved Compose has no services map")

    | . as $avant
    | $contrat[0] as $c
    | exiger(($c | type) == "object"; "Runtime declaration is not an object")
    | exiger(($c.services | type) == "array" and ($c.services | length) > 0;
             "Runtime declaration: \"services\" must be a non-empty array of service names")

    # Every declared name must exist, and every declared variable must already be
    # declared by the service. Both are checks rather than commands: a typo would
    # otherwise add a variable nothing reads, or write into a service that does not
    # have the variable, and the manifest would look complete either way.
    | (($c.environment // {}) | type) as $typeEnv
    | exiger($typeEnv == "object";
             "Runtime declaration: \"environment\" must map a service to the variables it overwrites")
    | reduce $c.services[] as $s (.;
        exiger((.services[$s] | type) == "object";
                "Runtime declaration names a service the Compose file does not have: " + $s))
    | (($c.environment // {}) | keys) as $cibles
    | reduce $cibles[] as $s (.;
        exiger((.services[$s] | type) == "object";
                "Runtime declaration names a service the Compose file does not have: " + $s)
        | reduce ($c.environment[$s] | to_entries[]) as $e (.;
            exiger(.services[$s].environment[$e.key] != null;
                    "Runtime declaration writes a variable " + $s + " does not declare: " + $e.key)))

    # A service left out of the declaration keeps the image it had, and a deployment
    # that quietly leaves a worker on an old tag is the failure this declaration
    # exists to prevent. Sharing an image with a declared service is the evidence
    # that it was meant to be declared: nothing else in a Compose file gives two
    # unrelated services the same image by accident.
    | ([$c.services[] as $s | $avant.services[$s].image | select(. != null)] | unique) as $partages
    | reduce ($avant.services | keys_unsorted[]) as $s (.;
        if ($c.services | index($s)) != null then .
        elif ($partages | index($avant.services[$s].image)) != null
            then error("Runtime declaration omits " + $s
                        + ", which runs the same image as a service it declares")
        else . end)

    | reduce $c.services[] as $s (.;
        .services[$s].image = $image
        | del(.services[$s].build))

    | reduce $cibles[] as $s (.;
        reduce ($c.environment[$s] | to_entries[]) as $e (.;
            ($ENV[$e.value] // "") as $valeur
            | exiger(($valeur | length) > 0;
                     "Runtime declaration needs the environment variable " + $e.value
                     + " for " + $s + "." + $e.key)
            # The value is checked, never written. The manifest is a file that
            # stays on the server and that an operator may read; putting a secret
            # in it would be the one thing this contract must never do. Compose
            # reads the same candidate environment later and resolves it there.
            | .services[$s].environment[$e.key] = ("${" + $e.value + ":?Missing runtime secret " + $e.value + "}")))
' "$1" > "$2"
