from __future__ import annotations

import contextlib
import io
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


REPO_ROOT = Path(__file__).resolve().parents[1]
BENCHMARKS = REPO_ROOT / "pettachainer" / "benchmarks"
sys.path.insert(0, str(BENCHMARKS))
try:
    import bounded_queue as AGENDA
    import core_suite as CORE
    import member_inheritance as MEMBER
finally:
    sys.path.pop(0)


class RuntimeBenchmarkTests(unittest.TestCase):
    def test_backward_validator_rejects_skipped_work_and_aborts(self):
        arguments = dict(mode="backward", fanout=5, seeds=1, steps=20, kb="kb")
        answers = ["(: (by success seed) (QueueBenchHub 0) "
                   "(STV 1.0 0.49997493871706983))"]
        metrics = dict(search_aborts=0, agenda_pushes=10, agenda_pops=8, expanded_hubs=1)
        AGENDA.validate_results(answers, metrics=metrics, **arguments)
        for bad_answers, bad_metrics in (
            ([], metrics),
            (answers + answers, metrics),
            ([answers[0].replace("success", "wrong_rule")], metrics),
            ([answers[0].replace("1.0", "0.1")], metrics),
            (answers, {**metrics, "search_aborts": 1}),
            (answers, {**metrics, "agenda_pushes": 1}),
            (answers, {**metrics, "agenda_pops": 1}),
        ):
            with self.subTest(answers=bad_answers, metrics=bad_metrics):
                with self.assertRaises(RuntimeError):
                    AGENDA.validate_results(bad_answers, metrics=bad_metrics, **arguments)
        with self.assertRaisesRegex(RuntimeError, "only explored one hub"):
            AGENDA.validate_results(
                answers, metrics=metrics, **{**arguments, "mode": "backward_many_small", "seeds": 3}
            )

    def test_forward_validator_accepts_unordered_complete_seed_groups(self):
        arguments = dict(mode="forward_many_small", fanout=2, seeds=3,
                         steps=2, kb="kb", metrics={})
        answers = [
            f"((QueueBenchNoise {seed} {index}) (kb MAIN Nil) "
            f"(by fan_{seed}_{index} seed_{seed}) (STV 1.0 0.4999749387171011))"
            for seed in (2, 1) for index in (1, 0)
        ]
        AGENDA.validate_results(answers, **arguments)
        for bad_answers in (
            [], answers[:-1], answers + answers[:1],
            [answers[0].replace("fan_2_1", "wrong_rule"), *answers[1:]],
            [answer.replace(" 2", " 3").replace("_2", "_3") for answer in answers],
        ):
            with self.subTest(answers=bad_answers):
                with self.assertRaises(RuntimeError):
                    AGENDA.validate_results(bad_answers, **arguments)

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
        self.assertAlmostEqual(metrics["member_population_cached_confidence"], 12 / 812)
        self.assertEqual(metrics["member_population_final_result_count"], 1)

    def test_core_rejects_incompatible_baseline_before_running(self):
        with tempfile.TemporaryDirectory() as directory:
            baseline = Path(directory) / "baseline.json"
            for payload in (
                {"schema_version": 1},
                {"schema_version": 2, "parameters": {}},
                {"schema_version": 2, "parameters": {
                    "repetitions": 3, "population_members": 1000,
                    "population_query_steps": 100,
                }},
            ):
                baseline.write_text(json.dumps(payload), encoding="utf-8")
                with patch.object(CORE, "run_workload") as run:
                    with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                        CORE.main(["--baseline-json", str(baseline)])
                    run.assert_not_called()

    def test_core_records_and_forwards_the_explicit_population_budget(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "result.json"
            for options, expected in (([], 2), (["--population-query-steps", "7"], 7)):
                with self.subTest(options=options):
                    with patch.object(CORE, "run_workload", return_value={}) as run:
                        with contextlib.redirect_stdout(io.StringIO()):
                            CORE.main(["--population-members", "12", "--json-out", str(output), *options])
                        population = next(call.kwargs for call in run.call_args_list
                                          if call.kwargs["name"] == "forward-member-population")
                    command = population["command"]
                    self.assertEqual(command[command.index("--query-steps") + 1], str(expected))
                    self.assertEqual(json.loads(output.read_text())["parameters"]["population_query_steps"], expected)


if __name__ == "__main__":
    unittest.main()
