!(import! &self compile)

!(use-module! heaps)

!(import_prolog_function (superpose (empty_heap add_to_heap get_from_heap heap_size)))
!(assertzPredicate (Predicate (arity empty_heap 1)))
!(assertzPredicate (Predicate (arity add_to_heap 4)))
!(assertzPredicate (Predicate (arity get_from_heap 4)))
!(assertzPredicate (Predicate (arity heap_size 2)))

!(import! &self chainer_utils)
!(import! &self forward_chainer)
!(import! &self dist_formulas)
!(import! &self tv_formulas)
!(import! &self compiled_query_runtime)
!(import! &self backward_proof_store)
!(import! &self backward_chainer)

(= (add-to-kb $expr) (kb-add-expr live $expr))

!(import! &self inheritance_induction)

(= (record-compiled-inheritance-subject! (: ($kbid $_ctx $_vars) $_prf (Inheritance $subj $_concept) $_tv))
   (if (is-var $subj) ()
      (add-atom &inheritance_subject ($kbid $subj))))
(= (record-compiled-inheritance-subject! $_expr) ())

(= (materialize-stmt-lambdas $term)
   (if (is-var $term) $term
      (if (is-expr $term)
         (if (== (car-atom $term) |->) (eval $term)
            (cons (materialize-stmt-lambdas (car-atom $term))
               (map-flat materialize-stmt-lambdas (cdr-atom $term))))
         $term)))

(= (compileadd $kb $stmt)
   (let*
      (($stmt1 (materialize-stmt-lambdas $stmt))
        ($atoms (collapse (mm2compile $kb $stmt1)))
        ($iatoms (list_to_set (map-flat internalize-proof-structure $atoms)))
        ($eatoms (map-flat externalize-proof-structure $iatoms))
        ($_subjects (collapse (foreach-flat record-compiled-inheritance-subject! $eatoms)))
        ($_ (collapse (foreach-flat add-to-kb $iatoms))))
      (superpose
         $eatoms)))
