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

(: add-to-kb ($compiled-expression -[nondet]-> (| Bool (List $none))))
(= (add-to-kb $expr) (kb-add-expr live $expr))

;; Inheritance induction is installed per concrete query by the compiler. The
;; public registration call remains valid but has no KB-local work to perform.
(: register-inheritance-induction! (-> $kb (List $none)))
(= (register-inheritance-induction! $_kb) ())

(: record-compiled-inheritance-subject!
   ($compiled-expression -[nondet]-> (| Bool (List $none))))
(= (record-compiled-inheritance-subject! $expr)
   (case $expr (
      ((: ($kbid $_ctx $_vars) $_prf (Inheritance $subj $_concept) $_tv)
         (if (is-var $subj) () (add-atom &inheritance_subject ($kbid $subj))))
      ($_other ()))))

(: record-compiled-inheritance-concepts!
   ($compiled-expression -[nondet]-> (| Bool (List $none))))
(= (record-compiled-inheritance-concepts! $expr)
   (case $expr (
      ((: ($kbid $_ctx $_vars) $_prf (Inheritance $subj $concept) $_tv)
         (record-inheritance-nodes! $kbid $subj $concept))
      ((: ($kbid $_ctx $_vars) $_prf (Member $_obj $class) $_tv)
         (record-concept-node! $kbid $class))
      ($_other ()))))

(: map-flat-nondet
   (($input -[nondet]-> $output) (List $input)
      -[nondet]-> (List $output)))
(= (map-flat-nondet $_f ()) ())
(= (map-flat-nondet $f (cons $x $xs))
   (cons ($f $x) (map-flat-nondet $f $xs)))

(: foreach-flat-nondet
   (($input -[nondet]-> $effect) (List $input)
      -[nondet]-> (List $none)))
(= (foreach-flat-nondet $_f ()) ())
(= (foreach-flat-nondet $f (cons $x $xs))
   (progn ($f $x) (foreach-flat-nondet $f $xs)))

(: materialize-stmt-lambdas ($term -[nondet]-> $term))
(= (materialize-stmt-lambdas $term)
   (if (is-var $term) $term
      (if (is-expr $term)
         (if (== (car-atom $term) |->) (eval $term)
            (cons (materialize-stmt-lambdas (car-atom $term))
               (map-flat-nondet materialize-stmt-lambdas (cdr-atom $term))))
         $term)))

(: compileadd ($kb AnnotatedStatement -[nondet]-> $compiled-expression))
(= (compileadd $kb $stmt)
   (let*
      (($stmt1 (materialize-stmt-lambdas $stmt))
        ($atoms (collapse (mm2compile $kb $stmt1)))
        ($iatoms (list_to_set (map-flat internalize-proof-structure-any $atoms)))
        ($eatoms (map-flat externalize-proof-structure $iatoms))
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
