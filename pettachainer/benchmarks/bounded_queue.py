#!/usr/bin/env python3
"""Measure agenda growth with checked answers and observable backward work."""
from __future__ import annotations

import argparse
import json
import math
import re
import statistics
import sys
import time
from dataclasses import asdict, dataclass, replace
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))
from pettachainer import PeTTaChainer


MODES = ("backward", "backward_many_small", "forward", "forward_many_small")
# Idealized modus ponens for one certain input and one confidence-0.5 input.
DERIVED_CONFIDENCE = 0.4999749387171011


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
    agenda_pushes: int
    agenda_pops: int
    expanded_hubs: int


def statements(mode: str, fanout: int, seeds: int) -> list[str]:
    backward = mode.startswith("backward")
    if backward:
        atoms = [
            "(: seed (QueueBenchSeed) (STV 1.0 0.5))",
            "(: success (Implication (QueueBenchSeed) (QueueBenchHub 0)) "
            "(CTV (STV 1.0 1.0) (STV 0.0 1.0)))",
        ]
        for seed in range(seeds - 1):
            atoms.append(
                f"(: hub_{seed} (Implication (QueueBenchHub {seed + 1}) "
                f"(QueueBenchHub {seed})) (STV 1.0 1.0))"
            )
        for seed in range(seeds):
            for index in range(fanout):
                # The intermediate has a producer, so structural feasibility
                # cannot discard every alternative before creating the agenda.
                atoms.extend([
                    f"(: branch_{seed}_{index} "
                    f"(Implication (QueueBenchBranch {seed} {index}) "
                    f"(QueueBenchHub {seed})) (STV 1.0 1.0))",
                    f"(: dead_{seed}_{index} "
                    f"(Implication (QueueBenchMissing {seed} {index}) "
                    f"(QueueBenchBranch {seed} {index})) (STV 1.0 1.0))",
                ])
        return atoms
    atoms = [
        f"(: seed_{seed} (QueueBenchSeed {seed}) (STV 1.0 1.0))"
        for seed in range(seeds)
    ]
    atoms.extend(
        f"(: fan_{seed}_{index} (Implication (QueueBenchSeed {seed}) "
        f"(QueueBenchNoise {seed} {index})) "
        "(CTV (STV 1.0 0.5) (STV 0.0 1.0)))"
        for seed in range(seeds)
        for index in range(fanout)
    )
    return atoms


def validate_results(
    results: list[str], *, mode: str, fanout: int, seeds: int, steps: int,
    kb: str, metrics: dict[str, object],
) -> None:
    proofs = []
    for result in results:
        match = re.fullmatch(r"(.*) \(STV ([^ ]+) ([^)]+)\)\)", result)
        if match is None or not (
            math.isclose(float(match[2]), 1.0, rel_tol=1e-12)
            and math.isclose(float(match[3]), DERIVED_CONFIDENCE, rel_tol=1e-12)
        ):
            raise RuntimeError(f"{mode} returned a wrong truth value: {result}")
        proofs.append(match[1])
    if mode.startswith("backward"):
        expected = ["(: (by success seed) (QueueBenchHub 0)"]
        if proofs != expected:
            raise RuntimeError(f"{mode} returned a wrong proof or truth value: {results}")
        if metrics["search_aborts"] != 0:
            raise RuntimeError(f"{mode} aborted search: {metrics}")
        if int(metrics["agenda_pushes"]) < fanout:
            raise RuntimeError(f"{mode} did not schedule its alternatives: {metrics}")
        if int(metrics["agenda_pops"]) < min(fanout, steps):
            raise RuntimeError(f"{mode} skipped its search workload: {metrics}")
        if seeds > 1 and int(metrics["expanded_hubs"]) < 2:
            raise RuntimeError(f"{mode} only explored one hub; increase --steps: {metrics}")
    else:
        # Certain unprocessed seeds outrank the confidence-0.5 derived leaves.
        # Equal-priority seed order is not a public forward-chainer guarantee.
        processed = set()
        for proof in proofs:
            match = re.match(r"\(\(QueueBenchNoise (\d+) \d+\)", proof)
            if match is None or not 0 <= int(match[1]) < seeds:
                raise RuntimeError(f"{mode} returned an invalid seed group: {proof}")
            processed.add(int(match[1]))
        expected = {
            f"((QueueBenchNoise {seed} {index}) ({kb} MAIN Nil) "
            f"(by fan_{seed}_{index} seed_{seed})"
            for seed in processed
            for index in range(fanout)
        }
        if (len(processed) != min(seeds, steps)
                or len(proofs) != len(expected) or set(proofs) != expected):
            raise RuntimeError(
                f"{mode} expected {len(expected)} exact derived facts; "
                f"got {len(results)} with missing or wrong facts"
            )


def run_case(mode: str, fanout: int, seeds: int, steps: int, pruning: bool) -> BenchmarkRow:
    seeds = seeds if mode.endswith("many_small") else 1
    handler = PeTTaChainer()
    handler.handler.process_metta_string(
        f"!(set-bounded-agenda-pruning {'true' if pruning else 'false'})"
    )
    backward = mode.startswith("backward")
    if backward:
        handler.set_query_metrics(True)
    atoms = statements(mode, fanout, seeds)
    started = time.perf_counter()
    handler.add_atoms_no_check(atoms)
    selected = [] if backward else handler.select_facts(
        [f"(QueueBenchSeed {seed})" for seed in range(seeds)]
    )
    setup_s = time.perf_counter() - started
    started = time.perf_counter()
    if backward:
        results = handler.query("(: $prf (QueueBenchHub 0) $tv)", steps=steps, timeout_sec=0)
    else:
        results = handler.forward_chain(selected, steps=steps)
    run_s = time.perf_counter() - started
    metrics = handler.last_query_metrics() if backward else {}
    if backward:
        metrics["expanded_hubs"] = int(handler.evaluate_statement(
            "(length (collapse (match &goal "
            "(stored-goal-row $_gid $_depth "
            f"((QueueBenchHub $hub) ({handler.kb} MAIN Nil) $_proof $_tv) "
            "true $_agenda) $hub)))"
        ))
    validate_results(
        results, mode=mode, fanout=fanout, seeds=seeds, steps=steps,
        kb=handler.kb, metrics=metrics,
    )
    return BenchmarkRow(
        pruning="on" if pruning else "off", mode=mode, fanout=fanout,
        seeds=seeds, steps=steps, repeats=1, setup_s=setup_s, run_s=run_s,
        result_count=len(results), agenda_pushes=int(metrics.get("agenda_pushes", 0)),
        agenda_pops=int(metrics.get("agenda_pops", 0)),
        expanded_hubs=int(metrics.get("expanded_hubs", 0)),
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fanouts", default="2000,8000", help="Comma-separated agenda fan-outs")
    parser.add_argument("--steps", type=int, default=100)
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--mode", choices=(*MODES, "both"), default="both")
    parser.add_argument("--seeds", type=int, default=100)
    parser.add_argument("--json-out", type=Path)
    parser.add_argument("--compare-pruning", action="store_true")
    args = parser.parse_args()
    try:
        fanouts = [int(value) for value in args.fanouts.split(",")]
    except ValueError:
        parser.error("--fanouts must contain comma-separated positive integers")
    modes = ("backward", "forward") if args.mode == "both" else (args.mode,)
    if min(*fanouts, args.steps, args.repeats, args.seeds) < 1:
        parser.error("fanouts, steps, repeats, and seeds must be positive")
    if any(mode.startswith("backward") for mode in modes) and args.steps < 3:
        parser.error("backward modes need at least three steps to prove the target")
    summaries = []
    for fanout in fanouts:
        for mode in modes:
            for pruning in ([True, False] if args.compare_pruning else [True]):
                rows = [run_case(mode, fanout, args.seeds, args.steps, pruning)
                        for _ in range(args.repeats)]
                summaries.append(asdict(replace(
                    rows[0], repeats=args.repeats,
                    setup_s=statistics.mean(row.setup_s for row in rows),
                    run_s=statistics.mean(row.run_s for row in rows),
                )))
    print(json.dumps(summaries, indent=2))
    if args.json_out:
        args.json_out.write_text(json.dumps(summaries, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
