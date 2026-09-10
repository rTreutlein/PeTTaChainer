# Verified search optimizations, 2026-09-10

Branch: `perf/verified-search-optimizations`. Tested implementation: `a4ea17453c22256d24c9e1307a6e3457da1e02d2`, based on `4a9593dd5eea83f3ba0277f8fe4d216b9033a5e9`. The baseline already includes the other agent's earlier cleanup; these measurements quantify only the subsequent retained stack. The follow-up commit adds this report, evidence summary, and an already-verified public regression test.

## Included work

- Compact waiter projection (`322179b2`, docs/tests `94a52ce9`).
- Fixed-reference StationOps quality tooling (`44857e94`, evidence/tests `3ada65a7`).
- Query-local goal eligibility cache (`a492877e`, docs/tests `d927e5f4`).
- Immutable constrained goal identities, publication to constraint variants, compatible cancellation, and recursive proof-DAG dependency memoization (`d5ce3b33`, docs/tests `68f76534`).
- Waiter-demand input index (`bb1664ef`, docs/tests `30b81192`).
- Immutable derivation descriptor cache (`e33d679c`, docs/tests `a4ea1745`).

Unfinished scheduler-policy experiments are excluded. There are no new tuning parameters or priority-formula changes in this stack.

## Matched full-stack measurements

One sequential baseline/candidate pair per development seed; two shifts, four modules, action budget 1. Time is seconds, RSS is peak whole-process MiB, inferences are diagnosis operations in millions. These are screening measurements, not repeated-run estimates of statistical significance.

| Seed / diagnosis budget | Diagnosis baseline → branch | Reduction | Whole episode baseline → branch | Peak RSS baseline → branch | Inferences baseline → branch |
|---|---:|---:|---:|---:|---:|
| 7 / 600 | 123.78 → 64.92 | 47.6% | 140.98 → 83.04 | 912.1 → 591.5 | 505.45 → 357.77 |
| 11 / 300 | 8.04 → 5.68 | 29.4% | 22.69 → 20.46 | 230.6 → 176.6 | 33.32 → 26.51 |
| 23 / 300 | 5.32 → 4.30 | 19.1% | 19.87 → 18.95 | 227.5 → 180.5 | 21.85 → 18.53 |

For seed 7, shift-one diagnosis fell from 14.07 to 8.76 seconds; shift two fell from 109.71 to 56.16 seconds. Whole-episode reductions were 41.1%, 9.8%, and 4.7%; peak RSS reductions were 35.1%, 23.4%, and 20.6%.

All three pairs matched complete proof answers (normalizing only knowledge-base UUIDs), queries, public results including backend counters, and all non-time query metrics. There were zero aborts. Raw coverage remained 100% in both shifts for seed 7, and 50% in both shifts for seeds 11 and 23; decision coverage remained 100%. This preserves the starting snapshot's results; it does not establish recovery of every older scheduler's coverage or accuracy. Held-out seeds 37 and 47 were not used.

Both sides used frozen PeTTa `e1aac8b791cf70b7843173b613f04b869b666979` and ChainerGame `99fc56e4ddd0d718f00e494146b0ff1884e5fc5e`, through the repository-pinned virtual environment. Nothing was fetched or rebuilt. Before/after source hashes matched for both chainer snapshots and both dependencies. Run order was baseline/candidate for seeds 7 and 23, reversed for seed 11. Machine: Ryzen 7 5700X3D, 16 logical CPUs, WSL2. Other agent jobs were stopped; unrelated host activity was uncontrolled.

## Complexity cost

Scope: all ten files in `pettachainer/metta/runtime/backward`, from baseline to tested implementation. All production changes in this stack are in that directory.

| Measure | Baseline | Branch | Change |
|---|---:|---:|---:|
| Physical source lines | 3,002 | 3,087 | +85 (+2.8%) |
| Nonblank, noncomment lines | 2,600 | 2,663 | +63 (+2.4%) |
| Named function units | 321 | 322 | +1 |
| Cyclomatic complexity sum | 878 | 891 | +13 (+1.5%) |
| Cognitive complexity sum | 929 | 965 | +36 (+3.9%) |
| Halstead token count | 13,391 | 13,512 | +121 (+0.9%) |

These static metrics are proxies, not a complete measure of maintenance difficulty. They measure direct control flow, not transitive callee complexity. Quoted expressions count as data. Complexity sums include top-level units; the named-function count excludes them. Token counts are additive; nonlinear Halstead volumes and efforts are not summed.

The main architectural cost is three new query-local stores: `&proof_goal_eligibility`, `&goal_waiter_demand`, and `&proof_derivation_descriptor`, with their lifecycle/indexing invariants. The existing `&proof_cycle_cache` also memoizes recursive DAG nodes. The largest local cognitive increase is `claim-goal-agenda-entry!`, 64 → 75; maximum function cyclomatic complexity rises 13 → 14.

Runtime churn is 205 lines added and 120 removed. Before this packaging commit, tests added 814/removed 12 lines, docs 678/4, benchmark tooling 105/6, and raw benchmark evidence added 23,738 lines. The large total diff is primarily evidence, not production code.

The local `mettametrics` tool is from a dirty sibling checkout (HEAD `6507f711246dedb3ce514dcd385977b0429fcb30`, metrics implementation untracked). Actual package source and hashes are archived with the measurements so the metric provenance does not depend on that commit alone.

## Validation and evidence

All 286 files in the previously validated candidate manifest match this branch byte for byte. That snapshot passed `scripts/verify.sh`: 79 MeTTa files, 57 Python tests, zero failures/aborts, import-scaling and ConceptNet checks. This campaign did not repeat that entire suite. The separately verified late-evidence regression is now included as `tests/test_priority_refinement.py` and passed again on this branch (one test, 17.235 seconds). It checks both root directions, two insertion orders, fixed truth values, and all four direct witnesses after adding late evidence.

Machine-readable summary: `benchmarks/stationops/verified-optimizations-results-2026-09-10.json`. Full raw runs, commands, source manifests, previous validation logs, metric outputs, and actual metric-tool source are preserved at `scratch/verified-optimizations-2026-09-10` in the main checkout. The raw archive is local and ignored by Git; the compact summary is committed.

Recommendation: retain this verified stack. It substantially reduces work and memory while preserving this baseline's exact results, for a modest aggregate code increase. Treat scheduler quality work as still unresolved; these runs do not justify adopting the unfinished policy experiments.
