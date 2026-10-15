# Issue 54, round 3: sound cuts and deferred rebuilds

This follows the review of `84fcd24f`. The work remains based on current
master `22bd1a09`. The earlier [cache report](cache-followup.md) records round
2 and its unsuccessful performance recovery; its measurements are historical.

## Correctness

In `pettachainer/metta/runtime/backward/evaluation.metta`, `sk-admits?` (line 1371) is the
exclusion-aware admission test; `sk-value` (line 2399) selects the readable
views. `sk-admit-step` (line 1394) tries a compatible branch and then falls
back to `sk-admit-older` (line 1380). The old failure was that the rejected
merged view concealed an independent branch and this fallback could stay
there forever, irrespective of query budget.

Every exclusion rejection now passes through `sk-excludes?`. It records
intersecting dependencies only while `sk_branch_at` identifies an active
rebuild frame. The conditioned re-read in `sk-given-view`, the left-out
rebuild, and rejected older views therefore contribute their cuts too.
Dependency tests concerning provisional folds or given statements are not
exclusion rejections and keep their original predicates. Settled reuse still
requires `deps ∩ E = ∅` and `cuts ⊆ E`. Dominance pruning and the eight-entry
per-row cache limit remain.

Backward query entry and forward entry reset the abandoned frame pointer,
cut-frame rows and active ordinary readers. The interruption probe injects
an exception during a real rebuild, proves that a dead frame/reader exists,
then starts another query and verifies that all three transient stores are
empty. No deferred request is cleared by that reset.

## Scheduling and lifetime

An ordinary read at frame zero never rebuilds inline on a cache miss. It
keeps a compatible stale cached branch, otherwise an older compatible view,
queues `(slot, hash, key, row-hash, exclusions)` in `&sk_branch_wanted`, and
holds the active reader through the existing `sk_holding` path. The
mandatory direct-premise check remains ahead of enqueueing: such a branch
cannot succeed, so it needs neither a request nor a held reader. Missing
row matches also leave no request. This preserves the existing no-self-support
behavior without adding a transitive prewalk.

After ordinary work and restales, the scheduler rotates through wanted
branches. It temporarily lends a rebuild at most the smaller of the remaining
evaluation allowance and its tier allowance, then restores the ordinary
allowance minus actual expenditure. Nested rebuilds remain inline within
that slice and still pay `sk-take!` per row. The tier ceiling is one eighth
of the original evaluation allowance; a zero-work lookup consumes one tier
unit too, bounding queue administration. Late misses from root merges or
conditioning receive the same remaining tier, without a second allowance.
Unsettled requests move to the tail and survive subsequent queries. A request
stays stored until its rebuild returns, so interruption does not lose it.
Row retirement removes pending requests even if no cache entry was built.

A semantically changed branch reschedules the requesting readers via
`&sk_restale`. Each row excludes its own key, so arrival notification selects
readers in the request's exclusions rather than forcing every reader of the
owner key. Distinct arrival causes allow another branch of the same owner to
notify a reader that already processed an earlier arrival. Forward runs mark
these previously requested readers needed so ordinary recomputation remains
charged.

An unchanged settled refresh does not force its readers merely because it
settled: that can publish another equivalent proof and invalidate the branch
again through a cycle. Equality uses the existing value/evidence/dependency
comparison, which deliberately ignores allocated proof identifiers.

A deferred row outside the ordinary need closure cannot wait for an ordinary
conditioning grant. Its rebuild pays that claim inside the same bounded
slice, or draws from the enclosing paid claim if one is already active.
It does not grant payment to the ordinary view. Settlement uses the rebuild's
unpaid-generation marker: actual `sk-wait!` calls already advance it; an
ordinary view's pre-existing conditioning debt alone cannot prevent a
different exclusion context from settling. The regression rebuilds a real
entangled conjunction outside the need closure, checks that conditioning is
charged, and preserves the ordinary view's debt and lack of a grant.

A positive unfinished result is retained as a stale incumbent with the entire
exclusion set as conservative cuts. It cannot satisfy a settled lookup or
prune settled entries. This preserves already paid inference while a nested
rebuild or conditioning claim waits; an empty incomplete result retains the
old incumbent. Existing invalidation subscriptions, proof/dependency roots,
dominance pruning, and bounded retirement apply to these entries too.

Wanted work is context local: MAIN requests survive queries; Assuming worlds
create their own requests and retire them with the world. MAIN still releases
held readers at its original point. Before applying assumptions, a world
locally relinks borrowed stale rows within the existing near-root need depth,
using its ordinary refresh path and reserve. The overlay regression verifies
the strengthened local C1 answer, stable MAIN truth/evidence/dependencies and
expanded proofs, and no MAIN writes while the world is active. Allocated proof
identifiers may change during MAIN maintenance before the world starts.

## Metrics and tests

Query metrics add `branch_cache_hits`, `branch_cache_misses`, `branch_builds`,
and `branch_cache_refreshes`. Hits count settled cache reuse; misses count
failed settled lookups, including requests that are already queued. Builds
count paid row expansions inside a rebuild. Refreshes count paid builds with
the cache's input-invalidation marker set; continuing an unfinished first
build is not an input-driven refresh. Metrics-disabled execution avoids the
refresh diagnostic lookup.

The three missing-cut regressions and the interrupted-rebuild regression
were first run against the reviewed production source and failed there.
The additional probes cover persistent requests across zero-budget queries,
the tier ceiling (ten queued rows, allowance three, exactly three builds),
retirement before first build, C1 hit/miss/refresh counters, conservative
unfinished cache entries, and notification of only the requesting reader.
The last probe fails on the preceding broad-notification implementation,
which wakes both readers. The unchanged-refresh and branch-conditioning
assertions also fail on their preceding implementations. Nine isolated state
tests pass now.

Both C1 orders still return confidence `0.888849375588311`, evidence
`{mf, xf}`, and the independent route `bx(mb(mf))` at budgets 200 and 5000,
including repeated queries. The three-/four-node cycle family keeps all
six/24 insertion permutations; unsupported cycles retain no self-support.
All round 1/2 assertions remain, with direct cache tests explicitly invoking
the deferred tier instead of assuming an inline rebuild.

Three finite-budget snapshots return to master: nested conditioning at 300
steps, flyingraven Sam, and smokes Edward at 500 steps. The smokes answer at
5000 steps still includes round 2's additional Anna–Frank completion branch
and its truth value `(0.41999279005873374, 0.9335544641629187)`. The change is
allocation, not refusal of that inference. Flyingraven's higher-budget
probe retains master's truth value as well. The partial-fold completeness
regression remains unchanged.

## Gates and query instrumentation

`scripts/test_metta.sh` passes all 136 files; Python unittest discovery passes
all 161 tests. `scripts/verify.sh` passes all six gates in 118 seconds, with
886 Python query metric rows and three judgment-scaling rows, zero aborts.
All PeTTa/test/probe processes use the repository-pinned environment through
`bench/capped --priority review`, with the prescribed memory limit and DISPLAY
unset. No benchmark runner, threshold, seed or stored result was edited.

The supplied review2 profiling driver was run on the same untimed stage-3,
seed-4, budget-100 case, against frozen production tree
`b6a9c5d236e98b89bbe65780ddde1847bdacbddb`. All 20 query records are in
`/nexus/Dev/OpenCog/bench/results/history-bug/round3/met_final_claims.jsonl`;
the sampled profile is `prof_final_claims.tsv` alongside it. The driver profiles
query calls 3 and 9. Its profile-tree extraction adds several minutes outside
the chainer and is not a benchmark timing measurement.

| Counter | Total, 20 queries | Mean/query | Maximum/query |
| --- | ---: | ---: | ---: |
| branch cache hits | 59 | 2.95 | 7 |
| branch cache misses | 18024 | 901.2 | 1540 |
| paid branch builds | 461 | 23.05 | 25 |
| input-driven refreshes | 106 | 5.3 | 16 |
| all row computations | 8965 | 448.25 | 653 |

The build maximum is exactly the 25-unit tier ceiling at 100 query steps
(`2 × 100 × 1/8`), versus the review's approximately 65 rebuilds/query.
Refreshes are a subset of builds. Misses include repeated lookups for queued
work and lookups rejected by the subsequent mandatory-premise check, so
their count does not mean that many rebuilds. Empty/inadmissible reads add
no paid build. First query: 330 misses and zero builds.

For the two sampled queries, inclusive rebuild ticks fall from 419 in
review2 to 94; `deps-excluded` ticks are 34 versus 31, and cut-recording
self ticks fall from 16 to 4. `sk-branch-values` self ticks are 14 versus
11; cache lookup overhead remains real. Sampling is noisy and inclusive
times overlap; these counts are diagnostic evidence, not additive wall-time
savings. The full and curve runs below measure performance independently.

## Full comparison: every original flag

Final full report: `/nexus/Dev/OpenCog/bench/results/compare/22bd1a09_vs_df91208c-d100e038d_full/report.md`.
Production tree: `b6a9c5d236e98b89bbe65780ddde1847bdacbddb`. The frozen build label predates
commit amendment; its production tree equals the handed-back commit.
The run executed 72 jobs and reused 1 result in
343.8 seconds. All candidate processes exit zero; no
nondeterminism or new fuzzer discrepancy is reported.

**REGRESSIONS (2): one accuracy flag and one confirmed timing flag**, down
from round 2's 17 (nine accuracy and eight timing). Accuracy changes in nine
cases. The original previous-storm starvation and both scale spq16 errors
now match master; the five conflict s2 accuracy flags clear. Seven of the
eight round-2 timing flags clear. One original timing flag remains: untimed
b50 s4, paired rerun 9.661 → 10.97 seconds, about 13.5% slower.

The fuzzer matches master exactly: 363 answered queries, mean error
0.006075093128365997, eight flagged KBs (seven error, one no-answer), zero
crashes, wrong-direction cases or budget regressions. A temporary broad
notification draft introduced a ninth flagged KB; restricting notifications
to the requesting exclusion context removed it. Replaying that seed
22000162 on the final source at budgets 2000/10000 recovers the same
conditioned F(a) answer as master, strength 0.5612738588742218.

Errors below are mean absolute errors by the named kind or whole case.
The original 13 flags and all five additional round-2 flags are covered by
these accuracy/timing tables; the previous-storm row also shows the original
flag already below threshold in round 2.

| Original accuracy flag | Round 2 candidate | Master | Round 3 candidate | Status |
| --- | ---: | ---: | ---: | --- |
| supplynet stage 3 timed b50 s3 producing_unstocked | 0.00322605604 | 0.00118390519 | 0.00364183754 | Remains |
| supplynet stage 3 untimed b25 s4 degraded | 0.00584272953 | 0.00267607657 | 0.00306496106 | Cleared threshold |
| scale l spq16 s1 front | 0.00843695256 | 0.00300934308 | 0.00300934308 | Cleared threshold |
| scale l spq16 s1 storm | 0.00386378764 | 0.00149882374 | 0.00149882374 | Cleared threshold |
| conflict pln-sources m spq1 s2 | 0.0842077308 | 0.0749686521 | 0.0749726108 | Cleared threshold |
| conflict pln-sources m spq1 s2 system | 0.0519459738 | 0.0355480383 | 0.0355837568 | Cleared threshold |
| conflict pln-sources m spq4 s2 | 0.0866573256 | 0.0765604439 | 0.0760437841 | Cleared threshold |
| conflict pln-sources m spq4 s2 component | 0.121272131 | 0.11390325 | 0.112845723 | Cleared threshold |
| conflict pln-sources m spq4 s2 system | 0.0520425198 | 0.0392176382 | 0.0392418456 | Cleared threshold |
| Original previous_storm starvation | 0.000978718283 | 2.39971832e-10 | 2.39971832e-10 | Matches master |

The untimed b25 s4 degraded change has not been declared an accuracy fix:
its cold answer was already reviewed as correct PLN. Deferring the rebuilds
changes its finite-budget value again. Clearing the threshold does not
establish convergence or justify discarding the admissible branch.

The remaining timed b50 s3 producing_unstocked flag is slightly worse than
round 2. At b100 its error is still 0.00364183754, while master's error is
0.00568401113; the whole-case candidate error is then 0.00215211869 versus
master's 0.00279861439. This is consistent with changed finite-budget
allocation; it is not an established convergence improvement for that kind.
The supplied warm/cold probes locate the additional error in round 16's
three producing roots. For plant-a and power-plant t17, warm is
0.45798658575086104 versus cold-at-2000 0.4643697759498394 and exact posterior
0.5051254218266992. For mine, the values are 0.4213475398272538,
0.42722015062553315 and 0.4647153880805632. Round 18's warm/cold producing
values agree within 1.6e-7. These samples support retaining the flag for
review rather than labeling it a proven convergence correction. Records are
in `round3/t3b50.json` and `round3/cold-t3-r16-b2000.json` under the task's
benchmark-results directory.

| Original timing flag | Round 2 paired base → candidate, seconds | Round 3 paired base → candidate, seconds | Current status |
| --- | ---: | ---: | --- |
| supplynet stage 3 untimed b25 s4 | 5.663 → 7.309 | 5.963 → 6.745 | Cleared |
| supplynet stage 3 untimed b50 s4 | 9.241 → 12.930 | 9.661 → 10.970 | Remains |
| supplynet stage 3 untimed b100 s4 | 10.810 → 14.890 | 11.110 → 12.140 | Cleared |
| conflict pln-sources m spq4 s2 | 10.840 → 12.350 | 11.210 → 12.020 | Cleared |
| conflict pln-sources m spq4 s3 | 10.490 → 12.330 | 10.700 → 11.410 | Cleared |
| learned stage 3 timed learned b50 r50 s1 | 13.540 → 16.730 | 14.138 → 13.372 | Cleared |
| learned stage 3 timed learned b50 r200 s1 | 11.980 → 16.560 | 14.040 → 15.270 | Cleared |
| learned stage 3 timed learned b50 r200 s2 | 11.790 → 15.670 | 14.630 → 16.040 | Cleared |

Timing rows use the paired confirmation where one ran, otherwise the actual
paired initial runs. Removed flags mean the standard comparison did not
confirm its threshold, not zero overhead. Eight initial timing flags were
not repeated by their paired reruns; the full report preserves those raw
measurements. Scale l spq4, which flagged in an intermediate draft, is not
a final timing flag.

## Curves and time to error

Complete seven-family report: `/nexus/Dev/OpenCog/bench/results/compare/22bd1a09_vs_df91208c-d100e038d_curves/curves.md`.
The target is master's best error anywhere in its standard ladder (with a
1e-12 floor for effectively zero error). Time to target is the fastest
measured point meeting it, within 1e-12. Last-point error remains visible
because these are non-monotone budget curves. The standard stopping rule
ended conflict at spq8; no custom seed or ladder was substituted.

| Curve | Last budget | Last error, master / candidate | Target error | Time to target, master / candidate (budget; load) |
| --- | ---: | ---: | ---: | --- |
| scale l s1 | 32 | 1.8469663e-05 / 1.8469663e-05 | 1.8469663e-05 | 167.622s (b32; load 24) / 155.387s (b32; load 5) |
| scale m s1 | 32 | 0.000108449761 / 0.000108449761 | 9.48615099e-05 | 67.017s (b16; load 24) / 62.381s (b16; load 10) |
| stage 3 timed s2 | 200 | 0.00298625966 / 0.00246913 | 0.00215297013 | 14.447s (b100; load 24) / 13.759s (b50; load 24) |
| stage 3 untimed s3 | 200 | 0.00140559526 / 0.00164284658 | 0.0013978389 | 15.166s (b100; load 24) / not reached |
| stage 2 r10 s1 | 200 | 3.90905978e-17 / 3.90905978e-17 | 1e-12 | 4.032s (b50; load 24) / 3.954s (b50; load 24) |
| conflict m s1 | 8 | 0.110876054 / 0.111006227 | 0.10766194 | 9.803s (b2; load 24) / 9.225s (b2; load 24) |
| replay s3 | 200 | 0.140378451 / 0.140378451 | 0.140378451 | 12.315s (b200; load 24) / 11.636s (b200; load 24) |

Scale l reaches the same spq32 error on both builds. Current stored times
are 167.622 versus 155.387 seconds, compared with the review's 132.9 versus
149.7 seconds. These are different loads/runs (24 versus 5 slots in the
current spq32 points); this does **not** establish a controlled recovery
relative to the review's 132.9-second reference. The matched full spq16
rerun is 110.5 → 119.1 seconds and does not confirm the timing threshold;
spq16 accuracy now matches master. Untimed s3 does not reach master's best
error in the measured ladder and remains a real curve limitation.

## Remaining convergence probe and limits

The supplied warm/cold replay scripts were also used on untimed s4. At round
12, the cold budget-2000 answer for Degraded power-plant t13 is 0.12665.
The warm budget-2000 answer is about 0.08500012; repeating at budget 20000
still returns 0.08500012380519378, with 38 deferred requests, the whole branch
tier spent, and no ordinary conditioning debt left. The large temporal
fixture is therefore **not demonstrated converged**, and the previous
review's cold-answer recovery is not claimed for this warm workload at
these budgets. The trace shows retained partial contexts and work outside
the ordinary need closure. It does not show an exhausted deferred queue.
C1 and the permutation family do converge at their asserted budgets.

The implementation retains the prescribed anytime/deferred work and all
correctness regressions, but this broader convergence/performance limit,
the untimed s3 curve, and the two full-suite flags remain for review. No tag,
push or merge is performed.
