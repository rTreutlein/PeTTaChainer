# Consumer-specific proof selection and continuation validity

The implementation keeps the general merged estimate of a proposition while
allowing each consumer to select its best compatible stored proof set. A change
to the general estimate no longer invalidates an unchanged consumer selection.

## Implementation

- Same-derivation proofs removed from the global current set remain indexed as
  alternatives. Ordinary explicit removal and fold-snapshot replacement do not
  retain the removed proof this way. Existing candidate classification, cycle
  rejection, truth-value formulas, and the public API remain unchanged.
- A consumer filters current candidates and retained alternatives against its
  parent goal, rule-direction restrictions, already-used evidence, and accumulated
  premise parts. Compatible replacements supersede older versions only after
  filtering, and the resulting sources are merged normally. Aggregate sources
  use the same alternatives and compatibility-relative supersession.
- A query-local source-pool cache checks goal compatibility once per proof-set
  revision. A second cache stores the selected proof IDs per frontier context
  and revision. Lookup tables use scalar hashes or IDs in their first column;
  full nonbinding alpha comparisons distinguish contexts with the same hash.
- Continuations are keyed by consumer view, parent path, and selected proof ID.
  Replacing a consumer's selection retires only its paths for removed IDs.
  Another consumer may keep using the same independent proof. A previously dead
  path gets a fresh ID if that proof is selected again; descendants are not revived.
- Each selected proof is delivered once per consumer until that selection is
  retired. Publication of one open-goal binding delivers only that output.
  This prevents unchanged selections from repeatedly advancing the same frontier.
- Direct fold-snapshot replacement still invalidates paths consuming the old
  snapshot. Publication still invalidates scheduling freshness even when the
  bounded synchronous-delivery guard suppresses callbacks.

Hashing now uses an attribute-free copy of a term for its temporary variable
markers. This avoids running TV type constraints against the hash marker while
preserving the original variables and their constraints for actual matching.
An explicit strict regression checks that hashing a typed free variable leaves
it unbound.

The old special-case conditioned-replay helpers and raw-conjunction path
exemption are removed. Replay and publication share consumer selection.
No depth coefficient, exploration parameter, or probability formula was changed.

## Correctness checks

The focused regressions establish that:

1. G receives an independent A component even when A's published merge also
   contains a G-dependent component; an unrelated observer receives the full merge.
2. A publication for one binding of an open goal does not replay other bindings.
3. A partial G proof waiting for H stays usable when A's general estimate changes.
4. If a broader version supersedes the same A derivation globally, G keeps the
   independent older version while Observer switches to the broader version.
   The old A is absent from the global current set but retained as an alternative;
   G's old path is live and Observer's old path is dead.
5. A consumer that already used shared evidence selects A's independent component
   without changing the general merged estimate of A.
6. Typed variable hashing neither instantiates the original variable nor triggers
   its constraints with the hash marker.

Existing tests continue to check fold replacement, evidence deduplication,
cycle boundaries, deterministic dispatch, open queries, multi-root behavior,
materialization, and unconditional demand-freshness invalidation.

The path-lifetime reproducer now binds the source ID list before its membership
check: the internal Atom-argument helper otherwise receives an unevaluated
expression. Its final assertion confirms all three facts explicitly: the
independent source remains current, its path stays live, and G is derived.

The updated full-proof expectations reflect newly completed valid branches:
the complete conjunction projection now wins over its marginal when available;
the general OR and Problem estimates can include the current alarm branch,
while LocalProblem still returns its direct prior `(STV 0.4 0.9)`. In the Python
materialization regression, the 100-step refined/fresh values become
0.46913539784101055 and 0.47191878015453864, both at confidence
3.999988000035998e-06. Zero-budget reuse and repeated-query convergence remain
asserted; only the two explicitly fold-order-sensitive snapshots changed.

## Validation

The complete verification script passed before a final source-pool cleanup.
After removing redundant proof reconstruction from that pool, the complete
MeTTa and Python suites and ConceptNet gate were rerun:

- 75 MeTTa files passed, zero failed, in strict mode with strict determinism.
- 49 Python tests passed; all 46 recorded query rows have zero search aborts.
- ConceptNet reports exactly two results, with no abort marker.
- Import scaling passed at a late/early median ratio of 1.006 (limit 1.500).
  The final cleanup changes only query-time source selection, not ingestion.

A later whitespace-only formatting pass on `store-proof-candidate` was checked
for exact MeTTa token identity. The working-tree implementation matches the
validated archive.

## StationOps screening results

**Keep this on the experimental branch; do not merge it into master yet.**
The focused correctness failures are fixed, but this implementation spends more
work on additional usable paths and gives worse finite-budget coverage. It is
not a fix for the performance regression. All episode scores and regrets match
control, and all twelve main-matrix diagnosis batches have zero search aborts.

Fresh runs were sequential, candidate then control for seeds 7, 11, and 23.
Each has two shifts, four modules, action budget 1, and diagnosis budget 600
for seed 7 or 300 for seeds 11 and 23. These are single-run screening timings,
not repeated performance acceptance measurements. Diagnosis time below is the
sum of the timed `query_many` calls, excluding post-query store snapshots.
Coverage and Brier are from shift two; Brier only covers evaluated beliefs and
must be read alongside coverage.

| Seed | Setting | Diagnosis seconds | Shift 2 coverage | Shift 2 Brier |
|---:|---|---:|---:|---:|
| 7 | Control | 49.34 | 100% | 0.163581 |
| 7 | Consumer views | 125.28 | 100% | 0.163857 |
| 11 | Control | 5.16 | 75% | 0.005095 |
| 11 | Consumer views | 8.85 | 50% | 0.007537 |
| 23 | Control | 4.33 | 75% | 0.003922 |
| 23 | Consumer views | 6.08 | 50% | 0.005951 |

The fresh controls reproduce the earlier shorter-path control answer/proof
strings after normalizing KB UUIDs. Seed 7 scores 637 with zero regret;
seed 11 scores 642 with regret 17.292347; seed 23 scores 642 with zero regret.

The larger cost is concentrated in seed 7's second diagnosis:

| Work | Control | Consumer views |
|---|---:|---:|
| Diagnosis seconds | 31.57 | 110.33 |
| Prolog inferences | 123,031,434 | 429,773,156 |
| Agenda pops | 824 | 958 |
| Demand evaluations | 99,437 | 355,001 |
| Stored goal waiter rows | 16,604 | 26,231 |
| Durable proof rows after query | 2,591 | 4,497 |

These counters establish a larger graph and more repeated scheduling work;
they do not attribute all the additional wall time to one function. The first
shift is 14.95 seconds versus 17.78 seconds in control, so its timing alone
would give a misleading picture of the change.

Without the separate shorter-path change, the desired independent dependency
proof is absent in both seed-7 runs. Their final noncyclic dependency-source
lists are empty, and M01 still returns the identical historical-materialization
proof at strength 0.22050793373327351, confidence 1e-6. Consumer-specific
selection cannot recover a source that the search has not derived.

## Combined shorter-path diagnostic

A separate archive adds the previously recorded shorter-path patch. This is a
scheduler experiment, not part of the working implementation or its full-suite
validation. The combined seed-7 run recovers the desired derivation, keeps 100%
coverage, and lowers shift-two Brier to 0.031622. Diagnosis totals 87.59 seconds
(35.37 + 52.22), versus control's 49.34 seconds. Score remains 637, regret zero.

The stored proof graph identifies the recovered route precisely:

1. The M03 pressure alarm is inverted into a Problem estimate and carried through
   `dependency-problem-shift-02-M03-M01`. Independent dependency proof 1888 has
   strength 0.05357142187500086 and confidence 0.05488004641017932. The runtime
   reports it does not depend on local root 0.
2. The general dependency estimate still includes a root-dependent component:
   merged proof 2741 contains 1888 and 2740 and is cyclic for root 0. The local
   consumer's final noncyclic source set is `(1888)`, not that global merge.
3. Local proof 1891 applies `((proj 0 (proof-ref 1834)) (proof-ref 1888))`.
   It combines the M01 alarm-derived disjunction with independent M03 dependency
   evidence and yields `(STV 0.722285446860001 0.00018167673884279787)`.
4. Final local representative 2735 merges that proof with historical estimate
   2734 and returns `(STV 0.7195391376616058 0.00018267637552250824)`.

This is evidence that the consumer/path fix can complete the intended proof
once scheduling reaches its independent input. It does not establish that the
shorter-path policy is generally better or that the resulting low-confidence
estimate is well calibrated. The full returned proof is included in the evidence.

The follow-up combined runs do not generalize the seed-7 improvement:

| Seed | Combined diagnosis seconds | Shift 2 coverage | Shift 2 Brier |
|---:|---:|---:|---:|
| 7 | 87.59 | 100% | 0.031622 |
| 11 | 8.85 | 50% | 0.007482 |
| 23 | 8.32 | 50% | 0.005860 |

All six combined diagnosis batches have zero search aborts; their scores and
regrets still match control. These archives received the focused shorter-path
regression, but not a complete combined-candidate validation campaign.

## Recommendation

Keep the consumer correctness contract and its regressions as the target, but
do not select a new depth or exploration default from this experiment. The next
implementation work should reduce duplicate continuation/scheduling work while
preserving distinct compatible proof choices. In particular, evaluate sharing
selection results between equivalent compatibility contexts without sharing
path invalidation, and measure demand propagation over the additional live
paths. Neither optimization is established by the present counters.

The implementation remains on `experiment/no-base-rate-success-prior`; master
is unchanged. The broader regression/performance objective remains unresolved.
Candidate classification is still global before storage: the retained pool does
not include candidates rejected before they ever reached the proof store. The
change therefore fixes the demonstrated current/superseded-proof cases, not a
complete constraint-sensitive search across every possible proof.

## Reproduction and artifacts

Baseline is `c0cd54e3`; frozen baseline and candidate archives use the same
repository-pinned runtime. Local master is
`1bfbf539c06c8e77ab45327ae9a9e9888393a435`, PeTTa tree is
`502d08ba468480093d22e710db17f21ab4c3ac59`, and ChainerGame is
`99fc56e4ddd0d718f00e494146b0ff1884e5fc5e`. No fetch or rebuild occurred.
The starting tree had only the pre-existing untracked `.claude/`,
`baseline_agenda_incumbent.json`, and `tmp.txt`; these are untouched.

The machine-readable evidence, `consumer-views-results-2026-09-09.json` (removed from the tree to keep it small; retrieve it with `git show 77ed45a2:benchmarks/stationops/consumer-views-results-2026-09-09.json`),
contains both shifts of every run, metrics, answers, relevant seed-7 proof rows,
the source patch, benchmark runner, and validation logs. Apply
`consumer-views.patch` to an archive of `c0cd54e3` for the tested implementation;
add `shorter-path.patch` only for the separate combined diagnostic.
Run the included `benchmark.py` with the repository's `.venv/bin/python`,
`--repository <archive> --chainergame ../../ChainerGame --petta ../../PeTTa
--json-out <output> --seed 7 --budget 600`. Use seeds 11 and 23 with budget 300
for the other workloads. Validation uses `PETTA_STRICT=1 PETTA_JOBS=8
scripts/verify.sh`, with `scripts/test_metta.sh` preserving the MeTTa runtime
working directory. Archive Python validation requires pointing `GIT_DIR` at the
real repository's `.git` and `GIT_WORK_TREE` at the archive for package metadata.

Full local snapshots and logs are mirrored in
`scratch/stationops-consumer-views-2026-09-09/` (gitignored).
