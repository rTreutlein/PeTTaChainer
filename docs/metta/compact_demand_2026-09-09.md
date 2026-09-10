# Compact demand projection experiment

The candidate changes demand bookkeeping without adding a state store or
changing priority policy. `goal-root-demands-walk` projects each full waiter
into a compact `WaiterDemand` before collecting its list. The projection
carries parent, score cap, path ID, candidate score, and remaining premise count;
aggregate waiters retain their parent and aggregate-demand mode. Full proof
bundles, used evidence, and premise parts remain in the delivery registry.

Projection preserves the registry's order and multiplicity: two distinct proof
contexts with identical scheduling inputs still produce two demand entries.
`goal-shallower?` fetches only the indexed goal depth. Registration and demand
cache rebuilds still bump revisions unconditionally; path-liveness, confidence,
shallower-parent checks, and consumer proof selection are unchanged.

The compact projection is also used for incremental waiter registration. Its
Atom input is an unevaluated stored-term boundary. The old internal
`waiter-root-demands` signature is replaced, and its test caller is updated;
no public API signature changes or compatibility wrapper is introduced.

## Validation

The complete `scripts/verify.sh` passes on the final candidate:

- 75 MeTTa files, strict mode and strict determinism, zero failures.
- 49 Python tests, with 46 metric rows and zero search aborts.
- Import scaling late/early median ratio 1.039, below 1.500.
- ConceptNet passes with exactly two results and no abort marker.

Focused assertions cover existing stale-priority/dead-path transitions and the
new projection's duplicate/order preservation, both aggregate demand modes,
ignored non-waiters, and strict depth ordering including a missing goal.
No existing result expectation changes. Full verification took 206 seconds.

## Measurement setup

Baseline is frozen PeTTaChainer `4a9593dd5eea83f3ba0277f8fe4d216b9033a5e9`.
Candidate applies `candidate.patch` to that source. Both use the required
PeTTa branch snapshot `e1aac8b791cf70b7843173b613f04b869b666979` and frozen
ChainerGame `99fc56e4ddd0d718f00e494146b0ff1884e5fc5e`. No fetch or rebuild.
The sibling live PeTTa integration checkout was not switched or modified.

Each episode has two shifts, four modules, action budget 1; diagnosis budget
is 600 for seed 7 and 300 for seeds 11 and 23. Runs are sequential and alternate
order: compact/base for seed 7, base/compact for seed 11, compact/base for seed
23. No verification runs overlap timed episodes. This is one paired run per
seed, suitable for screening rather than a repeated performance acceptance test.
Diagnosis times exclude initialization, KB updates, and action selection.

## Results

Total diagnosis time over both shifts:

| Seed / pair | Baseline seconds | Compact seconds | Reduction | Shift 2 coverage |
|---|---:|---:|---:|---:|
| 7 | 126.78 | 92.06 | 27.4% | 100% |
| 11 | 22.89 | 9.01 | 60.6% | 50% |
| 11 repeat | 8.28 | 6.87 | 17.0% | 50% |
| 23 | 5.43 | 4.88 | 10.2% | 50% |

The first seed-11 baseline is anomalous: shift two consumed 20.07 seconds of wall time and 20.11 seconds of CPU, versus 5.95/5.90 seconds in the repeat, at the identical inference count. The cause of that outlier was not established. The repeat reverses execution order and gives a 17.0% total reduction; do not advertise the first pair's 60.6% as a stable speedup. Both pairs are retained in the evidence.

Seed 7 shift two improves from 113.06 to 79.68 seconds (29.5%). Its inference count falls only from 436,243,039 to 429,510,287 (1.5%), consistent with making term handling cheaper per operation. This is not a new time profile and does not establish exclusive attribution between waiter projection and depth-only lookup.

Across all eight episodes / sixteen diagnosis batches, answers and full proof strings match after normalizing KB UUIDs; every non-timing backend query metric also matches within each comparison. Beliefs, coverage, Brier scores, station scores, and regret are unchanged. All sixteen batches report zero search aborts. No expected truth-value or proof result was rewritten to pass the tests.

Coverage remains 100% for seed 7 and 50% for seeds 11 and 23. This is a bookkeeping optimization, not a coverage repair or a resolution of the whole historical performance regression. It leaves depth, exploration, selection, and probability formulas unchanged.

## Handoff

Implemented on isolated branch `experiment/compact-demand`, worktree `/tmp/pettachainer-compact-demand`, to preserve Claude's active checkout. Core commit: `322179b2`; tests and evidence are a separate following commit. The validated archive and branch source are byte-identical for both changed code/test files.

The machine-readable evidence is `compact-demand-results-2026-09-09.json` (removed from the tree to keep it small; retrieve it with `git show 94a52ce9:benchmarks/stationops/compact-demand-results-2026-09-09.json`) on that branch. It contains the full source patch, benchmark/analyzer, all eight results, and verification logs. Full local artifacts are also in `scratch/compact-demand-2026-09-09/` in the original checkout. Baseline, runtime, game revisions and initial status are recorded in `metadata.json`.

Reproduce with the pinned `.venv/bin/petta` through `PETTA_STRICT=1 PETTA_JOBS=8 scripts/test_metta.sh`, or the full `scripts/verify.sh`. For the isolated archive, set `PETTA_PATH` to the frozen supported runtime, `PYTHONPATH` to the archive plus that runtime's `python` directory, and `GIT_DIR`/`GIT_WORK_TREE` to the original repository metadata and archive respectively. The benchmark driver uses `.venv/bin/python` and explicitly verifies all three source import paths.
