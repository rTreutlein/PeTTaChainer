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
logically. The runtime may expose one canonical merged proof in `&kb` and keep
supporting candidates in indexed side tables, but refreshing that materialized
representative is evidence accumulation, not mutation of the proposition.

Consequences:

- Never describe an addition as "changing A". It adds another proof that may
  contribute to the canonical proof of `A`.
- A previously valid proof remains valid after any addition.
- Evidence identity must survive materialization so the same evidence is not
  counted twice when forward and backward paths meet.
- Overlapping proofs are not independent evidence. Disjoint proofs may be
  revised together; overlapping paths need dominance, refinement, or cycle
  checks before aggregation.

Removal is different. Removing a named statement can make proofs and estimates
invalid and therefore permits explicit cleanup and invalidation work.

### Strict append-only follow-up

The public `remove-compiled-statement`, cache `clear-*`, and replace-style
configuration operations predate the decision that ordinary system history
should be append-only. They remain explicit administrative escape hatches for
now; normal reasoning and knowledge ingestion must not depend on them.

A future API pass should represent corrections, supersession, and configuration
changes as scoped events instead of retracting prior knowledge. This is not a
local cleanup: named-statement removal currently owns proof-frontier, rule-index,
and derived-cache invalidation, so changing it requires an explicit temporal or
scope policy. Mutable query arenas and replaceable cache/index rows are not
logical retractions as long as deleting those optimization tables would leave
the unbounded logical answers unchanged.

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

There are three kinds of base-rate entry:

- `user`: an explicit estimate supplied by the user. It is authoritative until
  explicitly cleared or replaced.
- `computed`: a snapshot harvested from backward folding at a particular point
  in the monotonic proof history and within that query's step budget.
- `forward-approx`: a provisional snapshot accumulated from facts that the
  forward chainer has processed so far.

Adding a fact or rule does not invalidate a `computed` or `forward-approx`
snapshot. The snapshot still summarizes valid evidence; it may simply know less
than a later fold. A backward query may use it immediately and schedule a live
fold that refines it. Forward chaining may incrementally improve the sufficient
statistics when it processes additional canonical proofs.

Base-rate invalidation is reserved for non-monotonic or interpretive changes:

- removing facts, rules, or supporting proofs;
- changing or clearing universe size;
- changing or clearing runtime prior parameters;
- explicitly clearing or replacing a base rate.

The important tradeoff is intentional: a tightly budgeted query may initially
use an older estimate. Add-time work must not eagerly make every cached estimate
current.

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
bearing exact key would require `variant_hash`, but do not add it unless its
lookup benchmark pays for the hashing cost. Never hash indexes whose purpose is
structural or variable-bearing pattern matching.

### Reasoning work is lazy and budgeted

`compileadd` stores knowledge; it does not silently perform inference. The user
may run forward chaining after one or many additions. Queries and chainer calls
must respect their explicit step budgets.

Forward chaining always starts from facts selected by its caller. Its agenda is
local to that invocation and is discarded when the agenda empties or the step
budget is exhausted. The canonical facts derived before that point remain in
`&kb`, and the inference controller may select any of them as seeds for a later
run. No unfinished search state is retained by the chainer.

Full saturation is not a separate operation. It is the special case in which
the caller selects every canonical KB fact and supplies enough budget. Adding a
rule does not automatically replay old facts; the inference controller decides
which existing facts should activate it.

### Derived state exists only for correctness or measured performance

`&kb` contains the canonical merged proof exposed to reasoning. Side tables may
retain proof candidates, evidence identities, indexes, accumulator state, or
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
  identity, not just their final truth values.
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

At the time this document was written, base-rate invalidation on monotonic
addition and global forward-agenda invalidation were removed. The remaining
insertion paths still need separate measurement and review:

- canonical proof-frontier insertion and merging;
- rule indexes and late rule activation;
- any compiler-generated registration performed per added rule.

The acceptance test for each change is not merely a faster benchmark. It must
preserve monotonic proof semantics, evidence deduplication, strict step budgets,
caller-selected late-rule activation, and the complete test/example suite.
