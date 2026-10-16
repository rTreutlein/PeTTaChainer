#!/usr/bin/env python3
"""Measure warm queries, unrelated skeleton growth, and retained view history.

Each invocation uses one process and one KB. Timed calls include the public
query API; state inspection is outside the timing and inference counts.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import resource
import time
from pathlib import Path

from _benchmark_support import load_chainer, write_json
from durable_query_many import initial_statements, queries, shift_statements
from member_inheritance import (
    INHERITANCE_QUERY, count_confidence, member_statements, validate_truth_value,
)


def run(repository: Path, rounds: int, repeats: int, mode: str) -> dict:
    handler = load_chainer(repository, RuntimeError)()
    import janus_swi as janus

    rows = []

    def query(phase, iteration, goals):
        before = janus.query_once("statistics(inferences, I)")["I"]
        start = time.perf_counter()
        answers = handler.query_many(goals, steps=300, timeout_sec=0)
        elapsed = time.perf_counter() - start
        inferences = janus.query_once("statistics(inferences, I)")["I"] - before
        if any(len(group) != 1 for group in answers):
            raise AssertionError(f"{phase} {iteration}: expected one proof per root: {answers}")
        normalized = re.sub(r"\bkb[0-9a-f]{32}\b", "KB", json.dumps(answers))
        rows.append(dict(
            phase=phase, iteration=iteration, seconds=elapsed, inferences=inferences,
            proof_sha256=hashlib.sha256(normalized.encode()).hexdigest(),
        ))
        return answers

    def snapshot():
        counts = {
            name: int(handler.handler.process_metta_string(
                f"!(length (collapse (match &{name} $row true)))"
            )[0])
            for name in ("sk_expanded", "sk_row", "sk_view", "sk_latest", "sk_needed")
        }
        return dict(**counts, peak_rss_kib=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss)

    snapshots = []
    if mode == "unrelated":
        handler.add_atoms_no_check(initial_statements(2))
        stable = queries(2, 0, 0)
        expected = query("initial", 0, stable)
        for iteration in range(rounds):
            handler.add_atoms_no_check(shift_statements(iteration, 6))
            query("growth", iteration, queries(2, 6, iteration))
            for _ in range(repeats):
                if query("unchanged", iteration, stable) != expected:
                    raise AssertionError("Unrelated growth changed a stable proof or TV")
            snapshots.append(dict(iteration=iteration, **snapshot()))
    else:
        handler.add_atoms_no_check([
            atom for index in range(16) for atom in member_statements(index, 0.75)
        ])
        handler.add_atoms_no_check([
            "(: (no_inverse sessionRule) "
            "(Implication (Inheritance MemberBenchSubject MemberBenchConcept) "
            "(SessionConclusion)) (CTV (STV 1 1) (STV 0 1)))"
        ])
        goals = [INHERITANCE_QUERY, "(: $proof (SessionConclusion) $tv)"]
        for iteration in range(rounds):
            if iteration:
                handler.add_atoms_no_check(member_statements(15 + iteration, 0.75))
            expected = query("growth", iteration, goals)
            validate_truth_value(expected[0], expected_strength=0.75,
                                 expected_confidence=count_confidence(16 + iteration))
            for _ in range(repeats):
                if query("unchanged", iteration, goals) != expected:
                    raise AssertionError("Warm query changed a proof or TV")
            snapshots.append(dict(iteration=iteration, **snapshot()))

    return dict(mode=mode, rounds=rounds, repeats=repeats, rows=rows, snapshots=snapshots)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--mode", choices=("unrelated", "history"), required=True)
    parser.add_argument("--rounds", type=int, default=40)
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--json-out", type=Path, required=True)
    args = parser.parse_args()
    if args.rounds < 2 or args.repeats < 1:
        parser.error("rounds must exceed one and repeats must be positive")
    write_json(args.json_out, run(args.repository, args.rounds, args.repeats, args.mode))
