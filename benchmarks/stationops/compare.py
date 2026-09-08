#!/usr/bin/env python3
"""Interleaved historical A/B of ChainerGame, with retained artifacts and gates."""
from __future__ import annotations

import argparse
import io
import json
import os
from pathlib import Path
import re
import statistics
import subprocess
import sys
import tarfile


def semantic_result(value):
    if isinstance(value, dict):
        return {key: semantic_result(item) for key, item in value.items()
                if not key.endswith("_seconds") and key != "backend_counters"}
    if isinstance(value, list):
        return [semantic_result(item) for item in value]
    return value


def compare_runs(rows, acceptance, max_regression_percent):
    reference = semantic_result(rows["base"][0]["result"])
    same_results = all(semantic_result(row["result"]) == reference
                       for side in rows.values() for row in side)
    proofs = [re.sub(r"\bkb[0-9a-f]{32}\b", "KB",
                     json.dumps([batch["answers"] for batch in row["batches"]]))
              for side in rows.values() for row in side]
    same_proofs = all(proof == proofs[0] for proof in proofs)
    comparisons = []
    for shift in range(2):
        for metric in ("seconds", "inferences"):
            medians = {side: statistics.median(row["batches"][shift][metric] for row in runs)
                       for side, runs in rows.items()}
            delta = 100 * (medians["candidate"] / medians["base"] - 1)
            comparison = dict(shift=shift + 1, metric=metric, **medians,
                              delta_percent=delta, passed=delta <= max_regression_percent)
            comparisons.append(comparison)
            print(json.dumps(comparison), flush=True)
    passed = (same_results and same_proofs and all(row["passed"] for row in comparisons)
              and all(row["passed"] for row in acceptance))
    summary = dict(semantic_results_equal=same_results, proof_answers_equal=same_proofs,
                   acceptance=acceptance,
                   comparisons=comparisons, passed=passed)
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("base")
    parser.add_argument("candidate")
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--chainergame", type=Path)
    parser.add_argument("--chainergame-ref", default="99fc56e")
    parser.add_argument("--pairs", type=int, default=3)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--max-regression-percent", type=float, default=5)
    args = parser.parse_args()
    if args.pairs < 1 or args.max_regression_percent < 0:
        parser.error("pairs must be positive and regression threshold nonnegative")
    repo = args.repository.resolve()
    game = (args.chainergame or repo / "../../ChainerGame").resolve()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=False)

    def git(*values, cwd=repo):
        return subprocess.check_output(["git", "-C", str(cwd), *values], text=True).strip()

    revisions = {side: git("rev-parse", f"{ref}^{{commit}}")
                 for side, ref in (("base", args.base), ("candidate", args.candidate))}
    # Freeze the game and PeTTa too; both sides use exactly these sources.
    sources = {
        **{side: (repo, rev, ["pettachainer", "third_party"])
           for side, rev in revisions.items()},
        "game": (game, git("rev-parse", f"{args.chainergame_ref}^{{commit}}", cwd=game), ["src"]),
        "runtime": (repo, git("rev-parse", "HEAD"), ["third_party/petta"]),
    }
    metadata = dict(
        revisions=revisions, pairs=args.pairs, max_regression_percent=args.max_regression_percent,
        game_commit=sources["game"][1], runtime_commit=sources["runtime"][1],
        runtime_tree=git("rev-parse", "HEAD:third_party/petta"),
        repository_status=git("status", "--short"), game_status=git("status", "--short", cwd=game),
        python=sys.version, executable=sys.executable, command=sys.argv,
        fetched=False, rebuilt=False,
    )
    (output / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
    for side, (source, rev, paths) in sources.items():
        archive = subprocess.check_output(["git", "-C", str(source), "archive", rev, *paths])
        destination = output / side
        destination.mkdir()
        with tarfile.open(fileobj=io.BytesIO(archive)) as stream:
            stream.extractall(destination)

    rows = {"base": [], "candidate": []}
    acceptance = []
    for pair in range(1, args.pairs + 1):
        for side in (("base", "candidate") if pair % 2 else ("candidate", "base")):
            label = f"{side}-{pair}"
            print(f"Starting {label} ({revisions[side][:8]})", flush=True)
            path = output / f"{label}.json"
            with (output / f"{label}.log").open("w") as log:
                process = subprocess.run(
                    [str(repo / ".venv/bin/python"), str(Path(__file__).with_name("benchmark.py")),
                     "--repository", str(output / side), "--chainergame", str(output / "game"),
                     "--petta", str(output / "runtime/third_party/petta"), "--json-out", str(path)],
                    cwd=output, env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1"),
                    stdout=log, stderr=subprocess.STDOUT,
                )
            # Preserve completed but semantically failing historical runs too.
            # An engine/load failure without a result is still fatal.
            if not path.exists():
                raise RuntimeError(f"{label} produced no result; see {label}.log")
            acceptance.append(dict(sample=label, passed=process.returncode == 0))
            rows[side].append(json.loads(path.read_text()))
            print(f"Finished {label}: exit {process.returncode}", flush=True)

    summary = compare_runs(rows, acceptance, args.max_regression_percent)
    (output / "comparison.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(f"Episode results equal: {summary['semantic_results_equal']}; "
          f"proof answers equal: {summary['proof_answers_equal']}; "
          f"gate: {'PASS' if summary['passed'] else 'FAIL'}")
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
