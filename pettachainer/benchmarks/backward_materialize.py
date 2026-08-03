#!/usr/bin/env python3
import argparse
import json
import os
import re
import statistics
import subprocess
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import List


THIS_DIR = Path(__file__).resolve().parent
REPO_ROOT = THIS_DIR.parent.parent
METTA_DIR = REPO_ROOT / "pettachainer" / "metta"
GENERATED_DIR = METTA_DIR / "benchmarks"


@dataclass
class BenchmarkRow:
    mode: str
    depth: int
    queries: int
    repeats: int
    rules: int
    initial_facts: int
    query_steps: int
    cached_steps: int
    plain_batch_s: float
    materialize_first_s: float
    materialized_tail_s: float
    materialized_batch_s: float
    total_speedup: float
    tail_speedup: float
    petta_wall_s: float


def parse_int_list(raw: str) -> List[int]:
    return [int(x.strip()) for x in raw.split(",") if x.strip()]


def reach_type(bench: str, level: int) -> str:
    return f"(MatReach {bench} {level})"


def target_type(bench: str, target: int) -> str:
    return f"(MatTarget {bench} {target})"


def target_query(bench: str, target: int) -> str:
    return f"(: $prf {target_type(bench, target)} $tv)"


def query_budget(depth: int) -> int:
    return max(10, 2 * (depth + 1))


def compile_commands(kb: str, bench: str, depth: int, targets: int, prefix: str) -> List[str]:
    commands = [f"!(compileadd {kb} (: {prefix}_seed {reach_type(bench, 0)} (STV 1.0 1.0)))"]
    for level in range(depth):
        commands.append(
            f"!(compileadd {kb} "
            f"(: {prefix}_step_{level} "
            f"(Implication {reach_type(bench, level)} "
            f"{reach_type(bench, level + 1)}) "
            f"(STV 1.0 1.0)))"
        )
    for target in range(targets):
        commands.append(
            f"!(compileadd {kb} "
            f"(: {prefix}_target_{target} "
            f"(Implication {reach_type(bench, depth)} "
            f"{target_type(bench, target)}) "
            f"(STV 1.0 1.0)))"
        )
    return commands


def query_bindings(kb: str, bench: str, targets: int, steps: int, prefix: str, query_fun: str) -> List[str]:
    return [
        f"($_{prefix}_{target} (collapse ({query_fun} {steps} {kb} {target_query(bench, target)})))"
        for target in range(targets)
    ]


def query_binding(kb: str, bench: str, target: int, steps: int, prefix: str, query_fun: str) -> str:
    return f"($_{prefix}_{target} (collapse ({query_fun} {steps} {kb} {target_query(bench, target)})))"


def repeated_query_bindings(
    kb: str,
    bench: str,
    query_targets: List[int],
    steps: int,
    prefix: str,
    query_fun: str,
) -> List[str]:
    return [
        f"($_{prefix}_{idx} (collapse ({query_fun} {steps} {kb} {target_query(bench, target)})))"
        for idx, target in enumerate(query_targets)
    ]


def generated_program(mode: str, depth: int, queries: int, cached_steps: int, repeat: int) -> str:
    steps = query_budget(depth)
    target_count = queries if mode == "sibling-targets" else 1
    plain_kb = f"matPlainKb_{mode}_{depth}_{queries}_{repeat}"
    materialized_kb = f"matCachedKb_{mode}_{depth}_{queries}_{repeat}"
    plain_bench = f"plainBench_{mode}_{depth}_{queries}_{repeat}"
    materialized_bench = f"cachedBench_{mode}_{depth}_{queries}_{repeat}"
    plain_targets = list(range(queries)) if mode == "sibling-targets" else [0 for _ in range(queries)]
    cached_tail_targets = list(range(1, queries)) if mode == "sibling-targets" else [0 for _ in range(max(0, queries - 1))]

    setup: List[str] = []
    setup.extend(compile_commands(plain_kb, plain_bench, depth, target_count, "p"))
    setup.extend(compile_commands(materialized_kb, materialized_bench, depth, target_count, "m"))
    bindings: List[str] = []
    bindings.append("($plain-start (current-time))")
    bindings.extend(repeated_query_bindings(plain_kb, plain_bench, plain_targets, steps, "plain_q", "query"))
    bindings.append("($plain-end (current-time))")
    bindings.append("($materialize-start (current-time))")
    bindings.append(
        f"($_materialize_first "
        f"(collapse (query-materialize {steps} {materialized_kb} {target_query(materialized_bench, 0)})))"
    )
    bindings.append("($materialize-first-end (current-time))")
    bindings.extend(
        query_binding(materialized_kb, materialized_bench, target, steps, "cached_tail", "query")
        if cached_steps == steps
        else query_binding(materialized_kb, materialized_bench, target, cached_steps, "cached_tail", "query")
        for target in cached_tail_targets
    )
    bindings.append("($materialize-end (current-time))")

    binding_text = "\n      ".join(bindings)
    return (
        "!(import! &self petta_chainer)\n\n"
        + "\n".join(setup)
        + "\n\n"
        "!(let*\n"
        f"   ({binding_text})\n"
        "   (bench-materialize-row\n"
        f"      (mode {mode})\n"
        f"      (depth {depth})\n"
        f"      (queries {queries})\n"
        f"      (query-steps {steps})\n"
        f"      (cached-steps {cached_steps})\n"
        "      (plain-seconds (- $plain-end $plain-start))\n"
        "      (materialize-first-seconds (- $materialize-first-end $materialize-start))\n"
        "      (materialized-tail-seconds (- $materialize-end $materialize-first-end))\n"
        "      (materialized-batch-seconds (- $materialize-end $materialize-start))))\n"
    )


def parse_seconds(output: str, key: str) -> float:
    match = re.search(rf"\({re.escape(key)} ([0-9eE+\-.]+)\)", output)
    if not match:
        raise RuntimeError(f"Could not parse {key} from petta output:\n{output[-2000:]}")
    return float(match.group(1))


def run_petta_benchmark(
    mode: str, depth: int, queries: int, cached_steps: int, repeat: int
) -> tuple[float, float, float, float, float]:
    script_name = f".generated_backward_materialize_{os.getpid()}_{mode}_{depth}_{queries}_{repeat}.metta"
    script_path = GENERATED_DIR / script_name
    script_path.write_text(generated_program(mode, depth, queries, cached_steps, repeat), encoding="ascii")
    try:
        t0 = time.perf_counter()
        result = subprocess.run(
            ["petta", f"benchmarks/{script_name}"],
            cwd=METTA_DIR,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        wall_s = time.perf_counter() - t0
        if result.returncode != 0:
            raise RuntimeError(
                f"petta failed with exit code {result.returncode} for {script_name}:\n{result.stdout[-4000:]}"
            )
    finally:
        try:
            script_path.unlink()
        except FileNotFoundError:
            pass

    output = result.stdout
    plain_s = parse_seconds(output, "plain-seconds")
    first_s = parse_seconds(output, "materialize-first-seconds")
    tail_s = parse_seconds(output, "materialized-tail-seconds")
    batch_s = parse_seconds(output, "materialized-batch-seconds")
    return plain_s, first_s, tail_s, batch_s, wall_s


def print_table(rows: List[BenchmarkRow]) -> None:
    headers = [
        "depth",
        "mode",
        "queries",
        "rules",
        "query_steps",
        "cached_steps",
        "plain_batch_s",
        "materialize_first_s",
        "materialized_tail_s",
        "materialized_batch_s",
        "total_speedup",
        "tail_speedup",
        "petta_wall_s",
    ]
    print("\t".join(headers))
    for row in rows:
        print(
            "\t".join(
                [
                    str(row.depth),
                    row.mode,
                    str(row.queries),
                    str(row.rules),
                    str(row.query_steps),
                    str(row.cached_steps),
                    f"{row.plain_batch_s:.6f}",
                    f"{row.materialize_first_s:.6f}",
                    f"{row.materialized_tail_s:.6f}",
                    f"{row.materialized_batch_s:.6f}",
                    f"{row.total_speedup:.3f}",
                    f"{row.tail_speedup:.3f}",
                    f"{row.petta_wall_s:.6f}",
                ]
            )
        )


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Compare repeated backward queries against one query-materialize pass plus "
            "subsequent queries that can reuse materialized intermediate facts."
        )
    )
    parser.add_argument("--depths", default="5", help="Comma-separated shared chain depths")
    parser.add_argument(
        "--queries",
        type=int,
        default=20,
        help="Number of repeated queries to answer per benchmark row",
    )
    parser.add_argument(
        "--mode",
        choices=("same-target", "sibling-targets"),
        default="same-target",
        help="same-target repeats one query; sibling-targets queries related targets sharing the deepest chain fact",
    )
    parser.add_argument("--repeats", type=int, default=3, help="Repeats per depth")
    parser.add_argument(
        "--cached-steps",
        type=int,
        default=0,
        help="Step budget after the materializing query; defaults to 1 for same-target and 2 for sibling-targets",
    )
    parser.add_argument("--json-out", default="", help="Optional JSON output file path")
    args = parser.parse_args()

    if args.queries < 1:
        raise ValueError("--queries must be at least 1")

    cached_steps = args.cached_steps
    if cached_steps <= 0:
        cached_steps = 1 if args.mode == "same-target" else 2

    rows: List[BenchmarkRow] = []
    for depth in parse_int_list(args.depths):
        plain_runs: List[float] = []
        materialize_first_runs: List[float] = []
        materialized_tail_runs: List[float] = []
        materialized_batch_runs: List[float] = []
        petta_wall_runs: List[float] = []

        for repeat in range(args.repeats):
            plain_s, first_s, tail_s, batch_s, wall_s = run_petta_benchmark(
                args.mode, depth, args.queries, cached_steps, repeat
            )
            plain_runs.append(plain_s)
            materialize_first_runs.append(first_s)
            materialized_tail_runs.append(tail_s)
            materialized_batch_runs.append(batch_s)
            petta_wall_runs.append(wall_s)

        plain_batch_s = statistics.mean(plain_runs)
        materialize_first_s = statistics.mean(materialize_first_runs)
        materialized_tail_s = statistics.mean(materialized_tail_runs)
        materialized_batch_s = statistics.mean(materialized_batch_runs)
        plain_tail_estimate_s = plain_batch_s * max(0, args.queries - 1) / args.queries

        rows.append(
            BenchmarkRow(
                mode=args.mode,
                depth=depth,
                queries=args.queries,
                repeats=args.repeats,
                rules=depth + (args.queries if args.mode == "sibling-targets" else 1),
                initial_facts=1,
                query_steps=query_budget(depth),
                cached_steps=cached_steps,
                plain_batch_s=plain_batch_s,
                materialize_first_s=materialize_first_s,
                materialized_tail_s=materialized_tail_s,
                materialized_batch_s=materialized_batch_s,
                total_speedup=(plain_batch_s / materialized_batch_s) if materialized_batch_s > 0 else 0.0,
                tail_speedup=(
                    plain_tail_estimate_s / materialized_tail_s
                    if materialized_tail_s > 0 and args.queries > 1
                    else 0.0
                ),
                petta_wall_s=statistics.mean(petta_wall_runs),
            )
        )

    print_table(rows)

    if args.json_out:
        with open(args.json_out, "w", encoding="ascii") as f:
            json.dump([asdict(row) for row in rows], f, indent=2)
        print(f"\nWrote JSON results to {args.json_out}")


if __name__ == "__main__":
    main()
