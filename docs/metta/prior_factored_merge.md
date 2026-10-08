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
- Their evidence overlaps only in the prior's when the rules and the
  observations differ, which the recognition checks (the same observation
  under two rules is not an independent observation). A rule stated with
  confidence 1 in both branches is not compared: its truth is given, not
  estimated, so two inversions through it share no evidence, and given the
  prior's statement their observations are independent (two reports of one
  storm through one report rule; `tests/metta/test_certain_merge.metta`). A
  rule whose truth is an estimate (confidence below 1, or refined) is shared
  evidence of both and blocks the factoring.

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
Var(logit s_i) − Var(logit s_p)).

Recognition: every view is read as updates of a prior. An inversion or a
factored merge updates its prior; any other view is its own prior, updated by
nothing. A view updating the base rate (`cpu`) merges into a view over any
other prior when

- the two share no evidence (`evidence-sets-overlap?`): no observation and no
  rule whose truth is an estimate, so a forward view derived from the
  inversion's own observation is not taken for an independent prior, and the
  overlap rule keeps one view as before. A rule stated with confidence 1
  carries no evidence (`register-rule-evidence!`): a persistence prediction
  through earlier periods' block rules and this period's block inversions are
  independent given this period's storm;
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
| factored, forward in the base rate's place | `(factored-revision (by block2 …) (prior (STV 0.7380 0.9790)) (…))` | 0.980662 | 0.9856 |
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
