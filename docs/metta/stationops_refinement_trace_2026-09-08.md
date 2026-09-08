# Refinement tracing, elapsed-time comparison, and depth ablation

This investigation keeps the production runtime unchanged. It compares the
success-prior baseline `1bfbf539`, the no-success-prior experiment `cb90add2`,
and an isolated variant of the latter with the depth term removed from queue
priority. All truth-value formulas, proof acceptance, structural depth, and
cycle guards remain unchanged.

## Where the useful proof is lost

The fixed-600-step trace reproduces both earlier policies' complete normalized
proof answers exactly. The old second-shift main answer is `0.7222996590` with
confidence `0.0001815568`; the new answer is `0.2205079337` with confidence
`0.000001`. These are different proof paths, not faster computation of the same
answer.

Both policies compute the same alarm-derived disjunction, strength
`0.7371764630`, confidence `0.0002945023`. The old policy reaches its
modus-ponens continuation at about 0.43 seconds; the new policy reaches it at
about 3.59 seconds. The missing ingredient is the other module's independent
alarm evidence needed to project that disjunction into a local diagnosis.

| Relevant MAIN-context goal | Old stored depth | New stored depth | Old at 600 steps | New at 600 steps |
| --- | ---: | ---: | --- | --- |
| `ProblemDependency shift-02 M01 ...` | 1 | 2 | Expanded | Expanded |
| `Problem old power-converter shift-02-M03` | 2 | 3 | Expanded | Expanded |
| `PressureAlarm old power-converter shift-02-M03` | 3 | 4 | Expanded | Still queued, unexpanded |

The old policy reads the alarm fact and derives the dependency, then performs
`OrProjection` with approximately `0.05357143` as the other disjunct. The useful
`0.7222996590` value is already present in a claimed continuation at about
0.55 seconds, well before diagnosis finishes at 91.81 seconds. This does not
mean all other root answers are settled by that time.

The new policy first reaches the dependency through its earlier inheritance
answer. When the shorter root-projection path arrives, the dependency has
already expanded. [`ensure-goal-at-depth`](../../pettachainer/metta/runtime/backward/search.metta)
lowers an existing goal's depth only while it is unexpanded. Thus its children
retain an extra depth level. The later root-projection waiter is present in the
recorded arena, but the required MAIN-context alarm goal remains unexpanded
with positive issued demand `0.00001227090343818` at the cutoff. Some similar
alarm goals in hypothetical contexts do expand; those are not the same fact
lookup.

This is concrete evidence of a discovery-order interaction with depth bands,
not proof that depth is the only source of poor allocation. The separate
unexpanded general `Problem old coolant-pump $x` fold source is another delayed
operation, but it is not needed to explain why the old main answer appears
before one second.

The relevant policy is in
[`backward-agenda-priority`](../../pettachainer/metta/runtime/scheduling.metta):

```text
priority = 1e9 * depth - 1e6 * demand - bonus + work_kind_offset
```

Lower values run first. Small goal-ID offsets are added by the queue issuer.
Depth also constrains demand propagation, so blindly changing stored depths
would require checking the acyclic-demand invariant and refreshing affected
queues; it is not an isolated arithmetic edit.

## Experimental controls

- Real ChainerGame source `99fc56e`, seed 7, two shifts, four modules, action
  budget 1. Additional seeds 11 and 23 use diagnosis budget 300. No policy
  coefficient was retuned between scenarios.
- The first shift retains its ordinary step budget in every elapsed-time run.
  The second shift receives a common 10,000-step ceiling and a 30, 60, or
  90-second deadline, checked between agenda operations. It returns available
  answers normally rather than killing a query and losing its partial result.
- Deadlines are soft: one expensive operation and result collection can overrun
  them. Tables report actual diagnosis time. These are independent fresh
  episodes, not repeated queries that accumulate extra hidden search work.
- Timed runs use matching clock/claim instrumentation. Goal/waiter snapshots
  are read after timing. Original fixed-budget answers match the uninstrumented
  historical evidence. No fetching, rebuilding, or production code edits occur.
- The time curves use a different step ceiling from the 600-step trace and
  differ in ordering early in search. The engine has budget-qualified empty
  Member caches, so a larger requested budget can reopen cached empty work.
  These traces must not be spliced into a single
  claimed 600-step execution prefix. Within each time curve, common-prefix
  comparisons are recorded separately in the compact evidence.
- One run per screening condition; no repeated speedup confidence claim.

## Results

### Time-limited second-shift diagnosis, seed 7

All runs keep shift one at 600 steps. Errors apply only to answered roots; a
missing answer is never treated as zero error. “No depth” also removes the
success prior. Each policy generates its own first-shift proof/cache state and
game history; these are end-to-end episode comparisons, not a shared-checkpoint
second-shift microbenchmark.

| Deadline | Policy | Actual seconds | Claimed operations | Coverage | Brier error |
| ---: | --- | ---: | ---: | ---: | ---: |
| 30 s | Old multiplier | 31.17 | 416 | 100% | 0.03102363 |
| 30 s | No multiplier | 30.57 | 603 | 100% | 0.16380192 |
| 30 s | No multiplier or depth | 31.56 | 933 | 25% | 0.07711748 |
| 60 s | Old multiplier | 61.56 | 486 | 100% | 0.03102650 |
| 60 s | No multiplier | 68.90 | 701 | 100% | 0.16371433 |
| 60 s | No multiplier or depth | 64.17 | 1042 | 25% | 0.07711748 |
| 90 s | Old multiplier | 92.91 | 672 | 100% | 0.03102650 |
| 90 s | No multiplier | 92.42 | 769 | 100% | 0.16371433 |
| 90 s | No multiplier or depth | 94.44 | 1135 | 25% | 0.07711748 |

The ordinary no-multiplier policy does not recover the main estimate within
these deadlines. At the longest checkpoint, both sides take about 92 seconds
and have full coverage, while Brier error remains approximately 0.0310 versus
0.1637. The 60-second candidate overruns to 68.90 seconds because stopping is
checked between operations; it still has substantially higher error.

The no-depth variant recovers the main `0.7222996590` estimate at the first
clock checkpoint, but has only 25% coverage there and still only 25% after
94.44 seconds. Its Brier error covers one root and cannot be compared directly with the controls that answer all four.

### Fixed-budget coverage across seeds

| Seed / steps per shift | Policy | Shift-one coverage | Shift-two coverage | Shift-two seconds | Shift-two Brier error |
| --- | --- | ---: | ---: | ---: | ---: |
| 7 / 600 | Old multiplier | 100% | 100% | 91.81 | 0.03103582 |
| 7 / 600 | No multiplier | 100% | 100% | 32.08 | 0.16358112 |
| 7 / 600 | No multiplier or depth | 25% | 0% | 6.34 | — |
| 11 / 300 | Old multiplier | 25% | 25% | 4.56 | 0.00313773 |
| 11 / 300 | No multiplier | 50% | 75% | 3.09 | 0.00509530 |
| 11 / 300 | No multiplier or depth | 0% | 0% | 3.29 | — |
| 23 / 300 | Old multiplier | 25% | 25% | 6.52 | 0.00000000 |
| 23 / 300 | No multiplier | 50% | 75% | 2.24 | 0.00392242 |
| 23 / 300 | No multiplier or depth | 0% | 0% | 3.25 | — |

On both additional seeds, removing the success multiplier increases coverage
from 25% to 50% in shift one and from 25% to 75% in shift two. The one root
answered by both policies keeps exactly the same belief value; the new policy
adds answers for two more roots. The old policy's lower aggregate Brier error
is therefore not evidence of better quality on those cases: it evaluates fewer
roots. Removing depth produces no answers on either shift for these seeds.
All three policies still receive the same game score and regret within each
seed, illustrating why game score alone misses diagnosis regressions.

These additional seeds remain the same application family, and the lower
budget already limits coverage in the controls. They are screening cases,
not passing full-coverage acceptance runs. No constants were adjusted to
improve any seed's answers.

## Validation beyond StationOps

The isolated depth ablation was run through the repository-pinned
`.venv/bin/petta` using `PETTA_STRICT=1 PETTA_JOBS=8 scripts/test_metta.sh` in
its archived checkout: **64 passed, 8 failed**. Tests were not rewritten to
accept the changed policy. Failures include open-query results, existential
reasoning, incremental Member inheritance, conditioned disjunction inversion,
inheritance proof confidence, specializing rules, `flyingraven`, and `smokes`.
`smokes` returns no answer where the baseline fixture requires one. Other
failures include changed refinement/confidence or proof structure; they do not
all establish invalid proofs. No backward-search-aborted message appears.

All 18 screening episodes complete, covering 36 diagnosis batches with zero
recorded search aborts. The clock/trace probe itself passes the strict
type/determinism check and its focused no-depth priority check. Both ordinary fixed-budget traces reproduce
their previously recorded full proof answers. Within each policy's time curve,
the shorter run's claimed work is a prefix of the longer run's work, including
issued scores, depths, goal variable sharing, and operation kinds. These checks
are recorded in the compact results. No full-suite acceptance or production
adoption is claimed for the depth variant.

## Interpretation and next target

The cross-seed coverage improvement argues against simply restoring the old
multiplier based on seed 7. The base-rate multiplier was not a valid estimate
of finding any proof, but removing it changes which shared goals are discovered
and expanded first.
Stored depth then preserves that discovery history in later scheduling. The
trace identifies a concrete delayed prerequisite for the useful proof; it does
not establish that changing one depth guard would safely fix the scheduler.

Removing all depth preference loses coverage at existing budgets and fails
multiple unrelated examples. The more focused next experiment is how late,
shorter root paths should affect scheduling of already-expanded shared goals
and their pending descendants. Structural depth also prevents circular demand,
so a solution must preserve that invariant and validate queue freshness and
coverage on generic shared-goal cases. No extra coefficient or game-specific
priority is justified by these results.

The [compact evidence](../../benchmarks/stationops/refinement-trace-results-2026-09-08.json)
contains exact revisions, per-run environments, answers, metrics, selected goal
traces, source patches, drivers, and the full MeTTa suite log. Raw per-run JSON
and logs are retained locally under
`scratch/stationops-refinement-2026-09-08/`. The runtime remains on the existing
experimental branch; `master` is unchanged.
