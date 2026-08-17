from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SUPPORT_PATH = (
    REPO_ROOT / "pettachainer" / "benchmarks" / "_benchmark_support.py"
)
SPEC = importlib.util.spec_from_file_location("benchmark_support", SUPPORT_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"cannot load benchmark support module: {SUPPORT_PATH}")
SUPPORT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SUPPORT)


class BenchmarkError(RuntimeError):
    pass


class BenchmarkSupportTests(unittest.TestCase):
    def test_load_chainer_rejects_non_repository_with_requested_error(self) -> None:
        with tempfile.TemporaryDirectory() as raw_directory:
            repository = Path(raw_directory)
            with self.assertRaisesRegex(
                BenchmarkError,
                f"not a PeTTaChainer repository: {repository}",
            ):
                SUPPORT.load_chainer(repository, BenchmarkError)

    def test_write_json_uses_stable_pretty_format_with_trailing_newline(self) -> None:
        with tempfile.TemporaryDirectory() as raw_directory:
            output_path = Path(raw_directory) / "result.json"
            payload = {"second": [2, 3], "first": 1}

            SUPPORT.write_json(output_path, payload)

            self.assertEqual(
                output_path.read_text(encoding="utf-8"),
                json.dumps(payload, indent=2, sort_keys=True) + "\n",
            )


if __name__ == "__main__":
    unittest.main()
