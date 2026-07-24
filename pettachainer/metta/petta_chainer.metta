!(import! &self (library lib_roman))
!(import! &self (library lib_spaces))
!(import! &self logic_config)

!(import! &self dist_formulas)
!(import! &self tv_formulas)
!(import! &self compile)

!(use-module! heaps)

!(import_prolog_function (superpose (empty_heap add_to_heap get_from_heap heap_size)))
!(assertzPredicate (Predicate (arity empty_heap 1)))
!(assertzPredicate (Predicate (arity add_to_heap 4)))
!(assertzPredicate (Predicate (arity get_from_heap 4)))
!(assertzPredicate (Predicate (arity heap_size 2)))

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
(: register-inheritance-induction! (-> KB (List $none)))
(= (register-inheritance-induction! $_kb) ())

(: record-compiled-inheritance-subject!
   (-[nondet]-> CompiledAddition  (| Bool (List $none))))
(= (record-compiled-inheritance-subject! $expr)
   (case $expr (
      ((: ($kbid $_ctx $_vars) $_prf (Inheritance $subj $_concept) $_tv)
         (if (is-var $subj) () (add-atom &inheritance_subject ($kbid $subj))))
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

(: map-flat-nondet
   (-[nondet]-> (-[nondet]-> $input  $output) (List $input)
       (List $output)))
(= (map-flat-nondet $_f ()) ())
(= (map-flat-nondet $f (cons $x $xs))
   (cons ($f $x) (map-flat-nondet $f $xs)))

(: foreach-flat-nondet
   (-[nondet]-> (-[nondet]-> $input  $effect) (List $input)
       (List $none)))
(= (foreach-flat-nondet $_f ()) ())
(= (foreach-flat-nondet $f (cons $x $xs))
   (progn ($f $x) (foreach-flat-nondet $f $xs)))

(: materialize-stmt-lambdas (-[nondet]-> $term  $term))
(= (materialize-stmt-lambdas $term)
   (if (is-var $term) $term
      (if (is-expr $term)
         (if (== (car-atom $term) |->) (eval $term)
            (cons (materialize-stmt-lambdas (car-atom $term))
               (map-flat-nondet materialize-stmt-lambdas (cdr-atom $term))))
         $term)))

(: internalize-runtime-addition
   (-> RuntimeAddition RuntimeAddition))
(= (internalize-runtime-addition $addition)
   (brand RuntimeAddition
      (internalize-proof-structure-any $addition)))

(: externalize-compiled-addition
   (-> RuntimeAddition CompiledAddition))
(= (externalize-compiled-addition $addition)
   (brand CompiledAddition
      (externalize-proof-structure $addition)))

(: compileadd
   (-[nondet]-> KB AnnotatedStatement  CompiledAddition))
(= (compileadd $kb $stmt)
   (let*
      (($stmt1 (materialize-stmt-lambdas $stmt))
        ($atoms (collapse (mm2compile $kb $stmt1)))
        ($iatoms
           (list_to_set
              (map-flat internalize-runtime-addition $atoms)))
        ($eatoms
           (map-flat externalize-compiled-addition $iatoms))
        ($_subjects
           (collapse
              (foreach-flat-nondet
                 record-compiled-inheritance-subject! $eatoms)))
        ($_concepts
           (collapse
              (foreach-flat-nondet
                 record-compiled-inheritance-concepts! $eatoms)))
        ($_ (collapse (foreach-flat-nondet add-to-kb $iatoms))))
      (superpose
         $eatoms)))
