"""Landing metrics use committed trees and original branch iteration labels."""

import csv
from datetime import datetime, timezone
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/round_metrics.py"
spec = importlib.util.spec_from_file_location("round_metrics", SCRIPT)
metrics = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metrics)


class RoundMetrics(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.repo = Path(scratch.name) / "repo"
        self.repo.mkdir()
        self.results = Path(scratch.name) / "results"
        metrics.git(self.repo, "init", "-q", "-b", "round-metrics")
        self.write("pettachainer/core.py", "old\n")
        self.write("pettachainer/metta/nested/core.metta", "a\nb\n")
        self.base = self.commit("base")
        self.write("pettachainer/core.py", "new\nmore\n")
        self.write("pettachainer/metta/nested/core.metta", "a\n")
        self.write("pettachainer/metta/native.pl", "native\n")
        self.write("pettachainer/metta/ignore.txt", "ignored\n")
        self.write("pettachainer/nested/ignore.py", "ignored\n")
        self.write("docs/nested/notes.md", "ignored\n")
        self.write("ROUND_METRICS_REPORT.md", "ignored\n")
        self.write("nested/OTHER_REPORT.md", "ignored\n")
        self.first = self.commit("first")
        self.write("other.txt", "one\ntwo\n")
        self.landed = self.commit("second")

    def write(self, name, text):
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def commit(self, message):
        metrics.git(self.repo, "add", ".")
        with patch.dict(os.environ, GIT_AUTHOR_DATE="2026-10-29T12:00:00Z",
                        GIT_COMMITTER_DATE="2026-10-29T12:00:00Z"):
            metrics.git(self.repo, "-c", "user.name=test", "-c", "user.email=test@example.invalid",
                        "commit", "-qm", message)
        return metrics.git(self.repo, "rev-parse", "HEAD").decode().strip()

    def test_append_counts_scope_iterations_and_one_header(self):
        for name, candidate in (("first", [self.first[:8] + "-dirty", self.first, "tree"]),
                                ("second", self.landed[:8]),
                                ("cross", ["pettachainer", self.first[:8], self.first, "tree"]),
                                ("unrelated", [self.base[:8], self.base, "tree"])):
            directory = self.results / "compare" / name
            directory.mkdir(parents=True)
            (directory / "compare.json").write_text(json.dumps({"candidate": candidate}))
        # Working-tree edits must not change token counts or the diff.
        self.write("pettachainer/core.py", "uncommitted\n")
        encoder = types.SimpleNamespace(get_encoding=lambda name: types.SimpleNamespace(
            encode=lambda text, **kwargs: list(text)))
        with patch.dict(sys.modules, tiktoken=encoder):
            metrics.append(self.repo, "round-metrics", self.base, self.landed, self.results)
        with patch.dict(sys.modules, tiktoken=None):
            metrics.append(self.repo, "round-metrics", self.base, self.landed, self.results)
        with (self.results / "round-metrics.csv").open(newline="") as stream:
            rows = list(csv.DictReader(stream))
        self.assertEqual(len(rows), 2)
        row = rows[0]
        self.assertEqual(row["branch"], "round-metrics")
        self.assertEqual(row["base_commit"], self.base)
        self.assertEqual(row["landed_commit"], self.landed)
        self.assertEqual(row["branch_commits"], "2")
        self.assertEqual((row["files_changed"], row["lines_added"], row["lines_removed"]),
                         ("5", "5", "2"))
        self.assertEqual((row["core_tokens_before"], row["core_tokens_after"]), ("8", "18"))
        self.assertEqual(row["compare_reports"], "3")
        self.assertEqual((row["two_way_pairs"], row["cross_functions"], row["widest_interface"]),
                         ("0", "0", "0"))
        self.assertEqual((row["largest_function_scc"], row["functions_in_cycles"]), ("0", "0"))
        self.assertEqual((rows[1]["core_tokens_before"], rows[1]["core_tokens_after"]), ("", ""))
        elapsed = (datetime.fromisoformat(row["date"]) -
                   datetime(2026, 10, 29, 12, tzinfo=timezone.utc)).total_seconds() / 3600
        self.assertAlmostEqual(float(row["hours"]), elapsed, places=6)

    def test_existing_header_extended_without_backfilling_and_landed_tree_measured(self):
        self.results.mkdir()
        path = self.results / "round-metrics.csv"
        with path.open("w", newline="") as stream:
            writer = csv.writer(stream)
            writer.writerow(metrics.HEADER[:-2])
            writer.writerow(["historical"] * len(metrics.HEADER[:-2]))
        self.write("pettachainer/metta/compiler/compile.metta", "(= (compile) (read-one read-two))\n")
        self.write("pettachainer/metta/runtime/forward/rules.metta",
                   "(= (read-one) (compile))\n(= (read-two) True)\n")
        landed = self.commit("coupled")
        # HEAD and the working tree can differ from the landed tree being logged.
        self.write("pettachainer/metta/compiler/compile.metta", "(= (compile) True)\n")
        self.commit("uncoupled")
        with patch.dict(sys.modules, tiktoken=None):
            metrics.append(self.repo, "round-metrics", self.base, landed, self.results)
        with path.open(newline="") as stream:
            rows = list(csv.reader(stream))
        self.assertEqual(rows[0], list(metrics.HEADER))
        self.assertEqual(rows[1], ["historical"] * len(metrics.HEADER[:-2]))
        self.assertEqual(rows[2][-5:], ["1", "3", "2", "2", "2"])

    def test_rename_uses_git_numstat_defaults(self):
        (self.repo / "pettachainer/core.py").rename(self.repo / "pettachainer/renamed\tfile\n.py")
        renamed = self.commit("rename")
        with patch.dict(sys.modules, tiktoken=None):
            metrics.append(self.repo, "round-metrics", self.landed, renamed, self.results)
        with (self.results / "round-metrics.csv").open(newline="") as stream:
            row = next(csv.DictReader(stream))
        self.assertEqual((row["files_changed"], row["lines_added"], row["lines_removed"]),
                         ("1", "0", "0"))

    def test_command_warns_and_succeeds_on_error(self):
        done = subprocess.run([sys.executable, str(SCRIPT), str(self.repo), "missing",
                               self.base, self.landed], capture_output=True, text=True,
                              stdin=subprocess.DEVNULL)
        self.assertEqual(done.returncode, 0)
        self.assertIn("round metrics: warning:", done.stderr)


if __name__ == "__main__":
    unittest.main()
