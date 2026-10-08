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
- **Gap 5 does not appear** in the tested case. Two hypotheses confirmed
  through perfectly correlated antecedents give confidence 0.671 together and
  0.669 alone, at the same strength (0.794 against the true 0.8). The
  evidence tracking sees that they share their samples.
- **Cross-feeding, open:** a hypothesis's samples read the consequent's
  merged value, which includes the other hypotheses' derivations (the
  samples of A→C hold `(merge/revision c1 (by hB b1))`). With certain
  observations the effect is in the third decimal; with uncertain ones two
  hypotheses could reinforce each other.
- **A CTV refined rule now learns its negative branch** from the base rates
  (`compile-implication-instance-adds` in CTV mode), where before it kept the
  axiom's. Two tests' values moved in the fifth decimal.
- **A score of 0 starved reviews.** With a zero factor on every hypothesis,
  the second review in a knowledge base folded nothing; the factor has a
  floor of 0.01.

`test_hypothesis_rules.metta`, with B depending on A (0.8 against 0.2) and
C unrelated, 20 cases, k = 5:

| | learned truth | score |
|---|---|---|
| before review, both | prior (0.5, 0.02), both branches | 0.0099 (floor) |
| A→B, confirmed | P(B\|A) 0.797 (c 0.669), P(B\|¬A) 0.228 (c 0.181) | 0.377 |
| C→B, rejected | 0.5 on both branches (c 0.669 / 0.181) | 0.0099 |

