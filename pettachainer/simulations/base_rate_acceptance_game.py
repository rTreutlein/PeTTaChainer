#!/usr/bin/env python3
"""End-to-end contract acceptance game driven by internal base-rate reasoning."""

from __future__ import annotations

import argparse
import json
import re
from dataclasses import asdict, dataclass
from typing import Dict, List, Optional, Sequence


STV_RE = re.compile(r"\((?:STV|stv)\s+([0-9.eE+-]+)\s+([0-9.eE+-]+)\)")


@dataclass(frozen=True)
class PredicateSpec:
    name: str
    true_rate: float
    success_reward: float = 80.0
    failure_cost: float = 30.0
    action_cost: float = 20.0


DEFAULT_PREDICATES = [
    PredicateSpec("Reliable", 0.90, success_reward=70.0, failure_cost=25.0, action_cost=20.0),
    PredicateSpec("Fast", 0.20, success_reward=95.0, failure_cost=20.0, action_cost=15.0),
    PredicateSpec("Cheap", 0.75, success_reward=60.0, failure_cost=15.0, action_cost=12.0),
    PredicateSpec("Local", 0.15, success_reward=65.0, failure_cost=12.0, action_cost=10.0),
    PredicateSpec("HighVolume", 0.95, success_reward=50.0, failure_cost=35.0, action_cost=18.0),
    PredicateSpec("Fragile", 0.05, success_reward=140.0, failure_cost=35.0, action_cost=20.0),
]


def parse_stv(raw: str) -> tuple[float, float]:
    match = STV_RE.search(raw)
    if match is None:
        raise ValueError(f"could not parse STV from {raw!r}")
    return float(match.group(1)), float(match.group(2))


def deterministic_bernoulli_prefix(true_rate: float, sample_count: int) -> List[int]:
    accumulator = 0.0
    samples = []
    for _ in range(sample_count):
        accumulator += true_rate
        if accumulator + 1.0e-12 >= 1.0:
            samples.append(1)
            accumulator -= 1.0
        else:
            samples.append(0)
    return samples


def samples_for(predicate: PredicateSpec, sample_count: int) -> List[int]:
    base = deterministic_bernoulli_prefix(predicate.true_rate, sample_count)
    offset = sum(ord(ch) for ch in predicate.name) % max(1, sample_count)
    return base[offset:] + base[:offset]


@dataclass(frozen=True)
class AcceptanceRow:
    sample_count: int
    backend: str
    contract: str
    true_rate: float
    accept_threshold: float
    accept_strength: float
    accept_confidence: float
    accepted: bool
    realized_expected_value: float


@dataclass(frozen=True)
class AcceptanceReport:
    rows: List[AcceptanceRow]
    accept_threshold_override: Optional[float]
    pettachainer_total_value: float
    libpln_fixed_total_value: Optional[float]
    libpln_uniform_total_value: Optional[float]
    value_delta_fixed: Optional[float]
    value_delta_uniform: Optional[float]
    libpln_fixed_available: bool
    libpln_fixed_message: str
    libpln_uniform_available: bool
    libpln_uniform_message: str


def contract_value(predicate: PredicateSpec) -> float:
    return (
        predicate.true_rate * predicate.success_reward
        - (1.0 - predicate.true_rate) * predicate.failure_cost
        - predicate.action_cost
    )


def break_even_probability(predicate: PredicateSpec) -> float:
    return (predicate.failure_cost + predicate.action_cost) / (predicate.success_reward + predicate.failure_cost)


def _acceptance_atoms(predicates: Sequence[PredicateSpec], sample_count: int) -> List[str]:
    atoms: List[str] = []
    for predicate in predicates:
        quality = f"{predicate.name}Good"
        signal = f"{predicate.name}ProbePaysOff"
        contract = f"contract{predicate.name}"
        atoms.append(
            f"(: signalRule_{predicate.name} "
            f"(Implication ({quality} $supplier) ({signal} $supplier)) "
            "(CTV (STV 0.8 0.9) (STV 0.1 0.9)))"
        )
        atoms.append(f"(: signal_{predicate.name} ({signal} {contract}) (STV 0.9 0.8))")
        atoms.append(
            f"(: acceptRule_{predicate.name} "
            f"(Implication ({quality} {contract}) (AcceptContract {contract})) "
            "(CTV (STV 1.0 1.0) (STV 0.0 1.0)))"
        )
        for index, value in enumerate(samples_for(predicate, sample_count), 1):
            atoms.append(
                f"(: obs_{predicate.name}_{index} "
                f"({quality} supplier_{predicate.name}_{index}) (STV {float(value)} 1.0))"
            )
    return atoms


def query_pettachainer_acceptance(
    predicates: Sequence[PredicateSpec],
    sample_count: int,
    steps: int = 800,
) -> Dict[str, tuple[float, float]]:
    from pettachainer import PeTTaChainer

    handler = PeTTaChainer()
    handler.add_atoms_no_check(_acceptance_atoms(predicates, sample_count))

    decisions: Dict[str, tuple[float, float]] = {}
    for predicate in predicates:
        contract = f"contract{predicate.name}"
        proofs = handler.query(
            f"(: $prf (AcceptContract {contract}) $tv)",
            steps=steps,
            timeout_sec=0,
        )
        if not proofs:
            raise RuntimeError(f"PeTTaChainer returned no accept decision for {contract}")
        decisions[predicate.name] = parse_stv(str(proofs[0]))
    return decisions


def _rows_for_backend(
    sample_count: int,
    backend: str,
    decisions: Dict[str, tuple[float, float]],
    predicates: Sequence[PredicateSpec],
    accept_threshold_override: Optional[float],
) -> List[AcceptanceRow]:
    rows = []
    for predicate in predicates:
        strength, confidence = decisions[predicate.name]
        accept_threshold = (
            accept_threshold_override
            if accept_threshold_override is not None
            else break_even_probability(predicate)
        )
        accepted = strength >= accept_threshold
        rows.append(
            AcceptanceRow(
                sample_count=sample_count,
                backend=backend,
                contract=f"contract{predicate.name}",
                true_rate=predicate.true_rate,
                accept_threshold=accept_threshold,
                accept_strength=strength,
                accept_confidence=confidence,
                accepted=accepted,
                realized_expected_value=contract_value(predicate) if accepted else 0.0,
            )
        )
    return rows


def _libpln_modus_ponens_acceptance(estimates: Dict[str, tuple[float, float]]) -> Dict[str, tuple[float, float]]:
    return {
        name: (strength + 0.02 * (1.0 - strength), confidence)
        for name, (strength, confidence) in estimates.items()
    }


def _fixed_libpln_acceptance(
    predicates: Sequence[PredicateSpec],
    prior_strength: float = 0.5,
    prior_confidence: float = 0.01,
) -> Dict[str, tuple[float, float]]:
    priors = {predicate.name: (prior_strength, prior_confidence) for predicate in predicates}
    return _libpln_modus_ponens_acceptance(priors)


def _uniform_libpln_acceptance(
    predicates: Sequence[PredicateSpec],
    prior_confidence: float = 0.01,
) -> Dict[str, tuple[float, float]]:
    if not predicates:
        return {}
    prior_strength = 1.0 / len(predicates)
    priors = {predicate.name: (prior_strength, prior_confidence) for predicate in predicates}
    return _libpln_modus_ponens_acceptance(priors)


def run_acceptance_game(
    sample_counts: Sequence[int] = (10, 25, 50, 100),
    predicates: Sequence[PredicateSpec] = DEFAULT_PREDICATES,
    accept_threshold: Optional[float] = None,
    include_libpln: bool = True,
) -> AcceptanceReport:
    rows: List[AcceptanceRow] = []
    fixed_available = include_libpln
    fixed_message = "ok" if include_libpln else "disabled"
    uniform_available = include_libpln
    uniform_message = "ok" if include_libpln else "disabled"
    fixed_decisions: Dict[str, tuple[float, float]] = {}
    uniform_decisions: Dict[str, tuple[float, float]] = {}

    if include_libpln:
        fixed_decisions = _fixed_libpln_acceptance(predicates)
        uniform_decisions = _uniform_libpln_acceptance(predicates)

    for sample_count in sample_counts:
        pettachainer_decisions = query_pettachainer_acceptance(predicates, sample_count)
        rows.extend(
            _rows_for_backend(
                sample_count,
                "pettachainer",
                pettachainer_decisions,
                predicates,
                accept_threshold,
            )
        )
        if fixed_decisions:
            rows.extend(_rows_for_backend(sample_count, "libpln_fixed", fixed_decisions, predicates, accept_threshold))
        if uniform_decisions:
            rows.extend(_rows_for_backend(sample_count, "libpln_uniform", uniform_decisions, predicates, accept_threshold))

    pc_value = sum(row.realized_expected_value for row in rows if row.backend == "pettachainer")
    fixed_values = [row.realized_expected_value for row in rows if row.backend == "libpln_fixed"]
    uniform_values = [row.realized_expected_value for row in rows if row.backend == "libpln_uniform"]
    fixed_value = sum(fixed_values) if fixed_values else None
    uniform_value = sum(uniform_values) if uniform_values else None
    return AcceptanceReport(
        rows=rows,
        accept_threshold_override=accept_threshold,
        pettachainer_total_value=pc_value,
        libpln_fixed_total_value=fixed_value,
        libpln_uniform_total_value=uniform_value,
        value_delta_fixed=(pc_value - fixed_value) if fixed_value is not None else None,
        value_delta_uniform=(pc_value - uniform_value) if uniform_value is not None else None,
        libpln_fixed_available=fixed_available,
        libpln_fixed_message=fixed_message,
        libpln_uniform_available=uniform_available,
        libpln_uniform_message=uniform_message,
    )


def parse_counts(raw: str) -> List[int]:
    return [int(item.strip()) for item in raw.split(",") if item.strip()]


def print_report(report: AcceptanceReport) -> None:
    print(
        "\t".join(
            [
                "samples",
                "backend",
                "contract",
                "true_rate",
                "accept_threshold",
                "accept_strength",
                "accept_conf",
                "accepted",
                "realized_expected_value",
            ]
        )
    )
    for row in report.rows:
        print(
            "\t".join(
                [
                    str(row.sample_count),
                    row.backend,
                    row.contract,
                    f"{row.true_rate:.6f}",
                    f"{row.accept_threshold:.6f}",
                    f"{row.accept_strength:.6f}",
                    f"{row.accept_confidence:.6f}",
                    str(row.accepted),
                    f"{row.realized_expected_value:.6f}",
                ]
            )
        )
    print(
        "accept_threshold_override\t"
        + ("" if report.accept_threshold_override is None else f"{report.accept_threshold_override:.6f}")
    )
    print(f"pettachainer_total_value\t{report.pettachainer_total_value:.6f}")
    if report.libpln_fixed_total_value is not None:
        print(f"libpln_fixed_total_value\t{report.libpln_fixed_total_value:.6f}")
    if report.libpln_uniform_total_value is not None:
        print(f"libpln_uniform_total_value\t{report.libpln_uniform_total_value:.6f}")
    if report.value_delta_fixed is not None:
        print(f"value_delta_pettachainer_minus_libpln_fixed\t{report.value_delta_fixed:.6f}")
    if report.value_delta_uniform is not None:
        print(f"value_delta_pettachainer_minus_libpln_uniform\t{report.value_delta_uniform:.6f}")
    print(f"libpln_fixed_available\t{report.libpln_fixed_available}\t{report.libpln_fixed_message}")
    print(f"libpln_uniform_available\t{report.libpln_uniform_available}\t{report.libpln_uniform_message}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the end-to-end base-rate acceptance game.")
    parser.add_argument("--samples", default="10,25,50,100")
    parser.add_argument(
        "--accept-threshold",
        type=float,
        default=None,
        help="Override the payoff-derived break-even threshold for every contract.",
    )
    parser.add_argument("--no-libpln", action="store_true")
    parser.add_argument("--json-out", default="")
    args = parser.parse_args()

    report = run_acceptance_game(
        sample_counts=parse_counts(args.samples),
        accept_threshold=args.accept_threshold,
        include_libpln=not args.no_libpln,
    )
    print_report(report)
    if args.json_out:
        with open(args.json_out, "w", encoding="ascii") as output:
            json.dump(asdict(report), output, indent=2)


if __name__ == "__main__":
    main()
