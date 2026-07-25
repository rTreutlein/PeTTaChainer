# TODO

- Refine compound-conclusion indexing, especially for `And`. The current
  `ccls_head_index` key records only the top-level constructor, so every
  `(And ...)` conclusion shares one bucket. The ConceptNet revision benchmark's
  typed export consequently examines roughly 11,000 extra `And` candidates
  even though the logical search and proof counts are unchanged. A sound first
  experiment is a one-level shape key containing the compound head, arity, and
  each non-variable child head, with compatible wildcard buckets queried for
  variable-shaped rules. Keep this optimization out of the typechecking
  performance baseline: that comparison is intended to measure only gains from
  type-driven compilation and code fixes. Evaluate the index separately on its
  own branch/worktree, including index size, candidate inspections, query time,
  and proof equivalence.

- Add an additive merge mode for complementary evidence sets. In cases like `Dog -> Animal` and `Not Dog -> Animal`, the two proofs are split parts of one conditional formula, not independent estimates. If one proof uses `(fact-ev ... d (Dog))` and the other uses `(not-fact-ev ... d (Dog))`, combine the MP-produced strengths additively instead of using `merge/revision` averaging. Also decide how zero-confidence branches should be scheduled once this merge mode exists.

- Decide whether to enable the merge absorption shortcut in `merge-proof-atoms`. The original code had `(if $proof-a (and (= $prfa (merge/revision ...)) (proof-tree-contains $prfa $prfb)) ...)` with condition and value swapped, so the "if one proof's merge/revision tree already contains the other, return it unchanged" shortcut never fired (PeTTa's `if` sends non-boolean conditions to the else branch). The dead branches and the orphaned `proof-tree-contains` helpers were removed; enabling the shortcut properly would change merge results and needs its own evaluation.

- Fix bare single-variable premises in implication queries. `lower-source-premise` unwraps a single-var-element premise `($x)` to the bare var `$x`, which breaks the assumed-premise pipeline: `(query ... (Implication (Premises ($x)) (Conclusions (B))) ...)` returns nothing. Named patterns like `(Feature $x)` work fine. Either support the bare form or reject it explicitly.

- Persist base-rate fold state across queries ("continue where we left off"). Two designs discussed: (a) per-entry contribution maps (instance key -> (w, c) plus kb watermark) so new direct facts fold in without search and derived instances arrive via the low-priority refold; (b) persist the base-rate proof subgraph across chainer runs (closed proof DAG, selective clear, no counter reset) with forward-trigger-keyed selective reopening of `expanded` goals. (b) preserves provenance and generalizes to cross-query tabling but needs evidence filtering for query-context contamination and waiter persistence.
