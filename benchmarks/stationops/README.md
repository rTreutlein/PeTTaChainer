# StationOps regression benchmark

This invokes `../../ChainerGame/src/stationops/game.py` directly: seed 7,
two shifts, four modules, diagnosis budget 600, action budget 1. It is the
workload recorded in ChainerGame's `benchmark-runs/2026-09-07/rerun.sh`.
ChainerGame owns the simulation, knowledge, adapter, and scoring.

From the PeTTaChainer repository:

```sh
.venv/bin/python benchmarks/stationops/compare.py 2e61e42 0b938c26 \
  --pairs 3 --output-dir /tmp/stationops-historical-ab
```

Use a new output directory for each comparison. The driver archives both
committed revisions without changing the working tree, freezes ChainerGame at
the recorded `99fc56e` revision (override with `--chainergame-ref`), and uses
the same PeTTa source from this repository's HEAD and
the same `.venv/bin/python` for every run. Other vendored source belongs to
each tested revision. It does not fetch or rebuild dependencies. Dirty source
edits are not benchmarked. Run benchmark processes sequentially without other
CPU-heavy work.

The order alternates AB, BA, AB. Every run retains full episode results,
proof answers, per-shift diagnosis times, Prolog inference counts, search
metrics, phase timings, and a process log. `metadata.json` records revisions
and the shared runtime tree. Source snapshots and raw results remain in the
output directory.

The command fails if coverage is incomplete, score differs from 637, regret
is nonzero, a search aborts, episode results differ after excluding timings
and backend counters, proof answers differ after normalizing runtime KB UUIDs,
or either shift's median diagnosis time or inference
count regresses by more than 5%. The tolerance is configurable with
`--max-regression-percent`; semantic differences still fail. Historical
comparisons that cross intentional reasoning changes may therefore fail
the semantic gate as well as the performance gate. Inspect the retained
results instead of treating equal scores as proof of equivalence.

For future changes, compare against both the preceding validated revision and
a fixed baseline. This expensive application benchmark is separate from
`scripts/verify.sh`; passing that script does not establish StationOps
performance. The historical runner is independent of benchmark files in the
tested revisions, so the same instrumentation executes on both sides.

The [refinement trace and depth ablation report](../../docs/metta/stationops_refinement_trace_2026-09-08.md)
records elapsed-time quality comparisons, additional seeds, and the existing
MeTTa suite results for the isolated scheduling experiment. Its compact evidence
includes the probe patches and drivers; these are diagnostic experiments, not
new benchmark acceptance defaults.
