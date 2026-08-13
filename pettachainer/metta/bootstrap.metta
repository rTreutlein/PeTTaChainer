;; Internal bootstrap. This is the single source of truth for load order.
;; PeTTa specializes equations while modules are loaded, so this sequence is
;; part of the runtime implementation even though the modules are internal.
!(import! &self (library lib_roman))
!(import! &self (library lib_spaces))
!(import! &self (library lib_import))

!(import! &self core/types)
!(import! &self core/logic_config)
!(import! &self core/formulas/distributions)
!(import! &self core/formulas/fold_inverse)
!(import! &self core/formulas/compute_inverse)
!(import! &self core/formulas/truth_values)
!(import! &self compiler/compiler)

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
    ($helper-relative "prolog/heap_helpers.pl")
    ($heap-helper
      (let $_
         (callPredicate
            (Predicate
               (directory_file_path
                  $metta-dir $helper-relative $heap-helper)))
         $heap-helper))
    ($metta-parent
      (let $_
         (callPredicate
            (Predicate
               (file_directory_name
                  $metta-dir $metta-parent)))
         $metta-parent))
    ($parent-heap-helper
      (let $_
         (callPredicate
            (Predicate
               (directory_file_path
                  $metta-parent $helper-relative $parent-heap-helper)))
         $parent-heap-helper)))
   (if (== $heap-helper $parent-heap-helper)
      (import_prolog_functions_from_file
         $heap-helper (heap_pop))
      (superpose
         ((import_prolog_functions_from_file
             $heap-helper (heap_pop))
          (import_prolog_functions_from_file
             $parent-heap-helper (heap_pop))))))

!(import! &self runtime/values)
!(import! &self runtime/scheduling)
!(import! &self runtime/evidence)
!(import! &self runtime/base_rates)
!(import! &self runtime/forward/canonical)
!(import! &self runtime/forward/aggregates)
!(import! &self runtime/forward/engine)
!(import! &self runtime/knowledge_store)
!(import! &self runtime/ingest)
!(import! &self runtime/backward/metrics)
!(import! &self runtime/backward/proof_store)
!(import! &self runtime/backward/proof_merge)
!(import! &self runtime/backward/search)
!(import! &self runtime/backward/rule_matching)
!(import! &self runtime/backward/aggregates)
!(import! &self runtime/backward/engine)
!(import! &self runtime/query)
