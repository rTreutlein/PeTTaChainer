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

- `settled-premise-bundle` (`source_lowering.metta`) turns one part's bundle
  into the bundle of the compound: the part's goals, then
  `(CPU SettlesFormula ($tv value) value)`, which yields `value` when the part
  is certain at it and nothing otherwise. Its proof token is `(settled P)`.
- The variants are alternatives of the compound lowering, after the complete
  one: in `compound-all-premise-bundle` (adapters for compound keys and `Or`
  antecedents), in `lower-implication-antecedent` for an `And` antecedent
  (each conjunct lowered as the complete fold lowers it, so `(Not X)` reads X
  and `NotFormula`), and for n-ary query compounds. `once` callers read the
  complete lowering; `compile-rule` compiles one forward rule per lowering.
  Inversion, completion and outputs use the complete antecedent only.
- A part settles only when it binds every variable of the compound, so a
  settled row is as ground as the complete join's.
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
(`term-confidence` scores `SettlesFormula` 0): it adds nothing beyond the
complete step it gives way to.

`AndFormula` and `OrFormula` are exact on the same inputs: a certain-false
conjunct gives `(STV 0.0 1.0)` (before: confidence 0.99997 from the clipped
variance, and 0 when the other input had none), so the complete step and the
settled step agree.

## Interactions

- Merging. Both a settled view and the complete view of the same step can
  exist. Their evidence normally shows the complete one containing the
  settled one, but a known statement under a condition, or an assumption
  context, reads with no evidence, and the two would revise. So a settled
  step gives way to the complete step it settles, as a marginal projection
  gives way to its full projection (`proof-dominates?`, `settled-within?`).
- Self-support. A settled row depends on its part's key only; cycle
  exclusion applies to it as to any row. Settling to true needs a certain
  part, so a loop disjunct cannot settle its own Or: without stock, nothing
  outside the cycle proves the plant running, and there is no answer (the
  open-world reading; the closed-world answer, not running, would need
  negation as failure). A degraded mine settles its `And` false and breaks
  the loop: then production is answered false.
- Expected confidence. `premises-expected-confidence` matched "a formula whose
  result modus ponens reads next" by unification, which bound the rule's CTV
  to a settled ground value; it now compares by identity.
- Projections. A settled `Or` key projects onto its other disjunct with
  confidence 0 (P(B) is undetermined when A is certain), as a stored
  certain `Or` did before.
- Dormancy and the prior-factored merge need nothing: a settled variant is an
  ordinary rule, and a certain view is not an inversion over a prior.

## Not built: bounds

An uncertain part gives only a bound, P(A or B) >= P(A), P(A and B) <= P(A).
One STV cannot carry an interval; reading the unproved part as its base rate
would turn every partly known compound into an answer whose strength the
population decides, and in the untimed cycle the loop disjunct's base rate
would make a plant without stock run with the population's rate (SupplyNet's
exact answer is 0). So only certainty settles.

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
