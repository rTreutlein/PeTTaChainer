;; Expensive end-to-end ConceptNet benchmark adapted from the original
;; pettachainer/metta/x.metta scratch probe.
;;
;; Run through benchmarks/run_conceptnet_own_pet_query.sh. The runner provides
;; the local .conceptnet_export link without baking a machine-specific CNet
;; path into this file. This stays beside petta_chainer.metta so its nested
;; module imports work with both the old and current PeTTa import resolvers.
!(import! &self petta_chainer)
!(static-import! &self .conceptnet_export/rules_dump)

(: current-time (-> Number))

;; This is the KB identifier contained in the current full ConceptNet export.
;; If a regenerated export changes it, update these call sites and the runner's
;; non-empty-result validation together.

!(compileadd kb5b10000f8f9f4f0dbd120f99aa0f43ce
   (: max_dog (Dog max) (STV 1.0 1.0)))
!(compileadd kb5b10000f8f9f4f0dbd120f99aa0f43ce
   (: ann_dog (Dog ann) (STV 1.0 1.0)))
!(compileadd kb5b10000f8f9f4f0dbd120f99aa0f43ce
   (: i_have_max (Have (i max)) (STV 1.0 1.0)))
!(compileadd kb5b10000f8f9f4f0dbd120f99aa0f43ce
   (: i_have_ann (Have (i ann)) (STV 1.0 1.0)))

!(let*
   (($start (current-time))
    ($results
       (collapse
          (query 10 kb5b10000f8f9f4f0dbd120f99aa0f43ce
             (: $_proof (And (Own (i $_pet)) (Pet $_pet)) $_tv))))
    ($finish (current-time)))
   (println!
      (CONCEPTNET_OWN_PET_RESULT_COUNT
         (length $results)
         RESULTS
         $results
         SECONDS
         (- $finish $start))))
