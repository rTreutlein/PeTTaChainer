# Issue 54, round 5: stop invalidating unchanged branch inputs

This follows the review of `231dff62`. Current master is still `22bd1a09`,
already an ancestor of this worktree. The round-4 source admission fix is
retained. No context overlay, budget share, exclusion reuse rule or inference
formula is redesigned.

## Invalidation and reader scheduling

`sk-store-view!` formerly invalidated all cached branch readers whenever a
new proof reference was published. It now compares the new view with that
row's previous view using `sk-same-view?`: truth value, evidence and
dependencies matter, while an equivalent proof's new identifier does not.
The comparison reuses the previous view already matched while replacing
it; there is no additional latest-view lookup. First publication still
invalidates readers of the formerly missing input. Ordinary proof publication
itself remains unchanged.

`sk-drop-merged!` now clears the merge memo and its pending merge debt without
invalidating branch readers. `sk-stale-key!` keeps ordinary stale propagation,
but does not interpret a stale marker as a changed branch input. Actual
external input changes invalidate branches in `sk-dirty-seed`; changing a
row value still invalidates at publication. Removing a nonempty latest view
also invalidates its branch readers in `sk-drop-row-views!`, including when
that row has no exclusion cache of its own. This preserves removal/fold
lifecycle correctness after removing the blanket memo-clear invalidation.

A conditioning grant is scheduling state, not new evidence or a new input.
A settled rebuilt branch has already paid its own conditioning. Clearing an
ordinary key's merge so it can consume its grant therefore does not stale
settled exclusion branches.

The deferred tier previously compared a result only against **stale** cached
entries. A request left queued after a nested build could hit an already
fresh entry, compare it with `sk-none`, and spuriously notify its readers.
The tier now checks the fresh incumbent before its stale fallback. Both an
unchanged actual rebuild and an already-settled request leave reader state
alone. The comparison still ignores proof identifiers, and every real tier
expansion and queue operation retains the existing budget accounting.

## Regressions

The synthetic input test publishes a fresh proof of an identical view,
clears its memo, and marks the key stale: none dirties the dependent branch.
Changing the view does dirty it. Removing the view after a fresh cache
publication also dirties it. The existing C1 test continues to verify that
adding actual evidence causes input-driven branch refreshes.

The notification test now leaves a request queued after its branch settles,
then processes it again. The fresh cache hit must not reschedule either
reader. The existing unchanged-stale-refresh assertion remains. Both new
checks fail against the reviewed production build.

`tests/probes/history_closed_replay.py` replaces the transient 0.12665
assertion. For both warm and cold histories at budgets 2000 and 20000, it
repeats the same query until builds, row computations and conditioned
evaluations are zero. It then requires three more queries to perform zero
work and return the same truth value, checks warm/cold fixed strengths, an
empty wanted queue, and the settled-cache exclusion invariant. This test
fails against `231dff62` because the branch work never stops.

The cache audit now records the original E from the actual frame as it is
removed before publication. Its previous Prolog `setup_call_cleanup` wrapper
could retain a completed call scope until its choice points were discarded,
then associate an unrelated publication with that scope's E. Recording the
runtime frame avoids that test-instrumentation false positive. No production
cache admission change was needed.

`docs/metta/runtime_design_assumptions.md` now states both contracts: direct
facts and closed reads respect the rebuild frame's original exclusions, and
unchanged input plus sufficient allowance must eventually leave the branch
cache quiet. The existing C1 insertion orders, independent evidence, cycle
permutations, unsupported-cycle, interruption, cache-lifetime, partial-work
and overlay checks remain.

## Why 0.085 is the fixed point

The fixture's persistence rule is the certain conditional
`P(D_t | D_previous)=0.75`, `P(D_t | not D_previous)=0.05`, hence
`D_t = 0.05 + 0.70 * D_previous`. The initial observed non-degradation at t9
propagates through t10, t11, t12 and t13 as 0.05, 0.085, 0.1095 and 0.12665.
That calculation has not yet incorporated the later observation of production
at t11 through `runs-power-plant` and its antecedent completion/conditioning.

Once that observed production is incorporated, the settled degraded strength
at t11 is approximately 2.526636607749139e-7. The two remaining persistence
steps give t12 = 0.05000017686456254 and t13 = **0.08500012380519378**.
The small nonzero residual is the finite-confidence PLN estimate of t11,
not a new persistence parameter. Both histories reach this fixed strength;
0.12665 is a transient that the previous test incorrectly pinned. Repeated
identical queries must not keep discarding the conditioned result and
rebuilding its older approximation.

## Gates, comparisons, counters and quiescence

All six final verification gates pass: 136 MeTTa files, 162 Python tests,
949 Python query metric rows and three judgment-scaling rows, zero aborts.
`verify-publish.log` records 183 seconds. The focused fourteen-state-test
campaign and the revised quiescence test pass; both input-invalidation and
already-settled-request regressions fail on the reviewed source. The final
quiescence check additionally requires no unpaid conditioning claim.

Final full report: `/nexus/Dev/OpenCog/bench/results/compare/22bd1a09_vs_231dff62-d8cc99342_full/report.md`.
Final curves report: `/nexus/Dev/OpenCog/bench/results/compare/22bd1a09_vs_231dff62-d8cc99342_curves/curves.md`.
Production tree: `80164967b1054a83466d290662d86e8f1a622020`. This is checked against the handed-back
commit; the frozen build name retains the preceding HEAD plus its source diff.
The full comparison ran 64 jobs and reused 1 result,
in 171.5 seconds. All jobs and probes use review admission
priority, the pinned environment, the memory limit, and DISPLAY unset.

### Full flags

**REGRESSIONS (4)**

* supplynet stage 3 timed b50 s3 producing_unstocked error 0.001184 -> 0.003642
* learned stage 3 timed learned b50 r50 s1 seconds 11.62 -> 13.7 (rerun 11.61 -> 12.96)
* learned stage 3 timed learned b50 r200 s1 seconds 11.81 -> 13.45 (rerun 11.41 -> 13.13)
* learned stage 3 timed learned b50 r200 s2 seconds 12.21 -> 13.69 (rerun 11.89 -> 13.64)

Paired reruns that did not confirm the threshold remain in the standard
report; no thresholds, seeds, budgets, runners or stored results were edited.

| Prior flag / watched case | Round 4 | Master → round 5 | Status |
| --- | ---: | ---: | --- |
| Timed s3 b50 producing_unstocked MAE | 0.00364183754 | 0.00118390519 → 0.00364183754 | Remains |
| Conflict m spq4 s2, seconds | 9.851 → 11.030 (+12.0%) | 9.200 → 9.972 (+8.4%) | Below confirmed threshold |
| Learned timed b50 r50 s1, seconds | 12.160 → 13.970 (+14.9%) | 11.610 → 12.960 (+11.6%) | Flagged |
| Learned timed b50 r200 s1, seconds | 12.580 → 13.510 (+7.4%; below threshold) | 11.410 → 13.130 (+15.1%) | Flagged |
| Learned timed b50 r200 s2, seconds | 13.928 → 14.102 (+1.2%; below threshold) | 11.890 → 13.640 (+14.7%) | Flagged |
| Untimed b50 s4, seconds | 8.797 → 9.753 (+10.9%; below threshold) | 7.711 → 8.621 (+11.8%) | Below confirmed threshold |

Accuracy differs from master in 9 cases.

The final candidate matches round 4 in every measured full-suite accuracy case.

The fuzzer matches master: 363 answered queries, MAE
0.006075093128365997, eight flagged KBs and identical flagged cases.

### Curves and time to error

The target is master's best MAE anywhere in its standard ladder, with a
1e-12 floor. Time to target uses the fastest point within 1e-12 of it. Curve
points come from the result store and can have different loads; paired full
runs are used for timing flags.

| Curve | Last budget | Last MAE master / candidate | Target MAE | Time to target master / candidate (budget; load) |
| --- | ---: | ---: | ---: | --- |
| scale l s1 | 32 | 1.8469663e-05 / 1.8469663e-05 | 1.8469663e-05 | 167.622s (b32; load 24) / 136.047s (b32; load 2) |
| scale m s1 | 32 | 0.000108449761 / 0.000108449761 | 9.48615099e-05 | 67.017s (b16; load 24) / 53.245s (b16; load 5) |
| stage 3 timed s2 | 200 | 0.00298625966 / 0.00246913006 | 0.00215297013 | 14.447s (b100; load 24) / 13.165s (b50; load 24) |
| stage 3 untimed s3 | 200 | 0.00140559526 / 0.00130607713 | 0.0013978389 | 15.166s (b100; load 24) / 16.061s (b200; load 16) |
| stage 2 r10 s1 | 200 | 3.90905978e-17 / 3.90905978e-17 | 1e-12 | 4.032s (b50; load 24) / 3.887s (b50; load 24) |
| conflict m s1 | 8 | 0.110876054 / 0.111006227 | 0.10766194 | 9.803s (b2; load 24) / 9.696s (b2; load 24) |
| replay s3 | 200 | 0.140378451 / 0.140378451 | 0.140378451 | 12.315s (b200; load 24) / 9.848s (b200; load 24) |

Paired scale l spq16: 120.124 → 131.566 seconds (+9.5%).
Scale l spq32 base: 167.622s, error 1.8469663032e-05, load 24.
Scale l spq32 candidate: 136.047s, error 1.8469663032e-05, load 2.

### Quiescence numbers

The same frozen fixture and ten identical follow-up queries are used for
each history/budget. Repeat 1 follows cold loading or all thirteen warm
rounds. Timings below are diagnostic, under concurrent benchmark load.

| Budget | History | First quiet repeat | Quiet rows / builds / conditioning / invalidations | Mean quiet seconds | Stable strength |
| --- | --- | ---: | --- | ---: | ---: |
| 2000 | Cold | 5 | 0 / 0 / 0 / 0 | 0.0099 | 0.085000123805193784 |
| 2000 | Warm | 6 | 0 / 0 / 0 / 0 | 0.0212 | 0.085000123805193784 |
| 20000 | Cold | 5 | 0 / 0 / 0 / 0 | 0.0248 | 0.085000123805193784 |
| 20000 | Warm | 6 | 0 / 0 / 0 / 0 | 0.0358 | 0.085000123805193784 |

Every branch counter (hits, misses, builds and input-driven refreshes) is zero
in those quiet queries. The old reviewed build kept invalidating seven
branches and doing roughly 105–235 row computations per repeat instead.
The new code takes a few refreshes to consume old held work; matching one
transient value is not used as the stopping condition.

At budget 200 a cold run can exhaust its payable work while leaving a
544-unit conditioning claim unpaid (only 400 evaluation units are available).
`raised-budget.log` shows that raising it to 2000 pays the claim, reaches
0.08500012380519378 and then becomes quiet. Zero rows alone is not treated as
proof of convergence when conditioning remains unpaid. The regression uses
sufficient allowances and checks the unpaid counter too.

The full per-history truth values are stable across quiet repeats. At this
fixture's fixed strength, warm confidence is 0.999914849784158 and cold
confidence is 0.9999154383433463. Equality here follows the review's strength
comparison; this work does not claim bit-identical confidence across histories.
The baseline replay in `quiescence-master.jsonl` records the corresponding
master behavior for review.

### Query counters on the changing-input workload

`metrics-publish.jsonl` contains the twenty untimed stage-3, seed-4, budget-100
queries recorded with the supplied `review/warm.py` driver. These rounds add
facts, so they need not be quiet. Profile extraction overhead is not included
in benchmark timings. The maximum of 25 paid builds per query preserves the
fixed tier ceiling.

| Counter | Round 4 total | Round 5 total | Mean/query | Maximum/query |
| --- | ---: | ---: | ---: | ---: |
| branch_cache_hits | 218 | 221 | 11.05 | 47 |
| branch_cache_misses | 17897 | 17826 | 891.30 | 1550 |
| branch_builds | 411 | 409 | 20.45 | 25 |
| branch_cache_refreshes | 120 | 116 | 5.80 | 15 |
| row_computes | 8933 | 8912 | 445.60 | 650 |

Raw misses still include cheap failed eligibility lookups, including mandatory
premise rejections; their definition has not changed. The quiescence test
concerns repeated queries without new input, where all of these counters
become zero.

No push, merge or tag is part of this handoff. Remaining benchmark flags and
the stable confidence difference are explicit review limitations.


### Earlier baseline nondeterminism observation

The pre-optimization round-5 comparison
`22bd1a09_vs_231dff62-d17788c00_full` flagged **master**, scale l spq16 s1,
as nondeterministic in a paired confirmation. Its MAE was
0.0009283936398095356 versus the stored first result
0.0009284126418080698, a difference of -1.900199853423299e-8; Brier differed
by -1.9206155346673803e-9. The cause was not diagnosed in this cache fix.
The final full comparison did not repeat the mismatch. The earlier report
and result-store samples are retained; this is not a claimed fix to master
and no stored accuracy result was changed. Standard reports continue to use
the first stored accuracy sample.

Master's own unchanged-KB replay also becomes quiet. Its cold fixed strength
is 0.08500012140411456, confidence 0.9999154383390005; warm is
0.0850001152331901, confidence 0.9999151339652158. The candidate removes the
observed strength difference across these histories, while the small stable
confidence difference already present in the reviewed candidate remains
outside this quiescence change.
