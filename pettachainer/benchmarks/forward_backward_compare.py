#!/usr/bin/env python3
import argparse
import json
import os
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


@dataclass
class ModeRun:
    mode: str
    elapsed_s: float
    success: bool


def raw_eval(chainer: PeTTaChainer, code: str) -> List[str]:
    out = chainer.handler.process_metta_string(code)
    if isinstance(out, str):
        return [out]
    return out


def add_chain_kb(chainer: PeTTaChainer, chain_len: int, noise_chains: int, noise_chain_len: int) -> None:
    if chain_len < 1:
        raise ValueError("chain_len must be >= 1")
    if noise_chain_len < 1:
        raise ValueError("noise_chain_len must be >= 1")

    chainer.add_atom("(: main_seed (Reach R0) (STV 1.0 1.0))")
    for i in range(chain_len):
        chainer.add_atom(
            "(: main_rule_{i} (Implication (Premises (Reach R{i})) (Conclusions (Reach R{i1}))) (STV 1.0 1.0))".format(
                i=i, i1=i + 1
            )
        )

    # Disconnected chains inflate forward workload but do not help the main query.
    for chain in range(noise_chains):
        chainer.add_atom(f"(: noise_seed_{chain} (Noise {chain} 0) (STV 1.0 1.0))")
        for step in range(noise_chain_len):
            chainer.add_atom(
                "(: noise_rule_{chain}_{step} (Implication (Premises (Noise {chain} {step})) (Conclusions (Noise {chain} {step1}))) (STV 1.0 1.0))".format(
                    chain=chain, step=step, step1=step + 1
                )
            )


def run_forward_only(chainer: PeTTaChainer, forward_steps: int, target_type: str) -> ModeRun:
    t0 = time.perf_counter()
    raw_eval(chainer, f"!(forward-chain {forward_steps} {chainer.kb})")
    proved = raw_eval(chainer, f"!(forward-has-derived? {chainer.kb} {target_type})")
    elapsed = time.perf_counter() - t0
    ok = bool(proved) and str(proved[0]).strip().lower() == "true"
    return ModeRun(mode="forward", elapsed_s=elapsed, success=ok)


def run_backward_only(chainer: PeTTaChainer, backward_steps: int, query_atom: str) -> ModeRun:
    query_eval = chainer.evaluate_query(query_atom)
    t0 = time.perf_counter()
    out = raw_eval(chainer, f"!(query {backward_steps} {chainer.kb} {query_eval})")
    elapsed = time.perf_counter() - t0
    return ModeRun(mode="backward", elapsed_s=elapsed, success=bool(out))


def run_forward_then_backward(
    chainer: PeTTaChainer, forward_steps: int, backward_steps: int, query_atom: str
) -> ModeRun:
    query_eval = chainer.evaluate_query(query_atom)
    t0 = time.perf_counter()
    raw_eval(chainer, f"!(forward-chain {forward_steps} {chainer.kb})")
    out = raw_eval(chainer, f"!(query {backward_steps} {chainer.kb} {query_eval})")
    elapsed = time.perf_counter() - t0
    return ModeRun(mode="forward_then_backward", elapsed_s=elapsed, success=bool(out))


def summarize(runs: List[ModeRun]) -> dict:
    elapsed = [r.elapsed_s for r in runs]
    return {
        "mode": runs[0].mode,
        "mean_s": statistics.mean(elapsed),
        "median_s": statistics.median(elapsed),
        "min_s": min(elapsed),
        "max_s": max(elapsed),
        "success_rate": sum(1 for r in runs if r.success) / len(runs),
    }


def print_table(rows: List[dict]) -> None:
    headers = ["mode", "mean_s", "median_s", "min_s", "max_s", "success_rate"]
    print("\t".join(headers))
    for row in rows:
        print(
            "\t".join(
                [
                    row["mode"],
                    f"{row['mean_s']:.6f}",
                    f"{row['median_s']:.6f}",
                    f"{row['min_s']:.6f}",
                    f"{row['max_s']:.6f}",
                    f"{row['success_rate']:.2f}",
                ]
            )
        )


def run_mode(
    mode: str,
    repeats: int,
    chain_len: int,
    noise_chains: int,
    noise_chain_len: int,
    forward_steps: int,
    backward_steps: int,
    query_atom: str,
    target_type: str,
) -> List[ModeRun]:
    out: List[ModeRun] = []
    for _ in range(repeats):
        chainer = PeTTaChainer()
        add_chain_kb(
            chainer,
            chain_len=chain_len,
            noise_chains=noise_chains,
            noise_chain_len=noise_chain_len,
        )
        if mode == "forward":
            out.append(run_forward_only(chainer, forward_steps=forward_steps, target_type=target_type))
        elif mode == "forward_then_backward":
            out.append(
                run_forward_then_backward(
                    chainer,
                    forward_steps=forward_steps,
                    backward_steps=backward_steps,
                    query_atom=query_atom,
                )
            )
        elif mode == "backward":
            out.append(run_backward_only(chainer, backward_steps=backward_steps, query_atom=query_atom))
        else:
            raise ValueError(f"Unknown mode: {mode}")
    return out


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Compare forward chaining, forward+backward, and backward-only performance."
    )
    parser.add_argument(
        "--chain-len",
        type=int,
        default=10,
        help="Main proof chain length (Reach R0 -> Reach R<chain_len>).",
    )
    parser.add_argument(
        "--noise-chains",
        type=int,
        default=10,
        help="Number of disconnected noise chains.",
    )
    parser.add_argument(
        "--noise-chain-len",
        type=int,
        default=2,
        help="Length of each disconnected noise chain.",
    )
    parser.add_argument(
        "--forward-steps",
        type=int,
        default=1200,
        help="Step budget for forward chaining.",
    )
    parser.add_argument(
        "--backward-steps",
        type=int,
        default=1200,
        help="Step budget for backward query.",
    )
    parser.add_argument("--repeats", type=int, default=3, help="Runs per mode.")
    parser.add_argument("--json-out", default="", help="Optional JSON output file path.")
    args = parser.parse_args()

    target_idx = args.chain_len
    target_type = f"(Reach R{target_idx})"
    query_atom = f"(: $prf {target_type} $tv)"

    all_runs: List[ModeRun] = []
    for mode in ("forward", "forward_then_backward", "backward"):
        all_runs.extend(
            run_mode(
                mode=mode,
                repeats=args.repeats,
                chain_len=args.chain_len,
                noise_chains=args.noise_chains,
                noise_chain_len=args.noise_chain_len,
                forward_steps=args.forward_steps,
                backward_steps=args.backward_steps,
                query_atom=query_atom,
                target_type=target_type,
            )
        )

    rows = [
        summarize([r for r in all_runs if r.mode == "forward"]),
        summarize([r for r in all_runs if r.mode == "forward_then_backward"]),
        summarize([r for r in all_runs if r.mode == "backward"]),
    ]
    print_table(rows)

    if args.json_out:
        with open(args.json_out, "w", encoding="ascii") as f:
            json.dump(rows, f, indent=2)
        print(f"\nWrote JSON results to {args.json_out}")


if __name__ == "__main__":
    main()
