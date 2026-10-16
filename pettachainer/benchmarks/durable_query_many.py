#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path
from typing import Any

from _benchmark_support import load_chainer, write_json


REPO_ROOT = Path(__file__).resolve().parents[2]


class DurableQueryBenchmarkError(RuntimeError):
    pass


def initial_statements(stable_roots: int) -> list[str]:
    stable = [
        (
            f"(: retainedStableRule{root} "
            f"(Implication (RetainedStableSeed {root}) (RetainedStableGoal {root})) "
            f"(CTV (STV 1.0 1.0) (STV 0.0 1.0)))"
        )
        for root in range(stable_roots)
    ]
    seeds = [
        f"(: retainedStableSeed{root} "
        f"(RetainedStableSeed {root}) (STV 1.0 0.8))"
        for root in range(stable_roots)
    ]
    return [
        (
            "(: retainedEvolvingRule "
            "(Implication "
            "(And (RetainedShared $shift) (RetainedSignal $root $shift)) "
            "(RetainedEvolvingGoal $root $shift)) "
            "(CTV (STV 1.0 1.0) (STV 0.0 1.0)))"
        ),
        *stable,
        *seeds,
    ]


def shift_statements(shift: int, evolving_roots: int) -> list[str]:
    return [
        f"(: retainedShared{shift} (RetainedShared {shift}) (STV 1.0 0.8))",
        *[
            f"(: retainedSignal{root}_{shift} "
            f"(RetainedSignal {root} {shift}) (STV 1.0 0.8))"
            for root in range(evolving_roots)
        ],
    ]


def goals(stable_roots: int, evolving_roots: int, shift: int) -> list[str]:
    return [f"(RetainedStableGoal {root})" for root in range(stable_roots)] + [
        f"(RetainedEvolvingGoal {root} {shift})" for root in range(evolving_roots)
    ]


def queries(stable_roots: int, evolving_roots: int, shift: int) -> list[str]:
    return [
        f"(: $retainedProof {goal} $retainedTV)"
        for goal in goals(stable_roots, evolving_roots, shift)
    ]


def run_benchmark(
    *, repository: Path, roots: int, stable_roots: int, shifts: int, steps: int
) -> dict[str, Any]:
    if roots < 2 or not 0 < stable_roots < roots or shifts < 2 or steps < 1:
        raise DurableQueryBenchmarkError(
            "roots must exceed one, stable-roots must be between zero and roots, "
            "steps must be positive, and shifts must be at least two"
        )

    chainer_type = load_chainer(repository, DurableQueryBenchmarkError)
    started = time.perf_counter()
    handler = chainer_type()
    handler.add_atoms_no_check(initial_statements(stable_roots))
    setup_seconds = time.perf_counter() - started

    evolving_roots = roots - stable_roots
    shift_seconds: list[float] = []
    shift_answer_counts: list[int] = []
    for shift in range(shifts):
        handler.add_atoms_no_check(shift_statements(shift, evolving_roots))
        started = time.perf_counter()
        answers = handler.query_many(
            queries(stable_roots, evolving_roots, shift), steps=steps, timeout_sec=0
        )
        shift_seconds.append(time.perf_counter() - started)
        wrong = [
            root
            for root, (root_answers, goal) in enumerate(
                zip(answers, goals(stable_roots, evolving_roots, shift))
            )
            if len(root_answers) != 1 or goal not in root_answers[0]
        ]
        if wrong:
            raise DurableQueryBenchmarkError(
                f"shift {shift + 1} did not prove roots {wrong} with exactly one answer"
            )
        shift_answer_counts.append(sum(map(len, answers)))

    return {
        "roots": roots,
        "stable_roots": stable_roots,
        "shifts": shifts,
        "steps": steps,
        "setup_seconds": setup_seconds,
        "shift_seconds": shift_seconds,
        "shift_answer_counts": shift_answer_counts,
        "query_total_seconds": sum(shift_seconds),
        "first_query_seconds": shift_seconds[0],
        "final_query_seconds": shift_seconds[-1],
        "max_query_seconds": max(shift_seconds),
        "final_to_first_ratio": shift_seconds[-1] / shift_seconds[0],
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Measure fixed-budget query_many calls while proofs survive across "
            "small monotonic knowledge additions"
        )
    )
    parser.add_argument("--repository", type=Path, default=REPO_ROOT)
    parser.add_argument("--roots", type=int, default=8)
    parser.add_argument("--stable-roots", type=int, default=2)
    parser.add_argument("--shifts", type=int, default=5)
    parser.add_argument("--steps", type=int, default=300)
    parser.add_argument("--json-out", type=Path)
    arguments = parser.parse_args(argv)
    try:
        metrics = run_benchmark(
            repository=arguments.repository,
            roots=arguments.roots,
            stable_roots=arguments.stable_roots,
            shifts=arguments.shifts,
            steps=arguments.steps,
        )
    except (DurableQueryBenchmarkError, ImportError) as error:
        print(f"durable query benchmark failed: {error}", file=sys.stderr)
        return 2
    print(json.dumps(metrics, indent=2, sort_keys=True))
    if arguments.json_out:
        write_json(arguments.json_out, metrics)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
