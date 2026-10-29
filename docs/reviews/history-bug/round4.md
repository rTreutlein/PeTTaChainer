# Issue 54, round 4: exclude direct leaves and closed keys

This follows the review of `dc187094`/`0809bf96`, on current master
`22bd1a09`. The round-3 report is historical; its unresolved cache/convergence
failure is addressed here. No context overlay or conditioning payment design
was changed.

## Exact cause and fix

The native trace in
`/nexus/Dev/OpenCog/bench/results/history-bug/round4/trace.log` catches the
first excluded dependency before conditioning: `sk-calibrated-value` returns the
stored `producing-mine-t5` fact while its own key is excluded. That value
passes through the closed read of `FuelArrived t5`, then into the rebuilt
`Fuelled power-plant t5` view. The cache faithfully stores this inadmissible
result; `sk-branch-values` correctly refuses to serve it forever.

There are two source paths, both in
`pettachainer/metta/runtime/backward/evaluation.metta`:

* `sk-leaf-step` (line 130): the direct-fact fast path returned the leaf before
  testing the enclosing rebuild's exclusions. Direct observations now pass
  `sk-branch-excludes?`, which reads the active frame's original exclusions
  and routes rejection through `sk-excludes?`. The dependency node is bound
  once; outside a frame this adds no dependency traversal or cut bookkeeping.
* `sk-closed-read` (line 2882): when no admissible ordinary value exists,
  closing a settled key could reconstruct that excluded key, or supply its
  unfounded value, both of which depend on that key. The closed read now
  refuses an owner excluded by the enclosing rebuild, through the same
  predicate. Explicit given/unfounded
  pins retain their semantics: `sk-premise-step` consumes them before this
  operation.

Both rejection paths record the actual cut in an active rebuild frame. A branch
that loses its only support therefore naturally returns `sk-none` and is
cached settled with the cut. Its wanted request is removed, and a repeated
read reuses that empty result. This fixes production of the inadmissible
value; it does not hide a bad value at cache publication or decline a paid,
admissible inference. A frame now keeps `(frame, original exclusions, cuts)` in the existing
indexed space. A closed read's additional local pins are distinct from those
original exclusions: local completion can still use its own unfounded pins
and direct observations. Both backward and forward entry reset the whole
frame store, including the original exclusions. The interrupted-frame
regression checks the updated representation. The existing dependency/cut
reuse rule, invalidation,
eight-context bound and metered deferred tier are unchanged.

`sk-admits?` still performs exclusion-aware view admission;
`sk-admit-step` selects the filtered version and tries cached/rebuilt branches
before its `sk-admit-older` fallback. The older fallback is no longer
permanent when the deferred tier can finish the requested branch.

## Regressions and convergence

Three isolated regressions in `tests/probes/exclusion_state.py` fail on the
reviewed frozen build and pass here:

1. A direct fact whose key is excluded is rejected and records its cut.
2. An excluded settled complete key cannot return an unfounded value and
   records its cut.
3. A complete A <- K <- X chain rebuilt excluding X settles EMPTY, removes
   its wanted request, and the next read records one hit and zero builds.

The replay fixture `tests/data/history_u4_r12.json` is the supplied untimed
stage-3, seed-4 record trimmed to its first 13 snapshots and associated calls.
`tests/probes/history_closed_replay.py` replays the warm history at budget
2000, refreshes at 2000 and then 20000 as in the review probe, and compares
with a cold load of exactly the same facts/rules queried at 20000. Both
return degraded power-plant t13 strength **0.12665**. The wanted queue is
empty. The frozen round-3 build fails this regression at the cache audit
already in the early rounds.

The audit in `tests/branch_cache_probe.pl` retains the original exclusion set
for each actual cache publication. After every warm query and after the
cold query, it scans surviving settled entries and asserts that none meets
its own original exclusion set. Testing against the smaller recorded cuts
would miss precisely the defect under review.

The regression also compares three additional warm/cold high-budget reads.
Both histories then return approximately 0.08500012380519378. Replaying the
**reviewed round-2 cold build** confirms the same transition: its first cold
read returns 0.12665, and subsequent cold reads return 0.08500012380519378.
The first cold answer is not an invariant of further population/conditioning
refreshes. These raw checks are `cold-repeat-round2.log`,
`cold-repeat-scoped.log` and `repeat-scoped.log` in the evidence directory.
The new test therefore checks the requested 0.12665 comparison and agreement
on further refreshes, rather than mistaking a transient match for convergence.
A single immediate high-budget warm read can still precede the refresh that
matches the first cold answer; the test preserves the supplied probe sequence.

The C1 orders, cycle permutations, unsupported-cycle checks, interrupted
rebuild, cache invalidation, incomplete branches, bounded tier and overlay
isolation remain covered by the existing gates.

## Validation and measurements

All six `scripts/verify.sh` gates pass on the final production source.
MeTTa suite: 136 files. Python unittest discovery: 162 tests, including the
isolated state-test campaign and replay/cache audit. All thirteen state
probes also pass after the final test addition. `verify-scoped.log` records
164 seconds, 910 Python query metric rows and three judgment-scaling rows,
zero aborts. Verification
uses `bench/capped --priority review --slots 8`, the pinned `.venv`,
`PETTA_JOBS=8`, `ulimit -v 16000000` and DISPLAY unset.

Final full report: `/nexus/Dev/OpenCog/bench/results/compare/22bd1a09_vs_0809bf96-d1e3c7497_full/report.md`.
Final curves report: `/nexus/Dev/OpenCog/bench/results/compare/22bd1a09_vs_0809bf96-d1e3c7497_curves/curves.md`.
Production tree: `38582ea5be8b407128d19849715037c3bfbecc5a`. The frozen label contains the
preceding commit plus its diff; the production tree is verified against the
new commit. Full comparison executed 66 jobs, reused
1 results, and took 186.7 seconds.

Full verdict: **REGRESSIONS (3): supplynet stage 3 timed b50 s3 producing_unstocked error 0.001184 -> 0.003642; conflict pln-sources m spq4 s2 seconds 8.992 -> 11.4 (rerun 9.851 -> 11.03); learned stage 3 timed learned b50 r50 s1 seconds 13.23 -> 15.18 (rerun 12.16 -> 13.97)**. Accuracy changes in
9 cases. Confirmed flags:

* supplynet stage 3 timed b50 s3 producing_unstocked error 0.001184 -> 0.003642
* conflict pln-sources m spq4 s2 seconds 8.992 -> 11.4 (rerun 9.851 -> 11.03)
* learned stage 3 timed learned b50 r50 s1 seconds 13.23 -> 15.18 (rerun 12.16 -> 13.97)

### The two round-3 flags

| Flag | Master | Round 3 | Round 4 | Status |
| --- | ---: | ---: | ---: | --- |
| Timed s3 b50 producing_unstocked MAE | 0.00118390519 | 0.00364183754 | 0.00364183754 | Remains |
| Untimed s4 b50, paired confirmation seconds | 8.797 | +13.5% paired overhead | 9.753 (+10.9%) | Cleared |

### Every original flag

Round-2 tables include the original thirteen flags and four subsequently
confirmed flags. Clearing a threshold is not a claim of identical timing.
Accuracy is MAE for the named kind, otherwise whole-case MAE.

| Accuracy flag | Round 2 | Master | Round 4 | Status |
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
| Original previous_storm starvation | 0.000978718283 | 2.39971832e-10 | 2.39971832e-10 | Compared by kind |

| Original timing flag | Round 2 paired master → candidate, seconds | Round 4 paired master → candidate, seconds | Status |
| --- | ---: | ---: | --- |
| supplynet stage 3 untimed b25 s4 | 5.663 → 7.309 | 5.431 → 5.925 | Cleared |
| supplynet stage 3 untimed b50 s4 | 9.241 → 12.93 | 8.797 → 9.753 | Cleared |
| supplynet stage 3 untimed b100 s4 | 10.81 → 14.89 | 10.241 → 11.107 | Cleared |
| conflict pln-sources m spq4 s2 | 10.84 → 12.35 | 9.851 → 11.030 | Remains |
| conflict pln-sources m spq4 s3 | 10.49 → 12.33 | 9.084 → 9.751 | Cleared |
| learned stage 3 timed learned b50 r50 s1 | 13.54 → 16.73 | 12.160 → 13.970 | Remains |
| learned stage 3 timed learned b50 r200 s1 | 11.98 → 16.56 | 12.580 → 13.510 | Cleared |
| learned stage 3 timed learned b50 r200 s2 | 11.79 → 15.67 | 13.928 → 14.102 | Cleared |

### Curves and time to error

The target is master's best MAE in the standard ladder, with a 1e-12 floor.
Time to target is the fastest measured point within 1e-12 of that error;
loads are shown because stored curve points are not matched timing runs.

| Curve | Last budget | Last MAE master / candidate | Target MAE | Time to target, master / candidate (budget, load) |
| --- | ---: | ---: | ---: | --- |
| scale l s1 | 32 | 1.8469663e-05 / 1.8469663e-05 | 1.8469663e-05 | 167.622s (b32, load 24) / 148.341s (b32, load 7) |
| scale m s1 | 32 | 0.000108449761 / 0.000108449761 | 9.48615099e-05 | 67.017s (b16, load 24) / 56.077s (b16, load 10) |
| stage 3 timed s2 | 200 | 0.00298625966 / 0.00246913006 | 0.00215297013 | 14.447s (b100, load 24) / 12.646s (b50, load 24) |
| stage 3 untimed s3 | 200 | 0.00140559526 / 0.00130607713 | 0.0013978389 | 15.166s (b100, load 24) / 19.784s (b200, load 24) |
| stage 2 r10 s1 | 200 | 3.90905978e-17 / 3.90905978e-17 | 1e-12 | 4.032s (b50, load 24) / 3.986s (b50, load 24) |
| conflict m s1 | 8 | 0.110876054 / 0.111006227 | 0.10766194 | 9.803s (b2, load 24) / 9.119s (b2, load 24) |
| replay s3 | 200 | 0.140378451 / 0.140378451 | 0.140378451 | 12.315s (b200, load 24) / 11.188s (b200, load 24) |

Scale l detail (the full comparison's paired spq16 timing and curve spq32
points are different measurements):

| Steps/query | MAE master / candidate | Seconds master / candidate | Load master / candidate |
| --- | ---: | ---: | ---: |
| 16 | 0.000928412642 / 0.000928412642 | 126.481 / 137.060 | 23 / 20 |
| 32 | 1.8469663e-05 / 1.8469663e-05 | 167.622 / 148.341 | 24 / 7 |

Paired full-suite spq16: 126.481 → 137.060s (+8.4%).


### Interpretation and remaining flags

The timed s3 producing_unstocked MAE remains 0.00364183754 versus master's
0.00118390519 at b50. At b100, candidate producing_unstocked remains the same
while master is worse, 0.00568401113. This remains a finite-budget allocation
flag; this patch does not suppress the additional admissible inference to
match the lower-budget master snapshot.

The previous untimed b50 s4 timing flag clears the standard threshold, but
its measured overhead is still **10.9%** (8.797 → 9.753 seconds). Two other
paired flags remain: conflict m spq4 s2, 9.851 → 11.030 seconds (**+12.0%**),
and learned timed b50 r50 s1, 12.160 → 13.970 seconds (**+14.9%**). The
unchanged benchmark thresholds and all paired false flags are preserved in
the full report. Clearing a flag does not mean eliminating the overhead.

All full-suite candidate accuracy values match round 3 except untimed b100
s4's degraded MAE, differing by approximately 2e-11. Compared with master,
the nine changed cases are the same as round 3. The reviewed untimed b25 s4
degraded correction and its independent PLN branch are retained; it is not
reverted to imitate the history-dependent master. The fuzzer matches master:
363 answered queries, MAE 0.006075093128365997, eight flagged KBs, no new
crash, no-answer or budget discrepancy.

Untimed s3 b200 improves from round 3's 0.001642846577 to **0.00130607713**,
versus master's 0.001405595263. It now reaches master's best measured error
at b200, in 19.784 seconds, versus master's 15.166 seconds at b100: convergence
quality recovers, while time to this error remains about **30.5% slower**.
The candidate reaches a lower error at that point, so this is not an
identical-quality last-point timing comparison.

Scale l spq16 has the same error and costs 126.481 → 137.060 seconds
(+8.4%) in the paired full run. Spq32 reaches the same error in
167.622 → 148.341 seconds, but at loads 24 versus 7. The review's previous
132.9 → 149.7-second comparison and these stored curve points do not share
loads; a controlled recovery against 132.9 seconds is not established.

### Branch counters

The supplied review2 profiling driver was replayed unchanged on untimed
stage 3, seed 4, budget 100, final source. All twenty query records are
`round4/metrics-scoped.jsonl`; the sampled profile is
`round4/profile-scoped.tsv`, under the evidence directory. Profile extraction
time is not benchmark time. The maximum of 25 branch builds per query
continues to obey the fixed tier ceiling.

| Counter | Round 3 total | Round 4 total | Mean/query | Maximum/query |
| --- | ---: | ---: | ---: | ---: |
| branch_cache_hits | 59 | 218 | 10.90 | 51 |
| branch_cache_misses | 18024 | 17897 | 894.85 | 1561 |
| branch_builds | 461 | 411 | 20.55 | 25 |
| branch_cache_refreshes | 106 | 120 | 6.00 | 18 |
| row_computes | 8965 | 8933 | 446.65 | 650 |

Hits increase from 59 to 218 and paid builds decrease from 461 to 411.
**Raw misses still dominate hits.** The existing counter counts failed
settled lookups before the mandatory-premise eligibility check, including
branches that cannot be queued and repeated reads within a query. Its
semantics have not been changed to obtain a better ratio. A separate native
probe (`misses-classified.log`) identifies at least 842 mandatory direct
premise rejections among 1,435 misses in the supplied refreshed budget-2000
query; 78 settled hits and 24 paid builds occur in that query. Remaining
misses include other reads/contexts; the diagnostic does not prove every
miss is harmless.

For the supplied high-budget review sequence, the previously stuck queue
now reaches **Wanted=0**, no conditioning debt. At b20000, the captured
refresh uses **12 builds, 44 hits, 910 misses, 8 input-driven refreshes**, with
39,698/40,000 ordinary evaluation units and 4,977/5,000 tier units left.
The reviewed failure used 4,996 builds, about 32,000 misses, 16 hits, and
kept 39 requests queued. This demonstrates removal of the unsatisfiable
rebuild loop, not complete elimination of cache lookup/allocation overhead.

No push, merge, tag, benchmark threshold change or sibling implementation
change is part of this handoff. The remaining accuracy/timing flags and
miss-counter limitation are explicit review items.
