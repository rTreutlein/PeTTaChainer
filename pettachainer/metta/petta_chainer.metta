!(import! &self (library lib_roman))
!(import! &self (library lib_spaces))
!(import! &self (library lib_import))
!(import! &self chainer_types)
!(import! &self logic_config)

!(import! &self dist_formulas)
!(import! &self fold_inverse)
!(import! &self tv_formulas)
!(import! &self compile)

!(use-module! heaps)

!(import_prolog_function (superpose (empty_heap add_to_heap get_from_heap heap_size)))
!(assertzPredicate (Predicate (arity empty_heap 1)))
!(assertzPredicate (Predicate (arity add_to_heap 4)))
!(assertzPredicate (Predicate (arity get_from_heap 4)))
!(assertzPredicate (Predicate (arity heap_size 2)))

;; Prolog helper imports resolve against the process CWD, while MeTTa imports
;; resolve against working_dir. Build the helper path from working_dir so the
;; public entry point behaves identically from the repo root, this directory,
;; Python, and benchmark runners.
!(let*
   (($metta-dir
      (let $_
         (callPredicate
            (Predicate (working_dir $metta-dir)))
         $metta-dir))
    ($heap-helper
      (let $_
         (callPredicate
            (Predicate
               (directory_file_path
                  $metta-dir "heap_helpers.pl" $heap-helper)))
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
                  $metta-parent
                  "heap_helpers.pl"
                  $parent-heap-helper)))
         $parent-heap-helper)))
   (if (== $heap-helper $parent-heap-helper)
      (import_prolog_functions_from_file
         $heap-helper (heap_pop))
      (superpose
         ((import_prolog_functions_from_file
             $heap-helper (heap_pop))
          (import_prolog_functions_from_file
             $parent-heap-helper (heap_pop))))))

!(import! &self chainer_utils)
!(import! &self forward_chainer)
!(import! &self compiled_query_runtime)
!(import! &self backward_proof_store)
!(import! &self backward_chainer)
!(import! &self query_runtime)

(: add-to-kb
   (-[nondet]-> RuntimeAddition  (| Bool (List $none))))
(= (add-to-kb $expr) (kb-add-expr live $expr))

;; Inheritance induction is installed per concrete query by the compiler. The
;; public registration call remains valid but has no KB-local work to perform.
(: register-inheritance-induction! (-[det]-> KB (List $none)))
(= (register-inheritance-induction! $_kb) ())

(: record-compiled-inheritance-subject!
   (-[nondet]-> CompiledAddition  (| Bool (List $none))))
(= (record-compiled-inheritance-subject! $expr)
   (case $expr (
      ((: ($kbid $_ctx $_vars) $_prf (Inheritance $subj $_concept) $_tv)
         (if (is-var $subj) ()
            (let $row
               (make-space-pair $kbid $subj)
               (add-space-atom! &inheritance_subject $row))))
      ($_other ()))))

(: record-compiled-inheritance-concepts!
   (-[nondet]-> CompiledAddition  (| Bool (List $none))))
(= (record-compiled-inheritance-concepts! $expr)
   (case $expr (
      ((: ($kbid $_ctx $_vars) $_prf (Inheritance $subj $concept) $_tv)
         (record-inheritance-nodes!
            (brand KB $kbid)
            (brand Statement $subj)
            (brand Statement $concept)))
      ((: ($kbid $_ctx $_vars) $_prf (Member $_obj $class) $_tv)
         (record-concept-node!
            (brand KB $kbid)
            (brand Statement $class)))
      ($_other ()))))

(: materialize-stmt-lambdas (-[nondet]-> $term  $term))
(= (materialize-stmt-lambdas $term)
   (if (== $term ()) ()
   (if (is-var $term) $term
      (if (is-expr $term)
         (if (== (car-atom $term) |->) (eval $term)
            (cons (materialize-stmt-lambdas (car-atom $term))
               (map-flat materialize-stmt-lambdas (cdr-atom $term))))
         $term))))

(: internalize-runtime-addition
   (-[det]-> RuntimeAddition RuntimeAddition))
(= (internalize-runtime-addition $addition)
   (brand RuntimeAddition
      (internalize-proof-structure-any $addition)))

(: externalize-compiled-addition
   (-[nondet]-> RuntimeAddition CompiledAddition))
(= (externalize-compiled-addition $addition)
   (brand CompiledAddition
      (externalize-proof-structure $addition)))

(: compileadd
   (-[nondet]-> KB AnnotatedStatement  CompiledAddition))
(= (compileadd $kb $stmt)
   (let*
      (($stmt1 (materialize-stmt-lambdas $stmt))
        ($raw-atoms (collapse (mm2compile $kb $stmt1)))
        ($atoms $raw-atoms)
        ($iatoms
           (list_to_set
              (map-flat internalize-runtime-addition $atoms)))
        ($eatoms
           (map-flat externalize-compiled-addition $iatoms))
        ($_subjects
           (collapse
              (foreach-flat
                 record-compiled-inheritance-subject! $eatoms)))
        ($_concepts
           (collapse
              (foreach-flat
                 record-compiled-inheritance-concepts! $eatoms)))
        ($_ (collapse (foreach-flat add-to-kb $iatoms))))
      (superpose
         $eatoms)))

;; Re-export the public query signatures from the facade module.
(: query
   (-[nondet]-> Number KB AnnotatedStatement AnnotatedStatement))
(: query-materialize
   (-[nondet]-> Number KB AnnotatedStatement AnnotatedStatement))
