#!/usr/bin/env python3
"""Run the real ChainerGame two-shift workload in a selected PeTTaChainer tree.

Use the repository's .venv/bin/python. No StationOps model is duplicated here.
"""
from __future__ import annotations

import argparse
import functools
from importlib.metadata import version
import json
import os
from pathlib import Path
import resource
import sys
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path, required=True)
    parser.add_argument("--chainergame", type=Path, required=True)
    parser.add_argument("--petta", type=Path,
                        help="PeTTa checkout; default: the interpreter's installed runtime")
    parser.add_argument("--json-out", type=Path, required=True)
    parser.add_argument("--seed", type=int, default=7)
    parser.add_argument("--budget", type=int, default=600)
    args = parser.parse_args()
    repository = args.repository.resolve()
    game = args.chainergame.resolve()
    if args.petta:
        os.environ["PETTA_PATH"] = str(args.petta.resolve())
        sys.path.insert(0, str(args.petta.resolve() / "python"))
    sys.path[:0] = [str(repository), str(game / "src")]

    import janus_swi as janus
    import petta
    import pettachainer
    import stationops
    from pettachainer import PeTTaChainer
    from stationops.backends import PeTTaChainerBackend
    from stationops.game import GameConfig, run_game_episode

    runtime = args.petta.resolve() if args.petta else Path(petta._resolve_petta_path()).resolve()
    sources = [(pettachainer, repository), (stationops, game)]
    if args.petta:
        sources.append((petta, args.petta.resolve()))
    for module, root in sources:
        if root not in Path(module.__file__).resolve().parents:
            raise RuntimeError(f"Wrong import: {module.__file__}; expected {root}")

    events = []
    batches = []
    shift = 1

    def timed(name, function):
        @functools.wraps(function)
        def call(*values, **kwargs):
            started = time.perf_counter()
            try:
                return function(*values, **kwargs)
            finally:
                event = dict(shift=shift, name=name, seconds=time.perf_counter() - started)
                events.append(event)
                print(json.dumps(event), flush=True)
        return call

    for name in ("_new_handler", "_reconcile", "infer", "propose_actions"):
        setattr(PeTTaChainerBackend, name, timed(name, getattr(PeTTaChainerBackend, name)))
    query_many = PeTTaChainer.query_many

    def query(self, atoms, steps=100, timeout_sec=10):
        self.set_query_metrics(True)
        before = janus.query_once("statistics(inferences, I), statistics(cputime, C)")
        started = time.perf_counter()
        answers = query_many(self, atoms, steps=steps, timeout_sec=timeout_sec)
        elapsed = time.perf_counter() - started
        after = janus.query_once("statistics(inferences, I), statistics(cputime, C)")
        batch = dict(
            shift=shift, seconds=elapsed,
            inferences=after["I"] - before["I"], cpu_seconds=after["C"] - before["C"],
            metrics=self.last_query_metrics(), queries=atoms, answers=answers,
            peak_rss_kib=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
        )
        batches.append(batch)
        self.set_query_metrics(False)
        print(json.dumps({key: batch[key] for key in ("shift", "seconds", "inferences")}), flush=True)
        return answers

    PeTTaChainer.query_many = query

    def completed(row):
        nonlocal shift
        print(json.dumps({key: row[key] for key in ("shift", "wall_time_seconds", "regret")}), flush=True)
        shift = row["shift"] + 1

    result = run_game_episode(
        GameConfig(seed=args.seed, shifts=2, modules=4), "pettachainer", args.budget,
        action_budget=1, on_shift=completed,
    )
    payload = dict(
        environment=dict(
            repository=str(repository), chainergame=str(game), petta=str(runtime),
            petta_module=str(Path(petta.__file__).resolve()),
            python=sys.version, executable=sys.executable, loadavg=os.getloadavg(),
            janus_version=version("janus-swi"),
            swi_version=janus.query_once("current_prolog_flag(version, V)")["V"],
        ),
        workload=dict(seed=args.seed, shifts=2, modules=4, budget=args.budget, action_budget=1),
        batches=batches, events=events, result=result,
    )
    args.json_out.write_text(json.dumps(payload, indent=2) + "\n")
    if len(batches) != 2 or any(b["metrics"].get("search_aborts", 0) for b in batches):
        raise RuntimeError("Expected two diagnosis batches with zero search aborts")
    if args.seed == 7:
        if any(row["belief_metrics"]["coverage"] != 1 for row in result["rounds"]):
            raise RuntimeError("Incomplete diagnosis coverage")
        if result["aggregate"]["regret"] != 0 or result["aggregate"]["station_score"] != 637:
            raise RuntimeError("StationOps acceptance result changed")


if __name__ == "__main__":
    main()
