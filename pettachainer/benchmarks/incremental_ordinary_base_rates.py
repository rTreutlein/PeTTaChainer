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


INVERSION_QUERY = "(: $prf (P alice) $tv)"


def cached_p_rate(handler: Any, prefix: str) -> tuple[dict[str, Any], tuple[float, float] | None]:
    """The cached ``P($x)`` rate's source and truth value as ``prefix``
    fields, and the truth value."""
    text = str(handler.handler.process_metta_string(
        f"!(base-rate-cache-entries {handler.kb} (P $x))"
    ))
    source = SOURCE_PATTERN.search(text)
    match = STV_PATTERN.search(text)
    tv = (float(match.group(1)), float(match.group(2))) if match else None
    return {
        f"{prefix}_cache_source": source.group(1) if source else "missing",
        f"{prefix}_cache_strength": tv[0] if tv else 0.0,
        f"{prefix}_cache_confidence": tv[1] if tv else 0.0,
    }, tv


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

    started = time.perf_counter()
    warm_answers = handler.query(INVERSION_QUERY, steps=query_steps, timeout_sec=0)
    warm_query_seconds = time.perf_counter() - started
    if not warm_answers:
        raise OrdinaryBaseRateBenchmarkError(
            "warm inversion query returned no answers"
        )
    warm, warm_tv = cached_p_rate(handler, "warm")
    if warm["warm_cache_source"] != "computed" or warm_tv is None:
        raise OrdinaryBaseRateBenchmarkError(
            f"warm query did not harvest a computed P($x) rate: {warm!r}"
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

    delta, delta_tv = cached_p_rate(handler, "delta")
    started = time.perf_counter()
    followup_answers = handler.query(INVERSION_QUERY, steps=query_steps, timeout_sec=0)
    followup_query_seconds = time.perf_counter() - started
    if not followup_answers:
        raise OrdinaryBaseRateBenchmarkError(
            "follow-up inversion query returned no answers"
        )
    followup, followup_tv = cached_p_rate(handler, "followup")
    return {
        "setup_seconds": setup_seconds,
        "warm_query_seconds": warm_query_seconds,
        "delta_add_seconds": add_seconds,
        "delta_forward_seconds": forward_seconds,
        "delta_total_seconds": add_seconds + forward_seconds,
        "followup_query_seconds": followup_query_seconds,
        **warm,
        **delta,
        **followup,
        "delta_cache_already_current": float(
            delta_tv is not None and followup_tv is not None
            and all(abs(a - b) <= 1e-9 for a, b in zip(delta_tv, followup_tv))
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
    answers = handler.query(INVERSION_QUERY, steps=query_steps, timeout_sec=0)
    query_seconds = time.perf_counter() - started
    if not answers:
        raise OrdinaryBaseRateBenchmarkError(
            "refold inversion query returned no answers"
        )
    return {
        "refold_setup_seconds": setup_seconds,
        "refold_query_seconds": query_seconds,
        **cached_p_rate(handler, "refold")[0],
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
