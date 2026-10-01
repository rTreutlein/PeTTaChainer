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
next query activates them
against the patterns already expanded, so a fact added between queries reaches
the rows that use it through ordinary leaf answers.

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
since no other proof could change its value.

A key's value merges its stored facts and one view per row:

- an identical proof pools its evidence; a marginal projection gives way to its
  full proof;
- overlapping evidence keeps the view whose evidence strictly contains the
  other's, or else the more confident one;
- disjoint evidence revises;
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
A compound And or Or antecedent is lowered into its parts, so what a rule
concludes from it depends on the parts' keys and never on the compound's; a
row inverting such a rule into the compound therefore also excludes views that
depend on any of its parts.

Premises are selected by the consumer. Evidence of a certain fact, strength 0
or 1 at confidence 1, never counts as shared: a join over it is exact either
way. A premise whose value shares other fact evidence with what the row already used is replaced by the merge of that key's
facts and views that share none; a shared rule is not a clash, except a rule
the row excludes: an implication instance sample excludes the rules restating
its implication, so it reads the consequent's other proofs. Premises are taken greedily in order; when every
value of a premise clashes, the row reads again on a fresh copy, taking
compatible stored facts first. Projections of one stored `(And ...)` source pool
back into that source instead of multiplying shared evidence, and
compiler-marked joins may share source evidence deliberately.

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

Conditioning lets a rule that builds conjunctions from its own conclusions
derive terms such as `(And X (And X Y))`, which evidence disjointness used to
rule out. A conclusion whose conjunction repeats a conjunct, with nested
conjunctions flattened, says what a shorter term says and makes no row
(`redundant-conjunction?` in `sk-complete-row!`), so such rules derive
finitely many terms.

Evaluation starts from what changed: new rows, and the readers of keys changed
outside evaluation (added facts, removed query-local rows, fold members). Rows
are computed in creation order. A recomputed view is kept only when it brings
support, a dependency the row never had; the keys a row can depend on are
finite, so evaluation ends even though inverted rules make real skeletons
cyclic. A change from outside the rows forces each reader once per evaluation
and per causing key, and a forced reader whose value changes passes the change
on to its own readers the same way, so a refined fold reaches the roots.

### Folds and base rates

A fold's or group's view is computed from its member keys when first read and
recomputed when a member changes; the members changed in one pass recompute it
once. Members are read without views that depend on the fold itself, except
by a base-rate fold (below). Base-rate folds estimate a population: they carry neither member evidence nor member
dependencies, like a prior, and are proved by `cpu`. An implication instance
fold carries no member evidence either, so its estimate revises with a rule's
stated truth, but it keeps its members' dependencies. A `FoldAllTruth` fold
reads its members' truth values as data and is treated the same way, so a rule
can fold a group's beliefs and read one member of the group again.

A base-rate fold is incremental, since its population grows with everything
ingested. It keeps its accumulated evidence and each member's contribution; a
member that joined or whose value changed is taken again, replacing its old
contribution, when a query needs the fold or it is next read. Needing the fold
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
certain. A certain likelihood, and the instance prior, are read as they are.

### Queries read what their roots reach

A query walks the skeleton best-first from its roots. Expanding a new node costs
one step of the budget; walking through an expanded node spends a separate walk
allowance of one per step, so revisiting what is already built never takes a
step from new expansions, and once the allowance is spent expanded nodes are
passed over while the walk goes on. A node's priority is
the best value any join waiting on it gives it: the owner's value times the
rule's expected confidence, shared among the premises still open. Equal scores
go shallowest first, then in insertion order, and the walk stops at the first
node the budget cannot pay for, so a larger budget extends the same search
prefix. A multi-root query shares one budget and one order.

Stored facts cost no expansion: a join waiting on a ground fact premise reads
its facts at once, and a root reads its own stored facts. An open premise waits
for its expansion, which bounds recursion. Before any state is created, a rule
whose ground fact premise has no fact and no concluding rule is pruned. New
rows have an allowance of ten per step, except the rows of the query's own
roots; rows beyond it wait with their node
and are completed when a later walk reaches that node, so leftover work never
spends an unrelated query's budget.

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
reads it. Rows are computed in creation order either way, so an allowance that
covers everything computes what an unbounded evaluation would.

A stale row is brought current only when a need reaches it within those two
steps, as a query asking for it does. A deeper stale row keeps its value and
stays out of the change path, so what no one asks for is never recomputed: a
base rate that every past belief read moves on each new observation, and
refreshing the stale history behind a current belief would cost as much as the
history. Beyond the two steps, need passes only through rows never computed or
waiting to be conditioned. A current row's inputs are current, because every
change reaches the readers of what changed, so nothing under it needs
recomputing.

Conditioning is paid for from what that allowance has left, never at depth
zero for free. A row whose clash needs it waits, keeping the views it had, with
a cost bound of 2^k times one more than the clashing value's dependency count
for k shared statements. Once the rows are computed, the waiting rows the query
needs are paid for nearest a root first, then cheapest, then oldest. Each is
recomputed conditioned, with its readers, which may add waiting rows. The first
row the allowance cannot pay for stops the payment, so a larger allowance
extends the same prefix, and the rest wait for a later query that needs them.

A root reads the answers of every node of its statement and context, whatever
their proof and truth-value patterns, and drops answers that instantiate
another answer with the same proof. When the search has no value for a key, a
materialized answer an earlier query left is returned as the incumbent; it is
never revised with the current value, since it is not independent evidence.

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

### Reasoning work is lazy and budgeted

`compileadd` stores knowledge; it does not silently perform inference. The user
may run forward chaining after one or many additions. Queries and chainer calls
must respect their explicit step budgets.

Rule priority is a value-of-computation estimate, not a claim that a proof will
succeed. Base-rate strength describes statement probability, not the
probability of finding a proof: a low-strength proof is still a useful answer,
so rule priority does not use base rates. Searching a base-rate fold's members
is valued by what one more member could add to the estimate's confidence.

Forward chaining always starts from facts selected by its caller, and grows
the backward skeleton upward from them (`runtime/backward/upward.metta`,
[forward_skeleton_unification.md](forward_skeleton_unification.md)).
- Taking a key starts, for every rule premise the key matches, a join with
  that premise bound. The join's other premises read the stored facts and the
  keys the skeleton already has, never expanding anything. A complete join is
  an ordinary row. Its owner is the rule's conclusion, and no node is marked
  expanded, so a later query still starts every rule on that pattern.
- The rows reading the taken key, including rows that went stale, are then
  needed and evaluated by the ordinary evaluation. So self-support, admitted
  versions, conditioning and dominance hold forward as they do for queries. A
  fold premise is a fold key. A fold that no search expanded, other than a
  base rate whose estimate the cache holds, is searched as a query would
  search it.
- The agenda holds keys by how far their value moved from the value a run
  last built on: the KL divergence of the two, each read as a Beta
  distribution over the strength (Beta(1, 1) for no value). Work a budget cut
  off is therefore found again by a later run that reaches the key.
- Seeds cost nothing; each derived key taken costs one step. A derived key
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
(`proof_dag_expand`). The agenda is local to that invocation and discarded
when it empties or the budget is exhausted.

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
