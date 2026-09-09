"""A fast run with identical actions must not hide a diagnosis regression."""
import copy
import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location(
    "stationops_quality_gate",
    Path(__file__).resolve().parents[1] / "benchmarks/stationops/quality_gate.py",
)
GATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GATE)


class QualityGateTests(unittest.TestCase):
    def setUp(self):
        errors = dict(mean_absolute_error=0.1, max_absolute_error=0.2,
                      brier_score=0.03, log_loss=0.14)
        self.reference = dict(
            workload=dict(seed=7, shifts=1, budget=600),
            batches=[dict(shift=1, seconds=90, metrics=dict(search_aborts=0))],
            result=dict(rounds=[dict(
                shift=1, beliefs=dict(A=0.7), decision_beliefs=dict(A=0.7),
                belief_metrics=errors, decision_belief_metrics=copy.deepcopy(errors),
                visible_incidents=["A", "B"], regret=0)],
                aggregate=dict(station_score=637)),
        )
        self.candidate = copy.deepcopy(self.reference)
        self.candidate["batches"][0]["seconds"] = 30

    def test_equal_quality_faster_passes(self):
        self.assertTrue(GATE.compare_quality(self.reference, self.candidate)["passed"])

    def test_same_score_and_coverage_worse_probabilities_fails(self):
        self.candidate["result"]["rounds"][0]["belief_metrics"]["brier_score"] = 0.16
        result = GATE.compare_quality(self.reference, self.candidate)
        self.assertFalse(result["passed"])
        self.assertIn("shift 1 beliefs: worse brier_score", result["failures"])

    def test_equal_coverage_different_answered_goal_fails(self):
        self.candidate["result"]["rounds"][0]["beliefs"] = dict(B=0.7)
        result = GATE.compare_quality(self.reference, self.candidate)
        self.assertFalse(result["passed"])
        self.assertTrue(result["failures"])
        self.assertTrue(result["unresolved"])

    def test_more_coverage_requires_comparable_errors(self):
        self.candidate["result"]["rounds"][0]["beliefs"]["B"] = 0.2
        result = GATE.compare_quality(self.reference, self.candidate)
        self.assertFalse(result["passed"])
        self.assertEqual(result["failures"], [])
        self.assertTrue(result["unresolved"])

    def test_aborted_search_fails_even_with_same_answers(self):
        self.candidate["batches"][0]["metrics"]["search_aborts"] = 1
        self.assertFalse(GATE.compare_quality(self.reference, self.candidate)["passed"])

    def test_different_budget_is_rejected(self):
        self.candidate["workload"]["budget"] = 1200
        with self.assertRaisesRegex(ValueError, "Workloads differ"):
            GATE.compare_quality(self.reference, self.candidate)

    def test_missing_shift_is_rejected(self):
        self.candidate["batches"] = []
        with self.assertRaisesRegex(ValueError, "Incomplete episode"):
            GATE.compare_quality(self.reference, self.candidate)

    def test_changed_proposals_are_not_changed_episode_inputs(self):
        for run in (self.reference, self.candidate):
            run["workload"]["shifts"] = 2
            row = run["result"]["rounds"][0]
            row.update(inspections={"A": "intact"}, chosen_repairs=[], resolution={})
            row["action_trace"] = [{"proposals": [], "selected": None}]
            run["result"]["rounds"].append(copy.deepcopy(row))
            run["result"]["rounds"][1]["shift"] = 2
            run["batches"].append(dict(shift=2, seconds=30, metrics=dict(search_aborts=0)))
        self.candidate["result"]["rounds"][0]["action_trace"][0]["proposals"] = ["other estimate"]
        self.assertTrue(GATE.compare_quality(self.reference, self.candidate)["passed"])
        self.candidate["result"]["rounds"][0]["inspections"] = {"B": "intact"}
        self.assertTrue(GATE.compare_quality(self.reference, self.candidate)["unresolved"])


if __name__ == "__main__":
    unittest.main()
