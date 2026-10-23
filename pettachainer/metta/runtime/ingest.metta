;; Public knowledge-ingestion transaction and its private normalization steps.
(: add-to-kb (-[nondet]-> RuntimeAddition (| Bool (List $none))))
(= (add-to-kb $expr) (kb-add-expr live $expr))

;; Inheritance induction is installed per concrete query by the compiler. The
;; public registration call remains valid but has no KB-local work to perform.
(: register-inheritance-induction! (-[det]-> KB (List $none)))
(= (register-inheritance-induction! $_kb) ())

(: record-compiled-inheritance! (-[nondet]-> CompiledAddition Atom))
(= (record-compiled-inheritance! $expr)
   (case $expr (
      ((: ($kbid $_ctx $_vars) $_prf (Inheritance $subj $concept) $_tv)
         (let*
            (($typed-kbid (brand KB $kbid))
             ($typed-subj (brand Statement $subj))
             ($_subject (record-kb-node! &inheritance_subject subject-node $typed-kbid $typed-subj)))
            (record-inheritance-nodes! $typed-kbid $typed-subj (brand Statement $concept))))
      ((: ($kbid $_ctx $_vars) $_prf (Member $_obj $class) $_tv)
         (record-kb-node! &concept_node concept-node (brand KB $kbid) (brand Statement $class)))
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

(: compileadd (-[nondet]-> KB AnnotatedStatement CompiledAddition))
(= (compileadd $kb $stmt)
   (let*
      (($source (materialize-stmt-lambdas $stmt))
       ($_valid (validate-ingestion! $kb $source))
       ($iatoms (list_to_set (collapse (mm2compile $kb $source))))
        ($_functional (functional-check-additions! $kb $iatoms))
        ($_identities (proof-identities-free! $iatoms))
        ($eatoms (the (List CompiledAddition) (map-flat externalize-proof-structure $iatoms)))
        ($_recorded (collapse (foreach-flat record-compiled-inheritance! $eatoms)))
        ($_ (collapse (foreach-flat add-to-kb $iatoms)))
        ($_mined (map-flat (|-> ($hypothesis) (collapse (compileadd $kb $hypothesis))) (hm-observe! $kb $stmt)))
        ($_closed (map-flat (|-> ($fact) (collapse (compileadd $kb $fact))) (observed-gaps $kb $stmt))))
      (superpose $eatoms)))
