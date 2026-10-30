"""Verify reuse follows gate inputs, including edits made during a run."""

import contextlib
import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "verify_cache", Path(__file__).resolve().parents[1] / "scripts/verify_cache.py")
cache = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cache)


class VerifyCache(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.repo = Path(scratch.name)
        cache.git(self.repo, "init", "-q")
        self.write(".gitignore", ".venv/\n__pycache__/\nscratch/\n")
        for path in ("pettachainer/core.py", "third_party/lib.metta", "tests/test_core.py",
                     "scripts/verify.sh", "examples/metta/supported.txt", "benchmarks/metta/query.metta",
                     "tools/metta-linter/linter.metta", "lib_pettachainer.metta", "pyproject.toml", "uv.lock",
                     "docs/workflow.md", "GATE_REPORT.md", "README.md"):
            self.write(path, "original\n")
        self.commit()
        self.addCleanup(patch.stopall)
        patch.object(cache, "output", return_value="version").start()
        self.records = self.repo / "scratch/records.jsonl"
        patch.object(cache, "store", return_value=self.records).start()

    def write(self, name, content):
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

    def commit(self):
        cache.git(self.repo, "add", "-A")
        cache.git(self.repo, "-c", "user.name=test", "-c", "user.email=test@example.invalid",
                  "commit", "-qm", "fixture")

    def key(self):
        return cache.key(cache.components(self.repo))

    def run_cache(self, command, *args):
        with contextlib.redirect_stdout(io.StringIO()) as output:
            status = cache.main(command, str(self.repo), *args)
        return status, output.getvalue()

    def test_docs_reports_and_unrelated_files_keep_key_before_and_after_commit(self):
        before = self.key()
        for name in ("docs/workflow.md", "docs/new.md", "GATE_REPORT.md", "NEW_REPORT.md", "README.md", "notes.txt"):
            self.write(name, "edited\n")
        self.assertEqual(before, self.key())
        self.commit()
        self.assertEqual(before, self.key())

    def test_each_gate_input_edit_changes_key(self):
        for name in ("pettachainer/core.py", "third_party/lib.metta", "tests/test_core.py",
                     "scripts/verify.sh", "examples/metta/supported.txt", "benchmarks/metta/query.metta",
                     "tools/metta-linter/linter.metta", "lib_pettachainer.metta", "pyproject.toml", "uv.lock"):
            with self.subTest(path=name):
                before = self.key()
                self.write(name, "edited\n")
                self.assertNotEqual(before, self.key())

    def test_untracked_staged_deleted_and_ignored_inputs(self):
        before = self.key()
        self.write("tests/new.py", "new\n")
        changed = self.key()
        self.assertNotEqual(before, changed)
        cache.git(self.repo, "add", "tests/new.py")
        self.assertEqual(changed, self.key())
        (self.repo / "tests/new.py").unlink()
        self.assertEqual(before, self.key())
        (self.repo / "tests/test_core.py").unlink()
        self.assertNotEqual(before, self.key())
        before = self.key()
        self.write("pettachainer/__pycache__/cache.pyc", "ignored")
        self.assertEqual(before, self.key())

    def test_key_does_not_change_real_index(self):
        self.write("tests/test_core.py", "staged\n")
        cache.git(self.repo, "add", "tests/test_core.py")
        self.write("tests/test_core.py", "unstaged\n")
        before = cache.git(self.repo, "diff", "--cached", "--binary")
        self.key()
        self.assertEqual(before, cache.git(self.repo, "diff", "--cached", "--binary"))

    def test_report_edits_during_run_record_and_reuse_pass(self):
        started = self.key()
        self.write("GATE_REPORT.md", "written during verify\n")
        self.write("docs/workflow.md", "written during verify\n")
        self.assertEqual(self.run_cache("record", started, "PASS", "1")[0], 0)
        self.commit()
        self.assertEqual(self.run_cache("lookup")[0], 0)
        self.assertEqual(json.loads(self.records.read_text())["key"], started)

    def test_gate_edit_during_run_is_not_recorded(self):
        for name in ("pettachainer/core.py", "tests/test_core.py"):
            with self.subTest(path=name):
                started = self.key()
                self.write(name, "changed during verify\n")
                status, output = self.run_cache("record", started, "PASS", "1")
                self.assertEqual(status, 0)
                self.assertIn("result not recorded", output)
                self.assertFalse(self.records.exists())
                self.assertEqual(self.run_cache("lookup")[0], 1)

    def test_newer_failure_withdraws_pass(self):
        started = self.key()
        self.run_cache("record", started, "PASS", "1")
        self.assertEqual(self.run_cache("lookup")[0], 0)
        self.run_cache("record", started, "FAIL", "1")
        self.assertEqual(self.run_cache("lookup")[0], 1)

    def test_petta_runtime_edit_changes_key(self):
        self.write(".venv/lib/python3.10/site-packages/petta/runtime.pl", "runtime\n")
        before = self.key()
        self.write(".venv/lib/python3.10/site-packages/petta/runtime.pl", "changed runtime\n")
        self.assertNotEqual(before, self.key())


if __name__ == "__main__":
    unittest.main()
