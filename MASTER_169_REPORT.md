# master-169: an inapplicable generic rule must not change a grounded channel's answers (#169)

Builder: Claude. Branch `master-169`, worktree `.claude/worktrees/master-169`, from master `d6207b87`.

## Commits

- `b89eaee3` Drop producers whose positive-only antecedent can never hold. Adds the producer filter in
  `source_catalog_template`, `tests/test_inapplicable_producers.py` and the contract paragraph.
- `d15c537c` Judge open positive-only antecedent conjuncts by unifying instances. This is the cp1 review blocker.
  It extends the rule to open conjuncts and drops the forward-only and user-rate checks, which the any-role
  producer check covers. The test now covers every strict metadata subset and a wrong About shape.
- `10ca38d3` Bill graph work at a measured 1/1700 unit per operation. This is the coordinator's option 1 for the
  50-source budget gap. It adds `scripts/calibrate_graph_tariff.py` and the contract's "Tariff" paragraph.

## Diagnosis

The traced key is `(Affirms claim1)`: KE's three-atom KB, k=800, About/Source/AtomicClaim positive-only, budget 1000.

- **Baseline.** The graph input of `(Affirms claim1)` is `conditional((And (A e) (B e)), [channel], ...)`, and
  the leaves plan a graph. Answers are .5/.5/.25 by `(node (conjunction observed (by channel cpu)))`.
- **With the generic rule added.**
  - The input is `unsupported` and the leaf plans are `none`, so the read returns `no-event-model` and the
    ordinary evaluator answers.
  - That evaluator has no route to the leaves. For the joint it inverts the channel with the c=0 prior, which
    gives .5.
- **Why the input is unsupported.**
  - `source_catalog_template` admits every forward producer whose conclusion matches the key, and one
    unsupported producer rejects the graph.
  - The generic rule's instance `(And (About claim1 (Ownership $a $b)) (Source claim1 OtherSource) ...)` is open,
    so it fails `ground(Parent)`.
  - Positive-only declarations were never consulted when producers were admitted.
- **Not the cause.** Sibling combination by base-rate odds and the choice of inversion act only after the graph
  has declined.
- **Master also breaks ground-parent inapplicable producers.** With a CTV variant the leaves are lost and the
  joint is .5. With a certain variant there are no answers at all.

## Rule the fix enforces

A producer takes part in a key's answer only if its antecedent can match. A non-negated positive-only conjunct,
ground or open, that no stored fact or assumption unifies with and no rule concludes makes the producer
inapplicable. A positive-only statement is only its stored instances.

- **User rates.** A user base rate reaches such a conjunct only through a live rule concluding it. This is
  checked: after `set-base-rate (Source $c OtherSource)` a `structural-source` application concludes
  `(Source claim1 OtherSource)`, so the producer is kept.
- **Lookups.** `positive-only-pattern?`, then `kb-facts` (the prefix-indexed unifying read), then keyed
  `context-leaves` (under an active context only ground conjuncts are judged), then `source_catalog_match` by
  conclusion prefix. There is no rule scan and no size constant. The check runs once per key and catalog
  generation.
- **Legitimate siblings are preserved.** Any producer whose positive-only conjuncts have a fact, an assumption or
  a concluding rule stays. So does any producer over other predicates, which read a population prior. Kept
  producers group and combine exactly as before.

## Tariff (option 1)

The old 1/256 was "the frozen design tariff": a guess. `scripts/calibrate_graph_tariff.py` runs a workload in
process with Prolog wraps.

- **Graph side:** CPU time inside `graph_moments`, and the ops `graph_take` paid.
- **Search side:** CPU time of the outermost `sk-walk!` and `sk-evaluate!` phases, less the graph work nested in
  them, and the steps debited from `sk_budget`.
- **Result:** ops per step = (search seconds per step) / (graph seconds per op).

One value per workload family that admits graphs:

| workload | graph µs/op | search ms/step | ops/step |
|---|---|---|---|
| KE capacity small (real-v2 1/10/25, boundary 3/6/9) | 2.28 | 3.86 | 1,695 |
| KE real-v2 50 sources (b20000, all graph work paid) | 0.86 | 5.88 | 6,835 |
| SupplyNet stage 1 b25 s2 | 2.70 | 2.54 | 940 |
| tests graph_folding | 0.96 | 10.86 | 11,288 |
| tests shared_parameters (#168) | 3.40 | 72.48 | 21,327 |
| tests certain_producer_families | 3.01 | 3.37 | 1,119 |
| tests event_dependence | 3.52 | 3.71 | 1,053 |
| tests atomic_posterior | 2.84 | 8.36 | 2,942 |
| tests soft_reports | 5.06 | 1.38 | 273 |

- **Value chosen.** The median is 1,695 and the spread is 273–21,327; I rounded to 1700.
- **Workloads that admit no graph.** SupplyNet stage 2 regions, stage 3 timed/untimed/soft/learned, and scale l
  and m.
- **Alternative measure, not used.** Counting evaluation units as well as steps gives a median of 940 (range
  180–9,869). The brief asked for per step.
- **Why the spread is wide.** Small graphs cost 2–5 µs per op against 0.9 µs for large ones, and row-heavy
  searches (shared_parameters: 24,650 evaluation units over 492 steps) cost more per step.
- **What it means for the 50-source KB.** The old tariff billed it 25–33× its CPU time.
- **Re-measuring.** The contract doc records how to re-run the measurement.

## Gates (final commit 10ca38d3)

- **`scripts/verify.sh`:** PASS, all 7 gates (Python 4,415 query rows, 0 aborts). Verify cache key 645a3b914538.
- **`compare.sh master --quick`:** PASS, accuracy changed in 0 cases
  (`bench/results/compare/d6207b87_vs_10ca38d3_quick/report.md`).
- **`compare.sh master --full`:** PASS, accuracy changed in 0 cases
  (`bench/results/compare/d6207b87_vs_10ca38d3_full/report.md`).
- **`compare.sh anchor --canary`:** PASS (`bench/results/compare/anchor-b4065459_vs_10ca38d3_canary/report.md`).
  Its 4 accuracy changes are against the anchor and identical on master: the candidate-versus-master pass
  executed 0 runs.
- **`compare.sh master --curves`:** identical error at every budget in all 9 curve cases (scale l/m, SupplyNet stage 3 timed/untimed/soft, stage 2 r10, conflict m, replay s3, minedsearch gated); times equal within noise (`bench/results/compare/d6207b87_vs_10ca38d3_curves/curves.md`). None of these cases pays graph work, so the tariff does not reach them.
- **KE `check_unrelated_source_rule.py`:** exit 0; the four controls equal baseline.
- **Reviewer `test_applicability.py`:** 10/10 OK.
- **Reviewer `test_ke_prefixes.py`:** it asks all four roots in one batched `query_many`, so one 1000-step budget
  and one 2,000-unit graph tier cover all four. Prefixes 1–36 answer exactly. At 37–50 the seven-part joint is
  now exact (.0078125, previously .5), but the leaves are not. All four 50-source graphs need about 8.25M ops
  against 3.4M in the tier.
- **KE's real query pattern.** KE's worker asks each query separately with the full step budget.
  - **At 1000 steps:** all 50 prefixes answer 4/4, cold and warm, exact at 1e-6 (.5, .5, .25, 1/128).
  - **At 200 steps:** prefixes 1–36 answer 4/4. Prefixes 37–50 answer 1/4, the seven-part joint at the coarse .5
    fallback. This is bounded behaviour, accepted for this round.

## Tokens (o200k)

- **Core:** +226 (`source_catalog.pl` +200, `event_graph.pl` +26). No estimate was recorded before coding, which
  breaks the protocol. The estimate recorded afterwards was +190 for the item-1 generalisation; the tariff was
  estimated at about 0 core.
- **Other:** contract doc +371, `scripts/calibrate_graph_tariff.py` +1,476, test +1,152.

## Moved test values

None.

## Limits

- At 200 steps, prefixes 37–50 answer 1/4 (listed above). A cheaper second-moment step (option 2) and a leaf
  fallback route (option 3) are deferred to the routedel2/elimination design. Pairing is 94% of the 50-source
  leaf's graph cost.
- In a single batched query of all four roots, the 50-source leaves need about 2,430 steps.
- The tariff is a median over a wide spread. Graph work in row-heavy or small-graph workloads is still billed
  differently from its time.
- An applicable producer with an open antecedent, or two uncertain applicable producers, still takes a key out of
  the graph (master behaviour, unchanged).
- I did not run the fuzzer separately; the verify gate's quick seed-1 fuzzer passed.
