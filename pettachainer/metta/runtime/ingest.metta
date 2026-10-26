;; Public knowledge-ingestion transaction and its private normalization steps.
(: add-to-kb (-[nondet]-> RuntimeAddition (| Bool (List $none))))
(= (add-to-kb $expr) (kb-add-expr live $expr))

;; A class link (Inheritance A B) is the implication (A $x) -> (B $x), whose
;; instances its queries fold. The public registration call remains valid but
;; has no KB-local work to perform.
(: register-inheritance-induction! (-[det]-> KB (List $none)))
(= (register-inheritance-induction! $_kb) ())

(: materialize-stmt-lambdas (-[nondet]-> $term  $term))
(= (materialize-stmt-lambdas $term)
   (if (== $term ()) ()
   (if (is-var $term) $term
      (if (is-expr $term)
         (if (== (car-atom $term) |->) (eval $term)
            (cons (materialize-stmt-lambdas (car-atom $term))
               (map-flat materialize-stmt-lambdas (cdr-atom $term))))
         $term))))

(: compileadd (-[nondet]-> KB AnnotatedStatement CompiledAddition))
(= (compileadd $kb $stmt)
   (let*
      (($source (member-canon (materialize-stmt-lambdas $stmt)))
       ($_valid (validate-ingestion! $kb $source))
       ($_heads (source-heads-free! $kb $source))
       ($iatoms (list_to_set (collapse (mm2compile $kb $source))))
        ($_functional (functional-check-additions! $kb $iatoms))
        ($_identities (proof-identities-free! $iatoms))
        ($_sorts (record-source-sorts! $kb $source))
        ($_recorded-heads (record-source-heads! $kb $source))
        ($eatoms (the (List CompiledAddition) (map-flat externalize-proof-structure $iatoms)))
        ($_ (collapse (foreach-flat add-to-kb $iatoms)))
        ($_mined (map-flat (|-> ($hypothesis) (collapse (compileadd $kb $hypothesis))) (hm-observe! $kb $source)))
        ($_closed (map-flat (|-> ($fact) (collapse (compileadd $kb $fact))) (observed-gaps $kb $source))))
      (superpose $eatoms)))
