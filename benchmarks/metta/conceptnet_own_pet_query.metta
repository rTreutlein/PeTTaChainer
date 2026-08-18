;; Expensive end-to-end ConceptNet benchmark adapted from the original
;; scratch/metta/x.metta probe.
;;
;; Run through benchmarks/metta/run_conceptnet_own_pet_query.sh. The runner provides
;; the local .conceptnet_export link without baking a machine-specific CNet
;; path into this file.
!(import! &self ../../pettachainer/metta/petta_chainer)
!(import! &self (library lib_datetime))
!(static-import! &self .conceptnet_export/rules_dump)

;; This is the KB identifier pinned by cnet load_pln_dump for every regenerated export.
;; If a regenerated export changes it, update these call sites and the runner's
;; non-empty-result validation together.

!(compileadd kbconceptnet
   (: max_dog (Dog max) (STV 1.0 1.0)))
!(compileadd kbconceptnet
   (: ann_dog (Dog ann) (STV 1.0 1.0)))
!(compileadd kbconceptnet
   (: i_have_max (Have (i max)) (STV 1.0 1.0)))
!(compileadd kbconceptnet
   (: i_have_ann (Have (i ann)) (STV 1.0 1.0)))

!(let*
   (($start (now))
    ($results
      (collapse
         (query 100 kbconceptnet
            (: $_proof (And (Own (i $_pet)) (Pet $_pet)) $_tv))))
    ($finish (now)))
   (println!
      (CONCEPTNET_OWN_PET_RESULT_COUNT
         (length $results)
         RESULTS
         $results
         SECONDS
         (- $finish $start)
         CLOCK
         wall)))
