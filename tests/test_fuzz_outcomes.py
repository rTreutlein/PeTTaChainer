"""Worker outcomes stay distinct through transport, judging and reporting."""
import contextlib
import io
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts import fuzz_vs_problog as fuzz
from tests.fuzz import run
from tests.fuzz.kb import KB


class Outcomes(unittest.TestCase):
    def setUp(self):
        self.kb = KB(["a"], {"A": 0.5}, [], [], queries=[("A", "a")])
        self.settings = run.Settings()
        self.exact = {"exact": [0.5], "prior": [0.5]}
        self.answers = {100: [[[0.5, 1.0, "fact"]]], 2000: [[[0.5, 1.0, "fact"]]]}

    def transport(self, code=0, stdout="", stderr=""):
        with patch.object(run.subprocess, "run", return_value=subprocess.CompletedProcess([], code, stdout, stderr)):
            return run.chainer(self.kb, self.settings)

    def test_supported(self):
        answers = self.transport(stdout="noise\n@@RESULT@@" + json.dumps(self.answers))
        self.assertEqual(answers, self.answers)
        verdict = run.judge(self.kb, self.exact, answers, self.settings)
        self.assertIsNone(verdict.category)
        self.assertEqual(verdict.rows[0]["err"], 0)

    def test_unsupported_exceptions_preserve_feature_and_stage(self):
        label = "slice: unsupported multi-root (planned stage 5)"
        for exception in ("NotImplementedError", "_mm2_chainer.UnsupportedCompilation"):
            with self.subTest(exception=exception):
                answers = self.transport(1, stderr="Traceback (most recent call last):\n" + exception + ": " + label + "\n")
                self.assertEqual(answers, {"unsupported": label})
                verdict = run.judge(self.kb, self.exact, answers, self.settings)
                self.assertEqual(verdict.category, "unsupported")
                self.assertEqual(verdict.unsupported, label)
                self.assertEqual(verdict.flags, [])
                self.assertEqual(verdict.rows, [])
                self.assertIsNone(verdict.error)

    def test_structured_unsupported(self):
        self.assertEqual(self.transport(stdout='@@RESULT@@{"unsupported": "setup: refinement"}'),
                         {"unsupported": "setup: refinement"})
        self.assertEqual(self.transport(1, stderr="NotImplementedError\n"), {"unsupported": "NotImplementedError"})

    def test_supported_query_error_is_not_unsupported_or_crash(self):
        answers = {budget: [[[0.9, 1.0, "fact"]]] for budget in self.settings.budgets}
        verdict = run.judge(self.kb, self.exact, answers, self.settings)
        self.assertEqual(verdict.category, "error")
        self.assertAlmostEqual(verdict.rows[0]["err"], 0.4)
        self.assertIsNone(verdict.unsupported)
        self.assertIsNone(verdict.error)

    def test_crashes_are_not_reclassified(self):
        for code, stderr in ((1, "RuntimeError: unsupported feature"), (-9, ""),
                             (-9, "NotImplementedError: printed before signal"),
                             (1, "NotImplementedError: old failure\nRuntimeError: terminal failure")):
            with self.subTest(code=code, stderr=stderr):
                verdict = run.judge(self.kb, self.exact, self.transport(code, stderr=stderr), self.settings)
                self.assertEqual(verdict.category, "crash")
                self.assertIsNone(verdict.unsupported)
                self.assertTrue(verdict.error)
        with patch.object(run.subprocess, "run", side_effect=subprocess.TimeoutExpired([], 300)):
            self.assertIn("timeout", run.chainer(self.kb, self.settings)["error"])

    def campaign(self, answers, exact=None):
        exact = exact or [self.exact] * len(answers)
        root = run.REPO / "scratch"
        root.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=root) as directory:
            argv = ["fuzz", "--n", str(len(answers)), "--features", "", "--out", directory]
            with patch("sys.argv", argv), patch.object(fuzz, "reexec_capped"), \
                 patch.object(fuzz, "generate", return_value=self.kb), \
                 patch.object(run, "oracle", return_value=exact), \
                 patch.object(run, "chainer", side_effect=answers), \
                 patch.object(fuzz, "minimise") as minimise, contextlib.redirect_stdout(io.StringIO()):
                fuzz.main()
                minimise.assert_not_called()
            out = Path(directory)
            return json.loads((out / "summary.json").read_text()), (out / "summary.md").read_text(), [json.loads(line) for line in (out / "cases.jsonl").read_text().splitlines()]

    def test_zero_supported_unsupported(self):
        label = "slice: unsupported set_base_rate (planned stage 3)"
        summary, report, cases = self.campaign([{"unsupported": label}] * 2)
        self.assertEqual(summary["kbs_unsupported"], 2)
        self.assertEqual(summary["unsupported_reasons"], {label: 2})
        self.assertEqual(summary["flagged_kbs"]["crash"], 0)
        self.assertEqual(summary["flagged_kbs"]["error"], 0)
        self.assertEqual(summary["kbs_skipped"], 0)
        self.assertEqual(summary["kbs_judged"], 0)
        self.assertIsNone(summary["mean_abs_error"])
        self.assertEqual(summary["clusters"], [])
        self.assertIn(label, report)
        self.assertEqual(cases[0]["unsupported"], label)

    def test_zero_supported_crash(self):
        summary, report, _ = self.campaign([{"error": "exit -9"}])
        self.assertEqual(summary["flagged_kbs"]["crash"], 1)
        self.assertEqual(summary["kbs_unsupported"], 0)
        self.assertEqual(summary["kbs_judged"], 0)
        self.assertEqual(summary["clusters"], [])
        self.assertIn("| crash | 1 | 1 |", report)

    def test_mixed_supported_unsupported_crash_and_oracle_skip(self):
        summary, _, _ = self.campaign([self.answers, {"unsupported": "refinement stage 3"}, {"error": "panic"}],
                                     [self.exact, self.exact, self.exact])
        self.assertEqual((summary["kbs_judged"], summary["kbs_unsupported"], summary["flagged_kbs"]["crash"]), (1, 1, 1))
        self.assertEqual(summary["answered"], 1)
        self.assertEqual(summary["mean_abs_error"], 0)
        summary, _, cases = self.campaign([{}], [{"error": "impossible evidence"}])
        self.assertEqual(summary["kbs_skipped"], 1)
        self.assertEqual(summary["kbs_unsupported"], 0)
        self.assertIn("skipped", cases[0])


if __name__ == "__main__":
    unittest.main()
