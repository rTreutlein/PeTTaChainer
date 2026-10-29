# Conditioning a key's merge on shared statements

Status: built, October 2026; budgeted cutset conditioning, entangled
premises, completions read under their part and sample twins added October
11-12; actual-work payment (#74), October 17. Code: `sk-merge-facts`,
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
A statement with stored facts ranks by those facts' spread and depends on its
own key alone: its rules' views are updates its weight keeps only apart from
the branches (see "The weight").

## Rule

For two views of a key whose evidence overlaps (identical proofs, projections
and settled steps are handled before, as they were):

1. **Containment.** A view is contained only when both its evidence and the
   given statements it used are subsets of the other's. Keep the containing
   view for strict containment and the more confident one when both sets are
   equal. A pinned observation has no evidence, but an inversion using it can
   still add information to a predictive view that did not use that given.
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
3. **One-step conditioning (#81).** A key conditions on shared statements
   within two dependency levels of at least two original views. The
   `deps-near-shared` horizon is near in both views, unlike row entanglement.
   Deeper history stays at the marginals admitted by the consumer; transitive
   self-support exclusion prevents later evidence re-entering its past summary.
   For eligible statements the whole key is conditioned:

   ```
   P(X) = P(K) P(X | K) + (1 - P(K)) P(X | not K)
   ```

   Each branch is the key's merge with K given: its leaves, and its views,
   each view depending on K being its row evaluated again with K known
   (`sk-given-view`, the row conditioning machinery). Given K, the views no
   longer share K or what they read only through it, so they merge by the
   rules above, or condition again on another shared statement. The branches
   mix by `CTVModusPonensFormula` over K's value (`sk-mix`, as for rows).
4. **Fallback.** When conditioning is unpaid or cannot finish, group original
   views into connected components through shared uncertain statements or
   observations. Sibling forward-rule views also connect through shared
   condition terms, including known premises. With known shared premises,
   combine sibling conditions by prior-factored odds using the consequent's
   existing outcome tally. Near-shared pairs keep the larger count while their
   claim waits: combining them would count the shared statement twice in
   strength. Other connected pairs read what they share as fixed marginal
   inputs: a prior and likelihood combine by
   factored odds, never revision, and other views as independent by the
   predicate's mode, else revision, with confidence min(c_a,c_b)/(1+R²), where
   R=max(1,abs(logit(s_combined)-logit(s_larger))) and s_larger is the more
   confident view's (`sk-dependent-merge`). Evidence and dependencies are retained.
   Same-condition estimates and ordinary non-rule proofs retain their existing
   representative behavior. Independent components then merge as before.

   Sibling grouping uses original views, even when all shared premises are
   known. Otherwise an unrelated view could revise with one sibling first and
   hide its condition before the other arrived. A combined view carries the
   union of its conditions for connectivity. Canonical original-view order
   fixes the fold order; bridge dependencies remain part of the component.
   Direct views and prior updates (inversions, completions) form components
   apart. Independent values combine first; each update component then applies
   to that merge by the pair rule above, so an update cannot interrupt the
   direct source claims' combination. Over deeper shared statements it
   updates them; a near-shared update competes with their merge by count
   while its claim waits.
   Grouping them together let one completion that read a source's statement
   join every direct claim of that source to its component, which then kept a
   single view (pln-reliable: 248 of 510 claims).

   Same-condition rules pool before sibling grouping, so repeated estimates of
   one class do not become separate odds updates. Condition order is canonical
   even when raw proof IDs were allocated in a different order.

   Paid conditioning recomputes the rule views with `(given true/false)`
   premises and combines siblings within each branch. Shared uncertainty is
   mixed once by the enclosing conditioning. The unpaid revision is a
   dependence approximation, not a newly inferred joint rule. Neither branch
   polarity nor class population nor confidence ranks different conditions.

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
They are tried in three groups, each by expected impact:

1. the frontier of the statements stored facts supply, those no other
   stored one depends on: their weight leaves out the views that share the
   branches' evidence, so their mix is not refused after both branches were
   paid, and giving one removes every statement shared only through its
   rules' views (T8 with a soft `Storm t1` shares `Fuelled plant t1` through
   the storm's inversion of the report; tried later, the derived statements
   cost 69 rows instead of 26 at two periods with the storm at (0.6, 0.9),
   and exceed the root cap at four);
2. the frontier of the derived statements: those no other shared statement
   depends on (the largest dependency set decides first), since a statement
   below another is usually read through it, and giving the upper one
   removes both;
3. the statements below either frontier.

When several stored statements could mix and a pass stops early, the first
of them decides the approximate answer; they rank by their facts' spread,
a choice made for cost, not for the value it settles on.

Expected impact is the statement's spread, the largest variance s (1 - s) of
its facts' and views' strengths, times one more than its dependency count.
The mix moves the value by P(K)(1 - P(K)) times the difference of the two
branches; the spread is the first factor, and the dependency count stands in
for the second, how much of the views the statement reaches, which is not
known before the branches are evaluated. A statement whose mix is impossible
(its value's evidence enters the branches by another path, see "The weight")
gives way to the next one in order. Each failed candidate has paid for its
two branches, which is why stored statements go first: SupplyNet's derived
`Fuelled plant t1` ranked first in `test_nested_conditioning` and failed
before the stored storm mixed.

**Depth.** A claim's pass has a depth d: the number of statements conditioned
on along any path from the target, a cutset of 2^d branches. A conditioning
nested deeper than d takes its approximate value instead (below), and the
pass is cut. A claim makes a pass at depth 1, then, while the pass was cut,
one at depth 2, and so on, each on what the claim has left, and keeps the
deepest pass that finished. A claim that overdraws keeps that pass (or the
waiting value when none finished) and remains pending for a later query.
Every conditioned row actually evaluated spends the shared allowance; the
whole dependency estimate is no longer prepaid.

**Approximate values.** Every target has one while its conditioning waits or
is cut:

| target | approximate value |
|---|---|
| a key's merge | the one-step component merge (the fallback above) |
| a row whose premises are entangled (below) | the premises read as independent |
| a row whose premises clash on shared evidence | none inside conditioning; facts-disjoint representative at an otherwise unanswered public root |

A clash has no approximate value inside a conditioning pass: multiplying
its shared facts would count evidence twice. If paid evaluation leaves a public
root unanswered, a pending row can instead read a facts-disjoint representative
lazily from compatible retained versions or bounded row replay, discounted against the independent row read
by c/(1+R²), with R the absolute logit difference, at least one. This waiting
answer is neither an ordinary view nor materializable, including through a
materializing query. Rates still exclude the row's own observations. No second
representative read runs on ordinary rows; paid conditioning replaces this answer.
A row also keeps views it had while it waits. A clash conditions at any depth
in one pass, and its
pass is taken only if no nested conditioning had to stand an approximation
in: a branch that stands in the independent product of two completions that
explain each other away gave the machine-failure example's Or 0.696 against
the inversion's 0.82, and its evidence held the inversion's, so it replaced
it (`examples/metta/machine_failure_inversion.metta`).

**Capped root refinement.** Only a queried key at need depth zero, outside
any condition and outside forward evaluation, may also claim deep overlaps.
Nested keys retain the one-step rule. Root claims share one eighth of the
query's evaluation allowance, capped at 256 units (512 conditioned rows),
and also spend the ordinary remaining allowance. These internal settings are
`sk-root-claim-share` and `sk-root-claim-limit`. The share leaves room for
ordinary work and other claims; the fixed ceiling covers the cheap two-period
(26 rows) and four-period (308 rows) T8 cuts while bounding longer-history
retries independently of history length. Each input world receives its own
slice, as it receives its own evaluation allowance. Exhaustion retains the
last completed pass, or the factored summary. A root that spends its whole
slice without completing leaves the pending queue and sleeps until its live
sources or dependency support change, or a larger slice becomes available.
Numeric re-estimation over unchanged support updates its summary without
retrying the structurally oversized claim. Spending is accumulated across
exclusion reads of that key; roots receiving only part of a shared slice stay
pending. Dormant markers are scoped scheduling state and are excluded from
`conditions_unpaid` only while that key is not a queried root. A dormant
queried-root claim remains unpaid and makes diagnostics report
`budget_exhausted`. No extra work is granted to the next query.
Merge caches record root eligibility so a key
first read as a summary can be promoted when queried; a root result cannot
silently serve a later nested merge under a different policy.

**Approximation.** A completed claim resolves its retained cutset under the
views' formulas and existing weight, while deeper shared history stays
factored. Increasing the budget does not recover the omitted joint slices.
On T8 the branched product filter differs from exact by +0.00072 at four
periods and about +0.001 at six through twelve periods. This is a measured
model-specific bound, not calibrated posterior confidence. Partial passes
need not improve numerical error monotonically.

**Cost (#74).** Charge one evaluation unit for each pair of conditioned rows
actually run. The factor preserves the existing maximum of two conditioned
row evaluations per unit. All branches, deeper passes and nested claims draw
from the same remaining evaluation allowance, so exponential branching cannot
exceed that allowance. Reads of independent stored views cost nothing.

A conditioned value mixes its target's views under the two branches. It has
the branches' reference class and forward parts when they agree, as a revision
does, so a conditioned row combines with sibling rule views by odds, as the
unconditioned row would (test_overlap_conditioning, condSiblingKb). A claim an
exception left open is closed when the next query or forward run starts, so
its state never carries into later evaluations.

The dependency estimate (twice one plus the dependency count) orders waiting
targets after depth; it does not gate admission. A cut can replace a large
history by a known statement and recompute only a short suffix. Prepaying the
whole history blocked such a cut even when the remaining allowance covered
its actual work (SupplyNet timed stage 3 seed 3, #74).

An exhausted claim retains its deepest completed pass, or its waiting value
when none finished. Both branches must finish before a pass is eligible.

Except for dormant capped roots, the ordinary pending request remains for
later queries. Row views and the
skeleton survive; no execution stack is saved. Repeated allowances smaller
than one complete pass need not finish it, but larger allowances can replace
the waiting value and finish the retained conditioned calculation under
the existing formulas; nested deep overlaps remain approximations. Resolving more nested conditioning does not guarantee
lower numerical error for every intermediate estimate.

## Entangled premises

Premises of one rule application, or of a compound read off its parts, that
read one uncertain statement are not independent, whatever evidence they
name. E <- (Or C B) with C <- B multiplied P(C) and P(B) as if they were:
fuzzer seed 1000004, 0.342 against the exact 0.274. Evidence sets name only
the leaves, here the certain fact (A b), and certain facts never clash. The
statements are found in the premises' dependency sets instead. The
candidates are the keys within two levels of each premise's set node (the
premise's own key and the keys its row read, `deps-entangled` in
`runtime_helpers.pl`); a candidate two premises' sets hold, uncertain, not
given and outside the row's exclusions, is shared, ordered as above. That is
a few masked membership tests per row, with no space lookups (reading the
premises' rows from `&sk_row` for the same keys cost SupplyNet stage 3 timed
seed 3 budget 100 about 15%). Collecting both sets and testing every key they
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
only while the evaluation allowance can pay for actual conditioned rows,
and takes its approximate value otherwise; a clash there opens a claim of its
own against the same allowance. Conditioning every entangled row a
closed read met, on every statement it shared and unpaid, made 162 claims
and 151,538 conditioned evaluations in SupplyNet stage 3 untimed (seed 4,
budget 50): 59 s against 10 s, for no gain. Paid from the allowance, fuzzer
seed 12000203's E <- D over a closed D <- (Or B C E) with C <- B is exact
at budget 2000 (0.8975) and keeps the independent value at 100 (0.8179).

Rows reading a fold read its members as data and compiler-marked joins share
their sources by design; neither is checked. Inversions and completions have their own reading of their
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
of a signature of each sample, updated with the tally at constant cost per
take. Two derivations through different refined rules (applications, or
inversions and completions reading one) whose truths' folds have equal
digests are one estimate from one sample applied twice. Different forward-rule
conditions retain both proofs in a conservative revision, capped at the smaller
input confidence. This preserves their common estimate without claiming more
samples or choosing a condition by confidence. For the same condition or ordinary
non-rule proofs the existing representative behavior remains.

Compare the original surviving views before combining any of them by odds.
Otherwise the first copy can disappear inside a combination before another
copy is visited. Read each rule's own fold, unwrapping specialization priors: a
containing class's truth dependency is a prior, not another sample history.
Read these digests once per view during grouping; a conservative group retains
the distinct truth keys and their common digest for subsequent comparisons.

A sample's signature is what it observes: the facts of its evidence other
than its antecedent's stored facts, and the antecedent's strength (the share
of its mass in the positive branch). It is not the statement the sample reads
as its consequent. A task rule that makes one outcome the complement of
another, `(Implication (Reward left $t) (Reward right $t)) (CTV (STV 0 1)
(STV 1 1))` and its converse, with only the chosen outcome stored, derives
each unchosen one: `context -> (Reward left $t)` and `context -> (Reward right
$t)` then learn from the same stored outcomes, each the complement of the
other. Applied to a new case, the first rule's view of `(Reward left t)` and
the inversion of the second's view of `(Reward right t)` revised as
independent, counting every past trial twice (ONA matching-to-sample with the
rule: confidence 0.98 where the stored complements gave 0.86; in reversal,
with change detection, the two views came to disagree and their revision
fell to confidence 1e-6, so the agent stopped acting). With observations
as signatures the two folds have equal digests and the merge keeps one view
(`test_determined_rows.metta`). A member that is no sample adds nothing, so
two folds that have taken the same samples agree whatever members wait.

Counting the trials once makes rule mode answer as facts mode does, where the
harness stores both outcomes and no rule couples the operations: the desire
of a trained context falls from 0.9998 to 0.83 to 0.94 as the samples grow.
Ten seeds: conditioning, identity matching and reversal with change
detection at 1e4 stay at 1.000; reversal without change detection, where
the inflated confidence happened to help the retest, falls from 0.709 to
0.591, against 0.597 in facts mode.

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
  inverted over two priors; two rules over the same facts). Since #81 a
  binary-certain stored fact read as given never counts as shared, even when a
  rule concludes its statement; the consequence observation a likelihood
  update reads stays evidence, and soft or nonbinary reports stay shared
  ([runtime design assumptions](runtime_design_assumptions.md)).
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
  deepest pass it finished and stays pending; the work meter, not a retry
  price, bounds each query (#74).
- **No refusal of the weight's evidence was relaxed.** A mix whose weight
  shares evidence with its branches is still refused; the next statement is
  tried instead.

## The weight

K's value is read without views depending on the merged key. The mix is the
total probability over K when that value is K's probability given all the
evidence, the views' included. Evidence the views hold about K and K's value
does not, such as a report that tells the storm through the fuel, is lost to
the weight but still counts in each branch. A statement with stored facts
weighs by the merge of those facts and of the views whose evidence the two
branches do not hold, in either polarity, as a premise selects compatible
views (Jeffrey on what the branches do not already count). A soft fact of
confidence below 1 is expanded, so reports below the views invert into its
merged value; that value reads the same reports as the branches, and the mix
on it would be refused (#94: T8 with `Storm t1` at (0.6, 0.9) published the
waiting value). Those views drop out of the weight; a report, forecast or
derivation the branches do not read stays in it, so the cut agrees with the
chainer's own answer for the statement. Reweighting the stored prior by the
branches' own evidence (Pearl) is a separate decision (#91 B2). The branches
are evaluated before the weight. A derived statement weighs by its value as
read without the target, as before. The chainer
propagates observations up through inversions and completions, so a derived K
(Storm north t1 in SupplyNet) carries what reached it. The same holds for row
conditioning.

## Cost

Conditioning uses the remaining evaluation allowance, with no up-front
payment. A claim covers its target, branches, nested conditioning, and weight
reads. Each pair of conditioned rows takes one unit before its first row runs,
so the conditioned row count is at most twice the allowance available to
claims.
The exhausted marker prevents an unfinished pass from claiming completion.
Iterative deepening retains the deepest completed pass, or the waiting value
when none completed.
Closed reads use this same meter; deferred rebuilds stay within their existing
tier slice. The near-root reserve never pays for conditioning.

A pending target records a dependency-based estimate for ordering, with row
hash -1 denoting a key merge. Targets get ordinary turns nearest a root first,
then cheapest estimated, then oldest. A granted key drops its cached merge and
forces its readers; roots are read before these turns, so a root can condition
in its own query. The payment-level store and exponential retry prices have
been removed: the work meter itself enforces the query bound.

Earlier dependency-bound claims prevented runaway nesting (for example, the
five-period plant once took 238 s at budget 300). That cap is preserved as a
bound on actual work, rather than a conservative reservation per claim.

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

## Result of the cutset work (October 12)

Branch `cutset` against master bc9d106b.

- Fuzzer campaign (seeds 11-14, 1,000 KBs, `--shrink 0`): flagged KBs 53 ->
  46 (default 5 -> 5, all 25 -> 18, learned 4 -> 4, cycle 19 -> 19), none
  newly flagged. By family: F1 1 -> 0, F5 18 -> 17, F6 2 -> 0, other 3 -> 0
  (F3 18, F4 10, N 1 unchanged). Mean absolute error of answered queries:
  all 0.0132 -> 0.0107, default 0.0029 -> 0.0028, learned and cycle
  unchanged. Results in `/nexus/Dev/OpenCog/bench/results/fuzz/cutset/`.
- `bench/compare.sh` full: PASS; fuzzer gate 13 -> 8; StationOps belief
  streams identical; SupplyNet, scale, learned and replay accuracy identical;
  conflict pln-sources m moves by under 0.004 either way; time +2-7% per
  suite.
- `--curves`: SupplyNet stage 3 timed seed 2 at budget 200 0.00356 ->
  0.00287 (the base's error rises past budget 100, the candidate's less),
  untimed seed 3 at 25 0.00329 -> 0.00330, the rest identical. Conflict m s1
  (pln-sources) is slightly worse from budget 4 up (0.2615 -> 0.2654 at 4,
  0.2759 -> 0.2820 at 16).
- Conflicting sources size l, 4 steps per query, seeds 1-4 (ProbLog learned
  0.0197): pln-stated 0.0791 -> 0.0791, pln-sources 0.3585 -> 0.3565,
  pln-likelihood (400 review steps) 0.0328 -> 0.0342 (seed 3 0.0193 ->
  0.0256, from the entangled-premise conditioning; seed 1 0.0295 -> 0.0287).
- StationOps replay, seeds 1-4 (ProbLog Brier 0.0581): Brier 0.0597, log loss
  0.2065, regret 307.4, unchanged.

