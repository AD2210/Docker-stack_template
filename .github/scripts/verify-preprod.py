#!/usr/bin/env python3
"""Require a successful release run's tag/SHA-bound post-preproduction marker."""
import json
import os
import re
import subprocess


def api(path):
    result = subprocess.run(["gh", "api", path], check=True, capture_output=True, text=True, timeout=30)
    return json.loads(result.stdout)


def verify(repository, tag, sha):
    if not re.fullmatch(r"V(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", tag):
        raise ValueError("Invalid release tag")
    if not re.fullmatch(r"[a-f0-9]{40}", sha):
        raise ValueError("Invalid release SHA")
    name = f"preprod-{tag}-{sha}"
    # Bounded pagination; API failures and absent/expired evidence fail closed.
    for page in range(1, 11):
        artifacts = api(f"repos/{repository}/actions/artifacts?name={name}&per_page=100&page={page}")["artifacts"]
        for artifact in artifacts:
            if artifact["name"] != name or artifact["expired"]:
                continue
            run = api(f"repos/{repository}/actions/runs/{int(artifact['workflow_run']['id'])}")
            if run["path"].split("@")[0] != ".github/workflows/release.yaml":
                continue
            if run["status"] != "completed" or run["conclusion"] != "success":
                continue
            if run["repository"]["full_name"].lower() != repository.lower():
                continue
            trusted_push = run["event"] == "push" and run["head_branch"] == tag and run["head_sha"] == sha
            trusted_dispatch = run["event"] == "workflow_dispatch" and run["head_branch"] == "main"
            if trusted_push or trusted_dispatch:
                return run["id"]
        if len(artifacts) < 100:
            break
    raise ValueError("No successful preproduction proof for this exact tag/SHA (proof may be expired)")


if __name__ == "__main__":
    run_id = verify(os.environ["GITHUB_REPOSITORY"], os.environ["RELEASE_TAG"], os.environ["RELEASE_SHA"])
    print(f"Preproduction validated by release run {run_id}; promoting existing production image")
