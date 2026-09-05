#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import math
import re
import statistics
import sys
import time
from pathlib import Path
from typing import Any

from _benchmark_support import load_chainer, write_json


REPO_ROOT = Path(__file__).resolve().parents[2]
ANSWER = re.compile(
    r"\(: \(by refinementMap \(conjunction refinementSeed "
    r"\(conjunction refinementLength refinementWidth\)\)\) "
    r"\(RefinementArea rectangle \(ParticleDist (\d+) 1\.0\)\) "
    r"\(STV ([^ ]+) ([^)]+)\)\)"
)


class RefinementBenchmarkError(RuntimeError):
    pass


def run_benchmark(*, repository: Path, queries: int, steps: int) -> dict[str, Any]:
    if queries < 2 or steps < 1:
        raise RefinementBenchmarkError("queries must exceed one and steps must be positive")
    chainer_type = load_chainer(repository, RefinementBenchmarkError)
    started = time.perf_counter()
    handler = chainer_type()
    handler.add_atoms_no_check(
        [
            "(: refinementSeed (RefinementRectangle rectangle) (STV 1.0 1.0))",
            "(: refinementLength (RefinementLength rectangle "
            "(ParticleFromNormal 10.0 1.0)) (STV 1.0 1.0))",
            "(: refinementWidth (RefinementWidth rectangle "
            "(ParticleFromNormal 5.0 0.5)) (STV 1.0 1.0))",
            "(: refinementMap (Implication "
            "(And (RefinementRectangle $r) "
            "(Map2Dist * (RefinementLength $r $length) $length "
            "(RefinementWidth $r $width) $width -> $area)) "
            "(RefinementArea $r $area)) "
            "(CTV (STV 1.0 1.0) (STV 0.0 1.0)))",
        ]
    )
    setup_seconds = time.perf_counter() - started
    query_seconds: list[float] = []
    draws: set[int] = set()
    for repetition in range(queries):
        started = time.perf_counter()
        answers = handler.query(
            "(: $proof (RefinementArea rectangle $area) $tv)",
            steps=steps,
            timeout_sec=0,
        )
        query_seconds.append(time.perf_counter() - started)
        matched = ANSWER.fullmatch(str(answers[0])) if len(answers) == 1 else None
        if matched is None:
            raise RefinementBenchmarkError(
                f"query {repetition + 1} did not return the expected complete proof: {answers}"
            )
        draw, strength, confidence = matched.groups()
        if int(draw) in draws or not math.isclose(float(strength), 1.0) or not math.isclose(
            float(confidence), 0.999700089898053, rel_tol=1e-12
        ):
            raise RefinementBenchmarkError(
                f"query {repetition + 1} reused an old draw or changed its TV: {answers}"
            )
        draws.add(int(draw))
    # Read the actual final distribution outside the measured query window.
    particle_rows = handler.handler.process_metta_string(
        f"!(ParticlePairs (ParticleDist {draw} 1.0))"
    )
    pairs = [
        (float(value), float(weight))
        for value, weight in re.findall(
            r"\(([^()\s]+) ([^()\s]+)\)", str(particle_rows[0])
        )
    ]
    mass = sum(weight for _, weight in pairs)
    weighted_mean = sum(value * weight for value, weight in pairs)
    if len(particle_rows) != 1 or not math.isclose(mass, 1.0, rel_tol=1e-12) or not math.isclose(
        weighted_mean, 50.0, rel_tol=1e-12
    ):
        raise RefinementBenchmarkError(
            f"final distribution has mass {mass} and weighted mean {weighted_mean}, expected 1 and 50"
        )
    counts = handler.handler.process_metta_string(
        "!((length (collapse (get-atoms &proof_derivation))) "
        "(length (collapse (get-atoms &proof))))"
    )
    matched_counts = re.fullmatch(r"\((\d+) (\d+)\)", str(counts[0]))
    if len(counts) != 1 or matched_counts is None:
        raise RefinementBenchmarkError(f"could not read retained proof counts: {counts}")
    derivation_rows, proof_rows = map(int, matched_counts.groups())
    window = min(10, queries // 2)
    return {
        "queries": queries,
        "steps": steps,
        "setup_seconds": setup_seconds,
        "query_seconds": query_seconds,
        "query_total_seconds": sum(query_seconds),
        "window_queries": window,
        "first_window_median_seconds": statistics.median(query_seconds[:window]),
        "last_window_median_seconds": statistics.median(query_seconds[-window:]),
        "fresh_results": len(draws),
        "final_distribution_mass": mass,
        "final_distribution_mean": weighted_mean / mass,
        "derivation_index_rows": derivation_rows,
        "durable_proof_rows": proof_rows,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Measure repeated refinement of one sampling derivation with fixed evidence"
    )
    parser.add_argument("--repository", type=Path, default=REPO_ROOT)
    parser.add_argument("--queries", type=int, default=25)
    parser.add_argument("--steps", type=int, default=20)
    parser.add_argument("--json-out", type=Path)
    arguments = parser.parse_args(argv)
    try:
        metrics = run_benchmark(
            repository=arguments.repository,
            queries=arguments.queries,
            steps=arguments.steps,
        )
    except (RefinementBenchmarkError, ImportError) as error:
        print(f"refinement benchmark failed: {error}", file=sys.stderr)
        return 2
    print(json.dumps(metrics, indent=2, sort_keys=True))
    if arguments.json_out:
        write_json(arguments.json_out, metrics)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
