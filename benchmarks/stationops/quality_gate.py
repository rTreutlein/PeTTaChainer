#!/usr/bin/env python3
"""Screen completed StationOps runs against a fixed quality reference.

Exit 1 means regression or an unresolved comparison, never permission to trade
answer quality for speed. Timing is reported only; repeat interleaved pairs
before making performance claims. Use compare.py for exact proof preservation.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path


def compare_quality(reference, candidate):
    if reference["workload"] != candidate["workload"]:
        raise ValueError("Workloads differ")
    expected = reference["workload"]["shifts"]
    sides = (reference, candidate)
    if any(len(run["result"]["rounds"]) != expected or
           len(run["batches"]) != expected for run in sides):
        raise ValueError("Incomplete episode")
    failures, unresolved, shifts = [], [], []
    for index in range(expected):
        rows = [run["result"]["rounds"][index] for run in sides]
        batches = [run["batches"][index] for run in sides]
        shift = index + 1
        if any(row["shift"] != shift for row in rows + batches):
            raise ValueError("Shift order differs")
        if any(batch["metrics"]["search_aborts"] for batch in batches):
            failures.append(f"shift {shift}: search aborted")
        comparisons = {}
        for field, metrics in (("beliefs", "belief_metrics"),
                               ("decision_beliefs", "decision_belief_metrics")):
            covered = [{key for key, value in row[field].items()
                        if isinstance(value, (int, float)) and math.isfinite(value)}
                       for row in rows]
            lost = sorted(covered[0] - covered[1])
            gained = sorted(covered[1] - covered[0])
            if lost:
                failures.append(f"shift {shift} {field}: lost answers {lost}")
            error = {}
            if covered[0] != covered[1]:
                unresolved.append(f"shift {shift} {field}: error averages cover different goals")
            elif not covered[0]:
                unresolved.append(f"shift {shift} {field}: no answers to score")
            else:
                for metric in ("mean_absolute_error", "max_absolute_error", "brier_score", "log_loss"):
                    values = [row[metrics][metric] for row in rows]
                    if any(value is None or not math.isfinite(value) for value in values):
                        unresolved.append(f"shift {shift} {field}: missing {metric}")
                        continue
                    passed = values[1] <= values[0] + 1e-12
                    error[metric] = dict(reference=values[0], candidate=values[1], passed=passed)
                    if not passed:
                        failures.append(f"shift {shift} {field}: worse {metric}")
            comparisons[field] = dict(reference_coverage=len(covered[0]),
                                      candidate_coverage=len(covered[1]), lost=lost,
                                      gained=gained, error=error)
        if rows[0]["visible_incidents"] != rows[1]["visible_incidents"]:
            unresolved.append(f"shift {shift}: visible episode inputs differ")
        if rows[1]["regret"] > rows[0]["regret"] + 1e-12:
            failures.append(f"shift {shift}: worse regret")
        if index and any(reference["result"]["rounds"][previous][field] !=
                         candidate["result"]["rounds"][previous][field]
                         for previous in range(index)
                         for field in ("inspections", "chosen_repairs", "resolution")):
            unresolved.append(f"shift {shift}: preceding episode actions or outcomes differ")
        shifts.append(dict(shift=shift, quality=comparisons,
                           diagnosis_seconds=dict(reference=batches[0]["seconds"],
                                                  candidate=batches[1]["seconds"])))
    aggregates = [run["result"]["aggregate"] for run in sides]
    if aggregates[1]["station_score"] < aggregates[0]["station_score"]:
        failures.append("Lower episode score")
    return dict(passed=not failures and not unresolved, failures=failures,
                unresolved=unresolved, shifts=shifts)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reference", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--json-out", type=Path)
    args = parser.parse_args()
    result = compare_quality(json.loads(args.reference.read_text()),
                             json.loads(args.candidate.read_text()))
    output = json.dumps(result, indent=2) + "\n"
    if args.json_out:
        args.json_out.write_text(output)
    print(output, end="")
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
