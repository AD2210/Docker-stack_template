"""Detect infrastructure changes; an unavailable Git baseline always enables validation."""

import os
import re
import subprocess


def infrastructure_changed(base, head):
    if not all(re.fullmatch(r"[0-9a-f]{40}", value or "") for value in [base, head]):
        return True
    try:
        changed = (
            subprocess.check_output(
                ["git", "diff", "--name-only", "--no-renames", "-z", base, head, "--"],
                stderr=subprocess.DEVNULL,
            )
            .decode("utf-8", errors="surrogateescape")
            .split("\0")
        )
    except subprocess.CalledProcessError:
        return True
    roots = {"Makefile", "Caddyfile", "composer.json", "composer.lock"}
    prefixes = ("docker/", "frankenphp/", "caddy/", ".github/")
    return any(
        path in roots
        or path.startswith(prefixes)
        or path.startswith("Dockerfile")
        or (path.startswith("compose") and path.endswith((".yaml", ".yml")))
        for path in changed
        if path
    )


if __name__ == "__main__":
    result = infrastructure_changed(
        os.environ.get("CI_BASE_SHA", ""), os.environ.get("CI_HEAD_SHA", "")
    )
    print("infrastructure=" + str(result).lower())
