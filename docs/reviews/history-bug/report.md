# Issue 54: exclusion-filtered branch rebuilding

Worktree: `.claude/worktrees/history-bug`, branch `history-bug`, based on
master `cca2b3333c1824d52e6289040db52df2d0bb0ae2`. No changes to the context
overlay, compiler, or public API.

## Diagnosis and change

In `pettachainer/metta/runtime/backward/evaluation.metta`, `sk-admits?`
(line 1357) rejects views whose transitive dependencies intersect the consumer's exclusion
set. `sk-value` (line 2259) selects exclusion-filtered versions when the cached open
merge's dependencies intersect that set. Previously `sk-admit-step` then
searched only `sk-older-views` (line 1511): it could never create a compatible branch
that had not been built before the merged view.

`sk-admit-step` (line 1380, older-view fallback at line 1387) now rebuilds a dependency-rejected ordinary row under the
consumer's exclusions before falling back to older compatible views.
`sk-rebuild-view` uses the existing indexed row lookup and `sk-row-view`,
carrying exclusions through all recursive reads. An excluded owner or mandatory
direct premise makes rebuilding impossible and is skipped. Every rebuilt row
spends the existing weighted evaluation allowance and increments `row-computes`.
If it cannot pay, it marks the row stale through the existing reader cascade,
which preserves retry after a partial result; no unlimited recursive expansion
or inference on insertion is introduced.

The returned branch is local to the reader. It is not installed into the
ordinary latest/history stores, where its additional cuts would be lost.
Thus this implementation is compatible with the MM2 reuse condition
`deps intersect E2 = empty and cuts subset E2`: it does not cache reconstructed
branches across exclusion sets. Ordinary historical views retain their existing
reuse semantics. This keeps the change small and avoids a new invalidation or
proof-root store. Repeated reads may pay to rebuild the same branch; memoizing
settled branches with explicit cuts remains a possible performance improvement.

The direct-premise check matters: a first draft attempted many impossible
rebuilds and spent allowance unnecessarily. That draft was rejected after the
quick comparison; the final code skips those attempts.

## Regression evidence

The new Python campaign, run with master's actual imported package, produces
20 failures across C1 and the cycle permutations. The candidate passes. The
campaign runs in a subprocess: its many durable KBs must not increase the
shared runtime's holder inventory before the existing GC phase tests, whose
setup advances at most 5000 collector units. The GC assertions are unchanged.

- Cold and warm C1, budgets 200 and 5000, and queries of M/B/X again: exact
  proof `revision(xf, bx(mb(mf)))`, confidence `0.888849375588311`.
- All six permutations of a three-node cycle and all 24 permutations of a
  four-node cycle, querying every member after each insertion: final proof
  and truth value agree with the cold graph.
- Unsupported cycles, with no fact or only the target's own fact: no new
  self-support or confidence increase.
- MeTTa budget regression: zero allowance produces no admissible B view and
  leaves B stale; one paid row returns `mb(mf)`, evidence exactly `{mf}`,
  dependencies contained in `{M,B}` and disjoint from `{X}`. Adding bx and
  querying X after that unpaid read converges to C1's expected revision.

## Changed existing expectations

These are cyclic-model consequences or finite-budget work changes, not changes
to any PLN truth formula.

| Fixture | Old | New | Reason |
| --- | --- | --- | --- |
| near-root evaluation, Same C1 B1, budget 25 | confidence 0.8999998721576475 | 0.8999998199501539 | Rebuilding consumes the same bounded evaluation allowance. Existing computation-count bound still passes. |
| nested conditioning, Degraded plant t5 | (0.14626802934111227, 0.9999620912647443) | (0.138655, 0.9999359441308396) | Exclusion reads rebuild admissible branches in the persistence/completion cycles. The new result also occurs at budget 3000; conditioned-evaluation bound remains unchanged. |
| Or inversion, LocalProblem current | prior (0.4181818181818182, 0.0011237357972281184); result (0.4001269843833966, 0.900036481087304) | prior (0.4185934569191004, 0.0011238544987638187); result (0.4001273433488443, 0.9000365438768168) | Previously hidden compatible views refine the local base-rate fold; proof shape is unchanged. Same result with ten times the query budgets. |
| overlap conditioning, budget-limited recovery | recovery budget 20 | 200, same expected truth value | Recovery now pays for branch rebuilding as well as conditioning. The initial budget-10 fallback and pending-work checks are unchanged. |
| flyingraven, Sam | (0.9786915593831819, 0.643251683490094) | (0.978691559383184, 0.6432516834961431) | Rebuilt views change the numeric conditioning path slightly; complete proof shape and shared-proof identities are unchanged. |
| smokes, Edward cancerous | (0.4199998330935358, 0.9335532845458568) | (0.41999279005873374, 0.9335544641629187) | The proof now retains the admissible Anna/Frank/Edward completion branch while excluding the consumer. The full shared proof is pinned in the example. |

## Validation and benchmarks

- Strict MeTTa suite: **136 passed, 0 failed**.
- Python suite: **134 passed**, including the three-test isolated cycle campaign.
- Final `scripts/verify.sh`: **all six gates PASS** in 91 seconds (MeTTa
  lint, MeTTa suite, Python unittest, import scaling, judgment scaling,
  ConceptNet). Python metrics: 819 query rows, zero aborts; judgment scaling:
  three query rows, zero aborts. Import scaling's late/early median is 0.971,
  below the existing 1.5 limit.

`compare.sh master <worktree> --full` completed: **REGRESSIONS (13)**,
accuracy changed in **11 cases**. There are nine accuracy flags and four
confirmed timing flags. The 28-case run executed 63 jobs and reused two
results; all base/candidate jobs exited zero. No nondeterminism was reported.
The candidate's PeTTaChainer source tree is `220b53234d4d` (frozen build
`cca2b333-d310d5415`); the full report labels the candidate
`cca2b333-d16b42454`, the same production tree with updated test snapshots.

Full report:
`/nexus/Dev/OpenCog/bench/results/compare/cca2b333_vs_cca2b333-d16b42454_full/report.md`.

The first concurrent full/curves launch hit a benchmark snapshot-directory
rename race. Retrying the full comparison after the curves snapshot existed
completed normally; no benchmark scripts or stored results were edited.

### Accuracy changes

The change is entered only when a view's dependencies intersect the reader's
exclusions. It recovers branches in the cycles produced by inversions,
completion rules, temporal persistence and refined rules. It also changes the
allocation of finite evaluation budgets. Therefore a changed benchmark mean
is not by itself evidence of greater Bayesian accuracy; these measured
regressions are retained for review. The suite does not distinguish every
individual prediction's branch-recovery effect from its budget effect.

All changed aggregate error values in the full comparison:

| Case | Master error | Candidate error |
| --- | --- | --- |

| supplynet stage 3 timed b50 s3 | 0.00157910134 | 0.00257855987 |
| supplynet stage 3 timed b100 s3 | 0.00279861439 | 0.00293057965 |
| supplynet stage 3 untimed b25 s4 | 0.000598539557 | 0.00113063383 |
| supplynet stage 3 untimed b50 s4 | 0.001018352 | 0.0012066625 |
| supplynet stage 3 untimed b100 s4 | 0.00095319232 | 0.00117473409 |
| scale l spq16 s1 | 0.000928412642 | 0.0024159978 |
| conflict pln-sources m spq1 s2 | 0.0749686521 | 0.0843503821 |
| conflict pln-sources m spq4 s2 | 0.0765604439 | 0.0897497524 |
| conflict pln-sources m spq1 s3 | 0.223341784 | 0.223394351 |
| conflict pln-sources m spq4 s3 | 0.217989735 | 0.217827266 |
| learned stage 3 timed learned b50 r200 s2 | 0.0625477745 | 0.0630138899 |

Flagged accuracy metrics:

- supplynet stage 3 timed b50 s3 previous_storm error 2.4e-10 -> 0.002967
- supplynet stage 3 untimed b25 s4 degraded error 0.002676 -> 0.005843
- scale l spq16 s1 front error 0.003009 -> 0.008437
- scale l spq16 s1 storm error 0.001499 -> 0.003864
- conflict pln-sources m spq1 s2 error 0.07497 -> 0.08435
- conflict pln-sources m spq1 s2 system error 0.03555 -> 0.05195
- conflict pln-sources m spq4 s2 error 0.07656 -> 0.08975
- conflict pln-sources m spq4 s2 component error 0.1139 -> 0.1282
- conflict pln-sources m spq4 s2 system error 0.03922 -> 0.05132

Confirmed timing regressions (the second pair is the runner's paired rerun):

- supplynet stage 3 untimed b50 s4 seconds 10.62 -> 12.32 (rerun 8.292 -> 9.619)
- supplynet stage 3 untimed b100 s4 seconds 12.43 -> 17.29 (rerun 9.858 -> 13.12)
- learned stage 3 timed learned b50 r200 s1 seconds 16.27 -> 18.32 (rerun 12.52 -> 14.2)
- learned stage 3 timed learned b50 r200 s2 seconds 16.66 -> 19.55 (rerun 13.01 -> 14.76)

Coverage is unchanged throughout. The ProbLog fuzzer has the same eight
flagged KBs, no newly flagged KBs, the same 363 answers, and the same mean
error 0.006075. The four StationOps replay cases have identical belief streams
(800 beliefs total). CombiNet and stage-1 SupplyNet accuracy are unchanged.

### Curves and limits

The requested complete `--curves` run finished in 336 seconds, all seven
curve families completed, with no unsupported cases or timeouts. Report:
`/nexus/Dev/OpenCog/bench/results/compare/cca2b333_vs_cca2b333-d310d5415_curves/curves.md`.

| Curve | Last budget | Master last error | Candidate last error |
| --- | --- | --- | --- |
| scale l s1 | 32 | 1.8469663e-05 | 1.8469663e-05 |
| scale m s1 | 32 | 0.000108449761 | 0.000108449761 |
| stage 3 timed s2 | 200 | 0.00298625966 | 0.00162344775 |
| stage 3 untimed s3 | 200 | 0.00140559526 | 0.00172607449 |
| stage 2 r10 s1 | 200 | 3.90905978e-17 | 3.90905978e-17 |
| conflict m s1 | 16 | 0.114636031 | 0.116173471 |
| replay s3 | 200 | 0.140378451 | 0.140378451 |

At scale l, the full suite's budget-16 error regression disappears at budget
32: both reach approximately 0.000018469663 in 139.1/141.2 chainer seconds.
Scale m's last-budget answers match exactly. Timed stage 3 s2 improves at
budget 200 (0.00298626 to 0.00162345), whereas untimed stage 3 s3 remains
worse (0.00140560 to 0.00172607). Conflict s1's last point is slightly worse;
its best error across the ladder is slightly better (0.10766194 to
0.10754192). These curves show both budget redistribution and persistent
answer changes; they are not a blanket accuracy improvement.

The fix has no cache for exclusion-specific reconstructed branches, so a
reader can rebuild a branch repeatedly. Every such computation is metered;
the cost is visible in the timing and finite-budget accuracy flags above.
The regression family establishes convergence for the reported case and
three-/four-node cycles, not exhaustive history independence for arbitrary
PLN graphs. No merge, push, tag, or acceptance of the benchmark flags is part
of this hand-back.


All task-owned test, verification and benchmark processes completed before
hand-back. No processes are intentionally left running.
