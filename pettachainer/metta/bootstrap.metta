;; Internal bootstrap. This is the single source of truth for load order.
;; PeTTa specializes equations while modules are loaded, so this sequence is
;; part of the runtime implementation even though the modules are internal.
!(import! &self (library lib_roman))
!(import! &self (library lib_spaces))
!(import! &self (library lib_import))

!(import! &self core/types)
!(import! &self core/logic_config)

!(use-module! heaps)

!(import_prolog_function (superpose (empty_heap add_to_heap get_from_heap heap_size)))
!(assertzPredicate (Predicate (arity empty_heap 1)))
!(assertzPredicate (Predicate (arity add_to_heap 4)))
!(assertzPredicate (Predicate (arity get_from_heap 4)))
!(assertzPredicate (Predicate (arity heap_size 2)))

;; Prolog helper imports resolve against the process CWD, while MeTTa imports
;; resolve against working_dir. Build both supported paths from working_dir so
;; loading works from the package, repository root, Python, and benchmarks.
!(let*
   (($metta-dir (let $_ (callPredicate (Predicate (working_dir $metta-dir))) $metta-dir))
    ($helper-relative "prolog/runtime_helpers.pl")
    ($runtime-helper
      (let $_
         (callPredicate
            (Predicate (directory_file_path $metta-dir $helper-relative $runtime-helper)))
         $runtime-helper))
    ($metta-parent
      (let $_
         (callPredicate (Predicate (file_directory_name $metta-dir $metta-parent)))
         $metta-parent))
    ($parent-runtime-helper
      (let $_
         (callPredicate
            (Predicate (directory_file_path $metta-parent $helper-relative $parent-runtime-helper)))
         $parent-runtime-helper)))
   (import_prolog_functions_from_file
      (if (== $runtime-helper $parent-runtime-helper)
         $runtime-helper
         (superpose ($runtime-helper $parent-runtime-helper)))
      (sk-order-claims sk-force-causes! sk-force-reset! source-list-union observation-keys observation-sources update-likelihood-support! update-aggregate-sources! aggregate-readers likelihood-support-counts likelihood-sources likelihood-support-admissible? validate-base-rate! functional-pattern? term-covers? validate-ingestion! source-exists? source-rule? set-max-term-bytes context-add! context-remove! set-context-reuse-threshold context-searching? context-rule-visible? context-rule-enabled? context-search-goal context-start! context-answer-seeds! context-seeded? context-addition context-note-rule! context-rule-premises context-leaves context-cold-merged context-finish! context-propagate? context-clear! set-functional-predicate functional-check-additions! functional-fact! functional-rule! sk-functional-conflict? sk-functional-exhausted? sk-functional-subscription sk-functional-delivered! add-space-atom! withdraw-rule! rule-live? proof-ref-negated? proof-zero-likelihood? proof-unsettled-sources sk-row-has-bayes? proof-representative? proof-given-evidence record-view-rule! record-summary-rules! record-stored-rules! forget-stored-rules! withdrawn-stores! proof-live? sk-step-proof same-proof? remove-data-rows! remove-variant-row! heap_pop heap-empty? index-hash statement-prefix-hashes statement-open-hash statement-open-probes kb-fact-prefix-hashes kb-fact-open-hash kb-fact-open-probes sk-link-pending! sk-work! sk-pending? sk-pending-children sk-holds-work? link-digest rule-truth-factor key-context rule-premise existential-key-before? existential-outer-values? existential-source pattern-shape evidence-set evidence-entries evidence-union evidence-join evidence-overlap? evidence-subset? evidence-subtraction evidence-negated evidence-uncertain-overlap? evidence-subtraction-certain evidence-condition evidence-observed-roles evidence-inherited evidence-shared-facts evidence-common-facts evidence-excludes? hash-set hash-union hash-subset? hash-intersection deps-key deps-union deps-join deps-has? deps-meet? deps-excluded deps-within? deps-mask-within? deps-size deps-shared deps-entangled deps-near-shared deps-cut! deps-gc! deps-gc-due? stored-refs-gc! stored-refs-gc-step! rule-dormant? rule-dormancy-wake! rule-dormancy-reset! rule-dormancy-forget-temp! context-create! beta_kl regime-take! regime-evidence proof_dag_expand alpha_unique_keys prune_answer_instances grows-from? link-open-variables term-cost rule-lookup-needs-occurs-check ccls-index-occurs-matches particle_merge_resample hypothesis-candidates hypothesis-failure-candidates hypothesis-exception-pairs hypothesis-place closed-world-gaps hypothesis-constants hypothesis-patterns hypothesis-generalizes? hypothesis-name hypothesis-features hypothesis-link-observations hypothesis-truths hypothesis-read! hypothesis-layers sk-known-conclusion? sk-store-join! sk-keep-child! sk-retire-known! sk-retire-searches! sk-retire-wait! sk-store-wait! sk-store-child!
         sk-fact-watches search-id-value inference-clock inference-add!
         query_metrics_enabled query_metrics_set_enabled
         query_metric_value query_metric_set query_metric_increment)))

!(import! &self ../../third_party/pln_formulas/metta/distributions)
!(import! &self ../../third_party/pln_formulas/metta/compute_inverse)
!(import! &self ../../third_party/pln_formulas/metta/truth_values)
!(import! &self compiler/compiler)

!(import! &self runtime/values)
!(import! &self runtime/scheduling)
!(import! &self runtime/evidence)
!(import! &self runtime/kb_index)
!(import! &self runtime/skeleton_journal)
!(import! &self runtime/base_rates)
!(import! &self runtime/forward/schema)
!(import! &self runtime/forward/aggregates)
!(import! &self runtime/knowledge_store)
!(import! &self runtime/hypothesis_mining)
!(import! &self runtime/observed_predicates)
!(import! &self runtime/ingest)
!(import! &self runtime/backward/skeleton)
!(import! &self runtime/backward/evaluation)
!(import! &self runtime/backward/upward)
!(import! &self runtime/backward/forgetting)
!(import! &self runtime/query)
!(import! &self runtime/hypothesis_review)
!(import! &self runtime/backward/diagnostics)
