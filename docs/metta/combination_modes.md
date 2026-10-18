# Learned combination modes

Status: built, October 2026.

## Problem

Several rules `A_i -> C` give several forward views of one statement `(C x)`,
P(C | A_i) or P(C | not A_i) for each known antecedent. Disjoint views are
revised, which averages them. What P(C | A_1, ..., A_n) is depends on how the
antecedents relate to C, which the rules do not say
(`combination_hypotheses.md`):

| relation | right combination |
|---|---|
| signs of C, independent given C | odds: prior odds times each view's likelihood ratio |
| independent causes of C (noisy-OR) | survival: 1 − (1 − p) Π (1 − s_i) / (1 − p) |
| the same evidence, redundant proxies | revision (the average) |
| interactions | none of these |

The data has the answer. A knowledge base that stores outcomes of C next to
its antecedents shows which combination predicts C. CombiNet (ChainerGame,
`docs/combination_bench.md`) measures the gap: revision's error against the
exact posterior is 0.076 / 0.108 / 0.139 at 2 / 3 / 5 parents, choosing the
mode per consequent by the likelihood of the history 0.045 / 0.046 / 0.060.

## Rule

Per consequent predicate, the knowledge base keeps a few numbers: how many
outcomes of C it stored and how many were true, and for each mode the log
likelihood of the outcomes under the views that met on them. Disjoint forward
views of a statement of C combine by the mode the outcomes prefer, and by
revision until they clearly prefer one.

### Formulas

A forward view is a rule application `(by R ...)`; its strength s_i is the
rule's conclusion for the antecedent's value. The prior p is the rate of C
among its counted outcomes. Each mode is one link g on which the views'
updates of p add up:

| mode | g(x) | combination |
|---|---|---|
| revision | | confidence-weighted mean (`mergetvs`) |
| odds | log(x / (1 − x)) | g(s) = g(p) + Σ_i (g(s_i) − g(p)) |
| noisy-OR | log(1 − x) | g(s) = g(p) + Σ_i (g(s_i) − g(p)), s clipped to [0, 1] |

The odds mode is the prior-factored merge (`prior_factored_merge.md`) over
the consequent's rate: each forward view, read as an update of p, contributes
its likelihood ratio once, and an uninformative view (s_i = p) drops out. The
noisy-OR mode is the same computation on the survival scale: each cause leaves
C off with probability (1 − s_i) / (1 − p) of what the leak leaves. The
confidence follows the variance on the link's scale by the delta method, as
for the factored merge: Var(g(x)) ≈ Var(x) g'(x)² with Var(x) = `ideal-var`,
V = V_p + Σ_i max(0, V_i − V_p), and Var(s) = V / g'(s)². Both product modes
are associative, so views merge pairwise in any order, as before; a merge of
combined views proves by `(combination <mode> (prior <p>) (<view proofs>))`.

### The prior

p is the rate of C among the outcomes counted, by Laplace's rule of
succession: (Σ y + 1) / (n + 2) over n outcomes y, with confidence
n / (n + k). The scores and the merge read the same estimate. It is C's own
tally, not a base-rate fold: nothing needs to read a base rate of C for its
views to combine (CombiNet's consequents are read by no rule), and a fold
would cost a search.

### Learning

An outcome is a stored fact of a ground statement of C in the main context
with confidence 1 (strength y, usually 0 or 1) that two or more forward rules
conclude.
Adding it records it as pending, one row: nothing else happens at add time.
The first merge that needs C's mode scores the pending outcomes, in the order
they were stored, and drops them:

1. Each forward rule concluding the statement is applied to its antecedents'
   stored facts, the rule's own formulas computing its view. A refined rule
   reads its truth key's current value, what it has learned when the outcome
   is scored (its prior before any review). A rule whose antecedent is not
   ground once the statement binds it, that reads a fold (a base rate), or
   that settles a compound (a variant of a complete step) gives no view.
   Containing rule conditions are removed before the disjointness check,
   as in a read. Otherwise a conjunction and its singles share premises and
   prevent the entire outcome from scoring any mode. This filter reads
   original conditions only, without prior merging or learning a mode inside
   its own score.
2. With two or more views whose evidence is disjoint, each mode predicts
   q_m from the views and the prior before this outcome, and its score gains
   y log q_m + (1 − y) log(1 − q_m), q clipped to [10⁻⁶, 1 − 10⁻⁶] as the
   formulas clip.
3. The outcome is counted in p.

So the scores are prequential: each outcome is predicted from the outcomes
before it, which is what a mode would have said had it been used.

### The threshold

The modes have no parameters fitted to the outcomes, so each score is the
log of the probability the mode, as a predictive model, gave the outcomes
(Dawid's prequential principle), and the difference of two scores is the log
of their Bayes factor. With the modes equally likely a priori, the best
product mode (odds on a tie) is used when its Bayes factor over revision is
at least 10, "strong" evidence on Jeffreys' scale: L_m − L_revision ≥ ln 10.
Otherwise the views revise. Few outcomes cannot reach it unless revision put
the outcomes at a tenth of the mode's probability; a mode that only overshoots
(rates estimated from little data) loses on its own outcomes and stays below
it.

### Where it applies

In `sk-merge-facts`, where disjoint views would revise:

- both views are forward views (rule applications, or combinations of them);
- they are independent: views that share an observation keep the overlap
  rule, so correlated or redundant evidence is never multiplied; a shared
  rule, given or estimated, is no shared evidence
  (`overlap_conditioning.md`, "Shared rules");
- the consequent's tally prefers odds or noisy-OR;
- two certain views that contradict revise, as in the factored merge.

The decision is read when the merge happens; a key merged before a switch
keeps its value until it is merged again, as a base rate lags its members.

### Interactions

- **Certain facts.** A ground statement with a certain stored fact is its own
  value: there is nothing to combine. Those facts are the outcomes.
- **Inversions and completions** are updates of a base rate, not rule
  applications: they factor among themselves as before. A combination of
  forward views is a derived view; it takes the base rate's place under their
  updates, as a revision of forward views did. A completion reads no forward
  conclusion as an observation of its consequence, and a combination is one.
- **Complete predicates.** Closed reads evaluate rows again under a pin and
  merge them like any rows; an unfounded value is not a forward view.
- **Partial folds.** Provisional values merge only when a key has nothing
  else, then by the mode like any views; their confidence is already scaled.
- **Specificity and siblings.** Containment selection over original views
  precedes combination (`hypothesis_rules.md`), so combinations cannot hide
  singles from a specific rule. Overlapping sibling forward views combine by
  odds, with shared uncertain statements conditioned through the existing
  machinery and a conservative combined fallback while unpaid. Disjoint signs
  retain the learned mode. Only same-condition independent estimates revise.
  Nearest incomparable containing classes supply an equal distribution mixture
  as the specific estimate's centre ([prior definition](prior_definition.md)).
- **Hypothesis rules.** Refined rules are scored with their truth key's
  value. Their views carry no samples (an implication instance fold carries
  none), so views of two refined rules into C are independent and combine
  by the mode (`test_combination_modes.metta`: the signs cases with both
  rules refined, odds). Until October 2026 they were not scored: the truth
  premise is an open statement and gave no view, so their outcomes left
  every mode tied and the views revised (ChainerGame's conflicting sources,
  pln-sources at size s, seed 1: error 0.322 with revision, 0.164 with odds).
  The correlated case of `test_hypothesis_rules.metta` stays at 0.794.
- **Lifting.** Lifting needs shared facts; disjoint views have none.
- **Forward chaining** merges with the same rule.

### Shared-class siblings (tracker #49)

Sibling odds are resolved over the whole original family, after same-condition
estimates revise and the existing confidence-dependent specificity shrinkage
(#69) reads each original specific estimate once. A supported family has
positive applicable conditions whose every pair intersects in exactly the same
nonempty class, with a live general view for that exact class. There is no
selection by confidence, condition size, or merge order. The shared class may
itself be a conjunction. Its same-condition estimates revise into one TV g.
For m siblings:

    logit s = sum_i logit s_i - (m-1) logit g
    V = V_g + sum_i max(0, V_i - V_g)

Here V is variance on the log-odds scale, converted back by the existing delta
method; confidence is capped by the least confident sibling. Sample twins
remain one estimate while every original condition participates in separator
recognition. All contributing proofs and dependencies survive; the shared general view remains a parameter,
not an additional instance observation. Shared uncertain evidence still uses
#68's budgeted conditioning. The supported correction runs inside the positive
conditioned branch; unpaid revisions stay provisional.

With AB->T=.8, BC->T=.6, B->T=.5 and population=.25 (shrinkage disabled to
isolate arithmetic), the answer is 6/7=.8571428571, replacing 18/19=.9473684211.
A family AB, BC, BD similarly divides by the shared B odds twice.

### Unresolved overlap approximation (tracker #77)

Cyclic/mixed families, mixed polarity, negative branches, and absent live
separator estimates retain the population approximation for strength. Their
confidence includes model uncertainty. It is a conservative heuristic rather
than a calibrated joint posterior; general overlap inference is tracked in
[#77](https://github.com/rTreutlein/PeTTaChainer/issues/77).

Let d=m-1, p be the population rate and g_j the live positive TVs of distinct
nonempty pair intersections. Consider denominator corrections on the log-odds
scale: d*logit(p), each d*logit(g_j), and
sum_j logit(g_j) - (number_of_g_j-d)*logit(p). The homogeneous separator bounds
include every choice of d available separators without enumerating trees; the
last candidate is an inclusion-exclusion approximation. Missing estimates are
omitted, with a minimum unresolved range of one natural log-odds unit:

    R = max(1, max(corrections)-min(corrections))
    c_reported = c_population_merge / (1 + R*R)

The minimum allowance also covers unknown interactions and complements, for
which a positive separator TV does not define the branch's conditional class.
It limits confidence to at most half the previous conservative confidence even
when available candidates agree. Larger disagreement lowers confidence further.
No candidate is selected as the strength, and this discount does not change
kappa or specificity shrinkage. Ordinary disjoint learned modes and
same-condition revision do not receive this model discount.

For AB, BC, AC strengths .7/.8/.9, live A=.4, B=.5, C=.6 and population=.25,
the population answer remains 756/757=.9986789960. The candidate corrections
A+B, A+C, B+C, population twice, and inclusion-exclusion give respectively
.9921259843, .9882352941, .9824561404, .9986789960, and .9655172414. The
implemented homogeneous bounds include all five: the extreme odds are 756
and 28, so R=ln(27)=3.2958368660. The confidence multiplier is
1/(1+ln(27)^2)=.0842989735; a population merge capped at .99 reports
.0834559838. In the regression at k=800 with 98 population observations
and rule confidence .99, the existing population variance and intermediate
confidence cap give .6011680080; the discount reports .0506778460. These
candidate values illustrate unresolved modeling choices; the marginal rule TVs
do not determine the joint answer.

### Cost

- Adding a certain fact: one indexed lookup of the forward rules concluding
  it, and one row when two or more do.
- Merging two forward views: one indexed lookup of the consequent's tally
  (and of its pending outcomes).
- Scoring: each outcome once, one stored-fact lookup per rule concluding it
  and a few arithmetic operations per mode; constant per outcome.
- State: one tally row per consequent predicate, and pending outcomes until a
  merge reads them.
- Sibling correction compares original condition pairs and searches retained
  general references for that key. It starts no new inference and adds no
  persistent store; its work is bounded by the key's contributing views.

### Limits

- **Interactions.** No mode represents an antagonistic pair or any effect of
  the combination itself; per-combination hypotheses
  (`combination_hypotheses.md`) are the extension, and the mode is what they
  would be smoothed towards.
- **One mode per predicate.** A predicate whose consequents mix relations
  (signs for some arguments, redundant copies for others) gets one mode.
- **Scored only from stored antecedents.** Views read off derived antecedents
  are combined by the mode learnt from stored ones.
- **Stated rule truth.** Scoring applies rules with their stated truth; a
  rule refined later is not scored.
- **Outcomes stored before their rules** are not counted.
- **Noisy copies.** Redundant evidence that is neither identical nor
  independent is best served by revision of the three, and stays there.

## Public API

None. The mode is on by default: it changes nothing until outcomes favour
another mode by a Bayes factor of 10, and only views that would otherwise
revise are combined. See Results for the benchmarks that justify the default.

## Results

`tests/metta/test_combination_modes.metta`: two rules into C, 60 sampled
cases each, a new case with both antecedents true.

| data | scores (revision / odds / noisy-OR) | mode | answer |
|---|---|---|---|
| signs | -18.92 / -12.19 / -19.12 | odds | 0.916803 = logit⁻¹(logit 0.7083 + logit 0.6316 − logit 17/62) |
| causes | -27.38 / -20.00 / -19.68 | noisy-OR | 0.937009 = 1 − (32/62)(0.1501 / (32/62))(0.2166 / (32/62)) |
| copies of one antecedent | -18.25 / -20.39 / -37.98 | revision | 0.7083 |
| signs, first 10 cases | -2.88 / -1.17 / -2.80 | revision (factor e^1.7) | 0.66995 |

The chainer's values equal a Python replay of the rule to 10⁻¹⁵.
`test_hypothesis_rules.metta`'s correlated hypotheses stay at 0.794: their
views share the samples.

### CombiNet

ChainerGame `supply-network` 9cfb585, small world (history H, then 5 rounds
of 5 cases, one consequent per relation), seeds 1–3, error against the exact
posterior; the Python references on the same runs, master d4f390d2 against
this branch.

| rates, H | n | revision | Python mode | master | branch |
|---|---|---|---|---|---|
| true, 30 | 2 | 0.069 | 0.059 | 0.077 | 0.078 |
| | 3 | 0.095 | 0.046 | 0.095 | 0.081 |
| | 5 | 0.141 | 0.068 | 0.141 | 0.107 |
| true, 200 | 2 | 0.075 | 0.035 | 0.081 | 0.044 |
| | 3 | 0.106 | 0.045 | 0.107 | 0.062 |
| | 5 | 0.140 | 0.059 | 0.140 | 0.089 |
| learned, 30 | 2 | 0.104 | 0.100 | 0.109 | 0.109 |
| | 3 | 0.139 | 0.097 | 0.139 | 0.115 |
| | 5 | 0.164 | 0.155 | 0.164 | 0.146 |
| learned, 200 | 2 | 0.090 | 0.059 | 0.095 | 0.065 |
| | 3 | 0.114 | 0.069 | 0.114 | 0.073 |
| | 5 | 0.150 | 0.084 | 0.150 | 0.098 |

Per relation, rates true, history 200 (n = 2, 3, 5 together): signs 0.125
→ 0.012 (Python mode 0.002), causes 0.114 → 0.049 (0.003), redundant 0.075
→ 0.075, interacting 0.122 → 0.124.

The chainer approaches the Python mode as outcomes accumulate, and with
learned rates it is within 0.01 of it at history 200. Two things keep it
behind with true rates, measured by replaying the chainer's rule in Python
(it reproduces the branch's numbers to 0.003):

- **The prior.** The Python mode reads the true base rate, which the rules
  are consistent with. The chainer estimates it from the outcomes; an error
  dp is multiplied by the number of views in the product modes (noisy-OR:
  (1 − p)^(1−k)). With the true rate, the replay gives 0.035 / 0.047 / 0.059
  at history 200. Priors implied by the rules (u P(A) + v (1 − P(A)), P(A)
  from the stored antecedents) were no better (0.047 / 0.063 / 0.068).
- **The threshold.** A Bayes factor of 1 instead of 10 gives 0.063 / 0.069 /
  0.101 at history 30 (0.075 / 0.080 / 0.107 with 10), and the same at
  history 200: the threshold costs only while outcomes are few, which is its
  purpose; 3 is between, 30 slightly worse.

Where the product modes overshoot (estimated rates, few outcomes) the scores
keep revision, as for the Python mode; at n = 5 with 30 learned cases the
chainer (0.146) is better than both revision and the Python mode.

### No regression

`bench/compare.sh d4f390d2 <branch> --full` (SupplyNet stages 1, 2, 3 timed
and untimed, seeds 1–4, budgets 50 and 100; regions; StationOps temporal
replay seeds 1–4 at budgets 25 and 50; scale; CombiNet n = 2, 3, 5): every
accuracy number outside CombiNet is identical, and the StationOps belief
streams are identical. None of those knowledge bases has a predicate whose
outcomes favour a product mode by a factor of 10. Suite times are within
±3%. CombiNet n = 3 and 5 improve (0.090 → 0.074, 0.128 → 0.107); at
n = 2, seed 1 the redundant consequent chose a product mode from 30 cases
(0.029 → 0.064, the overall 0.084 → 0.092 while Brier improves 0.1758 →
0.1727): noisy copies are none of the three modes, and the Python mode
errs the same way there (redundant 0.077 against revision's 0.066 at
history 30).
