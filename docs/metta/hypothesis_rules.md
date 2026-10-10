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

