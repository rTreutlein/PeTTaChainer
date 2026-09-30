#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
import time
from pathlib import Path
from typing import Any

from _benchmark_support import load_chainer, write_json


REPO_ROOT = Path(__file__).resolve().parents[2]
NUMBER = r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?"
STV_PATTERN = re.compile(rf"\(STV\s+({NUMBER})\s+({NUMBER})\)")
SOURCE_PATTERN = re.compile(
    rf"\(STV\s+{NUMBER}\s+{NUMBER}\)\s+(computed|user)\b"
)


class OrdinaryBaseRateBenchmarkError(RuntimeError):
    pass


def p_fact(index: int) -> str:
    return f"(: p{index} (P obj{index}) (STV 0.7 0.8))"


def initial_atoms(initial_facts: int) -> list[str]:
    return [
        "(: pToQ (Implication (P $x) (Q $x)) "
        "(CTV (STV 0.8 0.9) (STV 0.1 0.9)))",
        "(: qa (Q alice) (STV 0.9 0.8))",
        *[p_fact(index) for index in range(initial_facts)],
    ]


def inversion_query() -> str:
    return "(: $prf (P alice) $tv)"


def parse_stv(payload: Any) -> tuple[float, float] | None:
    match = STV_PATTERN.search(str(payload))
    if match is None:
        return None
    return float(match.group(1)), float(match.group(2))


def cached_p_rate(handler: Any) -> tuple[str, tuple[float, float] | None]:
    rows = handler.handler.process_metta_string(
        f"!(base-rate-cache-entries {handler.kb} (P $x))"
    )
    text = str(rows)
    source_match = SOURCE_PATTERN.search(text)
    source = source_match.group(1) if source_match else "missing"
    return source, parse_stv(text)


def stv_close(
    left: tuple[float, float] | None,
    right: tuple[float, float] | None,
    *,
    tolerance: float = 1e-9,
) -> bool:
    if left is None or right is None:
        return False
    return (
        abs(left[0] - right[0]) <= tolerance
        and abs(left[1] - right[1]) <= tolerance
    )


def run_incremental(
    *,
    handler_type: Any,
    initial_facts: int,
    deltas: int,
    query_steps: int,
    forward_steps: int,
) -> dict[str, Any]:
    started = time.perf_counter()
    handler = handler_type()
    handler.add_atoms_no_check(initial_atoms(initial_facts))
    setup_seconds = time.perf_counter() - started

    query = inversion_query()
    started = time.perf_counter()
    warm_answers = handler.query(query, steps=query_steps, timeout_sec=0)
    warm_query_seconds = time.perf_counter() - started
    if not warm_answers:
        raise OrdinaryBaseRateBenchmarkError(
            "warm inversion query returned no answers"
        )
    warm_source, warm_tv = cached_p_rate(handler)
    if warm_source != "computed" or warm_tv is None:
        raise OrdinaryBaseRateBenchmarkError(
            f"warm query did not harvest a computed P($x) rate; "
            f"source={warm_source!r} tv={warm_tv!r}"
        )

    add_seconds = 0.0
    forward_seconds = 0.0
    for offset in range(deltas):
        index = initial_facts + offset
        started = time.perf_counter()
        handler.add_atoms_no_check([p_fact(index)])
        selected = handler.select_facts(f"(P obj{index})")
        add_seconds += time.perf_counter() - started
        started = time.perf_counter()
        handler.forward_chain(selected, steps=forward_steps)
        forward_seconds += time.perf_counter() - started

    delta_source, delta_tv = cached_p_rate(handler)
    started = time.perf_counter()
    followup_answers = handler.query(query, steps=query_steps, timeout_sec=0)
    followup_query_seconds = time.perf_counter() - started
    if not followup_answers:
        raise OrdinaryBaseRateBenchmarkError(
            "follow-up inversion query returned no answers"
        )
    followup_source, followup_tv = cached_p_rate(handler)
    return {
        "setup_seconds": setup_seconds,
        "warm_query_seconds": warm_query_seconds,
        "delta_add_seconds": add_seconds,
        "delta_forward_seconds": forward_seconds,
        "delta_total_seconds": add_seconds + forward_seconds,
        "followup_query_seconds": followup_query_seconds,
        "warm_cache_source": warm_source,
        "delta_cache_source": delta_source,
        "followup_cache_source": followup_source,
        "delta_cache_already_current": float(
            stv_close(delta_tv, followup_tv)
        ),
        "warm_cache_strength": 0.0 if warm_tv is None else warm_tv[0],
        "warm_cache_confidence": 0.0 if warm_tv is None else warm_tv[1],
        "delta_cache_strength": 0.0 if delta_tv is None else delta_tv[0],
        "delta_cache_confidence": 0.0 if delta_tv is None else delta_tv[1],
        "followup_cache_strength": 0.0 if followup_tv is None else followup_tv[0],
        "followup_cache_confidence": (
            0.0 if followup_tv is None else followup_tv[1]
        ),
        "initial_facts": float(initial_facts),
        "delta_count": float(deltas),
    }


def run_refold(
    *,
    handler_type: Any,
    total_facts: int,
    query_steps: int,
) -> dict[str, Any]:
    started = time.perf_counter()
    handler = handler_type()
    handler.add_atoms_no_check(initial_atoms(total_facts))
    setup_seconds = time.perf_counter() - started
    started = time.perf_counter()
    answers = handler.query(inversion_query(), steps=query_steps, timeout_sec=0)
    query_seconds = time.perf_counter() - started
    if not answers:
        raise OrdinaryBaseRateBenchmarkError(
            "refold inversion query returned no answers"
        )
    source, tv = cached_p_rate(handler)
    return {
        "refold_setup_seconds": setup_seconds,
        "refold_query_seconds": query_seconds,
        "refold_cache_source": source,
        "refold_cache_strength": 0.0 if tv is None else tv[0],
        "refold_cache_confidence": 0.0 if tv is None else tv[1],
        "refold_facts": float(total_facts),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Measure ordinary inversion base-rate maintenance after a computed "
            "snapshot. Not part of the default suite."
        )
    )
    parser.add_argument("--repository", type=Path, default=REPO_ROOT)
    parser.add_argument("--initial-facts", type=int, default=128)
    parser.add_argument("--deltas", type=int, default=32)
    parser.add_argument("--query-steps", type=int, default=2000)
    parser.add_argument("--forward-steps", type=int, default=1)
    parser.add_argument("--json-out", type=Path)
    arguments = parser.parse_args(argv)
    if arguments.initial_facts < 1 or arguments.deltas < 1:
        parser.error("--initial-facts and --deltas must be positive")
    try:
        handler_type = load_chainer(
            arguments.repository, OrdinaryBaseRateBenchmarkError
        )
        incremental = run_incremental(
            handler_type=handler_type,
            initial_facts=arguments.initial_facts,
            deltas=arguments.deltas,
            query_steps=arguments.query_steps,
            forward_steps=arguments.forward_steps,
        )
        refold = run_refold(
            handler_type=handler_type,
            total_facts=arguments.initial_facts + arguments.deltas,
            query_steps=arguments.query_steps,
        )
    except (OrdinaryBaseRateBenchmarkError, ImportError) as error:
        print(f"ordinary base-rate benchmark failed: {error}", file=sys.stderr)
        return 2
    metrics = {**incremental, **refold}
    print(json.dumps(metrics, indent=2, sort_keys=True))
    if arguments.json_out:
        write_json(arguments.json_out, metrics)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
