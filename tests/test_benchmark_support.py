from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch


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

    def test_load_chainer_rejects_a_module_cached_from_another_checkout(self) -> None:
        with tempfile.TemporaryDirectory() as raw_directory:
            other_module = SimpleNamespace(
                __file__=str(Path(raw_directory) / "pettachainer" / "pettachainer.py")
            )
            with patch.object(SUPPORT.importlib, "import_module", return_value=other_module):
                with self.assertRaisesRegex(BenchmarkError, "loaded PeTTaChainer from"):
                    SUPPORT.load_chainer(REPO_ROOT, BenchmarkError)


if __name__ == "__main__":
    unittest.main()
