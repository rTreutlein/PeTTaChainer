# Observed predicates

Status: built, October 2026 (`set-observed-predicate`,
`runtime/observed_predicates.metta`).

## Problem

An agent that acts on a rule predicting an event at the next time point, and
then sees that the event did not come, has negative evidence for the rule:
ONA's anticipation. The chainer is open-world. A refined rule's instance
counts as a sample only where its consequent's truth is known, and an event
that was not observed is unknown, so the failed prediction was no sample.
The ChainerGame Pong agent learns one-step world rules

    (And (NextPeriod $t $u) (At x $t) (Did op $t)) -> (Ball y $u)

and goal rules `... -> (Hit $t)`. Without negative samples every such rule
reads 1 wherever it ever held.

Complete predicates (`complete_predicates.md`) do not cover this. A complete
statement is read false only where no rule application derives it, and here
the rule under test derives it. Instance folds do not see closed reads either.
ChainerGame `benchmarks/ona/repros/closed_world_past_events.py` shows both:
with `Ball` complete, the unobserved `(Ball equal d3)` still reads 0.995, and
the rule rests on its one positive sample.

## Semantics

Observation, not derivation, decides the past. An observed predicate has a
place in time (`set-predicate-time`: the position of its time argument). Its
statements at a time point are complete once the time point's observations
are in, and they are in once a true link fact reaches the time point
(`set-time-link`, `(link earlier later)`): the client states a time point's
observations, then the link into it. Rules still predict observed statements
at time points no link has reached. An outcome of the step from t to t' is
an observation of t' (the Pong agent states `(Hit t')`, the new position,
then `(NextPeriod t t')`; its goal rules conclude the outcome at `$u`).
Closing at the link leaving a time point instead delayed each position's
closure by a decision, and the agent played much worse (Pong2 without
misses, 300 steps: 2 hits in 19 against 14).

When a true link fact `(link t t')` is added, each ground statement of an
observed predicate at `t'` that a rule of the KB concludes, and that has no
stored fact, is stored false: `(: unobserved-<hash> S (STV 0.0 1.0))`.
The candidates are the conclusions of the KB's rules (inversions and
completions included) with the time argument a variable and every other
argument ground, instantiated at `t'`. These are what the KB predicts, which
is what anticipation tests. The facts are ordinary stored facts, so
absorption, instance tallies (`hypothesis_rules.md`), certainty (a certain
key applies no rules) and forward runs treat them as observations, and
nothing else changes.

Not covered: a statement no rule concludes is not closed (its truth matters
to no prediction), nor is a rule conclusion with another variable besides
the time argument (its instances cannot be enumerated). A fact stated for a
time point after its link is not reconciled with a false one: the link
closes the time point.

Cost: nothing for a statement that is not a declared link. For a link, one
scan of the KB's rule conclusions per observed predicate, bounded by the
rules, not by the history, plus one lookup per candidate.

## Result

`tests/metta/test_observed_predicates.metta`: the repro's rule over one
observed and two anticipated, missed instances reads 0.334 at confidence
0.751 (1 in 3, k = 1), the same as with the false facts stated by hand. A
time point no link has reached stays open, and an undeclared predicate is
never closed.

ChainerGame Pong (`onabench.pong`): the agent stated these false facts
itself before (labelled interim). On 300 steps of each game and mode, with
the chainer stating them instead, every decision and desire is the same.

## Porting to mm2-chainer

- Keep it at ingestion. The trigger is adding a true link fact; it closes the
  time point it reaches. Compute the
  candidates there and add them as plain facts. Do not make the reader
  (search, folds, samples) aware of closedness: every consumer then handles
  them as observations for free, and a fold's sample is just a stored false
  consequent.
- Candidates come from the rule index: the conclusions with head H among
  the observed heads. Index the rule store by conclusion head, so the scan
  costs the rules of H, not all rules. Instantiate the time argument, require
  the rest ground, and skip statements with a stored fact (one indexed
  lookup).
- Declarations per KB: the observed heads, each head's time-argument
  position, and the link head. These are the same time declarations the miner
  uses.
- Name each false fact by a hash of its statement, so a replay or a repeated
  link adds nothing twice.
