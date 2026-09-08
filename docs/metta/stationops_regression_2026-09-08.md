# StationOps second-shift regression investigation

The first slow revision in the narrowed interval is `5e6d1ece` (September 4,
"Nothing is retired: base-rate retirement, universe size and the reuse gate
go"). The expensive second-shift search is already present there, before the
September 5 simplifications and demand-publication freshness fix.

Three interleaved August/September pairs (AB, BA, AB) confirm the historical
regression with the same game, interpreter, and PeTTa runtime:

| Median diagnosis metric | August `2e61e42` | September `0b938c26` | Change |
| --- | ---: | ---: | ---: |
| Shift 1 seconds | 18.85 | 18.78 | -0.39% |
| Shift 2 seconds | 49.67 | 91.11 | +83.44% |
| Shift 1 inferences | 83,631,925 | 92,797,795 | +10.96% |
| Shift 2 inferences | 131,543,895 | 489,061,743 | +271.79% |

All six episodes have full coverage, zero regret, score 637, and zero search
aborts. Each revision reproduces exactly the same inference counts, episode
results excluding timings/counters, and proof answers with runtime KB UUIDs
normalized across its three repetitions. The revisions differ from each
other in proofs and beliefs. The new regression gate correctly returns failure
for the historical comparison and passes within-revision repeatability checks.

## Controlled workload and screening

The investigation runs ChainerGame's actual `run_game_episode` with seed 7,
two shifts, four modules, diagnosis budget 600 and action budget 1. ChainerGame
is unchanged at `99fc56e`. PeTTaChainer revisions are isolated source archives;
all use the primary checkout's pinned Python 3.10.16, Janus 1.5.2, and identical
vendored PeTTa sources. No fetching or rebuilding occurred. The primary
checkout remains on `master` at `ccf0862d`; its three pre-existing untracked
items were preserved. Only benchmark tooling and this report are added.

These are diagnosis-call measurements, not whole-shift timings. Counters are
enabled identically on both sides; there is no sampling profiler in these runs.
Each row below is one screening run, not a repeated timing estimate.

| Revision | Change | Shift 1 seconds | Shift 2 seconds | Shift 2 inferences | Shift 2 coverage |
| --- | --- | ---: | ---: | ---: | ---: |
| `2e61e42` | August endpoint | 18.93 | 49.16 | 131,543,895 | 100% |
| `4152fd71` | Before always-search | 14.39 | 25.58 | 113,562,131 | 100% |
| `afbfafc9` | Always-search and derivation supersession | 19.27 | 24.09 | 163,883,579 | 75% |
| `5e6d1ece` | Remove retirement | 19.26 | 95.75 | 518,077,958 | 100% |
| `6ae53c00` | Remove dependent-demand walk | 19.59 | 93.96 | 510,077,784 | 100% |
| `26a04bc0` | Remove materialized lineage | 19.06 | 93.53 | 510,076,172 | 100% |
| `207490e8` | September 5 simplifications merged | 18.58 | 91.33 | 490,214,548 | 100% |
| `0b938c26` | Publication freshness fix / September endpoint | 18.29 | 90.95 | 489,061,743 | 100% |

Every screening revision scores 637 with zero regret. Nevertheless,
`afbfafc9` misses the fourth diagnosis root in shift two and changes the first
root's belief from approximately 0.7223 to 0.2204. Its fast timing is not an
equivalent full-coverage baseline. The previous revision `4152fd71` is both
fast and full-coverage. August and September also differ in their complete
beliefs despite matching scores and coverage; for example the third
second-shift belief changes from 0.2175815335 to 0.2168543424.

## What changed

Before `5e6d1ece`, knowledge ingestion and forward cache updates could record
pending base-rate retirement keys. At fold spawn, `pending-base-rate-retires?`
enabled `consume-pending-base-rate-retire-key!`, which superseded the matching
current fold snapshots. For a pending ordinary base-rate fold, the spawn path
then selected `ba-spawn-live` instead of seeding the fold from the cached TV.
Member folds still consumed the pending retirement before the cached-refinement
path.

`5e6d1ece` deleted that pending-retirement protocol and the conditional spawn
path. Available non-user cached estimates now go through `ba-refine`, which
commits a cached snapshot and wakes its source. This operates on the retained
proof graph under the always-search policy introduced by the preceding commit.

The resulting second-shift search is much larger per expansion:

| Second-shift work | `afbfafc9` | `5e6d1ece` | `0b938c26` |
| --- | ---: | ---: | ---: |
| Agenda pops | 754 | 842 | 842 |
| Demand evaluations | 44,458 | 139,235 | 139,235 |
| Demand-cache misses | 7,817 | 19,967 | 19,967 |
| Proof candidates stored | 737 | 1,349 | 1,349 |
| Durable proof rows before query | 1,195 | 1,195 | 1,195 |
| Durable proof rows after query | 2,102 | 3,211 | 3,211 |

The September 5 commits reduce overhead within this search; they did not
introduce it. The expensive `satisfies-goal?` reconstruction path already
existed in August. Its presence alone cannot identify the regression.

### Isolating the mechanism within the commit

An isolated `afbfafc9` snapshot was changed in exactly one definition:

```metta
(= (pending-base-rate-retires?) false)
```

This disables pending-retirement consumption and its live-spawn decision,
without applying the universe-size removal, materialization reuse change, or
any later commit. The second diagnosis takes **95.31 seconds**, with
**518,502,325 inferences**, versus 95.75 seconds and 518,077,958 for the full
`5e6d1ece` change. Both shifts match that commit on **every non-timing query
metric**, complete episode results excluding timing/backend counters, and
complete proof answers after normalizing runtime KB UUIDs. Both have full
coverage and score 637.

This is a causal ablation, not just a correlation with a large commit. The
pending-retirement/spawn decision is sufficient to reproduce the expanded
search. The ablation retains the parent's other implementation, so its exact
Prolog inference total need not match the full deletion commit. The
experimental edit is confined to an isolated snapshot; it is not
a proposed runtime fix.

## Why validation missed it

1. The application workload was available in ChainerGame but absent from the
   PeTTaChainer performance gates. The durable fixture uses shallow stable
   implications and shift-specific shared facts, and took about 0.4 seconds
   across all five shifts. It does not reproduce this interacting diagnosis
   and inheritance workload.
   The retirement-removal commit described that machinery as having nothing
   left to do under always-search. The one-definition experiment disproves
   that assumption for this application: it still controlled fold startup
   and the amount of retained-proof work.
2. The September 5 performance reviews start at `26a04bc0` or later. The slow
   behavior was already in their baselines. Small local improvements therefore
   passed without checking cumulative performance against August.
3. `scripts/verify.sh` checks correctness, aborts, import scaling, and ConceptNet
   results, not application diagnosis latency. `scripts/performance.sh` prints
   core timing deltas without enforcing a regression threshold. The existing
   A/B threshold script covers only the Member and durable fixtures.
4. Score alone also hid an intermediate coverage regression: `afbfafc9` still
   scored 637 with one unanswered diagnosis. Full root coverage and beliefs
   must be retained alongside timing.

The final freshness fix's local validation record additionally says no full
repeated performance sweep was run. This is a process limitation, but the
measurements above exonerate that fix as the source of this slowdown.

## Permanent benchmark

[The StationOps runner](../../benchmarks/stationops/README.md) uses the existing
ChainerGame workload, archives both tested commits, pins the same game and
PeTTa sources, alternates execution order, and retains full results. Its gate
checks coverage, score, regret, aborts, episode equivalence, and each shift's
median diagnosis time and inference count. Passing `scripts/verify.sh` alone
does not establish this application's performance.

No runtime optimization or restoration of the deleted retirement design is
included in this investigation.

## Evidence and reproduction

- [Committed measurements and provenance](../../benchmarks/stationops/results-2026-09-08.json)
  include every screening counter, all six repeated runs, the causal patch,
  normalized result/proof digests, and the final comparison.
- Full local raw episodes, proof answers, logs, and the ablation patch are
  retained under `scratch/stationops-regression-2026-09-08/`; repeated-run
  outputs are in its `endpoint-ab/` directory. These scratch files are not
  committed. The original source archives also remain under
  `/tmp/stationops-regression/` and `/tmp/stationops-endpoint-ab/`.
- Reproduce the repeated comparison with:

  ```sh
  .venv/bin/python benchmarks/stationops/compare.py 2e61e42 0b938c26 \
    --pairs 3 --output-dir /tmp/stationops-historical-rerun
  ```

The benchmark's syntax and CLI were checked. The final comparison logic was
also checked against the independent equivalent ablation/full-commit runs
(accepted), the measured historical regression (rejected), and a failed
workload acceptance result (rejected). No runtime files changed, so the MeTTa
suite was not rerun for these benchmark/documentation additions.
