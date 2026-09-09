import importlib.util
import pathlib
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("promotion", pathlib.Path(__file__).resolve().parents[2] / ".github/scripts/verify-preprod.py")
promotion = importlib.util.module_from_spec(spec)
spec.loader.exec_module(promotion)


class PromotionTest(unittest.TestCase):
    def setUp(self):
        self.sha = "a" * 40
        self.name = f"preprod-V1.2.3-{self.sha}"
        self.artifact = {"name": self.name, "expired": False, "workflow_run": {"id": 42}}
        self.run = {"id": 42, "path": ".github/workflows/release.yaml", "status": "completed", "conclusion": "success", "repository": {"full_name": "owner/repo"}, "event": "push", "head_branch": "V1.2.3", "head_sha": self.sha}

    def check(self, artifacts=None, run=None):
        with patch.object(promotion, "api", side_effect=[{"artifacts": artifacts if artifacts is not None else [self.artifact]}, run or self.run]):
            return promotion.verify("owner/repo", "V1.2.3", self.sha)

    def test_successful_tag_and_manual_release(self):
        self.assertEqual(42, self.check())
        self.assertEqual(42, self.check(run=self.run | {"event": "workflow_dispatch", "head_branch": "main", "head_sha": "b" * 40}))

    def test_missing_expired_and_wrong_sha_proof(self):
        for artifacts in [[], [self.artifact | {"expired": True}], [self.artifact | {"name": self.name + "wrong"}]]:
            with self.subTest(artifacts=artifacts), self.assertRaises(ValueError):
                self.check(artifacts=artifacts)

    def test_failed_untrusted_or_wrong_commit_run(self):
        for change in [{"conclusion": "failure"}, {"status": "in_progress"}, {"path": ".github/workflows/other.yaml"}, {"head_sha": "b" * 40}, {"event": "pull_request"}, {"event": "workflow_dispatch", "head_branch": "feature/untrusted"}, {"repository": {"full_name": "other/repo"}}]:
            with self.subTest(change=change), self.assertRaises(ValueError):
                self.check(run=self.run | change)

    def test_api_failure_and_invalid_input_fail_closed(self):
        with patch.object(promotion, "api", side_effect=RuntimeError("API unavailable")), self.assertRaises(RuntimeError):
            promotion.verify("owner/repo", "V1.2.3", self.sha)
        with self.assertRaises(ValueError):
            promotion.verify("owner/repo", "v1.2.3", self.sha)
        with self.assertRaises(ValueError):
            promotion.verify("owner/repo", "V1.2.3", "bad")


if __name__ == "__main__":
    unittest.main()
