"""Runnable diagnosis of the StationOps base-rate inversion input.

Run from the repository root with::

    ./.venv/bin/python -m pettachainer.simulations.stationops_base_rate

The example distinguishes obsolete implication-side syntax, explicit logical
negation, and canonical zero-strength population observations.
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


def query(atoms: list[str]) -> list[str]:
    handler = PeTTaChainer()
    handler.add_atoms_no_check(atoms)
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

    print(f"tagged implication + Not history: {len(tagged)} proof(s)")
    if tagged:
        raise AssertionError("obsolete implication-side tags unexpectedly proved the goal")
    if not current_not or not current_zero:
        raise AssertionError("historical negative observations were not aggregated")
    print(f"current implication + Not history: {current_not[0]}")
    print(f"current implication + zero-strength history: {current_zero[0]}")
    not_strength = result_strength(current_not[0])
    zero_strength = result_strength(current_zero[0])
    if abs(not_strength - zero_strength) > 1e-12:
        raise AssertionError(
            "Not and zero-strength encodings produced different strengths: "
            f"{not_strength} != {zero_strength}"
        )
    print(f"representative posterior={not_strength:.12f}")
    print(f"full-population target={EXPECTED_POSTERIOR:.12f}")


if __name__ == "__main__":
    main()
