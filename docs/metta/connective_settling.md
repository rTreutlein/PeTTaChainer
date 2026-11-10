# Connective settling

Status: built, October 2026.

## Problem

An `And` or `Or` premise is lowered into a join over all its parts, whose
truth values `AndFormula` / `OrFormula` combine. A join needs every premise
answered, so a part with no proof blocks the compound even when another part
decides it. SupplyNet stage 3, untimed cycle: the power plant is
`Fuelled ← (Or StockedFuel FuelArrived)`, and `FuelArrived` is the mine's
production, which needs the plant: the loop. Cycle exclusion rightly leaves
`FuelArrived` without a proof, so `Fuelled`, and all production below it, had
no answer even when the stock alone settles it (480 of 480 production queries
unanswered).

## Rule

A part known with certainty at its connective's absorbing value decides the
compound whatever the other parts are: a disjunct of `(STV 1 1)` makes an `Or`
`(STV 1 1)`; a conjunct of `(STV 0 1)` makes an `And` `(STV 0 1)`. In PLN
terms, `(Implication A (Or A B))` holds with certainty, and its other branch,
P(Or | not A), needs B; with A certain, modus ponens reads only the first
branch. Likewise `(Implication (Not A) (Not (And A B)))`.

The absorbing value is logic configuration
(`(set-compound-settling $head $value)`; PLN sets `And` and `Or`, predicate
logic sets `And`, its `Or` already being disjunction introduction).

## Construction

Settling depends on values, which a join does not see: a row is built from
its premise keys, and its value is computed later. So a settled compound is a
rule variant that reads only the settling part:

- `settled-reading` (`compiler/source_lowering.metta`) turns one part's
  bundle into the bundle of the compound: the part's goals, then
  `(CPU SettlesFormula ($tv value) value)`, which yields `value` when the part
  is certain at it and nothing otherwise. Its proof token is `(settled P)`.
- The variants are readings of a compound after the complete one
  (`compound-readings`, used by the producers of compound keys and by an
  assumed compound), and lowerings of an `And` antecedent after the complete
  one (`antecedent-lowerings`, each conjunct read as `lower` reads it, so
  `(Not X)` reads X and `NotFormula`, and a compound conjunct its key, which
  its producers settle). `compile-rule` compiles one forward rule per
  lowering. Inversion, completion and outputs use the complete antecedent
  only; `complete-lowering` reads a completion's siblings and consequence
  inline, a compound one through its complete reading.
- Variables absent from a settling part must be bound by its reader. The
  compiler retains those variables in a `vars-covered?` CPU guard, checked
  after the enclosing join or query has supplied its bindings. Rejecting the
  reading at compile time lost valid ground instances and existential joins
  (#154); fold abstraction of fixed arguments exposed the same bug (#151).
  An open reader still cannot enumerate an unconstrained variable's domain.
  A shortcut over a whole conjunctive rule antecedent still requires its part
  to bind every antecedent variable: it has no enclosing premise join to
  select the skipped relation's tuple, such as a temporal predecessor.
  The structural guard runs during application construction even on open
  arguments. Ordinary joins reject it before starting, and no failed guard
  produces a row that consumes numerical evaluation allowance.
- A part whose bundle already carries a ground value settles only with that
  value; so an `Or` settled inside an `And` does not yield dead rules.

A settled join reads a part only when a certain stored fact fixes its value
(`sk-settled-read?`, `skeleton.metta`): the value of a ground key with a
certain stored fact is that fact, so the join binds it, the part's formulas
(`NotFormula`, `SettlesFormula`) run when the join is built, and a part that
does not settle builds no row. Derived values never settle in practice:
modus ponens leaves confidence below 1 (0.9998 from a certain premise and a
certain rule). Building rows for every answered part instead cost budget and
belief quality: StationOps replay Brier 0.0444/0.0602/0.0640/0.0708 (master)
went to 0.0502/0.0574/0.0958/0.0727 at budget 50, identical at budget 200,
and SupplyNet timed stage 3 lost 2.6% of the unstocked production answers.
For the same reason a settled step drives no search of its own
(`term-confidence` scores `SettlesFormula` 0): it reads the nodes other
joins expand and the facts read at once.

`AndFormula` and `OrFormula` are exact on the same inputs: a certain-false
conjunct gives `(STV 0.0 1.0)` (before: confidence 0.99997 from the clipped
variance, and 0 when the other input had none), so the complete step and the
settled step agree.

## Interactions

- Merging. Both a settled view and the complete view of the same step can
  exist with the same absorbing value. Their evidence normally shows the
  complete one containing the settled one, but a known statement under a
  condition, or an assumption context, reads with no evidence, and the two
  would revise. So one gives way to the other before the views merge, and it
  is the complete step that gives way to the settled step deciding it
  (`proof-dominates?`, `settled-within?`): the complete step's other parts
  add evidence the value does not depend on, and a reader that also reads
  one of them would see the two overlap and condition on it for nothing.
  SupplyNet #106 (Nov 5): with `FuelArrived` answered, the complete
  `Or(StockedFuel, FuelArrived)` step carried the mine's production history
  into the plant's production row, which clashed with its degradation
  premise and spent a two-root batch's whole budget on conditioning, so the
  mine read its population prior (.267) where it reads .95 alone; with the
  settled step kept, both read .95, at b400 and b4000.
- Self-support. A settled row depends on its part's key only; cycle
  exclusion applies to it as to any row. Settling to true needs a certain
  part, so a loop disjunct cannot settle its own Or: without stock, nothing
  outside the cycle proves the plant running, and there is no answer (the
  open-world reading; declaring the cycle's predicates complete gives the
  closed-world answer, not running: `complete_predicates.md`). A degraded mine settles its `And` false and breaks
  the loop: then production is answered false.
- Expected confidence. `premises-expected-confidence` matched "a formula whose
  result modus ponens reads next" by unification, which bound the rule's CTV
  to a settled ground value; it now compares by identity.
- Projections. A settled `Or` key gives its other disjunct no value: P(B) is
  undetermined when A is certain, and the compound's event node (like a false
  conjunct's) yields no message where the other atoms settle it whatever the
  part is (`settled_by_siblings`, `runtime_helpers.pl`), rather than a value
  of confidence 0, which would have replaced what else is known of B (a
  fuzzer repro answered 0 for a disjunct whose population prior is 0.73). The
  same holds for a stored certain `Or` with a certain disjunct.
- Dormancy. The dormancy analysis mirrors the settled join: a settled rule
  supports its conclusion only through a certain stored fact that settles
  the compound (`dormancy_settles`, `runtime_helpers.pl`). Counting it as an
  ordinary rule made `LeakPredicted` look supported by `NextState` alone in
  StationOps, which woke the inverted persistence rules: their expansions
  took the small budget from the instance priors (replay Brier at budget 25,
  seeds 2 and 3: 0.0583 -> 0.0782, 0.0649 -> 0.0862).
- The prior-factored merge needs nothing: a certain view is not an inversion
  over a prior.

## Bounds for stored reports (#183, November 10)

An uncertain part gives only a bound, P(A or B) >= P(A), P(A and B) <= P(A).
One STV cannot carry an interval; reading the unproved part as its base rate
would turn every partly known compound into an answer whose strength the
population decides, and in the untimed cycle the loop disjunct's base rate
would make a plant without stock run with the population's rate (SupplyNet's
exact answer is 0). So only certainty settles an unreported compound through this shortcut.
A stored compound uses its ordinary source merge and now installs a separate
partial producer at ingestion. Its unknown parts carry [0,1], and its known
parts read independently of that compound. It reads the connective interval
at its midpoint with confidence discounted by its width, as specified in
`event_node_contract.md`; a finite-confidence
absorbing part can therefore revise with the report. This does not broaden the
settling shortcut or add partial producers to unreported compounds.

## Result

Master a17c1fef against this branch, 4 seeds each, run concurrently, budget
100, 30 rounds (SupplyNet) / replay with identical actions (StationOps).

| | master | settling |
|---|---|---|
| SupplyNet 3 untimed: Brier / error / coverage | 0.1824 / 0.1056 / 0.800 | 0.1627 / 0.0622 / 0.911 |
| producing: error / coverage | 0.369 / 0.00 | 0.052 / 1.00 |
| producing without stock: error / coverage | 0.500 / 0.00 | 0.331 / 0.34 |
| SupplyNet 3 timed: Brier / error | 0.1457 / 0.0234 | 0.1457 / 0.0234 |
| SupplyNet 1, 2: Brier | 0.0284, 0.1546 | 0.0284, 0.1546 |
| StationOps replay Brier per seed | 0.0444 0.0602 0.0640 0.0708 | 0.0444 0.0597 0.0642 0.0714 |

Without stock, production is answered only where a degradation settles an
`And` false; the rest has no proof outside the loop and stays unanswered.
Wall time is unchanged within noise.
