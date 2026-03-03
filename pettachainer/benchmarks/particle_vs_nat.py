#!/usr/bin/env python3
import argparse
import json
import os
import random
import re
import statistics
import sys
import time
from dataclasses import dataclass
from typing import List

THIS_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(THIS_DIR, "..", ".."))
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)

from pettachainer.pettachainer import PeTTaChainer


STV_RE = re.compile(r"\(STV\s+([^\s\)]+)\s+([^\s\)]+)\)")


@dataclass
class RunResult:
    eval_seconds: float
    strength: float
    confidence: float
    particle_store_atoms: int


def parse_int_list(raw: str) -> List[int]:
    return [int(x.strip()) for x in raw.split(",") if x.strip()]


def raw_eval(chainer: PeTTaChainer, code: str) -> List[str]:
    out = chainer.handler.process_metta_string(code)
    if isinstance(out, str):
        return [out]
    return out


def parse_stv_single(atom: str) -> tuple[float, float]:
    match = STV_RE.search(atom)
    if not match:
        raise RuntimeError(f"Could not parse STV from output: {atom}")
    return float(match.group(1)), float(match.group(2))


def build_stv_list_expr(n: int, seed: int) -> str:
    rng = random.Random(seed)
    items = [f"(STV {rng.uniform(0.05, 0.95):.12f} 1.0)" for _ in range(n)]
    return f"({' '.join(items)})"


def reset_state(chainer: PeTTaChainer) -> None:
    raw_eval(chainer, "!(ParticleStoreClear)")


def run_single(mode: str, n: int, seed: int, threshold_ratio: float, particle_budget: int) -> RunResult:
    chainer = PeTTaChainer()
    reset_state(chainer)
    stv_list = build_stv_list_expr(n=n, seed=seed)
    threshold = int(n * threshold_ratio)

    if mode == "nat":
        expr = (
            "!(DistGreaterThanFormula "
            "(fold-flat NatDistAddBernoulliFromSTV (NatDist ((0 1.0))) "
            f"{stv_list}) "
            f"{threshold})"
        )
    elif mode == "particle":
        raw_eval(chainer, f"!(ParticleSetBudget {particle_budget})")
        expr = (
            "!(DistGreaterThanFormula "
            "(fold-flat ParticleAddBernoulliFromSTV (ParticleFromPairs ((0 1.0))) "
            f"{stv_list}) "
            f"{threshold})"
        )
    else:
        raise ValueError(f"Unknown mode: {mode}")

    t0 = time.perf_counter()
    out = raw_eval(chainer, expr)
    eval_seconds = time.perf_counter() - t0

    if not out:
        raise RuntimeError(f"Empty output for expression: {expr}")
    strength, confidence = parse_stv_single(out[0])
    particle_store_atoms = int(raw_eval(chainer, "!(ParticleStoreCount)")[0])
    return RunResult(
        eval_seconds=eval_seconds,
        strength=strength,
        confidence=confidence,
        particle_store_atoms=particle_store_atoms,
    )


def summarize(runs: List[RunResult]) -> RunResult:
    return RunResult(
        eval_seconds=statistics.mean(r.eval_seconds for r in runs),
        strength=statistics.mean(r.strength for r in runs),
        confidence=statistics.mean(r.confidence for r in runs),
        particle_store_atoms=int(round(statistics.mean(r.particle_store_atoms for r in runs))),
    )


def print_table(rows: List[dict]) -> None:
    headers = [
        "n",
        "budget",
        "nat_eval_s",
        "particle_eval_s",
        "speedup_nat_over_particle",
        "nat_strength",
        "particle_strength",
        "abs_err",
        "nat_conf",
        "particle_conf",
        "particle_atoms",
    ]
    print("\t".join(headers))
    for row in rows:
        print(
            "\t".join(
                [
                    str(row["n"]),
                    str(row["budget"]),
                    f"{row['nat_eval_s']:.6f}",
                    f"{row['particle_eval_s']:.6f}",
                    f"{row['speedup_nat_over_particle']:.3f}",
                    f"{row['nat_strength']:.6f}",
                    f"{row['particle_strength']:.6f}",
                    f"{row['abs_strength_error']:.6f}",
                    f"{row['nat_confidence']:.6f}",
                    f"{row['particle_confidence']:.6f}",
                    str(row["particle_store_atoms"]),
                ]
            )
        )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Benchmark direct NatDist vs ParticleDist folding + threshold evaluation"
    )
    parser.add_argument("--sizes", default="100,500,1000", help="Comma-separated number of Bernoulli updates")
    parser.add_argument("--particle-budgets", default="128,256,512,1024", help="Comma-separated particle budgets")
    parser.add_argument("--repeats", type=int, default=2, help="Repeats per configuration")
    parser.add_argument("--threshold-ratio", type=float, default=0.5, help="Threshold as fraction of n")
    parser.add_argument("--seed", type=int, default=42, help="Base RNG seed")
    parser.add_argument("--json-out", default="", help="Optional JSON output file path")
    args = parser.parse_args()

    sizes = parse_int_list(args.sizes)
    budgets = parse_int_list(args.particle_budgets)

    rows: List[dict] = []
    for n in sizes:
        nat_runs = [
            run_single(
                mode="nat",
                n=n,
                seed=args.seed + rep,
                threshold_ratio=args.threshold_ratio,
                particle_budget=0,
            )
            for rep in range(args.repeats)
        ]
        nat = summarize(nat_runs)

        for budget in budgets:
            particle_runs = [
                run_single(
                    mode="particle",
                    n=n,
                    seed=args.seed + rep,
                    threshold_ratio=args.threshold_ratio,
                    particle_budget=budget,
                )
                for rep in range(args.repeats)
            ]
            particle = summarize(particle_runs)
            rows.append(
                {
                    "n": n,
                    "budget": budget,
                    "nat_eval_s": nat.eval_seconds,
                    "particle_eval_s": particle.eval_seconds,
                    "speedup_nat_over_particle": (nat.eval_seconds / particle.eval_seconds)
                    if particle.eval_seconds > 0
                    else 0.0,
                    "nat_strength": nat.strength,
                    "particle_strength": particle.strength,
                    "abs_strength_error": abs(particle.strength - nat.strength),
                    "nat_confidence": nat.confidence,
                    "particle_confidence": particle.confidence,
                    "particle_store_atoms": particle.particle_store_atoms,
                }
            )

    print_table(rows)

    if args.json_out:
        with open(args.json_out, "w", encoding="ascii") as f:
            json.dump(rows, f, indent=2)
        print(f"\nWrote JSON results to {args.json_out}")


if __name__ == "__main__":
    main()
