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
- Overlapping proofs are not independent evidence. Disjoint proofs may be
  revised together; overlapping paths need dominance, refinement, or cycle
  checks before aggregation.

Removal is outside this logical model. The deprecated compatibility operation
may remove current KB and index rows, but it does not delete durable proofs or
make proof IDs reusable.

### Strict append-only follow-up

The public `remove-compiled-statement`, cache `clear-*`, and replace-style
configuration operations predate the decision that ordinary system history
should be append-only. Statement removal remains callable only for compatibility
and is deprecated; normal reasoning and knowledge ingestion must not depend on
it. In particular, removal does not erase stored proofs or skeleton rows, or
reset the monotonic proof ID counter.

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
query's hypothetical contexts see none of the main context's facts, but its
logic holds there: S → (A ∧ B ∧ C) answers S → (A ∧ B).

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
key, and each reader applies its own proof and truth-value pattern.

For the backward chainer, ingestion only journals added facts and rules. The
next query activates them against the skeleton before its walk: a rule reaches
the patterns already expanded, and a fact is read by every node that reads its
key (expanded nodes and the ground premises joins wait on, expanded or not)
and, through the rule it is a premise of, by each unexpanded node the skeleton
holds for that rule's conclusion, where that rule alone is started
([fact_absorption.md](fact_absorption.md)). So evidence that arrives after a
search reaches the keys it built, without the search returning to them.

Rules compiled for one query (query adapters, implication scaffolds) leave with
it: their rows, waiters and views are removed and the keys they fed change.
Producers that depend only on the pattern (the Member inheritance producer of a
concrete `Inheritance` link, the compiled source of a fold pattern) are
installed once as permanent backward rules, so their rows outlive the query.

### Truth values are views, recomputed from what changed

Evaluation computes each row's **view**: its conclusion from the premises'
values by the rule's formulas, with the evidence behind it and the hashes of
the keys it depends on, transitively. A view's proof is one rule application
whose premise proofs are references into `&proof`; the full proof tree is built
only for output. Stored proofs refer only to earlier ids, so they form a DAG. A
row keeps its latest view and the views it replaced, and later queries read
them until something below them changes.

A certain truth value, confidence 1, stands for unlimited evidence: revision
leaves it unchanged, and a ground key stored with one applies no rules,
since no other proof could change its value. For the same reason such a key's
value is its certain stored facts alone: views its rows got before the fact
was stored add neither evidence nor dependencies. Only stored facts end the
merge this way; a derived view of confidence 1 is a probability known
exactly, not the statement's truth, and merges as below.

A rule stated with confidence 1 in every branch is given, not estimated: its
applications carry no evidence of it, so proofs that both use it share no
evidence through it. A rule stated with less, or refined from its instances,
is evidence of every proof through it.

A key's value merges its stored facts and one view per row:

- an identical proof pools its evidence; a marginal projection gives way to its
  full proof;
- two views are independent when their evidence is disjoint, or when each
  holds evidence of its own and they share only known facts that no rule
  concludes (premises either reads as given), no statement whose value is
  uncertain (by their dependency sets, so a derived statement both read
  counts, not only shared leaves) and no rule whose truth is an estimate;
- inversions and antecedent completions over one prior through different
  observations, and rules that differ or are given, combine by Bayes' rule, and an inversion over a base rate combines the same
  way with a derived, uncertain view independent of it, which
  takes the base rate's place (`docs/metta/prior_factored_merge.md`);
- independent views otherwise revise, except that forward views (rule
  applications) of a predicate whose stored outcomes prefer odds or noisy-OR
  by a Bayes factor of 10 combine by that mode
  (`docs/metta/combination_modes.md`);
- of dependent views, the one whose evidence strictly contains the other's
  is kept; two that share an uncertain statement condition the key's whole
  merge on it: the merge with the statement known true and known false,
  mixed by its value (`docs/metta/overlap_conditioning.md`); otherwise, or
  while the conditioning waits to be paid, the more confident view is kept;
- when every proof of the key is modus ponens over conjunctions of facts, the
  proofs share fact premises, and their residual evidence is nonempty and
  pairwise disjoint, the lifting merge factors the shared facts out, revises
  the residual implications, and applies the shared conjunction once. It
  requires a strength linear in the shared conjunction (a two-point round
  trip); otherwise views merge pairwise. Lifting applies to a key's merged
  value; compatible selection below merges pairwise.

No value supports itself. A consumer reads, per row of a premise key, the
latest view that depends neither on its own key nor on any key unifying with
it; older views stay available to exactly the consumers a newer one came to
depend on. Because dependency sets are transitive, this rejects self-support
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
answered, nothing deferred), so a budget cut never concludes false.

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
P(A) = P(ABC) / P(BC) with P(BC) read off ABC would be 1.

A clash that survives the fresh read is resolved by conditioning, not refused.
The row is evaluated with the statement of a shared fact known true and again
known false, and the two results mix by modus ponens over that statement's
value, so the shared evidence counts once. Under a condition:
- a known statement reads as certain, with no evidence;
- a view depending on one is its row evaluated again under the same
  condition, excluding what the enclosing rows exclude, so the recursion
  follows only views that used a shared fact and cannot cycle;
- other views, and folds, read as stored.

A branch that still clashes over another shared statement conditions on it in
turn. There is nothing to condition when a premise reads one of the shared
statements itself (P(K and K) is P(K)), when the clashing value is a
projection, or when the conclusion is not a simple truth value; such premises
are refused as before. The mix needs the weight's evidence to be outside the
branches.

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

A fold's or group's view is computed from its member keys when first read and
recomputed when a member changes; the members changed in one pass recompute it
once. Members are read without views that depend on the fold itself. Base-rate folds estimate a population: they carry neither member evidence nor member
dependencies, like a prior, and are proved by `cpu`. An implication instance
fold carries no member evidence either, so its estimate revises with a rule's
stated truth, but it keeps its members' dependencies. A `FoldAllTruth` fold
reads its members' truth values as data and is treated the same way, so a rule
can fold a group's beliefs and read one member of the group again.

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
change, be needed and be recomputed every time the rate moved. Needing the fold
needs only those members, not the population. A member whose inputs changed
while no query needed it keeps its last contribution until a query recomputes
it, so a base rate may lag the members' current values; every step costs the
members that changed. Inheritance-weighted members count at unit mass and the
evidence is scaled by the current subject mass when the fold finishes, so a
growing universe does not leave contributions stale.

A conjunction whose conjuncts fall into parts sharing no variables ranges
over the cross product of the parts' instances, so its base rate is exactly
the product of the parts' rates: each part is folded on its own and the rates
are combined, instead of folding over every combination. Ground conjuncts
stay with a part, since a single instance multiplies nothing.

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
under a prior of a pseudo-observations (`set-bayes-prior-count`) centred on
independence: the pooled P(B) of both branches, or P(B) for P(B|A). Without
it, a false-alarm rate estimated as 0 from a handful of cases makes every alarm
certain. A base rate read as the prior of an inversion or a completion is the
prior of one more member, read the same way, centred on 0.5: a rate of 0 or
1 from finitely many members leaves an instance either way possible, so its
updates keep their likelihood ratios. A predicate whose stored instances are
only its true ones is declared positive-only (`set-positive-only-predicate`)
and has no prior. A certain likelihood, a certain rate, and the instance
prior are read as they are.

### Queries read what their roots reach

A query walks the skeleton best-first from its roots. Expanding a new node costs
one step of the budget; walking through an expanded node spends a separate walk
allowance of one per step, so revisiting what is already built never takes a
step from new expansions, and once the allowance is spent expanded nodes are
passed over while the walk goes on. A node's priority is
the best value any join waiting on it gives it: the owner's value times the
rule's expected confidence, shared among the premises still open. Equal scores
go first to the work of roots already started, shallowest first, and then to
the roots not started yet, in insertion order: the budget completes the
answers it started before it starts new ones. Once the budget is spent, nodes
it cannot pay for are passed over and the walk goes on, so expansions that
cost no step (below) still complete the joins the paid ones started; the paid
expansions of a larger budget extend the same prefix. A multi-root query
shares one budget and one order.

Stored facts cost no expansion: a join waiting on a ground fact premise reads
its facts at once, and whenever more are stored, and a root reads its own
stored facts. An open premise waits for its expansion, which bounds recursion.
A node no rule can conclude (other than an implication or inheritance link,
whose expansion installs rules) is expanded without a step when the walk
reaches it: its expansion only reads its stored facts. It keeps its place in the walk, so its facts extend joins
when its priority says so (reading them at once filled the row budget early:
StationOps Brier 0.0652 against 0.0607 at the smallest budgets). Before any state is created, a rule
whose ground fact premise has no fact and no concluding rule is pruned. New
rows have an allowance of ten per step, except the rows of the query's own
roots; rows beyond it wait with their node
and are completed when a later walk reaches that node, so leftover work never
spends an unrelated query's budget. Facts stored since the last query are the
exception: they are delivered first, before the next query's walk, from an
allowance of their own (ten rows per new fact and per step), as the deferred
cost of ingesting them.

Evaluation then brings current only what the roots read: their keys, the
premise keys of those keys' rows, and the members of folds and groups among
them (for a base-rate fold, the members it has yet to take). Any other row whose input changed is marked stale, once, together with
everything reading it; a later query that reaches it recomputes it. A stale row
leaves the reader lists of the keys it reads until then, so a change walks only
readers that are current. Rows built for earlier queries therefore cost nothing
per query or per change.

Evaluation is bounded too. A needed key records its depth, the fewest rows or
folds between it and a root. Rows of keys within two such steps are always
computed; deeper rows spend an allowance of two recomputations per step, and
what it cannot pay for is left stale, to be recomputed by a later query that
reads it. Within a pass the rows within two steps come first, by creation, and
the deeper rows after them, nearest a root first and by creation within a
depth. The allowance thus goes to the rows nearest a root, whatever order the
search created them in: when a query builds many rows, the ones it created
first are often far below its roots, and spending the allowance on them left
the rows the roots read stale (SupplyNet stage 3, mean posterior error over
seeds 1–4 and budgets 25–200: 0.00348 by creation, 0.00323 by depth). The
order does not depend on the allowance, so an allowance that covers everything
computes what an unbounded evaluation would.

A stale row is brought current only when a need reaches it within those two
steps, as a query asking for it does. A deeper stale row keeps its value and
stays out of the change path, so what no one asks for is never recomputed: a
base rate that every past belief read moves on each new observation, and
refreshing the stale history behind a current belief would cost as much as the
history. Beyond the two steps, need passes only through rows never computed or
waiting to be conditioned. A current row's inputs are current, because every
change reaches the readers of what changed, so nothing under it needs
recomputing.

A change during a query's own evaluation can stale a row the query needs after
the walk passed it, such as a reader of a fold that a new member moved. The
query brings each such row current and computes it in a further pass, once per
evaluation, so it reads no value from before what it needs. A forward run
leaves those rows stale for the query that next needs them: refreshing them
there would recompute every needed reader of each fold the new facts move,
which grows with the knowledge base (StationOps at 20 modules: forward time
+106–243%; leaving them to queries: +1–10%).

Conditioning is paid for from what that allowance has left, never at depth
zero for free. A row whose clash needs it waits, keeping the views it had, with
a cost bound of 2^k times one more than the clashing value's dependency count
for k shared statements; a key whose views overlap waits the same way,
keeping its merge with the more confident view, with the overlapping views'
dependency count. Once the rows are computed and the roots' merged values
read, the waiting rows and keys the query needs are paid for nearest a root
first, then cheapest, then oldest. A row is recomputed conditioned, with its
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
inversion reads, and a positive-only predicate has none. The prior is the population's value, not
the statement's: no row reads it and it is never materialized.

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
arguments walks every fact with that head, across the whole history. Each
ground fact is therefore also stored in `&kb_prefix` under the hash of every
prefix of its statement (its head with its first one, two, ... arguments). A
lookup hashes the pattern's longest ground prefix and still unifies each
candidate; facts whose statements have variables sit in `&kb_open`, which every
such lookup reads too, so no unifying fact is missed. Readers that bind only a
statement's head read `&kb` directly. The skeleton's registered keys are
indexed the same way: `&sk_key_prefix` and `&sk_key_open` beside
`&sk_key_terms`. Rule premises are indexed the other way round: each in
`&prem_prefix` under the hash of its statement's longest ground prefix, so the
rules a ground key is a premise of are found by hashing the key's prefixes.

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
  preserving answer order and copying each survivor independently. Indexing
  costs O(n log n) for bounded-size proofs; comparisons
  remain quadratic within a proof group when none subsumes another. Distinct
  proofs are never compared. Nonground proofs cannot be identical after the
  independent copies used for subsumption and pass through unchanged.
- A warm query still walks its reachable skeleton and rebuilds the set of keys
  it needs; repeating a query is not constant time.
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
