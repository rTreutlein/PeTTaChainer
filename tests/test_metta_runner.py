from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


class MeTTaRunnerTests(unittest.TestCase):
    def test_successful_load_with_search_abort_fails_the_suite(self) -> None:
        with tempfile.TemporaryDirectory(prefix="petta-runner-test-") as raw_dir:
            directory = Path(raw_dir)
            passing = directory / "passing.metta"
            aborted = directory / "aborted.metta"
            passing.write_text("!(test (+ 1 1) 2)\n", encoding="utf-8")
            aborted.write_text(
                "!(println! (backward-search-aborted steps 10))\n",
                encoding="utf-8",
            )
            manifest = directory / "files"
            manifest.write_text(f"{passing}\n{aborted}\n", encoding="utf-8")
            result = subprocess.run(
                [
                    str(REPO_ROOT / ".venv/bin/petta"),
                    str(REPO_ROOT / "scripts/fork_test_runner.metta"),
                    "--silent",
                    "--strict-det",
                ],
                cwd=REPO_ROOT / "pettachainer/metta",
                env={
                    **os.environ,
                    "PETTA_FORK_TEST_MANIFEST": str(manifest),
                    "PETTA_FORK_LOG_DIR": str(directory),
                    "PETTA_JOBS": "2",
                },
                capture_output=True,
                text=True,
                timeout=180,
            )

            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 1, output)
            self.assertIn(f"PASS {passing}", output)
            self.assertIn(f"FAIL {aborted}", output)
            self.assertIn("backward-search-aborted", output)
            self.assertIn("Summary: 1 passed, 1 failed", output)


if __name__ == "__main__":
    unittest.main()
