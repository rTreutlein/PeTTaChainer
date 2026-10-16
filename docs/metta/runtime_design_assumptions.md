# Runtime Design Assumptions and Goals

This document records the semantic and performance constraints of the compiled
PeTTa chainer. Read it before changing compilation, proof storage, caching, or
either chainer. A locally convenient optimization is incorrect when it violates
one of these assumptions.

Potential performance ports from the sibling native implementation are tracked
in [mm2_followup_candidates.md](mm2_followup_candidates.md).

## Logical model

### Knowledge addition is monotonic

Adding a fact or rule only enlarges the available proof space. It does not
replace or retract an existing fact, rule, proof, or evidence item.

If another proof of the same proposition is found, both proofs still exist
logically. `&kb` keeps each added fact; readers merge a statement's facts, and
that merging is evidence accumulation, not mutation of the proposition.

Consequences:

- Never describe an addition as "changing A". It adds another proof that may
  contribute to what is known about `A`.
- A previously valid proof remains valid after any addition.
- Evidence identity must survive materialization so the same evidence is not
  counted twice when forward and backward paths meet.
- Double negation preserves evidence identity. Negation toggles fact polarity
  and cancels its own evidence wrapper; applied rule identities and exclusions
  retain their identity regardless of conclusion polarity. Projection positions
  are proof metadata, never evidence. A stored proof reference carries its
  computed evidence set, including applied rules, rather than reconstructed
  leaves of the printed proof.
- Overlapping proofs are not independent evidence. Disjoint proofs may be
  revised together; overlapping paths need dominance, refinement, or cycle
  checks before aggregation.

Explicit rule withdrawal is separate from monotonic addition. Hypothesis
review and the deprecated statement-removal path both retire compiled rule
identities. Later reads exclude every derivation using them, including cached
views. Each immutable proof records its permanent owner identity in its existing
metadata word, alongside its negation bit. Transitive rule provenance is resolved
through the shared proof DAG only when retirement checks or exposed KB copies
need it, then cached as a canonical interned set id. Ordinary backward reads
at retirement epoch zero
allocate neither provenance sets nor a per-proof cache. Publishing a derived KB
copy is a separate operation: even at epoch zero it resolves provenance and
registers each copy once against its canonical rule-set id. Shared Patricia
nodes record child-to-parent edges. Withdrawal follows those edges from retired
rule leaves to affected sets and their copies, visiting each node once. Copy
registration and removal do not enumerate source rules; republishing replaces
one registration. Provenance resolution still pays for previously uncached
proof DAG nodes. Index storage is O(set nodes + copies).
A stale liveness memo checks subsequent retirement events or the set's leaves
against the retirement index, whichever is smaller. Proof ids remain durable
and never reusable.

Derived facts exposed in `&kb` (forward copies, materialized answers and
forgetting summaries) are indexed by their canonical source set. Withdrawal
removes affected copies and their fact indexes, so direct KB readers obey the
same semantics. A mixed forgetting summary cannot subtract a contributor:
removing it thaws the key and queues reconstruction from live rules. Its
conclusion-indexed join digests are removed so old delivered joins can rebuild
the erased rows. Join keys and links use the same 60-bit digest contract.
Retired waiters remove themselves on their first subsequent delivery. Closed
reads and needs remove encountered retired waiters, deferred work and rows,
including their pending counts and optimization registrations.
Withdrawal costs the ancestor set nodes and affected physical copies; it does
not scan row or proof history. Rule-id sets use canonical Patricia trees:
regrouping or repeating a union returns the same id, while shared branches avoid copying transitive lists.
Membership follows one rule-id bit path, even when the retired rule belongs
to another proof. Union memos, provenance nodes and liveness memos are
collected in metered phases of the proof/evidence collector; root marking
follows each shared tree node once. Each demand-built proof-to-set cache entry
and summary-user registration leaves with its proof. Retirement-event rows
older than any live set can need, and events naming no surviving set leaf,
are collected too; permanent rule retirement
identities remain for later cold reads. Retirement growth also triggers a
collection when no new proofs are being stored. The first provenance read resolves its reachable uncached DAG nodes once; subsequent reads
reuse those sets and check at most the smaller of the retirement delta and
their distinct rule count. Withdrawal itself never walks the proof DAG.
The stored owner is encoded as id+1; zero denotes no permanent owner and never
aliases real rule identity zero.
Direct references to frozen summaries register when a proof is published. Their
historical source metadata survives physical summary retirement and collection
until the referencing proof has captured its rule set, or is itself collected.

### Strict append-only follow-up

The public `remove-compiled-statement`, cache `clear-*`, and replace-style
configuration operations predate the decision that ordinary system history
should be append-only. Statement removal remains callable only for compatibility
and is deprecated; normal reasoning and knowledge ingestion must not depend on
it. Removal does not erase durable proofs or reset the monotonic proof ID counter.
It now retires the removed rules and their derived KB copies as described
above; retired skeleton rows contribute no later value and leave optimization
stores when encountered.
Removing a binary-certain fact after its joins have been retired leaves its
owner expanded with those joins gone: the search does not restart. This
deprecated interaction is outside the monotonic contract.

A future API pass should represent corrections, supersession, and configuration
changes as scoped events instead of retracting prior knowledge. Explicit proof
forgetting needs its own temporal or scope policy and must not be smuggled into
statement removal. Query-local rows and replaceable cache/index rows are not
logical retractions as long as deleting those optimization tables would leave
the unbounded logical answers unchanged.

In particular, negative or empty-search cache markers may keep one mutable
best-known budget per key. They are not assertions of falsity. Matching new
knowledge should refine the registered cache contribution directly; unrelated
monotonic additions do not invalidate the approximation.

### Compilation specializes reasoning

The compiler turns source facts and rules into the relations and rule shapes
needed by the chainers. The runtime should use those compiled relations instead
of recovering general-purpose PLN rules dynamically. Generic runtime rules
defeat the purpose of the compiler and add avoidable search branches.

A rule concluding an implication holds as its exported form, `A → (B → C)`
as `(A ∧ B) → C`, and the statement it derives is applied by modus ponens
through one compiled statement rule per implication shape, found by its
consequent like any rule ([derived_implications.md](derived_implications.md)).

A rule and the adapters compiled with it (the projections of a compound
conclusion, the connective of a compound antecedent) share one context
pattern, so they hold in every context the rule applies in. An implication
query's private contexts borrow MAIN observations for independent fixed
premises, including their compiled projections. They never borrow an observation
of their own consequent key, its instances, or its negation: P(B) does not
establish P(B given A). An assumed key overrides its world value, and a hypothetical individual cannot bind to a world individual.
Rules hold there: S → (A ∧ B ∧ C) answers S → (A ∧ B).

`Inheritance` may receive compiler-specific lowering and querying, but its
ordinary compiled implication reasoning should use the same chainer machinery
as other relations. A genuinely different semantic operation, such as member
lookup, may remain a separate path.

### Cached base rates are estimates, not exact memoized answers

There are two kinds of base-rate entry:

- `user`: an explicit estimate supplied by the user. It is authoritative until
  explicitly cleared or replaced.
- `computed`: the current value of the pattern's one estimate. The estimate is
  a tally of per-member contributions (`&forward_aggregate_observation`, keyed
  by aggregate and member). Forward steps and backward folds only update it: a
  member already counted has its contribution replaced, never added twice.

Adding a fact or rule does not invalidate a `computed` entry. It still
summarizes valid evidence; it may simply know less than a later fold. A
backward query may use it immediately and schedule a live fold that adds the
members its search finds.

Base-rate invalidation is reserved for non-monotonic or interpretive changes:

- removing facts, rules, or supporting proofs;
- changing or clearing runtime prior parameters;
- explicitly clearing or replacing a base rate.

Setting or clearing a base rate marks dirty only the folds that read that
pattern's cache entries, in any fold mode; they and their readers recompute at
the next evaluation through the ordinary change path. Nothing else is dropped.

The important tradeoff is intentional: a tightly budgeted query may initially
use an older estimate. Add-time work must not eagerly make every cached estimate
current.

### The backward chainer keeps a durable skeleton

The backward chainer keeps the structure of search across queries, in
`runtime/skeleton_journal.metta`. Nodes, answers, joins and permanent rows are
append-only; truth values live only in views, which evaluation recomputes when
something below them changes:

- a **node** is an expanded goal pattern: a fact goal
  `(statement context proof tv)` or a fold goal
  `(CPU FoldAllCompiled args result)`;
- an **answer** links a node to a **key**, a statement in a context (or a fold,
  or one group of a grouped fold) that matches it;
- a **partial join** is a rule application waiting on its next premise node;
  every answer of that node extends it once;
- a **row** is a complete join: a rule instance with bound premise keys and no
  truth value.

A rule applies to a node when its conclusion fits the whole node pattern, but
its row is built from the statement and context alone: a row belongs to its
key, and each reader applies its own proof and truth-value pattern. A ground
instance one of whose premise keys is its own conclusion's builds no row: it
would read the statement, its stored facts included, to conclude it again.
A row reads each premise at the key that extended its join. An open key (a
fact stored with variables, an implication with its own variables) holds
for every value of its variables, and later premises that bind them do not
change the key read: the instance is no key of its own and has no rows. The
variables the join left open stay linked to the key, so evaluation binds
them through its value.

For the backward chainer, ingestion only journals added facts and rules. The
next query activates them against the skeleton before its walk: a rule reaches
the patterns already expanded, and a fact is read by every node that reads its
key (expanded nodes and the ground premises joins wait on, expanded or not)
and, through the rule it is a premise of, by each unexpanded node the skeleton
holds for that rule's conclusion, where that rule alone is started
([fact_absorption.md](fact_absorption.md)). So evidence that arrives after a
search reaches the keys it built, without the search returning to them. A
missing fact premise must keep its ordinary partial join subscription: an
expanded node never restarts its rules merely because a fact was added. This
also holds for rules deriving compound outputs whose projections already
expanded without an answer. Fold-member compilation may abstract constants
only in user predicates and connectives entirely over them. A connective
with an implication or other compiler-specific child keeps its original
shape; abstracting that child changes how the query compiles and can leave
expansion unfinished with temporary waiters still installed.

Rules compiled for one query (query adapters, implication scaffolds) leave with
it: their rows, waiters and views are removed and the keys they fed change.
Producers that depend only on the pattern (the Member inheritance producer of a
concrete `Inheritance` link, the compiled source of a fold pattern) are
installed once as permanent backward rules, so their rows outlive the query.
An implication premise of a permanent join likewise installs its own permanent
scaffold, including its private assumptions and consequent metadata. A temporary
scaffold from an earlier query cannot supply that lifetime, even when the
premise node is already expanded. Reuse checks the exact statement up to alpha
renaming, proof/TV constraints and producer lifetime. The private contexts keep
their existing world-reading restrictions; no assumption becomes a MAIN fact.

### Assuming shares MAIN structure and overlays dependent values

An Assuming query builds rows and keys in MAIN, with MAIN premise identities.
Assumptions may enable a dormant producer, but structural discovery supplies no
assumed truth value to MAIN evaluation. Independent MAIN search, views and
aggregate maintenance performed during the query remain reusable. A cold merge
read executes in MAIN when its indexed rows/member keys have no actual local
input value; this includes all cache, conditioning and aggregate maintenance
performed by that read. It is not a possible-reachability test.

C owns only assumption-dependent evaluation entries and its assumed facts.
A local row view replaces that row's borrowed MAIN view in C; no borrowed key
or evidence item acquires a new identity. Merged caches, conditioned reads,
aggregate contributions, instance regimes and propagation bookkeeping follow the
same evaluation scope. None of them may publish an assumption-dependent value
to MAIN. Computed base-rate publication, removal and invalidation use the
same scoped write API as their aggregate observations and states. Raw MeTTa
mutations of an overlay store are rejected by the write-boundary audit. Cleanup
drops C without retracting independent MAIN work.

Existential assumptions lower to canonical claim keys, never categorical
witnesses. Freshen binders before the Assuming plan shares variables with its
goal. MAIN-scoped existential compilation is intentional inside ContextQuery:
scalar and grouped folds keep MAIN member identities and read C-local values.
The direct-claim and witness channels follow the existing dependency edges;
no affected-head analysis is needed. Empty existential-fold subscription reads
must use the overlay facade too. Private implication judgments retain their
hypothetical fold routing and shared-variable constraints.

Search expansion is shared across a batch. Evaluation is per input world:
MAIN and each context receive the query's evaluation allowance and initial
near-root reserve independently. Earlier contexts cannot exhaust later ones.

Propagation follows the existing readers, including inversion, completion and
fold membership. A plain STV update propagates beyond a configurable Beta KL
threshold (`set-context-reuse-threshold`, default 1e-6), with a missing value
read as Beta(1,1), as in forward chaining. Compare individual row views as well
as the open merge: self-support exclusion can expose a dominated alternative.
At zero, provenance and
compatibility changes propagate too. Non-STV values, including utility arguments,
require value comparison. Two results of an open key are different when their
statement arguments differ, even if their STVs agree.

The overlay's native bootstrap must remain compatible with the pinned library
load cache. Initialize mutable settings as runtime entries, not source-owned
dynamic facts. The cache prelude can consult a native source twice, so generating
the static read facades must be idempotent. A cold load and a cached replay must
both support Assuming and leave MAIN free of the assumed value.

MAIN's authoritative user priors are inherited. This intentionally corrects the
old private-context prior's self-inclusion and can change Assuming answers; the
Jeffrey update and accepted numerical exception are documented in
`assumption_queries.md`. It does not correct MAIN's separate stored-target /
inversion revision confidence overcount.

### Truth values are views, recomputed from what changed

Evaluation computes each row's **view**: its conclusion from the premises'
values by the rule's formulas, with the evidence behind it and the hashes of
the keys it depends on, transitively. A view's proof is one rule application
whose premise proofs are references into `&proof`; the full proof tree is built
only for output. Stored proofs refer only to earlier ids, so they form a DAG. A
row keeps its latest view and the views it replaced, and later queries read
them until something below them changes.

A reader excluding keys cannot assume that a rejected merged row view has
no admissible proof. An ordinary read serves a compatible cached incumbent
or older view and queues the missing branch; it holds the consuming reader
through the existing stale-reader path. The deferred tier runs after ordinary
work and restales, using at most one eighth of the query's evaluation allowance
within that same allowance. Requests survive queries until settled or their
row is retired. Nested rebuilds run inside that tier's remaining slice, with
exclusions carried through their premises and each rebuilt row charged to
the evaluation allowance. A row
whose owner or a mandatory direct premise is excluded cannot contribute.
Direct facts and closed reads also respect the active rebuild frame's
original exclusions: a direct observation must not bypass that test, and
closing an excluded key must not recreate its value as unfounded. Closed
reads may still use their own local pins; those pins do not weaken the
enclosing rebuild's original exclusions. A branch with no admissible support
settles empty with its exclusion cut, so its request can finish and later
reads reuse the empty result.
Rebuilt branches are cached across reads and queries, separately from ordinary
views, with their exclusion cuts. A settled branch built under E1 serves E2
only when its dependencies are disjoint from E2 and its cuts are a subset of
E2. Each rebuild records only the exclusions that rejected branches, including
cuts propagated by the child branches it reads. Every exclusion rejection
uses the same predicate, which records cuts only inside a rebuild frame.
Cuts are immutable sets:
forgetting may shorten proof dependencies, but must not shorten exclusion
cuts.

Each cached row registers its direct input keys. A changed input marks its
branches stale and follows only those cached readers; ordinary views remain
valid. Stale rows leave the input reader lists until branch publication
subscribes them again. A positive unfinished rebuild can publish a stale
incumbent, restricted conservatively by the entire exclusion set; it cannot
prune settled contexts. Stale compatible branches are incumbents while rebuilding is unpaid,
never settled cache hits. A semantically changed branch result schedules the
readers in its request's exclusion context again; each reader excludes its
own key. An unchanged settled refresh does not force an equivalent proof
publication. A rebuild outside the ordinary need closure pays its own
conditioning from the tier slice, without granting payment to the ordinary
view. Branch settlement follows actual unpaid work inside its frame, not an
ordinary view's pre-existing conditioning debt. An unpaid nested rebuild holds the consuming reader
through evaluation and stales that reader after answers are read; it does not
stale the producer whose ordinary view is still valid. Successful settled
rebuilds prune dominated contexts, each row retains at most eight contexts,
and row/key retirement removes its branches and subscriptions. Cached proof
references are roots of the existing proof collector and cached dependencies
are roots of the dependency collector. Branch entries, owners, dirty markers
and input readers use the same scoped store interface as ordinary views, so
an Assuming overlay can invalidate borrowed branches without changing MAIN.

Branch invalidation follows changes to input truth values, evidence or
dependencies. Publishing a fresh proof reference for the same view, clearing
a merged-value memo, or marking an ordinary row stale does not itself change
that input. New external facts and changed row views still invalidate their
indexed branch readers. A conditioning grant is scheduling state: a settled
branch has already paid its own conditioning. A queued request that is
already settled, or a rebuild identical to its cached incumbent, must not
stale or reschedule readers.

On an unchanged KB, repeated queries with enough allowance must finish
pending search, conditioning and branch refreshes, reach a stable answer,
and then perform zero branch builds and zero row computations. Cache
maintenance must not restart that work on the next identical query. This
quiescence contract allows finite-budget transients; a transient cold answer
is not an oracle for the fixed point.

A certain truth value, confidence >= 1, stands for unlimited evidence in
revision. Only a stored binary-certain fact, STV strength 0 or 1 at confidence
>= 1, is absorbing for search retirement: no other proof can change its value
even under conditioning. Such a key's value is its certain stored facts
alone: views its rows got before the fact
was stored add neither evidence nor dependencies. Only stored facts end the
merge this way; a derived view of confidence 1 is a probability known
exactly, not the statement's truth, and merges as below. A statement known
by a stored fact of strength 0 or 1 is that fact to every reader, conditioned
ones included, so a join of an open node builds no row for it either: such
rows only spent the evaluation's allowance, and the need walked on below them
(test_known_history_rows: an Assuming context reads a known history through
an open node, the base rate an antecedent completion reads, and its fold
over the decision's outcomes had no value at budget 8). A statement stored at
confidence 1 with another strength keeps those rows: conditioning ranks it
by the dependencies of its rows' views.

Searches already started for a statement that becomes known are obsolete
optimization state too. Partial joins are indexed by their bound conclusion,
as well as by the premise they await. Storing a known fact queues retirement
by that statement and context; activation and query cleanup erase bounded
slices of its waiters, deferred work and extension digests. A join whose
conclusion is already known starts no fact waiter and cannot be extended by
later answers. Its current keys are still read once, including the aggregate
registrations before the completed-row check. Child links have waiter
leases and fixed claims indexed by their actual join conclusion, so retiring
one bound conclusion of an open search leaves its other conclusions searchable.
Waiters store a shared continuation template derived from the immutable compiled
rule at its premise position, plus bindings and the awaited node. The template
widens context/proof slots without imposing variable sharing absent from the
actual join. Delivery reconstructs the original partial; original open keys and
their sharing survive. The static, read-only `&sk_wait` relation owns no waiter clauses and is not
created as a mutable space. Making its source clause dynamic prevents the
pinned runtime from snapshotting the library load.
Cleanup erases compact payload clause references and removes each template with
its last subscriber.
Delivered join digests also lease their waiter's exact payload reference,
selected before the answer binds its open slots. Removing a waiter queues its
digests for the existing 512-unit retirement slices; each unit erases one digest
and its conclusion ownership. Thawing a summary still erases digests by
conclusion, and removes their waiter leases through the same retract listener.
Transient joins without a stored waiter retain their conclusion ownership.
A waiter batch computes its child-link digest once and passes it to the
waiter, child and fixed-claim stores. A waiter lease records that digest and
the waiter's clause reference; retraction finds the digest by the reference,
without copying or hashing the partial again. Ownership records retain only a hash, store kind and clause reference; reads
check the actual key on the owned clause (delivered joins check their existing
60-bit conclusion digest). Retiring a search node erases the exact selected
index clause. Several proof/TV-constrained nodes can share a MAIN key and node
hash; pattern-based `retract` leaves alternatives that replay the rest of a
query on backtracking. Retirement and search must remain semideterministic
when contexts reuse those MAIN nodes. Functional subscriptions use a distinct store kind
so a hash collision cannot confuse their key with the conclusion key.
Ownership, claim and debt cleanup
uses their existing scalar clause-reference or digest columns, rather than
duplicate reverse predicates.
Fact-watch cleanup uses the node hash already available at expansion or
context cleanup and compares only subscriptions at that hash.
A known owner can still have a child claimed by another conclusion. Query
adapters reading a known statement retain the same exemption as completed rows.
An unowned link to a pending premise still provides shared search work to
later queries; retiring that traversal early changes finite-budget answers.
It stays indexed by its pending component until that component settles,
then leaves in the same bounded collection slices, without a graph scan.
Dropping a pending representative also removes its child-retirement debts
and queued component retirement, so context cleanup cannot orphan either.
An unexpanded ground premise also used its waiter as a late-fact subscription.
Retirement compacts those subscriptions to one node record in `&sk_fact_watch`;
expansion or context cleanup removes it. Fact activation reads these nodes
alongside expanded nodes and live waiters, so retiring a join loses no shared
key or aggregate input.
Incoming links and parked answer deliveries belong to surviving consumers and stay. Reclamation unlinks
only released edges and drops isolated pending nodes; ordinary context
cleanup retains its existing component accounting. Facts, completed rows, views, sample
contributions, regimes and leave-one-out indexes do not leave with search
work. A fractional confidence-1 fact retains its backward derivations for
conditioning, as before.

An optional `set-functional-predicate` declaration gives an input relation
immutable single-valued keys. It also declares that relation positive-only;
only ground certain-true main-world inputs may populate it, and no rule,
including a temporary query rule, may derive it. A conflicting tuple is rejected
before that fact is published. An unassigned key stays open. This deliberately does not infer
negative facts for every other value: those would invent negative-antecedent
samples. It is not a declaration about uncertain or derived values.
Waiters whose key arguments are ground share the existing ownership index and
retirement queue under a private functional key. Assignment retires incompatible
subscriptions in the same bounded slices; compatible ones consume their answer
before releasing their leases. A node that already has its unique functional
answer reads that key directly without allocating a new subscription or
producer traversal: the declaration forbids other producers of that relation. Delivery keeps the pre-extension subscription:
extension may bind its variables and change its node hash. An open subscription
with unbound key arguments remains live. Shared pending premise traversal and
ordinary context bookkeeping retain their existing rules. Assignment records,
input history, completed rows, views and learned samples are retained.

Retaining missing-input joins costs subscriptions when input-only predicates
are undeclared and their facts never arrive. The review's nested fixture
measured about 57% more waiters per step after removing ground-fact pruning.
For an immutable single-valued input relation, declare
`(set-functional-predicate $kb $head $arity $key-positions)` before ingestion.
Once a ground key is assigned, its incompatible subscriptions retire and
matching subscriptions close after consuming their unique answer, as above.
Unassigned keys and subscriptions with unbound key arguments stay open.

A rule stated with confidence 1 in every branch is given, not estimated: its
applications carry no evidence of it. A rule stated with less, or refined from
its instances, is evidence of every proof through it, so a proof of the rule
itself (its axiom) and a proof through it are one piece of evidence. Proofs
that both apply a rule to different premises are not: given the rule's truth
they are independent, whether that truth is given or estimated, and its
uncertainty enters each proof's confidence.

A key's value merges its stored facts and one view per row:

- an identical proof pools its evidence; a marginal projection gives way to its
  full proof, and a settled step to its complete step, before the views merge,
  so neither stands for its full proof in a merge with a third view;
- before lifting or other aggregation, original applicable rule views are
  compared by syntactic containment (reversed for complements), including
  mined parent/child rules. Counts and confidence do not rank conditions;
- a containing general view supplies the specific estimate's prior. Its
  weight accounts for uncertainty of the general estimate and heterogeneity
  κ (`set-bayes-prior-count`, default 0.2), as described below. General views
  revise into one prior, whose confidence sets the weight, and the original
  specific estimate is shrunk once; `specializes`
  records both TVs. Derived implication applications include their source
  conditions. Prior observations do not enter the specific likelihood's
  evidence; its proof and refresh dependencies retain the general class.
  The existing semantic generalization path remains where the conditions
  do not overlap literally, including the penguin/bird example;
- two views are independent when their evidence is disjoint, or when each
  holds evidence of its own and they share only known facts that no rule
  concludes (premises either reads as given), rules (as for rows: a rule's
  truth, its `RuleTruth` key included, is a parameter of both views, not an
  event either observes) and no statement whose value is uncertain (by their
  dependency sets, so a derived statement both read counts, not only shared
  leaves);
- inversions and antecedent completions over one prior through different
  observations combine by Bayes' rule (a completion observes its consequence;
  a sibling it reads as certain, alone or inside the compound of the other
  parts, is conditioned on, not evidence it shares; so
  is, for a complete statement, a certain complete premise of its rule
  application that the update observes, `complete_predicates.md`), and an inversion over a base rate combines the same
  way with a derived, uncertain view independent of it, which
  takes the base rate's place (`docs/metta/prior_factored_merge.md`);
- independent views otherwise revise, except that forward views (rule
  applications) of a predicate whose stored outcomes prefer odds or noisy-OR
  by a Bayes factor of 10 combine by that mode
  (`docs/metta/combination_modes.md`);
- two derivations through different refined rules whose truths were folded
  from samples observing the same outcomes (equal digests of their instance
  folds) share one sample: different rule conditions retain both proofs by
  conservative revision with confidence capped by the smaller input; ordinary
  proofs retain their representative behavior. The history never told the rules
  apart (`overlap_conditioning.md`, "Sample twins");
- of dependent views, the one whose evidence strictly contains the other's
  is kept; two that share uncertain statements condition the key's whole
  merge on them, a budgeted cutset: the merge with the statement of most
  impact known true and known false, mixed by its value, a branch whose views
  still share one conditioning on it in turn, as deep as the claim reaches
  (`docs/metta/overlap_conditioning.md`); otherwise, or while the
  conditioning waits to be paid, or where a pass stops at its depth, the
  views are grouped into connected components by shared statements or
  observations. Sibling forward-rule views combine by prior-factored odds;
  the conservative unpaid result unions evidence and dependencies and caps
  confidence by the smaller input confidence. Paid conditioning recomputes
  and combines those views inside its branches. Same-condition and ordinary
  non-rule proofs retain their existing representative behavior.
  Independent components merge, preserving evidence outside the overlap;
- when every proof of the key is modus ponens over conjunctions of facts, the
  proofs share fact premises, and their residual evidence is nonempty and
  pairwise disjoint, the lifting merge factors the shared facts out, revises
  the residual implications, and applies the shared conjunction once. It
  requires a strength linear in the shared conjunction (a two-point round
  trip); sibling rule conditions instead combine by odds inside the shared
  conditioning path. Otherwise views merge pairwise. Lifting applies to a key's merged
  value; compatible selection below merges pairwise.

No value supports itself. A consumer reads, per row of a premise key, the
latest view that depends neither on its own key nor on any key unifying with
it; older views stay available to exactly the consumers a newer one came to
depend on. An estimate from a rule's instances is the exception: an
implication instance fold carries no member dependencies, and a consumer
reads it without the samples that read a key it excludes, its tally less
their contributions, which are found by the keys they read; a row reading
such a fold (a refined rule's truth) is evaluated again for it. So a refined
rule applied to an instance reads its truth without that instance's own
sample (leave one out), at the cost of the samples left out, instead of an
older truth that knew fewer instances. A rule's truth is a parameter: a rule
application depends on the truth's key, not on the instances it was learned
from, so two views through rules learned from one history share no
observation through them. Because dependency sets are transitive, this rejects self-support
through inverted rules, longer cycles, and more general or more specific keys.
A value carries its dependency set as one interned node id, a union of its
premises' nodes, so it stays one integer however long its history; whether a
set holds a key is a walk pruned by each node's bitmask of key hashes
(`dependency_tracking_design.md`). Its evidence is one interned set id too,
the set's entries kept in the order they were added, so equal evidence is an
equal id and set tests run over integers ([evidence_sets.md](evidence_sets.md)).
A compound And or Or antecedent is lowered into its parts, so what a rule
concludes from it depends on the parts' keys and never on the compound's; a
row inverting such a rule into the compound therefore also excludes views that
depend on any of its parts. A part whose certain stored fact is its
connective's absorbing value (a true disjunct, a false conjunct) settles the
compound alone, through a rule variant reading only that part, whose join
builds a row only for such a part; its view gives way to the complete step's
when both exist (`connective_settling.md`).

The chainer is open-world: a statement with no proof is unknown. A KB may
declare a predicate complete (`complete_predicates.md`): a rule application
of a complete statement reads a complete premise none of whose views it may
read as that premise's rows evaluated again with the reader's conclusion
unfounded, `(STV 0 1)`, and a complete statement no rule application derives
is unfounded; both only once the statement's search is settled (its general
node expanded, no rule application of it waiting on a premise not yet
answered, nothing deferred), so a budget cut never concludes false. The pin
cuts circular support; it is no observation, so an inversion or completion
reading the pinned statement as its consequence gives nothing.

Premises are selected by the consumer. Evidence of a certain fact, strength 0
or 1 at confidence 1, never counts as shared: a join over it is exact either
way, however the evidence names the fact (a fact proof name read off a proof
term, negated under a Not, is looked up by that name). A factored merge's
evidence is its prior view's and its updates'; the population base rate
(`cpu`) and the prior's truth value it names are not evidence. A premise whose value shares other fact evidence with what the row already used is replaced by the merge of that key's
facts and views that share none; a shared rule is not a clash, except a rule
the row excludes: an implication instance sample excludes the rules restating
its implication, so it reads the consequent's other proofs. Premises are taken greedily in order; when every
value of a premise clashes, the row reads again on a fresh copy, taking
compatible stored facts first. Projections of one stored `(And ...)` source pool
back into that source instead of multiplying shared evidence, and
compiler-marked joins may share source evidence deliberately. A projection of
a compound onto one part reads the other parts as evidence apart from the
compound, so it reads none of their views that depend on the compound's key:
P(A) = P(ABC) / P(BC) with P(BC) read off ABC would be 1. A projection that leaves the
part undetermined (a true disjunct, a false conjunct) gives no value rather
than one of confidence 0. A child of an inverted pure `And` or `Or`
antecedent is recovered by completion, not projection: the completion is
Bayes' rule over the child's base rate with the other parts at their values
(`prior_factored_merge.md`); a part with no value of its own is read where
the child leaves the compound open, the child given false for an Or and true
for an And, so a root in a loop of complete predicates observed only through
the loop is updated by it (`overlap_conditioning.md`, "Completions").

A clash that survives the fresh read is resolved by conditioning, not refused.
The row is evaluated with the statement of a shared fact known true and again
known false, and the two results mix by modus ponens over that statement's
value, so the shared evidence counts once. Under a condition:
- a known statement reads as certain, with no evidence;
- a view depending on one is its row evaluated again under the same
  condition, excluding what the enclosing rows exclude, so the recursion
  follows only views that used a shared fact and cannot cycle;
- a compound And or Or with no value whose rows read a given statement
  directly is those rows evaluated under the condition, once along any path
  (read off its parts, it had no value because the part had none);
- other views, and folds, read as stored.

A branch that still clashes over another shared statement conditions on it in
turn. A premise that reads one of the shared statements itself reads it as
known under the condition, so a row reading K and a value derived from K, or
K twice, is exact. A complete premise's closed value conditions like any
other. There is nothing to condition when the clashing value is a projection,
or when the conclusion is not a simple truth value; such premises are refused
as before. The mix needs the weight's evidence to be outside the
branches; when it is not, the next shared statement is tried.

Premises can depend on one another without sharing uncertain evidence: E <-
(Or C B) with C <- B, all from the certain fact (A b), multiplied P(C) and
P(B) as independent. A rule application's (or a compound's) premises that
read one uncertain statement, found in their dependency sets, are
entangled, and the row is conditioned on the statement as on a clash. Such a
row has an approximate value, the premises read as independent, which it
keeps while the conditioning waits; a clash has none and derives nothing
until it is conditioned.

Evaluation starts from what changed: new rows, and the readers of keys changed
outside evaluation (added facts, removed query-local rows, fold members). Rows
are computed in creation order, except that a query computes the rows it pays
for from its allowance after the others (see below). A recomputed view is kept only when it brings
support, a dependency the row never had; the keys a row can depend on are
finite, so evaluation ends even though inverted rules make real skeletons
cyclic. A change from outside the rows forces each reader once per evaluation
and per causing key, and a forced reader whose value changes passes the change
on to its own readers the same way, so a refined fold reaches the roots. A row
never computed is not forced: its first view changes its key whatever caused
it.

### Folds and base rates

Existential witness folds are open-population judgments, not exact population
summaries. They return no value when empty and retain subscriptions in that
state so late evidence can wake their readers. Their disjunction uses the
ordinary premise fact-overlap test; a shared uncertain rule is not overlap.
An outer strength floor compares this witness judgment to the direct claim
without revising the two. Exact strength ties prefer more evidence, then a
canonical statement-key order. Correlated witness bounds carry only the chosen
witness's proof and evidence, while retaining every member dependency.
Bare queries and premises use the same lowering. The residual alone uses the
empty witness identity (0,1). Empty-view invalidation and nested forward-fold
draining added for existence are restricted to existential folds.
These folds recompute over their members and need no closure certificate or
new store. See [explicit_exists.md](explicit_exists.md).

A fold's or group's view is computed from its member keys when first read and
recomputed when a member changes; the members changed in one pass recompute it
once. Members are read without views that depend on the fold itself. Base-rate folds estimate a population: they carry neither member evidence nor member
dependencies, like a prior, and are proved by `cpu`. An implication instance
fold is a tally of its samples' contributions too, proved by `cpu`. It carries
no member evidence either, so its estimate revises with a rule's stated truth,
and no member dependencies. Its samples read no value that depends on a
refined rule's truth, since another hypothesis's prediction is no
observation of the consequent, nor one derived through the implication they
sample. Each branch of the tally keeps its samples as regimes of the rule's
rate (`set-rule-change-hazard`, on by default): an old segment, the current one
and a candidate run since a possible change, each a sum of contributions, and
the branch's estimate is the posterior mixture over which segments share a
rate. Each sample is scored once, when it first gets a value, so the order is
the order values arrive; a segment that merges into another leaves an entry in
`&sk_instance_regime`, so a changed member or a leave-one-out read reaches the
segment holding its sample (merges keep the larger segment's id, so the chain
grows only logarithmically). A branch's work per new sample is constant (at
most five hypotheses), and nothing is cut while the branch holds at most three
distinct regimes. A `FoldAllTruth` fold
reads its members' truth values as data and is treated the same way, so a rule
can fold a group's beliefs and read one member of the group again.

A refined `RuleTruth` key is a live model parameter, not a historical
instance eligible for epoch freezing. Its row keeps reading the instance
fold even while no query asks for the rule; freezing that row made a later
read return an old summary and stopped later observations refining it.
Ordinary historical beliefs retain the configured freezing and decay.

Keys with a row directly reading a fold or group are replayable caches,
including `FoldAll`, `FoldAllValue`, `FoldAllTruth`, base rates and instance
folds. Each row registers in `&sk_aggregate_row`, indexed by its conclusion
hash and exact key, even with forgetting disabled. Retirement removes the
registration. Idle aggregate readers are evicted rather than converted to
historical summaries: their local join digests leave and their matching
search nodes become unexpanded, with one pending work item. A later demand
replays the compiled rules against current inputs; no summary can preserve an
old aggregate value. Existing subscriptions are reused, so replay creates no
waiter per query. Active searches and consumers keep the ordinary need/touch
policy; reading a fold alone grants no permanent liveness.

Population-fold members and incidental keys feeding aggregate rows through
open searches are replayable too. The latter have no independently expanded
node of their own. Otherwise an inverse population search left one summary
of a forward deduction per newly observed member. Classify the idle batch
before dropping any rows, so classification does not depend on freeze order.
These tests use key/reader indexes, not a history or dependency-graph walk.
Authored facts and incremental population contributions remain. Ordinary
historical summaries retain freezing and decay. When the last current or
stale reader of a fold leaves during eviction, its cached views and merged
values leave too. Generic folds still read all their members when demanded.
Their evidence join interns one final ordered union rather than every prefix.
Frozen member markers are unique across repeated need/freeze cycles. Proof
collection is metered by allocated proof words as well as proof count, so
large exact-fold proof snapshots do not wait for 4096 new proof records.

An exact fold (`FoldAll`, `FoldAllValue`, `FoldAllTruth`) needs all its
members. While its search has members still to come (members whose rows are
stale, uncomputed or waiting for conditioning; premises of its member node
that can still be answered; a member node not yet expanded), it is partial:
it proves by `(partial-fold covered total proof)`, a conclusion drawn from it
has its confidence scaled by the share covered, and a value depending on it is
provisional, merged only when its key has no other value. A partial fold a
query needs is checked again at each evaluation
([partial_folds.md](partial_folds.md)).

A base-rate fold is incremental, since its population grows with everything
ingested. It keeps its accumulated evidence and each member's contribution. A
stored fact counts in the base rates observing it when it is added, its
statement with its stored facts merged, as a removal recounts it: one lookup
of the aggregates interested in its head. Whether a forward run or a search
reaches the fact does not change what the rate counts. A derived
member that joined or whose value changed is taken again, replacing its old
contribution, when a query needs the fold or it is next read. A member's
change that came through the rate itself is not taken again: the rate does not
count that version, and a past belief read through the rate would otherwise
change, be needed and be recomputed every time the rate moved. Nor is a member
taken again whose new view left its open merged value the same, outside the
rate's dependencies: the rate takes that value, so it has nothing new to take.
A labelled past member gaining its first derived view under its fact is such a
change; taking it again made the next query reaching the rate need every such
member and compute its history rows ahead of the current period's, at equal
depth by creation, until the allowance ran out (SupplyNet scale l at 16 steps
per query: error 0.0042 against 0.0015 without). Needing the fold
needs only those members, not the population. A member whose inputs changed
while no query needed it keeps its last contribution until a query recomputes
it, so a base rate may lag the members' current values; every step costs the
members that changed. Inheritance-weighted members count at unit mass and the
evidence is scaled by the current subject mass when the fold finishes, so a
growing universe does not leave contributions stale.

A conjunction whose conjuncts fall into parts sharing no variables ranges
over the cross product of the parts' instances, so its base rate is exactly
the product of the parts' rates: each part is folded on its own and the rates
are combined, instead of folding over every combination. A separate user joint
override on such a disconnected pattern is rejected before cache mutation;
component rates remain configurable. Ground conjuncts
stay with a part, since a single instance multiplies nothing. While a part
has no counted member the product has no evidence, as one fold with no
member has none (`BaseRateProductFormula`), so an STV rule over such an
antecedent still applies, with the negative branch of unknown base rates.

A KB may opt into base-rate smoothing, which reads every computed base rate
as its n observations plus k pseudo-observations at 0.5: the strength of a
rate over few observations then stays uncertain, while its confidence is
still n/(n+k). The smoothing is applied where a fold's value is finished, so
cached rates carry it too.

A base rate is the user's value when one is set. Otherwise an unexpanded fold
reads the cached estimate, and an expanded fold takes its members into the
tally and reads the tally's value, which is published to the cache. An entry
the tally did not produce gives way however confident it was: partial work may
be confidently wrong. Storing the value the entry already holds is skipped,
since every store wakes the folds over the pattern.

A base rate counts each member without the member's values derived through
that base rate. Otherwise a rule inverted with the rate as its prior concludes
members of the rate's own population, the estimate becomes its own evidence,
and keeping it current means iterating a fixed point through every past
member. The fold's own take reads members with the fold excluded, as a
computed fold does; a forward take reads the taken key with the base rates it
is a member of excluded. Only stored facts count as seeded or remaining
members: a forward run's copy of a key's value is reported by the run itself.

Bayes' rule and inversion read a likelihood estimated from finite evidence
under a prior centred on independence: the pooled P(B) of both branches,
or P(B) for P(B|A). The configured heterogeneity count κ
(`set-bayes-prior-count`, default 0.2; existing API names retained) is no
longer a fixed prior weight. Add the centre estimate variance
`g(1−g)/(n_g+1)` and subclass heterogeneity variance `g(1−g)/(κ+1)`, where
`n_g = c_g·k/(1−c_g)`, and convert back to pseudo-observations:

    a = max(0, 1/(1/(n_g+1) + 1/(κ+1)) − 1)

A certain centre has no estimate variance and gives `a = κ`. An uncertain
centre reduces the pull; for finite counts a positive weight requires
`n_g·κ > 1` (at default κ, counts at most 5 give zero). With κ large relative
to n_g the weight approaches n_g, and with n_g large it approaches κ.
Specificity uses the containing general view's confidence; STV inversion
uses P(B)'s confidence before reconciliation; Bayes' rule pools branch
counts and converts their sum back to the centre's confidence (certain if
either branch is certain). This changes only the strength read from the
likelihood, not its evidence count. At k=1,
general (0.25, 0.7), specific (0.99, 0.4) now reads 0.99, since a clamps to
zero, rather than the fixed-weight 0.8192307583. κ is configured, not
estimated from sibling spread.

Without a prior, a false-alarm rate estimated as 0 from a handful of cases
can make every alarm certain. A base rate read as the prior of an inversion
or a completion is the prior of one more member, read the same way, centred
on the given 0.5 (confidence 1, so a = κ): a rate of 0 or 1 from finitely many
members leaves an instance either way possible, so its
updates keep their likelihood ratios. A predicate whose stored instances are
only its true ones is declared positive-only (`set-positive-only-predicate`)
and has no empirical prior. An explicit user base rate overrides that sampling
restriction; setting or clearing it updates existing readers. A certain likelihood, a certain rate, and the instance
prior are read as they are.

### Queries read what their roots reach

A query walks the skeleton best-first from its roots. Expanding a new node costs
one step of the budget (one more for each 400 words of the node, see below); walking through an expanded node spends a separate walk
allowance of one per step, so revisiting what is already built never takes a
step from new expansions, and once the allowance is spent expanded nodes are
passed over while the walk goes on. The walk enters only nodes whose search
may still have work (below), so the allowance is spent only on them. A node's
priority is
the best value any join waiting on it gives it: the owner's value times the
rule's expected confidence, shared among the premises still open. Equal scores
go first to the work of roots already started, shallowest first, and then to
the roots not started yet, in insertion order: the budget completes the
answers it started before it starts new ones. Once the budget is spent, nodes
it cannot pay for are passed over and the walk goes on, so expansions that
cost no step (below) still complete the joins the paid ones started; the paid
expansions of a larger budget extend the same prefix. A multi-root query
shares one budget and one order.

A node's search may still have work while it, or a node below it, is
unexpanded or holds parked deliveries, deferred joins or deferred rows: the
only things walking an expanded node does are resuming that work and pushing
its children. Below any other node everything is expanded and nothing waits,
so walking it changes nothing; the walk neither pushes nor enters it, and a
warm query walks only the paths down to work, whatever the size of the
skeleton. Work appears outside the walk too (a rule or fact activated on an
existing node starts joins whose premises are new nodes), so the index of
pending work is kept current where work is created and taken, not by walks:

- Every child link, and every node with work, belongs to a component of
  the skeleton's cycles. Skeletons are cyclic (inverted rules; a rule's truth
  reads its instances, whose samples read the consequent the rule derives),
  and every node of a cycle reaches what any other reaches, so pending is a
  property of components. The components form an acyclic graph; each
  counts its nodes' work items (being unexpanded, each parked delivery,
  deferred join and deferred row) and its pending child components, and is
  pending while either count is positive. A change of state moves its
  parents' counts, up to the first parent whose state stays. So the index is
  exact at every moment, a lookup is a union-find step, and taking the last
  work of a cycle of any size leaves the whole cycle idle at once
  (`runtime_helpers.pl`, "Pending work").
- A child link whose child's component reaches the owner's closes a cycle:
  the components on the paths from child to owner merge. A child without
  children or an owner without parents (a new node, a new root) closes
  none. Otherwise the test searches forward from the child and backward from
  the owner, each turn expanding the component that keeps the two searches'
  link counts nearer, until one side is exhausted, neither passing the
  other's start; the components that side found whose links within it lead
  back to the other start are the ones to merge. It costs about twice the
  smaller side, so linking new work under a large component never reads
  that component's links (SupplyNet scale l: 21,134 links, 5,512 closing
  cycles, 0.5 s of a 26 s run).
- Assuming overlays borrow MAIN's components: cleanup removes no structural
  child links. Ordinary node retirement releases a component when its last
  node leaves; context-local value entries have no separate search graph.

The index changes which nodes the walk reaches only where the walk allowance
was spent before: nodes without work no longer spend it, so a walk that ran
out of allowance on them now reaches work beyond them, and its answers move
toward those of an unlimited allowance. With the allowance unlimited the
answers are the same with and without the index (SupplyNet stage 3 untimed
b100 s4, stage 3 timed learned b50 s1, conflict m spq4 s2), apart from
equal-score ties broken by push order and depth: a node without work is no
longer pushed, and children linked during the walk are pushed with the depth
of the next node walked. ONA matching-to-sample, 10 seeds by 3 tasks:
identical decisions; desires moved in 3 runs, from trials where the walk had
run out of allowance with deferred work below.

Stored facts cost no expansion: a join waiting on a ground fact premise reads
its facts at once, and whenever more are stored, and a root reads its own
stored facts. An open premise waits for its expansion, which bounds recursion.
An open node below the roots whose statement grows a term of an open node
whose rules were started (binds one of its variables to a compound, as `(Num
(succ $x))` does `(Num $x)`), other than a root of the current query, starts
no rules: it
reads the general node's answers that unify with it, and a child link to the
general node lets walks through it resume the general search. Every rule
concluding the instance concludes the general node, whose joins wait on
premises at least as general, so the general search finds every key the
instance's would. Without it a recursive rule read through an open node
unrolls without bound: the base rates of `(Num $x) → (Num (succ $x))` read
`(Num $x)` and `(Num (succ $x))`, the inverted rule asks `(Num (succ (succ
$x)))` of the second, and so on, one open node per step, each answered by
every key below it (ONA reasoningbench_num: the second query of four took
minutes and the run hit a SWI segfault at 569 s in `sk-row-present?`). A mere
specialization, such as `(Reward op1 $t)` of `(Reward $op $t)`, keeps its own
search, which a budget spends on that case first: subsuming those too moved
SupplyNet stage 3 timed (error 0.0027 to 0.0039 at budget 50) and StationOps
replay (Brier 0.0446 to 0.0497 at budget 50). A root subsumes nothing, since
its rows always fit the allowance below.
A node no rule can conclude (other than an implication or inheritance link,
whose expansion installs rules) is expanded without a step when the walk
reaches it: its expansion only reads its stored facts. It keeps its place in the walk, so its facts extend joins
when its priority says so (reading them at once filled the row budget early:
StationOps Brier 0.0652 against 0.0607 at the smallest budgets). Before any state is created, a rule
whose ground computation cannot succeed is pruned. A ground fact premise
without a fact or concluding rule still keeps its waiter: that input can
arrive later, and the node will not be expanded again. New
rows have an allowance of ten per step, except the rows of the query's own
roots, and a row costs one more for each 400
words of its statement, what storing, hashing and comparing that much of a
term takes beyond a row's fixed cost (`term-cost`); rows beyond it wait with
their node and are completed when a later walk reaches that node, so leftover work never
spends an unrelated query's budget. Facts stored since the last query are the
exception: they are delivered first, before the next query's walk, from an
allowance of their own (ten rows per new fact and per step), as the deferred
cost of ingesting them.

Evaluation then brings current only what the roots read: their keys, the
premise keys of those keys' rows, and the members of folds and groups among
them (for a base-rate fold, the members it has yet to take). Implication
instance folds are the exception: every evaluation also brings current each
instance fold that rows read and whose members changed, with the keys
reading it, a refined rule's truth above all, as it does a root's. So a new instance
moves its rule's truth, and the search score read from it, at the next
evaluation, whatever the query or forward run asks, at the cost of the
members that changed (`hypothesis_rules.md`, "Instance tallies"). Any other
row whose input changed is marked stale, once, together with everything
reading it (the rows the query needs once it has read its answers, below); a
later query that reaches it recomputes it. A stale row leaves the reader lists of the keys it reads until
then, so a change walks only readers that are current. Rows built for earlier queries therefore cost nothing
per query or per change.

**Determined rows.** A row whose rule is deterministic (stated with
strength 0 or 1 and confidence 1 in every branch) and whose premises are all
certain statements, reading no fold or group, is determined: its conclusion
is certain, as a stored fact is. It is computed when it is built and
whenever its premises change, whoever needs it, at no cost to the allowance;
a stored fact that makes a stale reader of its key determined brings that row
back among the key's readers. Its key then changes as a stored fact's would:
readers no query needs go stale, which brings an implication instance fold
over a sample reading the key current at the same evaluation, and a base rate
over the key takes it when next read. So an outcome a deterministic rule
derives from new facts counts as a sample and as a population member at the
next query, whatever it asks, without a query reaching it: with
`(Implication (Reward left $t) (Reward right $t)) (CTV (STV 0 1) (STV 1 1))`,
a stored `(Reward left t) (STV 1 1)` makes `(Reward right t)` an
observation, as storing it would (ONA matching-to-sample with the task rule,
`test_determined_rows.metta`). Before, such a row no query needed was left
stale, whether it was built after the fact arrived or, as in a trial whose
outcome both operations' queries had predicted, computed from the prediction
before it: the derived outcome of a past trial never reached the tallies, and
the client had to query it. A determined row is computed once per change of
the certain facts it reads, so the cost per new fact stays bounded, and its
value does not depend on when it is computed. One step only: a key a
determined row derives is not a stored fact, so the rows reading it are
computed when needed, as before. A rule given with an intermediate strength
determines a probability, not an outcome: its application is evidence to be
weighed with the rest of its key and waits for a query. Taking those too
computed 3,620 more rows in SupplyNet stage 1 (b100 s3, 7,105 in all), whose
rules are given conditional probabilities, for about 15% more time.

Evaluation is bounded too. A needed key records its depth, the fewest rows or
folds between it and a root, found breadth first so each key is reached at its
least depth on its first visit. The members a base-rate or instance fold has
yet to take are visited after every key reached otherwise, one level past the
deepest: such a fold estimates a population, so each member moves its readers
by one member's share, and a member on a path the roots read through keeps
that path's depth. Counted one step below the fold, a base rate near a root
put its whole population, every past observation of the pattern, two steps
from the root, and the history rows reading the rate took the allowance
before the periods nearest the present (SupplyNet stage 2 b100 seeds 1 and 2:
error 0 to 0.00006 and 0.0004; scale m spq16 0.0009 to 0.0011 on seed 1).
The rows and folds of keys within two such
steps are computed at any budget, from a reserve the need fills with eight
computations for each one it reaches there; what the reserve cannot pay for,
and every deeper row, spends an allowance of two computations per step, and
what neither can pay for is left stale, to be recomputed by a later query that
reads it. The reserve bounds the rows near a root by the size of what the
roots read, not by the passes their cycles take: rows reading one another
through inverted rules recompute whenever their support grows. Depths found
depth first put some keys two steps from a root at depths 13 to 28, whose rows
then spent the allowance; with correct depths those rows count as near, and
the reserve keeps them bounded. Evaluations take far fewer than eight per row
(ONA relationalnetwork, ChainerGame
`benchmarks/ona/nal_pln/relationalnetwork.metta`: 1,020 computations for 620
rows in its first query at budget 200; SupplyNet stage 2 up to about four), so
no benchmark answer changes. Within a pass the rows within two steps come
first, by creation, and the deeper rows after them, nearest a root first and by creation within a
depth. The allowance thus goes to the rows nearest a root, whatever order the
search created them in: when a query builds many rows, the ones it created
first are often far below its roots, and spending the allowance on them left
the rows the roots read stale (SupplyNet stage 3, mean posterior error over
seeds 1–4 and budgets 25–200: 0.00348 by creation, 0.00323 by depth). The
order does not depend on the allowance, so an allowance that covers everything
computes what an unbounded evaluation would.

A row's computation from the allowance, like its creation, costs more the
larger its key (`term-cost`), so a step costs the same however large the terms
a recursive rule builds; the reserve near the roots is left by count, since it
covers what the roots read. Below the two steps the need passes through rows
never computed nearest a root first; a row of a large statement spends what
its size costs beyond a row's from as much as the allowance can compute, so a
recursive rule that builds ever larger rows faster than they are computed (a
base rate's members through `(Num $x) → (Num (succ $x))`) leaves a backlog the
need does not walk: walking it made each query of ONA reasoningbench_num cost
0.17 s more than the last; bounded, 32 queries at budget 100 take 1.0 to 2.0 s
each. Rows of ordinary size pass as before: the need also takes base rates'
changed members, work the allowance does not count, and capping their count
left members untaken that SupplyNet scale l reads (spq16: error 0.0015 to
0.0026) and moved conflict m at 16 steps per query (0.2754 to 0.2937).

A stale row is brought current only when a need reaches it within those two
steps, as a query asking for it does. A deeper stale row keeps its value and
stays out of the change path, so what no one asks for is never recomputed: a
base rate that every past belief read moves on each new observation, and
refreshing the stale history behind a current belief would cost as much as the
history. Beyond the two steps, need passes only through rows never computed or
waiting to be conditioned. A current row's inputs are current, because every
change reaches the readers of what changed, so nothing under it needs
recomputing.

While a query's evaluation runs, the stale cascade does not stale a row the
query needs: the row stays linked and keeps following the changes the
evaluation still makes. A row goes stale keeping its view, so the key it
concludes keeps its value, and a needed reader of that key is held until the
query has read its answers and then marked stale with what reads it, so
between queries a current row's inputs are current. A fold that goes stale
drops its view and is recomputed when read, so a needed reader of it is
computed again in a further pass, each time that happens, and reads no value
from before what it needs. Staling needed readers at once, with one refresh
per evaluation, froze the rows nearest the roots partway through it: when the
allowance ran out on a row of an old period's front, the cascade staled the
front's chain up to the current period, whose storms and blocks then kept
views of inputs that moved after them (SupplyNet scale m spq4 s2: error
0.0071, 0.0038 with the rows held; which zone froze depended on where the
allowance ran out, so an unrelated change of walk order had moved it from
0.0042). A forward run stales those rows for the query that next needs them:
refreshing them there would recompute every needed reader of each fold the
new facts move, which grows with the knowledge base (StationOps at 20
modules: forward time +106–243%; leaving them to queries: +1–10%).

mm2-chainer marks staleness differently: a changed key adds a dirty record
(`sk-dirty row cause`) to each direct reader, readers are never unlinked, and
a query evaluates the dirty rows of its whole needed closure, without a depth
limit, in creation order within its budget. A dirty row the budget cannot
reach keeps its record and a later call evaluates it; nothing propagates
staleness upward, and no row is refreshed once and then frozen. So it does
not have the flaw above. If it bounds its need by depth, as this chainer
does, it should hold the rule above: during an evaluation a needed row stays
linked and keeps being evaluated, and the outdatedness of rows above an
unpaid row is recorded only once the query has its answers, so a later
need knows to come back down to it.

Conditioning is paid for from what that allowance has left, never at depth
zero for free. A row whose clash needs it waits, keeping the views it had; an
entangled row waits the same way, taking its independent value if it has no
view; a key whose views overlap waits with the independent merge of its
components' most confident views. The full dependencies of discarded views
still connect their component, so transitive overlaps cannot split it. Each waits with a cost of 2^l times its base, one more than
the dependency count of what it conditions, at level l, 1 at first. Once the
rows are computed and the roots' merged values read, the waiting rows and
keys the query needs are paid for nearest a root first, then cheapest, then
oldest. What a payment covers, the claim, evaluates at most twice its cost in
rows under a condition. A target with an approximate value conditions in
passes of growing depth, the number of statements conditioned on along a
path, a conditioning nested deeper taking its approximate value, and keeps
the deepest pass that finished; a clash conditions at any depth in one pass.
A claim that would take more stops, keeps what it finished, and waits at the
next level, twice the cost, so a larger allowance conditions on more
statements and nested conditioning never multiplies past what was paid
(`overlap_conditioning.md`, "Budgeted cutset conditioning"). A row is recomputed conditioned, with its
readers; a key drops its merged value and forces its readers, which read it
conditioned. Either may add waiting rows or keys. The first one the allowance
cannot pay for stops the payment, so a larger allowance extends the same
prefix, and the rest wait for a later query that needs them.

A root reads the answers of every node of its statement and context, whatever
their proof and truth-value patterns, and drops answers that instantiate
another answer with the same proof; a ground root also reads its own key. When
the search has no value for a key, a materialized answer an earlier query left
is returned as the incumbent; it is never revised with the current value,
since it is not independent evidence. Without one, a ground root answers its
population prior, `(population-prior <pattern>)`: the base rate that one of
the rules concluding it reads over a pattern its statement belongs to, the
prior its inversions update, at the confidence of the members it counted.
Reading it costs no expansion, so every such root has an estimate at any
budget, and any view the search finds replaces it. It is the prior an
inversion reads, and a positive-only predicate has none. The prior is the
population's value, not the statement's, and it is never materialized.

A ground statement in the main context that no rule application concludes
and that is not complete is a root of the model: inversions and completions
conclude it from evidence, but nothing derives it. When its node is
expanded, a row of its key reads its population prior from the base-rate
fold, so the prior follows the rate; the key reads it only while nothing
else gives it a value. Only an antecedent completion reads it as a premise:
the likelihood of the consequence it inverts marginalises the parts it does
not complete over their values, and a part nothing tells about is at the
prior of one more member of its population. Its row answers only the
completions waiting on the node. No other row reads a population prior: a
derivation from it would present the population's value as the instance's,
and an inversion or a sample would read it as an observation; folds do not
count it either. So a rule reading an unobserved root premise with nothing
observed below it still concludes nothing, while an observation of a
compound's consequence updates each part (`fuzzing.md`).

A materializing query writes back its first answer and, for every statement
that answer's proof uses, that statement's current value. Materialized facts are never leaves of later searches: the
backward chainer re-derives them.

## Performance goals

### Atom addition should be constant time

Adding one compiled atom should perform only a bounded number of indexed
lookups, inserts, and small state updates. In particular, an addition must not:

- scan all facts in the KB;
- scan or delete all cached base rates;
- rebuild an agenda from the KB;
- traverse the rule graph or all downstream conclusions;
- eagerly run forward or backward inference.

When strict constant time is prevented by proof merging or the underlying
index, keep work proportional to the candidates for the one affected output,
not to total KB, rule, cache, or agenda size. Record pending work and charge it
to the later operation that requests reasoning.

Internal exact-map side tables must expose a selective scalar as their first
argument to the generated Prolog predicate when benchmarks show that compound
same-head keys scale poorly. Key ground terms with `term_hash` and retain the
complete key in the row so unification rejects hash collisions. A variable-
bearing exact key may use a coarse scalar hash provided a nonbinding alpha
comparison checks the full key; a more selective `variant_hash` must justify
its cost in lookup benchmarks. After selecting an open row by alpha identity,
do not remove it with an unifying pattern: use a ground unique row ID or erase
the exact selected clause reference. Never hash indexes whose purpose is
structural or variable-bearing pattern matching.

`&kb` is the exception that shows the limit of SWI's own index: a statement is
a list, and the JIT indexes it by its head only, so a lookup by head and
arguments walks every fact with that head, across the whole history. Each fact
is therefore also stored in `&kb_prefix` under the hash of every ground prefix
of its statement (its head with its first one, two, ... arguments, up to the
first argument with a variable). A fact whose statement has variables is also
stored in `&kb_open` under the hash of exactly its longest ground prefix (its
head's when it has none, 0 when its head is not an atom). A lookup reads
`&kb_prefix` under the pattern's longest ground prefix, which finds the facts
whose own ground prefix is at least as long, and `&kb_open` under each shorter
prefix of the pattern, its head and 0, which finds the rest; it still unifies
each candidate. So a lookup costs a bounded number of indexed reads however
many facts share its head, even when facts with variables arrive with every
step (one open `ImplicationInstanceSample` key per Pong decision made the
truth read and the fact add grow linearly with the history while they read
one store that held them all). Readers that bind only a statement's head read
`&kb` directly. The skeleton's registered keys are indexed the same way
(`&sk_key_prefix` and `&sk_key_open` beside `&sk_key_terms`), and so are the
open reading keys whose unifier sets a new key joins (`&sk_reader_prefix`,
`&sk_reader_open`). Rule premises are indexed the other way round: each in
`&prem_prefix` under the hash of its statement's longest ground prefix, so the
rules a ground key is a premise of are found by hashing the key's prefixes.

A store's first column must be what tells its rows apart for the lookups that
run every step. A constant tag (`&forward_aggregate_observation` rows began
with their constructor name), or an id every row of a large group shares
(`pw_out` rows of a component with one child per decision), makes each such
lookup read the whole group: key the rows by a hash of the real lookup key, or
answer the question from a count kept per key (`pw_deg`).

### Reasoning work is lazy and budgeted

`compileadd` stores knowledge; it does not silently perform inference. The user
may run forward chaining after one or many additions. Queries and chainer calls
must respect their explicit step budgets.

Rule priority is a value-of-computation estimate, not a claim that a proof will
succeed. Base-rate strength describes statement probability, not the
probability of finding a proof: a low-strength proof is still a useful answer,
so rule priority does not use base rates. Searching a base-rate fold's members
is valued by what one more member could add to the estimate's confidence.

Forward chaining starts from facts selected by its caller, or continues the
agenda earlier runs left, and grows the backward skeleton upward from them (`runtime/backward/upward.metta`,
[forward_skeleton_unification.md](forward_skeleton_unification.md)).
- Taking a key starts, for every rule premise the key matches, a join with
  that premise bound. The join's other premises read the stored facts and the
  keys the skeleton already has, never expanding anything. A complete join is
  an ordinary row. Its owner is the rule's conclusion, and no node is marked
  expanded, so a later query still starts every rule on that pattern.
- The rows reading the taken keys, including rows that went stale, are then
  needed and evaluated by the ordinary evaluation; the need stops at those
  readers. So self-support, admitted
  versions, conditioning and dominance hold forward as they do for queries. A
  fold premise is a fold key. A fold that no search expanded, other than a
  base rate whose estimate the cache holds, is searched as a query would
  search it.
- The agenda holds keys by how far their value moved from the value a run
  last built on: the KL divergence of the two, each read as a Beta
  distribution over the strength (Beta(1, 1) for no value).
- The budget counts row computations, at any depth, a seed's readers
  included ([forward_units.md](forward_units.md)). A row it cannot pay for is
  left stale, and its key goes back on the agenda as a rest item, which
  computes the stale readers without starting joins again. So a step costs
  the same however many readers a key has.
- The agenda outlives the run: a run carries the best items it leaves (at most
  `bounded-agenda-target-size`) to the next run on its knowledge base, which
  continues from them. A run works the facts callers chose first (its own
  and those earlier runs queued; a run without budget only queues them), for
  a share of its budget (`set-forward-seed-share`, default 1), so carried
  derived keys never starve them, then everything by priority. Seeds are
  carried whatever the bound.
- Keys are taken in waves, in agenda order, while the rows they bring (new
  rows of their joins and stale readers) fit the budget left. One evaluation
  serves a wave, so a row several of its keys reach is computed once; the
  keys it changed join the agenda. A derived key
  whose value rests on less than a minimum of evidence (one observation, n =
  c·k/(1−c), by default; `set-forward-min-evidence`) is not built on,
  however much budget is left.
- Taking a key also updates the base-rate aggregates over it with its value.
- Upward joins apply no rule to a certain statement, as expansion does not.

A run stores the value of each derived key it built on in `&kb`, so a later
query reads it as a fact without searching for it: forward chaining exists to
make later queries cheap.
- The stored fact is a copy of the key's value, kept apart from the key's
  user facts. It replaces the copy an earlier run stored.
- It carries the value's evidence and what the value was derived through
  (`&sk_forward_stored`). A reader that must not depend on one of those keys,
  or a read conditioned on one, leaves it out.
- It stands for the value only while the key has no computed versions. Once
  it has, the live value wins and the copy never competes with it.

`forward-chain` returns the values it stored, with each proof printed as a DAG
(`proof_dag_expand`).

A query's answers keep their proofs as the values hold them, references into
`&proof`, until the query prints them. `query-many-refs` never prints them:
callers that read only the truth value or the statement get answers whose size
does not grow with the derivation behind them, as terms through janus rather
than text (SupplyNet scale l at 16 steps per query: query time 151 s to 122 s,
peak RSS 3.5 GB to 1.5 GB, 140 MB of answer text no longer built).

Output proofs print a shared subproof once: a stored subproof referenced more
than once that itself refers to stored proofs appears in full at its first
occurrence as `(shared N proof)` and as `(shared N)` after that. Expanding the
DAG as a tree grows exponentially when values build on merged values, as
beliefs carried from shift to shift do.

Full saturation is not a separate operation. It is the special case in which
the caller selects every KB fact and supplies enough budget. Adding a
rule does not automatically replay old facts; the inference controller decides
which existing facts should activate it.

### Derived state exists only for correctness or measured performance

`&kb` contains the facts exposed to reasoning. Side tables may retain
evidence identities, indexes, accumulator state, or
pending work when they avoid repeated computation. They are implementation
indexes, not a second logical KB.

Do not materialize all possible derivations or retain every intermediate object
by default. Prefer the smallest state that allows a result to be recovered
correctly and lazily.

### Search must remain deterministic where order matters

MeTTa definitions can produce multiple reductions. Indexed matches, agenda
priority, proof dominance, and merge order must not acquire accidental
nondeterminism from overlapping clauses or unstable iteration order.

Syntactic dispatch must inspect an expression's actual head before matching its
arguments. A variable predicate in a query, rule premise/conclusion, open key,
or recursively encoded expression must remain a variable: testing whether it
is `Implication`, `Inheritance`, `RuleTruth`, `CPU` or another reserved form
must not bind it to that symbol. Unification remains the operation for matching
knowledge against a query; it is not a syntax classifier. The ingestion rule
for free variables does not make internal open keys or rule patterns ground.

## Correctness requirements

- Reject cyclic self-support before it reaches proof merging or aggregation.
- Preserve complete proof structure in examples that are intended to test proof
  identity, not just their final truth values. Base rates are the exception:
  they are proved by `cpu`, so their tests check the truth value, which counts
  the members.
- Never revise a proof with itself through a materialized forward/backward view.
- Truth-value confidence is not assumed to be monotonic. A proof that contains
  more evidence can produce a lower-confidence conclusion through the rule
  formulas, even though the earlier proof remains valid. Cache-refinement and
  proof-dominance policies must therefore be tested separately from proof
  monotonicity. An old computed base-rate snapshot remains usable while
  refinement is pending.
- Optimization side tables must be removable in principle without changing
  logical answers, apart from search order and finite-budget approximations.

## Known performance work

- Root answer subsumption builds a query-local index by identical ground proof,
  preserving answer order and copying each survivor independently. Proof
  identity follows the DAG through references, ignoring their allocated IDs;
  its hashes are memoized per reference within the query, and hash collisions
  are checked without binding variables. Opaque `cpu` computations retain
  reference identity because their printed proof omits their arguments or
  population. A singleton needs no comparison.
  Indexing costs O(n log n) plus the distinct proof DAG nodes read; comparisons
  remain quadratic within a proof group when none subsumes another. Distinct
  proofs are never compared. Nonground proofs cannot be identical after the
  independent copies used for subsumption and pass through unchanged.
- A warm query walks only the paths to pending work, but it still rebuilds
  the set of keys it needs from its roots. The set is relative to the
  query's roots, which differ from query to query (each decision of ONA's
  matching-to-sample agent asks about its own trial), and its depths decide
  what the evaluation computes from the reserve, so keeping it across
  queries would compute rows no query needs; the rebuild is bounded by the
  keys within two steps of the roots and the rows never computed below
  them. The fixed cost of a call outside inference is about 0.2 ms
  (`PeTTaChainer.timing()` reports the split).
- Per-cause forcing can accumulate many temporary records. Evaluation resets
  bulk-remove these data rows; consuming a row's pending causes preserves their
  order and retains its used causes until the next evaluation. Stale propagation
  and creating the cause records still cost work; see the
  [cleanup measurements](skeleton_bookkeeping_2026-09-25.md).
- The support test unions dependencies over a row's retained views, so its cost
  grows with that history. Older views serve compatibility-filtered consumers
  and cannot simply be dropped.
- A new open answer key invalidates cached unifier sets broadly.

The acceptance test for each change is not merely a faster benchmark. It must
preserve monotonic proof semantics, evidence deduplication, strict step budgets,
caller-selected late-rule activation, and the complete test/example suite.
