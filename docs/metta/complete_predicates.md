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
pinned false, proof `unfounded`. The pin is a hypothesis that cuts the
circular support, not an observation of G: an inversion or a completion
that reads G under the pin as the consequence it inverts gives nothing
(`sk-observation-prior`). Reading it as one had a chain A -> B -> C over
complete B and C answer 0.054 for C where the exact value is 0.2195, and
drove loops with soft roots to about 1e-6. Nested reads pin each reading
conclusion in turn, so the recursion follows the cycle once and ends at the
first pinned statement. A complete K whose settled search found no rule application (no
rule concludes it, or every rule's conditions failed) is false:
`(STV 0.0 1.0)`, proof `unfounded`. A root reads such a K that way too.

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
context, or in an Assuming query's context, is therefore answered by its own
key when its node is expanded. That
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
  premise. Inversions and projections concluding it are judged as before. A
  complete premise supports any reader in the dormancy analysis: once its
  search settles it has a value, if only unfounded, even when its only
  derivations loop back to it. Reading the loop as no support put a rule
  outside the loop to sleep: `D <- C` over `B <- (Or A C)`, `C <- B` with A
  soft answered nothing for D (fuzzer seed 14000155).
- Conditioning. A closed value whose evidence overlaps uncertain evidence the
  row already read (a soft fact both derive from) conditions on it like any
  other premise value; before, it was refused and an `And` loop over a soft
  root had no answer.
- Merging. A closed value has the evidence of the recomputed rows and depends
  on K and the pinned statements; the reader's view merges as any other.
- Observations inside a loop. A rule application of a complete G may read a
  certain fact of a complete K as a premise (a cause of G) that an inversion
  or completion onto G observes as G's effect: K is both only in a loop
  through G. The merge compares the rule application's evidence without K
  (`sk-update-evidence`), so the two combine by Bayes' rule, the forward view
  in the base rate's place: a false disjunct adds nothing to the rule's other
  causes, and a true one is explained only through G. In `C <- (Or B D)`,
  `D <- C` with B = 1 and D = 0, C is 0.47 · 0.06 / (0.47 · 0.06 + 0.53) =
  0.0505, exact; before, the forward view's evidence contained the
  inversion's and 0.47 was kept (`test_problog_fuzz_regressions.metta`, F5).
  Outside complete predicates the premise stays shared: a symmetric rule and
  its own completion read the same fact twice.
- Forward chaining. Forward rows are evaluated like any row, so they read
  closed values where a query settled the statement's search; a forward run
  expands no node and settles nothing itself.
- Partial folds and base rates. Folds read their members' stored values; a
  closed value is a read-time conclusion of rule applications and roots, and
  folds do not see it (out of scope).
- Assuming and implication queries. An Assuming query's context holds the
  world's facts and rules with its assumptions, so its statements are
  complete as the main context's are: a decision that does not assume a
  complete statement reads it false once its search there settles. An
  implication query's hypothetical contexts see none of the world, and the
  predicate is open there.
- Hypothesis and refined rules. A rule application concluding a complete
  predicate is one more way it becomes true, read like any rule.

## Not built

- Settling by a closed value: an `And` with a closed-false part and an unknown
  other part waits for the other part, though it is false.
- Re-reading a closed read the search later settles without any row change:
  a reader refused because K was unsettled is computed again when K's rows
  change, as is usual after more search.

## Result

`tests/metta/test_complete_predicates.metta`: the loop above as P and M, with
P and M complete. No stock: P and M 0. Stock 0.9: P 0.9, M 0.9; with
P(degraded) 0.3, P 0.9 and M 0.63. Stock: 1. Undeclared, or with the stock
an open statement with no fact: no answer. A chain whose proof the budget
has not reached: no answer at budgets 1 and 2, true at 3.

Against master 28473546, run concurrently. SupplyNet stage 3, untimed,
seeds 1–4, budget 100, 30 rounds, with `Producing`, `Fuelled`, `FuelArrived`
declared complete (ChainerGame branch supply-complete-predicates): error
0.062 → 0.017, coverage 0.91 → 1.00, production without stock 0.331 → 0.000
(answered 34% → 100%), Brier 0.163 → 0.140 (exact posterior 0.135), time
+6%. Timed seed 1 and stage 2 seed 1, which have no loop: identical, time
+1%. StationOps temporal replay, seeds 2 and 3 at budgets 25 and 50, no
declarations: beliefs identical, time +0–2%.
