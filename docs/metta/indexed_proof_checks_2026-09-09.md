# Indexed proof checks: combined validation, September 9, 2026

The combined change passes every repository verification gate and preserves the
immediate `d927e5f4` baseline's complete StationOps results, proof answers, and
non-time query metrics for all three workloads. Diagnosis inference operations
fall by 6.9–8.4% across the two shifts. These functional runs overlapped other
work; their elapsed times are not controlled performance evidence.

The change makes complete goal patterns immutable arena identities, updates all
constraint views on proof publication, requires compatible proofs for agenda
cancellation, and recognizes installed implication scaffolds without binding
open proof patterns. It then uses a `(proof ID, goal ID)` eligibility cache and
memoizes recursive proof-DAG dependency checks. Existing depth policy, priority
calculation, truth-value formulas, and expected proof fixtures are preserved.

## Source and verification

Validation started on branch `experiment/indexed-proof-checks`, base
`d927e5f4bba15c90e878cf6761908f13113d7746`, with the candidate applied. The six
runtime files were subsequently committed unchanged as
`d5ce3b333961e548b69ed92801c0c5860dec22bd`. All **195** inventoried source/test/script
files match before, after, and the post-commit audit. Source manifest SHA256:
`0523e20435c1128be2a9491a90d8d9711c6da23a5cf7713f313890c11a7043b3`.
Pre-commit metadata is retained separately from the final commit audit.

The pinned `.venv/bin/petta` used frozen PeTTa
`e1aac8b791cf70b7843173b613f04b869b666979` and ChainerGame
`99fc56e4ddd0d718f00e494146b0ff1884e5fc5e`; nothing was fetched or rebuilt.
`PETTA_PATH=<frozen-runtime> PETTA_STRICT=1 PETTA_STRICT_DET=1 PETTA_JOBS=8 scripts/verify.sh`
passed completely:

| Gate | Result |
|---|---|
| MeTTa suite through `scripts/test_metta.sh` | 77 passed, 0 failed |
| Python suite | 57 passed, 0 failed |
| Python query metrics | 46 rows, 0 search aborts |
| Import scaling | Ratio 1.003, limit 1.500, PASS |
| ConceptNet query | Exactly 2 answers, PASS |
| Strict defect scans and `git diff --check` | PASS |

## Exact StationOps comparison

All runs use two shifts, four modules, and action budget 1. All three per-goal
quality gates pass without unresolved entries. Entire episode results, complete
proof strings, and every non-time query metric match the retained d927 baseline
exactly, with zero aborts. Random KB UUIDs are normalized; timing fields are
excluded and inference operations are compared separately below.

| Seed / diagnosis budget | Shift 1 inferences, parent → combined | Shift 2 inferences, parent → combined | Total reduction |
|---|---:|---:|---:|
| 7 / 600 | 51,701,883 → 44,890,760 | 345,684,800 → 325,231,470 | 6.86% |
| 11 / 300 | 8,906,684 → 8,169,070 | 20,781,793 → 19,016,912 | 8.43% |
| 23 / 300 | 8,580,802 → 7,926,935 | 11,598,086 → 10,804,578 | 7.17% |

The parent's known losses against older original/no-prior references remain
inherited. Seed 7 M01 stays at 0.124143/0.220508 across the shifts, versus the
older original's 0/0.722300. Seeds 11/23 still lack shift 2-M04 relative to the
no-prior reference. This change does **not** restore those historical quality
targets or validate a new scheduling policy.

## Memory tradeoff and artifacts

The separate [DAG-only screen](proof_dependency_cache_2026-09-09.md) observed
4.9–6.6% less diagnosis time in one quiet alternating pair per seed. Shift-two
memo rows increased roughly 1.8–2.2 times. Seed 7 grew from 17,694 to 31,742 rows
and from 516.5 to 586.9 MiB peak RSS (+70.4 MiB). RSS includes SWI stack/GC effects,
not just cache storage; the other seeds' RSS changes were mixed. Memos clear at
query reset. Those isolated observations are not combined-candidate timing or
memory measurements.

Evidence is retained in `scratch/indexed-proof-checks-2026-09-09/`:
`VALIDATION.md`, `verify.log`, `exact-comparison.json`, `combined-*.json` and logs,
`quality-vs-d927-*.json`, frozen drivers, before/after source manifests,
`metadata.json`, and `final-hashes.json`. Historical attribution and isolated
cache evidence are copied into the corresponding subdirectories.
