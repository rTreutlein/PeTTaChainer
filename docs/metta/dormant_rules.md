# Dormant rules

Status: built, October 2026.

## Problem

A rule whose premise can only be proved through the rule's own conclusion,
the same instance of it, produces nothing a reader can use: every value of
that premise depends on the conclusion's key, so self-support exclusion
drops it. The chainer still starts the rule, joins it, evaluates its rows
and only then excludes the result.

StationOps with never-queried consequence chains (`--distractor-chains 4
--distractor-chain-length 3`: rules `SealLeak → Consequence_i_1 → … →
Consequence_i_3`) shows the cost. The compiler inverts every implication, so
`Consequence_i_1 → SealLeak` exists. No `Consequence` predicate has a stored
fact; its only evidence is derived from `SealLeak` itself. A query for
`SealLeak(c t u)` still starts the inverted rule, needs `Consequence_i_1(c t
u)`, starts the inversion of the next link, and so on. Seed 1, 5 shifts, 10
modules: 4,524 rows against 2,429 without chains, `SealLeak` rows 670
against 310; over 8 seeds and 20 shifts queries take 92% longer and memory
more than doubles, for identical answers.

The rule involved is an inversion here, but the condition is about rules,
not inversions: any rule can have a premise that only its own conclusion
supports.

## Rule

A rule R with conclusion C and premise P is **dormant** when every way to
prove P, other than a stored fact, passes through C with the same arguments:
the instance of C the rule would conclude. A rule is dormant if any of its
statement premises is; a dormant rule is not started.

The condition is per instance, not per predicate. Recursion through the same
predicate at another instance is legitimate:

- `Consequence_i_1(c t u)` is derived only from `SealLeak(c t u)`; the rule
  `Consequence_i_1(c t u) → SealLeak(c t u)` can only support itself: dormant.
- In the temporal model `SealLeak(u)` reads `LeakPredicted(u)`, which reads
  `SealLeakAtShiftEnd(p)` with `NextState(p u)`, which reads `SealLeak(p)`:
  the same predicate, another instance (`p`, not `u`): active.
- `Path(a b) ∧ Edge(b c) → Path(a c)`: the premise `Path(a b)` is another
  instance of the conclusion `Path(a c)`, and `Edge` has facts: active.

## Analysis

For a rule R (conclusion C, premise P, sharing variables) the analysis
searches backward from P over the rules and the stored facts, as a query
would, but on patterns rather than on facts:

- P is **supported** if a stored fact unifies with it (`kb-facts`), or a rule
  whose conclusion unifies with P has every statement premise supported, after
  that unification.
- A pattern that is the forbidden instance, C with R's own variables (a
  variant of C under the bindings shared with P), is not supported by that
  branch.
- A settled rule (one part of a compound, `connective_settling.md`)
  supports its conclusion only through a certain stored fact that settles
  the compound: its part's formulas are run on such a fact up to the
  settling check. The settled join reads nothing else, so counting its part
  as supported by rules would wake rules that can only support themselves
  (StationOps: the persistence rule's variant settled by `NextState`, whose
  facts are all true, woke the inverted persistence rules and cost the replay
  0.02 Brier at budget 25).
- Computed premises (`CPU`) and fold premises count as supported: a fold
  always has a value, and a computation has no evidence to loop on.
- Only what the search fully sees is judged: user predicates in the main
  context, or a context the rule leaves open. A premise in an assumption
  context (the query-local rules of total implications) is supplied by its
  assumptions, and the chainer's own vocabulary (`Inheritance`,
  member and implication samples, `RuleTruth`, implications and connectives)
  has support the search does not model: rules installed when a node expands,
  member folds. Such premises count as supported. (A first version judged
  them and put the `smokes` example's inheritance-lift rules to sleep,
  changing its answer from 0.420 to 0.380.)
- Patterns already on the search path are not supported by that branch
  (recursion), and patterns already decided are memoized by variant.
- The search is bounded (depth and patterns visited). When the bound is
  reached, the premise counts as supported. So the analysis can only miss a
  dormant rule; it never puts a useful one to sleep.

The analysis works on the rule's own patterns, so its answer holds for every
MAIN node the rule is started on. A node that binds the rule's variables can only
make fewer facts unify, so a rule active in general may be useless for a
particular node; that is left to self-support exclusion, as today.

Private implication judgment contexts bypass this MAIN verdict, as Assuming
searches already do. Contextualizing a producer can redirect a MAIN premise to
an assumed key, supplying support absent from the rule's original patterns.
Reusing a cached dormant verdict there loses valid hypothetical proofs after
earlier queries (KE issue 61). These contexts still use ordinary self-support
exclusion; the fix adds no cache reset or invalidation.

## Correctness

If every proof of P passes through the instance C of R's conclusion, every
value of P depends on C's key. A row of R reads P excluding the views that
depend on its own key, so it never admits one, and R yields nothing for C.
Not starting R changes no answer; it removes the work. The same holds for a
forward run, which starts joins upward from the keys it takes
(`sk-forward-start-step`): a dormant rule is not started there either.

## Changes over time

Facts and rules arrive while the chainer runs, and either can give P support
it did not have.

- The analysis is computed when a rule is first matched and memoized per
  rule.
- A dormant rule records the predicate heads of the patterns its search found
  no support for. A new fact or rule with one of those heads clears the memo
  of the rules waiting on it and schedules them through the existing
  pending-rule activation (`&sk_pending_rules`, `sk-activate-rule-step`),
  which starts a rule on the expanded nodes it matches. A rule woken this way
  is analysed again when next matched.
- A new permanent rule drops every verdict, since it can also give a rule
  that had support a path back to its own conclusion. A query's own rule
  (an `Assuming` or implication query's) wakes only by its conclusion's head,
  as a fact does: it leaves with the query, and dropping every verdict would
  make each such query judge every rule again over a growing store.

## Where it applies

`sk-start-rule-step` (node expansion and pending-rule activation) and
`sk-forward-start-step` (forward runs) skip a dormant rule. Nothing else
changes: compilation, the rules space and self-support exclusion stay as
they are.

## Evaluation

- Unit tests: the consequence chain (no rows for the inverted links, the
  same answers); the temporal chain of `test_instance_prior` and the
  transitive `Path` rules stay active; a fact added later for a consequence
  predicate wakes the rule and its answers appear.
- StationOps, 8 seeds, 10 modules, 20 shifts: answers identical with and
  without dormancy, on the plain game and with consequence chains; query
  time and memory with chains back near the plain game's. Forward runs still
  derive the consequences, which is what forward chaining is for.

## Result

StationOps, 8 seeds, 10 modules, 20 shifts, replaying the same recorded
inspections and repairs (ChainerGame `--replay`), so belief quality is
comparable across settings. Grid over forward steps per fact (0.25 to 2)
and query budget (50 to 300); compute is forward plus query time per seed.

| | head | dormancy |
|---|---|---|
| best Brier within 12 s | 0.0861 | 0.0728 |
| best Brier within 16 s | 0.0615 | 0.0602 |
| f 2, q 50 | 0.0861 @ 9.6 s | 0.0607 @ 14.0 s |
| f 0.5, q 300 | 0.0607 @ 24.1 s | 0.0655 @ 14.5 s |
| plateau | 0.0591 @ 18.6 s | 0.0599 @ 16.3 s |

Nearly every setting costs less, and the curve moves left in the middle of
the range. The plateau is 0.0008 higher, and low forward with a high query
budget is worse: base rates count derived members only when something
happens to read them, and dormant rules no longer read some of them. That is
a defect of base-rate refresh, not of dormancy (see
`base_rate_refresh.md`).
