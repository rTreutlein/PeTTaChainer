# Forward Chaining as a Mode of the Skeleton

Design note, 2026-09-30. Status: implemented (`runtime/backward/upward.metta`,
the base-rate fold view in `runtime/backward/evaluation.metta`); the forward
engine and canonical store are gone.

## Why

The forward chainer is a second reasoning engine beside the skeleton. It
shares `&kb`, evidence identities and the formulas, but keeps its own:
- matching: the forward premise index, with joins read straight from `&kb`;
- a per-derivation frontier (`&forward_frontier`) and one canonical merged fact
  per output in `&kb`;
- a dependency table (`&forward_output_deps`, added today);
- aggregate subscriptions that estimate base rates.

Everything the skeleton learned has to be rebuilt there, and every piece so far
has come out weaker:

| Concern | Skeleton | Forward chainer |
|---|---|---|
| Self-support | Key dependencies, transitive | Per-output dependencies (today) |
| Reader-specific values | Each reader takes the admitted versions that do not depend on it | One merged value per output; a weak inversion blocks rules leading back to its source |
| Shared premise evidence | Conditioning | Refusal |
| Inverted rules | Run | Excluded |
| Fold premises | Fold keys, incremental base rates | Cache, stored skeleton view, or a nested backward query |

The two also meet badly:
- A forward-derived fact reaches the skeleton as a leaf. It carries its
  evidence but only its own key as a dependency. Dominance then cannot tell it
  from the backward proof of the same statement, which let a double-counted
  forward value win backward queries.
- The same missing dependencies forced the rule that a stored fact is left
  out under a condition.

The alternative to building a second skeleton inside the forward chainer is to
let forward chaining build rows in the one skeleton.

## Current mechanics (what the design has to fit)

Skeleton construction is goal-driven (`runtime/backward/skeleton.metta`):
- A node is an expanded goal pattern. `sk-expand!` records its leaf answers
  and, for each rule whose conclusion matches (`ccls_index`), starts a partial
  join owned by the node.
- A partial join waits on its next premise node (`sk-wait-on!`). A ground
  premise reads its stored facts at once; an open premise waits for its node's
  expansion. Every answer of that node extends the join once.
- A complete join is a row (`sk-complete-row!`): rule, premise keys,
  conclusion key. It is added to `&sk_new` and registered as a reader of its
  premise keys.
- Evaluation (`sk-evaluate!`) computes views of new rows and of the readers of
  changed keys, in creation order. It computes only what the query's roots need
  (`sk-need!`) and marks the rest stale. Rows beyond two steps from a root are
  paid from an allowance.
- Facts added between queries are journaled (`sk-note-fact!`) and activated at
  the next query against the expanded nodes they unify with.

Forward chaining is data-driven (`runtime/forward/engine.metta`):
- A fact triggers the rules with a premise matching it (`prem_index`).
- The other premises are matched against `&kb`.
- Results go onto a confidence-ordered agenda with the remaining seeds. A step
  stores the most confident result in the frontier and in `&kb`, and expands
  it. Results under the minimum evidence start no output.

## Design

A forward run grows the skeleton upward from its seeds and evaluates what it
grew. Its outputs are skeleton keys and views, not a separate store.

### 1. Upward joins

A trigger key `K` (a seed's statement, or a key whose view a forward step just
changed) looks up the rules with a premise unifying with `K`, through the
existing forward premise index. For each one it starts a partial join with
that premise bound to `K`.

The other premises differ from goal-driven joins. They are read from what
already exists, and nothing is expanded:
- stored facts, as `sk-wait-on!` already reads them for ground premises;
- keys already answered anywhere in the skeleton, found through the structural
  key index (`&sk_key_terms`).

This keeps forward chaining's meaning ("combine what is known") and never
starts backward search. When the join completes, it becomes an ordinary row
through `sk-complete-row!`. Its owner is the conclusion pattern, recorded as a
*forward owner*: a node that is **not** marked expanded. A later query on that
pattern must still start every rule that concludes it, not only the one the
forward run started. The row is registered as a reader of its premise keys like
any other row, so later changes reach it by the ordinary change path.

### 2. Evaluation of a forward run

A forward run is an evaluation whose roots are the keys it triggered, with the
existing machinery:
- The new rows go through `&sk_new`. Their keys are needed at depth 0 for the
  run, so they are computed rather than marked stale.
- Views get dependencies, admitted versions, dominance, lifting, conditioning
  and the self-support exclusion unchanged.
- Base-rate and other fold premises are fold keys, read as queries read them:
  the cached estimate, or the fold's view.

### 3. One base-rate estimate, updated from both sides

Keeping base rates current cheaply, as facts arrive and before any query has
folded them, is the forward chainer's main job. The skeleton does not do it:
its incremental folds take a changed member only when a query needs the fold.
Before this step the two kept separate per-member tallies of the same base rate:
- the forward aggregates (`&forward_aggregate_observation`, per fact);
- the skeleton's rate folds (`&sk_rate_part`, per member key).

The cache entry held whichever one last "won". A computed fold replaced a
`forward-approx` entry when it was at least as confident.

Instead there is one estimate per base-rate pattern, made of per-member
contributions, and every side only updates it:
- The forward run updates the contribution of each key a step takes, at the
  point where a stored forward fact updates the aggregates today.
- A backward fold adds the members its search found. A member already counted
  has its contribution replaced, never added twice.
- The cache entry is that estimate's current value. Its source (user,
  computed, forward) no longer decides precedence, except that a user base
  rate stays authoritative.

A query then searches for more members only when the estimate is not good
enough. That is already how the skeleton scores a fold's member search: by what
one more member could add to the estimate's confidence. With forward outputs as
skeleton keys, both sides name members by the same key, which is what lets the
two tallies become one.

Implemented as: the forward aggregate is the one tally. A base-rate fold view
takes its dirty members into it (`fa-update!` with each member key's value)
and reads its value; the skeleton's own rate stores and the `forward-approx`
source are gone. A cache entry the tally did not produce gives way to it
however confident it was.

### 4. Priority, budget and the stopping rule

The run keeps today's semantics at the level of keys, ranked by how much a
key's value changed rather than by its confidence:
- An agenda holds seeds and keys whose view changed, each by the size of its
  change. That is the KL divergence of the new value from the old one, each
  read as a Beta distribution over the strength: with n = c·k/(1−c)
  observations, Beta(s·n + 1, (1−s)·n + 1).
  - A key with no value before is Beta(1, 1), the value that says nothing, so
    a new key and a seed are compared with ignorance.
  - The measure has no hand-chosen weights. A shift in strength counts more
    the more confident the new value is, and gaining confidence without moving
    counts too.
  - It needs log-gamma and digamma. PeTTa has no digamma, so an asymptotic
    series is used. So a large revision of a known key outranks a
  confident key that barely moved, and a key whose value did not change is not
  taken at all.
- A step takes the key that changed most and runs upward joins from it (1). It
  then evaluates the rows those created (2) and puts their keys on the agenda.
- The budget counts keys taken. A seed is taken lazily when it is the top
  item and costs nothing, as now.
- A key whose merged value rests on less than the minimum evidence
  (`set-forward-min-evidence`) is not taken. Its row still has a view, which
  is cheap and useful to a later query, but nothing is built on top of it.

Weak inversions then cost one row each and propagate nowhere. That was the
original motivation for priority.

### 5. Results stay in the skeleton (superseded: see below)

A plain backward query writes nothing to `&kb`: its answers are views, and only
a materializing query (`chainer-materialize`) writes back. Forward results
follow the same rule. `forward-chain` returns the merged values of the keys the
run changed, keeping its signature in `docs/metta/API.md`. A caller who wants
forward results in `&kb` materializes them, as with a query.

`forward-has-derived?` goes: nothing but `test_forward_chainer.metta` calls it,
as a shortcut for "is this statement in `&kb`". Those tests read what
`forward-chain` returns instead. It is a public API entry, so removing it
was approved.

### 6. What is retired

- `runtime/forward/engine.metta`'s join and agenda, replaced by sections 1, 2 and 4.
- `runtime/forward/canonical.metta`'s frontier, canonical evidence rows,
  candidate comparison (`forward-frontier-compare`, `forward-candidate-refines?`)
  and `&forward_output_deps`. A materializing query needs a plain writer for
  `&kb` in their place.

Implemented as: `compileadd` stores each fact in `&kb` as it is, and readers
that need one value per statement (member-inheritance joins, base-rate seeding,
removal) merge its stored facts (`stored-statement-candidate`). The skeleton
already read them as separate leaves. Materialization adds a marked fact and
removes the statement's earlier marked ones. `remove-compiled-statement`
removes the named facts from `&kb` and re-observes what remains of their
statements. Two equally confident facts of one statement now merge in the
skeleton's order rather than insertion order.
- The special cases forward results forced into the backward chainer: the
  leaf exclusion under a condition and `forward-fold-value`.

## Consequences and risks

- **Costlier steps.** A skeleton row carries views, versions, readers and
  dependency sets. A forward join today is a `&kb` match and a merge. StationOps
  runs a forward chain every shift at budget 2, so this has to be measured, not
  assumed.
- **One evaluation per run.** `sk-evaluate!` resets per-evaluation state and
  walks the needed set, so a run must not start several evaluations.
- **Owner semantics.** Forward owners are the one new concept in the skeleton,
  and the rule that they are never marked expanded must hold everywhere
  expansion is checked (`sk-expanded?`, activation, the search walk).
- **Premise lookup by unification.** Reading keys through `&sk_key_terms` for
  an open premise is a structural match. It must stay indexed (statement first)
  so a trigger does not scan every key.
- **Tests.** Forward tests that inspect `&forward_frontier` or its merge order
  test the retired representation. They would be rewritten against keys and
  views, not kept as scaffolding.

## Open questions

None at present. Decided on 2026-09-30:
- priority by change, measured as the Beta divergence;
- `forward-has-derived?` is removed;
- one base-rate estimate updated from both sides.

## What the implementation added

**Stored results (decided after the first StationOps run).** Keeping results
only in the skeleton halved the StationOps score (26,940). The action KB is
queried with a budget of 1, relying on forward chaining to have derived what it
reads, and a query reaches skeleton values only through expansions it cannot
pay for. So a run now stores each derived key's value in `&kb` as a copy, with
the value's evidence and dependencies. The copy stands for the value only
while the key has no computed versions, so it never competes with the live
value. An earlier attempt went through the canonical store, which merged
the copy into the key's user facts; the copy's dependencies then made readers
drop the user facts too.

**Proof output.** StationOps crashed at shift 6 until output proofs printed
shared subproofs once. Expanding the proof DAG as a tree doubled every shift.

Four details the design did not anticipate:
- **Last-taken values.** A key is compared with the value a run last built on,
  not with its value before this evaluation. Otherwise a key evaluated but
  not taken, because the budget ran out, never looks changed again, and its
  work is lost.
- **Stale readers.** A row that goes stale leaves the reader lists of the keys
  it reads, which keeps backward change propagation cheap. A forward run needs
  exactly those rows, so a stale row is kept as a *stale reader*
  (`&sk_stale_reader`) until it is refreshed.
- **Fold search.** A fold premise that no search expanded has no members. The
  run searches it, as a query would, unless it is a base rate, whose estimate
  the cache holds.
- **Certain statements.** Expansion applies no rule to a certain statement.
  Upward joins skip one where their conclusion is first bound, in
  `sk-complete-row!`, during forward runs only.

Baseline before this work (4 seeds × 20 shifts, budget 600, per seed):
- about 72 s wall;
- `forward_chain` about 24 s over 80 calls (0.3 s per call);
- `query_many` about 30 s over 20 calls;
- station score 52,236.

## Plan

1. Measure: StationOps forward cost per shift and the forward tests' runtime,
   as the baseline.
2. Upward joins and forward owners, with premises read from facts and keys;
   one test per premise source.
3. A forward run as an evaluation over its triggered keys, with the
   key-level agenda, budget and minimum evidence.
4. `forward-chain` answered from views; `forward-has-derived?` removed.
5. One base-rate estimate per pattern: merge the forward observations and the
   skeleton's rate parts into per-member contributions keyed by member key,
   updated by forward steps and backward folds alike.
6. Put inverted rules back; check the S/Q and P/Q cases from
   `test_forward_incremental_base_rates` behave as the backward chainer does.
7. Retire the forward engine, canonical store and dependency table. Rewrite
   the forward tests against keys.
8. Full suites, then StationOps against the baseline from step 1.

## Measured after step 7

StationOps, 4 seeds × 20 shifts, budget 600:

| | score | Brier | wall (4 seeds) | `forward_chain` per seed |
|---|---|---|---|---|
| before this work | 52,236 | 0.0908 | 289 s | ~24 s |
| forward over the skeleton (e713c29a) | 52,310 | 0.0733 | 582 s | ~85 s |
| one base-rate estimate (step 5) | 52,300 | 0.0722 | 576 s | ~88 s |
| canonical store retired (step 7) | 52,300 | 0.0722 | 556 s | ~85 s |

Per-phase timers over seed 7 (CPU, outermost calls only, inside
`forward-chain`): 82 s in all. Upward starts take 24.6 s, evaluations 24.5 s
(row views 11.8 s) and `sk-need!` 14.4 s. Almost every take is a seed: about
110 per call.

The cost is not spread evenly. Of the four forward calls per shift, three stay
near 0.5–0.8 s. The first grows linearly with the number of shifts, from
0.35 s to about 7.5 s by shift 20, on a constant ~28 seeds. Between shift 2 and
shift 12 that call's:
- `sk-need!` rose from 1.7 ms to 12 ms per call;
- `sk-mark-stale!` calls rose from 218 to 2,497;
- row-view cost rose from 0.2 ms to 0.58 ms.

Beliefs carried from shift to shift form a chain. Needing a reader walks its
premise ancestry, a change marks the chain's readers stale, and dependency and
evidence sets grow along it. This is the next scalability problem: a step
should cost the same at shift 20 as at shift 2.
