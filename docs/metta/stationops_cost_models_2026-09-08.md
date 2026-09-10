# Cost-model screening after removal of the success prior

Neither cost model tested here recovers the useful refinement lost when the
base-rate success multiplier was removed. Average operation cost makes the
original workload slower. Counting waiting consumers saves some work across
three scenarios, but does not improve belief quality or coverage. These are
screening experiments, not established scheduler improvements.

The checked-out runtime remains `cb90add2` on
`experiment/no-base-rate-success-prior`. All probe code is confined to isolated
archives. No additional runtime policy is adopted and `master` is unchanged.

## Experimental controls

- ChainerGame `99fc56e`, two shifts, four modules, action budget 1. The primary
  case is seed 7 with diagnosis budget 600. The consumer-count model is also
  tested on seeds 11 and 23 at budget 300. Those additional cases were selected
  before seeing the final model's results and the formula was not adjusted
  between cases.
- Both sides of each pair use the same instrumented runtime. Instrumentation
  records Prolog inferences around claimed agenda work, including synchronous
  proof publication and demand work. It excludes some outer queue bookkeeping.
  Timings must be compared within pairs, not directly to uninstrumented runs.
- The adjustment is enabled only during shift-two diagnosis. Shift one is
  unchanged; complete normalized first-shift proofs match within each pair.
  Adjustments are cleared before subsequent action selection.
- Depth, confidence-gain estimates, truth-value formulas, and proof acceptance
  are unchanged. Neither model uses expected answers, game-specific labels, or
  outcome-tuned coefficients. There was no fetching or rebuilding.
- Each table row is one screening pair. Small timing differences are not
  established repeatable speedups. This is still one application family;
  broader workloads and full semantic validation would be required before
  adoption.

## Average operation cost

Operations are grouped by agenda kind and CPU function or statement head.
The model learns mean inference work from shift one, then freezes those
estimates for shift two:

```text
relative_cost(class) = mean_work(class) / mean_work(all_operations)
queue_utility       = existing_demand / relative_cost(class)
```

An unseen class keeps the original utility. This avoids per-update cost-model
invalidation and uses no timing-derived ordering.

On seed 7, second-shift diagnosis changes from **32.91 to 53.87 seconds**, and
inferences from **124,176,770 to 225,712,118**. Coverage remains 100%, but Brier
error increases from **0.16358112 to 0.16371334**. The main weak estimate stays
at strength **0.22050793**, far from the earlier success-prior baseline's
approximately **0.72229966**. The probe's unadjusted answers match `cb90add2`.

The measurements explain a limitation of this predictor:

| Operation | Shift-one mean inferences | Shift-two mean inferences |
| --- | ---: | ---: |
| Inheritance expansion | 182,847 | 229,188 |
| CTV modus-ponens expansion | 133,963 | 295,897 |
| Fold refresh | 83,808 | 466,756 |

Fold refresh cost grows about 5.6 times between shifts. Costs also vary widely
within a class: shift-one Inheritance expansion has median 21,120 but maximum
11,482,481 inferences. The formula's arithmetic is only part of the operation;
the proof graph and triggered publications change its cost substantially.

## Waiting-consumer count

The second model uses a current graph property with no learned coefficients:

```text
estimated_cost(goal) = max(1, number_of_registered_waiters(goal))
queue_utility       = existing_demand / estimated_cost(goal)
```

Registered waiters include paths that may no longer contribute live demand;
this is a proxy for bookkeeping fanout, not an exact proof-traversal count.
The issued cost is stored with the goal's scheduling metadata in a dedicated
indexed space. At claim time, changed cost forces requeueing even when raw
demand is unchanged. Cancellation still uses the original raw-demand rule.
Issued costs are cleared with the query arena.

| Seed / budget | Shift-two seconds, control → candidate | Inferences, control → candidate | Coverage, both | Brier error, control → candidate |
| --- | ---: | ---: | ---: | ---: |
| 7 / 600 | 32.79 → 28.40 | 124,929,523 → 116,536,526 | 100% | 0.16358112 → 0.16367047 |
| 11 / 300 | 3.34 → 2.93 | 12,759,830 → 11,966,704 | 75% | 0.00509530 → 0.00509530 |
| 23 / 300 | 2.49 → 2.32 | 9,272,443 → 9,044,931 | 75% | 0.00392242 → 0.00397154 |

Both sides answer the same roots in each case. The two lower-budget cases
already have 50% coverage in shift one and 75% in shift two. Their Brier errors
cover only answered roots and must not be interpreted as full-coverage quality.
The existing benchmark's full-coverage assertion therefore fails on both sides
of those cases; its JSON is saved before that assertion. They are not passing
acceptance runs.

Scores and regrets are unchanged within each pair: seed 7 scores 637 with
zero regret; seed 11 scores 642 with regret 17.292347; seed 23 scores 642 with
zero regret. All recorded query abort counts are zero. The maximum issued
consumer-count costs are 591, 211, and 87 respectively, confirming that the
adjustment actually activates. The seed-7 main estimate remains 0.22050793.

## Validation and evidence

Both final probe implementations pass the pinned strict type/determinism
checker. Focused consumer-count checks verify activation, counting three then
four waiters, and preserving the previously issued cost for freshness checks.
No full-suite acceptance is claimed for these isolated policies; none is being
promoted into the runtime.

Earlier consumer-count trials are excluded: a bare-atom activation marker did
not match in the space, so they were no-op trials. The final probe uses a tuple
marker, asserts activation before diagnosis, and records issued costs. The
final version also includes explicit cost freshness in the claim path.

The committed compact results, `cost-model-results-2026-09-08.json` (removed from the tree to keep it small; retrieve it with `git show 454564c4:benchmarks/stationops/cost-model-results-2026-09-08.json`),
include metrics, normalized proof hashes, operation statistics, source patches,
and probe drivers. Full raw JSON, logs, and probe sources are retained locally
under `scratch/stationops-cost-models-2026-09-08/`.

The consumer-count result is a possible small efficiency improvement, not a
solution to the lost refinement. Adding further cost coefficients to fit seed
7 is not justified by these results. Expected benefit remains a separate,
unresolved part of the scheduler model.
