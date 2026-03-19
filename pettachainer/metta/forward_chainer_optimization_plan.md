# Forward Chainer Optimization Plan

This document maps the useful runtime optimizations from the backward chainer onto the forward chainer.

The goal is not to make the two engines identical. The goal is to move the forward chainer away from repeated full rematching and repeated proof reconstruction, while preserving current semantics around proof merging and incremental rule/fact adds.

## Current Forward Shape

Relevant code:

- [`forward_chainer.metta`](/home/roman/NL2PLN_Project/PeTTaChainer/pettachainer/metta/forward_chainer.metta)
- [`chainer_utils.metta`](/home/roman/NL2PLN_Project/PeTTaChainer/pettachainer/metta/chainer_utils.metta)

Current behavior:

- Facts are queued in a heap keyed by confidence.
- Duplicate queued facts are prevented by scanning the heap linearly.
- When a fact is popped, matching rules are found through `prem_index`.
- For each matching rule, the remaining premises are satisfied by recursively matching `&kb` from scratch.
- Derived facts are merged into `&kb` after the full proof term has already been built.

This means the current forward chainer pays repeatedly for:

- heap dedupe by linear scan
- premise re-satisfaction from scratch
- evidence extraction from nested proof terms
- proof merging after expensive candidate construction

## Backward Optimizations That Transfer Well

### 1. Cached Proof Stats

Backward stores proof metadata once in `&proof_stats`:

- score
- evidence set

Relevant code:

- [`backward_chainer.metta:154`](/home/roman/NL2PLN_Project/PeTTaChainer/pettachainer/metta/backward_chainer.metta#L154)
- [`chainer_utils.metta:99`](/home/roman/NL2PLN_Project/PeTTaChainer/pettachainer/metta/chainer_utils.metta#L99)

Why it applies:

- Forward currently recomputes evidence from proof structure during merge.
- That gets more expensive as proofs get deeper.
- A cache also makes overlap checks cheap enough to use earlier in the derivation path.

Forward design:

- Add a forward proof-id space and a forward proof-stats table.
- Store at least `pid -> score, evidence`.
- Optionally also store `pid -> kind, children, tv` if forward moves to proof references.

Expected benefit:

- cheaper `merge-proof-atoms`
- cheap overlap checks before materializing merged proof terms
- foundation for other optimizations below

### 2. Pending-Score Table and Stale Agenda Suppression

Backward tracks the best queued score per goal and ignores stale heap entries.

Relevant code:

- [`backward_chainer.metta:6`](/home/roman/NL2PLN_Project/PeTTaChainer/pettachainer/metta/backward_chainer.metta#L6)
- [`backward_chainer.metta:105`](/home/roman/NL2PLN_Project/PeTTaChainer/pettachainer/metta/backward_chainer.metta#L105)
- [`backward_chainer.metta:351`](/home/roman/NL2PLN_Project/PeTTaChainer/pettachainer/metta/backward_chainer.metta#L351)

Why it applies:

- Forward currently checks whether a fact is already queued by recursively scanning the heap.
- That is O(n) per enqueue and does not protect against stale lower-priority copies already sitting in the heap.

Forward design:

- Introduce a canonical fact key based on `(kb, type)` rather than full proof term.
- Track `fact_pending_score(key)`.
- On enqueue:
  - do nothing if the queued score is not better than the current pending score
  - otherwise push a new heap item and update the pending score
- On pop:
  - skip the item if its score is stale relative to `fact_pending_score`
  - clear the pending score when the live item is consumed

Expected benefit:

- removes O(n) heap dedupe
- avoids repeated processing of outdated fact queue entries
- preserves best-first behavior more reliably under repeated updates

### 3. Partial Frontier States for Multi-Premise Rules

Backward uses explicit frontier states instead of rematching every remaining premise from scratch.

Relevant code:

- [`backward_chainer.metta:278`](/home/roman/NL2PLN_Project/PeTTaChainer/pettachainer/metta/backward_chainer.metta#L278)
- [`backward_chainer.metta:310`](/home/roman/NL2PLN_Project/PeTTaChainer/pettachainer/metta/backward_chainer.metta#L310)

Why it applies:

- Forward currently uses `forward-satisfy-premises` to walk the rest of the rule by repeated `match &kb`.
- For a rule with many premises, the same partial matches are rediscovered every time a triggering fact is processed.

Forward design:

- Introduce a forward frontier table for partially matched rule applications.
- A frontier instance should hold:
  - rule id
  - current bound environment or instantiated remainder
  - accumulated score
  - accumulated evidence
  - proof ids or proof refs of matched premises
- A new fact should advance matching frontier instances rather than restarting the entire rule body.
- Rule creation should also seed frontier instances from the first premise index, similar to how backward seeds waiters.

Expected benefit:

- major reduction in repeated matching work for conjunction-heavy rules
- better incremental behavior when facts arrive over time
- direct place to add early pruning checks

### 4. Immediate Reuse of Existing Matches

Backward attaches all existing proofs to a new frontier immediately.

Relevant code:

- [`backward_chainer.metta:244`](/home/roman/NL2PLN_Project/PeTTaChainer/pettachainer/metta/backward_chainer.metta#L244)

Why it applies:

- When a new rule or new partial forward frontier is added, the engine should not wait for an already-known fact to be requeued before using it.
- This matters for incremental rule adds and for frontier-based forward evaluation.

Forward design:

- When a frontier is created for a premise pattern, immediately consume all existing matching facts.
- When a new rule is added, seed its initial frontier from existing facts rather than only pushing raw facts back on the agenda.

Expected benefit:

- makes incremental `compileadd` behavior more complete and more predictable
- reduces wasted queue churn after rule insertion

### 5. Early Evidence-Overlap Pruning

Backward blocks frontier advancement when the new proof overlaps with already-seen evidence.

Relevant code:

- [`backward_chainer.metta:314`](/home/roman/NL2PLN_Project/PeTTaChainer/pettachainer/metta/backward_chainer.metta#L314)

Why it applies:

- Forward currently discovers overlap only during final proof merge.
- That means a bad conjunction can still spend time matching all remaining premises and building the resulting proof term.

Forward design:

- Every partial forward frontier carries an evidence set.
- Before extending a frontier with a new supporting fact, reject the step if the evidence overlaps.

Expected benefit:

- prunes invalid or dominated conjunction paths early
- reduces downstream merge pressure

### 6. Dominance Pruning Before KB Upsert

Backward classifies candidates before committing them.

Relevant code:

- [`backward_chainer.metta:136`](/home/roman/NL2PLN_Project/PeTTaChainer/pettachainer/metta/backward_chainer.metta#L136)
- [`backward_chainer.metta:146`](/home/roman/NL2PLN_Project/PeTTaChainer/pettachainer/metta/backward_chainer.metta#L146)

Why it applies:

- Forward currently removes all matching facts from `&kb`, folds `merge-proof-atoms`, then re-adds one merged fact.
- If the new candidate is already dominated by an existing overlapping proof, that whole path is wasted work.

Forward design:

- Before removing existing facts, compare the candidate against cached stats of existing proofs for the same fact key.
- If an existing proof overlap-dominates the candidate, drop the candidate immediately.
- Only run the full merge path when there is a genuine non-dominated alternative.

Expected benefit:

- cheaper updates under high redundancy
- fewer transient remove/readd cycles in `&kb`

### 7. Proof DAG Storage Instead of Nested Proof Terms

Backward stores proofs as nodes with children and materializes only on output.

Relevant code:

- [`backward_chainer.metta:19`](/home/roman/NL2PLN_Project/PeTTaChainer/pettachainer/metta/backward_chainer.metta#L19)
- [`backward_chainer.metta:52`](/home/roman/NL2PLN_Project/PeTTaChainer/pettachainer/metta/backward_chainer.metta#L52)

Why it applies:

- Forward proof terms grow structurally with every derivation and merge.
- Evidence walking, tree containment checks, and repeated merge decisions all become more expensive with depth.

Forward design:

- Store forward facts in `&kb` with `(proof-ref $pid)` rather than a fully materialized proof term.
- Maintain proof kind and child relations in side tables.
- Materialize only for external output or tests that explicitly inspect proof structure.

Expected benefit:

- cheaper internal proof handling
- proof metadata naturally lives next to proof ids
- avoids repeated structural duplication of large proof terms

Cost:

- this is the most invasive change in the plan
- should come after proof-stats caching and frontier work, not before

## Backward Optimizations That Are Mostly Backward-Specific

These are useful concepts, but they should not be copied directly:

- `ensure-goal` and goal-id canonicalization
- `goal-expanded?`
- separate direct-goal and rule-goal expansion phases
- root-goal summary proof machinery

The forward analog is not "goals". The forward analog is "fact keys" and "partial rule states".

## Recommended Implementation Order

### Phase 1. Cheap Wins

- Add a forward fact-key function based on `(kb, type)`.
- Add `fact_pending_score`.
- Remove heap-scan dedupe in favor of pending-score logic.
- Add cached proof stats for newly produced forward facts.

This phase should improve runtime without forcing a major rewrite.

### Phase 2. Better Incremental Firing

- Add forward frontier state for multi-premise rules.
- Make rule insertion seed frontier instances from current KB matches.
- Make frontier creation immediately reuse existing matching facts.

This phase attacks the biggest asymptotic issue in the current forward chainer.

### Phase 3. Early Pruning

- Carry evidence sets on frontier instances.
- Reject overlapping extensions before full derivation.
- Add pre-upsert dominance classification against existing proofs.

This phase should cut redundant work created by Phase 2's broader incremental reach.

### Phase 4. Structural Cleanup

- Move forward proofs to proof ids and `proof-ref`.
- Materialize only at external boundaries.
- Revisit cycle checks once proof ids exist.

This phase is optional unless forward proof growth becomes a real bottleneck after earlier changes.

## Suggested New Runtime Tables

Minimal additions:

- `&fact_pending_score`
- `&fwd_proof_stats`

If frontier matching is added:

- `&fwd_frontier`
- `&fwd_fact_waiter` or equivalent premise-to-frontier index
- `&fwd_proof_kind`
- `&fwd_proof_children`
- `&fwd_proof_tv`

If the existing backward proof tables can be safely shared, that may be simpler than creating parallel forward-only tables. If shared tables are used, the ownership and lifecycle rules need to be explicit so backward and forward state resets do not interfere with each other.

## Suggested Validation Strategy

- Keep [`test_forward_chainer.metta`](/home/roman/NL2PLN_Project/PeTTaChainer/pettachainer/metta/tests/test_forward_chainer.metta) as the main regression target.
- Add a benchmark-style multi-premise forward test with repeated shared prefixes.
- Add a test that inserts a rule after facts already exist and confirms immediate reuse.
- Add a test that repeated lower-confidence enqueues do not cause repeated pops.
- Add a test that overlapping conjunction branches are pruned before producing `merge/revision`.

## Short Version

If only three changes get built, they should be:

1. cached proof stats
2. pending-score agenda suppression
3. partial frontier states for multi-premise rules

Those three carry most of the backward chainer's useful runtime ideas into the forward chainer without forcing a full architectural merge between the two engines.
