# Chainer module dependencies

`pettachainer/metta/petta_chainer.metta` is the stable public facade. It imports
`bootstrap.metta`, which is the single source of truth for the internal load
order. PeTTa specializes equations while modules load, so this order is part of
the implementation contract:

1. `core/types.metta` defines shared nominal types and runtime row shapes.
2. `core/logic_config.metta` defines selectable logic configuration.
3. `third_party/pln_formulas/metta/` provides distributions, inverse operations,
   and truth-value formulas used by compiled rules.
4. `compiler/source_lowering.metta` and `compiler/runtime_encoding.metta`
   provide source lowering and runtime encoding. `compiler/compiler.metta`
   combines them with the rule/specialization component and query lowering.
5. `runtime/values.metta`, `scheduling.metta`, `evidence.metta`, and
   `base_rates.metta` provide shared runtime semantics without owning a search
   engine.
6. `runtime/forward/` loads the forward schemas (trigger keys, aggregate
   identities, materialization marks, a statement's merged stored facts) and
   the incremental aggregate subscriptions. Forward chaining itself runs over
   the skeleton, in `runtime/backward/upward.metta`.
7. `runtime/knowledge_store.metta` owns KB fact, rule, and index insertion;
   `runtime/ingest.metta` coordinates the public compilation/add transaction.
8. `runtime/backward/` loads durable proof storage, proof merging, the recursive
   demand/frontier search component, rule matching, aggregate execution, and the
   final search runner.
9. `runtime/query.metta` provides public single-root and shared multi-root query
   orchestration.

Do not reorder modules merely to make the dependency sequence look more
conventional. Validate every ordering change against the strict loader, full
MeTTa suite, and relevant performance benchmarks.

## Ownership boundaries

- The vendored lowering library owns generic source-to-runtime translation.
  The local compiler owns PLN rule lowering, query lowering, and compiler
  specialization metadata. Neither owns KB insertion or search.
- `runtime/knowledge_store.metta` owns stored facts, rules, and their indexes.
  `runtime/ingest.metta` is the transaction boundary that combines compilation,
  metadata recording, and insertion.
- Forward aggregate subscriptions keep one observation per statement: its
  stored facts merged, or the value a forward run or fold took for its key.
- Backward proof storage owns durable proof DAG rows and liveness indexes.
  `proof_merge.metta` owns factoring, revision, dominance, and candidate
  commitment policy.
- Backward scheduling, root demand, and frontier advancement remain together in
  `search.metta`: they form a recursive component in which demand changes wake
  and reschedule existing frontiers.
- `rule_matching.metta` loads before backward aggregates because an aggregate
  child can itself be resolved through an ordinary stored rule.
- Query wrappers load last. Storage and compiler modules do not depend on query
  orchestration.

These are internal boundaries, not new public APIs. The supported surface is
documented in `docs/metta/API.md` and re-exported through
`pettachainer/metta/petta_chainer.metta`.
