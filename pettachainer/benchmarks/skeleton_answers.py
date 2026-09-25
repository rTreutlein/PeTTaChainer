#!/usr/bin/env python3
"""Time broad stored-fact queries, checking every complete proof and TV.

Run each repetition in a fresh process; loading and ingestion are not timed.
"""
from __future__ import annotations

import argparse
import time
from pathlib import Path

from _benchmark_support import load_chainer, write_json


def run(repository: Path, facts: int) -> dict:
    chainer = load_chainer(repository, RuntimeError)()
    expected = {
        f"(: wideFact{i} (WideItem {i}) (STV 1.0 0.8))" for i in range(facts)
    }
    chainer.add_atoms_no_check(sorted(expected))
    timings = []
    for _ in range(2):
        start = time.perf_counter()
        answers = chainer.query_many(
            ["(: $proof (WideItem $item) $tv)"], steps=0, timeout_sec=0
        )[0]
        timings.append(time.perf_counter() - start)
        actual = [str(answer) for answer in answers]
        if len(actual) != facts or set(actual) != expected:
            raise AssertionError(f"expected {facts} complete facts, got {actual!r}")
    return {
        "facts": facts,
        "cold_seconds": timings[0],
        "warm_seconds": timings[1],
        "answers": len(actual),
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--facts", type=int, default=600)
    parser.add_argument("--json-out", type=Path, required=True)
    args = parser.parse_args()
    if args.facts < 1:
        parser.error("--facts must be positive")
    write_json(args.json_out, run(args.repository, args.facts))
