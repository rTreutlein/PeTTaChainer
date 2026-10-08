# Partial folds

Status: built, October 2026.

## Problem

An exact fold — `FoldAll`, `FoldAllValue`, `FoldAllTruth` — is a function of
all its members: a sum, a list, the candidates a posterior is computed over.
The evaluation read such a fold as complete whatever its search had reached:
a fold whose node no search had expanded was the empty fold, and a fold over
some members was the fold over those. A rule reading it stated its conclusion
with the rule's confidence. With StationOps' shortfall posterior (a
`FoldAllTruth` over a shortfall's candidates feeding a weighted-subset
posterior) a fold over too few candidates said with confidence near 1 that a
leak the shortfall had confirmed was absent. And since the rule's view reads
the leak belief the plain view reads, and more, it was kept over that view by
evidence containment: a larger budget, reaching the fold but not all its
members, made the answer worse than a smaller one that never reached it.

## What incomplete means

A fold covers the members its search found that have a value. Members still
to come are:

- members found without a value whose key still has a row that is stale,
  never computed, or waiting for conditioning (a row computed that derived
  nothing records empty support, so a member that cannot be derived is no
  member and is not waited for);
- at least one more while a premise of the member node's joins has no answer
  yet and its search can still give one: the premise node, or a node below
  it, is unexpanded or has work waiting at it (parked deliveries, deferred
  joins or rows). A premise whose search ended without an answer brings no
  member. Premises are not counted one by one: rule variants (settled
  variants, other premise orders) wait on overlapping premises, an open
  `(Leak $v)` beside the ground `(Leak u1)`, so a premise is not a member.
  The count of members to come is therefore a lower bound and the share an
  upper bound until the search ends.

A fold whose node no search expanded, or whose member node is unexpanded, has
covered nothing: how many members it has is not known.

All of it is read off state the skeleton keeps (answers, values, row marks,
child links); the walk below an unanswered premise stops at the first
unexpanded node and visits each node once.

Statistical folds are not read for completeness: base rates, implication
instance folds and priors estimate from a sample, and their confidence already
counts the members they took. An existential disjunction (`OrFormula` fold)
bounds its witnesses and is left to the connective rules.

## Rule

An incomplete fold keeps the value over the members it covered and proves by
`(partial-fold covered total proof)`; `total` is covered plus the members
still to come, 0 when nothing is known. A conclusion a row draws from
incomplete folds has its confidence multiplied by the share each covered,
covered/total (0 for a fold that covered nothing). A complete fold changes
nothing.

A value that depends on an incomplete fold is provisional: it was computed
from part of an aggregate that needs all of it, so its strength is not an
estimate of the conclusion, only a placeholder. A key merges its provisional
values only when it has no other value. Dependency sets are transitive, so
this holds for values derived from a provisional one too.

An incomplete fold that a query needs is checked again at each evaluation:
its members may have been searched, computed, or found to derive nothing
since, and none of these necessarily changes a member's value. When its
coverage or value changed, its readers recompute.

So:

- with no budget, a fold claims nothing (confidence 0), and a key with any
  other view answers with that view;
- with some budget, a fold over part of its members says how much it covered,
  in its proof and in its conclusion's confidence, and gives way to complete
  views;
- with enough budget, the fold is complete and its conclusion is what it was
  before.

A larger budget extends the same search prefix, so coverage only grows, and
the answer moves from the views that do not need the fold to the fold's
conclusion, never through a confident value over part of the members.

Alternatives considered:

- A fold with no value until complete (its readers derive nothing). Sound,
  but a key whose only view is through the fold has no answer at all, and the
  fold's partial work is invisible.
- Discounting the fold premise's truth value, `(STV 1 coverage)` in place of
  the compiled `(STV 1.0 1.0)`. The variance-based formulas give a strength
  of 1 almost no variance whatever its confidence, so the conclusion's
  confidence barely moves. The discount has to apply to the conclusion.
- Discounting confidence alone. The strength stays the placeholder's, and the
  containment rule keeps it over a complete view it contains: the budget
  non-monotonicity above remains.
- Imputing members still to come (at a prior). It needs their identity and a
  prior for an arbitrary member pattern; neither is available in general.

## Worked example

`tests/metta/test_partial_folds.metta`. Five candidates u1..u5; the leak of
u1 is derived by one rule from a fact, of u2 by two, u3 three, u4 four, each
with strength 0.4; u5 has no derivation. `total` sums the candidates' leak
strengths, `(CTV (STV $sum 1) (STV $sum 1))`.

| budget | fold proof | Total u1 |
|---|---|---|
| 1 | `(partial-fold 0 0 cpu)`: fold not searched | (0.0, 0.0) |
| 4 | `(partial-fold 1 2 …)`: u1; the search for more goes on | (0.4, 0.5) |
| 16 | `(partial-fold 2 3 …)` | (0.8, 0.667) |
| 200 | `(foldall-proof …)` over u1–u4; u5's search ended | (1.6, 0.9999) |

Before, budgets 1 to 3 answered (0.0, 0.9999) and budget 4 (0.4, 0.9999).

With a second, complete view of the statement (`prior: (Cand $u) -> (Total
$u)` at 0.5, and the fold rule reading `(Extra $u)` too, so its evidence
strictly contains the prior view's), budget 4 answers the prior view, 0.5;
before, the unsearched fold's conclusion, (0.0, 0.9999), won by containment.
At 200 the complete fold's conclusion, 0.8, is kept as before.

## Measurements

StationOps (temporal model, 10 modules, 20 shifts, budget 50) and SupplyNet
(stages 1–2, budget 100) are unchanged or nearly so: in StationOps every
shortfall fold is complete when its posterior is finally read, even at
budget 5. Each fold's first computation comes before its members' (rows are
computed in creation order, and the reader row is created before the member
rows), so it sees every member without a value; that transient view is now
provisional with confidence 0 instead of a confident posterior over no
candidates, and is replaced within the same evaluation. The confident
partial reads reported earlier came from evaluation allowance spent on
antecedent completions that are now pruned
(`prior_factored_merge.md`, "Antecedent completions").

Against 07e829a7, run concurrently: StationOps replay Brier 0.0444 / 0.0599 /
0.0642 / 0.0714 (master 0.0444 / 0.0597 / 0.0642 / 0.0714), live regret
604.4 / 86.4 / 197.4 / 70.5 (identical), query time within 2%. SupplyNet
stages 1 and 2 identical. Over diagnosis budgets 5 to 100 (seeds 2 and 3),
replay is identical but for the fourth decimal; live play is equal or better
in every cell (seed 3 at budgets 5 and 10: regret 159.3 to 52.3).
