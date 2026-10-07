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
   (($metta-dir
      (let $_
         (callPredicate
            (Predicate (working_dir $metta-dir)))
         $metta-dir))
    ($helper-relative "prolog/runtime_helpers.pl")
    ($runtime-helper
      (let $_
         (callPredicate
            (Predicate
               (directory_file_path
                  $metta-dir $helper-relative $runtime-helper)))
         $runtime-helper))
    ($metta-parent
      (let $_
         (callPredicate
            (Predicate
               (file_directory_name
                  $metta-dir $metta-parent)))
         $metta-parent))
    ($parent-runtime-helper
      (let $_
         (callPredicate
            (Predicate
               (directory_file_path
                  $metta-parent $helper-relative $parent-runtime-helper)))
         $parent-runtime-helper)))
   (if (== $runtime-helper $parent-runtime-helper)
      (import_prolog_functions_from_file
         $runtime-helper
         (remove-data-rows! remove-variant-row! heap_pop heap-empty? index-hash statement-prefix-hashes link-digest pattern-shape evidence-member? evidence-intersection evidence-subtraction evidence-sets-overlap? hash-set hash-union deps-key deps-union deps-join deps-has? deps-meet? deps-within? deps-mask-within? deps-size deps-cut! deps-gc! rule-dormant? rule-dormancy-wake! rule-dormancy-reset! context-world! context-world? context-affected? context-pattern-affected? context-affected-reset! context-forget! beta_kl proof_dag_expand alpha_unique_keys prune_answer_instances rule-lookup-needs-occurs-check ccls-index-occurs-matches particle_merge_resample
            query_metrics_enabled query_metrics_set_enabled
            query_metric_value query_metric_set query_metric_increment))
      (superpose
         ((import_prolog_functions_from_file
             $runtime-helper
             (remove-data-rows! remove-variant-row! heap_pop heap-empty? index-hash statement-prefix-hashes link-digest pattern-shape evidence-member? evidence-intersection evidence-subtraction evidence-sets-overlap? hash-set hash-union deps-key deps-union deps-join deps-has? deps-meet? deps-within? deps-mask-within? deps-size deps-cut! deps-gc! rule-dormant? rule-dormancy-wake! rule-dormancy-reset! context-world! context-world? context-affected? context-pattern-affected? context-affected-reset! context-forget! beta_kl proof_dag_expand alpha_unique_keys prune_answer_instances rule-lookup-needs-occurs-check ccls-index-occurs-matches particle_merge_resample
                query_metrics_enabled query_metrics_set_enabled
                query_metric_value query_metric_set
                query_metric_increment))
          (import_prolog_functions_from_file
             $parent-runtime-helper
             (remove-data-rows! remove-variant-row! heap_pop heap-empty? index-hash statement-prefix-hashes link-digest pattern-shape evidence-member? evidence-intersection evidence-subtraction evidence-sets-overlap? hash-set hash-union deps-key deps-union deps-join deps-has? deps-meet? deps-within? deps-mask-within? deps-size deps-cut! deps-gc! rule-dormant? rule-dormancy-wake! rule-dormancy-reset! context-world! context-world? context-affected? context-pattern-affected? context-affected-reset! context-forget! beta_kl proof_dag_expand alpha_unique_keys prune_answer_instances rule-lookup-needs-occurs-check ccls-index-occurs-matches particle_merge_resample
                query_metrics_enabled query_metrics_set_enabled
                query_metric_value query_metric_set
                query_metric_increment))))))

!(import! &self ../../third_party/pln_formulas/metta/distributions)
!(import! &self ../../third_party/pln_formulas/metta/compute_inverse)
!(import! &self ../../third_party/pln_formulas/metta/truth_values)
!(import! &self compiler/compiler)

!(import! &self runtime/values)
!(import! &self runtime/scheduling)
!(import! &self runtime/evidence)
!(import! &self runtime/skeleton_journal)
!(import! &self runtime/base_rates)
!(import! &self runtime/forward/schema)
!(import! &self runtime/forward/aggregates)
!(import! &self runtime/knowledge_store)
!(import! &self runtime/ingest)
!(import! &self runtime/backward/skeleton)
!(import! &self runtime/backward/evaluation)
!(import! &self runtime/backward/upward)
!(import! &self runtime/backward/forgetting)
!(import! &self runtime/query)
