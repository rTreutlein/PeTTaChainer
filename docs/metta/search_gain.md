# Searching where the answer can still change

Status: not adopted, October 2026 (see Results; patch kept outside the repository).

## Problem

The walk is best-first by node score. A premise's score is its owner's
score times the rule's expected confidence, shared among the premises still
open (`sk-join-score`). The score says nothing about whether the premise
already has a value.

StationOps' actions in the belief knowledge base
(ChainerGame `docs/single_kb_actions.md`) show the cost. A decision query
reaches each incident's leak belief through a one-premise link, so the
belief's subtree keeps nearly the whole score. The facts the decision cannot
do without sit behind rules of five to seven premises:

| node head | score in the first action query |
|---|---|
| `LeakBelief` | 0.99 |
| `LeakPredicted` (inside the belief) | up to 0.988 |
| `OutcomeValue` | 0.49 |
| `ActionCost` | 0.25 |
| `Outcome` | 0.24 |
| `InspectionEligible` | 0.12 |

But the beliefs were answered by the shift's belief query. With budget 200,
about half of an action query's new expansions went into belief subtrees,
and with budget 50 the decisions did not complete at all.

A "settled" flag would stop that. It would also stop a later query with much
more budget from improving a belief, which can be worth it. Such a query
should get to the belief subtree, but after the work that has no value yet.

## Rule

A node's priority is what expanding it is worth: its score times what search
under it can still add to its value.

- **A node without a value: 1.** A non-ground node also counts as 1, since
  its search can find new instances. So does a computation.
- **A ground node whose key has a value: the confidence one more independent
  observation would add.** With the value's confidence c and its observation
  count n = c·k/(1−c), that is count-confidence(n + 1) − c, as
  `sk-fold-child-score` already ranks a base-rate fold's members. Another
  proof found by search revises the value much as one more observation does.

The factor is small for a confident value and never zero. With budget left
once everything valueless is expanded, the walk goes under answered nodes,
most uncertain first. A larger budget still extends the same order.

## Where

- The factor applies when a node is pushed onto the walk's frontier
  (`sk-push`), on the node's current value. A value found during the query
  lowers the priority of the node's later pushes.
- The stored score is unchanged: a child's score still comes from its
  owner's. Its children are reached only after the node is popped, so they
  follow it.
- Rows, budgets and the walk allowance are unchanged.

## Risks

- **Cost.** Each push of a ground node reads its key's value
  (`sk-key-value`, a cached merged value when one exists). Measure the
  query time per push.
- **Quality.** A query whose roots are already answered spends its budget
  differently: on the less certain parts first. Replayed grid, plain and
  distractor-chain games: Brier against compute must stay on or left of the
  current curve. The belief query is where most budget goes, so it decides
  the result.
- **Roots.** An answered root is discounted like any node. Roots of one
  query discounted alike keep their order. Between an answered root and an
  unanswered one, the unanswered goes first, which is intended.

## Evaluation

1. Unit test: a query with two premises, one answered with high
   confidence and one without a value, expands the valueless one first,
   and with enough budget expands under the answered one too.
2. Full suite.
3. Replayed slice grid (forward slice 50–150, query budget 50/200, 8 seeds,
   plain and distractor chains) against the current results.
4. Live single-knowledge-base actions (ChainerGame `single-kb-actions`): the
   action budget at which decisions match the reference, and the compute per
   game against the separate knowledge bases (42 s, 4 seeds).

## Results

Built as above. The unit test behaved as designed: with (A x) answered by a
forward run, budget 3 proved (G x) through the unexplored B and C where the
old order spent budgets 2 to 6 refining A, and budget 16 refined A as well.
It also changed `test_best_first_runtime.metta`'s incumbent case: refining
an answered B whose subtree held a certain fact gave confidence 0.990 at
budget 2; the new order took the unanswered D first and gave 0.904.

Replayed StationOps, 8 seeds, share 1 (Brier, compute per seed):

| slice, q | plain, before | plain, gain | distractor, before | distractor, gain |
|---|---|---|---|---|
| 50, q50 | 0.0607 (8.6 s) | 0.0717 (9.0 s) | 0.0617 (9.3 s) | 0.0713 (9.1 s) |
| 50, q200 | 0.0594 (11.8 s) | 0.0647 (13.5 s) | 0.0594 (13.3 s) | 0.0646 (15.6 s) |
| 100, q50 | 0.0605 (9.2 s) | 0.0603 (10.8 s) | 0.0610 (10.4 s) | 0.0715 (9.8 s) |
| 150, q50 | 0.0590 (11.2 s) | 0.0592 (12.2 s) | 0.0609 (12.3 s) | 0.0700 (11.2 s) |
| 150, q200 | 0.0590 (13.2 s) | 0.0593 (16.9 s) | 0.0593 (14.8 s) | 0.0642 (15.6 s) |

Worse in nearly every cell, and slower. Most belief keys a query reaches
already have a value: a forward run's, or an earlier shift's. One more
observation's worth of confidence is far smaller than what refining them
actually gains (shortfall posteriors, refined rules, newly revised
evidence), so the beliefs' own refinement was starved. Whether a value can
still change is not visible from its confidence alone; the incumbent test
shows the same from the other side.
