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
- The rule applies with the merged truth, backward and inverted.

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
- **Gap 5 is open.** Two hypotheses confirmed through perfectly correlated
  antecedents each learn the single hypothesis's truth (0.797, c 0.669), but
  applied to one case their views revise as independent: c 0.802 against
  0.669 for one. Their truths are estimated from the same outcomes, which
  the views do not carry as evidence. The confidence 0.671 first reported
  here was the stale-truth bug below: one view read its rule's prior.
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
    out, `sk-left-out-view`), instead of an older version;
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

Two refined hypotheses about one consequent where one antecedent refines the
other, `(S a $t) → Win` and `(And (S a $t) (L b $t)) → Win`, both apply to a
case with S and L. Their views shared no evidence, so they revised: 0.40 for
a case the specific rule wins every time (0.25 general, 0.99 specific). The
specific application reads a proper superset of the general one's stored
facts, so its antecedent, as instantiated, entails the general one's, whose
rate is a marginal over this case and cases it is not. The merge now reads
the specific strength under `bayes-prior-count` pseudo-observations at the
general one (`sk-specialized`, proof `(specializes specific general)`): 0.95
(`test_hypothesis_rules.metta`, ChainerGame
`benchmarks/ona/repros/specificity.py`). A specific rule with little evidence
stays near the general rate. Only applications to stored facts are compared:
a derived premise's leaves say nothing about entailment.


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
  yet takes all its members when first read.

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


## Mining hypotheses (October 2026)

Status: built, opt-in (`set-hypothesis-mining`); evaluation below.

Until now a client had to state every hypothesis (the ONA matching-to-sample
harness creates them in Python). A KB with mining on proposes them itself
from the facts added to it, keeps the ones that predict and drops the rest,
as ONA forms, revises and forgets its implications.

### Proposing (`runtime/hypothesis_mining.metta`)

`compileadd` of a ground fact `(P c1 .. cn)` with constant arguments, when its
KB has mining on:

1. counts the fact in the tally of every consequent pattern it is an
   instance of that already has a hypothesis (the fact with a nonempty set of
   its constants made variables; at most 2^n − 1 lookups): the
   opportunities a hypothesis had since it was born;
2. reads its **features**: the true facts recorded for each of its
   constants (the last 24 per constant), newest first, without its own
   predicate, at most 24, and, if the fact is true (strength above 0.5),
   records it under each of its constants;
3. builds the candidates, unless its predicate is declared positive-only
   (`set-positive-only-predicate`: nothing could refute a hypothesis
   concluding it). A constant a feature shares with the fact becomes a
   variable:
   - **pairs**: the fact concluded from two features, and, for two
     features that share a constant the fact does not have, the relational
     form with that constant a variable too: `(Sample A1 t5)`,
     `(LeftStim A1 t5)`, `(Reward left t5)` give
     `(And (LeftStim $x $t) (Sample $x $t)) → (Reward left $t)`;
   - **singles**: the fact concluded from one feature;
4. for a true fact, proposes, recurring singles first, each candidate that neither it nor its
   reverse was proposed before and whose consequent pattern has fewer than
   `max-live` live hypotheses, until `max-new` are proposed: a pair at once,
   a single only when it **recurs**: seen at another instance than its first
   sighting, with other features (generalized alike) than at the first
   sighting. Where the same features accompany it, the first context's pairs
   explain it as well, so the most specific candidates are proposed first
   and a single only once the data show it predicting across contexts. A
   single without other features recurs at its second instance (no pair
   could explain it). Its instance fold reads every earlier instance, so a
   single proposed late loses no evidence;
5. for a false fact, proposes only when a live hypothesis concluding it
   applies to it (its antecedent holds of the features): the prediction
   failed, and the pairs that contain a fact the prediction read can learn
   where it fails (a matching-to-sample agent that learned "right" where
   the right stimulus matches the sample learns that it fails where the
   left one does, its desire there drops, and it explores "left").
   Otherwise a false fact proposes nothing: what co-occurs with a statement
   that does not hold says nothing about what makes it hold.

So the newer of two facts is the consequent (ONA's temporal order), and the
reverse of a proposed hypothesis is never proposed: one direction per pair of
statements, decided by the order the data arrive in.

A hypothesis is a refined rule named `hypothesis-N` with a weak prior,
strength 0.5 with the evidence of 0.01 observations (confidence 0.01/(0.01 +
k), so the first samples decide whatever the evidence parameter k): an STV
when a conjunct of its antecedent is positive-only (no instance where it
fails could teach a CTV's negative branch, which would stay at its prior), a
CTV otherwise. So adding a fact costs a bounded number of indexed lookups (24
features give at most 24 singles and 276 pairs and their relational forms)
and at most `max-new` rule compilations, whatever the KB's size; off, it
costs one lookup of the KB's setting.

### Reviewing and dropping (`runtime/hypothesis_review.metta`)

`review-hypotheses` reads the `RuleTruth` goals of the live hypotheses that
apply to a goal in one query. The chainer keeps the truths current as
instances arrive ("Instance tallies"), so the query has budget only for the
hypotheses no review has read yet: `$steps` for each, which their first read
spends folding their instances; once every hypothesis was read, it has none.
Each hypothesis is then judged:

- one whose truth rests on fewer than 4 observations is kept, unless its
  consequent pattern was observed 32 times since it was proposed (its
  antecedent hardly ever holds);
- otherwise it is kept when its strength P(B|A) differs from the
  consequent's probability without it by more than two standard errors of
  that probability over its observations, and from the strength of every
  more general live hypothesis judged in the same review that rests on
  enough observations (one whose antecedent conjuncts, under a substitution
  taking its consequent to this one's, are some of this one's:
  `(A $x) → (B $x)` screens off `(And (A $x) (C $x)) → (B $x)`, and the
  relational `(And (L $x $t) (S $x $t))` screens off
  `(And (L A1 $t) (S A1 $t))`). The consequent's probability without the
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
leave the rule indexes (`withdraw-named-rules!`, what the deprecated
statement removal uses), so no later search applies it; the skeleton rows it
built stay, as forgetting leaves summaries. It is never proposed again. A
general rule is not dropped for its specifics: its view is their prior.

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
- **Deciding the direction by the data.** For two statements alone,
  correlation is symmetric and no statistic of the pair tells cause from
  effect: SupplyNet's storm → blocked (0.8 against 0.03 without a storm)
  reverses, at a storm rate of 0.25, to 0.90 against 0.06, which is more
  informative and gains more Brier score. Only a third statement that screens one off says more.
- **Explaining away and chain reduction in the review**: drop A → C when a
  pair (A and B) → C does not differ from B → C (B screens A off), or when
  the deduction through live A → B and B → C predicts A → C's strength. Both
  drop what they should in unit cases, but changed nothing that matters:
  matching-to-sample scores identical; SupplyNet (seed 1, 10 rounds)
  explaining away dropped 1 more rule at the same error 0.1242 (the pairs
  that would screen are rarely proposed), and chain reduction 15 more
  indirect rules, error 0.1242 → 0.1265, time unchanged. Not kept.
- **Features of the consequent's own predicate, through a link.** A pair
  of `(NextPeriod p1 p2)` and `(Storm north p1)` concluding
  `(Storm north p2)` is the persistence rule
  `(And (NextPeriod $q $p) (Storm $r $q)) → (Storm $r $p)` (found in a unit
  test), but the same link gives such a rule for every predicate, each
  recursive over the whole history: SupplyNet stage 2 with mining ran out
  of memory (16 GB) before its first round with 10 history periods, and
  held 12.9 GB for 33 minutes without finishing it with 30. Without them,
  10 history periods run at 30 s per round.
- **A consequent pattern seen only once proposes nothing.** It keeps out
  hypotheses such as `(And (Blocked r1 $q) (Storm north $q)) →
  (NextPeriod $q h7)`, whose consequent names a period that never recurs,
  but it delays every first pattern: matching-to-sample 0.797
  (conditioning), 0.555 (identity), 0.586 (reversal) over 4 seeds, against
  1.000, 1.000 and 0.688 on the same seeds. The client declares such link
  predicates positive-only instead (below).
- **Mining at query time from the journal of added facts.** The journal is
  kept only once the skeleton has expanded nodes, and batching changes
  nothing about the bound per fact.

### Evaluation (October 2026, master f42c380a)

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
