"""Contract tests invoke the real Bash gate with an isolated GitHub CLI fixture."""
import json
import os
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class PromotionTest(unittest.TestCase):
    def setUp(self):
        self.sha = "a" * 40
        self.name = f"preprod-v2-V1.2.3-{self.sha}"
        self.artifact = {"name": self.name, "expired": False, "workflow_run": {"id": 42}}
        self.run = {"id": 42, "path": ".github/workflows/release.yaml", "status": "completed", "conclusion": "success", "repository": {"full_name": "owner/repo"}, "event": "push", "head_branch": "V1.2.3", "head_sha": self.sha}

    def check(self, artifacts=None, run=None, raw=None, failure=False, tag="V1.2.3", sha=None, pages=None):
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            (directory / "gh").write_text('''#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$*" >> "$FIXTURES/calls"
[[ "$API_FAILURE" = 0 ]] || exit 1
if [[ "$*" = *'/actions/artifacts?'* ]]; then
    page="${2##*page=}"
    if [[ -f "$FIXTURES/page-$page" ]]; then cat "$FIXTURES/page-$page"; else cat "$FIXTURES/artifacts"; fi
else
    cat "$FIXTURES/run"
fi
''')
            (directory / "gh").chmod(0o755)
            (directory / "artifacts").write_text(raw if raw is not None else json.dumps({"artifacts": artifacts if artifacts is not None else [self.artifact]}))
            (directory / "run").write_text(json.dumps(run if run is not None else self.run))
            for page, content in (pages or {}).items():
                (directory / f"page-{page}").write_text(json.dumps({"artifacts": content}))
            result = subprocess.run(["bash", str(ROOT / ".github/scripts/verify-preprod.sh")], env=os.environ | {"PATH": str(directory) + ":" + os.environ["PATH"], "FIXTURES": temporary, "API_FAILURE": str(int(failure)), "GITHUB_REPOSITORY": "owner/repo", "RELEASE_TAG": tag, "RELEASE_SHA": sha or self.sha}, capture_output=True, text=True, timeout=10)
            calls = directory / "calls"
            return result.returncode, calls.read_text() if calls.exists() else ""

    def test_successful_tag_and_manual_release(self):
        self.assertEqual(0, self.check()[0])
        self.assertEqual(0, self.check(run=self.run | {"event": "workflow_dispatch", "head_branch": "main", "head_sha": "b" * 40})[0])

    def test_missing_expired_and_wrong_sha_proof(self):
        for artifacts in [[], [self.artifact | {"expired": True}], [self.artifact | {"name": self.name + "wrong"}], [self.artifact | {"name": f"preprod-V1.2.3-{self.sha}"}], [self.artifact | {"expired": "false"}]]:
            with self.subTest(artifacts=artifacts):
                self.assertNotEqual(0, self.check(artifacts=artifacts)[0])

    def test_failed_untrusted_or_wrong_commit_run(self):
        for change in [{"id": 99}, {"conclusion": "failure"}, {"status": "in_progress"}, {"path": ".github/workflows/other.yaml"}, {"head_sha": "b" * 40}, {"event": "pull_request"}, {"event": "workflow_dispatch", "head_branch": "feature/untrusted"}, {"repository": {"full_name": "other/repo"}}]:
            with self.subTest(change=change):
                self.assertNotEqual(0, self.check(run=self.run | change)[0])

    def test_api_failure_and_invalid_input_fail_closed(self):
        for options in [{"failure": True}, {"tag": "v1.2.3"}, {"sha": "bad"}, {"raw": "{"}, {"raw": "{}"}, {"raw": '{"artifacts":null}'}, {"artifacts": [self.artifact | {"workflow_run": {"id": "42/other"}}]}, {"run": {}}]:
            with self.subTest(options=options):
                self.assertNotEqual(0, self.check(**options)[0])

    def test_pagination_reaches_second_page_and_stops_at_ten(self):
        ignored = self.artifact | {"expired": True}
        code, calls = self.check(pages={1: [ignored] * 100, 2: [self.artifact]})
        self.assertEqual(0, code)
        self.assertIn("page=2", calls)
        code, calls = self.check(artifacts=[ignored] * 100)
        self.assertNotEqual(0, code)
        self.assertEqual(10, calls.count("/actions/artifacts?"))


if __name__ == "__main__":
    unittest.main()
