# Runtime ownership and internal interfaces

[API.md](API.md) defines public signatures; [layers.md](layers.md) inventories
internal entry points in layer order. `bootstrap.metta` is the composition root
and authoritative specialization order. Declarations needed before their
implementations belong to its ABI.

## Ownership

- `runtime/query.metta` and `ingest.metta` compile public requests.
  `installation.metta` installs compiler additions and coordinates withdrawal;
  `configuration.metta` applies configuration through installation and ledger
  transactions. They do not own physical fact publication.
- `runtime/backward/execution.metta` owns invocation/finally brackets and worlds;
  `presentation.metta` formats answers while their references are still held.
  `backward/upward.metta` selects forward work, and `backward/forgetting.metta`
  selects idle keys for eviction or summarization.
- `runtime/backward/skeleton.metta` constructs and traverses proof-search work.
  `store/search_index.metta` owns shared keys, readers and indexed search-state
  reads. `runtime/application_discovery/` matches compiled applications and
  describes inputs without expanding or evaluating them. Its native ownership and
  bounded retirement service is `prolog/application_support/search_state.pl`,
  above fact selection rather than inside the raw state backend. Raw component
  counters and graph operations live separately in `prolog/pending_store.pl`.
  Search preparation, including root producer installation, belongs to search.
- `runtime/evaluator/` owns the mutually recursive value/row/conditioning engine,
  numerical context reads, demand and value-change propagation. Its early
  instruction scoring remains in `runtime/values.metta` and `scheduling.metta`.
  Cache admission and pending-search inspection live in `backward/eval_cache.metta`.
  Numerical fact merging and population seeding live in `stored_facts.metta`;
  aggregate storage consumes values supplied by that reader.
- `runtime/statistics/` owns contribution replacement, leave-one-out tallies,
  regime state and population cache notifications. `statistics/plans.metta`
  constructs compiler-visible rate descriptors separately from maintaining them;
  `plans_fold.metta` classifies their lowered forms without accessing state.
- `runtime/store/` owns raw fact/settings indexes, rule identity, input epochs,
  dirty keys, retained value versions, key/reader indexes, row removal and budget
  frames. Stores call core terms, collection primitives and native services, or
  lower stores; they never call reader policy, compiler plans or proof semantics.
  `runtime/skeleton_journal.metta` coordinates ingestion notifications above the
  raw journal, catalog and dormancy services. `kb_publication.metta` publishes
  supplied facts; `installation_retirement.metta` removes withdrawn copies.
- `runtime/fact_reads/` owns fact selection, borrowing, declaration installation
  and completeness policy. `runtime/proofs.metta` and
  `prolog/proof_semantics.pl` own proof/evidence meaning and construction.
  `prolog/proof_terms.pl` reads immutable metadata, application templates and
  proof DAGs without constructing evidence. `runtime/proofs.metta` also owns
  proof-shape classifiers, binary-certainty checks and proof expansion.
- Native storage is below those readers: `prolog/term_index.pl` encodes keys,
  `functional_store.pl` reads immutable input assignments, `context_overlay.pl`
  routes physical scope, `space_store.pl` writes raw rows and resolves exact
  waiter payloads, `pending_store.pl` maintains pending components without
  consulting fact policy, and `runtime_state.pl` owns evidence, dependency and
  provenance lifetime and scalar instrumentation. It calls no reader policy.
  `core/search_terms.metta` supplies schemas and structural node hashes.
- `core/runtime_terms.metta`, `stored_terms.metta`, `truth_values.metta` and
  `fold_values.metta` provide shared data boundaries and pure normalization.
  `runtime_terms_keys.metta` owns pure key adapters.
  These operations do not choose query or evaluation policy.
- `lib/` holds chainer-independent support below all of these: list and space
  operations (`collections.metta`), native registration, the `finally` cleanup
  bracket and host calls (`natives.pl`), variant deduplication, ordered integer
  sets and heaps (`collections.pl`) and numeric kernels (`numeric.pl`), declared
  by `natives.metta`.

The raw store dependency order is `rows` → `search_index` / `value_store` →
`journal`; fact/settings indexes, rule identity, schema and allowances have no
store-to-store calls. Core/native services sit below these stores. File-level
call SCCs contain no store: the former 17-file store component is fully split.
The remaining 11-file evaluator/posterior component is outside this round.
The fixed subsystem map still groups readers and publishers with fact storage;
its lexical reciprocal pairs therefore measure a broader boundary.

Implementations move without forwarding aliases. Single-use configuration and
prefix projections are inlined at their callers. Keep the named row fold
boundaries: moving a writable row through an additional reduction can change
PeTTa specialization.

## Interface inventory

[layers.md](layers.md) lists every cross-subsystem entry point in the fixed
layer order. The two remaining reciprocal pairs cross the protected posterior
boundary: evaluator admission/cavity callbacks, and native graph reset /
context/index access. Native ingestion diagnostics still name the public API;
these labels are lexical references, not controller calls.
