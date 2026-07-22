;; Public query orchestration sits above the backward chainer.  Keeping these
;; wrappers out of compiled_query_runtime lets compilation/storage remain a
;; foundational dependency of both chainers.
(: run-compiled-query (Number CompiledQuery -[nondet]-> (List AnnotatedStatement)))
(= (run-compiled-query $steps (compiled-query $goal $adds))
   (let*
      (($_clear-temp-before (clear-temp-query-adds))
        ($_ (inject-compiled-adds $adds))
        ($results (chainer $steps $goal))
        ($eres (map-flat externalize-proof-structure $results))
        ($pres (map-flat pretty $eres))
        ($_clear-temp-after (clear-temp-query-adds)))
      $pres))

(: run-compiled-query-materialize
   (Number CompiledQuery -[nondet]-> (List AnnotatedStatement)))
(= (run-compiled-query-materialize $steps (compiled-query $goal $adds))
   (let*
      (($_clear-temp-before (clear-temp-query-adds))
        ($_ (inject-compiled-adds $adds))
        ($results (chainer-materialize $steps $goal))
        ($eres (map-flat externalize-proof-structure $results))
        ($pres (map-flat pretty $eres))
        ($_clear-temp-after (clear-temp-query-adds)))
      $pres))

(: append-annotated-statements
   (-> (List AnnotatedStatement) (List AnnotatedStatement)
       (List AnnotatedStatement)))
(= (append-annotated-statements $left $right)
   (append $left $right))

(: query (Number $kb AnnotatedStatement -[nondet]-> AnnotatedStatement))
(= (query $steps $kb $stmt)
   (let $pres
      (fold-flat append-annotated-statements ()
         (map-flat (run-compiled-query $steps)
            (collapse (mm2compileQuery $kb $stmt))))
      (superpose
         $pres)))

(: query-materialize (Number $kb AnnotatedStatement -[nondet]-> AnnotatedStatement))
(= (query-materialize $steps $kb $stmt)
   (let $pres
      (fold-flat append-annotated-statements ()
         (map-flat (run-compiled-query-materialize $steps)
            (collapse (mm2compileQuery $kb $stmt))))
      (superpose
         $pres)))
