# Conditioning a key's merge on shared statements

Status: built, October 2026; budgeted cutset conditioning, entangled
premises, completions read under their part and sample twins added October
11-12. Code: `sk-merge-facts`,
`sk-merge-key`, `sk-shared-statements`, `sk-entangle`, `sk-conditioned`,
`sk-deepen`, `sk-sample-twins?` in `runtime/backward/evaluation.metta`.
Tests: `tests/metta/test_overlap_conditioning.metta`,
`test_nested_conditioning.metta`, `test_problog_fuzz_regressions.metta`
(F7), `test_hypothesis_rules.metta` (gap 5). Row conditioning, which this
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
- rule truths (`RuleTruth` keys), which are parameters of the views, not
  events (see "Shared rules" below);
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
   statement and no known fact that some rule concludes. A known fact no rule concludes, like a period link, is a
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
4. **Fallback.** The more confident view is kept when the views share an
   observation (it cannot be given), when the mix is
   impossible (a branch has no simple truth value, or K's value shares
   uncertain evidence with the branches), and while the conditioning waits for
   its cost to be paid.

Which statement first: see "Budgeted cutset conditioning" below.

## Budgeted cutset conditioning

Conditioning on one shared statement is the first step of cutset
conditioning: given a set of statements (a cutset) that breaks every path
along which the views share something, the views are independent in each of
the 2^k branches, the merge rules above are exact in each, and the mix over
the branches is the exact value. The chainer never builds the cutset ahead:
it conditions on one statement, and a branch whose views still share one
conditions on it in turn. What bounds this is the claim's budget, and what
makes it anytime is the depth.

**Order.** The candidates are the shared statements whose value is uncertain.
They are tried in two groups, each by expected impact:

1. the frontier: the statements no other shared statement depends on (the
   largest dependency set decides first), since a statement below another
   is usually read through it, and giving the upper one removes both;
2. the statements below the frontier.

Expected impact is the statement's spread, the largest variance s (1 - s) of
its facts' and views' strengths, times one more than its dependency count.
The mix moves the value by P(K)(1 - P(K)) times the difference of the two
branches; the spread is the first factor, and the dependency count stands in
for the second, how much of the views the statement reaches, which is not
known before the branches are evaluated. A statement whose mix is impossible
(its value's evidence enters the branches by another path, see "The weight")
gives way to the next one in order: SupplyNet's derived `Fuelled plant t1`
ranks first in `test_nested_conditioning` and fails; the stored storm below
it mixes.

**Depth.** A claim's pass has a depth d: the number of statements conditioned
on along any path from the target, a cutset of 2^d branches. A conditioning
nested deeper than d takes its approximate value instead (below), and the
pass is cut. A claim makes a pass at depth 1, then, while the pass was cut,
one at depth 2, and so on, each on what the claim has left, and keeps the
deepest pass that finished. A claim that overdraws keeps that pass (or the
waiting value when none finished) and waits at twice its cost, so it may be
paid again in the same evaluation once the allowance covers it, or by a
later query.

**Approximate values.** Every target has one while its conditioning waits or
is cut:

| target | approximate value |
|---|---|
| a key's merge | the more confident of the overlapping views (the fallback above) |
| a row whose premises are entangled (below) | the premises read as independent |
| a row whose premises clash on shared evidence | none |

A clash has no approximate value: without conditioning the row derives
nothing, as before conditioning existed (a row keeps the views it had while
it waits). So a clash conditions at any depth in one pass, as before, and its
pass is taken only if no nested conditioning had to stand an approximation
in: a branch that stands in the independent product of two completions that
explain each other away gave the machine-failure example's Or 0.696 against
the inversion's 0.82, and its evidence held the inversion's, so it replaced
it (`examples/metta/machine_failure_inversion.metta`).

**Convergence.** Let V_d be the value a pass at depth d computes. For every d
it is a mix, over the statements conditioned on, of branch values in which
every conditioning nested deeper than d is replaced by its approximate value.
Two facts give the argument:

1. *Exactness at the cutset.* If the pass at depth d is not cut, no
   conditioning stood an approximation in: every branch merged views that
   share no uncertain statement (or share only what the merge rules handle
   exactly: containment, given facts, rules), so each branch is exact under
   the views' own formulas, and the mix of exact branches by the
   statements' values is the exact total probability (up to the weight, see
   "The weight"). Once d reaches the size of the cutset the target's views
   need, V_d is that value and no deeper pass changes it.
2. *Monotone refinement.* V_{d+1} differs from V_d only inside the branches
   where V_d stood an approximation in, and there it replaces the
   approximation by the mix that conditioning on the next statement gives,
   which is exact given the statements above it whenever it is not cut
   itself. So each pass replaces approximations by values closer to the
   exact one, statement by statement, in order of impact.

The shared statements of a finite skeleton are finite, so the depths are
bounded, and with an allowance that covers 2^k times the base the claim
finishes uncut and is exact. With less it keeps the deepest pass it could
pay for, so a larger allowance never conditions on fewer statements: it
extends the same sequence of passes. That is the anytime property the
`--curves` profile checks: error per second should fall with the budget.
It is not monotone in every instance. A partial conditioning can be further
from the exact value than the approximation when the approximations' errors
cancelled (two views each overcounting in opposite directions); it is
monotone in expectation over the uncertainty the approximations leave,
because each pass removes one source of error and adds none.

**Cost.** A payment at level l costs 2^l times the base, one more than the
dependency count of what the target conditions (the overlapping views', the
clashing value's, or the entangled premises' together), and the claim may
make twice that in conditioned row evaluations. The level starts at 1, so
the first payment covers a depth-1 pass, and rises by one with every claim
that overdrew. Each pass costs at most 2^d times the base, so the passes up
to depth d cost less than twice the last; the deepening costs at most a
factor 2 over knowing the right depth in advance.

## Entangled premises

Premises of one rule application, or of a compound read off its parts, that
read one uncertain statement are not independent, whatever evidence they
name. E <- (Or C B) with C <- B multiplied P(C) and P(B) as if they were:
fuzzer seed 1000004, 0.342 against the exact 0.274. Evidence sets name only
the leaves, here the certain fact (A b), and certain facts never clash. The
statements are found in the premises' dependency sets instead. The
candidates are the premises' own keys and the keys their rows read; a
candidate two premises' sets hold, uncertain, not given and outside the
row's exclusions, is shared, ordered as above. That is a few masked
membership tests per row. Collecting both sets and testing every key they
share found more (a statement shared further down) but doubled SupplyNet
scale l's time (26 s to 59 s) for no change in any answer, so a statement
shared more than one row below the premises is not found. The row is conditioned on them like a clash: under B known, the
premise B reads as known and C is its row evaluated again under B. E <- (And
C D) with C <- B and D <- B is found the same way, through the common
ancestor (0.2264, independent 0.1794).

Unlike a clash, an entangled row has an approximate value: the premises read
as independent, which is what the chainer computed before. A row waiting for
its payment keeps the views it had, or takes that value if it has none. The
attempt that conditioned on such premises as soon as they were found
(branch `backup/fuzz-f4to7-f7`, 7f14a85f) made rows waiting for payment
derive nothing: fuzzer seed 11000301 lost its answer, and conflicting
sources (pln-sources) lost coverage.

Under a closed read's pins outside any claim (a complete statement's rows
evaluated again with the reader unfounded), an entangled row is conditioned
only when what the evaluation allowance has left pays its depth-1 cost, two
times its base, and takes its approximate value otherwise; a clash there
opens a claim of its own, as before. Conditioning every entangled row a
closed read met, on every statement it shared and unpaid, made 162 claims
and 151,538 conditioned evaluations in SupplyNet stage 3 untimed (seed 4,
budget 50): 59 s against 10 s, for no gain. Paid from the allowance, fuzzer
seed 12000203's E <- D over a closed D <- (Or B C E) with C <- B is exact
at budget 2000 (0.8975) and keeps the independent value at 100 (0.8179).

Rows reading a fold read its members as data, compiler-marked joins share
their sources by design, and projections of one source pool into it; none of
them is checked. Inversions and completions have their own reading of their
premises and are not checked either. A row whose greedy read finds premises
entangled reads again on a fresh copy, taking stored facts first, as for a
clash: a sample (Tall alice) and (Female alice) whose merged value derives
Female from Tall reads the stored Female fact and is independent.

## Completions

An antecedent completion onto a part M of a compound antecedent needs the
other parts O only where M leaves the compound open: given M false for an
Or, given M true for an And (`DisjunctLikelihoodFormula`,
`ConjunctLikelihoodFormula`). It reads O at its value, apart from the
consequence. When O has no value of its own it is read under that condition
instead, a one-statement conditioning on the target itself whose branch is
the only one the formula reads: fuzzer seed 12000044 has B <- (Or A D), D <-
(Or A B) over complete B and D, A an unobserved root and D observed false. B
has no value, since a derivation reads no population prior for A, so the
completion onto A failed and A answered its population prior, 0.18. Given A
false, B's closed read finds it unfounded, the completion reads s_B = 0, and
D false says A false: 0, exact. The read under M may depend on M's
hypothesis, which is no support, so M's own key is not excluded there.

Only a part without a value is read so. A part with a value correlated with
M through a derived statement is still read unconditioned; reading every
part under M would recompute the persistence chains behind SupplyNet's
smoothing completions at every evaluation.

## Sample twins

Two refined rules learned from the same outcomes, applied to one case,
revised as independent: `test_hypothesis_rules`, A -> C and B -> C confirmed
from twenty cases in which A and B always agree, gave (C new) confidence
0.802 against 0.669 for either rule (hypothesis_rules.md, gap 5). Given the
truths the two applications are not independent views of C: the history
never told A and B apart, so the second rule's view adds nothing to the
first's. No statement is shared (each view depends on its own truth's key,
"Shared rules"), so this is no conditioning; it is containment on the
samples. An implication instance fold keeps a digest of its samples, the sum
of a hash of each member's consequent and contribution, updated with the
tally at constant cost per take. Two applications of different refined rules
whose truths' folds have equal digests are one estimate from one sample
applied twice, and the merge keeps the more confident.

Only equal sample sets count. Overlapping ones (antecedents that mostly but
not always agree) still revise as independent; their joint estimate, P(C |
A, B) over the cases where both hold, is a rule the KB does not have, and
conditioning on a latent common cause needs a statement the KB does not
mention. A subset (B -> A in the history) would make the narrower rule the
specific one, as `more-specific-application?` does for facts, but a small
sample is a subset of a large one by chance (a rare source's three claims
all co-claimed by a loud one), so it is not used.

## Shared rules

Two applications of one rule to different premises share the rule's truth and
nothing else. Given that truth they are independent: P(X | both, θ) factors
as the generating model does, and to first order the mix over θ is the value
at θ's estimate. So a shared rule, given or estimated, does not make views
dependent, in a key's merge as in a row's premises (which never counted a
shared rule as a clash). Its uncertainty enters each view's confidence, and
the revision counts it once per view: the merge is more confident than the
rule's own evidence warrants when many views share one estimated rule. A rule
and its own axiom (`rule-axiom`, an implication query answered through it)
still carry the same evidence and are kept by containment.

Until October 2026 a shared estimated rule was a fallback: the merge kept the
more confident view. ChainerGame's conflicting sources: a node's own claim by
source s was dropped whenever a system rule's view of the node read another
claim of s (`test_certain_merge.metta`, `test_hypothesis_rules.metta`: 0.748
against 0.568 with the claim revised in).

Conditioning on the rule's truth, as on a statement, was considered and not
built. A two-point (STV) or four-point (CTV) mix over the truth's Beta would
add its variance once, but given the truth each view's confidence is that of
its premises alone, often certain, and revision weighs views by confidence:
two views of certain claims become certain and revision takes the stronger
one whatever the rule's evidence. Its cost is 2 or 4 evaluations per shared
rule, and stated rules have no key to pin.

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
- **Iterative deepening, not one deep claim.** Until October 11 a claim
  conditioned as deep as its budget allowed and, when it overdrew, discarded
  everything and fell back: a claim either finished or gave nothing, and an
  overdrawn claim waited at the same cost for ever. Now a claim keeps the
  deepest pass it finished and waits at twice the cost.
- **No refusal of the weight's evidence was relaxed.** A mix whose weight
  shares evidence with its branches is still refused; the next statement is
  tried instead.

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
Its cost bound is 2^l times one more than the size of the two views'
dependency sets together, at the claim's level l (see "Budgeted cutset
conditioning").

The bound is enforced. A claim is what one payment covers: a row or key
conditioned outside any condition, with everything its branches condition on
in turn, and everything conditioned that a weight's read reaches. Each row it
evaluates again under a condition takes one of twice its bound (the bound
counts each dependency once per branch, and a row read through two paths is
evaluated twice); a claim that would take more stops, keeps its deepest
finished pass (or, with none, falls back as an unpaid one does, the row
keeping its views and the key its more confident view), and waits at twice
the cost. Nesting made a claim's work unbounded before: a branch whose
views still overlap conditions again, and every level doubles the work
(ONA identity matching, while rule truths were shared statements: one claim
ran for 13 minutes). Test_overlap_conditioning's plant over five periods with
soft reports, where conditioning Degraded plant t5 conditions t4 inside its
branches, t4 t3 and so on, took 238 s at budget 300 and 509 s at budget 2000;
bounded claims took 7 s and 8.5 s for the same answers
(`test_nested_conditioning.metta`), and twelve periods take 8 s. With
deepening the query at budget 300 makes 728 conditioned evaluations instead
of 5,648 for the same strength, and a second query at 300 keeps it (bounded
single claims lost it there: 0.127, the persistence view alone); at 3,000
it conditions deep enough to read the t5 report, which says the plant runs
and so is not degraded (0.0). A closed read outside any claim that conditions opens a claim
of its own. A key waiting for the
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
conditioning are not paid there either.

The rows beyond the free depth now run nearest a root first
(`sk-item-order`). Over stage 3 (timed and untimed, seeds 1–4, budgets 50 and
100) mean posterior error is 0.00304 on master and 0.00247 with the rows
ordered by depth. Paying a claim nearer a root before a deeper row spends the
allowance was tried on top (branch `conditioning-order`, b6872723) and not
merged: 0.00245, no net gain. It moves Degraded power-plant t4 to 0.05 at
budget 50 and helps the untimed cycle (0.00170 → 0.00145), but costs the timed
one (0.00323 → 0.00346): a claim of cost 84–90 takes most of a 100–200
allowance, and the rows it displaces carry storm evidence to the more
numerous Storm and Blocked keys.

`bench/compare.sh` full against master dd53deb6: PASS; accuracy changed in
stage 3 at budget 100 only (timed seed 4 error 0.00399 → 0.00273, degraded
0.0130 → 0.0097, producing 0.0076 → 0.0040; seed 3 0.00316 → 0.00310);
StationOps replay beliefs identical; time +3% SupplyNet, +1% scale.
