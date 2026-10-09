# Conditioning a key's merge on shared statements

Status: built, October 2026. Code: `sk-merge-facts`, `sk-merge-key`,
`sk-shared-statements`, `sk-key-condition` in
`runtime/backward/evaluation.metta`. Tests:
`tests/metta/test_overlap_conditioning.metta`. Row conditioning, which this
extends to a key's merge, is in
[overlapping_premise_conditioning.md](overlapping_premise_conditioning.md).

## Problem

Two views of one key whose evidence overlaps, neither containing the other's,
kept the more confident view. That dropped whatever evidence the other one
held alone.

SupplyNet stage 3 timed, seed 2, budget 50, round 4: `Degraded power-plant t4`
was 0.127, exact 0.05. Degraded power-plant t3 had two views:

- the persistence view from t2, built through t2's production report, which
  reads the fuel delivered in t2 and so the north storm of t1;
- the t3 completion over the t3 production report, which reads the fuel
  delivered in t3 and so the north storm of t2, a persistence of t1's.

The persistence view was near certain and won; the report, which settles t3
(producing, so not degraded), was dropped.

Every fact and rule in SupplyNet is certain. The two views share only certain
facts as evidence (the storm's history, the late shipments of t1, the period
links). What makes them dependent is a derived statement both read, Storm
north t1, uncertain although every leaf below it is known. Evidence sets name
only leaves, so they cannot say what to condition on, and reading the overlap
as harmless because its facts are certain would count the shipments of t1
twice, once through each view.

## What two views share

A value's dependency set holds every key its derivation read
([dependency_tracking_design.md](dependency_tracking_design.md)). The
statements two views share are the keys in both sets, less

- the merged key itself and the keys unifying with it, which neither view may
  depend on beyond its own key;
- statements already given by an enclosing condition;
- folds, which are not statements (a shared population base rate is the prior
  the factored merge reads, `prior_factored_merge.md`);
- statements known: a stored fact of strength 0 or 1 at confidence 1, or
  rows whose every view is.

Shared uncertain facts are among them: a stored fact depends on its own key.

## Rule

For two views of a key whose evidence overlaps (identical proofs, projections
and settled steps are handled before, as they were):

1. **Containment.** A view whose evidence contains the other's is kept, the
   larger one when the containment is strict and the more confident one when
   the sets are equal. Such a view holds nothing the other lacks, so neither
   revision nor conditioning has anything to add.
2. **Independent.** Otherwise the views are independent when they share no
   statement, no rule whose truth is an estimate, and no known fact that some
   rule concludes. A known fact no rule concludes, like a period link, is a
   premise either view reads as given; a fact some rule concludes may be an
   observation both views update on, and counted twice by combining them (wet
   ground read by an inversion and by a completion,
   `test_antecedent_completion.metta`; a late shipment read by the shipment's
   inversion and through the storm, `test_population_prior_factoring.metta`).
   Independent views merge as views with disjoint evidence: factored over a
   prior, combined by the mode their predicate prefers, or revised. The
   factored merge's own independence tests read the same way.
3. **Conditioning.** Otherwise, when they share statements, the whole key is
   conditioned on them:

   ```
   P(X) = P(K) P(X | K) + (1 - P(K)) P(X | not K)
   ```

   Each branch is the key's merge with K given: its leaves, and its views,
   each view depending on K being its row evaluated again with K known
   (`sk-given-view`, the row conditioning machinery). Given K, the views no
   longer share K or what they read only through it, so they merge by the
   rules above, or condition again on another shared statement. The branches
   mix by `CTVModusPonensFormula` over K's value (`sk-mix`, as for rows).
4. **Fallback.** The more confident view is kept when the views share only an
   estimated rule or an observation (neither can be given), when the mix is
   impossible (a branch has no simple truth value, or K's value shares
   uncertain evidence with the branches), and while the conditioning waits for
   its cost to be paid.

Which statement first: the shared statements whose set no other shared
statement's dependency set holds, the largest dependency set first. A
statement below another is usually read through it, so giving the upper one
removes both. One read around it is still shared in the branch and is
conditioned there.

## Decisions against the proposal

- **Statements from dependency sets, not evidence sets.** The proposal looked
  for the shared uncertain statements among the evidence entries. Those are
  leaves; in SupplyNet every leaf is certain, and the statement that couples
  the two views is derived. Dependency sets hold derived keys and stored facts
  alike.
- **Certain overlap is not harmless.** Reading every overlap in certain facts
  as independence was tried first: it fixed the stage 3 case and broke seven
  tests, all of them two views of one observation (wet ground through an
  inversion and a completion; a late shipment through two rules; one alarm
  inverted over two priors; two rules over the same facts). The facts no rule
  concludes are the ones that cannot be observations.
- **No new estimate of the weight.** The exact mix weighs each branch by K's
  probability given everything, the views' evidence included. The views'
  values do not determine how likely their evidence is under each branch, so
  the weight is K's value as the chainer has it.
- **The allowance as for rows.** The conditioning is gated exactly as row
  conditioning is, with the cost bound the brief asked for.

## The weight

K's value is read without views depending on the merged key. The mix is the
total probability over K when that value is K's probability given all the
evidence, the views' included. Evidence the views hold about K and K's value
does not, such as a report that tells the storm through the fuel, is lost to
the weight but still counts in each branch. A stored soft fact applies no
rules, so its value is its stored value, and observations below the views
never update it. The chainer propagates observations up through inversions and
completions, so a derived K (Storm north t1 in SupplyNet) carries what reached
it. The same holds for row conditioning.

## Cost

As for rows: a merge outside any condition conditions only once the evaluation
paid for it, and inside a conditioned read it is part of what was paid for.
Its cost bound is 2^k times one more than the size of the two views'
dependency sets together, for k first statements. A key waiting for the
payment keeps its fallback merged value, and the payment is claimed with the
rows waiting to be conditioned (`sk_given_pending` with row hash -1): nearest
a root first, then cheapest, then oldest. A paid key drops its merged value
and forces its readers, which read it conditioned. The roots' merged values
are read before the payment, so a root conditions in its own query.

Finding the shared statements costs a walk of both dependency sets and a
look at each shared key's stored facts and latest row views, only when the
evidence overlaps and neither view contains the other's. A shared key is
never merged for this: its merge may read the key being merged, and the two
merges would read each other without end (SupplyNet stage 3 untimed, seed 3,
round 17, before this was so). For the same reason a key read again inside
its own conditioning, through the weight's value, keeps its fallback there
(`&sk_conditioning`), and the conditioned value replaces whatever that inner
read cached.

## Worked example

`tests/metta/test_overlap_conditioning.metta`, SupplyNet stage 3 in small. A
soft storm (Storm t1) = 0.6 persists with (0.7, 0.3); fuel arrives with 0.2 in
a storm and 0.9 otherwise; the plant runs exactly when fuelled and not
degraded; degradation persists with (0.75, 0.05); the plant is sound in t0,
off in t1 and running in t2.

Degraded plant t1 has two views sharing the storm: the t1 report, odds(0.05)
/ (1 − P(fuel t1)), merged with the persistence from t0; and the smoothing
completion from t2, where the plant running means not degraded, a likelihood
ratio of 0.25 / 0.95 for Degraded t1.

| | Degraded plant t1 |
|---|---|
| more confident view (before) | 0.0919 |
| given storm: odds 0.05/0.95 / 0.8 · 0.25/0.95 | 0.0170 |
| given no storm: odds 0.05/0.95 / 0.1 · 0.25/0.95 | 0.1217 |
| conditioned, 0.6 · 0.0170 + 0.4 · 0.1217 | 0.0589 |
| exact posterior (the reports also update the storm, to 0.864) | 0.0312 |

The conditioned value is the total probability over the storm's stored value;
the gap to the posterior is the weight's (see above).

## Result

SupplyNet stage 3 timed, seed 2, 30 rounds, against master 5bbb87ad (posterior
error is the mean distance from the exact posterior):

| budget | posterior error | Brier | seconds | keys moved |
|---|---|---|---|---|
| 50 | 0.00478 → 0.00478 | 0.1446 → 0.1446 | 16.4 → 15.7 | 0 |
| 100 | 0.00618 → 0.00618 | 0.1459 → 0.1459 | 18.8 → 19.0 | 0 |
| 200 | 0.00460 → 0.00387 | 0.1448 → 0.1456 | 20.0 → 21.7 | 10, all closer |

At budget 200, Degraded power-plant t4 in round 4 is 0.05 (was 0.127, exact
0.05), and Producing power-plant t4 0.95 (was 0.873, exact 0.95). At budgets
50 and 100 the rows recomputed below the free depth spend the whole
evaluation allowance before any conditioning is claimed: the Degraded t3
claim (cost 88) met an allowance of 0 at budget 50. Rows waiting for
conditioning are not paid there either. Moving the case at budget 50 needs
conditioning near a root to be paid before deeper rows, a change to the
allowance's order for rows and keys alike, left open.

`bench/compare.sh` full against master dd53deb6: PASS; accuracy changed in
stage 3 at budget 100 only (timed seed 4 error 0.00399 → 0.00273, degraded
0.0130 → 0.0097, producing 0.0076 → 0.0040; seed 3 0.00316 → 0.00310);
StationOps replay beliefs identical; time +3% SupplyNet, +1% scale.
