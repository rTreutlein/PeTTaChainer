;; Internal bootstrap. This is the single source of truth for load order.
;; PeTTa specializes equations while modules are loaded, so this sequence is
;; part of the runtime implementation even though the modules are internal.
!(import! &self (library lib_roman))
!(import! &self (library lib_spaces))
!(import! &self (library lib_import))

!(import! &self core/types)
!(import! &self lib/collections)
!(import! &self core/vocabulary)
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
      (quote (declare-natives! execution-declare!))))

!(import! &self core/natives)
!(declare-stores!)

!(import! &self ../../third_party/pln_formulas/metta/distributions)
!(import! &self ../../third_party/pln_formulas/metta/compute_inverse)
!(import! &self ../../third_party/pln_formulas/metta/truth_values)
!(import! &self runtime/store/rule_identity)
!(import! &self runtime/store/predicate_policy)
!(import! &self runtime/statistics/plans)
!(import! &self core/fold_values)
!(import! &self compiler/compiler)

!(import! &self core/truth_values)
!(import! &self core/runtime_terms)
!(import! &self runtime/values)
!(import! &self runtime/scheduling)
!(import! &self runtime/evaluator/formulas)
!(import! &self runtime/store/proofs)
!(import! &self runtime/store/fact_index)
!(import! &self runtime/store/contracts)
!(import! &self runtime/store/journal)
!(import! &self runtime/statistics/base_rates)
!(import! &self runtime/store/schema)
!(import! &self runtime/evaluator/types)
!(import! &self runtime/store/fact_reads)
!(import! &self runtime/store/application_policy)
!(import! &self runtime/store/applications)
!(import! &self runtime/store/allowances)
!(import! &self runtime/statistics/ledger)
!(import! &self runtime/statistics/aggregates)
!(import! &self runtime/evaluator/stored_facts)
!(import! &self runtime/store/publication)
!(import! &self core/stored_terms)
!(import! &self runtime/installation)
!(import! &self runtime/hypothesis_mining)
!(import! &self runtime/observed_predicates)
!(import! &self runtime/ingest)
!(import! &self runtime/store/fact_policy)
!(import! &self runtime/store/value_store)
!(import! &self runtime/store/search_index)
!(import! &self runtime/store/rows)
!(import! &self runtime/backward/skeleton)
!(import! &self runtime/evaluator/values)
!(import! &self runtime/evaluator/versions)
!(import! &self runtime/evaluator/merge)
!(import! &self runtime/evaluator/folds)
!(import! &self runtime/evaluator/sampling)
!(import! &self runtime/evaluator/core)
!(import! &self runtime/evaluator/work)
!(import! &self runtime/evaluator/evaluation)
!(import! &self runtime/configuration)
!(import! &self runtime/evaluator/context)
!(import! &self runtime/backward/upward)
!(import! &self runtime/backward/forgetting)
!(import! &self runtime/store/retirement)
!(import! &self runtime/backward/execution)
!(import! &self runtime/presentation)
!(import! &self runtime/query)
!(import! &self runtime/hypothesis_review)
!(import! &self runtime/backward/diagnostics)
