"""Validate the real Compose cache override without building or publishing an image."""

import json
import os
import pathlib
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class BuildCacheTest(unittest.TestCase):
    def config(self, environment, cache):
        command = [
            "docker",
            "compose",
            "--env-file",
            ".env",
            "--env-file",
            f"docker/env/{environment}.env",
            "-f",
            "compose.yaml",
            "-f",
            f"docker/override/{environment}.yaml",
        ]
        if cache:
            command += ["-f", "docker/override/build-cache.yaml"]
        result = subprocess.run(
            command + ["config", "--format", "json"],
            cwd=ROOT,
            env=os.environ
            | {
                "APP_SECRET": "cache-test-only-32-characters-secret",
                "BUILD_CACHE_REF": f"ghcr.io/example/build-cache:{environment}",
            },
            capture_output=True,
            text=True,
            timeout=20,
        )
        self.assertEqual(0, result.returncode, result.stderr)
        return json.loads(result.stdout)

    def test_cache_is_opt_in_and_does_not_change_release_images(self):
        for environment in ["preprod", "prod"]:
            with self.subTest(environment=environment):
                normal = self.config(environment, False)["services"]["php"]
                cached = self.config(environment, True)["services"]["php"]
                self.assertEqual(normal["image"], cached["image"])
                self.assertEqual(normal["build"]["target"], cached["build"]["target"])
                self.assertNotIn("cache_to", normal["build"])
                self.assertEqual(
                    [f"type=registry,ref=ghcr.io/example/build-cache:{environment}"],
                    cached["build"]["cache_from"],
                )
                self.assertEqual(
                    [
                        f"type=registry,ref=ghcr.io/example/build-cache:{environment},mode=max"
                    ],
                    cached["build"]["cache_to"],
                )
                build = subprocess.run(
                    [
                        "make",
                        "-n",
                        f"{environment}-build",
                        f"BUILD_CACHE_REF=ghcr.io/example/build-cache:{environment}",
                        "BUILDX_BUILDER=test-builder",
                    ],
                    cwd=ROOT,
                    capture_output=True,
                    text=True,
                    timeout=20,
                )
                self.assertEqual(0, build.returncode, build.stderr)
                self.assertIn("-f docker/override/build-cache.yaml", build.stdout)
                self.assertIn("--builder test-builder", build.stdout)
