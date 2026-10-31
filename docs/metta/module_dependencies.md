# Runtime ownership and internal interfaces

The public API is [API.md](API.md). The internal entry points below are the
names currently consumed outside their subsystem. Other internal definitions
belong to that owner; this inventory does not narrow the public API.
`scripts/coupling.py --json` reproduces this inventory.
It counts lexical references, including emitted instruction names, ABI tables
and error context labels; it does not claim to resolve dynamic calls.

The intended dependency direction is API → invocation controller → search →
evaluator → statistics and knowledge storage → shared terms and physical
stores. The compiler translates source into plans beside that hierarchy.
`bootstrap.metta` is the composition root and the authoritative specialization
order, rather than a runtime dependency layer. A declaration required before
its implementation belongs to that ABI, rather than to a search journal.

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
  Numerical fact merging and population seeding live in `stored_facts.metta`;
  aggregate storage consumes values supplied by that reader.
- `runtime/statistics/` owns contribution replacement, leave-one-out tallies,
  regime state and population cache notifications. `statistics/plans.metta`
  constructs compiler-visible rate descriptors separately from maintaining them.
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
  proof DAGs without constructing evidence. `core/proof_terms.metta` only
  classifies term shapes and binary-certain truth values.
- Native storage is below those readers: `prolog/term_index.pl` encodes keys,
  `functional_store.pl` reads immutable input assignments, `context_overlay.pl`
  routes physical scope, `space_store.pl` writes raw rows and resolves exact
  waiter payloads, `pending_store.pl` maintains pending components without
  consulting fact policy, and `runtime_state.pl` owns evidence, dependency and
  provenance lifetime and scalar instrumentation. It calls no reader policy.
  `core/search_terms.metta` supplies schemas and structural node hashes.
- `core/runtime_terms.metta`, `stored_terms.metta`, `truth_values.metta` and
  `fold_values.metta` provide shared data boundaries and pure normalization.
  These operations do not choose query or evaluation policy.

The raw store dependency order is `rows` → `search_index` / `value_store` →
`journal`; fact/settings indexes, rule identity, schema and allowances have no
store-to-store calls. Core/native services sit below these stores. File-level
call SCCs contain no store: the former 17-file store component is fully split.
The remaining 11-file evaluator/posterior component is outside this round.
The fixed subsystem map still groups readers and publishers with fact storage;
its lexical reciprocal pairs therefore measure a broader boundary.

These files have moved implementations, not forwarding aliases. All baseline
MeTTa equation bodies, signatures and datatype forms are preserved, as are native
clauses in predicate order. Keep the named row fold boundaries: moving a writable
row through an additional reduction can change PeTTa specialization.

## Remaining lexical reciprocal pairs

Three are data references: native ingestion error contexts name `query` and
`compileadd`; a value-cache volatility check recognizes the `rule-likelihood-read`
instruction; native rate validation names `set-base-rate` in its error context.
They are not calls back into those controllers. Two pairs cross the protected
posterior boundary: evaluator admission/cavity callbacks and native graph reset /
context/index access. This round does not claim a complete acyclic hierarchy or
replace the posterior interface; its files were left byte-for-byte unchanged.

## Entry points by owner

### API (6)

`compileadd`, `query`, `query-many`, `query-many-materialize`, `query-many-refs`, `query-materialize`.

### Allowances (16)

`execution-allowances!`, `execution-close-frame!`, `execution-close-slice!`, `execution-open-frame!`, `execution-open-slice!`, `execution-reset-frames!`, `sk-branch-share`, `sk-close-claim!`, `sk-evaluation-free-depth`, `sk-evaluation-per-step`, `sk-open-claim!`, `sk-reserve-near!`, `sk-root-claim-limit`, `sk-root-claim-share`, `sk-take!`, `sk-walk-per-step`.

### Bootstrap/ABI (0)

Composition and declarations only; no equation entry points.

### Compiler (12)

`compile-implication-instance-adds`, `compile-implication-subgoal-query`, `externalize-proof-structure`, `externalize-query-proof`, `internalize-proof-structure`, `mm2compile`, `mm2compileQuery`, `mm2stmt`, `pretty`, `producers`, `rule-truth-installed?`, `statement-query-tv`.

### Compiler plans (12)

`and-tv-goals`, `antecedent-rate-premises`, `base-rate-fold`, `base-rate-premises`, `base-rate-read-plan`, `compound-rate-goals`, `configured-population-prior-tv`, `conjunct-parts`, `population-prior-tv`, `prior-base-rate-premises`, `rate-children`, `rule-base-rate-pattern`.

### Core types (35)

`any-flat?`, `append-flat`, `assumption-proof?`, `bidirectional-implication-form?`, `bidirectional-implication-type?`, `canon`, `certain-tvs?`, `compound-connective?`, `compound-source?`, `configured-compound-output-mode`, `configured-compound-premise-mode`, `conjunct-leaves`, `contextual-cpu?`, `extract-vars`, `fold-semidet`, `foreach-flat`, `head-is-member?`, `head-is?`, `implication-side-conjuncts`, `implication-type?`, `kbctx`, `logic-rule?`, `make-kb-context`, `map-semidet`, `reverse-onto`, `rule-query-pattern`, `seq2expr`, `sk-cons-step`, `sk-node-hash`, `source-computation-head?`, `space-row-present?`, `specializing-predicate?`, `statement-children`, `stored-list-member?`, `vars-covered?`.

### Evaluator (39)

`EventNodeJeffrey`, `EventNodeJoint`, `EventNodeMessage`, `EventNodeValue`, `backward-query-metrics`, `bounded-agenda-prune`, `bounded-agenda-target-size`, `context-cold-merged`, `context-propagate?`, `instance-prior-tv`, `leaf-evidence-for-result`, `premises-expected-confidence`, `rule-likelihood-read`, `set-backward-query-metrics`, `sk-admits?`, `sk-admitted-versions`, `sk-change`, `sk-combination-mode`, `sk-drop-fold-view!`, `sk-evaluate!`, `sk-invalidate-world!`, `sk-key-value`, `sk-leaf-view`, `sk-merge-facts`, `sk-merge-step`, `sk-need-roots!`, `sk-observation-prior`, `sk-open-filter?`, `sk-part-prior`, `sk-rate-entries`, `sk-readers`, `sk-refresh-near!`, `sk-root-keys-step`, `sk-root-results`, `sk-rule-truth-key?`, `sk-stale-held!`, `sk-value`, `sk-version-view`, `stored-statement-candidate`.

### Executor (8)

`chainer-many`, `chainer-many-materialize`, `execute-backward`, `expand-proof`, `present-query-plan-results`, `query-plan-runtime-goal`, `retain-query-proof!`, `run-query-execution-plan`.

### Fact store (41)

`clear-temp-query-adds`, `complete-part?`, `complete-statement?`, `context-polymorphic-facts?`, `context-vars-in-type?`, `forward-fact-key`, `forward-output-index-hash`, `forward-premise-keys`, `forward-type-trigger-key`, `implication-instance-supported?`, `judgment-assumed-key?`, `judgment-consequent?`, `judgment-world-premise?`, `kb-add-atom`, `kb-fact-present?`, `kb-facts`, `kb-publish-fact!`, `kb-publish-materialized!`, `kb-publish-prediction!`, `kb-publish-summary!`, `kb-remove-prediction!`, `kb-retire-copy!`, `link-aggregate-fold!`, `materialized-forward-fact?`, `positive-only-pattern?`, `prefix-key`, `refined-rule?`, `set-positive-only-predicate`, `set-rule-refinement`, `sk-certain?`, `sk-fact-key`, `sk-fact-matches?`, `sk-full-fact`, `sk-full-proof`, `sk-known-leaf-step`, `sk-leaf-facts`, `sk-read-fact`, `sk-world-readers`, `statement-prefix-keys`, `unknown-branch-centre`, `user-base-rate?`.

### Input journal (6)

`sk-clear-root-cap!`, `sk-dirty!`, `sk-input-changed!`, `sk-input-epoch`, `sk-note-fact!`, `sk-note-rule!`.

### Installation (6)

`InstanceEvidenceFormula`, `inject-compiled-adds`, `kb-add-expr`, `set-base-rate`, `sk-retire-store!`, `withdraw-named-rules!`.

### Native stores (27)

`alpha_unique_keys`, `beta_kl`, `context_active`, `ev_union`, `functional_key`, `heap_pop`, `holds_work`, `particle_merge_resample`, `proof_dag_expand`, `proof_ref_id`, `proof_template_erase`, `prune_answer_instances`, `pw_find`, `pw_known`, `pw_pending_rep`, `pw_unlink`, `query_metric_increment`, `query_metric_set`, `query_metric_value`, `query_metrics_enabled`, `query_metrics_set_enabled`, `refs_gc_touch_set`, `sk_search_key`, `sk_unwatch_fact`, `sk_wait_ref`, `statement_index_hashes`, `stored_proof`.

### Posterior (2)

`event_graph_reset`, `observed`.

### Proof search (15)

`context-answer-seeds!`, `sk-activate-facts!`, `sk-activate-pending!`, `sk-activate-rule-row`, `sk-activate-rules!`, `sk-activate-thawed!`, `sk-advance!`, `sk-clear-temp!`, `sk-drain!`, `sk-park-deliveries!`, `sk-register-key!`, `sk-root-reader-step`, `sk-root-score-step`, `sk-root?`, `sk-walk!`.

### Proofs (24)

`all-members?`, `certain-fact-evidence?`, `derivation-proof?`, `deterministic-rule?`, `equivalence-rule?`, `evidence-certainty-step`, `fact-evidence-entry`, `more-specific-application?`, `premise-evidence-overlap?`, `proof-atom-proof`, `proof-children`, `proof-dominates?`, `proof-input-entanglement?`, `proof-term-evidence`, `register-equivalence-rule!`, `register-rule-evidence!`, `rule-application-proof?`, `rule-evidence-base-name`, `rule-evidence-head`, `rule-name?`, `rule-result-evidence`, `shared-evidence-frontier-proof?`, `sk-node-row?`, `specialization-includes?`.

### Runtime terms (21)

`ExistentialFloor`, `assemble-runtime-fact`, `assemble-stored-runtime-fact`, `chainer-acyclic-term?`, `chainer-add-atom`, `chainer-first-or`, `cpu-call`, `expected-tv`, `make-space-pair`, `make-space-row3`, `make-space-row4`, `next-search-id`, `normalize-expected-ctv`, `normalize-expected-evidence-tv`, `normalize-expected-likelihoods`, `normalize-expected-stv`, `stored-number`, `tv-confidence`, `typed-runtime-fact`, `typed-runtime-premise`, `typed-runtime-premises`.

### Search state (39)

`aggregate-fold-function?`, `application-read-plan`, `discover-application`, `discover-triggered-applications`, `existential-fold-source`, `prefilter-premise-blocks?`, `sk-add-reader!`, `sk-add-use!`, `sk-answers`, `sk-children`, `sk-context-search?`, `sk-direct-key-step`, `sk-drop-stale-reader!`, `sk-existential-fold?`, `sk-expanded?`, `sk-grows`, `sk-judgment-main-rule-match`, `sk-link-new!`, `sk-mark-dirty!`, `sk-mark-expanded!`, `sk-node-prefix`, `sk-node-score`, `sk-premise-rules-step`, `sk-prior-folds`, `sk-prior-inputs`, `sk-raise-score!`, `sk-remove-reader!`, `sk-rule-goal`, `sk-rule-match`, `sk-rule-score`, `sk-set-truth-factor!`, `sk-stale-reader!`, `sk-touch-key!`, `sk-unifier-add!`, `sk-unifier-hashes`, `sk-unifying-key-hashes`, `sk-unifying-readers`, `sk-unindex-key!`, `sk-use-step!`.

### Statistics (40)

`base-rate-aggregate-key`, `base-rate-cache-entries-for-mode`, `base-rate-cache-hash`, `base-rate-cache-remove!`, `base-rate-entry-tv`, `base-rate-entry-user?`, `base-rate-finish?`, `base-rate-readers-changed!`, `cached-base-rate`, `fa-id`, `fa-instance-acc`, `fa-left-out`, `fa-premise-subscriptions`, `fa-register!`, `fa-remove!`, `fa-result`, `fa-update!`, `finish-aggregate`, `forward-maintain-aggregates!`, `forward-rate-folds`, `hm-observe!`, `hm-outcomes`, `hm-pattern-hash`, `hm-screen-changed!`, `ledger-instance-changed!`, `ledger-instance-read-excluding`, `ledger-member-current!`, `ledger-read-excluding`, `ledger-replace-instance!`, `ledger-reset-regime!`, `ledger-set-base-rate!`, `ledger-take-change!`, `register-forward-aggregate-premises!`, `sk-instance-fold-key?`, `sk-instance-fold?`, `sk-left-out`, `sk-rate-changed`, `sk-rate-dirty!`, `sk-rate-fold?`, `smoothed-base-rate-tv`.

### Value store (23)

`sk-branch-excludes?`, `sk-branch-values`, `sk-cache-branch!`, `sk-cache-summary-reference!`, `sk-clear-query-values!`, `sk-deps-roots`, `sk-drop-merged!`, `sk-drop-row!`, `sk-drop-row-views!`, `sk-excludes?`, `sk-finish-branch-request!`, `sk-invalidate-branches!`, `sk-latest-view`, `sk-live-view?`, `sk-note-cuts!`, `sk-older-views`, `sk-request-branch!`, `sk-row-support`, `sk-same-view?`, `sk-store-view!`, `sk-uncache!`, `sk-update-representative!`, `sk-view-deps-step`.
