# Master round: settled-step dominance (#106 batch loss), Nov 5

Branch `master-dominance`, worktree `.claude/worktrees/master-dominance`, from master `bdae8d7e`.

## Commits

- `191dc3c2` Let a settled step stand for the complete step it settles (one-line rule change, comments, docs, tests).
- report commit (this file).

## Diagnosis

`diag-ancestor-batch.md`: with an ancestor root in the batch, `FuelArrived t18` is answered before the plant's first
production row. `Or(StockedFuel, FuelArrived)` then has a complete view `(conjunction stock arrival)` and a settled
view `(settled stock)`, both `(STV 1 1)`. `proof-dominates?` let the complete step dominate the settled one
(`settled-within? $prf-b $prf-a`), so the selected support carried the mine's production history through
arrival, the production row clashed with its degradation premise, and conditioning spent the budget: the mine
read its population prior (.267), plant-a had no answer.

## Design

One rule: `proof-dominates?` now reads `settled-within? $prf-a $prf-b`. A settled step dominates the complete step it
settles, in both places that use the relation (standing selection `sk-gives-way-step`, pair merge `sk-pair-facts`).
They still never revise with each other. Both have the same value by construction: settling needs a certain stored
part at the absorbing value, and `AndFormula`/`OrFormula` are exact there (`connective_settling.md`). Joint-row dominance is
unchanged. I did not add a value-equality check: equal statement and context come from the key, and equal value
comes from the construction. Core net lines: 0 (+13/-13, comments included).

Rejected: making joint rows also dominate settled steps. That would let a larger proof suppress a sufficient
smaller one again.

## Reproducers (scratch/repro/replay.py, ops 106-timed-b400-ops.json, selected op replaced)

| case | master pair | candidate pair b400 = b4000 = single = sequential | master single | reference |
|---|---|---|---|---|
| mine t18 | prior .26667 | .9499997165502357 c .99995 | .95 c .99999994 | .9499983311 |
| plant-a t16 | no answer | .864999088336457 c .56765 | .8649995644 | .87335 |

Ancestor answers: Storm t17 .275416 -> .246736; Storm t15 .390304 -> .396680.

## Gates

`scripts/verify.sh`: PASS (all 7 gates, fuzzer gate included), recorded under key fb0526a0df56.

## Benchmarks

- `--full` vs bdae8d7e: **REGRESSIONS (1): supplynet stage 3 timed b100 s3 degraded error 0.003897 -> 0.008598**.
  Accuracy changed in 8 cases. All other changes are improvements: timed b25 error .004467->.003820, b50 .001985->.001339,
  b100 overall .001422->.001339 (blocked/storm/producing kinds to ~0), soft0.9 timed .020086->.014541 (coverage
  .9752->.9826), soft0.9 untimed .019054->.018938, learned s1/s2 slightly better. The timing flag did not repeat on
  rerun. Report: bench/results/compare/bdae8d7e_vs_191dc3c2_full/report.md.
- Canary: PASS (bench/results/compare/anchor-b4065459_vs_191dc3c2_canary/report.md).

### The flagged case comes from a stale-root bug that master already has

Rounds 6-8, `Degraded plant-a t6..t8`: master .4132 (exact) vs candidate .2642 at round 6. Replaying the recorded
master run (scratch/repro/record.py and replay2.py; op 78, a single root) reproduces it. The candidate keeps the
persistence chain from h30 and ignores the late observations t1=0 and t2=1. Querying `Degraded plant-a t2` first
gives the exact .4132 on the candidate too.

Minimal reproducer, failing on master (scratch/repro/chain2.py): persistence chain t0..t6. Query t1..t6 as roots,
then add a certain fact at t2 and query t6 again. Both builds keep .26417, even at 1000 steps; exact .41322. With
3 hops between the fact and the root it refreshes; with 4 or more it does not. If the intermediate keys were never
roots, it refreshes. On master, SupplyNet happened to refresh the key through the complete `runs-plant-a` step,
which reads the `Degraded` key. The settled step reads the certain stored fact at join time instead. This is a
separate mechanism (late-fact refresh depth) and needs its own round, or the flag accepted.

## Reviewer tests (master-dominance-review, run on this worktree)

Supplemental: 12/12 pass. Main suite: 10 of 11 methods pass, including the 16 native dominance cases, all invariants
(neutral, relevant flip/no hidden evidence, rename/reorder/repeat, batch = sequential both orders, budget
monotone, budget 0) and replay batch = sequential. The 4 failures are all the supplied-reference subcases: mine
1.39e-6 against a 1e-6 tolerance, plant-a .00835. Master fails them too (1.67e-6 and .00835; the reviewer's
inherited finding 2). Log: scratch/review/tests.log.

## Moved test values

Proof-shape pins with unchanged truth values now show `(settled ...)`:
- test_complete_predicates actKb Assuming S: `(conjunction (ctx proof 1) f)` -> `(settled (ctx proof 1))`;
- test_problog_fuzz_regressions F5 `(conjunction obs-B-a obs-D-a)` -> `(settled obs-B-a)`; f8settled
  `(conjunction obs-B-a (by rF obs-E-a))` -> `(settled obs-B-a)`;
- test_certain_observation_overlap: with stock, the block was no longer read and the test's `blocked19` pin failed.
  The test now has no stock and a producing mine, so fuel goes through the block. It is exact by enumeration:
  D18 1 -> .989579812386961, D19 1, D20 .75. It passes on master and on the candidate.

New tests: test_connective_settling knownKb (settled proof kept, no conditioning; a relevant flip moves C to .58),
test_proof_semantics test_settled_step_stands_for_its_complete_step (native support reproducer; fails on master).

## Limits

- The supplied references are not reached: mine is 1.4e-6 above .9499983, and plant-a .865 is .0083 below .87335.
  This is the authored-soft gap the diagnosis calls separate, and master's singles show it too.
- Single-root controls moved slightly: mine .95 -> .9499997 (closer to the reference), plant-a -5e-7. The rule
  now applies through the whole history, not only at the selected operation as in the diagnostic wrapper.
- The b76000 stack overflow is not addressed (it is out of scope).
- The stale-root bug above is inherited and not fixed.
