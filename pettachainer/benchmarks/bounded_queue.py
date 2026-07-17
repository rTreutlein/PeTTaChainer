#!/usr/bin/env python3
import argparse
import json
import os
import statistics
import sys
import time
from dataclasses import asdict, dataclass
from typing import List


THIS_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(THIS_DIR, "..", ".."))
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)

from pettachainer.pettachainer import PeTTaChainer


@dataclass
class BenchmarkRow:
    pruning: str
    mode: str
    fanout: int
    seeds: int
    steps: int
    repeats: int
    setup_s: float
    run_s: float
    result_count: int


def parse_int_list(raw: str) -> List[int]:
    return [int(x.strip()) for x in raw.split(",") if x.strip()]


def mean(values: List[float]) -> float:
    return statistics.mean(values) if values else 0.0


def set_pruning(handler: PeTTaChainer, enabled: bool) -> None:
    value = "true" if enabled else "false"
    handler.handler.process_metta_string(f"!(set-bounded-agenda-pruning {value})")


def build_backward_fanout(handler: PeTTaChainer, fanout: int) -> None:
    atoms = [
        f"(: root_{idx} (Implication (Premises (DeadEnd {idx})) (Conclusions (QueueBenchGoal))) (STV 1.0 1.0))"
        for idx in range(fanout)
    ]
    handler.add_atoms_no_check(atoms)


def build_backward_many_small_fanouts(handler: PeTTaChainer, fanout: int, seeds: int) -> None:
    atoms: List[str] = []
    for seed in range(seeds):
        if seed + 1 < seeds:
            atoms.append(
                f"(: hub_link_{seed} "
                f"(Implication (Premises (QueueBenchHub {seed + 1})) "
                f"(Conclusions (QueueBenchHub {seed}))) "
                f"(STV 1.0 1.0))"
            )
        atoms.extend(
            f"(: dead_{seed}_{idx} "
            f"(Implication (Premises (QueueBenchDeadEnd {seed} {idx})) "
            f"(Conclusions (QueueBenchHub {seed}))) "
            f"(STV 1.0 0.5))"
            for idx in range(fanout)
        )
    handler.add_atoms_no_check(atoms)


def build_forward_fanout(handler: PeTTaChainer, fanout: int) -> None:
    atoms = ["(: seed (QueueBenchSeed) (STV 1.0 1.0))"]
    atoms.extend(
        f"(: fan_{idx} (Implication (Premises (QueueBenchSeed)) (Conclusions (QueueBenchNoise {idx}))) (CTV (STV 1.0 1.0) (STV 0.0 1.0)))"
        for idx in range(fanout)
    )
    handler.add_atoms_no_check(atoms)


def build_forward_many_small_fanouts(handler: PeTTaChainer, fanout: int, seeds: int) -> None:
    atoms = [
        f"(: seed_{seed} (QueueBenchSeed {seed}) (STV 1.0 1.0))"
        for seed in range(seeds)
    ]
    for seed in range(seeds):
        atoms.extend(
            f"(: fan_{seed}_{idx} "
            f"(Implication (Premises (QueueBenchSeed {seed})) "
            f"(Conclusions (QueueBenchNoise {seed} {idx}))) "
            f"(CTV (STV 1.0 0.5) (STV 0.0 1.0)))"
            for idx in range(fanout)
        )
    handler.add_atoms_no_check(atoms)


def time_backward(fanout: int, steps: int, pruning: bool) -> BenchmarkRow:
    handler = PeTTaChainer()
    set_pruning(handler, pruning)
    t0 = time.perf_counter()
    build_backward_fanout(handler, fanout)
    setup_s = time.perf_counter() - t0

    t1 = time.perf_counter()
    results = handler.query("(: $prf (QueueBenchGoal) $tv)", steps=steps, timeout_sec=0)
    run_s = time.perf_counter() - t1
    return BenchmarkRow(
        pruning="on" if pruning else "off",
        mode="backward",
        fanout=fanout,
        seeds=0,
        steps=steps,
        repeats=1,
        setup_s=setup_s,
        run_s=run_s,
        result_count=len(results),
    )


def time_backward_many_small(fanout: int, seeds: int, steps: int, pruning: bool) -> BenchmarkRow:
    handler = PeTTaChainer()
    set_pruning(handler, pruning)
    t0 = time.perf_counter()
    build_backward_many_small_fanouts(handler, fanout, seeds)
    setup_s = time.perf_counter() - t0

    t1 = time.perf_counter()
    results = handler.query("(: $prf (QueueBenchHub 0) $tv)", steps=steps, timeout_sec=0)
    run_s = time.perf_counter() - t1
    return BenchmarkRow(
        pruning="on" if pruning else "off",
        mode="backward_many_small",
        fanout=fanout,
        seeds=seeds,
        steps=steps,
        repeats=1,
        setup_s=setup_s,
        run_s=run_s,
        result_count=len(results),
    )


def time_forward(fanout: int, steps: int, pruning: bool) -> BenchmarkRow:
    handler = PeTTaChainer()
    set_pruning(handler, pruning)
    t0 = time.perf_counter()
    build_forward_fanout(handler, fanout)
    setup_s = time.perf_counter() - t0

    t1 = time.perf_counter()
    results = handler.forward_chain("(QueueBenchSeed)", steps=steps)
    run_s = time.perf_counter() - t1
    return BenchmarkRow(
        pruning="on" if pruning else "off",
        mode="forward",
        fanout=fanout,
        seeds=1,
        steps=steps,
        repeats=1,
        setup_s=setup_s,
        run_s=run_s,
        result_count=len(results),
    )


def time_forward_many_small(fanout: int, seeds: int, steps: int, pruning: bool) -> BenchmarkRow:
    handler = PeTTaChainer()
    set_pruning(handler, pruning)
    t0 = time.perf_counter()
    build_forward_many_small_fanouts(handler, fanout, seeds)
    setup_s = time.perf_counter() - t0

    t1 = time.perf_counter()
    results = handler.forward_chain(
        [f"(QueueBenchSeed {seed})" for seed in range(seeds)], steps=steps
    )
    run_s = time.perf_counter() - t1
    return BenchmarkRow(
        pruning="on" if pruning else "off",
        mode="forward_many_small",
        fanout=fanout,
        seeds=seeds,
        steps=steps,
        repeats=1,
        setup_s=setup_s,
        run_s=run_s,
        result_count=len(results),
    )


def summarize(rows: List[BenchmarkRow], repeats: int) -> List[BenchmarkRow]:
    grouped: dict[tuple[str, str, int, int, int], List[BenchmarkRow]] = {}
    for row in rows:
        grouped.setdefault((row.pruning, row.mode, row.fanout, row.seeds, row.steps), []).append(row)

    summary: List[BenchmarkRow] = []
    for (pruning, mode, fanout, seeds, steps), group in sorted(grouped.items()):
        summary.append(
            BenchmarkRow(
                pruning=pruning,
                mode=mode,
                fanout=fanout,
                seeds=seeds,
                steps=steps,
                repeats=repeats,
                setup_s=mean([row.setup_s for row in group]),
                run_s=mean([row.run_s for row in group]),
                result_count=int(mean([row.result_count for row in group])),
            )
        )
    return summary


def print_table(rows: List[BenchmarkRow]) -> None:
    headers = ["pruning", "mode", "fanout", "seeds", "steps", "repeats", "setup_s", "run_s", "result_count"]
    print("\t".join(headers))
    for row in rows:
        print(
            "\t".join(
                [
                    row.pruning,
                    row.mode,
                    str(row.fanout),
                    str(row.seeds),
                    str(row.steps),
                    str(row.repeats),
                    f"{row.setup_s:.6f}",
                    f"{row.run_s:.6f}",
                    str(row.result_count),
                ]
            )
        )


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Stress PeTTaChainer priority agenda growth. Run the same command on two commits "
            "to compare bounded queue pruning against the old unbounded heap behavior."
        )
    )
    parser.add_argument("--fanouts", default="2000,8000", help="Comma-separated generated agenda fan-outs")
    parser.add_argument("--steps", type=int, default=100, help="Search/forward steps per run")
    parser.add_argument("--repeats", type=int, default=3, help="Repeats per fanout and mode")
    parser.add_argument(
        "--mode",
        choices=["backward", "backward_many_small", "forward", "forward_many_small", "both"],
        default="both",
        help="Which agenda path to benchmark",
    )
    parser.add_argument(
        "--seeds",
        type=int,
        default=100,
        help="Number of independent seed goals for forward_many_small mode",
    )
    parser.add_argument("--json-out", default="", help="Optional JSON output path")
    parser.add_argument(
        "--compare-pruning",
        action="store_true",
        help="Run each benchmark once with pruning enabled and once with pruning disabled",
    )
    args = parser.parse_args()

    rows: List[BenchmarkRow] = []
    pruning_variants = [True, False] if args.compare_pruning else [True]
    for fanout in parse_int_list(args.fanouts):
        for _ in range(args.repeats):
            for pruning in pruning_variants:
                if args.mode in ("backward", "both"):
                    rows.append(time_backward(fanout, args.steps, pruning))
                if args.mode in ("backward_many_small", "both"):
                    rows.append(time_backward_many_small(fanout, args.seeds, args.steps, pruning))
                if args.mode in ("forward", "both"):
                    rows.append(time_forward(fanout, args.steps, pruning))
                if args.mode in ("forward_many_small", "both"):
                    rows.append(time_forward_many_small(fanout, args.seeds, args.steps, pruning))

    summary = summarize(rows, args.repeats)
    print_table(summary)

    if args.json_out:
        with open(args.json_out, "w", encoding="ascii") as f:
            json.dump([asdict(row) for row in summary], f, indent=2)
        print(f"\nWrote JSON results to {args.json_out}")


if __name__ == "__main__":
    main()
