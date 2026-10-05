# Shared joins

Status: parked, October 2026. Built on branch shared-joins (44700af0); with dormant rules it adds 1–4 s per seed for no quality gain. Results are in that branch's copy of this document.

## Problem

A partial join today is `(sk-partial owner rule conclusion premises remaining
keys)`: the computation (a rule applied, the premise keys bound so far, the
premises left) together with the node it serves. Two nodes that need the
same computation each build their own copy, step by step, and only the last
step notices: `sk-complete-row!` finds the row present and answers the second
owner.

The skeleton memoizes requests, not computations. Reaching the same row by
several paths means the second path was wasted work.

Measured on StationOps (seed 1, 8 shifts, dormant rules with answers by
index, f 2, q 300): 1,030 rows were created and 635 further completions
found their row already present. All 635 came from a different owner than
the row's creator; none from the same owner.

| first built by | rebuilt by | count |
|---|---|---|
| forward join | query | 516 |
| query | query (another node) | 66 |
| query | forward join | 43 |
| forward join | forward join | 10 |

- In 300 of them both owners have the same statement and differ only in their
  proof pattern, or in being a forward join versus a query node.
- In 318 the creator was the more specific one, for example a forward join
  for `SealLeakAtShiftEnd(… shift-01-M02)` and a query over
  `SealLeakAtShiftEnd $ $ $`.
- Only 17 had a more general creator, the case call subsumption would cover.

The index made this visible: before it, the second copy usually stalled at a
ground premise. Profiled, the index's extra cost is almost all join building
(`sk-wait-on!` and `sk-advance!` +1,300 ticks of 8,500), while its own
bookkeeping is about 1%.

## Rule

A join state is identified by what it computes, not by who asked:

    state = (rule, conclusion statement and context, remaining premises, keys bound)

taken up to variable renaming, with the conclusion's proof and truth value
left out, since a row is built from the statement and context alone. Each
state exists once. Nodes, and the states that extended into it, subscribe
to it. Every step of a join is then done at most once, whoever needs it,
which is what laziness asks for: no step computed twice, and none computed
before something needs it.

Specific nodes stay specific. A ground node's state binds the rule's
variables and reads only the matching premises. Sharing never makes a node
enumerate more than its own pattern does; it only stops two nodes from
enumerating the same thing.

## Structure

- **`&sk_join (shash state)`.** One row per state, keyed by its variant
  hash (`link-digest` of the state term). A state is the old partial minus
  its owner.
- **`&sk_join_sub (shash subscriber)`.** A subscriber is
  `(sk-node-sub node)` for a node whose expansion or activation started the
  rule, `(sk-state-sub parent-hash)` for the state that extended into this
  one, or `sk-forward-sub` for an upward join of a forward run.
- **`&sk_join_result (shash key)`.** The conclusion keys of the rows this
  state or its descendants completed.

Waiting, extension and completion move from partials to states:

- `sk-wait-on!` registers `(premise-hash premise shash)` in `&sk_wait`.
- `sk-extend!` extends a state once per answer key: the `sk-join-link`
  digest is `(shash, key)`. The extended state is looked up by hash. When it
  already exists, the extension only subscribes the parent to it. When it is
  new, it is created and advanced.
- At completion, the row is created as today, or found present. Either way,
  the key becomes a result of the state.

## Results

A new result of state S is added to `&sk_join_result` once. It is then
passed to S's subscribers: a node subscriber gets `sk-add-answer!`, a parent
state records the result and passes it on. The path is at most as long as
the rule has premises.

A new subscriber of an existing state receives the state's results so far
at once, then the later ones as they arrive. This replaces
`sk-row-present?` as the point where a second asker learns of an existing
row, and it happens at the first shared step, not the last.

## Search, budget and deferral

The walk, the step and row budgets, and deferral keep their meaning. Only
the owner they used to read from the partial becomes the state's
subscribers.

- **Child links.** When a node subscribes to a state, it also becomes the
  parent of the premise nodes the state and its unfinished descendants wait
  on (`sk-add-child!`), so a walk from that node reaches them. The score
  given is the node's join score, as today. When several nodes subscribe,
  the premise node keeps the best score (`sk-raise-score!` already does).
- **Root exemption.** A row the query's roots need always fits. A state
  serves a root when a node subscriber is a root, directly or through its
  parents. The test walks subscriber links up, at most the rule's premise
  count.
- **Row budget.** A new row costs the allowance once, whoever completes it.
  A second subscriber pays nothing, which is the saving.
- **Deferral.** A row or extension the allowance cannot pay for waits with
  its state (`&sk_deferred`, `&sk_deferred_joins` keyed by state hash), and
  `&sk_state_of (node-hash shash)` records which top states each node
  subscribes to. When a walk reaches a node (`sk-resume!`), the deferred
  work under that node's states resumes. A deferred state reached by
  several nodes resumes on the first walk that reaches any of them.
  Leftover work still never spends an unrelated query's budget: only a node
  the query's walk reaches resumes it.

## Forward runs

An upward join (`sk-forward-start-step`) creates the state for its rule with
the taken premise bound, subscribed by `sk-forward-sub`. Its rows and
results are stored as today.

A later query node whose rule application is a variant of that state
subscribes to it and reads its results without rebuilding the join. That was
516 of the 635 duplicates. Forward and backward then share join work, where
today they share only finished rows.

Forward joins never wait (they read what exists). A state a forward run
creates and leaves unfinished therefore has no waiters. A query subscribing
to it advances it through the premises it still lacks, as a query advances
any state.

## Query-local rules

Rules with ids of 10⁹ and above exist for one query. Their states are
recorded in the temporary set and removed with the query's other temporary
rows, together with their subscriptions, waits and results
(`sk-clear-temp!`). A permanent state never subscribes to a temporary one:
a state's rule is fixed, and an extension keeps it. So nothing temporary
survives the query.

## Forgetting

A frozen key's rows leave as today. Results naming a buried key are removed
with its answers (`sk-bury!`). A state whose subscribers are all gone can
be dropped by the same garbage collection that drops dependency nodes;
nothing reads it.

## Correctness

A row's identity, its view and self-support exclusion are unchanged: the
same rows are created from the same premise keys. What changes is how many
times the steps toward a row run, and when a second asker hears of it.

- **Answers.** A node receives the conclusion keys of the rows reachable
  from the states it subscribes to. That is exactly what its own copies
  would have produced: each copy's steps are variants of the shared state's
  steps, so they extend with the same keys and complete the same rows.
- **Extension once.** "Every answer extends a partial join once" holds per
  state. A sampling computation still draws once per (state, key).
- **Order.** Answers may reach a second subscriber earlier than before, at
  the first shared step rather than at completion. Within one node, answer
  and row order follow state creation and extension order, which stays
  deterministic. Tests that check order may change; values may not.

## What goes

- The owner field of `sk-partial`; the partial becomes the state.
- `sk-row-present?`'s role in answering a second owner. It stays as the
  guard against duplicate rows from distinct states that complete the same
  ident (different premise orders), which remains possible.
- Per-owner temporary waits: waits are per state.

## Evaluation

1. **Duplicate count** (the probe behind the table above): completions
   finding their row present should drop to the residue from distinct
   states with the same ident.
2. **Unit tests:**
   - two nodes whose rule applications are variants build one state and
     both get the answer;
   - a node subscribing after the state completed is answered at once;
   - a forward join's state is reused by a later query, with no rows added;
   - a query-local rule's states leave with the query;
   - a deferred state resumes when a walk reaches any of its nodes.
3. **Full suite and examples:** values unchanged, order changes reviewed one
   by one.
4. **Replayed grid,** the nine cells of grid54/55, for head and for
   dormancy, both with answers by index. Success: Brier unchanged per cell,
   compute down, most where answers are already found (f 2, q ≥ 200, where
   the index added 1.5–3 s per seed), and memory not up.

## Follow-up: known keys at open waits

Head with sharing gained because queries continued forward-built joins with
the keys the forward run read. A narrower change tested whether dormant rules
gain the same way:
- a join waiting on an open premise of a known predicate reads, once, the
  stored facts and registered ground keys that match it;
- premises with a variable predicate are left out, since they read every
  binary key, the compiler's `And` keys included;
- root rows spend the row allowance while it lasts, so recursive rules stay
  bounded.

It is not adopted. Replayed StationOps, 8 seeds, dormant rules with answers
by index; each cell is Brier, then compute per seed:

| game | f | q | without | with known keys |
|---|---|---|---|---|
| plain | 1 | 50 | 0.0611 (11.2 s) | 0.0601 (12.0 s) |
| plain | 2 | 50 | 0.0590 (14.0 s) | 0.0591 (13.7 s) |
| plain | 2 | 200 | 0.0590 (17.1 s) | 0.0590 (17.4 s) |
| consequence chains | 1 | 50 | 0.0611 (11.0 s) | 0.0601 (12.2 s) |
| consequence chains | 2 | 50 | 0.0610 (14.4 s) | 0.0625 (15.4 s) |
| consequence chains | 2 | 200 | 0.0598 (17.1 s) | 0.0597 (18.4 s) |

Dormant rules already reach the plateau in these cells: head's gain was
search it wasted, which dormancy does not waste.
