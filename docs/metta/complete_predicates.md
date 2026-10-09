# Complete predicates

Status: built, October 2026.

## Problem

The chainer is open-world: a statement with no proof is unknown. SupplyNet
stage 3, untimed cycle, has certain rules within one period:

```
(Producing power $t) <- (And (Fuelled power $t) (Not (Degraded power $t)))
(Fuelled power $t)   <- (Or (StockedFuel $t) (FuelArrived $t))
(FuelArrived $t)     <- (And (Producing mine $t) (Not (Blocked fuel $t)))
(Producing mine $t)  <- (And (Producing power $t) (Not (Degraded mine $t)))
```

Without stock nothing runs (the least fixed point, exact P = 0). Cycle
exclusion rightly refuses the loop's proof of itself, and then there is no
answer at all: the loop disjunct `FuelArrived` has no proof, so the `Or` and
everything after it waits. With an uncertain stock (0.9) the same happens,
though production is 0.9 times P(not degraded). Connective settling
(`connective_settling.md`) answers only where a certain part decides.

## Declaration

`(set-complete-predicate $kb $head)` declares that the rules and facts of the
predicate `$head` in `$kb` are the only ways a statement of it becomes true:
Clark's completion of the predicate. Nothing changes for a predicate not
declared. Declarations are made before knowledge is added, like
`set-rule-refinement`; Python: `PeTTaChainer.set_complete_predicate(head)`,
which timed subprocess queries replay.

## Rule

A statement of a complete predicate is read closed by a rule application that
concludes a statement of a complete predicate: its derivations that run
through the reader's own conclusion are circular, and they contribute
nothing, so the statement's value for that reader is its value with the
reader's conclusion taken false. That is the well-founded reading of the
loop: a set of statements that only support one another (an unfounded set) is
false, and what a statement gets from outside the set is kept.

Concretely, when a rule application R concluding a complete G reads a
complete K and finds no view of K it may read (every one depends on G, or K
has none yet), K is read as the merge of its rows evaluated again with G
pinned false, proof `unfounded`. Nested reads pin each reading conclusion in
turn, so the recursion follows the cycle once and ends at the first pinned
statement. A complete K with no rows at all, whose search is settled, is
false: `(STV 0.0 1.0)`, proof `unfounded`. A root reads such a K that way too.

So, for the loop above with `(StockedFuel t)` at 0.9 and nothing degraded:
`Fuelled` reads `FuelArrived` with `Fuelled` pinned false, which is the mine's
production with the plant's pinned false, 0: `Fuelled` is
`OrFormula(0.9, 0)` = 0.9, and the mine runs with 0.9. With no stock, all are
0; with stock, 1.

Why pinning and not a flat 0: a row can combine a circular part with a
non-circular one (the `Or` above). Read by the mine, the plant's value with
the mine pinned false is the stock's 0.9, while a flat 0 for every statement
whose views the reader excludes would conclude 0 for the mine whenever the
mine's row was computed before the plant's.

Only complete statements are pinned. An open statement in the loop could be
true for reasons the KB does not hold, so the loop's remainder through it is
unknown, not 0, and a closed read never pins it: a complete statement whose
only support runs through an open one has no value for that reader.

## When the reading is definitive

A closed read never concludes from a search the budget cut short. K's search
is **settled** when:

- K's general node (open proof and truth value) is expanded, so every rule
  concluding K was started (rule applications concluding a complete
  predicate are never dormant and never pruned by the start prefilter, so
  none is skipped); and
- no join of a rule application owned by that node waits on a premise without
  a delivered answer (no answer yet, or a delivery parked or queued), and the
  node has no deferred joins or rows.

A join waiting on a premise not yet expanded, or on an open statement with no
proof, is a derivation not yet examined or unknown, so K is not settled and
the reader gets nothing (unknown), as before. Only rule applications
(`(by ...)` proofs) count: inversions, completions and projections are
evidence, not ways K becomes true, and their pending joins do not keep K
unsettled. The check reads the node's children and the joins waiting on them:
local, constant in the size of the knowledge base.

Joins must reach K for its search to settle: a join waits until its premise
node answers, and a complete statement with no fact would never answer, so
the loop would build no rows at all. A ground complete statement in the main
context is therefore answered by its own key when its node is expanded. That
answer claims no value; it lets the joins reading the statement build their
rows, whose values the reading above decides.

Rows recomputed under pins are not stored; a closed reader stays a reader of
K, and is scheduled again when K's rows change even when the new view depends
on the reader's own key (which an ordinary reader would not admit), and when
a new or forced row of K derives nothing (under the pin it may derive
something). A closed read costs one evaluation of each of K's rows, and a
nested read one more per statement of the cycle it follows, so a loop of n
statements costs n row evaluations per read; rows with several complete
premises in the same cycle multiply that.

## Interactions

- Stored facts. A complete statement with a stored fact has a value; it is
  read as usual. A certain stored fact applies no rules, as before.
- Settling. A settled join reads a part only through a certain stored fact,
  so a closed value never settles a compound; the complete row reads it.
- Dormancy, prefilter. A rule application concluding a complete predicate
  is never dormant and never pruned before it starts: its join is how a
  closed read sees that a derivation exists, or that one waits on an unknown
  premise. Inversions and projections concluding it are judged as before.
- Merging. A closed value has the evidence of the recomputed rows and depends
  on K and the pinned statements; the reader's view merges as any other.
- Forward chaining. Forward rows are evaluated like any row, so they read
  closed values where a query settled the statement's search; a forward run
  expands no node and settles nothing itself.
- Partial folds and base rates. Folds read their members' stored values; a
  closed value is a read-time conclusion of rule applications and roots, and
  folds do not see it (out of scope).
- Assuming and implication queries. Only statements in the main context are
  complete; in a hypothetical context the predicate is open (out of scope).
  Premises an Assuming query reads in the main context are read closed there.
- Hypothesis and refined rules. A rule concluding a complete predicate is one
  more way it becomes true, read like any rule.

## Not built

- Settling by a closed value: an `And` with a closed-false part and an unknown
  other part waits for the other part, though it is false.
- Re-reading a closed read the search later settles without any row change:
  a reader refused because K was unsettled is computed again when K's rows
  change, as is usual after more search.
