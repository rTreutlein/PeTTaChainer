# Prior-factored merge

Status: built, October 2026.

## Problem

A rule declared `(WithPrior p (Implication a b))` is inverted per instance by
Bayes' rule (`prior-inverse-implication`, `CTVBayesFormula`, then
`CTVModusPonensFormula` with the observation of `b`). With several such rules
on the same `a` (several sensors of one state), every inversion of an
instance reads the same prior `p`, and their views must be combined.

A plain implication `(Implication a b)` is inverted the same way with the
population base rate of `a` as the prior (`inverse-implication`,
`CTVInversionFormula`, then modus ponens): several such rules on the same `a`
(several routes blocked by one storm) give several updates of that one base
rate.

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
  under two rules is not an independent observation).

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
  `WithPrior` inversion over the population base rate. Its inversion reads
  only the positive likelihood and recovers the negative one from the two
  base rates, so it is Bayes' rule over the reconciled base rates
  (`ConsistentTriple`): an observation as likely with `a` as without leaves
  the prior's strength.

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
