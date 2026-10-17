"""A failed root read must not hide subsequently stored facts (tracker #79)."""
import json
from pathlib import Path
import subprocess
import sys
import unittest

from pettachainer import PeTTaChainer


class TestLateRootFact(unittest.TestCase):
    def test_empty_root_then_fact_matches_fresh_kb(self):
        # The journal's fast path tests process-wide stores. Isolate cases
        # so a previous rule's versions cannot hide the fact-only defect.
        probe = Path(__file__).parent / "probes" / "late_root_fact.py"
        for name in ("facts_only", "concluding_rule", "cycle"):
            for confidence in (0.8, 1):
                for pre_budget in (0, 300):
                    with self.subTest(rules=name, confidence=confidence, pre_budget=pre_budget):
                        run = subprocess.run(
                            [sys.executable, str(probe), name, str(confidence), str(pre_budget)],
                            capture_output=True, text=True, timeout=90)
                        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
                        result = json.loads(run.stdout.splitlines()[-1])
                        self.assertEqual(result["empty"], [[], [], []])
                        self.assertEqual(result["before"]["Empty"], 1)
                        if name == "facts_only":
                            self.assertEqual(result["before"]["Versions"], 0)
                        for record in result["records"]:
                            with self.subTest(goal=record["goal"], budget=record["budget"]):
                                expected_count = 2 if record["goal"] == "(A $x)" else 1
                                self.assertEqual(len(record["cold"]), expected_count, record)
                                self.assertEqual(record["warm"], record["cold"], record)

    def test_empty_subgoal_then_fact_matches_fresh_kb(self):
        for confidence in (0.8, 1):
            with self.subTest(confidence=confidence):
                warm, cold = PeTTaChainer(), PeTTaChainer()
                rule = "(: (no_inverse de) (Implication (D $x) (E $x)) (STV 1 1))"
                for kb in (warm, cold):
                    kb.add_atom(rule)
                self.assertEqual(warm.query("(: $p (E a) $tv)", steps=300, timeout_sec=0), [])
                for kb in (warm, cold):
                    kb.add_atom(f"(: seed (D a) (STV 1 {confidence}))")
                for goal in ("(D a)", "(E a)"):
                    query = f"(: $p {goal} $tv)"
                    expected = cold.query(query, steps=300, timeout_sec=0)
                    self.assertEqual(len(expected), 1)
                    self.assertEqual(warm.query(query, steps=300, timeout_sec=0), expected)


if __name__ == "__main__":
    unittest.main()
