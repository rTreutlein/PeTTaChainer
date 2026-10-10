# Conditioning on Shared Premise Evidence

Design record, 2026-09-30. The mechanism is described where it lives:
premise selection and the evaluation allowance in
[runtime_design_assumptions.md](runtime_design_assumptions.md), the proof form
in `pettachainer/LANGUAGE_SPEC.md` ("Premises that reuse evidence"). This note
keeps the reasoning and the alternatives that were rejected. Tests:
`tests/metta/test_premise_conditioning.metta`. A key's merge conditions the
same way on the statements two of its views share
([overlap_conditioning.md](overlap_conditioning.md)).

## Problem

With `a : (A x)`, `b : (B x)`, `r1 : A ∧ B → C` and `r2 : A ∧ C → D`, the
backward chainer derived `(C x)` but never `(D x)`. The row of `r2` refused
`(C x)` because its evidence contains `a`, which the row had already read.
That refusal kept `a` from counting twice, at the price of a valid inference.

## What is computed

The row is evaluated with the shared statement `K` known true and again known
false, and the results mix by K's value:

```
P(D) = P(K) P(D | K) + (1 - P(K)) P(D | not K)
```

The mix is `CTVModusPonensFormula` over K's value, with the two branches as the
positive and negative branch, so strength and confidence come from an existing
formula. Because every modus ponens is complete, and STV rules get a negative
branch from the base rates, the mix is exact under the proof's own independence
assumptions. The one stand-in is the rule's negative branch `P(C | not (A and
B))`, used in place of `P(C | A, not B)`, which the engine never estimates.
`test_premise_conditioning.metta` checks the analytic value 0.436, against
0.4024 for the independent product.

## Decisions against the proposal

- **Row-level mixing for every case.** The proposal treated a shared fact the
  row read itself (one branch, true only) differently from one hidden inside
  two derived premises (both branches). Mixing the whole row over K covers
  both:
  - it equals the one-branch chain rule, since modus ponens is linear in its
    antecedent;
  - it holds for any formula the row applies, Or included:
    P(A or C) = P(A) · 1 + (1 - P(A)) P(C | not A).

  The price is a second evaluation for a directly read fact.
- **No estimate before conditioning.** The proposal gave an unconditioned row a
  Fréchet-interval estimate. Premise truth values feed arbitrary formulas, so
  the interval of the conjunction cannot be put into the row generically. A
  waiting row therefore derives nothing, exactly as the refusal did, and keeps
  any view an earlier conditioning gave it.
- **Priority without a gain estimate.** The Fréchet width was to be the gain.
  Without an estimate the value of conditioning is the value of the row's
  answer, which the need depth already ranks. Waiting rows are paid for
  nearest a root first, then cheapest, then oldest, with no fixed cap:
  - cost bound: 2^k × (1 + dependencies of the clashing value);
  - paid from the evaluation allowance;
  - the first row that cannot be paid stops the payment;
  - the claim, the row with everything its branches condition on in turn,
    evaluates at most twice its bound in conditioned rows, or falls back
    ([overlap_conditioning.md](overlap_conditioning.md), "Cost").

  A width of 0 would also have ranked the motivating example, with certain
  facts, as worthless, while without conditioning it has no answer at all.
- **Exclusions**:
  - A premise reading one of the shared statements itself, like `(And X X)`
    from `X` twice, gains nothing, since P(K and K) = P(K).
  - A projection of a conjunction pools with its siblings and has no
    conditional value when the conjunction is known false. Allowing it
    replaced the marginal answers in the projection tests with wrong ones.
  - A conclusion that is not a simple truth value cannot be mixed.
  - Folds read under a condition keep their ordinary values.

## Consequences observed

- Rules that build terms from their own conclusions, such as
  `(AtTime x t) ∧ (AtTime y t) → (AtTime (And x y) t)`, now also derive
  redundant forms like `(And X (And X Y))`. Evidence disjointness used to bound
  them, and now only the budget does. At budget 50,
  `test_backward_open_query_results` returns 10 answers instead of 4. A
  filter refusing conclusions that repeat a conjunct was tried and removed:
  `And` inside a term is data, and a user's recursive rule is bounded by the
  budget, as any recursive rule is.
- Base-rate folds count members whose parts share evidence. The confidence in
  `test_specializing_rule`'s open query moved from 0.03943 to 0.03970.

## Forward chainer

The forward chainer joined premises with no overlap check at all, so it
counted shared evidence twice. It derived D = 0.4024 in the example above, and
because that stored fact carried the same evidence as the backward proof, it
also won later backward queries. It now refuses the overlapping premise
instead of conditioning, since it has no rows to evaluate again.

It also never fired a rule with a fold premise, because nothing evaluated one
outside a query; that covers every plain STV rule, whose truth needs base
rates. A base-rate fold premise now reads the base-rate cache, any other
fold premise the fold's value stored in the skeleton, and only a fold with
neither asks the backward chainer. Querying directly on every cache miss cost StationOps 36% of its wall
time (324 s → 441 s) for the same score. The misses were the shortfall DP fold,
re-queried at the forward budget of 2 on every join. With the stored views the
run takes 309 s. That made the compiled inverted rules and
antecedent completions live in forward runs too. They derived near-empty
Skolem conclusions and moved base rates, so they are kept out of the forward
premise index: forward chaining runs rules in their stated direction, as it
effectively did before.

The refusal first halved the StationOps score (53,668 → 26,626 over 4 seeds).
The action KB states its decision data as certain facts, `(STV 1 1)`, and
derives values like RepairValue from LeakProbability. Its rules then read both,
and the refusal cut those action-rule joins from the forward run.
Sharing a certain fact counts nothing twice, since the join is exact either
way. So evidence of a fact with strength 0 or 1 at confidence 1 is not
overlap, in either chainer.
