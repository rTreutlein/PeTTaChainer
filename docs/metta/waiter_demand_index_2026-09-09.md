# Waiter demand index: exact behavior and measured cost

The index makes repeated demand calculation cheaper by storing each waiter's
existing compact scheduling inputs once at registration. On the fixed seed-11
workload, three alternating baseline/candidate pairs improve diagnosis wall and
CPU time by about 4%, with about 12 MiB more peak process memory. The complete
proofs, results and non-time search metrics match on all three development
workloads. This is an additional bookkeeping improvement over the earlier
compact projection and proof caches, not a change to scheduler policy.

Core commit: `bb1664ef`, based on clean
`68f76534ff69cb8165445c9ca036c2a00c5b8328`. The tested archive's 283 inventoried
files match the isolated worktree byte-for-byte before adding this report and
its compact evidence JSON. Runtime files and tested assertions are unchanged.

## Implementation

`&goal_waiter_demand` stores `(child GID, WaiterDemand)` rows. Registration keeps
the complete proof-bearing waiter in its delivery registry and projects the
compact row at the original evaluation point. Both registries preserve order
and duplicates until query reset. Demand still reads live goal depths,
confidence and path validity; all priority-revision events remain unchanged.
No evaluated priority, consumer result, new coefficient or depth is cached.

An erased-space extraction restores the three disjoint demand constructors.
Its compiled clauses are shallow identities with cuts. A generic `the` cast at
that boundary instead performs reflective validation costing 42 inferences per
read; that first implementation was rejected. The extraction helper preserves
the existing algebraic type and is needed at the compiler boundary. The old
single-use incremental-update wrapper is removed.

The depth check also compares within its existing indexed lookup and directly
extracts the resulting Boolean. Missing goals still return false, depth changes
remain visible, and goal variables stay unbound. This removes one inference
per check; its isolated CPU measurements did not establish a speedup.

## Validation

The pinned `.venv/bin/petta` runs through `scripts/test_metta.sh`. Full
`scripts/verify.sh`, with strict mode and strict determinism, passes:

| Gate | Result |
|---|---|
| MeTTa | 78 files passed, zero failures |
| Python | 57 tests passed; 46 metric rows, zero aborts |
| Import scaling | 1.001 ratio, below 1.500 |
| ConceptNet | Exactly two answers |
| Separate unchanged late-evidence regression | Passed; four metric rows, zero aborts |

The new focused assertions cover duplicate registrations, equal projections,
ordering across child IDs, cached/live aggregate modes, proof-variable copy
isolation, query reset with reused IDs, and live shallower-depth updates.
Existing public proof/TV assertions and budgets were not changed. Independent
review checked registration ownership, generated code, freshness and reset.

Every seed-7/600, seed-11/300 and seed-23/300 episode uses two shifts, four
modules and action budget one. Full returned proofs, queries, public results
including backend counters, and all non-time native query metrics equal the
fixed parent68 references. Only random KB UUIDs are normalized in strings.
All runs finish without aborts or watchdog retries. The seed-7/23 screens
overlapped functional verification, so their times are not performance evidence.

## Paired timing and limits

The seed-11 timing order was declared as AB, BA, AB before execution. Our other
CPU-heavy tasks were paused for all six runs. Runtime, game, benchmark,
reference and source hashes remained unchanged. Unrelated host activity was
not controlled; per-run machine load and raw measurements are retained.

| Metric | Baseline median | Candidate median | Median paired change |
|---|---:|---:|---:|
| Diagnosis, both shifts | 5.820 s | 5.581 s | -3.96% |
| Second-shift diagnosis | 4.016 s | 3.781 s | -5.15% |
| Diagnosis CPU | 5.826 s | 5.595 s | -3.96% |
| Full episode | 20.085 s | 19.954 s | -0.65% |
| Peak process RSS | 169,068 KiB | 181,248 KiB | +7.02% |

All three pairs improve total diagnosis time. Paired percentages are computed
within each pair before taking their median; they differ slightly from ratios
of the displayed independent medians. RSS includes runtime allocation and GC
effects, not just index storage. The result establishes a modest tradeoff on
this workload, not a universal 4% improvement.

The previous baseline's quality gaps remain: seed 7 retains full raw belief
coverage; seeds 11 and 23 retain 50% raw belief coverage on both shifts.
Decision coverage stays 100% on these workloads. Older original/no-prior
reference differences are unchanged. This commit does not claim to restore
those historical targets, and no held-out workload was consumed.

## Reproduction and evidence

Frozen PeTTa is `e1aac8b791cf70b7843173b613f04b869b666979`; ChainerGame is
`99fc56e4ddd0d718f00e494146b0ff1884e5fc5e`. Nothing was fetched or rebuilt.
Set `PETTA_PATH` to that supported runtime, `PETTA_STRICT=1`,
`PETTA_STRICT_DET=1`, and `PETTA_JOBS=4`, then run `scripts/verify.sh` from the
worktree. The retained environment also identifies the existing ConceptNet
export through `CNET_DIR` with `CNET_REFRESH=0`.

The measured runs use the archived `exact-demand-combined/benchmark.py`,
included in the evidence bundle below. It adds post-scoring quality-target
capture to the repository driver, without exposing targets during inference.
It accepts `--repository`, `--chainergame`, `--petta`, `--json-out`,
`--seed 11`, and `--budget 300`. Run that archived driver with the pinned
`.venv/bin/python`; the exact six commands, environment, per-run measurements,
gates and source hashes are in
[`waiter-demand-index-results-2026-09-09.json`](../../benchmarks/stationops/waiter-demand-index-results-2026-09-09.json).

Complete raw sources, drivers, proof outputs and logs are retained in the
original checkout under `scratch/priority-causal-audit-2026-09-09/` as
`waiter-demand-index-validated-evidence.tar.gz`, with a per-file/hash manifest.
Directly readable summaries are in `scratch/waiter-demand-index-2026-09-09/`.
