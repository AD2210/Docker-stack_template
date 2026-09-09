#!/usr/bin/env python3
"""Render a single Compose JSON/YAML file retaining server-release interpolation."""
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    manifest = json.load(source)
if not manifest.get("name"):
    raise SystemExit("Compose project name missing")
for name in ("php", "messenger", "scheduler"):
    service = manifest["services"][name]
    service["image"] = "${PHP_IMAGE:?Missing release image}:${PHP_SHA_CURRENT:?Missing release tag}"
    service.pop("build", None)
with open(sys.argv[2], "w", encoding="utf-8") as target:
    json.dump(manifest, target, indent=2)
    target.write("\n")
