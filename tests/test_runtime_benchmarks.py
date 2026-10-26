from __future__ import annotations

import json
import subprocess
import sys
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
BENCHMARKS = REPO_ROOT / "pettachainer" / "benchmarks"
sys.path.insert(0, str(BENCHMARKS))
try:
    import member_inheritance as MEMBER
finally:
    sys.path.pop(0)


class RuntimeBenchmarkTests(unittest.TestCase):
    def test_member_validator_checks_one_top_level_answer(self):
        expected = dict(expected_strength=0.6, expected_confidence=0.5)
        answer = ("(: proof (Inheritance MemberBenchSubject MemberBenchConcept) "
                  "(STV 0.6 0.5))")
        self.assertEqual(MEMBER.validate_truth_value([answer], **expected), (0.6, 0.5))
        for answers in (
            [], [answer, answer], [answer.replace("MemberBenchSubject", "Wrong")],
            ["(: (nested (STV 0.6 0.5)) "
             "(Inheritance MemberBenchSubject MemberBenchConcept) (STV 0.6 0.1))"],
        ):
            with self.subTest(answers=answers):
                with self.assertRaises(MEMBER.MemberInheritanceBenchmarkError):
                    MEMBER.validate_truth_value(answers, **expected)

    def test_forward_member_population_uses_count_confidence(self):
        result = subprocess.run(
            [sys.executable, str(BENCHMARKS / "member_inheritance.py"),
             "--population-mode", "forward-populate", "--initial-members", "12",
             "--query-steps", "100", "--forward-steps", "2"],
            cwd=REPO_ROOT, text=True, capture_output=True, timeout=60,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        metrics = json.loads(result.stdout)
        self.assertAlmostEqual(metrics["member_population_final_confidence"], 12 / 812)
        self.assertAlmostEqual(metrics["member_population_one_step_confidence"], 12 / 812)
        self.assertEqual(metrics["member_population_final_result_count"], 1)


if __name__ == "__main__":
    unittest.main()
