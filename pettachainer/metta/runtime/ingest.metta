;; Public knowledge-ingestion transaction and its private normalization steps.
(: add-to-kb
   (-[nondet]-> RuntimeAddition  (| Bool (List $none))))
(= (add-to-kb $expr)
   (kb-add-expr live $expr))

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
            (let* (($typed-kbid (brand KB $kbid))
                   ($typed-subj (brand Statement $subj))
                   ($known?
                      (observed-inheritance-subject?
                         $typed-kbid $typed-subj))
                   ($universe-identity
                      (inheritance-prior-universe-identity $typed-kbid))
                   ($tracked?
                      (aggregate-proof-identity-recorded?
                         $universe-identity))
                   ($row (make-space-pair $kbid $subj))
                   ($_subject
                      (add-space-atom! &inheritance_subject $row))
                   ($_refresh
                      (if (or $known? (not $tracked?)) ()
                         (let* (($_next
                                  (bump-aggregate-revision!
                                     $universe-identity))
                                ($_cache
                                  (invalidate-computed-base-rates!
                                     $typed-kbid)))
                            ()))))
               ())))
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
        ($_ (collapse (foreach-flat add-to-kb $iatoms)))
        ($_member-revisions
           (case $stmt1 (
              ((: $_proof (Inheritance $_subj $concept) $_tv)
                 (forward-bump-member-aggregate-revisions!
                    (brand KB $kb) (brand Term $concept)))
              ($_other ())))))
      (superpose
         $eatoms)))
