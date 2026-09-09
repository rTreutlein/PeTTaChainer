# Late shorter paths: scheduler experiment

Updating stored depths and pending descendants **does reach the previously
missed upstream alarm**, but does not recover the good local diagnosis. The
prototype is slower and fails three existing result assertions across the
MeTTa and Python suites. It remains an isolated experiment, not a runtime change.

The new evidence identifies a second obstacle: the independent upstream proof
is merged with a proof derived from the local diagnosis itself. That merged
representative is cyclic for the local consumer, even though the independent
component is still available and valid for that consumer.

## Policy and correctness controls

The archive starts from `ca15dd98` on `experiment/no-base-rate-success-prior`.
This is the ordinary no-success-prior scheduler, without the reuse/refinement
prototype. No priority coefficient, truth-value formula, or proof acceptance
rule was changed.

When a shorter path reaches an existing goal, the experiment lowers its stored
depth even if it has expanded, then relaxes its existing child links. Expanded
goals keep their rules and proof state. Strictly decreasing nonnegative depths
make this relaxation terminate on cycles. Demand still follows strictly
shallower parents, so the ordering of allowed demand edges remains acyclic.

Changing depth can add or remove demand-parent relationships. The affected
reachable closure therefore has its demand cache invalidated and its revisions
advanced, including descendants whose depth does not change. Each shortening
uses a distinct invalidation pass so a cache rebuilt between two shortenings
cannot escape the second invalidation. Before the next heap pop, affected
pending work is reissued with a fresh generation at its new priority. Pending
fold refreshes are included because their priority uses their source's depth.
Expanded rules are not re-enumerated by this update.

Three focused strict tests pass:

- A late path through expanded shared goals lowers pending descendants and
  stales old heap tokens; a recursive/equal-depth graph does not amplify demand.
- A branch with unchanged depth gains demand when its parent becomes shallower;
  a pending fold's key follows a shortened source even if the fold does not move.
- Two shortenings before heap refresh invalidate caches rebuilt between them,
  including removal of a formerly allowed demand parent.

## StationOps results

Six final episodes compare control and candidate on seeds 7, 11, and 23, two
shifts/four modules/action budget 1. Diagnosis budget is 600 for seed 7 and 300
for the other seeds. Each final setting/seed has one run: these are screening
measurements, not repeated performance acceptance results.

| Seed | Total diagnosis seconds, control → candidate | Shift 2 coverage, control → candidate | Shift 2 Brier, control → candidate |
|---:|---:|---:|---:|
| 7 | 48.65 → 68.17 | 100% → 100% | 0.163581 → 0.163751 |
| 11 | 5.17 → 8.49 | 75% → 75% | 0.005095 → 0.005095 |
| 23 | 4.32 → 12.08 | 75% → 50% | 0.003922 → 0.005881 |

Brier covers answered roots only, so seed 23's averages are not directly
comparable; the loss of coverage is itself a regression. Shift-one coverage
stays 100%, 50%, and 50% respectively. Scores and episode regrets remain
unchanged within each seed: 637/0 for seed 7, 642/17.292347 for seed 11, and
642/0 for seed 23. No diagnosis batch aborts. Control proof answers reproduce
the earlier no-success-prior runs after KB-UUID normalization.

The initial control/draft runs alternated order. Review found a repeated-
shortening invalidation issue, which was corrected and covered by the new
focused test before rerunning all three candidates. The table includes only
those final candidates. Validation and timed benchmarks ran separately. No
coefficient was tuned against any seed.

## Why the useful diagnosis is still missing

In the final seed-7 candidate, the MAIN-context upstream alarm goal is depth 3
and **expanded**, instead of depth 4 and unexpanded in control. The negative
alarm produces the independent upstream-problem proof and then its dependency
proof. The root still returns the historical-inheritance strength
**0.22050793373327351**, confidence 0.000001.

The captured store and direct runtime cycle checks show:

| Proof ID | Dependency strength | Origin | Depends on the local diagnosis? |
|---:|---:|---|---|
| 1254 | 0.6628278881 | Reverse OR projection using local proof 1176 | Yes |
| 1257 | 0.0562500000 | Independent upstream alarm | No |
| 1258 | 0.0562613462 | Merge of 1254 and 1257 | Yes |
| 1285 | 0.0535714286 | Refined independent upstream alarm | No |
| 1286 | 0.0535819207 | Merge of 1254 and 1285 | Yes |

These booleans are evaluations of `proof-depends-on-goal-seen?` against the local
root, not guesses based on proof names. At the end of the query,
`noncyclic-proof-source-ids` for that consumer still returns **(1285)**.
Thus finding and retaining the independent evidence is no longer the problem.

`commit-proof-candidate-heap` passes `goal-merged-proof-id-for-pid` to
`wake-proof-commit-heap`. A waiting frontier checks that delivered proof through
`frontier-proof-admissible?`, which rejects a proof whose ancestry contains its
parent goal. In this case the merged dependency has precisely that ancestry.
The guard should remain: accepting the mixed representative would allow
self-support. The problem is that the independent subset is usable while the
published merged representative is not.

There is already a consumer-specific noncyclic selection path in
`frontier-conditioned-proof-ids` for existing proof replay. The next focused
target is whether live proof delivery should likewise select a representative
from the proofs compatible with each waiting consumer. This should be tested
first on a small cyclic-dependency/independent-evidence fixture, with incremental
publication and cached replay producing the same usable evidence. It is a
separate proof-delivery change; no such change was made in this experiment.

The snapshot and source establish this blocked representative, but do not claim
that all remaining search-order effects or proof-path invalidations have been
eliminated. Shorter stored depth alone is not sufficient to make the result
independent of the earlier search history.

## Broader validation

The repository-pinned `.venv/bin/petta`, through
`PETTA_STRICT=1 PETTA_JOBS=8 scripts/test_metta.sh` in the archive, reports
**71 passed, 2 failed**, including the new focused test file. Existing fixtures
were not changed to accept the policy:

- `test_or_inversion_conditioned_merge` returns an alarm-containing merged
  proof at strength 0.5200045679 instead of the expected direct OR proof at
  0.52. A separate diagnostic run that evaluates all three original queries
  shows the subsequent Problem answer also differs, while the final local
  prior remains exactly 0.4/confidence 0.9. This is a cycle-sensitive regression
  requiring investigation; passing the focused demand-cycle test does not
  establish equivalent conditioned proof behavior.
- `test_inheritance_query_proof` retains strength 0.9993340727 but returns
  confidence 0.000001 instead of approximately 0.000002 at budget 80.

Python reports **49 tests run, 1 failure**. The materialization regression
returns strength 0.4684319204 instead of 0.4719187802 after the evidence update,
with the same approximately 0.000004 confidence. This is a different finite-
budget proof; the test is not evidence that the new value is intrinsically
invalid, but the existing refinement contract is not established by this run.

The first Python invocation additionally hit two metadata-only errors because
the archive has no `.git`. The final complete rerun reads the base repository's
Git metadata using `GIT_DIR` and sets `GIT_WORK_TREE` to the archive; only the
materialization failure remains. No dependency fetch or rebuild occurred.

## Provenance and recommendation

Do not adopt this depth-update prototype as the default: it adds bookkeeping,
does not improve the main diagnosis, and does not pass the existing acceptance
fixtures. The experiment nevertheless separates two obstacles: the depth update
fixes access to the upstream alarm, then the merged proof supplied to the local
consumer prevents use of that independent evidence.

ChainerGame is `99fc56e4ddd0d718f00e494146b0ff1884e5fc5e`; the pinned PeTTa tree
is `502d08ba468480093d22e710db17f21ab4c3ac59`. The production working tree and
master are unchanged. Pre-existing untracked `.claude/`,
`baseline_agenda_incumbent.json`, and `tmp.txt` were excluded.

The [compact evidence](../../benchmarks/stationops/shorter-path-results-2026-09-09.json)
contains the final patch, focused tests, drivers, environments, diagnosis
answers/counters, selected proof stores, cycle-check results, and validation
logs. Full raw stores and logs remain locally in
`scratch/stationops-shorter-path-2026-09-09/`. The prototype archive is
`/tmp/stationops-depth`; its complete patch applies to the source revision
above. The query snapshots are collected after the timed diagnosis; they are
not part of the reported diagnosis time.
