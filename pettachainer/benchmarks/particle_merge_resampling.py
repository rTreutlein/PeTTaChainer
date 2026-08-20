#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
import re
import resource
import statistics
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Sequence

from _benchmark_support import load_chainer, write_json


REPO_ROOT = Path(__file__).resolve().parents[2]
POINT_PATTERN = re.compile(
    r"\(BenchmarkPoint\s+([^\s()]+)\s+([^\s()]+)\)\s+([^\s()]+)"
)
BENCHMARK_DEFINITIONS = """
(: BenchmarkPointType Type)
(: BenchmarkPoint (-[det]-> Number Number BenchmarkPointType))
(: BenchmarkParticleStateType Type)
(: BenchmarkParticleState
   (-[det]-> (List (Atom Number)) Number Number BenchmarkParticleStateType))
(: benchmark-append-particle
   (-[det]-> (List (Atom Number)) (Atom Number) (List (Atom Number))))
(= (benchmark-append-particle () $particle)
   (cons $particle ()))
(= (benchmark-append-particle (cons $head $rest) $particle)
   (cons $head (benchmark-append-particle $rest $particle)))
(: benchmark-particle-add
   (-[det]-> BenchmarkParticleStateType BenchmarkPointType
       BenchmarkParticleStateType))
(= (benchmark-particle-add
      (BenchmarkParticleState $pairs $count $budget) $point)
   (let*
      (($normalized
          (normalize-pairs
             (benchmark-append-particle
                $pairs
                (particle-value-weight $point (/ 1.0 $count)))))
       ($compressed
          (if (> (list-count $normalized) $budget)
             (coalesce-pairs-to-budget $normalized $budget)
             $normalized)))
      (BenchmarkParticleState $compressed (+ $count 1) $budget)))
"""


class ParticleMergeBenchmarkError(RuntimeError):
    pass


@dataclass(frozen=True)
class Point:
    x: float
    y: float
    cluster: int


def generate_points(count: int, seed: int) -> list[Point]:
    rng = random.Random(seed)
    centers = ((-4.0, -4.0), (-4.0, 4.0), (4.0, -4.0), (4.0, 4.0))
    points = []
    for index in range(count):
        cluster = index % len(centers)
        center_x, center_y = centers[cluster]
        points.append(
            Point(
                rng.gauss(center_x, 0.6),
                rng.gauss(center_y, 0.6),
                cluster,
            )
        )
    return points


def ordered_points(points: Sequence[Point], order: str, seed: int) -> list[Point]:
    result = list(points)
    if order == "clustered":
        result.sort(key=lambda point: point.cluster)
    elif order == "shuffled":
        random.Random(seed + 1).shuffle(result)
    else:
        raise ParticleMergeBenchmarkError(f"unknown point order: {order}")
    return result


def metta_number(value: float) -> str:
    return format(value, ".17g")


def point_term(point: Point) -> str:
    return f"(BenchmarkPoint {metta_number(point.x)} {metta_number(point.y)})"


def incremental_expression(points: Sequence[Point], budget: int) -> str:
    first, *rest = points
    rest_terms = " ".join(point_term(point) for point in rest)
    return (
        "!(let (BenchmarkParticleState $pairs $_count $_budget) "
        "(fold-flat benchmark-particle-add "
        f"(BenchmarkParticleState (({point_term(first)} 1.0)) 1 {budget}) "
        f"({rest_terms})) "
        "$pairs)"
    )


def batch_expression(points: Sequence[Point], budget: int) -> str:
    weight = 1.0 / len(points)
    pairs = " ".join(
        f"({point_term(point)} {metta_number(weight)})" for point in points
    )
    return (
        "!(coalesce-pairs-to-budget "
        f"(normalize-pairs ({pairs})) {budget})"
    )


def raw_eval(handler: Any, expression: str) -> list[str]:
    result = handler.process_metta_string(expression)
    if isinstance(result, str):
        return [result]
    return [str(atom) for atom in result]


def parse_particle_pairs(result: Sequence[str]) -> list[tuple[float, float, float]]:
    if len(result) != 1:
        raise ParticleMergeBenchmarkError(
            f"particle expression returned {len(result)} results, expected one"
        )
    pairs = [
        (float(match.group(1)), float(match.group(2)), float(match.group(3)))
        for match in POINT_PATTERN.finditer(result[0])
    ]
    if not pairs:
        raise ParticleMergeBenchmarkError(
            f"could not parse BenchmarkPoint particles from: {result[0]}"
        )
    return pairs


def weighted_moments(
    pairs: Sequence[tuple[float, float, float]],
) -> tuple[tuple[float, float], tuple[float, float, float]]:
    mass = sum(weight for _, _, weight in pairs)
    mean_x = sum(x * weight for x, _, weight in pairs) / mass
    mean_y = sum(y * weight for _, y, weight in pairs) / mass
    covariance_xx = sum(
        weight * (x - mean_x) ** 2 for x, _, weight in pairs
    ) / mass
    covariance_xy = sum(
        weight * (x - mean_x) * (y - mean_y) for x, y, weight in pairs
    ) / mass
    covariance_yy = sum(
        weight * (y - mean_y) ** 2 for _, y, weight in pairs
    ) / mass
    return (mean_x, mean_y), (covariance_xx, covariance_xy, covariance_yy)


def quality_metrics(
    source: Sequence[Point], compressed: Sequence[tuple[float, float, float]]
) -> dict[str, float]:
    source_pairs = [(point.x, point.y, 1.0 / len(source)) for point in source]
    source_mean, source_covariance = weighted_moments(source_pairs)
    output_mean, output_covariance = weighted_moments(compressed)
    mean_error = math.dist(source_mean, output_mean)
    covariance_error = math.sqrt(
        (source_covariance[0] - output_covariance[0]) ** 2
        + 2.0 * (source_covariance[1] - output_covariance[1]) ** 2
        + (source_covariance[2] - output_covariance[2]) ** 2
    )
    reconstruction_mse = statistics.mean(
        min((point.x - x) ** 2 + (point.y - y) ** 2 for x, y, _ in compressed)
        for point in source
    )
    return {
        "mean_l2_error": mean_error,
        "covariance_frobenius_error": covariance_error,
        "nearest_reconstruction_mse": reconstruction_mse,
    }


def result_digest(pairs: Sequence[tuple[float, float, float]]) -> str:
    payload = json.dumps(list(pairs), separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def validate_result(
    pairs: Sequence[tuple[float, float, float]], budget: int
) -> None:
    if len(pairs) != budget:
        raise ParticleMergeBenchmarkError(
            f"compressed support is {len(pairs)}, expected {budget}"
        )
    mass = sum(weight for _, _, weight in pairs)
    if not math.isclose(mass, 1.0, rel_tol=0.0, abs_tol=1e-9):
        raise ParticleMergeBenchmarkError(
            f"compressed particle mass is {mass}, expected 1.0"
        )
    if not all(math.isfinite(value) for pair in pairs for value in pair):
        raise ParticleMergeBenchmarkError("compressed particles are not finite")


def run_worker(
    *,
    repository: Path,
    mode: str,
    order: str,
    points_count: int,
    budget: int,
    seed: int,
) -> dict[str, Any]:
    chainer_type = load_chainer(repository, ParticleMergeBenchmarkError)
    points = ordered_points(generate_points(points_count, seed), order, seed)
    expression = (
        incremental_expression(points, budget)
        if mode == "incremental"
        else batch_expression(points, budget)
    )
    chainer = chainer_type()
    raw_eval(chainer.handler, BENCHMARK_DEFINITIONS)

    started = time.perf_counter()
    result = raw_eval(chainer.handler, expression)
    elapsed = time.perf_counter() - started

    pairs = parse_particle_pairs(result)
    validate_result(pairs, budget)
    return {
        "seconds": elapsed,
        "points_per_second": points_count / elapsed,
        "peak_rss_kib": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
        "support": len(pairs),
        "mass": sum(weight for _, _, weight in pairs),
        "digest": result_digest(pairs),
        "quality": quality_metrics(points, pairs),
    }


def metric_summary(values: Sequence[float]) -> dict[str, Any]:
    return {
        "mean": statistics.mean(values),
        "median": statistics.median(values),
        "min": min(values),
        "max": max(values),
        "values": list(values),
    }


def run_fresh_worker(
    *,
    repository: Path,
    mode: str,
    order: str,
    points_count: int,
    budget: int,
    seed: int,
) -> dict[str, Any]:
    command = [
        sys.executable,
        str(Path(__file__).resolve()),
        "--worker",
        "--repository",
        str(repository),
        "--mode",
        mode,
        "--order",
        order,
        "--points",
        str(points_count),
        "--budget",
        str(budget),
        "--seed",
        str(seed),
    ]
    completed = subprocess.run(command, text=True, capture_output=True)
    if completed.returncode != 0:
        raise ParticleMergeBenchmarkError(
            f"worker failed ({' '.join(command)}):\n"
            f"{completed.stdout}{completed.stderr}"
        )
    return json.loads(completed.stdout)


def summarize_workload(runs: Sequence[dict[str, Any]]) -> dict[str, Any]:
    digests = {run["digest"] for run in runs}
    if len(digests) != 1:
        raise ParticleMergeBenchmarkError(
            f"repeated runs produced different particle distributions: {digests}"
        )
    quality = runs[0]["quality"]
    for run in runs[1:]:
        if run["quality"] != quality:
            raise ParticleMergeBenchmarkError(
                "repeated runs produced different quality metrics"
            )
    return {
        "seconds": metric_summary([run["seconds"] for run in runs]),
        "points_per_second": metric_summary(
            [run["points_per_second"] for run in runs]
        ),
        "peak_rss_kib": metric_summary([run["peak_rss_kib"] for run in runs]),
        "support": runs[0]["support"],
        "mass": runs[0]["mass"],
        "digest": runs[0]["digest"],
        "quality": quality,
    }


def run_benchmark(
    *,
    repository: Path,
    points_count: int,
    budget: int,
    repetitions: int,
    seed: int,
) -> dict[str, Any]:
    if points_count <= budget:
        raise ParticleMergeBenchmarkError("points must exceed the particle budget")
    if budget < 1 or repetitions < 1:
        raise ParticleMergeBenchmarkError(
            "budget and repetitions must both be positive"
        )
    workloads = (
        ("incremental_clustered", "incremental", "clustered"),
        ("incremental_shuffled", "incremental", "shuffled"),
        ("batch_shuffled_baseline", "batch", "shuffled"),
    )
    results = {}
    for name, mode, order in workloads:
        runs = []
        for repetition in range(1, repetitions + 1):
            print(
                f"[{name}] repetition {repetition}/{repetitions}",
                file=sys.stderr,
            )
            runs.append(
                run_fresh_worker(
                    repository=repository,
                    mode=mode,
                    order=order,
                    points_count=points_count,
                    budget=budget,
                    seed=seed,
                )
            )
        results[name] = summarize_workload(runs)
    return {
        "repository": {
            "path": str(repository),
            "commit": subprocess.run(
                ["git", "rev-parse", "HEAD"],
                cwd=repository,
                check=True,
                capture_output=True,
                text=True,
            ).stdout.strip(),
            "dirty": bool(
                subprocess.run(
                    ["git", "status", "--porcelain=v1"],
                    cwd=repository,
                    check=True,
                    capture_output=True,
                    text=True,
                ).stdout.strip()
            ),
        },
        "config": {
            "points": points_count,
            "budget": budget,
            "repetitions": repetitions,
            "seed": seed,
            "dimensions": 2,
            "distribution": "four_equal_gaussian_clusters",
        },
        "workloads": results,
    }


def print_summary(result: dict[str, Any]) -> None:
    print(
        "workload\tmedian_s\tpoints_per_s\tsupport\tmean_error\t"
        "cov_error\treconstruction_mse"
    )
    for name, workload in result["workloads"].items():
        print(
            "\t".join(
                (
                    name,
                    f"{workload['seconds']['median']:.6f}",
                    f"{workload['points_per_second']['median']:.1f}",
                    str(workload["support"]),
                    f"{workload['quality']['mean_l2_error']:.6g}",
                    f"{workload['quality']['covariance_frobenius_error']:.6g}",
                    f"{workload['quality']['nearest_reconstruction_mse']:.6g}",
                )
            )
        )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Benchmark incremental structured-particle merge resampling, with "
            "one-shot batch compression as a baseline"
        )
    )
    parser.add_argument("--repository", type=Path, default=REPO_ROOT)
    parser.add_argument("--points", type=int, default=1024)
    parser.add_argument("--budget", type=int, default=128)
    parser.add_argument("--repetitions", type=int, default=3)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--json-out", type=Path)
    parser.add_argument("--worker", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument(
        "--mode", choices=("incremental", "batch"), help=argparse.SUPPRESS
    )
    parser.add_argument(
        "--order", choices=("clustered", "shuffled"), help=argparse.SUPPRESS
    )
    arguments = parser.parse_args(argv)
    repository = arguments.repository.resolve()
    try:
        if arguments.worker:
            if arguments.mode is None or arguments.order is None:
                parser.error("--worker requires --mode and --order")
            print(
                json.dumps(
                    run_worker(
                        repository=repository,
                        mode=arguments.mode,
                        order=arguments.order,
                        points_count=arguments.points,
                        budget=arguments.budget,
                        seed=arguments.seed,
                    ),
                    sort_keys=True,
                )
            )
            return 0
        result = run_benchmark(
            repository=repository,
            points_count=arguments.points,
            budget=arguments.budget,
            repetitions=arguments.repetitions,
            seed=arguments.seed,
        )
    except (ImportError, ParticleMergeBenchmarkError) as error:
        print(f"particle merge benchmark failed: {error}", file=sys.stderr)
        return 2
    print_summary(result)
    if arguments.json_out:
        write_json(arguments.json_out, result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
