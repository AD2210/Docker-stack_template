"""Prepare a VM profile without accessing virtualization or any GitHub credentials."""

import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class RunnerVmTest(unittest.TestCase):
    def test_preparation_is_private_and_never_overwrites_an_existing_vm(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            key = root / "key.pub"
            key.write_text('ssh-ed25519 YWJjZGVmZ2hpamtsbW5vcA== runner "comment"\n')
            output = root / "seed"
            command = [
                "python3",
                str(ROOT / "tools/prepare_runner_vm.py"),
                "--ssh-public-key",
                str(key),
                "--output",
                str(output),
            ]
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(0, result.returncode, result.stderr)
            content = (output / "user-data").read_text()
            self.assertNotIn("__SSH_PUBLIC_KEY__", content)
            self.assertNotIn("GITHUB_TOKEN", content)
            self.assertIn('runner \\"comment\\"', content)
            self.assertEqual(0o600, (output / "user-data").stat().st_mode & 0o777)
            second = subprocess.run(command, capture_output=True, text=True)
            self.assertNotEqual(0, second.returncode)
            self.assertEqual(content, (output / "user-data").read_text())

    def test_a_private_key_is_rejected_before_any_output_is_written(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            key = root / "private"
            key.write_text("-----BEGIN OPENSSH PRIVATE KEY-----\nnot-a-public-key\n")
            output = root / "seed"
            result = subprocess.run(
                [
                    "python3",
                    str(ROOT / "tools/prepare_runner_vm.py"),
                    "--ssh-public-key",
                    str(key),
                    "--output",
                    str(output),
                ],
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(0, result.returncode)
            self.assertFalse(output.exists())
