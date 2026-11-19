"""Run the change selector against real Git history, including unavailable baselines."""

import importlib.util
import os
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("ci_scope", ROOT / "tools/ci_scope.py")
scope = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scope)


class ScopeTest(unittest.TestCase):
    def test_real_changes_and_fail_closed_baselines(self):
        with tempfile.TemporaryDirectory(prefix="dsn-ci-scope-") as temporary:
            root = pathlib.Path(temporary)
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            for key, value in [
                ("user.name", "CI test"),
                ("user.email", "ci@example.test"),
            ]:
                subprocess.run(
                    ["git", "-C", str(root), "config", key, value], check=True
                )
            previous = os.getcwd()
            try:
                os.chdir(root)
                for filename, expected in [
                    ("README.md", False),
                    ("src/Foo.php", False),
                    ("docker/example.yaml", True),
                    (".github/workflows/ci.yaml", True),
                ]:
                    result = subprocess.run(
                        ["git", "rev-parse", "HEAD"], capture_output=True, text=True
                    )
                    before = result.stdout.strip() if result.returncode == 0 else ""
                    path = root / filename
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text("fixture\n")
                    subprocess.run(["git", "add", "."], check=True)
                    subprocess.run(["git", "commit", "-qm", "fixture"], check=True)
                    head = subprocess.check_output(
                        ["git", "rev-parse", "HEAD"], text=True
                    ).strip()
                    self.assertEqual(
                        expected if before else True,
                        scope.infrastructure_changed(before, head),
                    )
                    self.assertFalse(scope.infrastructure_changed(head, head))
                self.assertTrue(scope.infrastructure_changed("0" * 40, head))
                self.assertTrue(scope.infrastructure_changed("invalid", head))
                self.assertTrue(scope.infrastructure_changed("a" * 40, head))
            finally:
                os.chdir(previous)
