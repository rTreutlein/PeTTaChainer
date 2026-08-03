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

NOISE_CONFIDENCE = "0.000001"


@dataclass
class BenchmarkRow:
    depth: int
    noise_branching: int
    repeats: int
    rules: int
    initial_facts: int
    reachable_facts: int
    forward_goal_steps: int
    forward_full_steps: int
    backward_s: float
    forward_goal_s: float
    forward_full_s: float
    forward_goal_over_backward: float
    forward_full_over_backward: float


def parse_int_list(raw: str) -> List[int]:
    return [int(x.strip()) for x in raw.split(",") if x.strip()]


def goal_symbol(i: int) -> str:
    return f"g{i}"


def noise_symbol(depth_i: int, branch_i: int) -> str:
    return f"noise_{depth_i}_{branch_i}"


def target_query(depth: int) -> str:
    return f"(: $prf (Reach {goal_symbol(depth)}) $tv)"


def query_budget(depth: int) -> int:
    return max(10, 2 * depth)


def expected_reachable_facts(depth: int, noise_branching: int) -> int:
    return (depth + 1) + (depth * noise_branching)


def build_chain_problem(handler: PeTTaChainer, depth: int, noise_branching: int) -> None:
    handler.add_atom(f"(: seed (Reach {goal_symbol(0)}) (STV 1.0 1.0))")
    rules: List[str] = []
    for i in range(depth):
        src = goal_symbol(i)
        dst = goal_symbol(i + 1)
        rules.append(
            f"(: reach_{i} (Implication (Reach {src}) (Reach {dst})) (CTV (STV 1.0 1.0) (STV 0.0 1.0)))"
        )
        for branch in range(noise_branching):
            rules.append(
                "(: "
                f"noise_{i}_{branch} "
                f"(Implication (Reach {src}) (Noise {noise_symbol(i, branch)})) "
                f"(CTV (STV 1.0 {NOISE_CONFIDENCE}) (STV 0.0 1.0)))"
            )
    handler.add_atoms_no_check(rules)


def assert_query_succeeds(handler: PeTTaChainer, depth: int, steps: int) -> None:
    proofs = handler.query(target_query(depth), steps=steps, timeout_sec=0)
    if not proofs:
        raise RuntimeError(f"Target query returned no proofs at depth={depth}")


def time_backward(depth: int, noise_branching: int, query_steps: int) -> float:
    handler = PeTTaChainer()
    build_chain_problem(handler, depth=depth, noise_branching=noise_branching)
    t0 = time.perf_counter()
    assert_query_succeeds(handler, depth=depth, steps=query_steps)
    return time.perf_counter() - t0


def time_forward_goal(depth: int, noise_branching: int) -> float:
    handler = PeTTaChainer()
    build_chain_problem(handler, depth=depth, noise_branching=noise_branching)
    seeds = handler.select_facts(f"(Reach {goal_symbol(0)})")
    t0 = time.perf_counter()
    handler.forward_chain(seeds, steps=depth)
    elapsed = time.perf_counter() - t0
    assert_query_succeeds(handler, depth=depth, steps=query_budget(depth))
    return elapsed


def time_forward_full(depth: int, noise_branching: int, full_steps: int) -> float:
    handler = PeTTaChainer()
    build_chain_problem(handler, depth=depth, noise_branching=noise_branching)
    seeds = handler.select_facts(f"(Reach {goal_symbol(0)})")
    t0 = time.perf_counter()
    handler.forward_chain(seeds, steps=full_steps)
    elapsed = time.perf_counter() - t0
    assert_query_succeeds(handler, depth=depth, steps=query_budget(depth))
    return elapsed


def print_table(rows: List[BenchmarkRow]) -> None:
    headers = [
        "depth",
        "noise_branching",
        "rules",
        "reachable_facts",
        "backward_s",
        "forward_goal_s",
        "forward_full_s",
        "goal_over_backward",
        "full_over_backward",
    ]
    print("\t".join(headers))
    for row in rows:
        print(
            "\t".join(
                [
                    str(row.depth),
                    str(row.noise_branching),
                    str(row.rules),
                    str(row.reachable_facts),
                    f"{row.backward_s:.6f}",
                    f"{row.forward_goal_s:.6f}",
                    f"{row.forward_full_s:.6f}",
                    f"{row.forward_goal_over_backward:.3f}",
                    f"{row.forward_full_over_backward:.3f}",
                ]
            )
        )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Compare backward query time against forward chaining on a simple rule chain."
    )
    parser.add_argument("--depths", default="10,25,50,100", help="Comma-separated chain depths")
    parser.add_argument(
        "--noise-branching",
        type=int,
        default=8,
        help="Extra non-goal conclusions produced at each depth; backward ignores them, forward materializes them",
    )
    parser.add_argument("--repeats", type=int, default=3, help="Repeats per depth")
    parser.add_argument("--json-out", default="", help="Optional JSON output file path")
    args = parser.parse_args()

    rows: List[BenchmarkRow] = []
    for depth in parse_int_list(args.depths):
        query_steps = query_budget(depth)
        rules = depth * (1 + args.noise_branching)
        initial_facts = 1
        reachable_facts = expected_reachable_facts(depth, args.noise_branching)
        forward_goal_steps = depth
        forward_full_steps = reachable_facts

        backward_runs = [
            time_backward(depth=depth, noise_branching=args.noise_branching, query_steps=query_steps)
            for _ in range(args.repeats)
        ]
        forward_goal_runs = [
            time_forward_goal(depth=depth, noise_branching=args.noise_branching)
            for _ in range(args.repeats)
        ]
        forward_full_runs = [
            time_forward_full(
                depth=depth,
                noise_branching=args.noise_branching,
                full_steps=forward_full_steps,
            )
            for _ in range(args.repeats)
        ]

        backward_s = statistics.mean(backward_runs)
        forward_goal_s = statistics.mean(forward_goal_runs)
        forward_full_s = statistics.mean(forward_full_runs)
        rows.append(
            BenchmarkRow(
                depth=depth,
                noise_branching=args.noise_branching,
                repeats=args.repeats,
                rules=rules,
                initial_facts=initial_facts,
                reachable_facts=reachable_facts,
                forward_goal_steps=forward_goal_steps,
                forward_full_steps=forward_full_steps,
                backward_s=backward_s,
                forward_goal_s=forward_goal_s,
                forward_full_s=forward_full_s,
                forward_goal_over_backward=(forward_goal_s / backward_s) if backward_s > 0 else 0.0,
                forward_full_over_backward=(forward_full_s / backward_s) if backward_s > 0 else 0.0,
            )
        )

    print_table(rows)

    if args.json_out:
        with open(args.json_out, "w", encoding="ascii") as f:
            json.dump([asdict(row) for row in rows], f, indent=2)
        print(f"\nWrote JSON results to {args.json_out}")


if __name__ == "__main__":
    main()
