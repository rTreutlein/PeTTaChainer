;; Public knowledge-ingestion transaction and its private normalization steps.
(: add-to-kb
   (-[nondet]-> RuntimeAddition  (| Bool (List $none))))
(= (add-to-kb $expr)
   (kb-add-expr live $expr))

;; Inheritance induction is installed per concrete query by the compiler. The
;; public registration call remains valid but has no KB-local work to perform.
(: register-inheritance-induction! (-[det]-> KB (List $none)))
(= (register-inheritance-induction! $_kb) ())

(: record-compiled-inheritance!
   (-[nondet]-> CompiledAddition  (| Bool (List $none))))
(= (record-compiled-inheritance! $expr)
   (let $_folds (case $expr ( ((: ($kbid $_c $_v) $_p $stmt $_t) (retire-base-rate-folds-matching! (brand KB $kbid) (brand Statement $stmt))) ($_o ())))
   (case $expr (
      ((: ($kbid $_ctx $_vars) $_prf (Inheritance $subj $concept) $_tv)
         (let*
            (($typed-kbid (brand KB $kbid))
             ($typed-subj (brand Statement $subj))
             ($_subject
                (if (is-var $subj) ()
                   (let*
                      (($_retire
                          (if (observed-inheritance-subject?
                                 $typed-kbid $typed-subj)
                             ()
                             (retire-changed-base-rate-universe!
                                $typed-kbid)))
                       ($_row
                          (add-space-atom! &inheritance_subject
                             (make-space-pair $kbid $subj))))
                      ()))))
            (record-inheritance-nodes!
               $typed-kbid $typed-subj (brand Statement $concept))))
      ((: ($kbid $_ctx $_vars) $_prf (Member $_obj $class) $_tv)
         (record-concept-node!
            (brand KB $kbid)
            (brand Statement $class)))
      ($_other ())))))

(: materialize-stmt-lambdas (-[nondet]-> $term  $term))
(= (materialize-stmt-lambdas $term)
   (if (== $term ()) ()
   (if (is-var $term) $term
      (if (is-expr $term)
         (if (== (car-atom $term) |->) (eval $term)
            (cons (materialize-stmt-lambdas (car-atom $term))
               (map-flat materialize-stmt-lambdas (cdr-atom $term))))
         $term))))

(: compileadd
   (-[nondet]-> KB AnnotatedStatement  CompiledAddition))
(= (compileadd $kb $stmt)
   (let*
      (($raw-atoms
          (collapse (mm2compile $kb (materialize-stmt-lambdas $stmt))))
        ($iatoms
           (list_to_set
              (map-flat internalize-runtime-addition $raw-atoms)))
        ($eatoms
           (the (List CompiledAddition)
              (map-flat externalize-proof-structure $iatoms)))
        ($_recorded
           (collapse
              (foreach-flat record-compiled-inheritance! $eatoms)))
        ($_ (collapse (foreach-flat add-to-kb $iatoms))))
      (superpose
         $eatoms)))
