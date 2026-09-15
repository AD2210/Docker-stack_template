import os
import pathlib
import subprocess
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parents[2] / ".github/scripts/update-caddy.sh"


class CaddyDeploymentTest(unittest.TestCase):
    def exercise(self, failure="", existing=True):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            (root / "apps").mkdir()
            (root / "bin").mkdir()
            (root / "Caddyfile").write_text("import apps/*.caddy")
            source = root / "candidate"
            source.write_text("new")
            target = root / "apps/example-preprod.caddy"
            if existing:
                target.write_text("old")
            other = root / "apps/other.caddy"
            other.write_text("untouched")
            for command in ["caddy", "systemctl"]:
                tool = root / "bin" / command
                tool.write_text("#!/bin/bash\n" + 'echo "$(basename "$0") $*" >> "$CALLS"\n' + 'if [[ "$(basename "$0")" == "$FAIL" && ! -f "$MARKER" ]]; then touch "$MARKER"; exit 9; fi\n')
                tool.chmod(0o700)
            env = os.environ | {"PATH": str(root / "bin") + ":" + os.environ["PATH"], "CADDY_ROOT": folder, "CADDY_LOCK_FILE": str(root / "lock"), "CALLS": str(root / "calls"), "MARKER": str(root / "failed"), "FAIL": failure}
            result = subprocess.run(["bash", str(SCRIPT), "example-preprod", str(source)], env=env, capture_output=True, text=True)
            self.assertEqual(0 if not failure else 9, result.returncode, result.stderr)
            self.assertEqual("untouched", other.read_text())
            if failure and not existing:
                self.assertFalse(target.exists())
            else:
                self.assertEqual("old" if failure else "new", target.read_text())
            calls = (root / "calls").read_text()
            self.assertNotIn("daemon-reload", calls)
            self.assertIn("systemctl reload caddy", calls)
            self.assertLess(calls.index("caddy validate"), calls.index("systemctl reload"))

    def test_success(self):
        self.exercise()

    def test_invalid_config_restores_old_file(self):
        self.exercise("caddy")

    def test_reload_failure_restores_old_file(self):
        self.exercise("systemctl")

    def test_first_install_failure_removes_new_file(self):
        self.exercise("caddy", existing=False)
