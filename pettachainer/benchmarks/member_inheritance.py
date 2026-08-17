#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import math
import re
import sys
import time
from pathlib import Path
from typing import Any, Sequence

from _benchmark_support import load_chainer, write_json


REPO_ROOT = Path(__file__).resolve().parents[2]
NUMBER = r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?"
TV_PATTERN = re.compile(rf"\(STV\s+({NUMBER})\s+({NUMBER})\)")


class MemberInheritanceBenchmarkError(RuntimeError):
    pass


def extract_truth_values(answers: Sequence[Any]) -> list[tuple[float, float]]:
    values: list[tuple[float, float]] = []
    for answer in answers:
        values.extend(
            (float(strength), float(confidence))
            for strength, confidence in TV_PATTERN.findall(str(answer))
        )
    return values


def validate_truth_value(
    answers: Sequence[Any],
    *,
    expected_strength: float,
    expected_confidence: float,
    tolerance: float = 1e-6,
) -> tuple[float, float]:
    values = extract_truth_values(answers)
    for strength, confidence in values:
        if math.isclose(
            strength, expected_strength, abs_tol=tolerance
        ) and math.isclose(confidence, expected_confidence, abs_tol=tolerance):
            return strength, confidence
    raise MemberInheritanceBenchmarkError(
        "member inheritance query did not contain the expected truth value "
        f"(STV {expected_strength} {expected_confidence}); got {values or answers!r}"
    )


def member_statements(index: int, strength: float) -> tuple[str, str]:
    object_name = f"memberBenchObject{index}"
    return (
        f"(: memberBenchSubject{index} "
        f"(Member {object_name} MemberBenchSubject) (STV 1.0 1.0))",
        f"(: memberBenchConcept{index} "
        f"(Member {object_name} MemberBenchConcept) (STV {strength} 1.0))",
    )


def inheritance_query() -> str:
    return (
        "(: $memberBenchProof "
        "(Inheritance MemberBenchSubject MemberBenchConcept) "
        "$memberBenchTV)"
    )


def run_incremental_benchmark(
    *,
    repository: Path,
    initial_members: int,
    deltas: int,
    member_strength: float,
    query_steps: int,
    forward_steps: int,
) -> dict[str, float]:
    if initial_members < 1 or deltas < 1:
        raise MemberInheritanceBenchmarkError(
            "initial-members and deltas must both be positive"
        )
    if not 0.0 <= member_strength <= 1.0:
        raise MemberInheritanceBenchmarkError("member-strength must be in [0, 1]")

    chainer_type = load_chainer(repository, MemberInheritanceBenchmarkError)
    total_members = initial_members + deltas

    started = time.perf_counter()
    handler = chainer_type()
    handler.handler.process_metta_string(
        f"!(set-universe-size {handler.kb} {float(total_members)})"
    )
    initial_atoms = [
        atom
        for index in range(initial_members)
        for atom in member_statements(index, member_strength)
    ]
    handler.add_atoms_no_check(initial_atoms)
    initial_load_seconds = time.perf_counter() - started

    query = inheritance_query()
    started = time.perf_counter()
    warm_answers = handler.query(query, steps=query_steps, timeout_sec=0)
    warm_query_seconds = time.perf_counter() - started
    validate_truth_value(
        warm_answers,
        expected_strength=member_strength,
        expected_confidence=initial_members / total_members,
    )

    add_seconds = 0.0
    forward_seconds = 0.0
    query_seconds = 0.0
    final_strength = 0.0
    final_confidence = 0.0
    final_result_count = 0
    for offset in range(deltas):
        index = initial_members + offset
        subject_statement, concept_statement = member_statements(
            index, member_strength
        )

        started = time.perf_counter()
        handler.add_atoms_no_check([subject_statement, concept_statement])
        selected = handler.select_facts(
            f"(Member memberBenchObject{index} MemberBenchConcept)"
        )
        add_seconds += time.perf_counter() - started

        started = time.perf_counter()
        handler.forward_chain(selected, steps=forward_steps)
        forward_seconds += time.perf_counter() - started

        started = time.perf_counter()
        answers = handler.query(query, steps=query_steps, timeout_sec=0)
        query_seconds += time.perf_counter() - started
        final_strength, final_confidence = validate_truth_value(
            answers,
            expected_strength=member_strength,
            expected_confidence=(index + 1) / total_members,
        )
        final_result_count = len(answers)

    delta_total_seconds = add_seconds + forward_seconds + query_seconds
    return {
        "member_initial_load_seconds": initial_load_seconds,
        "member_warm_query_seconds": warm_query_seconds,
        "member_delta_add_seconds": add_seconds,
        "member_delta_forward_seconds": forward_seconds,
        "member_delta_query_seconds": query_seconds,
        "member_delta_total_seconds": delta_total_seconds,
        "member_delta_query_mean_seconds": query_seconds / deltas,
        "member_final_strength": final_strength,
        "member_final_confidence": final_confidence,
        "member_final_result_count": float(final_result_count),
        "member_initial_count": float(initial_members),
        "member_delta_count": float(deltas),
    }


def run_forward_population_benchmark(
    *,
    repository: Path,
    members: int,
    member_strength: float,
    query_steps: int,
    forward_steps: int,
) -> dict[str, float]:
    if members < 1:
        raise MemberInheritanceBenchmarkError("initial-members must be positive")
    if not 0.0 <= member_strength <= 1.0:
        raise MemberInheritanceBenchmarkError("member-strength must be in [0, 1]")

    chainer_type = load_chainer(repository, MemberInheritanceBenchmarkError)
    started = time.perf_counter()
    handler = chainer_type()
    handler.handler.process_metta_string(
        f"!(set-universe-size {handler.kb} {float(members)})"
    )
    setup_seconds = time.perf_counter() - started

    query = inheritance_query()
    started = time.perf_counter()
    registration_answers = handler.query(query, steps=0, timeout_sec=0)
    registration_seconds = time.perf_counter() - started

    add_seconds = 0.0
    select_seconds = 0.0
    forward_seconds = 0.0
    for index in range(members):
        subject_statement, concept_statement = member_statements(
            index, member_strength
        )
        started = time.perf_counter()
        handler.add_atoms_no_check([subject_statement, concept_statement])
        add_seconds += time.perf_counter() - started

        started = time.perf_counter()
        selected = handler.select_facts(
            [
                f"(Member memberBenchObject{index} MemberBenchSubject)",
                f"(Member memberBenchObject{index} MemberBenchConcept)",
            ]
        )
        select_seconds += time.perf_counter() - started

        started = time.perf_counter()
        handler.forward_chain(selected, steps=forward_steps)
        forward_seconds += time.perf_counter() - started

    started = time.perf_counter()
    answers = handler.query(query, steps=query_steps, timeout_sec=0)
    final_query_seconds = time.perf_counter() - started
    final_strength, final_confidence = validate_truth_value(
        answers,
        expected_strength=member_strength,
        expected_confidence=1.0,
    )

    build_seconds = add_seconds + select_seconds + forward_seconds
    return {
        "member_population_setup_seconds": setup_seconds,
        "member_population_registration_seconds": registration_seconds,
        "member_population_add_seconds": add_seconds,
        "member_population_select_seconds": select_seconds,
        "member_population_forward_seconds": forward_seconds,
        "member_population_build_seconds": build_seconds,
        "member_population_final_query_seconds": final_query_seconds,
        "member_population_total_seconds": (
            setup_seconds + registration_seconds + build_seconds + final_query_seconds
        ),
        "member_population_expected_tv_present": 1.0,
        "member_population_final_strength": final_strength,
        "member_population_final_confidence": final_confidence,
        "member_population_final_result_count": float(len(answers)),
        "member_population_registration_result_count": float(
            len(registration_answers)
        ),
        "member_initial_count": float(members),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Measure incremental Member-to-Inheritance maintenance or build a "
            "forward-populated Member inheritance cache"
        )
    )
    parser.add_argument("--candidate-repo", type=Path, default=REPO_ROOT)
    parser.add_argument("--initial-members", type=int, default=48)
    parser.add_argument("--deltas", type=int, default=4)
    parser.add_argument("--member-strength", type=float, default=0.6)
    parser.add_argument("--query-steps", type=int, default=400)
    parser.add_argument("--forward-steps", type=int, default=1)
    parser.add_argument(
        "--population-mode",
        choices=("backward-warm", "forward-populate"),
        default="backward-warm",
    )
    parser.add_argument("--json-out", type=Path)
    arguments = parser.parse_args(argv)
    try:
        if arguments.population_mode == "forward-populate":
            metrics = run_forward_population_benchmark(
                repository=arguments.candidate_repo,
                members=arguments.initial_members,
                member_strength=arguments.member_strength,
                query_steps=arguments.query_steps,
                forward_steps=arguments.forward_steps,
            )
        else:
            metrics = run_incremental_benchmark(
                repository=arguments.candidate_repo,
                initial_members=arguments.initial_members,
                deltas=arguments.deltas,
                member_strength=arguments.member_strength,
                query_steps=arguments.query_steps,
                forward_steps=arguments.forward_steps,
            )
    except (MemberInheritanceBenchmarkError, ImportError) as error:
        print(f"member inheritance benchmark failed: {error}", file=sys.stderr)
        return 2
    print(json.dumps(metrics, indent=2, sort_keys=True))
    if arguments.json_out:
        write_json(arguments.json_out, metrics)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
