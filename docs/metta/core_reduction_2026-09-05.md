# Core MeTTa reduction, 2026-09-05

Baseline: `06df18bc`. Scope: the same 29 owned implementation files under
`pettachainer/metta`, excluding vendored `repos/**` and scratch `x.metta`.
Tests, documentation, and third-party implementation are excluded from these counts.

| Metric | Before | After | Reduction |
|---|---:|---:|---:|
| Physical lines, including comments and blanks | 7,477 | 7,314 | 163 (2.2%) |
| Functions | 624 | 608 | 16 (2.6%) |
| Halstead tokens | 26,789 | 26,348 | 441 (1.6%) |
| Cyclomatic sum | 1,657 | 1,629 | 28 (1.7%) |
| Cognitive sum | 1,737 | 1,707 | 30 (1.7%) |

Counts use the installed `mettametrics` defaults; complexity sums are
intraprocedural, not transitive call-graph scores. Reproduce the metrics with:

```sh
mettametrics pettachainer/metta --exclude 'repos/**' --exclude x.metta --json
```

The reduction removes duplicate demand-cache packaging and proof-refresh paths,
two redundant forward payload types, specialized cache writers, hand-written
query/trigger walkers, and single-use scheduling adapters. Sixteen functions
were removed and none added. No implementation moved into another language or
vendored library; public API signatures are unchanged.

Required type/effect boundaries remain. Rejected trials were reverted, including
a pseudo-filter that copied an open captured subject and changed inheritance
identity. A regression now checks that contextual premises stay out of a lift's
auxiliary triggers. Additional checks cover empty/stale demand caches and
zero-budget/empty-agenda forward runs.

## Validation

`PETTA_STRICT=1 PETTA_JOBS=8 scripts/verify.sh` passed: 69 MeTTa files,
48 Python tests, 43 measured queries with zero aborts, import-scaling ratio
1.007 (limit 1.500), and exactly two ConceptNet results. Wall time: 167 seconds.

## Performance

Three baseline/candidate pairs passed all 42 workload runs using the unchanged
`pettachainer/benchmarks/core_suite.py`, in order AB, BA, AB, with one suite
repetition per invocation and no concurrent test workloads. Defaults were
unchanged, including 1,000 population members and population query budget 2.
Primary medians in seconds (negative delta means faster):

| Workload / metric | Baseline | Candidate | Delta |
|---|---:|---:|---:|
| Backward agenda runtime | 2.804 | 2.751 | -1.89% |
| Forward agenda runtime | 0.625 | 0.617 | -1.16% |
| Durable multi-root query total | 0.415 | 0.407 | -1.95% |
| Lifting merge, cold query | 0.383 | 0.376 | -1.66% |
| Lifting merge, warm query | 3.879 | 3.738 | -3.65% |
| Incremental inheritance, delta total | 0.503 | 0.486 | -3.46% |
| Forward population, total | 28.299 | 28.431 | +0.47% |
| Repeated refinement, query total | 3.679 | 3.610 | -1.89% |

No material regression was observed in this workload set; three local samples
are not evidence of a universal speedup. All setup medians changed by at most
1.02%. Individual durable-query shifts ranged from -2.83% to +1.03%.
Raw logs and JSON: `/tmp/pettachainer-core-reduction.BoCs9T/`.
