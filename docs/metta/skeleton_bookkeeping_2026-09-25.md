# Skeleton evaluation bookkeeping — 2026-09-25

This pass replaces per-row deletion of temporary evaluation records with native
bulk removal. It preserves per-cause forcing, stale propagation, proof order,
durable views and public API signatures.

## Change

`remove-data-rows!` removes a matching pattern from a data-only space in one
native call. Its patterns are quoted at the MeTTa boundary. It deliberately
bypasses `remove-atom`'s function-definition and compiler-metadata handling;
these stores contain only data. No new state, cache or runtime dependency was
introduced.

Twelve deletion paths now use bulk removal: eight query/evaluation resets,
new-row and dirty-key consumption, pending fold members, and pending row
causes. Consumers collect their values in the original order before removing
them. Used row/cause pairs still survive consumption until the next evaluation.
The single-use `sk-take-forced!` helper was removed and its consumer now performs
the collect/remove operation directly.

## Code size and complexity

Counts cover the 23 production `.metta`/`.pl` files under `pettachainer/metta`,
including comments and whitespace; tests and documentation are excluded.

| Metric | Baseline | Candidate | Change |
|---|---:|---:|---:|
| Production lines | 7,188 | 7,188 | unchanged |
| Production bytes | 329,986 | 329,860 | −126 (−0.038%) |
| Evaluation module lines | 1,540 | 1,532 | −8 |
| Evaluation module bytes | 79,136 | 78,655 | −481 |
| Distinct MeTTa equation names | 511 | 510 | −1 |

One native helper replaces the removed MeTTa helper; total helper names are unchanged.

The source-size improvement is small. The complexity improvement is replacing
per-record deletion calls and discarded result lists with a single native
operation per pattern. Collecting needed values and creating per-cause records
still scale with the number of records; durable proof history is unchanged.

## Method

Baseline: local `skeleton-core` commit
`2a1bcf8f3735c41ef624462f81bcdf4ce9c56f55`, including the latest answer-subsumption
ordering fix. Candidate: that commit plus this uncommitted production patch.
Baseline source was archived separately; both used the same installed,
repository-pinned `.venv` runtime. No fetch or rebuild occurred.

Each workload has three fresh-process baseline/candidate pairs, with order
alternating B/C, C/B, B/C. Runs were sequential and did not overlap validation.
Values below are medians of the three runs. The machine was not isolated from
other system activity, so small timing differences should not be overinterpreted.
The accompanying JSON records source/diff hashes, runtime source hashes, CPU,
paths, dirty state, game commit, all run summaries and raw artifact hashes.

Session workloads use one KB, 40 growth rounds and three unchanged queries
after each growth query, with a query budget of 300. The unrelated workload
keeps two stable roots while adding six unrelated roots per round. The history
workload grows a Member aggregate and its downstream conclusion from 16 to 55
members. Timed regions include the public query API; state snapshots are outside
both timing and inference counts.

## Session measurements

| Workload and query phase | Baseline seconds | Candidate seconds | Change |
|---|---:|---:|---:|
| Unrelated growth: 40 growth queries | 74.1706 | 61.0561 | -17.7% |
| Unrelated growth: 40 first unchanged queries | 10.1420 | 5.8979 | -41.8% |
| Unrelated growth: 80 subsequent unchanged queries | 0.3483 | 0.3913 | +12.4% |
| Member history: 40 growth queries | 1.2802 | 1.2808 | +0.0% |
| Member history: 40 first unchanged queries | 0.7358 | 0.7161 | -2.7% |
| Member history: 80 subsequent unchanged queries | 1.4380 | 1.4301 | -0.5% |

All ordered proof hashes match across all six runs of each session workload. All five recorded skeleton-state counts match at every snapshot.

Unrelated growth: median peak RSS was 896.4 → 881.4 MiB. This is process peak RSS, not a measurement of live retained objects. The last first-unchanged query used 2,148,817 → 689,339 Prolog inferences (-67.9%).

Member history: median peak RSS was 132.6 → 132.6 MiB. This is process peak RSS, not a measurement of live retained objects. The last first-unchanged query used 150,274 → 146,984 Prolog inferences (-2.2%).

## StationOps

Three pairs used the frozen game source at `db031348f395926e2ff9da6e6d7a89ceef0025d2`, four modules, seed 7, diagnosis budget 600 and action budget 1.

| Batch | Baseline seconds | Candidate seconds | Change |
|---|---:|---:|---:|
| Shift 1 | 12.759 | 13.011 | +2.0% |
| Shift 2 | 25.102 | 24.319 | -3.1% |

Complete proof answers and episode results match across all six runs. Every shift has 100% belief coverage; every episode scores 637 with zero regret. Both per-shift median time and inference counts pass the 5% regression gate.

## Validation and limits

- `scripts/verify.sh`: all four gates pass; 72 MeTTa files, 58 Python tests, 50 instrumented Python query rows with zero aborts, import scaling and ConceptNet pass.
- `scripts/strict_check_metta.sh`: passes.
- `git diff --check`: passes.
- The new evaluation-lifecycle regression checks ordered causes, duplicate suppression after consumption, isolation between rows and keys, empty resets, reuse in the next evaluation and durable zero-budget answers. Existing aggregate/existential tests also cover stale readers after changes.

Already-stable queries in the unrelated workload increased from 4.35 to 4.89 ms per call on average (each run's total divided by 80, then the median across runs). For the last ten rounds, the median of per-run median latencies was 3.41 → 5.10 ms. This regression is reported separately from the growth and root-switch savings. This change does not make warm queries constant time or bound durable proof history. Creating per-cause records and propagating stale marks remain performance work.

The [machine-readable results](skeleton_bookkeeping_2026-09-25.json) contain per-run measurements and provenance. Raw logs and JSON files are in `/tmp/skeleton-bookkeeping/`. Reproduce the workloads using the commands recorded in the JSON, substituting the desired checkout and output path.
