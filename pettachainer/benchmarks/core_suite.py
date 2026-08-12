#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import statistics
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, Callable


REPO_ROOT = Path(__file__).resolve().parents[2]


def repository_commit(repository: Path) -> str:
    return subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=repository,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()


def repository_dirty(repository: Path) -> bool:
    return bool(
        subprocess.run(
            ["git", "status", "--porcelain=v1"],
            cwd=repository,
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
    )


def run_json_command(
    repository: Path, arguments: list[str], output_path: Path
) -> Any:
    command = [sys.executable, *arguments, "--json-out", str(output_path)]
    result = subprocess.run(
        command,
        cwd=repository,
        text=True,
        capture_output=True,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"benchmark failed ({' '.join(command)}):\n"
            f"{result.stdout}{result.stderr}"
        )
    return json.loads(output_path.read_text(encoding="utf-8"))


def summary(values: list[float]) -> dict[str, Any]:
    return {
        "mean": statistics.mean(values),
        "median": statistics.median(values),
        "min": min(values),
        "max": max(values),
        "values": values,
    }


def run_workload(
    *,
    name: str,
    repository: Path,
    repetitions: int,
    command: list[str],
    selectors: dict[str, Callable[[Any], float]],
    temporary_directory: Path,
) -> dict[str, Any]:
    collected = {metric: [] for metric in selectors}
    for repetition in range(1, repetitions + 1):
        print(f"[{name}] repetition {repetition}/{repetitions}", file=sys.stderr)
        payload = run_json_command(
            repository,
            command,
            temporary_directory / f"{name}-{repetition}.json",
        )
        for metric, selector in selectors.items():
            collected[metric].append(selector(payload))
    return {metric: summary(values) for metric, values in collected.items()}


def median_metrics(result: dict[str, Any]) -> dict[tuple[str, str], float]:
    return {
        (workload, metric): float(metric_summary["median"])
        for workload, metrics in result["workloads"].items()
        for metric, metric_summary in metrics.items()
    }


def print_comparison(
    result: dict[str, Any], baseline: dict[str, Any] | None = None
) -> None:
    current = median_metrics(result)
    previous = median_metrics(baseline) if baseline else {}
    columns = ["workload", "metric", "median_s"]
    if baseline:
        columns.extend(["baseline_s", "delta"])
    print("\t".join(columns))
    for workload, metric in sorted(current):
        row = [workload, metric, f"{current[(workload, metric)]:.6f}"]
        if baseline:
            old = previous.get((workload, metric))
            if old is None:
                row.extend(["-", "-"])
            else:
                delta = (current[(workload, metric)] / old - 1.0) * 100.0
                row.extend([f"{old:.6f}", f"{delta:+.2f}%"])
        print("\t".join(row))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Run the stable PeTTaChainer performance checks in isolated "
            "processes and optionally compare them with a saved baseline"
        )
    )
    parser.add_argument("--repository", type=Path, default=REPO_ROOT)
    parser.add_argument("--repetitions", type=int, default=3)
    parser.add_argument("--population-members", type=int, default=1000)
    parser.add_argument("--baseline-json", type=Path)
    parser.add_argument("--json-out", type=Path)
    arguments = parser.parse_args(argv)
    repository = arguments.repository.resolve()
    if arguments.repetitions < 1:
        parser.error("--repetitions must be positive")
    if arguments.population_members < 1:
        parser.error("--population-members must be positive")

    benchmark_directory = repository / "pettachainer" / "benchmarks"
    bounded = str(benchmark_directory / "bounded_queue.py")
    member = str(benchmark_directory / "member_inheritance.py")
    for benchmark in (Path(bounded), Path(member)):
        if not benchmark.is_file():
            parser.error(f"benchmark is absent from --repository: {benchmark}")
    with tempfile.TemporaryDirectory(prefix="pettachainer-bench-") as raw_temp:
        temporary_directory = Path(raw_temp)
        workloads = {
            "bounded_backward": run_workload(
                name="bounded-backward",
                repository=repository,
                repetitions=arguments.repetitions,
                command=[
                    bounded,
                    "--fanouts",
                    "500",
                    "--steps",
                    "200",
                    "--repeats",
                    "1",
                    "--mode",
                    "backward",
                ],
                selectors={
                    "setup_seconds": lambda payload: float(payload[0]["setup_s"]),
                    "runtime_seconds": lambda payload: float(payload[0]["run_s"]),
                },
                temporary_directory=temporary_directory,
            ),
            "bounded_forward": run_workload(
                name="bounded-forward",
                repository=repository,
                repetitions=arguments.repetitions,
                command=[
                    bounded,
                    "--fanouts",
                    "500",
                    "--steps",
                    "200",
                    "--repeats",
                    "1",
                    "--mode",
                    "forward",
                ],
                selectors={
                    "setup_seconds": lambda payload: float(payload[0]["setup_s"]),
                    "runtime_seconds": lambda payload: float(payload[0]["run_s"]),
                },
                temporary_directory=temporary_directory,
            ),
            "incremental_member_inheritance": run_workload(
                name="incremental-member-inheritance",
                repository=repository,
                repetitions=arguments.repetitions,
                command=[
                    member,
                    "--candidate-repo",
                    str(repository),
                    "--initial-members",
                    "48",
                    "--deltas",
                    "4",
                    "--query-steps",
                    "400",
                    "--forward-steps",
                    "1",
                ],
                selectors={
                    "initial_load_seconds": lambda payload: float(
                        payload["member_initial_load_seconds"]
                    ),
                    "warm_query_seconds": lambda payload: float(
                        payload["member_warm_query_seconds"]
                    ),
                    "delta_query_seconds": lambda payload: float(
                        payload["member_delta_query_seconds"]
                    ),
                    "delta_total_seconds": lambda payload: float(
                        payload["member_delta_total_seconds"]
                    ),
                },
                temporary_directory=temporary_directory,
            ),
            "forward_member_population": run_workload(
                name="forward-member-population",
                repository=repository,
                repetitions=arguments.repetitions,
                command=[
                    member,
                    "--candidate-repo",
                    str(repository),
                    "--population-mode",
                    "forward-populate",
                    "--initial-members",
                    str(arguments.population_members),
                    "--query-steps",
                    "2",
                    "--forward-steps",
                    "2",
                ],
                selectors={
                    "build_seconds": lambda payload: float(
                        payload["member_population_build_seconds"]
                    ),
                    "final_query_seconds": lambda payload: float(
                        payload["member_population_final_query_seconds"]
                    ),
                    "total_seconds": lambda payload: float(
                        payload["member_population_total_seconds"]
                    ),
                },
                temporary_directory=temporary_directory,
            ),
        }

    result = {
        "schema_version": 1,
        "repository": str(repository),
        "commit": repository_commit(repository),
        "dirty": repository_dirty(repository),
        "parameters": {
            "repetitions": arguments.repetitions,
            "population_members": arguments.population_members,
        },
        "workloads": workloads,
    }
    baseline = None
    if arguments.baseline_json:
        baseline = json.loads(arguments.baseline_json.read_text(encoding="utf-8"))
        if baseline.get("parameters") != result["parameters"]:
            parser.error(
                "baseline parameters differ from this run; use the same "
                "--repetitions and --population-members values"
            )
    print_comparison(result, baseline)
    if arguments.json_out:
        arguments.json_out.write_text(
            json.dumps(result, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        print(f"\nWrote JSON results to {arguments.json_out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
