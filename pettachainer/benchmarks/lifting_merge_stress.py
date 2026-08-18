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


class LiftingMergeStressBenchmarkError(RuntimeError):
    pass


def statements(b_count: int, c_count: int) -> list[str]:
    atoms = ["(: a (A i) (STV 1.0 1.0))"]
    for index in range(1, b_count + 1):
        atoms.append(
            f"(: ab{index} (Implication (A $x) (B $x)) "
            f"(CTV (STV {0.60 + 0.01 * index:.2f} 0.9) (STV 0.0 1.0)))"
        )
    for index in range(1, c_count + 1):
        atoms.append(f"(: cx{index} (X{index} i) (STV 1.0 1.0))")
        atoms.append(
            f"(: cr{index} "
            f"(Implication (And (A $z) (X{index} $z)) (C $z)) "
            f"(CTV (STV {0.60 + 0.01 * index:.2f} 0.9) (STV 0.0 1.0)))"
        )
    return atoms


def validate_results(results: list[Any], query_name: str) -> None:
    if len(results) != 1:
        raise LiftingMergeStressBenchmarkError(
            f"{query_name} query returned {len(results)} results, expected one"
        )
    if query_name == "B" and "merge/revision" not in str(results[0]):
        raise LiftingMergeStressBenchmarkError(
            "B query proof does not contain merge/revision"
        )


def run_benchmark(
    *, repository: Path, b_count: int, c_count: int, repetitions: int
) -> dict[str, Any]:
    if b_count < 2 or c_count < 2 or repetitions < 1:
        raise LiftingMergeStressBenchmarkError(
            "b-count and c-count must be at least two, and repetitions must be positive"
        )

    chainer_type = load_chainer(repository, LiftingMergeStressBenchmarkError)
    handler = chainer_type()
    atoms = statements(b_count, c_count)

    started = time.perf_counter()
    handler.add_atoms_no_check(atoms)
    setup_seconds = time.perf_counter() - started

    b_query = "(: $prf (B i) $tv)"
    c_query = "(: $prf (C i) $tv)"
    started = time.perf_counter()
    cold_b_results = handler.query(b_query, steps=300, timeout_sec=0)
    cold_c_results = handler.query(c_query, steps=500, timeout_sec=0)
    cold_query_seconds = time.perf_counter() - started
    validate_results(cold_b_results, "B")
    validate_results(cold_c_results, "C")

    warm_results: list[tuple[list[Any], list[Any]]] = []
    started = time.perf_counter()
    for _ in range(repetitions):
        warm_results.append(
            (
                handler.query(b_query, steps=300, timeout_sec=0),
                handler.query(c_query, steps=500, timeout_sec=0),
            )
        )
    warm_query_seconds = time.perf_counter() - started
    for b_results, c_results in warm_results:
        validate_results(b_results, "B")
        validate_results(c_results, "C")

    return {
        "b_count": b_count,
        "c_count": c_count,
        "repetitions": repetitions,
        "setup_seconds": setup_seconds,
        "cold_query_seconds": cold_query_seconds,
        "warm_query_seconds": warm_query_seconds,
        "warm_query_per_rep_seconds": warm_query_seconds / repetitions,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Measure cold and warm queries over large direct and conjunction "
            "lifting-merge groups"
        )
    )
    parser.add_argument("--repository", type=Path, default=REPO_ROOT)
    parser.add_argument("--b-count", type=int, default=12)
    parser.add_argument("--c-count", type=int, default=8)
    parser.add_argument("--repetitions", type=int, default=30)
    parser.add_argument("--json-out", type=Path)
    arguments = parser.parse_args(argv)
    try:
        metrics = run_benchmark(
            repository=arguments.repository,
            b_count=arguments.b_count,
            c_count=arguments.c_count,
            repetitions=arguments.repetitions,
        )
    except (LiftingMergeStressBenchmarkError, ImportError) as error:
        print(f"lifting merge stress benchmark failed: {error}", file=sys.stderr)
        return 2
    print(json.dumps(metrics, indent=2, sort_keys=True))
    if arguments.json_out:
        write_json(arguments.json_out, metrics)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
