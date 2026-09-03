# Fold nodes: one result mechanism for goals and aggregates

Every backward goal turns many proofs into one representative per output key.
An ordinary goal does it with a fixed accumulator (independence filter, then
revision or lifting merge). A `FoldAllCompiled` / `GroupedFoldAllCompiled` goal
does it with the accumulator named in its arguments over the representatives of
a source goal. This document fixes the shared contract so the two share one
result store, one replacement primitive, one liveness rule and one durable
restore path. What remains specific to folds is listed at the end.

## Vocabulary

- **Fold goal**: a goal whose term is `(CPU FoldAllCompiled args $result)` or
  `(CPU GroupedFoldAllCompiled args $result)`. `aggregate-fold-function?`
  recognises the head.
- **Snapshot**: a proof of a fold goal. Kind `(aggregate $term)`, children =
  the source proof ids folded, evidence per the fold's evidence policy.
- **Fold key**: the output key of a snapshot. It is the fold term *without the
  result value*, `(quote (CPU F args))`. Two snapshots of the same fold, or of
  the same group of a grouped fold (the group key is inside `args`), share one
  fold key. `candidate-output-key` implements this; there is no separate
  snapshot key.
- **Source goal**: the goal compiled from the fold's pattern. Its
  representatives are the fold's inputs.

## Result store (shared)

1. A snapshot is stored through `store-proof-candidate` like any proof: a row
   in `&proof` owned by the fold goal's key, indexed in `&proof_goal`, a
   candidate row in `&proof_current`, a result row in `&proof_current_result`.
2. **Replace policy.** Storing a snapshot whose fold key already has a result
   representative replaces it: the old representative leaves `&proof_current`
   and `&proof_current_result`, is marked superseded, its liveness cache and
   dependents are invalidated, and the new snapshot becomes the result
   directly. No dirty flag, no merge, no dominance. The old row stays in
   `&proof` as history. This is `replace-result!`; the ordinary accumulate
   policy (candidate stays, key marked dirty, representative refreshed lazily)
   is unchanged for every other kind.
3. A fold goal therefore has at most one current candidate per fold key. The
   normal representative rule for CPU groups (`latest-live-proof-id`) is
   consistent with that and needs no special case.
4. `&aggregate` no longer carries a current-pid list. `result-ids` /
   `current-proof-result-id-for-output-key` on the fold goal's key are the only
   way to read a fold's current snapshots.

## Liveness (shared)

A snapshot is live iff it is still a current representative (not superseded,
not retired) and every child is live. The `&aggregate` probe and
`durable-aggregate-representative?` are gone; superseding at replacement is
what makes the previous snapshot dead. Static liveness is decided by proof
kind alone: aggregate-kind proofs are never static.

## Durable restore (shared)

Result rows are durable across queries. A fold goal created in a later query
resolves to the same goal key and finds its latest snapshot through the normal
result index, exactly as an ordinary goal reuses a completed proof. There is no
separate durable-restore walk for folds. Base-rate folds are harvested into the
base-rate cache after each query and their snapshot stays current: it is
superseded only when the facts it folded change (a new fact instantiating the
fold's pattern, `set-base-rate`, `clear-base-rate`, a universe change request
the retirement, consumed when the next query starts) and at the next spawn the
cache seeds the refold. An empty member-inheritance fold is an exhausted-budget
observation, not a value, and is retired at harvest so a larger budget retries.

## Scheduling (fold-specific)

The source goal is the budgeted search. The fold itself is a refresh over the
source goal's current representatives:

- Spawning a fold goal creates the source goal one level deeper, records a
  `fold-source-row` (fold gid, source gid, base score, search budget,
  forward-approx flag) in `&fold_source`, and registers an `aggregate-waiter`
  on the source. The row is query-local search state like the goal row.
- A source proof commit wakes the fold goal's `agenda-aggregate` lane. The
  lane coalesces: one pending refresh per fold goal, re-issued only when the
  requested score rises. Pending-ness is the lane membership in the goal's
  agenda state; there is no separate pending counter.
- Popping the lane runs `refresh-fold-heap`: collect source representatives
  (excluding proofs that depend on the fold goal itself and materialized
  forward facts), accumulate one state per group key, then commit each state
  through `commit-fold-snapshot-heap`. A scalar fold is the single group
  `scalar`, seeded with the accumulator's initial value so an empty source
  still commits its neutral result. Only the typed step differs between the
  two spec shapes; accumulation, result construction, the evidence policy and
  the degrade guard are shared.
- `commit-fold-snapshot-heap` is the single commit path for scalar, grouped,
  cached and user-supplied snapshots: unchanged result (alpha-equal term and
  equal evidence to the current representative) wakes the existing
  representative; a cyclic candidate is dropped; otherwise the snapshot is
  stored with the replace policy and its waiters are woken.

The residual difference to ordinary goals is timing: an ordinary goal refreshes
its representative at read time because revision is cheap and per-key; a fold
refreshes on the agenda because one source commit may change every group and
the fold is linear in the source count, so refreshes must coalesce across
source commits and be budgeted.

## Policies attached to the fold spec (fold-specific)

- **Evidence**: base-rate, `uniform-prior` and `uniform-prior-known` finishes
  commit with empty evidence (population statistics are evidence-transparent).
  The policy is keyed on the finish, so it applies to grouped folds too.
- **Harvest**: after a search one pass over the fold-source rows publishes
  each base-rate fold's current snapshot: a computed STV seeds the cache and
  the forward statistics (and is superseded unless materialized); an empty
  member-inheritance fold with no refresh pending records its budget as an
  authoritative empty cache entry.
- **Acceptance**: a base-rate fold that is not forward-approx may not replace a
  snapshot with a lower-confidence STV (`ba-degrades?`).
- **Cache**: base-rate folds consult `&base_rate_cache` at spawn: a user entry
  commits directly without a source goal; a computed or forward-approx entry
  commits as the first snapshot and schedules the live refold with the
  discounted demand spec.
- **Index**: base-rate fold goals register their base-rate key against their
  goal key in `&base_rate_fold` once, at spawn. Invalidation on `set-base-rate`,
  `clear-base-rate`, universe or prior changes looks up the goal keys for the
  affected base-rate keys and supersedes their current results. No per-pid
  index maintenance.

## What this removes

`stored-aggregate-row` current pids and pending counter,
`set-aggregate-current-pid!`, `append-grouped-aggregate-current-pid!`,
`ba-current?`, `ba-durable`/`ba-restorable`, `aggregate-snapshot-groups`,
`aggregate-snapshot-key-by-id`, `durable-aggregate-representative?`, the
`&aggregate` probe in `compute-live` and `mark-static-proof!`, the
`&base_rate_aggregate_current*` pid indexes and their maintenance in
`remove-current!`, the `&aggregate_search_budget` and
`&aggregate_forward_approx` spaces (columns of the fold-source row), and the
fold special case in `frontier-compatible-source-ids`.

## Invariants to test

- Two snapshots of one fold key never coexist in `&proof_current`.
- Replacing a snapshot supersedes the old one, invalidates its dependents,
  and leaves it retrievable from `&proof` as history.
- A grouped fold keeps one current snapshot per group key.
- A fold goal re-created in a later query sees its last snapshot as its
  result without any fold-specific restore.
- A lower-confidence base-rate refold is rejected unless the current snapshot
  is forward-approx; any other fold replaces on change regardless of
  confidence.
