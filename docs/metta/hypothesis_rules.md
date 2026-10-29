# Hypotheses as refined rules

Status: built, October 2026 (see Results).

## Problem

A client that can propose candidate implications (a pattern miner, a person,
a benchmark generator) wants the chainer to confirm or reject each from the
data, and to use the confirmed ones. Finding good candidates is the hard
part and stays outside the chainer; this note covers what happens once a
candidate is stated:

    (: h17 (Implication (Late $s r1) (Late $s r2)) (CTV (STV 0.5 0.02) (STV 0.5 0.02)))

stated as a CTV, so the data decides both P(B|A) and P(B|¬A), in a knowledge
base with `set-rule-refinement` on and a small evidence parameter
(`set-evidence-confidence-k`): with the default k = 800, n samples give
confidence n/(n+800), so a hypothesis would need hundreds of cases.

## What exists

Rule refinement (`set-rule-refinement`, LANGUAGE_SPEC "Refining rules from
their instances") already does the statistics:

- A refined rule's truth is the goal `(RuleTruth (Implication ...))`. The
  stored truth is its axiom proof, and the fold of the rule's instances is a
  second proof; revision merges the two.
- **Samples.** An instance is a binding where the antecedent holds and the
  consequent's truth is known. A false consequent (`STV 0 1`) is a negative
  sample; an unknown one is not a sample. The rule's own derivations never
  count.
- A weak prior, like the one above, gives way to the first few samples.
- Facts added later join the fold the next time the goal is read.
- The rule applies with the merged truth, backward, inverted and completed
  onto a conjunct of its antecedent (before October 2026 a completion read
  the stated truth; fuzzer seed 13000041).

So a hypothesis is an ordinary rule with a weak prior. What is missing is
what makes many such rules affordable and useful.

## Gaps

1. **The search does not see what a rule is worth.** A rule's expected
   confidence (`rule_expected`, read by `sk-join-score`) is computed once,
   when the rule is stored. For a refined rule it does not depend on the
   rule's truth at all. A hypothesis stated with `(STV 0.5 0.05)` and an
   established rule with `(STV 0.9 0.9)` both get 0.99 for modus ponens and
   0.9 for the inverse. Every hypothesis, confirmed or rejected, is expanded
   as eagerly as an established rule, so a hundred candidates cost a
   hundred rules' search.
2. **A rejected hypothesis keeps running.** A hypothesis whose refined truth
   says P(B|A) ≈ P(B), with confidence, adds nothing beyond the base rate,
   but it is still applied and still adds near-base-rate conclusions.
3. **Its truth is only refreshed when it is applied.** The fold reads the
   facts, but runs only when something reads `RuleTruth`. If gaps 1 and 2 are
   fixed by scoring weak or uninformative rules low, a hypothesis that is
   rarely applied is also rarely re-evaluated, and data that would confirm it
   goes unread.
4. **Forward chaining uses the prior.** Forward runs fire a refined rule with
   its stored truth (LANGUAGE_SPEC), so a hypothesis's forward conclusions
   carry its guess, not its evidence.
5. **Overlapping hypotheses.** If `A→C` and `B→C` are both confirmed from the
   same cases, and A and B are correlated (for example, through a common
   cause), applying both to a new case may count the same evidence twice.
   Whether the evidence tracking catches this for rule-truth evidence is
   unknown.

## Design

### Score a rule by what applying it can add (gaps 1, 2)

A refined rule's expected confidence is read from its current truth instead
of being fixed at storage:

    rule score = c(truth) · informativeness

- **Confidence:** the rule truth's confidence, from the `RuleTruth` key's
  value when it has one, else the axiom's.
- **Informativeness:** how far the rule moves its conclusion from what is
  known without it. For a CTV, that is |P(B|A) − P(B|¬A)|; for an STV,
  |P(B|A) − P(B)|, with P(B) the consequent's base rate when known. It is 1
  until a base rate is known.

A confirmed hypothesis rises to an established rule's score. A rejected one
(confident and uninformative) falls towards 0 and is reached only with budget
left over, which is the same graded treatment the dormancy and search-gain
work chose over a settled flag: a later query with much more budget can
still reach it. The score is read where `sk-rule-score` reads it now: a
cached value per rule, updated when the rule-truth key's value changes (the
same moment views are re-merged). Rules that are not refined keep the stored
score.

### Review hypotheses explicitly (gap 3)

The client asks for the hypotheses' truths, as it asks for beliefs:

    (query-many 0 kb ((: $p (RuleTruth (Implication ...)) $tv) ...))

Folding a rule's instances is the work, and the client decides when it is
worth doing: after a round of new labelled data, for the hypotheses whose
antecedent or consequent statements gained facts. Zero search budget is
enough, since the fold reads facts and needs no expansion. The answer is
also the client's report: a hypothesis's strength, confidence and
informativeness.

### Forward chaining with the refined truth (gap 4)

A forward run fires a refined rule with the `RuleTruth` key's current value
when it has one, and with the axiom otherwise. A forward run never folds:
folding stays with the reviews of gap 3, so forward cost does not grow with
the number of samples.

### Overlap: test first (gap 5)

Write the test before designing anything. Two correlated antecedents (both
caused by S, which the KB does not mention), hypotheses `A→C` and `B→C`, and
a new case with A and B: compare the chainer's answer with P(C|A,B) from the
generating model. If it double counts, the candidate fix is to give both
rule truths the shared consequent facts as evidence, so the existing
evidence-overlap check sees that the two applications are dependent.

## Evaluation

1. Unit tests:
   - a weak hypothesis with enough positive samples reaches the score of an
     established rule, and one with samples at the base rate falls below it;
   - with a small budget, a query reaches the confirmed hypothesis's
     conclusion before the rejected one's;
   - a review with budget 0 refolds after new facts;
   - a forward run uses the refined truth;
   - the overlap test of gap 5.
2. Full suite, StationOps unchanged: its refined rules are established ones
   whose score barely moves.
3. SupplyNet, hypothesis stage (ChainerGame `docs/supply_network.md`):
   - true, spurious (common-cause) and noise candidates;
   - convergence of each one's truth;
   - search share spent on rejected ones;
   - decision gain once the true ones are confirmed.

## Results

Built as designed, with these findings from probing the existing code:

- **Gap 3:** a review needs a small budget, not 0. Budget 0 answers with the
  axiom only, because the fold node is not expanded.
- **Gap 4 was already fixed:** since forward and backward chaining were
  unified, a forward run reads the truth goal's current value. LANGUAGE_SPEC
  is corrected.
- **Gap 5, equal samples (October 11).** Two hypotheses confirmed through
  perfectly correlated antecedents each learn the single hypothesis's truth
  (0.797, c 0.669), but applied to one case their views revised as
  independent: c 0.802 against 0.669 for one. Their instance folds now keep
  a digest of their samples, and two applications of refined rules with
  equal digests are one view (overlap_conditioning.md, "Sample twins"):
  (C new) is 0.797, c 0.669. Antecedents that agree on most but not all
  cases still revise as independent; their joint estimate would be a rule
  over both. The confidence 0.671 first reported here was the stale-truth
  bug below: one view read its rule's prior.
  The ONA reversal task (ChainerGame `onabench.mts`, sample-pairs space)
  fell from 0.700 to 0.650 with this change, seeds 2 and 7 only. Its
  hypotheses come in twins ((Sample A1) with (LeftStim B2) or with
  (RightStim B1)), and an op without a hypothesis for the trial answers its
  population prior. Seed 2, trial 104: the twins' 14 samples gave right
  c 0.966 (28 counted) before and 0.933 now, against left's prior from 17
  stored rewards, (0.994, 0.944); the agent tried left once, and that
  failure later held the reversed rule at 0.5. The rewards are stored only
  for the op the agent chose, so the prior is biased by its choices; the
  chainer's answers are the right ones for the facts it has. With desires
  read only through hypotheses matching the trial, both versions decide
  alike: reversal 0.681 (0.778 with change detection at 1e4), conditioning
  0.938, identity matching 0.956.
- **Cross-feeding (October 2026).** A hypothesis's samples read the
  consequent's merged value, which included the other hypotheses'
  derivations (the samples of A→C held `(merge/revision c1 (by hB b1))`).
  Besides counting the other hypothesis's samples again, this made each
  truth depend on every instance the other hypotheses predict, and a rule
  applied to such an instance may not read a truth depending on it: it read
  an older truth, the prior when the first review came before any
  observation, for ever (ChainerGame `benchmarks/ona/repros/
  stale_after_early_review.py`; conflicting sources, problem 6). Now:
  - a sample reads no value that depends on a refined rule's truth (the
    sample row excludes every `RuleTruth` key of its KB);
  - a rule applied to an instance whose own sample is in the fold (an
    observed but uncertain consequent, or one derived by given rules) reads
    the truth folded again without the samples depending on it (leave one
    out, `sk-admit-step`), instead of an older version;
  - a rule application depends on its truth's key, not on the samples
    below it, so views through rules learned from one history are not
    dependent through that history (SupplyNet learned rules: the storm
    persistence chain dropped the next period's blocking report, 0.212
    against 0.925 now, `test_refined_rule_reads.metta`).

  The result no longer depends on when the rules were reviewed, and clients
  need not review before adding a round's facts. A leave-one-out read folded
  the rule's instances again, O(instances) for each reader whose instance is
  a sample (now a subtraction, see "Instance tallies"); rows reading through
  a rule's truth no longer see the truth's samples in their dependencies, so
  a deeper reader is not protected from its own sample through the
  parameter.
- **A CTV refined rule now learns its negative branch** from the instances
  whose antecedent is false (`ImplicationInstanceAcc`, finish
  `implication-instance-ctv`), with their count as its confidence; from the
  base rates only while there are none. Reading it off the base rates, as
  first built, was biased and stayed at confidence about 0.2 whatever the
  sample (ChainerGame conflicting sources: an expert's "down" claims read
  0.00 against an empirical 0.33, and 47 of an echo's still gave c 0.23).
  A rule whose antecedent never held learns the negative branch too, its
  positive branch at confidence 0 (SupplyNet learned rules: late-s10
  rules with 3 of 59 negative samples late stayed at their prior).
- **Antecedents of three or more parts** are sampled: their truth values
  multiply pairwise, as a lowered antecedent does (AndFormula is binary;
  before, three parts gave no sample).
- **A score of 0 starved reviews.** With a zero factor on every hypothesis,
  the second review in a knowledge base folded nothing; the factor has a
  floor of 0.01.

`test_hypothesis_rules.metta`, with B depending on A (0.8 against 0.2) and
C unrelated, 20 cases, k = 5:

| | learned truth | score |
|---|---|---|
| before review, both | prior (0.5, 0.02), both branches | 0.0099 (floor) |
| A→B, confirmed | P(B\|A) 0.797 (c 0.669), P(B\|¬A) 0.203 (c 0.669) | 0.393 |
| C→B, rejected | 0.5 on both branches (c 0.669) | 0.0099 |


## Specificity (October 2026)

A rule predicts its condition's average. Before lifting or combining original
rule views across classes, equal conditions first pool their estimates. A
syntactically narrower applicable condition takes precedence over
a containing condition. Complement containment reverses the ordering. Mined
parent/child rules use the same relation; applicability counts and confidence
do not order different conditions. Semantic subsumption is not extended.

The comparison uses the original views, before a learned `combination odds`
proof can hide the singles. A derived implication's application includes the
conditions under which that implication was derived, so `A -> (B -> C)` and
`(A AND B) -> C` have the same class. Compatible premise reads perform the same
selection after filtering evidence.

A containing general class supplies the specific estimate's prior under
[the common definition](prior_definition.md). Only independent estimates of the
same containing class revise. Nearest incomparable containing classes form an
equal distribution mixture; their disagreement increases centre variance rather
than confidence. Select the nearest classes first, then recompute learned
generals without the specific estimate's training observations using the
incremental tally. Omit a selected general only when that read is impossible;
an overlapping nearest class never promotes its ancestor.

The proof `(specializes specific general raw-tv prior-tv)` records the original
estimate and centre. The general class supplies a parameter and refresh
dependencies, not new likelihood evidence. At k=1, general (.25,.7) supplies zero
weight at default κ=.2, so specific (.99,.4) reads .99. The earlier fixed-weight
.81923 example no longer applies. Same-condition independent rules still revise.

Applicable sibling conditions, including a negative branch against a positive
branch, combine rather than competing for a representative. For overlapping
forward rule views the combination uses odds relative to the consequent's
existing outcome tally: `odds(T|A,B) = odds(T|A) * odds(T|B) / odds(T)`.
With no counted outcomes its Laplace prior is .5. Shared uncertain statements
still use the existing budgeted conditioning, and sibling views combine inside
each paid branch. While shared uncertainty is unpaid, sibling estimates revise conservatively
with evidence/dependency unions and confidence capped by the smaller input
confidence. Known shared premises need no uncertainty cut and use odds directly. This retains both estimates without claiming new
independent evidence from the shared part. A proof records both contributing
rules in `combination odds`; confidence never selects between their conditions.
This fallback approximates dependence; it is not a newly inferred joint rule.

Disjoint forward views retain learned combination modes. Ordinary non-rule
proofs retain their existing overlap behavior. The pre-existing derived-premise
generalization path remains for views without literal condition overlap,
including the existing penguin/bird example. This change adds no semantic
subsumption; literal sibling conditions use combination and conditioning.


## Instance tallies (October 2026)

A refined rule's truth was refolded over all its instances whenever a
member changed, by every review that needed it (the review needed every
member), and by every leave-one-out read. Each cost O(instances), so review
time grew with history: SupplyNet learned rules, stage 1 reviews 18 s to
35 s, and 2 to 2.5 times the time at 120 history periods.

An implication instance fold is now a tally, as a base rate is
(`sk-fold-view`):

- **Contributions.** Each sample's contribution to the
  `ImplicationInstanceAcc` sums is kept per member (`&sk_instance_member`)
  and the sums once per fold (`&sk_instance_tally`). The sums are additive,
  so a member that joins or changes replaces its contribution: a take costs
  the members that changed, never the instances.
- **No member dependencies.** The fold's view carries neither member evidence
  nor member dependencies, as a base rate's does not, and is proved by `cpu`.
  Self-support is refused where the samples are read instead: a sample reads
  no value through a refined rule's truth (as before) nor through the
  implication it samples (a derived implication applied to its own instance,
  `test_derived_implications.metta`).
- **Leave one out.** Each member's first take records the statements its
  sample reads (`&sk_instance_read`). A consumer excluding a key reads the
  fold less the contributions of the samples that read that key, a lookup per
  excluded key; a refined rule's truth leaves the sample out for the rule
  applied to the instance by evaluating its fold row again for that reader.
  A sample that depends on the reader's key only through a derived statement
  it reads is not found this way (no case in the suite).
- **Kept current.** Every evaluation, of a query or a forward run, brings
  current each instance fold that rows read and whose members changed, with
  the keys reading it, as it does a root's (`sk-instance-checks!`): a fact
  absorbed for the next query starts the sample rule's joins, the new or
  changed sample is computed and taken, and the truth and its search score
  move, whatever the query asks for. The members are needed again at the
  depth of a root's, and the fold's readers as roots, so their rows are
  computed in full and their stale rows brought current. A member whose rows
  the evaluation could not compute waits for the next one. A fold nobody read
  yet takes all its members when first read. A sample whose consequent a
  deterministic rule derives from certain facts, such as the unchosen
  operation's outcome under `(Implication (Reward left $t) (Reward right
  $t)) (CTV (STV 0 1) (STV 1 1))`, is taken the same way: the determined row
  is computed when it is built (runtime_design_assumptions.md, "Determined
  rows").

So a review is a read: once the first query that reads a rule's truth has
folded its instances, later reviews compute nothing
(`test_instance_tally.metta`: a new instance costs three row computations
after 4 instances as after 16, a budget-0 query about an unrelated fact
takes it, and the review after it computes no row).

**Clients.** A review is no longer work, only a read: a client needs one
review per rule, the first read that folds its instances, and after that
reads the truths, all in one query of no budget, before the queries that
should be scored with them (the search reads a rule's score from its truth
at the walk, before the evaluation that brings the truth current; leaving
out the read cost SupplyNet stage 2 0.0735 -> 0.0769). ChainerGame
`forward-folds` makes SupplyNet's learned backend, the conflicting-sources
backends and the ONA matching-to-sample agent do so.

SupplyNet learned rules, seeds 1-4, 30 rounds, budget 100 (posterior error,
seconds per round; the supply-network client reviews every rule each round with 200
steps):

| stage | history | d1aed361 (master and 5846dc43), reviews | tallies, reviews | tallies, one read per round |
|---|---|---|---|---|
| 1 | 30 | 0.0244, 1.22 s | 0.0244, 0.90 s | 0.0244, 0.59 s |
| 2 | 30 | 0.0750, 1.26 s | 0.0756, 1.14 s | 0.0735, 0.80 s |
| 3 timed | 30 | 0.0688, 1.75 s | 0.0687, 1.66 s | 0.0685, 1.15 s |
| 3 untimed | 30 | 0.0677, 1.75 s | 0.0684, 1.66 s | 0.0676, 1.16 s |
| 1 | 120 | 0.0152, 3.07 s | 0.0152, 1.61 s | 0.0152, 1.11 s |
| 2 | 120 | 0.0494, 2.88 s | 0.0484, 1.83 s | 0.0464, 1.45 s |
| 3 timed | 120 | 0.0432, 3.79 s | 0.0424, 2.52 s | 0.0421, 2.05 s |
| 3 untimed | 120 | 0.0406, 3.84 s | 0.0410, 2.49 s | 0.0406, 2.10 s |

The per-round read of all 26 stage 2 truths takes 0.13 s with 30 history
periods and 0.155 s with 120 (seed 1); d1aed361's reviews 0.76 s and 2.18 s.
What still grows with the history is the first review, which folds every
instance once (4.4 s and 26 s), and the queries themselves (0.55 s and
0.66 s per round). Raw runs: `bench/results/forward-folds/learned/`.


## Regimes (October 2026)

Status: built, on by default (`set-rule-change-hazard`, default 0.0001).
It replaced a hard change detector (master 90bddc6e..1d01ad71, opt-in
`set-rule-change-detection`), described at the end.

**Problem.** A tally weighs every sample alike, so a rule whose world changed
keeps its old rate until new samples outnumber the old ones. In ONA's
reversal task (ChainerGame `onabench.mts reversal`: matching-to-sample
trained for 20 blocks, then the mapping reversed for 20 feedback blocks and
tested again) the PLN agent kept the trained choice through most of the
reversal. The hard detector fixed that by cutting: once the Bayes factor of
the recent samples' having a rate of their own passed a threshold, the tally
kept only them. The cut was irreversible, the threshold a knob (100 fired
falsely on SupplyNet, 10^4 was safe), and the old samples were lost even when
the old regime came back.

**Model.** Each branch of a rule, P(B|A) and P(B|¬A), has a rate that is
constant between change points nobody announces; each sample starts a new
regime with the prior probability h, the hazard. A branch keeps its samples,
in arrival order, as at most three segments, each the additive sums
(Σ strength·mass, Σ mass) of its samples:

- an **old** regime (once a change was accepted),
- the **current** one,
- a **candidate**: the run of samples since a possible change.

The hypotheses are the assignments of the segments to regimes, as restricted
growth strings over the segments in order: no change (one regime), one
change at either boundary, two changes, and a regime that returns (old and
candidate one regime, the current one between them). A hypothesis's prior is
1 − h per boundary without a change, and h per change, split evenly between
a new rate and each earlier regime it may return to; its likelihood is the
product over its regimes of the Beta(½, ½) marginal likelihood of their sums,
so it does not depend on the order of samples within a segment. With at most
three segments there are at most five hypotheses.

**Truth.** The branch's evidence is the posterior mixture over the
hypotheses of the newest sample's regime: strength the posterior mean of the
hypotheses' strengths (Σ w / Σ m of the regime), mass the posterior mean of
their regimes' masses, the evidence the estimate stands on. With one segment
(no candidate open) it is that segment's sums exactly. On samples of one
rate the no-change hypothesis takes all but about h times the candidate's
Bayes factor of the posterior, so the truth is the all-evidence one up to
that weight; nothing is forgotten, unlike exponential decay.

A moment-matched mass (the Beta of the mixture's mean and variance) was
tried first and rejected: a hypothesis of weight 7·10^-4 whose mean is far
from the others' (two failures at the end of 200 samples at 0.75) cut the
mass from 200 to 160, so stable worlds lost confidence whenever a candidate
was open. The mean mass moves by the weight only (199.88).

**Segments, constant cost per sample.**

- A new sample joins the candidate. The candidate starts where a change is
  most probable among two points (Page's CUSUM, the maximum over start points,
  here over two): its first sample, or the new sample alone if that departs
  further, by Bayes factor, from everything before it. Without this a candidate
  that started at a few odd samples could never merge or become a regime, and
  a later change would be appended to it.
- A candidate whose Bayes factor for a rate of its own is at most 1 merges into
  the current segment (no change), and a new candidate starts.
- A candidate that the posterior more probably than not puts in a regime of
  its own becomes the current segment. If an old segment is already kept, two
  of the three must merge first: the pair the posterior most probably puts in
  one regime, adjacent or not, if more probably than not. The old regime and
  the new one merge when the old one returned (**recurrence**: its evidence
  counts at once instead of being relearned). If no pair is one regime, the
  older segment least probably in the newest one's regime is dropped; that is
  the only loss of evidence, and it needs three distinct regimes.
- Each member records its segment per branch (`&sk_instance_member`). A
  merged segment's id leaves an entry in `&sk_instance_regime` pointing to the
  survivor, which keeps the larger segment's id (union by size), so a member's
  chain grows only logarithmically and is shortened whenever the member is
  rewritten. A member whose sample changes replaces its contribution in the
  segment that holds it, and is not scored again; a leave-one-out read takes
  the reader's sample out of its segment and computes the mixture again.
- h = 0 keeps one segment per branch, every sample in it: the values without
  regimes.

Two drafts were rejected on the same reversal (12 successes, 8 failures, then
successes):

- Each sample a segment of its own, and at four segments the pair with the
  largest Bayes factor for one rate merged. One returning success matched the
  12 successes as well as two failures matched each other, merged with them,
  and the truth jumped to 0.95, although one success after 8 failures is far
  more probably noise than a second change (prior h²/2). Merging the pair the
  posterior most probably puts in one regime fixed that, but then the
  segments went to the uncertain boundary of the first change (was the 12th
  success already the new regime?) and the returning successes were merged
  into the failures: once merged a boundary is gone, so the return was never
  found. A candidate run keeps the newest boundary, the one that matters for
  prediction.

**Default hazard.** 0.0001: one change expected in 10^4 samples of a branch.
A rule in a long-lived KB sees at most thousands of samples, so a change is
a priori unlikely within its life, and the posterior favours one only at a
Bayes factor near 1/h = 10^4: the setting at which the hard detector cost
nothing on SupplyNet and kept most of the reversal gain (on samples of one
rate a candidate's factor passes 10^4 with probability at most 10^-4, Ville's
inequality). A KB whose world is known to change more often sets a larger
hazard; two changes within a few dozen samples (reversal and its return) need
h near 0.01 to be believed quickly.

**Results.** Branch soft-regimes (272d99ac) against master d395f3a2.

ONA matching-to-sample (ChainerGame `onabench.mts`, harness hypotheses,
sample-pairs, k = 1, budget 200, seeds 42 and 1-9). Score is the mean of the
scored test phases; phase columns are mean block scores; criterion is the
first block of a feedback phase answered all right (21: never in 20 blocks).
"master 1e4" is the hard detector at its recommended setting.

| outcome evidence | task | h = 0 | default 1e-4 | 1e-3 | 1e-2 | master 1e4 |
|---|---|---|---|---|---|---|
| none | reversal score | 0.650 | 0.769 | 0.797 | 0.881 | 0.756 |
| none | reverse blocks | 0.075 | 0.326 | 0.361 | 0.490 | 0.304 |
| none | retest | 0.300 | 0.537 | 0.594 | 0.762 | 0.512 |
| rule | reversal score | 0.738 | 1.000 | 1.000 | 1.000 | 1.000 |
| rule | reverse blocks | 0.044 | 0.798 | 0.847 | 0.900 | 0.778 |
| rule | blocks to criterion, reverse | 21 | 5.1 | 4.1 | 3.0 | 5.8 |
| none | conditioning, identity matching | 1.000, 0.956 | same | | | |
| rule | conditioning, identity matching | 1.000, 1.000 | same | | | |

h = 0 reproduces master without detection (0.650, 0.738). Conditioning and
identity matching score the same at h = 0 and at the default. The default
beats the hard detector in every reversal column, and a larger hazard, the
prior of a world that changes often, does better still.

Recurrence (`rereversal`, a ChainerGame task added for it: the trained
mapping returns for 20 feedback blocks after the reversal, then a final
test): with outcome evidence `rule`, blocks to criterion in the return phase
equal those of the reversal (default 5.0 against 5.1, 1e-3 4.0 against 4.1,
1e-2 3.0 against 3.0; h = 0 7.3 against never). The agent decides on the
strength crossing 0.5, and the return is believed when the posterior accepts
a second change; merging the old regime then raises the rule's confidence at
once (test_rule_regimes.metta: 15 cases at the third returning sample instead
of 3) but does not move that crossing. With outcome evidence `none` the
return is slower than the reversal at every hazard (0.464 against 0.326 block
score at the default, 0.351 against 0.490 at 1e-2): the agent's exploration,
not the rule, limits it: an op that failed is tried again only when the
policy babbles.

Stable worlds, default against master:

- SupplyNet learned rules, stages 1-3, seeds 1-4: mean posterior error
  0.0244, 0.0706, 0.0644, 0.0629 → 0.0244, 0.0706, 0.0644, 0.0630; 218 of
  489 final rule truths differ, by at most 0.010 in strength and 0.0023 in
  confidence (a stage 3 rule `(Degraded mine $p)` over NextPeriod: 0.7484 →
  0.7382, its samples in period order). Each run's error moves by at most
  1.1·10^-4.
- Conflicting sources size l, pln-sources and pln-likelihood, seeds 1-4,
  4 steps per query: posterior error moves by at most 3.4·10^-4 (pln-sources
  seed 4, 0.35341 → 0.35375).
- Shuffled stable histories (test_rule_regimes.metta): 200 samples at 0.75
  in three random orders give strength and mass within 0.1% of all samples;
  32 shuffled instances through the chainer give exactly the one-regime
  truth.


**Rejected alternatives.**

- **Exponential decay** of the tally's sums per new sample: it forgets on
  stationary data too, so a rule's evidence never exceeds 1/(1−λ) samples,
  and λ is a time scale each task would need tuned.
- **Full Bayesian online changepoint detection** (a posterior over every run
  length) costs a step per run length kept; truncated to the last two change
  points it is this model.
- **The hard detector** (until October 2026): each branch scored its recent
  run, as samples arrived, once as more of the tally's rate and once as a rate
  of its own (Page's CUSUM with a Bayesian alternative); when the log Bayes
  factor passed the threshold (10^4 recommended) the tally kept the run alone,
  and the earlier samples never counted again. Reversal 0.650 → 0.756 at 10^4
  (0.738 → 1.000 with counterfactual outcome evidence); identical on
  SupplyNet's learned rules at 10^4, false alarms at 100.
- **Treating a changed sample as a new one.** In SupplyNet a sample's value
  moves whenever its consequent's merged value does; scoring every move would
  count one sample many times.


## Mining hypotheses (October 2026)

Status: built, opt-in (`set-hypothesis-mining`); evaluation below.

Until now a client had to state every hypothesis (the ONA matching-to-sample
harness creates them in Python). A KB with mining on proposes them itself
from the facts added to it, keeps the ones that predict and drops the rest,
as ONA forms, revises and forgets its implications.

### Proposing (`runtime/hypothesis_mining.metta`)

**Time.** A fact is grouped and ordered by the time it refers to, never by
the order it arrives in: a late shipment reported two periods after it
left, or a storm labelled once its period resolves, still belongs to its
period. The client declares where each mined predicate sits in time:

    !(set-time-link kb NextPeriod)        ; (NextPeriod earlier later)
    !(set-predicate-time kb Storm 2 0)    ; time point at argument 2, layer 0
    !(set-predicate-time kb Blocked 2 1)
    !(set-predicate-time kb Late 2 2)

A time declaration also changes inference: the declared predicate's ground
statements become stages, which inversions and completions update only from
evidence below them, never from a forward prediction (#122,
`prior_factored_merge.md`, "Stages and aggregates"). Declare before adding
rules and querying.

Only declared predicates are mined; a link fact is recorded under the two
time points it links and is not mined itself. When the link arrives after
observations, it also joins observations already indexed at its two endpoints,
including false outcomes, without recounting or recording those observations
again. Replay uses the same feature builder and observation order as ingestion,
including the same-period context used to decide whether a temporal candidate
recurs. The work is bounded by the facts at those endpoints and the feature and
proposal caps, rather than the history. Causes precede effects:

- across a link, the fact at the earlier time point is the antecedent, with
  the link as a conjunct;
- within a time point, time cannot order a pair, so the declared **layers**
  do: a fact of a lower layer is an antecedent of one of a higher layer,
  and facts of one layer are not related (two routes of a region, two late
  shipments).

`compileadd` of a true or false ground fact of a declared predicate, whose
time argument is a constant, when its KB has mining on:

1. counts the fact in the tally of every consequent pattern it is an
   instance of that already has a hypothesis (the fact with a nonempty set of
   its constants made variables; at most 2^n − 1 lookups): the
   opportunities a hypothesis had since it was born;
2. reads its **features**: the true facts recorded for each of its
   constants (the last 24 per constant), at its own time point or at the one
   a link makes the previous or the next, newest first, at most 24, and, if
   the fact is true (strength above 0.5), records it under each of its
   constants with its time point and layer;
3. builds the candidates, for a true fact in either direction, as time and
   layer order the fact and each feature, whichever arrived first:
   - **pairs**: a fact of the time point concluded from two of a lower
     layer, one of them the added fact (or the added fact from two
     features), and, for two antecedents that share a constant the
     consequent does not have, the relational form with that constant a
     variable too: `(Sample A1 t5)`, `(LeftStim A1 t5)`, `(Reward left t5)`
     give `(And (LeftStim $x $t) (Sample $x $t)) → (Reward left $t)`;
   - **singles**: one fact concluded from one other, at the time point, or
     across a link, `(And (NextPeriod $q $p) (Storm north $q)) → (Storm
     north $p)`. A constant an antecedent shares with the consequent becomes
     a variable, but across a link only the two time points do: persistence
     is per entity (below);
4. for a true fact, proposes, singles first, each candidate not proposed
   before whose consequent's predicate is not positive-only (nothing could
   refute it) and whose consequent pattern has fewer than `max-live` live
   hypotheses, until `max-new` are proposed: a pair at once, a single only
   when it **recurs**: seen at another instance of its consequent than its
   first sighting, with other facts below the consequent at its time point
   (generalized alike) than at the first sighting. Where the same facts
   accompany it, the first sighting's pairs explain it as well, so the most
   specific candidates are proposed first and a single only once the data
   show it predicting across contexts. A single with no such facts (or
   concluding a fact at the next time point, whose own are not read) recurs
   at its second instance. Its instance fold reads every earlier instance,
   so a single proposed late loses no evidence. A candidate through a link
   is not proposed once a live hypothesis concludes its consequent from its
   own time point: the present's causes first, the past only for what they
   leave unexplained, as a single only where no pair explains it;
5. for a false fact, proposes the candidates that conclude it in two
   cases:
   - when a live hypothesis concluding it applies to it (its antecedent
     holds of the features): the prediction failed, and the pairs
     concluding it that contain a fact the prediction read can learn where
     it fails (a matching-to-sample agent that learned "right" where the
     right stimulus matches the sample learns that it fails where the left
     one does, its desire there drops, and it explores "left");
   - as a true fact does (a pair at once, a single when it recurs among
     failures), when no live hypothesis concluded the candidate's
     consequent pattern before this fact: a statement that never holds,
     such as an operation that never succeeds, gets hypotheses that learn
     its failure. Without it, a Pong agent mining its hypotheses
     never had one for an operation that never got the ball hit, so its
     desire stayed at the neutral 0.5, above the learned rate of the
     operations that sometimes succeed (ChainerGame
     `benchmarks/ona/repros/mined_never_rewarded.py`).

   Otherwise a false fact proposes nothing: once a hypothesis concludes the
   pattern, what co-occurs with another of its failures says nothing about
   what makes it hold. Sightings are kept per polarity, so a failure never
   counts towards a success's recurrence, nor a success towards a
   failure's.

Since the declared order decides the direction, a candidate's reverse is
never a candidate, and every rule points forward in time, so no set of
hypotheses forms a cycle: a chain through links reaches back only as far as
the history goes. The window is the adjacent time points, and a fact joins
only facts sharing a constant with it, so a fact has at most 24 features
whatever the history's length.

A hypothesis is a refined rule named `hypothesis-N` with a weak prior,
strength 0.5 with the evidence of 0.01 observations (confidence 0.01/(0.01 +
k), so the first samples decide whatever the evidence parameter k): an STV
when a conjunct of its antecedent is positive-only (no instance where it
fails could teach a CTV's negative branch, which would stay at its prior), a
CTV otherwise. So adding a fact costs a bounded number of indexed lookups (24
features give at most 24 singles and some hundreds of pairs and their
relational forms) and at most `max-new` rule compilations, whatever the KB's
size; off, it costs one lookup of the KB's setting.

### Failures (October 2026)

Proposing from failures as from successes (item 5, second case) fixes the
ChainerGame repro (`left`, never rewarded in 6 trials, now has
`(Ball right $t) -> (Reward left $t)` at 0.0008 instead of answering the
population prior 0.34). ONA matching-to-sample, mined (`--mined 8 16`),
10 seeds, master 2307ca50 against the branch: conditioning 1.000 -> 0.981,
identity matching 0.956 -> 0.912, reversal 0.931 -> 0.922. The hypothesis
sets end the same (all 18 pairs). The differences are single seeds (9, 4,
9), where the failure-born pairs exist before the first success and
evidence arrives in another order. Time per trial is +3%, +24% and +18%.
A first version proposed one candidate per failure and let a failure's
sighting count towards a success's recurrence: it proposed uninformative
pairs and many singles (conditioning 0.963, identity 0.912, reversal
0.900).

Porting to mm2-chainer: the miner's step for a false fact gets the same
candidate generation as a true fact, restricted to candidates that conclude
the fact, and gated per candidate on its consequent pattern having had no
live hypothesis before this fact (read the live set once, before proposing).
Sightings for recurrence are keyed by (rule, polarity), so successes and
failures recur separately. The live cap, max-new, the tried set and
recurrence stay shared.

### Reviewing and dropping (`runtime/hypothesis_review.metta`)

`review-hypotheses` reads the `RuleTruth` goals of the live hypotheses that
apply to a goal, a consequent layer at a time, lowest first, each layer in
one query. The chainer keeps the truths current as instances arrive
("Instance tallies"), so a query has budget only for the hypotheses no
review has read yet: `$steps` for each, which their first read spends
folding their instances; once every hypothesis was read, it has none. The
layers matter for the first read: a fold resolves its consequent's
instances through the hypotheses concluding its antecedent, which are then
read already. In one query, after a SupplyNet stage 1 history (188 live
hypotheses, all pointing forward), it ran out of memory (16 GB) at 200
steps per hypothesis and at 50; a layer at a time it took 82 s and 1.3 GB
(the arrival-ordered miner's 104 hypotheses, whose antecedents were mostly
late shipments with no rule concluding them, took 177 s and 7.8 GB in one
query). Each hypothesis is then judged:

- one whose truth rests on fewer than 4 observations is kept, unless its
  consequent pattern was observed 32 times since it was proposed (its
  antecedent hardly ever holds);
- otherwise it is kept when its strength P(B|A) differs from the
  consequent's probability without it by more than two standard errors of
  that probability over its observations, and from the strength of every
  more general live hypothesis judged in the same review. The variance
  estimate is clamped to a rate
  in [0.05, 0.95] to retain a nonzero SE near 0 or 1; the comparison stays
  centered on the actual general rate, so identical rates stay identical
  at every count. A general
  rule is one whose antecedent conjuncts, under a substitution taking its
  consequent to this one's, are some of this one's:
  `(A $x) → (B $x)` screens off `(And (A $x) (C $x)) → (B $x)`, and the
  relational `(And (L $x $t) (S $x $t))` screens off
  `(And (L A1 $t) (S A1 $t))`. The consequent's probability without the
  antecedent is a CTV's negative branch P(B|¬A), once an instance where the
  antecedent fails taught it; without one (an STV, whose antecedent has a
  positive-only conjunct, or a CTV whose antecedent always held) the first
  test is skipped. The consequent's observed rate is no substitute: it is
  biased by which instances get observed. A matching-to-sample agent's
  rewards come mostly from the contexts it already believes in, so with the
  rate as the reference, perfect hypotheses (strength 0.998 over 4 samples
  against a rate near 0.95) were dropped (identity matching seed 8; the
  scores of 6 seeds did not move, since a more general relational
  hypothesis carried the same prediction); and a tally that started late
  reads near 0.5, against which true SupplyNet late rules at P(late |
  blocked) 0.85 over 7 samples were dropped.

A dropped hypothesis leaves the live set, freeing its slot, and its rules
leave the rule indexes (`withdraw-named-rules!`), with its specialization templates,
so no later fact grounds it again (#114).
Re-adding a withdrawn rule exactly as it was (its name, statement and value)
is accepted (#113) and installs it again: it derives once more, its
specialization included. Another value under its name is rejected.
Withdrawal marks each compiled rule identity retired;
its durable joins cannot extend and its views, cached merges, materializations
and summaries cannot contribute to later reads. Stored proofs keep the distinct
permanent rule identities they used, separately from statistical evidence, so
certain rules are covered too. Retirement does not scan the skeleton or history:
views are checked and affected live rows refreshed when a read needs them. The
historical proof store stays. An uninformative or opportunity-expired hypothesis
is never proposed again. A screened hypothesis instead records one screening
`RuleTruth` key and its own implication. Changes to the screening key queue
one notification; unchanged keys cause no reconsideration. At the next review,
after reading live truths, only notified keys and the current instance folds
of their screened candidates are read. Those retained folds recover the
specific rule's current strength and count even while its executable rule is
withdrawn. If the specific rule now differs by more than two current standard
errors from that general rule, or the general rule was withdrawn, the tried
marker and screening record are removed. There is no stored-strength or
frozen-SE movement threshold.

It may then be proposed by a later ordinary sighting, with a fresh name and
prior, folding its historical instances again. Reconsideration itself allocates
no live hypotheses and bypasses neither `$max-new` nor `$max-live`; a full
consequent waits for a later sighting with room. Repeated notifications coalesce,
and each dropped candidate has only one screening record. Work follows the
changed key's screened candidates, never a scan of all tried candidates.
A general rule is not dropped for its specifics: its view is their prior.

Rejected alternatives:

- **Keep a rejected hypothesis at the search floor** (the graded treatment of
  the score above). It still applies wherever its premises are stored facts,
  which cost no expansion, and its near-base-rate view revises with the
  informative ones: the harness's "all features" space, which states every
  single and pair hypothesis, scored 0.29 against 0.91 for the pairs alone.
  Withdrawing it is resource-bounded forgetting of a proposal the miner
  made, not a retraction of user knowledge.
- **Every co-occurrence at once, singles included, in both directions** (the
  first miner, master 2882ffdb). Singles concluded from one sample misled
  matching-to-sample decisions, and both directions of every pair, applied
  together, counted SupplyNet's evidence twice (evaluation below).
- **Singles only when a fact has one feature** (most specific first, no
  exception). It fixes matching-to-sample (conditioning 0.981 with the
  first miner) but hides SupplyNet's true single rules behind pairs for
  ever; recurrence across contexts proposes them once the data show them.
- **Recurrence for pairs too.** Matching-to-sample then learns from the
  second success in a context only, and the agent, which acts on 20% of
  untrained trials, rarely gets one: 0.542 (conditioning), 0.542 (identity),
  0.385 (reversal), 3 seeds, against 1.000, 1.000 and 0.594 with pairs at
  once.
- **Every false fact proposes** (a failure proposes the hypotheses of its
  context, as the harness does): 0.812, 1.000, 0.521 with pairs at once,
  0.458, 0.802, 0.281 with recurrent pairs, 3 seeds, at twice the time per
  trial: every failure fills slots with hypotheses about what does not
  happen, and in SupplyNet most statements are false.
- **No false fact proposes.** An agent whose only hypotheses say "right"
  never stops trying "right" where it fails often enough to explore "left":
  identity matching 0.812, 4 of 10 seeds near 0.5.
- **A predicted failure proposes all pairs of its context.** In SupplyNet a
  false route with a predicting rule then proposes pairs of every true
  statement of the period: seed 1, 10 rounds, error 0.182 against 0.142
  with the pairs anchored on what the prediction read, and 0.124 with no
  proposal from false facts; 36 s per round over 30 rounds.
- **The arrival order decides the direction** (the miner of master
  f42c380a: the newer of two facts is the consequent, ONA's temporal
  order). In SupplyNet the inspections and late shipments arrive before
  their period's storms are labelled, so 24 of the 29 true rules found on
  seed 1 were reversed (evaluation below).
- **Deciding the direction within a time point by the data.** For two
  statements alone, correlation is symmetric and no statistic of the pair
  tells cause from effect: SupplyNet's storm → blocked (0.8 against 0.03
  without a storm) reverses, at a storm rate of 0.25, to 0.90 against 0.06,
  which is more informative and gains more Brier score. With three or more,
  a v-structure test orients A → C ← B when A and B are independent but
  dependent given C. SupplyNet's true structure has no such collider (each
  route has one storm, each shipment one route): it is a forest of forks
  and chains, Markov equivalent to its reversals, so no test on the data
  can orient it. A PC skeleton and collider search over the periods'
  statements (`bench/results/hypothesis-mining-time/probes/vstructure.py`,
  G-tests at 0.05, seeds 1-4) oriented 1 of 119 true edges correctly and 1
  reversed with the 60 periods a learner sees, 0 right and 2 reversed with
  200, and 2 right and 1 reversed with 1000. The layers are operator
  knowledge of the same kind as the time argument, cost nothing, and hold
  from the first fact.
- **Time points from the link facts alone** ("individuals linked by
  NextPeriod are time points", one declaration and no per-predicate one). A
  fact's time would then be known only once a link names it: the first
  period's facts arrive before the link to the second, and a constant that
  is both a time point and something else is ambiguous. The per-predicate
  declaration states it once and holds from the first fact.
- **Undeclared predicates fall back to the arrival order.** It keeps the
  wrong direction wherever a declaration is missing and mixes two orders in
  one KB; a predicate without a place in time is not mined.
- **Persistence in the general form** `(And (NextPeriod $q $p) (Storm $r
  $q)) → (Storm $r $p)`, as for constants shared at one time point. Its
  fold is recursive over every entity at once: after a stage 2 history its
  first read took 229 s and 2.5 GB, against 7 s for the three regions'
  rules; with the general Late and Blocked persistence rules as well it ran
  out of memory (16 GB), where the 31 per-entity ones took 22 s
  (`probes/persist_probe.py`). Per entity is also what the data says: each
  region has its own rate.
- **Every predicate's persistence through the link.** In SupplyNet stage 2
  a route stays blocked and a shipment late because its region's storm
  persists, so the routes' and shipments' own persistence predicts, the
  review kept it (`(And (NextPeriod $q $p) (Blocked r7 $q)) → (Blocked r7
  $p)` and 8 others after the history), it counted the storm's persistence
  again, and every query recursed through the history per route and
  shipment: a game's rounds grew from 30 s to 460 s by round 10 (error
  about 0.13). With the present's causes first, the history proposes
  exactly the three regions' storm persistence, and its review takes 65 s
  and 1.3 GB instead of 84 s and 6.4 GB.
- **Pairs across a link, or a wider window.** A pair with an antecedent at
  the previous time point, or singles reaching two time points back, would
  find delayed effects of two causes, but multiply the candidates of every
  fact by the facts of another time point. Not needed by any task here.
- **Explaining away and chain reduction in the review**: drop A → C when a
  pair (A and B) → C does not differ from B → C (B screens A off), or when
  the deduction through live A → B and B → C predicts A → C's strength. Both
  drop what they should in unit cases, but changed nothing that matters:
  matching-to-sample scores identical; SupplyNet (seed 1, 10 rounds)
  explaining away dropped 1 more rule at the same error 0.1242 (the pairs
  that would screen are rarely proposed), and chain reduction 15 more
  indirect rules, error 0.1242 → 0.1265, time unchanged. Not kept.
- **Features of the consequent's own predicate, through a link, in both
  directions** (the arrival-ordered miner with the link as a feature): the
  link gave a rule for every predicate, each recursive over the whole
  history, and with the later fact as the antecedent as often as the
  earlier, rules in both directions formed cycles: SupplyNet stage 2 ran out
  of memory (16 GB) before its first round with 10 history periods, and
  held 12.9 GB for 33 minutes without finishing it with 30. Ordered by
  time, every rule points forward and a stage 2 history's review took 65 s
  (above).
- **A consequent pattern seen only once proposes nothing.** It keeps out
  hypotheses such as `(And (Blocked r1 $q) (Storm north $q)) →
  (NextPeriod $q h7)`, whose consequent names a period that never recurs,
  but it delays every first pattern: matching-to-sample 0.797
  (conditioning), 0.555 (identity), 0.586 (reversal) over 4 seeds, against
  1.000, 1.000 and 0.688 on the same seeds. A link predicate is now not
  mined at all (it has no place in time; `set-time-link`).
- **Mining at query time from the journal of added facts.** The journal is
  kept only once the skeleton has expanded nodes, and batching changes
  nothing about the bound per fact.

### Evaluation with time order (October 2026, branch mined-time-direction)

Raw runs, scripts, probes and frozen builds:
`/nexus/Dev/OpenCog/bench/results/hypothesis-mining-time/`. ChainerGame
branch `mined-time-direction` declares the learned-rule predicates' place
in time (Storm and Degraded layer 0, Blocked 1, Late 2, the period in the
last argument; `NextPeriod` the link) in place of declaring `NextPeriod`
positive-only, and each matching-to-sample fact's trial (stimuli layer 0,
reward 1). Same settings as the evaluation below (`--mine-rules 4 8`,
`--mined 8 16`).

**Off.** `bench/compare.sh master <branch> --full --jobs 2`: PASS,
accuracy identical (27 cases on the per-behaviour suites against master
2b75021b; 73 cases on the former suite against 89a2c02c).

**SupplyNet learned rules, stage 1** (30 history periods, 30 rounds,
seeds 1-4; before: the arrival-ordered miner, the evaluation below):

| seed | error before | error after | given | true rules live, before (reversed) | after (reversed) | other live, after | s per round before / after |
|---|---|---|---|---|---|---|---|
| 1 | 0.173 | 0.065 | 0.027 | 29 of 31 (24) | 31 (0) | 81 + 10 pairs with a true parent | 25.1 / 55.2 |
| 2 | 0.167 | 0.107 | 0.019 | 22 of 28 (20) | 28 (0) | 64 + 15 | 21.1 / 24.8 |
| 3 | 0.188 | 0.072 | 0.017 | 25 of 39 (22) | 29 (0) | 64 + 12 | 16.3 / 33.9 |
| 4 | 0.191 | 0.107 | 0.035 | 18 of 21 (14) | 19 (0) | 36 + 7 | 16.4 / 29.0 |
| mean | 0.180 | 0.087 | 0.024 | 94 of 119 (80) | 107 (0) | | 19.7 / 35.7 |

Brier 0.114 → 0.068 (given 0.031, base rates 0.134). Both query kinds
improve (seed 1: blocked 0.177 → 0.061, storm 0.158 → 0.073). The first
round, which reads every hypothesis proposed during the history, takes
35-95 s (before 146-191 s, a layer at a time); later rounds take longer
(the queries apply forward rules whose antecedents are concluded by other
hypotheses, where the reversed ones mostly ended at observed late
shipments): side by side on master 2b75021b under the same load, seed 1
took 104 against 34 s per round and seed 2 40 against 33, with errors
identical to the runs above. The other live hypotheses are cross-entity
co-occurrences of a period (another region's storm concluding a route,
pairs of routes concluding a shipment), now all pointing from cause layer
to effect layer.

**Stage 2** (storm persistence, transits of 1-3 periods):

| seed | error before | error after | given | rounds | s per round before / after |
|---|---|---|---|---|---|
| 1 | 0.147 | 0.145 | 0.058 | 30 | 61 / 374 |
| 2 (first 17 rounds) | 0.258 | 0.242 | 0.097 | 17 | 48 / 544 |

Seed 1 ends with all 26 true single rules live, none reversed, and 2 of
the 3 storm persistence rules (the arrival-ordered miner: 24 of 26 in
either direction, 21 reversed, no persistence, 56 rules through the link
of other kinds), but the error does not move: the storm queries stay far
from the given structure's (storm 0.177, previous storm 0.224, against
0.064 and 0.074). And the rounds grow from 25 s to over 500 s by round 15
and 1000 s on seed 2 (stopped after 17 rounds): the query time grows with the history while the
live set stays near 95 (`probes/round_probe.py`: round 9, 210 s of
queries, 44 s of review), against 0.9 s per round for the given structure.

**Stage 3 timed** (seed 1): stopped after 14 rounds at 1000 s per round,
error 0.175 over them (given 0.074). Not affordable.

**ONA matching-to-sample** (10 seeds, the same master 2b75021b base on
both sides): identical, trial by trial: conditioning 1.000, identity
matching 0.956 (novel 0.963), reversal 0.644 (retest 0.287), at 48, 59 and
76 ms per trial on both. There the stimuli always arrive before the
reward, so arrival order and time order agree.

**What the miner finds and misses.** Ordered by time, it finds the
direction of every rule it finds: SupplyNet's storm → blocked → late
rules, and per-region storm persistence through the link. It still keeps
cross-entity co-occurrences that a review does not drop (they predict, if
weakly), proposes no rule over two cross-period antecedents or across
more than one time point, only predicates with a declared place in time,
and needs the operator's layers within a time point: the data cannot
orient SupplyNet's within-period rules. The cost of the queries that
apply the mined rules grows with the history in stages 2 and 3.

### Evaluation of the arrival-ordered miner (October 2026, master f42c380a)

Raw runs, scripts and summaries:
`/nexus/Dev/OpenCog/bench/results/hypothesis-mining-v2/`.

**Off.** `bench/compare.sh master <branch> --full --jobs 2`: PASS, accuracy
identical in all 73 cases, suite times within +2% (scale 389.1 → 392.2 s,
SupplyNet 295.9 → 296.4 s, replay 26.4 → 26.9 s; a second run 402.7 →
402.8, 311.7 → 311.9, 28.0 → 28.2). Peak memory is unchanged but for scale
l spq16 (1436 → 1519 MB in both runs, 1624 in a third; the other cases
within 2 MB). An added fact pays one lookup of the KB's setting.

**ONA matching-to-sample** (ChainerGame `onabench.mts`, branch
`hypothesis-mining`, 10 seeds, k = 1, budget 200, the same build; harness:
the hypotheses the harness creates, sample-pairs space; mined: `--mined 8
16`, the harness creates none and reviews with `review-hypotheses` of
`(Reward $op t)`):

| task | harness score | mined score | first miner (2882ffdb) | harness ms/trial | mined ms/trial | first miner ms/trial |
|---|---|---|---|---|---|---|
| conditioning | 1.000 | 1.000 | 0.688 | 45 | 60 | 176 |
| identity matching | 0.956 (novel 0.963) | 0.956 (novel 0.963) | 0.944 (novel 0.963) | 62 | 71 | 176 |
| reversal | 0.700 | 0.644 | 0.441 | 55 | 101 | 199 |

The miner now matches the harness on conditioning and identity matching,
the relational identity form included, at 1.1 to 1.8 times its time per
trial (the first miner took 2.2 to 3.2 times the harness's time of then).
In reversal it reaches the harness's test score (1.000) but relearns the
reversed mapping more slowly (retest 0.287 against 0.400). A review is a
read: 26 to 47 ms per trial, against 103 to 121 for the first miner's
per-hypothesis queries.

**SupplyNet learned rules** (stage 1, 30 history periods, 30 rounds,
budget 100, seeds 1-4; given: the learned-rules structure stated with weak
priors; mined: no learned rule stated, `--mine-rules 4 8`, the client
declaring `NextPeriod` positive-only; s per round over all rounds, the
first round in brackets):

| | posterior error | Brier | s per round |
|---|---|---|---|
| given structure | 0.024 | 0.031 | 0.59 (4-9) |
| mined | 0.180 | 0.114 | 19.7 (146-191) |
| base rates (supplynet_learned_rules.md) | 0.239 | 0.134 | |

Seed 1 over 10 rounds, against the first miner: error 0.142 (first miner
0.132, given 0.042) at 28 s per round (first miner 104). The first round
holds the first read of every hypothesis proposed during the history, which
folds its instances (150-190 s); later rounds take 8-18 s (median) against
0.6 s with the given structure: the queries apply 65-100 live hypotheses.

After 30 rounds the miner has found most true rules, in the wrong
direction: seed 1 has 29 of 31 live (5 as stated, 24 reversed), seed 2 22
of 28 (2, 20), seed 3 25 of 39 (3, 22), seed 4 18 of 21 (4, 14), beside 42
to 69 others (a late shipment concluding its route's region's storm or a
neighbouring route, pairs of late shipments). Inspections and late
shipments arrive before the storms and routes they depend on are labelled,
so the arrival order makes the effect the antecedent. The others count
evidence again, and the error is 7 times the given structure's, though
below the base rates'.

**Stage 2** (storm persistence, seed 1, 30 rounds): the mined KB reaches
error 0.147 (given 0.058, base rates 0.183; Brier 0.178 against 0.152) at
61 s per round, growing with the live set (195 at the end, 118 of them
through the `NextPeriod` link, such as `(And (Blocked r1 $q) (NextPeriod
$q $p)) → ...`; 24 of the 26 true rules live in either direction). It
needs the client to declare `NextPeriod` positive-only, which the period
links are: otherwise each period proposes pairs concluding
`(NextPeriod $q <period>)`, whose period never recurs, and the run ran out
of memory (16 GB) before its first round. The persistence rule itself is
not found (rejected above).

**What the miner finds and misses.** It finds one- and two-feature rules
over facts sharing a constant, including the relational identity form, and
the exceptions to a failed prediction. It cannot find: direction (the
arrival order decides it, and in SupplyNet the order is anti-causal); rules
through a link fact over the consequent's own predicate, such as
persistence (rejected above); rules over the same predicate
(`(Blocked r2 $p) → (Blocked r1 $p)`); three or more conjuncts; negations;
and Inheritance or Member facts.

### First miner (October 2026, master 2882ffdb, before instance tallies)

Every co-occurrence at once, singles included, in both directions; each
review a query per hypothesis.

Raw runs: `/nexus/Dev/OpenCog/bench/results/hypothesis-mining/`.

**Off.** `bench/compare.sh 2882ffdb <branch> --full`: PASS, accuracy
identical in all 73 cases, suite times within ±1% (scale 416.2 → 415.0 s,
SupplyNet 307.7 → 307.2 s, replay 26.4 → 26.0 s). An added fact pays one
lookup of the KB's setting.

**ONA matching-to-sample** (ChainerGame `onabench.mts`, branch
`hypothesis-mining`, 10 seeds, k = 1, review budget 200; harness: the
hypotheses the harness creates, sample-pairs space; mined: `--mined 8 16`,
the harness creates none and reviews with `review-hypotheses` of
`(Reward $op t)`):

| task | harness score | mined score | harness ms/trial | mined ms/trial |
|---|---|---|---|---|
| conditioning | 1.000 | 0.688 | 55 | 176 |
| identity matching | 0.956 (novel 0.963) | 0.944 (novel 0.963) | 79 | 176 |
| reversal | 0.700 | 0.441 | 80 | 199 |

The miner finds what the harness states, the relational identity form
included (novel stimuli 0.963 either way), and more: single-feature
hypotheses and pairs over the two comparison stimuli. The singles cost the
score. A single concluded from one sample, `(Sample A2 $t) → (Reward left $t)`
at 0.005 after one failure, applies to a context no specific hypothesis
covers yet, the decision reads it, and the agent stops trying that
operation there (desire 0.10). An ablation that proposes no single when a
fact has two or more features scores 0.981 (conditioning), 0.912 (identity,
novel 0.912) and 0.619 (reversal) at 78, 102 and 83 ms per trial. Once a
specific hypothesis exists, the single is only its prior (specificity), so
the harm is in the order evidence arrives, not in the singles as such.

**SupplyNet learned rules** (stage 1, seed 1, 30 history periods, 10
rounds, budget 100; given: the learned-rules structure stated with weak
priors; mined: no learned rule stated, `--mine-rules 4 8`):

| | posterior error | Brier | s per round | review s (10 rounds) |
|---|---|---|---|---|
| given structure | 0.042 | 0.039 | 1.6 | 12 |
| mined | 0.132 | 0.094 | 104 | 867 |

After ten rounds 28 of the 31 true rules are live (9 of 10 storm → blocked,
19 of 21 blocked → late), and so are 24 of their reverses (inspections
arrive before storms, so `(Blocked r2 $p) → (Storm north $p)` is proposed
and confirmed too) and about 170 others (220 live, 259 dropped). Applied
together, the reverses and the spurious survivors count evidence twice: the
error triples. The cost is the reviews: each live hypothesis's `RuleTruth`
fold is its own query, 0.1 to 17 s each with hundreds of interacting refined
rules (a first review of 436 hypotheses after the history took 406 s). With
`8 16`, the first proposals fill each consequent's slots with whatever
co-occurred first (inspected routes arrive with the period's late
shipments, before its storms), so after the history no storm rule was live
and 15 true late rules had been dropped against a tally that started late
(fixed: the reference is now the learned P(B|¬A)).

### Late-link replay horizon

A newly added true time link replays the observations already stored at its
endpoints, including false outcomes. Replay proposes only candidates involving
that link. Same-period features remain recurrence context; pairs and singles
refused by an ingestion's `max-new` allowance are not retried by replay. Outcomes
are not counted again, and repeating a link does not replay it again.

The endpoint observation index retains the last 24 distinct time points per KB
in first-observed order (the miner's `hm-window`), including all observations at
those endpoints. Ingestion evicts one expired endpoint by index, at a cost
bounded by that endpoint's facts. Links delayed beyond this horizon cannot replay
its old observations; ordinary KB facts remain stored for reasoning. This index
is separate from the recent true-feature window per constant.
