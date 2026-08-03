"""Runnable diagnosis of the StationOps base-rate inversion input.

Run from the repository root with::

    ./.venv/bin/python -m pettachainer.simulations.stationops_base_rate

The example distinguishes obsolete implication-side syntax, explicit logical
negation, zero-strength population observations, and adapter-provided rates.
"""

from __future__ import annotations

import re

from pettachainer import PeTTaChainer


QUERY = "(: $prf (PatchPaysOff old current-008) $tv)"
LEAK_BASE_RATE = 0.05
ALARM_GIVEN_LEAK = 0.9
ALARM_GIVEN_NO_LEAK = 0.12
ALARM_BASE_RATE = (
    LEAK_BASE_RATE * ALARM_GIVEN_LEAK
    + (1.0 - LEAK_BASE_RATE) * ALARM_GIVEN_NO_LEAK
)
EXPECTED_POSTERIOR = ALARM_GIVEN_LEAK * LEAK_BASE_RATE / ALARM_BASE_RATE

CURRENT_RULES = [
    "(: alarmGivenLeak "
    "(Implication (SealLeak $cohort $unit) (PressureAlarm $cohort $unit)) "
    "(CTV (STV 0.9 1.0) (STV 0.12 1.0)))",
    "(: patchGoal "
    "(Implication (SealLeak $cohort $unit) (PatchPaysOff $cohort $unit)) "
    "(CTV (STV 1.0 1.0) (STV 0.0 1.0)))",
]

TAGGED_RULES = [
    "(: alarmGivenLeak "
    "(Implication (Premises (SealLeak $cohort $unit)) "
    "(Conclusions (PressureAlarm $cohort $unit))) "
    "(CTV (STV 0.9 1.0) (STV 0.12 1.0)))",
    "(: patchGoal "
    "(Implication (Premises (SealLeak $cohort $unit)) "
    "(Conclusions (PatchPaysOff $cohort $unit))) "
    "(CTV (STV 1.0 1.0) (STV 0.0 1.0)))",
]

NOT_HISTORY = [
    "(: leak-h-old-0020 (SealLeak old h-old-0020) (STV 1.0 1.0))",
    "(: alarm-h-old-0020 (PressureAlarm old h-old-0020) (STV 1.0 1.0))",
    "(: leak-h-old-0000 (Not (SealLeak old h-old-0000)) (STV 1.0 1.0))",
    "(: alarm-h-old-0000 (Not (PressureAlarm old h-old-0000)) (STV 1.0 1.0))",
    "(: observed-current-008 (PressureAlarm old current-008) (STV 1.0 1.0))",
]

ZERO_STRENGTH_HISTORY = [
    "(: leak-h-old-0020 (SealLeak old h-old-0020) (STV 1.0 1.0))",
    "(: alarm-h-old-0020 (PressureAlarm old h-old-0020) (STV 1.0 1.0))",
    "(: leak-h-old-0000 (SealLeak old h-old-0000) (STV 0.0 1.0))",
    "(: alarm-h-old-0000 (PressureAlarm old h-old-0000) (STV 0.0 1.0))",
    "(: observed-current-008 (PressureAlarm old current-008) (STV 1.0 1.0))",
]


def query(atoms: list[str], *, pin_population_rates: bool = False) -> list[str]:
    handler = PeTTaChainer()
    handler.add_atoms_no_check(atoms)
    if pin_population_rates:
        # The generic rules compile open base-rate patterns. The StationOps
        # adapter has already selected the old-cohort population, so publish
        # that population's sufficient statistics against those patterns.
        handler.handler.process_metta_string(
            f"!(set-base-rate {handler.kb} "
            f"(SealLeak $cohort $unit) (STV {LEAK_BASE_RATE} 1.0))"
        )
        handler.handler.process_metta_string(
            f"!(set-base-rate {handler.kb} "
            f"(PressureAlarm $cohort $unit) (STV {ALARM_BASE_RATE} 1.0))"
        )
    return handler.query(QUERY, steps=200, timeout_sec=0)


def result_strength(proof: str) -> float:
    matches = re.findall(r"\(STV ([^ ]+) ([^)]+)\)", proof)
    if not matches:
        raise ValueError(f"No STV in proof: {proof}")
    return float(matches[-1][0])


def main() -> None:
    tagged = query(TAGGED_RULES + NOT_HISTORY)
    current_not = query(CURRENT_RULES + NOT_HISTORY)
    current_zero = query(CURRENT_RULES + ZERO_STRENGTH_HISTORY)
    explicit_rates = query(
        CURRENT_RULES + NOT_HISTORY,
        pin_population_rates=True,
    )

    print(f"tagged implication + Not history: {len(tagged)} proof(s)")
    print(f"current implication + Not history: {len(current_not)} proof(s)")
    print(
        "current implication + zero-strength history: "
        f"{len(current_zero)} proof(s)"
    )
    print(f"current implication + explicit population rates: {explicit_rates[0]}")

    if tagged or current_not:
        raise AssertionError("malformed/underspecified inputs unexpectedly proved the goal")
    if not current_zero:
        raise AssertionError("zero-strength population observations were not aggregated")
    actual = result_strength(explicit_rates[0])
    print(f"posterior={actual:.12f} expected={EXPECTED_POSTERIOR:.12f}")
    if abs(actual - EXPECTED_POSTERIOR) > 1e-12:
        raise AssertionError(f"unexpected posterior: {actual}")


if __name__ == "__main__":
    main()
