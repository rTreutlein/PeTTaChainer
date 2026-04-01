(= (aggregate-compiled-query $kb $pattern)
   (mm2compileQueryInternal $kb (: $prf $pattern $tvin)))

(= (assert-space-atom-ref $space $expr)
   (let*
      (($term (Predicate (cons $space $expr)))
        ($_ (callPredicate (Predicate (assertz $term $ref)))))
      $ref))

(= (erase-clause-ref $ref) (callPredicate (Predicate (erase $ref))))

(= (track-temp-query-ref $ref) (add-atom &temp_query_ref (clause_ref $ref)))

(= (kb-add-atom live $space $expr) (add-atom $space $expr))
(= (kb-add-atom temp $space $expr)
   (track-temp-query-ref (assert-space-atom-ref $space $expr)))

(= (kb-next-rule-id live) (next-search-id ruleid))
(= (kb-next-rule-id temp) (next-search-id bwd_tmp_ruleid))

(= (kb-after-add-rule live $args $ccls) (forward-register-added-rule $args $ccls))
(= (kb-after-add-rule temp $_args $_ccls) ())

(= (kb-after-add-expr live $expr) (forward-register-added-expr $expr))
(= (kb-after-add-expr temp $_expr) ())

(= (kb-add-prem $backend $id $idx $prem)
   (let $key (forward-indexable-premise-key $prem)
      (progn
         (if (== $key ()) () (kb-add-atom $backend prem_index ($key $prem $id $idx)))
         (+ $idx 1))))

(= (kb-add-expr $backend $expr)
   (if (= $expr (rules ($args |- $ccls)))
      (let*
         (($id (kb-next-rule-id $backend))
           ($_1 (fold-flat (kb-add-prem $backend $id) 0 $args))
           ($_2 (kb-add-atom $backend ccls_index ($ccls $id)))
           ($_3 (kb-add-atom $backend rules ($id $ccls $args)))
           ($_4 (kb-after-add-rule $backend $args $ccls)))
         ())
      (progn (kb-add-atom $backend &kb $expr) (kb-after-add-expr $backend $expr))))

(= (temp-add-to-kb $expr) (kb-add-expr temp $expr))

(= (clear-temp-query-adds)
   (progn
      (collapse
         (match &temp_query_ref (clause_ref $ref)
            (progn
               (erase-clause-ref $ref)
               (remove-atom &temp_query_ref (clause_ref $ref)))))
      ()))

(= (inject-compiled-adds $adds) (if (= $adds ()) () (foreach-flat (kb-add-expr temp) $adds)))

(= (query $steps $kb $stmt)
   (let*
      (((compiled-query $goal $adds) (mm2compileQueryInternal $kb $stmt))
        ($_clear-temp-before (clear-temp-query-adds))
        ($_ (inject-compiled-adds $adds))
        ($results (chainer $steps $goal))
        ($eres (map-flat externalize-proof-structure $results))
        ($pres (map-flat pretty $eres))
        ($_clear-temp-after (clear-temp-query-adds)))
      (superpose $pres)))
