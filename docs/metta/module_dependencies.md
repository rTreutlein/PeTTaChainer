# Runtime ownership and internal interfaces

The public API is [API.md](API.md). The internal entry points below are the
names currently consumed outside their subsystem; all other definitions are
private to that owner. `scripts/coupling.py --json` reproduces this inventory.
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
  reads. `store/applications.metta` matches compiled applications and describes
  inputs without expanding or evaluating them. Search preparation, including
  root producer installation, belongs to search, not the evaluator.
- `runtime/evaluator/` owns the mutually recursive value/row/conditioning engine,
  numerical context reads, demand and value-change propagation. Its early
  instruction scoring remains in `runtime/values.metta` and `scheduling.metta`.
  Numerical fact merging and population seeding live in `stored_facts.metta`;
  aggregate storage consumes values supplied by that reader.
- `runtime/statistics/` owns contribution replacement, leave-one-out tallies,
  regime state and population cache notifications. `statistics/plans.metta`
  constructs compiler-visible rate descriptors separately from maintaining them.
- `runtime/store/` separates indexed fact reads and publication, rule identity,
  predicate policy, the input journal, value versions, and physical row/copy
  retirement. The input journal records changes; it does not expand search.
  `store/allowances.metta` owns budget slices and frame state used by both engines.
- `store/proofs.metta` and `prolog/proof_semantics.pl` own proof/evidence meaning
  and DAG presentation. Native metadata marking/removal and immutable functional
  key lookup live with physical state in `prolog/runtime_state.pl`.
- `core/runtime_terms.metta`, `stored_terms.metta`, `truth_values.metta` and
  `fold_values.metta` provide shared data boundaries and pure normalization.
  These operations do not choose query or evaluation policy.

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

### Compiler plans (13)

`and-tv-goals`, `antecedent-rate-premises`, `base-rate-fold`, `base-rate-premises`, `base-rate-read-plan`, `compound-rate-goals`, `configured-population-prior-tv`, `conjunct-parts`, `population-prior-tv`, `prior-base-rate-premises`, `rate-children`, `rule-base-rate-pattern`, `user-base-rate?`.

### Core types (32)

`any-flat?`, `append-flat`, `bidirectional-implication-form?`, `bidirectional-implication-type?`, `canon`, `compound-connective?`, `compound-source?`, `configured-compound-output-mode`, `configured-compound-premise-mode`, `conjunct-leaves`, `contextual-cpu?`, `extract-vars`, `fold-semidet`, `foreach-flat`, `head-is-member?`, `head-is?`, `implication-side-conjuncts`, `implication-type?`, `kbctx`, `logic-rule?`, `make-kb-context`, `map-semidet`, `reverse-onto`, `rule-query-pattern`, `seq2expr`, `sk-cons-step`, `source-computation-head?`, `space-row-present?`, `specializing-predicate?`, `statement-children`, `stored-list-member?`, `vars-covered?`.

### Evaluator (39)

`EventNodeJeffrey`, `EventNodeJoint`, `EventNodeMessage`, `EventNodeValue`, `backward-query-metrics`, `bounded-agenda-prune`, `bounded-agenda-target-size`, `context-cold-merged`, `context-propagate?`, `instance-prior-tv`, `leaf-evidence-for-result`, `premises-expected-confidence`, `rule-likelihood-read`, `set-backward-query-metrics`, `sk-admits?`, `sk-admitted-versions`, `sk-change`, `sk-combination-mode`, `sk-drop-fold-view!`, `sk-evaluate!`, `sk-invalidate-world!`, `sk-key-value`, `sk-leaf-view`, `sk-merge-facts`, `sk-merge-step`, `sk-need-roots!`, `sk-observation-prior`, `sk-open-filter?`, `sk-part-prior`, `sk-rate-entries`, `sk-readers`, `sk-refresh-near!`, `sk-root-keys-step`, `sk-root-results`, `sk-rule-truth-key?`, `sk-stale-held!`, `sk-value`, `sk-version-view`, `stored-statement-candidate`.

### Executor (8)

`chainer-many`, `chainer-many-materialize`, `execute-backward`, `expand-proof`, `present-query-plan-results`, `query-plan-runtime-goal`, `retain-query-proof!`, `run-query-execution-plan`.

### Fact store (48)

`application-read-plan`, `clear-temp-query-adds`, `complete-part?`, `complete-statement?`, `context-polymorphic-facts?`, `context-vars-in-type?`, `forward-fact-key`, `forward-output-index-hash`, `forward-premise-keys`, `forward-type-trigger-key`, `implication-instance-supported?`, `judgment-assumed-key?`, `judgment-consequent?`, `judgment-world-premise?`, `kb-add-atom`, `kb-fact-present?`, `kb-facts`, `kb-publish-fact!`, `kb-publish-materialized!`, `kb-publish-prediction!`, `kb-publish-summary!`, `kb-remove-prediction!`, `kb-retire-copy!`, `link-aggregate-fold!`, `materialized-forward-fact?`, `positive-only-pattern?`, `prefix-key`, `refined-rule?`, `set-positive-only-predicate`, `set-rule-refinement`, `sk-certain?`, `sk-clear-root-cap!`, `sk-dirty!`, `sk-fact-key`, `sk-fact-matches?`, `sk-full-fact`, `sk-full-proof`, `sk-input-changed!`, `sk-input-epoch`, `sk-known-leaf-step`, `sk-leaf-facts`, `sk-node-hash`, `sk-note-fact!`, `sk-note-rule!`, `sk-read-fact`, `sk-world-readers`, `statement-prefix-keys`, `unknown-branch-centre`.

### Installation (5)

`InstanceEvidenceFormula`, `inject-compiled-adds`, `kb-add-expr`, `set-base-rate`, `withdraw-named-rules!`.

### Native stores (18)

`alpha_unique_keys`, `beta_kl`, `context_active`, `ev_union`, `functional_key`, `heap_pop`, `particle_merge_resample`, `proof_ref_id`, `prune_answer_instances`, `query_metric_increment`, `query_metric_set`, `query_metric_value`, `query_metrics_enabled`, `query_metrics_set_enabled`, `refs_gc_touch_set`, `sk_queue_retirement`, `sk_search_owned`, `statement_index_hashes`.

### Posterior (2)

`event_graph_reset`, `observed`.

### Proof search (15)

`context-answer-seeds!`, `sk-activate-facts!`, `sk-activate-pending!`, `sk-activate-rule-row`, `sk-activate-rules!`, `sk-activate-thawed!`, `sk-advance!`, `sk-clear-temp!`, `sk-drain!`, `sk-park-deliveries!`, `sk-register-key!`, `sk-root-reader-step`, `sk-root-score-step`, `sk-root?`, `sk-walk!`.

### Proofs (29)

`all-members?`, `assumption-proof?`, `certain-fact-evidence?`, `certain-tvs?`, `derivation-proof?`, `deterministic-rule?`, `equivalence-rule?`, `evidence-certainty-step`, `fact-evidence-entry`, `more-specific-application?`, `premise-evidence-overlap?`, `proof-atom-proof`, `proof-children`, `proof-dominates?`, `proof-input-entanglement?`, `proof-term-evidence`, `proof_dag_expand`, `proof_template_erase`, `register-equivalence-rule!`, `register-rule-evidence!`, `rule-application-proof?`, `rule-evidence-base-name`, `rule-evidence-head`, `rule-name?`, `rule-result-evidence`, `shared-evidence-frontier-proof?`, `sk-node-row?`, `specialization-includes?`, `stored_proof`.

### Runtime terms (21)

`ExistentialFloor`, `assemble-runtime-fact`, `assemble-stored-runtime-fact`, `chainer-acyclic-term?`, `chainer-add-atom`, `chainer-first-or`, `cpu-call`, `expected-tv`, `make-space-pair`, `make-space-row3`, `make-space-row4`, `next-search-id`, `normalize-expected-ctv`, `normalize-expected-evidence-tv`, `normalize-expected-likelihoods`, `normalize-expected-stv`, `stored-number`, `tv-confidence`, `typed-runtime-fact`, `typed-runtime-premise`, `typed-runtime-premises`.

### Search state (38)

`aggregate-fold-function?`, `discover-application`, `discover-triggered-applications`, `existential-fold-source`, `prefilter-premise-blocks?`, `sk-add-reader!`, `sk-add-use!`, `sk-answers`, `sk-children`, `sk-context-search?`, `sk-direct-key-step`, `sk-drop-stale-reader!`, `sk-existential-fold?`, `sk-expanded?`, `sk-grows`, `sk-judgment-main-rule-match`, `sk-link-new!`, `sk-mark-dirty!`, `sk-mark-expanded!`, `sk-node-prefix`, `sk-node-score`, `sk-premise-rules-step`, `sk-prior-folds`, `sk-prior-inputs`, `sk-raise-score!`, `sk-remove-reader!`, `sk-rule-goal`, `sk-rule-match`, `sk-rule-score`, `sk-set-truth-factor!`, `sk-stale-reader!`, `sk-touch-key!`, `sk-unifier-add!`, `sk-unifier-hashes`, `sk-unifying-key-hashes`, `sk-unifying-readers`, `sk-unindex-key!`, `sk-use-step!`.

### Statistics (40)

`base-rate-aggregate-key`, `base-rate-cache-entries-for-mode`, `base-rate-cache-hash`, `base-rate-cache-remove!`, `base-rate-entry-tv`, `base-rate-entry-user?`, `base-rate-finish?`, `base-rate-readers-changed!`, `cached-base-rate`, `fa-id`, `fa-instance-acc`, `fa-left-out`, `fa-premise-subscriptions`, `fa-register!`, `fa-remove!`, `fa-result`, `fa-update!`, `finish-aggregate`, `forward-maintain-aggregates!`, `forward-rate-folds`, `hm-observe!`, `hm-outcomes`, `hm-pattern-hash`, `hm-screen-changed!`, `ledger-instance-changed!`, `ledger-instance-read-excluding`, `ledger-member-current!`, `ledger-read-excluding`, `ledger-replace-instance!`, `ledger-reset-regime!`, `ledger-set-base-rate!`, `ledger-take-change!`, `register-forward-aggregate-premises!`, `sk-instance-fold-key?`, `sk-instance-fold?`, `sk-left-out`, `sk-rate-changed`, `sk-rate-dirty!`, `sk-rate-fold?`, `smoothed-base-rate-tv`.

### Value store (25)

`sk-branch-excludes?`, `sk-branch-values`, `sk-cache-branch!`, `sk-cache-summary-reference!`, `sk-clear-query-values!`, `sk-commit-result!`, `sk-deps-roots`, `sk-drop-merged!`, `sk-drop-row!`, `sk-drop-row-views!`, `sk-excludes?`, `sk-finish-branch-request!`, `sk-invalidate-branches!`, `sk-latest-view`, `sk-live-view?`, `sk-note-cuts!`, `sk-older-views`, `sk-request-branch!`, `sk-retire-store!`, `sk-same-view?`, `sk-store-view!`, `sk-uncache!`, `sk-update-representative!`, `sk-view-deps-step`, `sk-view-step-proof`.
