# Prior-factored merge

Status: built, October 2026.

## Problem

A rule declared `(WithPrior p (Implication a b))` is inverted per instance by
Bayes' rule (`prior-inverse-implication`, `CTVBayesFormula`, then
`CTVModusPonensFormula` with the observation of `b`). With several such rules
on the same `a` (several sensors of one state), every inversion of an
instance reads the same prior `p`, and their views must be combined.

A plain implication `(Implication a b)` is inverted the same way with the
population base rate of `a` as the prior: stated with a CTV, by Bayes' rule
with its stated likelihoods (`prior-inverse-implication` with `population`,
`CTVBayesFormula`); stated with an STV, by `inverse-implication`, which
recovers P(b | not a) from the base rates of both sides
(`ImplicationCTVFormula`, `CTVInversionFormula`); then modus ponens. Several
such rules on the same `a` (several routes blocked by one storm) give several
updates of that one base rate.

Today `sk-merge-facts` combines views by their evidence. Inversions over the
same prior share the prior's evidence, so:

- When the prior is the population base rate (`with cpu derived`), base rates
  carry no member evidence, the views look disjoint, and they are revised:
  the prior is counted once per sensor.
- When the prior is an instance's own belief (`with <prior proof> derived`),
  the views overlap, and the merge keeps the view whose evidence contains the
  other's or else the more confident one: one sensor's inference survives
  and the others are dropped.

StationOps with two uninformative noise sensors per equipment type
(`--distractor-signals 2`; P(noise | leak) = P(noise | no leak) = q, stated
with confidence 1) shows both. At shift 1 the alarm and both noise posteriors
are revised; from shift 2 on the noise inversion wins, being the more
confident, and the shift's pressure alarm, the only real evidence, is
ignored. Seed 1, module M02, shift 3: belief 0.251 (confidence 0.79) through
`inverted noiseGivenLeak0 …` against 0.169 (0.39) through the alarm without
noise sensors. Over 8 seeds Brier goes from 0.0591 to 0.0801, log loss from
0.203 to 0.269.

## Rule

Inversions of conditionally independent observations over one prior combine
as sequential Bayes: posterior odds are the prior odds times each
observation's likelihood ratio. Each view already is one such update of the
prior, so its likelihood ratio is its odds over the prior's:

    logit s = logit s_p + Σ_i (logit s_i − logit s_p)

where s_p is the prior's strength and s_i the view's. An uninformative
observation has s_i = s_p and drops out exactly.

Confidence follows the variance of the log-odds by the delta method, as the
inversion and modus ponens formulas do: Var(logit x) ≈ Var(x) / (x(1−x))²
with Var(x) = `ideal-var`. A view's log-odds variance is the prior's plus its
own likelihood ratio's (independent), so

    Var(logit s) = Var(logit s_p) + Σ_i max(0, Var(logit s_i) − Var(logit s_p))

and the result's confidence is `ideal-conf-from-var` of s with
Var(s) = (s(1−s))² Var(logit s).

The merge is associative: merging a third view into a merged one applies the
same update, so views fold pairwise in any order.

## Worked example

Computed with the chainer's own formulas (`CTVBayesFormula`, modus ponens,
`ideal-var`, revision), k = 5. Prior
(0.088, 0.80); alarm P(alarm | leak) = 0.85, P(alarm | no leak) = 0.15, both
at confidence 0.9; noise q = 0.5675 both ways at confidence 1; observations
alarm = 1, noise0 = 1, noise1 = 0.

| | strength | confidence |
|---|---|---|
| alarm alone | 0.3507 | 0.5054 |
| each noise sensor alone | 0.0880 | 0.8000 |
| today, shift 1 (revision of all three) | 0.1178 | 0.9002 |
| today, shift ≥ 2 (most confident kept) | 0.0880 | 0.8000 |
| prior-factored, alarm only | 0.3507 | 0.5054 |
| prior-factored, alarm and both noise sensors | 0.3507 | 0.5053 |
| prior-factored, two alarms = 1 | 0.7515 | 0.5165 |
| exact odds for two alarms = 1 (no shrinkage) | 0.7560 | |
| prior-factored, alarm and noise from likelihoods at confidence 0.6 | 0.3507 | 0.4375 |

The noise sensors leave the alarm-only posterior unchanged; two informative
sensors compound as Bayes' rule does (the small gap is the likelihoods'
shrinkage toward their pooled value); a noise sensor whose likelihoods are
uncertain leaves the strength and lowers the confidence, since it could have
been informative.

## Recognising views to factor

Two views are factored when each is a prior-based inversion, or a factored
merge, over the same prior, and their observations differ.

- The prior has to be known at the merge. The inversion's proof today is
  `((inverted R with P derived) O)`: R the rule, P the prior's proof (or `cpu`
  for the population base rate), O the observation's proof. The prior's truth
  value is not in it. The compiled rule binds it (`$atv`), so the marker
  `derived` becomes `(prior <TV>)`: `((inverted R with P (prior (STV s c))) O)`.
  The prior is then identified by `P` and its truth value together, so two
  population priors of the same pattern match and two different instance
  priors do not.
- A merged view's proof is `(factored-revision P (prior <TV>) proof-1 proof-2
  …)`, with the views' proofs in a fixed order, so a further view with the
  same prior merges into it.
- Their evidence overlaps only in the prior's when the observations differ,
  which the recognition checks (the same observation under two rules is not
  an independent observation). Rules are not compared: given the rule's truth,
  whether stated with confidence 1 or an estimate, and the prior's statement,
  observations through one rule are independent (two reports of one storm
  through one report rule; `tests/metta/test_certain_merge.metta`). Until
  October 2026 an estimated rule blocked the factoring, as it blocked any
  merge (`overlap_conditioning.md`, "Shared rules").

The merged view's evidence and dependencies are the unions of the views'. It
is applied in `sk-merge-facts` before the overlap rule, so it takes
precedence over keeping one view and over revising.

## Edge cases

- A prior of strength 0 or 1 makes every view equal to it; the result is the
  prior.
- A view of strength 0 or 1 at a prior strictly between is a certain
  observation; it decides the result. Two certain views that contradict fall
  back to today's rule.
- Strengths are clipped as the formulas do (`ideal-clip`), so the log-odds
  stay finite.
- A plain implication is inverted with its antecedent's base rate as the
  prior, `((inverted R with cpu (prior <TV>)) O)`, and factors like a
  `WithPrior` inversion over the population base rate. A rule stated with a
  CTV is inverted by Bayes' rule with its stated likelihoods and reads no base
  rate of `b`; a rule stated with an STV reads only the positive likelihood
  and recovers the negative one from the two base rates, so it is Bayes' rule
  over the reconciled base rates (`ConsistentTriple`). Either way an
  observation as likely with `a` as without leaves the prior's strength.

## A view in the base rate's place

An inversion over the population base rate updates what is known of the
population, not of the instance. Another view of the same statement that
shares none of its evidence, such as a forward conclusion through other
observations, already is the instance's prior given that evidence. Under the
model the two bodies of evidence are independent given the statement, so the
inversion's likelihood ratio applies to that view's odds instead of the base
rate's:

    logit s = logit s_f + Σ_i (logit s_i − logit s_p)

with s_f the view's strength, s_i each inversion's, and s_p the base rate it
read. The variance follows the same rule with the view's log-odds variance
in the prior's place: Var(logit s) = Var(logit s_f) + Σ_i max(0,
Var(logit s_i) − Var(logit s_p)). (Until October 2026 the merge took the
larger of Var(logit s_f) and Var(logit s_p) in place of the first term, so
a confident view over a rate estimated from few members inherited the
rate's uncertainty: a certain persistence prediction updated by one storm
came out at confidence 10^-6; `tests/metta/test_base_rate_place_variance.metta`.)

Recognition: every view is read as updates of a prior. An inversion or a
factored merge updates its prior; any other view is its own prior, updated by
nothing. A view updating the base rate (`cpu`) merges into a view over any
other prior when

- the two are independent: they share no observation (no fact some rule
  concludes, no statement whose value is uncertain) and no rule whose truth
  is an estimate, so a forward view derived from the inversion's own
  observation is not taken for an independent prior, and the overlap rule
  keeps one view or conditions on what they share
  ([overlap_conditioning.md](overlap_conditioning.md)). A known fact no rule
  concludes, such as a period link both rules read, is a premise, not an
  observation. A rule stated with confidence 1 carries no evidence
  (`register-rule-evidence!`): a persistence prediction through earlier
  periods' block rules and this period's block inversions are independent
  given this period's storm;
- the other view is derived, not a stored fact: base rates fold the stored
  facts of their population, so an instance's own fact is already counted in
  the base rate the inversion read (a fact read against a base rate estimated
  from that one fact would count it twice); and
- the other view is uncertain: a certain view stands for unlimited evidence
  and stays as it is, as revision leaves it.

Otherwise the views are left to the overlap rule and revision as before.

The result is `(factored-revision F (prior <TV of F>) parts)`, F the view's
proof, so further inversions over the base rate fold into it the same way,
and inversions over F itself merge with it over the common prior F. The
pairwise merge stays associative: a forward view merged with two inversions
one after the other gives the same value as merged with their factored merge.
Two forward views still revise; when the views are revised first, the
inversions apply to the revision.

### Worked example

`tests/metta/test_population_prior_factoring.metta`: P(Storm) = 0.3 (0.9);
storm blocks routes r1 and r2 with P(Blocked | Storm) = 0.8,
P(Blocked | no storm) = 0.03, so P(Blocked) = 0.261; a blocked route delays
its shipment with 0.9, an open one with 0.05. Route r1 is inspected blocked,
r2's shipment is late. Blocked r2 has two views (the confidences are those
since a CTV rule's inversion reads no consequent base rate; see "Inversion
of rules stating both likelihoods" below):

| view | proof | strength | confidence |
|---|---|---|---|
| forward | `(by block2 ((inverted block1 …) o1))` | 0.7380 | 0.9790 |
| shipment inversion | `((inverted late2 with cpu (prior (STV 0.261 0.9))) l2)` | 0.8641 | 0.9172 |
| revised (before) | `merge/revision` | 0.7623 | 0.9829 |
| factored, forward in the base rate's place | `(factored-revision (by block2 …) (prior (STV 0.7380 0.9790)) (…))` | 0.980662 | 0.9943 |
| enumeration | | 0.980663 | |

logit 0.7380 + (logit 0.8641 − logit 0.261) = 1.036 + (1.851 + 1.041) =
3.927, odds 50.7. Storm north factors its two block inversions over its base
rate as before (0.991031 against 0.991032 by enumeration). With an
additional rule reading the storm off the late shipment directly, the forward
view of r2 contains the shipment's observation, and the views are not
factored.

## What changes

- Proof terms of prior-based inversions print `(prior <TV>)` instead of
  `derived`; tests and documents that show them change with them.
- StationOps with one sensor per type is unaffected beyond that: a single
  inversion has nothing to factor with. Shift-1 views over the population
  prior stop counting it more than once when there are several sensors.

## Evaluation

- Unit tests: the worked example's rows (noise leaves the alarm-only value;
  two alarms compound; uncertain noise lowers confidence); associativity of a
  three-view merge in either order.
- StationOps, 8 seeds, 10 modules, 20 shifts: plain game unchanged except for
  proof terms; `--distractor-signals 2` back to Brier 0.0591 and log loss
  0.203, or close.

## Result

StationOps, 8 seeds, 10 modules, 20 shifts (ChainerGame reads an answer's
own truth value, the last in its text, since a proof now holds its prior's):

| | score | Brier | log loss |
|---|---|---|---|
| plain game, before | 108,317 | 0.0591 | 0.203 |
| plain game, factored merge | 108,317 (identical per seed) | 0.0591 | 0.203 |
| two noise sensors, before | 107,440 | 0.0801 | 0.269 |
| two noise sensors, factored merge | 107,786 | 0.0630 | 0.213 |

Three of the eight seeds play the same game as without noise; the rest
diverge on an inspection or repair, which moves the remaining gap.

### Population-prior inversions

Plain implications factor over their antecedent's base rate since
`77c62799`. Two routes of one storm region, P(Storm) = 0.3,
P(Blocked | Storm) = 0.8, P(Blocked | no storm) = 0.03
(`tests/metta/test_population_prior_factoring.metta`):

| | before | factored | Bayes' rule |
|---|---|---|---|
| r1 blocked, r2 open | 0.085 (revision) | 0.7021 | 0.7021 |
| both blocked | | 0.9967 | 0.9967 |

SupplyNet stage 1, budget 100, seeds 1–4 (the reference posterior's Brier
is 0.028, history base rates alone 0.136):

| | Brier | log loss | posterior error |
|---|---|---|---|
| before | 0.113 | 0.368 | 0.151 |
| factored | 0.065 | 0.238 | 0.081 |
| forward view in the base rate's place | 0.034 | 0.153 | 0.019 |

Both levels factor: a route's shipment inversions over the route's base
rate, and a storm's block inversions, whose observations are those factored
route views or inspected facts. A route's belief revised its shipment view
with the forward view through the storm inferred from the other routes
(`(by block-r (factored-revision …))`), counting the route's prior twice;
the forward view now takes the base rate's place under the shipment updates
(see "A view in the base rate's place"), and every answer of seed 1 is a
`factored-revision`. Per seed, Brier 0.0427 / 0.0411 / 0.0139 / 0.0369 (was
0.0805 / 0.0763 / 0.0422 / 0.0608), at the same cost (12.2 / 11.6 / 15.4 /
8.0 s).

The largest remaining errors came from a shipment whose history base rates
are inconsistent with the stated likelihoods: seed 1, s3-1 late in 3 of 30
periods, its route blocked in 5, so P(late | open) recovered from the base
rates is below 0 and clipped. Its inversion was near 1 at confidence 10^-6,
and a strength near 1 decides a factored merge whatever its confidence:
Blocked r3 at t3 was 0.99998 against 0.122 by enumeration, Storm north 0.713
against 0.133. Revision used to weigh that view away.

### Inversion of rules stating both likelihoods

The shipment rules state both likelihoods (a CTV), so the base rate of the
consequent is not needed: P(a | b) = u P(a) / (u P(a) + v (1 − P(a))) with
u = P(b | a), v = P(b | not a). A CTV rule, stated or refined, is now
inverted by `CTVBayesFormula` over its antecedent's base rate, as a
`WithPrior` rule over the population base rate is; only an STV rule recovers
v from the two base rates. For s3-1, P(Blocked) = 1/6 and the stated 0.9 and
0.05 give 0.783 for one late shipment, whatever P(Late) the history shows
(`tests/metta/test_implication_inversion.metta`). Every inversion of a CTV
rule folds one base rate less.

SupplyNet stage 1, budget 100, seeds 1–4:

| | Brier | log loss | posterior error | seconds |
|---|---|---|---|---|
| ratio over both base rates | 0.0337 | 0.153 | 0.0186 | 12.2 / 11.6 / 15.4 / 8.0 |
| Bayes' rule with the stated likelihoods | 0.0285 | 0.109 | 0.0093 | 11.4 / 10.8 / 14.2 / 7.5 |

Per seed, Brier 0.0239 / 0.0436 / 0.0105 / 0.0361 (was 0.0427 / 0.0411 /
0.0139 / 0.0369); the reference posterior's Brier is 0.0278 over the same
keys (0.0253 / 0.0401 / 0.0107 / 0.0349).

## Antecedent completions

A rule whose antecedent is a conjunction, `(Implication (And O M) C)`, is
inverted onto each conjunct by its completion `(And O C) -> M`. With `u =
P(C | O, M)` and `v = P(C | not (O, M))` the rule's branches and s_O the
value of O (its observations' posterior, O independent of M a priori), C's
likelihoods given M are O's mixture of the branches, and given not M the
antecedent fails whatever O:

    P(C | M) = u' = s_O u + (1 − s_O) v        P(C | not M) = v

(`ConjunctLikelihoodFormula`; modus ponens, or u itself when O is certainly
true). The completion is Bayes' rule over the base rate P(M) with these, C's
value entering as its likelihood ratio λ (see "Soft observations"):

    odds(M | C) = odds(P(M)) (u' λ + 1 − u') / (v λ + 1 − v)

This is the joint posterior over O and M given C's evidence, marginalized over
O: C's value also updates O, and given O it decides M as the rule does. A
certain rule, O certainly true and C certainly false give P(M) = 0. Before,
O's value weighed the completion given O against P(M),
s_O P(M | O, C-evidence) + (1 − s_O) P(M), which weighs the two by O's value
before C's evidence: with u = 0.9, v = 0.3, P(M) = 0.3, s_O = 0.5 and C
certain it gave 0.43125 where the joint gives 0.4615.

A negated conjunct `(Not I)` completes I, the statement its observations,
base rate and queries are about, with the two likelihoods swapped: P(C | I) =
v, P(C | not I) = u'. Its proof is the completion's, over I's base rate, so it
merges with other updates of I. A conjunction with negated children is pure
for completion (`pure-connective-antecedent?`): before, the `Not` counted as a
computation and no conjunct of such a rule was completed.

A disjunct M of `(Or O M) -> C` is completed the same way with the
likelihoods of a disjunction (`DisjunctLikelihoodFormula`): P(C | M) = u and
P(C | not M) = s_O u + (1 − s_O) v. Before, an inverted `Or` was projected
onto its parts (`OrProjection`) under the disjunction's own prior, so a known
disjunct did not condition it: with O known false, P(M | C) is Bayes' rule
over P(M), not the disjunction's posterior (fuzzer repro seed 13000140: 0.0178
exact, 0.120 projected). A sibling certain at the connective's absorbing
value (a true disjunct, a false conjunct) decides the compound alone: the
consequence then tells nothing about M and the completion gives no view,
rather than M's base rate as a view that competes in merges. A part the
completion does not complete with no
value of its own is read at its population prior (see
`runtime_design_assumptions.md`, "Queries read what their roots reach").

For an STV rule, v is recovered from the base rates of `(And O M)` and C, as
for a plain inversion. The proof is `((antecedent-completion R idx with cpu
(prior <P(M)>)) (conjunction <O proofs> <C proof>))`.

What is factored over what. The completion is an update of M's population
base rate P(M), the same prior a plain inversion of a rule `M -> D` reads (the
pattern is M's, a fresh copy, so the folds and truth values are the same). An
observation of C as likely as the rule makes it, s_C = u' P(M) + v (1 − P(M)),
leaves P(M), so the completion's odds over P(M) are the likelihood ratio of
O's and C's evidence, and it merges with other updates of P(M), or with a
derived view in the base rate's place, as an inversion does. Factoring needs
the views' evidence to be independent given M. Given M, C depends on the past
only through O and M, so evidence about C that reaches no other view (C's own
observations) is independent of the other views' evidence; O is conditioned
on, and the rule, when given, carries no evidence. The checks stay those of
inversions, at the level of the completion's witnesses:

- over a base rate, the views are independent (no shared observation or
  uncertain statement, as above), so an observation read below the
  witnesses blocks the factoring;
- no observation of one view is an observation of another
  (`sk-part-witnesses`): two completions reading the same C through
  different O are one observation, not two.

A completion's observation is its consequence C alone. A sibling O known
with certainty is conditioned on, not observed: given O, the completion is
the likelihood ratio of C, P(C | M, O) over P(C | not M, O), and holds no
evidence of M through O. So the merge compares a completion's evidence
without its certain siblings (`sk-update-evidence`): another view that reads
O, an inversion of O's rule (P(O | M)) or a forward view from O (P(M | O)),
is independent of it given O, and Bayes' rule over both is exact,
P(M) P(O | M) P(C | M, O). Compared with the siblings, the completion's
evidence contained the inversion's, and the completion alone was kept: with
P(M) = 0.3, P(O | M) = 0.8 against 0.2, P(C | M, O) = 0.9 against 0.1, and
O and C observed, 0.794 instead of 0.939
(`tests/metta/test_antecedent_completion.metta`; fuzzer seed 12000059, a
certain O = 1 that only M explains answered 0.69 instead of 1). An
uncertain sibling's value is read as independent of M a priori, so it stays
evidence of the completion.

The siblings are marginalised before C is observed: s_O is O's probability
apart from C. So a completion reads no view of a sibling that depends on its
consequence, which would count C twice, through s_O and through the
likelihood ratio. In a loop through C a sibling's support through C is
circular: a complete sibling none of whose views it may read is read closed,
with a complete C pinned unfounded (`sk-completion-state`,
`complete_predicates.md`). A consequence stored as known false is what the pin
would make it, so the siblings then read it as it is, through the rows it
settles; a closed read could not settle `D <- (And B C)` with C false while B
has no value. In `B <- (Or A D)`, `D <- B` with B observed true,
D's value was B's own, D true explained B, and A stayed at its prior; read
apart from B, D is unfounded and only A explains B, exact 1
(`test_problog_fuzz_regressions.metta`; fuzzer seeds 12000068, 12000268).

The previous formula, P(M | O, C) = u P(O, M) / P(O, C), read the base rate of
the known conjunction `(And O C)` and never used v. That base rate is folded
over other members and at other times than P(M) and P(O, M), so an
uninformative C did not return P(M) and the view was not an update of P(M).
In the SupplyNet toy below P(O, M) = 0.448 and P(O, C) = 0.324 against
P(M) = 0.325, so
P(M | O, C) = 0.7 · 0.448 / 0.324 = 0.969 and the completion of Storm w1 was
0.103 where Bayes' rule gives 0.204; recognised as an update, it made
smoothing worse (0.7305). Bayes'
rule with the stated likelihoods reads no P(C) or P(O, C), as for plain
inversions of rules stating both likelihoods.

A base rate is read as the prior of one more member of its population: its
mean under the Bayes prior with which Bayes' rule reads a likelihood,
(s n + a/2) / (n + a) over the n members counted (`set-bayes-prior-count`,
a = 0.2), at the rate's confidence (`population-prior-tv`, where the base
rate is read as the prior, `prior-base-rate-premises`, for completions and
for inversions of STV and CTV rules over a population base rate alike, and
for a root's population prior). A rate of 0 or 1 from finitely many members
then leaves an instance either way possible, and its updates keep their
likelihood ratios for a view in the base rate's place (see "Degenerate
rates" below). A certain rate, and an instance prior of a `WithPrior` rule
(the instance's own belief), keep their values.

A knowledge base that stores only the true instances of a predicate (logic
KBs of Provable, Path or Ancestor facts) declares it positive-only
(`set-positive-only-predicate`). Its stored instances are then no sample of
its population: their rate, 1, says nothing of how often a candidate holds,
and an inversion over it would assert every antecedent of every stored
conclusion. A positive-only predicate has no prior: no inversion or
completion is compiled onto a pattern with a conjunct of it, and a root of
it gets no population prior. Nor does an STV rule over it read its rate: its
negative branch is derived without the antecedent's rate, which would
otherwise reconcile P(B | A) with P(A) = 1 and so pull it to P(B) (a refined
`(Asserts s $x) → $x` rule learned at 0.798 applied at 0.666 in ChainerGame's
conflicting sources). The declaration replaces the cut that gave a
rate of 0 or 1 no prior until October 2026, which also left a front never
(or always) seen in a SupplyNet history at its persistence prediction
whatever the window showed (`tests/metta/test_implication_inversion.metta`,
`tests/metta/test_math.metta`, `tests/metta/test_antecedent_completion.metta`).

A completion reads C's value as an observation of C, so it reads no view of
C that is a forward conclusion or a closed read's unfounded value
(`sk-consequence-prior`): a forward conclusion predicts C from its causes,
the completed conjunct among them, and carries no evidence about M
(`tests/metta/test_antecedent_completion.metta`, the backup feed: read as an
observation it moved the degradation from its prior 0.25 to 0.6). In
SupplyNet stage 3 the current period's production is only predicted;
reading it, the error of unstocked production was 0.021 instead of 0.008. For the same reason it is
compiled into the search only where C can be observed: a statement of C's predicate is
stored (a forward run's copy of a derived value does not count), or an
inverse rule, an inversion or a completion, concludes C from observations of
its consequences. A predicate only forward rules conclude is a prediction,
from M through the completed rule itself or from other causes, and carries no
evidence about M. The completion's first premise asks this with C's head and
arity (`observed-predicate?`), so the rule start prunes the completion before
any join or base-rate fold exists. In SupplyNet the storm of the next period
is observed through the block rules' inversions and is completed. StationOps'
temporal filter (`persist`: `(And (NextState $previous $unit)
(SealLeakAtShiftEnd … $previous)) -> (LeakPredicted …)`) predicts
`LeakPredicted` from the previous shift's state and from servicing, and
nothing observes it: the alarm reads it as its `WithPrior` prior. Its
completions never produced a view, but each joined `NextState` and read the
base rate of `SealLeakAtShiftEnd`, a fold over the derived states of every
shift. That fold took the evaluation allowance the shortfall fold's members
needed; the shortfall posterior was computed over a part of its candidates
and stated, with confidence 1, that a leak the shortfall had confirmed was
absent (StationOps seed 3, shift 8: 0.29 for a confirmed leak, Brier 0.0636
to 0.0685). With the check the completions are pruned and StationOps plays
as before. Read as an observation, a prediction would also move M: in
`tests/metta/test_antecedent_completion.metta`, servicing predicts 0.2 for
the consequence and would pull the conjunct from its base rate 0.3 to 0.172.

### Worked example: production reports and degradation

`tests/metta/test_antecedent_completion.metta`, SupplyNet stage 3 in small:
the mine runs exactly when the power plant runs and the mine is not degraded,
`(Implication (And (Producing plant $t) (Not (Degraded mine $t))) (Producing
mine $t))` with (1, 0); P(Degraded) = 0.25. With the plant on and the mine
off in t5, Degraded mine t5 is 1 (the positive form, `Healthy`, gives 0).
With the plant on at 0.8 and a report of the mine running (likelihood ratio
0.9 / 0.2 = 4.5), odds(Degraded) = 1/3 · 1 / (0.8 · 4.5 + 0.2), P = 2.5 / 31
= 0.080645 (the chainer: 0.0806452). With a persistence rule (0.75, 0.1) and
the mine inspected sound in t4, Degraded mine t6 is 0.75: the completion
decides t5, merged with the persistence view in the base rate's place.

SupplyNet stage 3, 30 rounds, against master 0b2f637c, run concurrently
(timed and untimed, seeds 1–4 at budget 100 and seeds 2–3 at budget 50;
error is the mean distance from the exact posterior):

| | error | Brier | degraded | producing | producing, no stock | seconds |
|---|---|---|---|---|---|---|
| timed, master | 0.0232 | 0.1498 | 0.0665 | 0.0558 | 0.0251 | 89.9 |
| timed | 0.0101 | 0.1466 | 0.0081 | 0.0117 | 0.0128 | 109.2 |
| untimed, master | 0.0166 | 0.1433 | 0.0540 | 0.0482 | 0.0000 | 98.9 |
| untimed | 0.0081 | 0.1408 | 0.0053 | 0.0095 | 0.0039 | 118.5 |

Seed 1, round 6 (the diagnosed gap): Degraded mine t6 0.134 → 0.750 and
Producing mine t6 0.866 → 0.250, Degraded plant-b t6 0.253 → 0.750, all
exact. Stages 1 and 2 are identical to master; StationOps temporal replay
(seeds 1–4, budgets 25 and 50) plays and believes identically, compute
within ±3%.

### Worked example: a certain conjunct

`tests/metta/test_antecedent_completion.metta`: P(Rain) = 0.3 (0.9); rain
wets an outdoor place, `(Implication (And (Outdoor $x) (Rain $x)) (Wet $x))`
with (0.9, 0.2), and brings clouds, `(Implication (Rain $x) (Clouds $x))` with
(0.8, 0.25), all stated with confidence 1; d is outdoor, wet and cloudy, all
certain.

| view | proof | strength |
|---|---|---|
| completion | `((antecedent-completion wet 1 with cpu (prior (STV 0.3 0.9))) (conjunction outdoor-d wet-d))` | 0.27 / (0.27 + 0.14) = 0.6585 |
| inversion | `((inverted clouds with cpu (prior (STV 0.3 0.9))) clouds-d)` | 0.24 / (0.24 + 0.175) = 0.5783 |
| factored | `(factored-revision cpu (prior (STV 0.3 0.9)) (completion inversion))` | 0.860558 |
| Bayes' rule | odds 0.3/0.7 · 0.9/0.2 · 0.8/0.25 = 6.171 | 0.860558 |

With a rule reading rain off the wet ground directly, its inversion of wet-d
shares the completion's observation; the views are not factored, and the
completion, whose evidence contains the inversion's, is kept (0.6585, where
factoring would count wet-d twice: 0.897).

### Worked example: smoothing a persistent storm

`tests/metta/test_certain_merge.metta`, SupplyNet stage 2 in small: a storm
persists, `(Implication (And (NextPeriod $p $t) (Storm north $p)) (Storm north
$t))` with (0.7, 0.3); it blocks r1 with (0.8, 0.03), and a blocked route
delays each of three shipments with (0.9, 0.05). The storm of h3 is resolved
false, all three shipments of w1 are late and none of w2. The filter view of
Storm w1, the persistence prediction updated by w1's block inversion, is
0.919133, the exact filter. The previous period's storm takes w2's evidence
through the completion `((antecedent-completion persist-north 1 with cpu
(prior (STV 0.325 0.444))) (conjunction next-w2 <w2's block inversion>))`:
NextPeriod is certain, P(Storm) = 0.325, so

    P(M | O, C) = 0.7 · 0.325 / (0.7 · 0.325 + 0.3 · 0.675) = 0.52907
    P(M | O, not C) = 0.3 · 0.325 / (0.3 · 0.325 + 0.7 · 0.675) = 0.17105

Storm w2 is 0.0907 from w2's observations alone (the view of Storm w2 that
does not depend on Storm w1), formed under the base rate 0.325, so it enters
as its likelihood ratio (see "Soft observations" below)
λ = odds(0.0907) / odds(0.325) = 0.2071, restated under the prior the rule
implies for Storm w2, 0.7 · 0.325 + 0.3 · 0.675 = 0.43: odds 0.2071 ·
0.43 / 0.57 = 0.1563, s' = 0.1351, and the completion is 0.1351 · 0.52907 +
0.8649 · 0.17105 = 0.2194, a likelihood ratio for Storm w1 of
odds(0.2194) / odds(0.325) = 0.5839 = (0.7 λ + 0.3) / (0.3 λ + 0.7). The
filter view's evidence (h3's fact, w1's shipments) and the completion's
(next-w2, w2's shipments) are disjoint and the rules are given, so the views
factor, the filter view in the base rate's place:

    logit 0.919133 + logit 0.2194 − logit 0.325 = 2.4306 − 1.2690 + 0.7309 = 1.8925, P = 0.86905

Exact smoothing: P(none late | storm w2) = 0.172275, P(none late | no storm
w2) = 0.831684, likelihood ratio for Storm w1 (0.7 · 0.172275 + 0.3 ·
0.831684) / (0.3 · 0.172275 + 0.7 · 0.831684) = 0.58388, P = 0.86905. The
chainer gives 0.869048. Revising the two views gave 0.7445; reading
Storm w2's 0.0908 as a posterior under the rule's prior 0.43 gave the
completion 0.2036, a ratio of 0.531, and 0.8579.

### Result

SupplyNet, budget 100, 30 rounds, seeds 1–4 (four in parallel):

| | Brier | posterior error | previous storm | storm | blocked | seconds |
|---|---|---|---|---|---|---|
| stage 2, revised completion | 0.1552 | 0.0100 | 0.0388 | 0.0012 | 0.0007 | 22.3 / 24.0 / 23.8 / 14.1 |
| stage 2, Bayes completion | 0.1546 | 0.0089 | 0.0341 | 0.0012 | 0.0007 | 21.4 / 23.5 / 22.3 / 13.2 |
| stage 1, either | 0.0284 | 0.0085 | | | | 12.1 / 11.6 / 16.4 / 8.1 |

The reference posterior's Brier is 0.1540 for stage 2. StationOps (live
temporal model, 4 seeds, budget 50) is unchanged by the observation check:
regret 614.7 / 114.1 → 86.4 / 182.4 / 70.5, Brier 0.0452 / 0.0643 / 0.0652 /
0.0595 (master 0.0450 / 0.0641 / 0.0652 / 0.0592). A previous storm whose
answer includes the completion is within 0.003 of the posterior (seed 3);
at budget 100 the search reaches the completion for 7 of 87 previous storms,
the rest answer with the filter view alone (error 0.045). At budget 2000 it
reaches 52 and the previous-storm error falls to 0.006; with soft
observations read as likelihood ratios (below) it is 0.

## Soft observations

An inversion applies its observation of b to the inverted rule (P(a|b),
P(a|not b)) by modus ponens. For a certain observation that is Bayes' rule.
A soft value s of b is a posterior: an inversion or a factored merge of b's
own observations over a prior p of b, b's base rate or a view in its place.
Its evidence is the likelihood ratio λ = odds(s) / odds(p). Modus ponens
reads s as a posterior under the prior the inversion implies for b, the π
with π P(a|b) + (1 − π) P(a|not b) = P(a) (for Bayes' rule u P(a) + v (1 −
P(a))), and so scales that evidence wrongly wherever p ≠ π.

Rule: the observation is restated under π, odds(s') = λ odds(π), before
modus ponens. Modus ponens over s' gives the posterior odds

    odds(P(a)) (u λ + 1 − u) / (v λ + 1 − v)

exactly. The log-odds variance of λ is that of s less that of p, which s's
contains (delta method; a value stated with confidence 1 keeps it), as the
merge reads an update's variance over its prior. (Until October 2026 the
whole variance of s carried over, the prior's included, so an observation
formed over a rate from few members read as nearly uninformative in
confidence.)
A certain observation (λ infinite or 0) is unchanged, as is an inversion b
does not move.

Where. `ObservationRatioFormula` (pln_formulas `truth_values.metta`) runs
between the inversion formula and modus ponens in every inverse rule: STV
rules (`inverse-implication`, after `CTVInversionFormula`), CTV and
`WithPrior` rules over a population or instance prior
(`prior-inverse-implication`, after `CTVBayesFormula`), and antecedent
completions on the consequence C (after `CTVBayesFormula` over P(M)). It
recovers π from the inversion and its prior by total probability, which
Bayes' rule satisfies exactly; for an STV rule π is the reconciled P(b),
exact when `ConsistentTriple` leaves P(a) as it is and clipped into (0, 1)
otherwise.

Which prior. `sk-observation-prior` reads p off the observation's proof as
the merge reads it (`sk-prior-update-of`): an inversion or a completion
updates the `(prior <TV>)` it names, a factored merge its prior, which is a
base rate or the view in the base rate's place. That view's information is
then left out of λ: it is C's prediction from other sources, which the
likelihood ratio of C's own evidence does not contain, as a child's message
to its parent in belief propagation carries only its diagnostic evidence. A
view updating nothing (a stored fact, a forward conclusion, a revision) was
formed under no known prior; it is read as before, as a posterior under π
(Jeffrey's rule), and so is a value over a prior of 0 or 1. Reading a stored
soft fact against b's population base rate instead would count the fact in
the rate it is compared with, and a predicate with a single soft fact would
carry no evidence at all.

Examples. `tests/metta/test_implication_inversion.metta`: a late shipment
makes its route blocked with 0.8182 over P(Blocked) = 0.2, a ratio of 18 =
0.9 / 0.05; the storm read through the block rule is 0.805591, Bayes' rule
over the chain (P(Late | storm) = 0.73, P(Late | no storm) = 0.0755), where
modus ponens under the rule's prior 0.261 gave 0.7671.
`tests/metta/test_certain_merge.metta` becomes exact everywhere: Storm h3
while open 0.1500 → 0.13636, the filter view of Storm w1 0.91920 → 0.919133,
Storm w2 0.29405 → 0.293848, the smoothed Storm w1 0.8579 → 0.869048
(exact 0.86905).

### Result

Against master affb69cf, run concurrently, 30 rounds, seeds 1–4 (SupplyNet
error is the mean absolute distance from the exact posterior):

| | Brier | error | previous storm | storm | blocked | seconds |
|---|---|---|---|---|---|---|
| stage 2, budget 100, master | 0.1546 | 0.0089 | 0.0341 | 0.0012 | 0.0008 | 18.1 / 19.7 / 18.7 / 11.0 |
| stage 2, budget 100, ratio | 0.1546 | 0.0078 | 0.0319 | 0.0000 | 0.0001 | 16.9 / 18.0 / 17.3 / 10.4 |
| stage 2, budget 2000, master | 0.1540 | 0.0021 | 0.0064 | 0.0012 | 0.0006 | 20.6 / 22.8 / 23.2 / 12.2 |
| stage 2, budget 2000, ratio | 0.1540 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 19.1 / 21.2 / 20.3 / 12.3 |
| stage 1, budget 100, master | 0.0284 | 0.0085 | | | | 9.5 / 8.9 / 11.8 / 6.1 |
| stage 1, budget 100, ratio | 0.0282 | 0.0077 | | | | 8.6 / 8.2 / 10.8 / 5.6 |

At budget 2000 every answer equals the exact posterior to 10^-16 (the
reference posterior's Brier is 0.1540; master's mean Brier matches it only
on average, per seed it is 0.1460 / 0.1396 / 0.1628 / 0.1676 against
0.1466 / 0.1391 / 0.1625 / 0.1679). At budget 100 the previous storms
whose answer the search does not extend to the completion keep the filter
view's error. Stage 2 at budget 50 (seeds 2, 3): previous storm 0.0383 /
0.0450 → 0.0348 / 0.0452. Stage 3, seed 1: timed error 0.0217 → 0.0212,
untimed 0.0207 → 0.0201, production unchanged. StationOps temporal replay,
seeds 1–4 at budgets 25 and 50: beliefs identical, compute time within
±5%.

## Degenerate rates

SupplyNet stage "scale" (ChainerGame `supply-network`): a zone's front
persists with 0.9 and starts with 0.05. A front never on in the 20 labelled
history periods has base rate 0, and so has every storm of the zone whose
history had none. Until the rate was read as a prior under the Bayes prior,
a rate of 0 gave no prior, so no storm's inversion onto the front existed,
nor any alarm's inversion onto such a storm: the front stayed at its
persistence prediction from the last label whatever the window showed. Size
l, seed 1, 4 steps per query: Front z3 t1 0.050 in all ten rounds (exact
0.096, then 0.006 down to 0.000); seed 2: Front z3 t3 0.129 against 0.946.

`tests/metta/test_degenerate_rate_update.metta`, at budget 4, where the
fold counts only the stored periods:

| history of the front | t1 alarms | prior read | exact | chainer | before |
|---|---|---|---|---|---|
| off in h1..h3 (rate 0) | both ring | 0.1 / 3.2 | 0.155525 | 0.155525 | 0.05 |
| on in h1..h3 (rate 1) | neither | 3.1 / 3.2 | 0.823280 | 0.823280 | 0.9 |

Clipping the rate off 0 (10^-6, as the formulas clip) instead was tried: an
update with a likelihood ratio below 1 then falls under the clip floor, only
upward evidence survives, and l seed 1 went from 0.032 to 0.152 (Front z3 t1
0.997).

### Result

Scale sweep, sizes s, m, l, seeds 1 and 2 (`supplynet.sweep`, two runs at a
time per build), mean error to the exact posterior, master d0be7108 against
this change:

| steps/query | s | m | l |
|---|---|---|---|
| 0.25 | 0.224 → 0.159 | 0.164 → 0.151 | 0.190 → 0.137 |
| 0.5 | 0.110 → 0.083 | 0.099 → 0.092 | 0.161 → 0.098 |
| 1 | 0.068 → 0.033 | 0.013 → 0.007 | 0.066 → 0.030 |
| 2 | 0.068 → 0.033 | 0.013 → 0.006 | 0.060 → 0.020 |
| 4 | 0.040 → 0.033 | 0.012 → 0.004 | 0.048 → 0.005 |
| 8 | 0.016 → 0.016 | 0.010 → 0.006 | 0.046 → 0.006 |
| 16 | 0.029 → 0.029 | 0.006 → 0.005 | 0.015 → 0.008 |

Current-front error, seed 2: s 0.259 → 0.064 (1 step), m 0.047 → 0.016 and
l 0.180 → 0.018 (4 steps). Coverage is 1 at every budget: a root the budget
does not reach answers its population prior, which a rate of 0 or 1 now
gives too. The inversions that now exist cost work where they are reached:
at l, 2 to 8 steps per query, 25-40% more time per query and 50-70% more
peak memory (1.4 → 2.2 GB at 4 steps); s, m and l at 16 steps are within a
few percent. l at 4 steps (48 ms per query, error 0.005) is now better than
master at 16 steps (147 ms, 0.015). What remains at s seed 2 is evidence the
search does not reach: Front z1 t8, 0.489 against 0.965, is built from the
alarms of t1..t8 alone (exact from those alarms: 0.493).

## Relation to PLN

Revision, as the PLN book derives it, combines estimates of the same
frequency from different samples (Goertzel et al., *Probabilistic Logic
Networks*, draft of 27 June 2008, §5.10.3, pp. 116–120); its dependency
parameter changes the count, never the strength. The book notes that
averaging deductive conclusions "can be improved upon considerably" (§9.3,
p. 194) and points to Bayes-net propagation for static rule bases (§9.4).
The nearest PLN rule, `opencog/pln/rules/wip/implication-implicant-conjunction.scm`,
derives P(C|A,B) = P(C|A)·P(C|B)/P(C) and caps the overflow its additional
marginal-independence assumption causes. The odds form used here,
O(C|A,B) = O(C|A)·O(C|B)/O(C), needs only conditional independence given C
and given ¬C, and stays within [0, 1]. Correlated evidence stays guarded as
the book's inference trails guard it: views that share rules or
observations are not factored.
