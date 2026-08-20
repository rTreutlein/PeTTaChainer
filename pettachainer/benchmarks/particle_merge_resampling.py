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
    r"\(BenchmarkPoint\s+\(([^()]*)\)\)\s+([^\s()]+)"
)
BENCHMARK_DEFINITIONS = """
(: BenchmarkPointType Type)
(: BenchmarkPoint (-[det]-> (List Number) BenchmarkPointType))
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
    coordinates: tuple[float, ...]
    cluster: int


def generate_points(count: int, seed: int, dimensions: int) -> list[Point]:
    rng = random.Random(seed)
    points = []
    for index in range(count):
        cluster = index % 4
        points.append(
            Point(
                tuple(
                    rng.gauss(
                        4.0
                        if cluster & (1 << (dimension % 2))
                        else -4.0,
                        0.6,
                    )
                    for dimension in range(dimensions)
                ),
                cluster,
            )
        )
    return points


def metta_number(value: float) -> str:
    return format(value, ".17g")


def point_term(point: Point) -> str:
    coordinates = " ".join(metta_number(value) for value in point.coordinates)
    return f"(BenchmarkPoint ({coordinates}))"


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


def parse_particle_pairs(
    result: Sequence[str], dimensions: int
) -> list[tuple[tuple[float, ...], float]]:
    if len(result) != 1:
        raise ParticleMergeBenchmarkError(
            f"particle expression returned {len(result)} results, expected one"
        )
    pairs = [
        (
            tuple(float(value) for value in match.group(1).split()),
            float(match.group(2)),
        )
        for match in POINT_PATTERN.finditer(result[0])
    ]
    if not pairs:
        raise ParticleMergeBenchmarkError(
            f"could not parse BenchmarkPoint particles from: {result[0]}"
        )
    if any(len(coordinates) != dimensions for coordinates, _ in pairs):
        raise ParticleMergeBenchmarkError(
            f"compressed particles do not have {dimensions} dimensions"
        )
    return pairs


def weighted_moments(
    pairs: Sequence[tuple[tuple[float, ...], float]],
) -> tuple[tuple[float, ...], tuple[tuple[float, ...], ...]]:
    mass = sum(weight for _, weight in pairs)
    dimensions = len(pairs[0][0])
    mean = tuple(
        sum(coordinates[index] * weight for coordinates, weight in pairs) / mass
        for index in range(dimensions)
    )
    covariance = tuple(
        tuple(
            sum(
                weight
                * (coordinates[row] - mean[row])
                * (coordinates[column] - mean[column])
                for coordinates, weight in pairs
            )
            / mass
            for column in range(dimensions)
        )
        for row in range(dimensions)
    )
    return mean, covariance


def quality_metrics(
    source: Sequence[Point],
    compressed: Sequence[tuple[tuple[float, ...], float]],
) -> dict[str, float]:
    source_pairs = [
        (point.coordinates, 1.0 / len(source)) for point in source
    ]
    source_mean, source_covariance = weighted_moments(source_pairs)
    output_mean, output_covariance = weighted_moments(compressed)
    mean_error = math.dist(source_mean, output_mean)
    covariance_error = math.sqrt(
        sum(
            (source_value - output_value) ** 2
            for source_row, output_row in zip(
                source_covariance, output_covariance
            )
            for source_value, output_value in zip(source_row, output_row)
        )
    )
    reconstruction_mse = statistics.mean(
        min(
            sum(
                (source_value - output_value) ** 2
                for source_value, output_value in zip(
                    point.coordinates, coordinates
                )
            )
            for coordinates, _ in compressed
        )
        for point in source
    )
    return {
        "mean_l2_error": mean_error,
        "covariance_frobenius_error": covariance_error,
        "nearest_reconstruction_mse": reconstruction_mse,
        "nearest_reconstruction_mse_per_dimension": (
            reconstruction_mse / len(source[0].coordinates)
        ),
    }


def result_digest(
    pairs: Sequence[tuple[tuple[float, ...], float]],
) -> str:
    payload = json.dumps(list(pairs), separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def validate_result(
    pairs: Sequence[tuple[tuple[float, ...], float]], budget: int
) -> None:
    if len(pairs) != budget:
        raise ParticleMergeBenchmarkError(
            f"compressed support is {len(pairs)}, expected {budget}"
        )
    mass = sum(weight for _, weight in pairs)
    if not math.isclose(mass, 1.0, rel_tol=0.0, abs_tol=1e-9):
        raise ParticleMergeBenchmarkError(
            f"compressed particle mass is {mass}, expected 1.0"
        )
    if not all(
        math.isfinite(value)
        for coordinates, weight in pairs
        for value in (*coordinates, weight)
    ):
        raise ParticleMergeBenchmarkError("compressed particles are not finite")


def run_worker(
    *,
    repository: Path,
    mode: str,
    points_count: int,
    budget: int,
    dimensions: int,
    seed: int,
) -> dict[str, Any]:
    chainer_type = load_chainer(repository, ParticleMergeBenchmarkError)
    points = generate_points(points_count, seed, dimensions)
    random.Random(seed + 1).shuffle(points)
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

    pairs = parse_particle_pairs(result, dimensions)
    validate_result(pairs, budget)
    return {
        "seconds": elapsed,
        "points_per_second": points_count / elapsed,
        "peak_rss_kib": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
        "support": len(pairs),
        "mass": sum(weight for _, weight in pairs),
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


def repository_metadata(repository: Path) -> dict[str, Any]:
    return {
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
    }


def run_fresh_worker(
    *,
    repository: Path,
    mode: str,
    points_count: int,
    budget: int,
    dimensions: int,
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
        "--points",
        str(points_count),
        "--budget",
        str(budget),
        "--dimensions",
        str(dimensions),
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


def one_factor_configurations(
    *,
    base_points: int,
    base_budget: int,
    base_dimensions: int,
    point_sweep: Sequence[int],
    budget_sweep: Sequence[int],
    dimension_sweep: Sequence[int],
) -> list[dict[str, Any]]:
    configurations: dict[tuple[int, int, int], dict[str, Any]] = {}
    for axis, values in (
        ("points", point_sweep),
        ("budget", budget_sweep),
        ("dimensions", dimension_sweep),
    ):
        for value in values:
            config = {
                "points": base_points,
                "budget": base_budget,
                "dimensions": base_dimensions,
            }
            config[axis] = value
            if config["points"] <= config["budget"]:
                raise ParticleMergeBenchmarkError(
                    f"scaling configuration requires points > budget: {config}"
                )
            if value < 1:
                raise ParticleMergeBenchmarkError(
                    f"scaling values must be positive: {axis}={value}"
                )
            key = (config["points"], config["budget"], config["dimensions"])
            entry = configurations.setdefault(key, {**config, "axes": []})
            entry["axes"].append(axis)
    return list(configurations.values())


def run_scaling_benchmark(
    *,
    repository: Path,
    base_points: int,
    base_budget: int,
    base_dimensions: int,
    point_sweep: Sequence[int],
    budget_sweep: Sequence[int],
    dimension_sweep: Sequence[int],
    repetitions: int,
    seed: int,
) -> dict[str, Any]:
    configurations = one_factor_configurations(
        base_points=base_points,
        base_budget=base_budget,
        base_dimensions=base_dimensions,
        point_sweep=point_sweep,
        budget_sweep=budget_sweep,
        dimension_sweep=dimension_sweep,
    )
    results = []
    for config in configurations:
        result = dict(config)
        result["estimated_candidate_coordinate_comparisons"] = (
            (config["points"] - config["budget"])
            * config["budget"]
            * config["dimensions"]
        )
        for mode in ("incremental", "batch"):
            runs = []
            label = (
                f"{mode} points={config['points']} budget={config['budget']} "
                f"dimensions={config['dimensions']}"
            )
            for repetition in range(1, repetitions + 1):
                print(
                    f"[{label}] repetition {repetition}/{repetitions}",
                    file=sys.stderr,
                )
                runs.append(
                    run_fresh_worker(
                        repository=repository,
                        mode=mode,
                        points_count=config["points"],
                        budget=config["budget"],
                        dimensions=config["dimensions"],
                        seed=seed,
                    )
                )
            result[mode] = summarize_workload(runs)
        results.append(result)
    return {
        "repository": repository_metadata(repository),
        "config": {
            "base_points": base_points,
            "base_budget": base_budget,
            "base_dimensions": base_dimensions,
            "point_sweep": list(point_sweep),
            "budget_sweep": list(budget_sweep),
            "dimension_sweep": list(dimension_sweep),
            "repetitions": repetitions,
            "seed": seed,
            "distribution": "four_equal_gaussian_clusters",
            "order": "shuffled",
        },
        "configurations": results,
    }


def print_scaling_summary(result: dict[str, Any]) -> None:
    print(
        "axes\tpoints\tbudget\tdimensions\tmode\tmedian_s\tpoints_per_s\t"
        "ns_per_candidate_coordinate\treconstruction_mse_per_dimension"
    )
    for config in result["configurations"]:
        comparisons = config["estimated_candidate_coordinate_comparisons"]
        for mode in ("incremental", "batch"):
            workload = config[mode]
            normalized_ns = workload["seconds"]["median"] * 1e9 / comparisons
            print(
                "\t".join(
                    (
                        ",".join(config["axes"]),
                        str(config["points"]),
                        str(config["budget"]),
                        str(config["dimensions"]),
                        mode,
                        f"{workload['seconds']['median']:.6f}",
                        f"{workload['points_per_second']['median']:.1f}",
                        f"{normalized_ns:.3f}",
                        f"{workload['quality']['nearest_reconstruction_mse_per_dimension']:.6g}",
                    )
                )
            )


def positive_int_list(raw: str) -> tuple[int, ...]:
    try:
        values = tuple(int(value.strip()) for value in raw.split(","))
    except ValueError as error:
        raise argparse.ArgumentTypeError(
            "expected comma-separated integers"
        ) from error
    if not values or any(value < 1 for value in values):
        raise argparse.ArgumentTypeError("all sweep values must be positive")
    return values


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Benchmark one-factor scaling of incremental structured-particle "
            "merge resampling, with batch compression as a baseline"
        )
    )
    parser.add_argument("--repository", type=Path, default=REPO_ROOT)
    parser.add_argument("--points", type=int, default=1024)
    parser.add_argument("--budget", type=int, default=128)
    parser.add_argument("--dimensions", type=int, default=2)
    parser.add_argument("--repetitions", type=int, default=1)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--json-out", type=Path)
    parser.add_argument(
        "--point-sweep",
        type=positive_int_list,
        default=positive_int_list("256,512,1024,2048,4096"),
    )
    parser.add_argument(
        "--budget-sweep",
        type=positive_int_list,
        default=positive_int_list("32,64,128,256"),
    )
    parser.add_argument(
        "--dimension-sweep",
        type=positive_int_list,
        default=positive_int_list("1,2,4,8,16"),
    )
    parser.add_argument("--worker", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument(
        "--mode", choices=("incremental", "batch"), help=argparse.SUPPRESS
    )
    arguments = parser.parse_args(argv)
    repository = arguments.repository.resolve()
    try:
        if arguments.worker:
            if arguments.mode is None:
                parser.error("--worker requires --mode")
            print(
                json.dumps(
                    run_worker(
                        repository=repository,
                        mode=arguments.mode,
                        points_count=arguments.points,
                        budget=arguments.budget,
                        dimensions=arguments.dimensions,
                        seed=arguments.seed,
                    ),
                    sort_keys=True,
                )
            )
            return 0
        result = run_scaling_benchmark(
            repository=repository,
            base_points=arguments.points,
            base_budget=arguments.budget,
            base_dimensions=arguments.dimensions,
            point_sweep=arguments.point_sweep,
            budget_sweep=arguments.budget_sweep,
            dimension_sweep=arguments.dimension_sweep,
            repetitions=arguments.repetitions,
            seed=arguments.seed,
        )
    except (ImportError, ParticleMergeBenchmarkError) as error:
        print(f"particle merge benchmark failed: {error}", file=sys.stderr)
        return 2
    print_scaling_summary(result)
    if arguments.json_out:
        write_json(arguments.json_out, result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
