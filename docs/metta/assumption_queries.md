# Queries under assumptions

Status: built, October 2026.

`Assuming` supports explicit existential facts, including among `And` facts,
and bare existential goals. It preserves local binder scope and never creates
a categorical witness from a non-constructive claim. An assumed implication
with variables is a rule of the query's world, as a stored one is (#127),
when its consequent is a plain statement: an assumed implication with a
nested-implication or existential consequent is rejected. Quantified
implications as Assuming goals remain unsupported; see
[existential queries](explicit_exists.md).

## Problem

A client often asks a question that holds only together with some facts: a
StationOps decision step reads the current leak beliefs together with the
step's candidates, costs and eligibility. Stored as facts, those facts and
the skeleton nodes built over them stay after the question is answered.
StationOps' decision steps left about 10,000 nodes after 20 shifts, and
action query time per shift rose 1.4 s → 5.7 s at a fixed budget
(`client_practices.md`).

An implication query, `(Implication A B)`, does not serve: it judges how
strongly A implies B, from the assumption alone. Its contexts borrow MAIN
observations only as fixed co-premises (#63), never the world's value of its
consequent, and keep only derivations that depend on the assumption (#65);
world facts about the statements it relates would otherwise make it hold
trivially ([derived implications](derived_implications.md)). A decision wants
the opposite: the world as it is, plus the decision's facts. Placing premises
in an implication query by what the assumptions affect broke the implication
tests (patches kept outside the repository); the two questions need two query
forms.

## Query form

    (: $prf (Assuming (And <fact> ...) <goal>) $tv)

answers `<goal>` as if the facts were stored, together with everything the
knowledge base holds, with proof `(assuming <proof in the context>)`, one
answer per binding of the goal's variables. A fact may be an implication: it
is then a rule within the query, which lets a client link stored statements
to the ones its question reads without adding rules to the knowledge base.

## Context

C is a value overlay on MAIN. It borrows MAIN's keys, rows, views, dependency
identities and evidence identities; opening C copies none of them.

- **What reads C.** Every rule instance is built once in MAIN and reads MAIN
  premise identities. C starts with its assumed facts, then reevaluates only
  the readers of values that actually changed. The existing dependency edges
  include inverse rules, antecedent completions and aggregate membership.
  An unchanged key reads MAIN's value. A changed row's local view replaces that
  row's MAIN view for C; older compatible views remain available to readers.
- **Cold dependencies.** Ordinary search and evaluation may build independent
  MAIN work during the context query. That work stays available to later
  queries. A cold merge read checks its actual local input values and runs in
  MAIN when none changed, including the read's aggregate/cache maintenance.
  No assumption-dependent value, merged cache, aggregate contribution
  or KB fact may be written to MAIN. Search may register an assumed statement's
  MAIN key and build joins over it, but MAIN has no assumed leaf to evaluate.
- **New producers.** Assumptions can enable a producer MAIN skipped as dormant.
  The assumption starts indexed joins structurally, without supplying a truth
  value. An assumed implication is an explicitly local input to its shared
  structural row; MAIN never applies it as a rule axiom. As a stored rule is,
  it is no premise of its applications: its key joins no row's dependencies,
  so applications to different entities stay independent.
- **Consistent evidence.** A premise borrowed from MAIN retains its original
  key, evidence and dependency identity. Conditioning and self-support exclusion
  use those same identities when it meets a C-derived premise. A borrowed
  scalar is never turned into independent evidence.
- **Folds and priors.** Folds share their MAIN member nodes and keys. Changed
  contributions, tallies, compatibility reads and merged views live in C.
  Unchanged aggregates are borrowed. MAIN's explicit user priors remain
  authoritative in C. An assumption-dependent aggregate update cannot alter
  MAIN's tally or cache. All writers of overlay stores use `context-add!`,
  `context-remove!` or their scoped exact-row helpers, including computed
  base-rate publication and invalidation. A source audit rejects raw MeTTa
  writes to these stores.
- **Existential queries.** Assumed `Exists` facts lower to canonical
  `ExistentialClaim` keys. Their bodies are not assumed. `ExistentialAlternatives`
  readers subscribe to those claim keys and to concrete witness populations;
  both propagate actual changes through the shared reader/fold edges. This
  replaces the former `assumed_head` / `pattern_head` affected-head tests.
  Binder freshening runs before Assuming facts or goals can bind one another.
  `compile-existential-query` deliberately compiles against MAIN: ContextQuery
  evaluates that same goal under C, preserving MAIN member and evidence
  identities. Scalar and grouped existential folds read C-local values when
  present. Private implication judgments still route witness folds into their
  hypothetical scope; their individuals are not world witnesses.
- **Implication queries.** The private judgment contexts of an `Implication`
  query retain their existing hypothetical semantics. The Assuming overlay
  does not turn them into world contexts.

### Propagation threshold

`(set-context-reuse-threshold threshold)` sets a process-wide nonnegative Beta
KL divergence threshold, default **0.000001**. Python:
`handler.set_context_reuse_threshold(threshold)`; timed workers replay it.
A plain STV's strength and confidence determine its Beta distribution exactly
as in forward chaining (`forward_units.md`); an absent value is Beta(1,1).
Both the open merge and individual row views are compared: a dominated row
can become the admissible input when a reader excludes the dominant support.
A change below the threshold does not schedule further readers. Utility arguments and other non-STV results are
compared as values, rather than assigned a meaningless Beta divergence.

At **zero**, compatibility and provenance changes propagate as well, preserving
exact evidence conditioning. A positive threshold is an approximation; it can
stop a small numerical update even when its provenance differs. MAIN's user
priors are inherited at every threshold.

### Accepted prior-inheritance correction

Given `P(Cause)=.3`, diagnostic likelihoods `(.9,.2)` imply `P(Effect)=.41`.
An assumed action predicting Effect at `.40` is slight evidence against Cause:
Jeffrey's rule gives `.4*.6585 + .6*.0508 = .2939`. With the current MAIN merge,
the answer is `.294434361302045`. The former private population prior was
accidentally based on the target's own `.8`-weighted observation, shrank to `.34`,
and returned `.3000469674834495`, in the wrong direction. The regression in
`test_pln_induction.metta` records the inherited result and this derivation.
Its matched `Hidden` completion has a certain-true `Enabled` sibling, so the
effective likelihoods, prior and hand computation are identical.

The inherited answer's confidence near `.98` comes from an existing MAIN
revision overcount. Correcting that merge is a separate issue; context reuse
preserves the current formula and merge behavior.

## Cleanup

After externalizing results, the query removes C's local evaluation entries,
its shadow markers and its assumed facts/rules. MAIN's assumption-independent
search rows, keys, views and aggregate maintenance remain reusable. Temporary
query adapters still follow the ordinary query lifetime. The overlay's values
hold references into the append-only proof and evidence stores; their ordinary
collectors reclaim unreachable entries after cleanup.

The invariant is **nothing assumption-dependent is written to MAIN**, rather
than a byte-identical MAIN store census. Test it both by comparing a subsequent
MAIN query with that query alone on a fresh KB and by auditing MAIN view,
merged-value, aggregate and fact provenance for assumption tokens. MAIN warming
is permitted; promoting an overlay value into MAIN is not.

## Budget

MAIN search uses the query's ordinary expansion and row allowances. Independent
MAIN evaluation runs first. Each C then receives a fresh evaluation allowance
scaled by the query's steps and the original near-root reserve. A preceding
context cannot spend another context's allowance, so N contexts may spend N
allowances (#55). Contexts in a batch share
structure and the query's total expansion budget, while evaluating their
separate input worlds independently. A context
query leaves no live overlay to continue across calls (persistent contexts are
outside this implementation).

## Evaluation

1. Unit tests:
   - an assumed fact combines with a main-context belief;
   - the subsequent MAIN answer equals the same query on a fresh KB; MAIN
     views, merges, aggregate observations and facts have no assumption
     provenance or dependency, and C has no surviving entries;
   - an unaffected premise is read in the main context, and its existing
     answer is reused without expansion.
2. Full suite.
3. StationOps: decision steps as `Assuming` queries over the step's facts.
   Proposals equal the reference oracle. Over a 60-shift live game, action
   query time per shift stays flat without forgetting, and memory grows as in
   a replay without actions (about 5 MB per shift).

## Historical results before the overlay

These measurements describe the earlier private-context implementation. The
overlay replaces its head reachability and context-link cleanup.

StationOps live temporal-model games (ChainerGame `single-kb-actions`),
query budget 50, action budget 15 per candidate, forward slice 150.

- **Decisions.** The reference oracle test passes. Over 60 shifts (seeds 1
  and 2) regret is identical to the former design with one knowledge base per
  decision (1310.9 and 636.1).
- **Time.** Action query time per shift stays flat (about 2 s per shift of
  three decisions, shift 1 to 60), against 0.3 s → 38.6 s for the
  knowledge base per decision, whose forward runs also grew to 14 s per
  shift. A 60-shift game takes about 3 minutes instead of 32.
- **What made time grow, and was fixed.** Leftover contexts;
  each decision's fold compiling its conjunction adapters again as permanent
  rules (one compilation per pattern shape now, `sk-shape-members`); every
  query rule dropping every dormancy verdict (query rules now wake by head);
  scanning every stored fact for the affected heads; quadratic evidence-set
  operations.
- **Memory.** Before cleanup, contexts were 58% of skeleton rows. At shift 60
  of seed 1, clause storage is 417 MB (1,315 MB before cleanup; 346 MB
  replaying the same game without decisions) and RSS 1,129 MB (1,605 MB;
  514 MB). The remaining RSS gap, about 8–10 MB per shift, is SWI-Prolog
  virtual-machine code of erased clauses that clause garbage collection
  does not reclaim in the full game. Neither plain SWI churn nor isolated
  `Assuming` loops (mixed with `query_many`, forward runs and fact additions)
  reproduce it. Open.
- **Cost of cleanup.** Recording and removing a context's link digests costs
  3–4% of decision query time (paired 20-shift runs).

## Existential assumptions (tracker #51)

A complete `(Exists ($x ...) body)` assumption, including one among the `And`
facts, adds a contextual direct `ExistentialClaim` with scoped canonical slots
and TV (1,1). It does not add the body's facts or a witness. Rules consume it
through the same existential premise judgment as bare queries; a bare `Exists`
goal reads that judgment in the context. The ordinary world facts and rules
remain available as before. Local binder names cannot become free goal
bindings, and answers freshen binders while preserving free outer sharing.

Affected-head analysis treats the assumption as `ExistentialClaim`. An
existential population can be affected through either its direct claim or its
witness-body predicates. Both scalar and grouped existential folds read the
appropriate context. This is the integration contract for the ctx-overlay
branch; it introduces no new context store or alternate routing system.
Quantified implications as Assuming goals, assumed implications with an
existential consequent, nested binders and `Not Exists` are not supported. See [explicit_exists.md](explicit_exists.md).

## Weighted assumptions (tracker #120)

A bare fact is assumed certain. A fact written as the annotation `compileadd`
takes, `(: name statement tv)`, is held in the context with that value
instead, alone or among the `And` facts, next to bare ones:

    (Assuming (And (Candidate s1)
                   (: bridge (Implication (PlaysTennis Bob) (PlayingTennisNow Bob)) (STV 0.12 0.2)))
       (PlayingTennisNow Bob))

The annotation is the source form of a stored input. A weighted assumption
adds evidence; it does not set the statement's value:

- a closed ordinary fact with an STV is a stored soft fact. Read directly, it
  answers its own STV. On a key MAIN also holds, it is one more stored report,
  merged with MAIN's facts by revision;
- `(: name (Not statement) (STV s c))` stores the statement with
  `(STV 1-s c)`, as `compileadd` does;
- an implication with an STV or a CTV is a rule with that truth value. It
  consumes MAIN facts and sibling assumptions. Its variables are the rule's
  own, as a stored rule's are: they are standardized apart from the goal's and
  from other assumptions', even under the same name, and each application
  binds them anew. Applications to different entities are independent, as a
  stored rule's are (#127).

This matches the same inputs added to an isolated KB, with these known
limits:

- an assumed CTV implication whose key MAIN already states does not combine
  with MAIN's rule as two stored rules do (#123); an STV one does;
- a judgment of an assumed implication itself, an `Implication` goal on its
  key, has no answer: it reads no stated value of an assumed rule, where an
  isolated KB reads the stated rule. The rule's applications share its
  evidence identity, as a stored rule's do, so they cannot support it;
- a rule that reads a base rate (a variable STV rule's population branch)
  reads MAIN's population, which does not count the weighted fact. Only a
  certain assumption, which gives that branch weight zero, matches an isolated
  KB (#124);
- names are labels, not identities: two facts with one name count as two
  reports, where `compileadd` rejects a second value under one name (#113);
- a variable only in a rule's consequent is Skolemised with the assumption's
  context token, which differs per query, where a stored rule uses its name:
  the value is the same, the answer term is not stable across queries;
- rules that form a schematic cycle read their population as #124 describes,
  so a cycle's values can differ from an isolated KB's.

The name labels the assumption in the answer's statement; the proof names the
assumption's context token, as for a bare fact. Any other annotation is
rejected with `domain_error(weighted_assumption, Annotation)` (message
`unsupported weighted assumption`) before the query runs, never read as
certain or as a colon-headed predicate: a missing or open TV or name, an STV
outside [0,1], a CTV on a fact, a TV that is not an STV or CTV (the KB stores
no distribution-valued facts; a distribution is an argument of a statement),
free variables in a fact (an implication's variables are its own), an
implication with a variable side or a nested-implication or existential
consequent,
and connectives, binders, computations, rule wrappers, `Inheritance` or
`Assuming` as the weighted statement. Weight each conjunct of a conjunction
separately. An annotation in any other statement position is rejected the
same way: the goal, a nested `And`, `Or` or `Not`, an implication query's
antecedent, or the inside of a weighted statement. An annotation inside a
predicate argument is data.

As for bare facts, nothing that depends on a weighted assumption is written
to MAIN, and a later plain query cannot read it.

## Source-gated existential witnesses (tracker #66)

A single `Assuming` can enable a concrete witness through source-gated rules,
including a rule deriving a negated property. The existential witness fold
reads the same conjunction TV as the exactly matched ground query. Its public
answer retains a lexical binder; the concrete witness stays inside the search.
Both source proofs survive, and acceptance and derived event values remain local.

Conjunction pooling keeps individual premise parts until their source
computations have run. A lowered `Not` complements its last fact read before
pooling, so a later `AndFormula` does not restore the uncomplemented TV. This
also applies to ordinary conjunction queries, in every conjunct order. It does
not fix ordinary disjunction queries: an `Or` with a negated disjunct is still
computed as the conjunction of its disjuncts (#85). Raw
projection source names are resolved in the premise's own KB context; a source
with the same name in another KB cannot supply its pooling TV.

`Assuming` is only the query's outermost statement. Anywhere else (its goal,
its facts, a conjunct, a `Not`) it raises `domain_error(nested_assuming, ...)`
(#125). Nesting needs child context-query planning and evaluation that
inherits the enclosing world's values; a single top-level overlay does not
provide that composition.
