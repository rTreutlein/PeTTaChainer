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

(= (kb-add-prem $backend $id $idx $prem)
   (let $key (forward-indexable-premise-key $prem)
      (progn
         (if (== $key ()) () (kb-add-atom $backend prem_index ($key $prem $id $idx)))
         (+ $idx 1))))

(= (kb-add-expr $backend $expr)
   (if (= $expr (rules ($args |- $ccls)))
      (let*
         (($id (if (== $backend live) (next-search-id ruleid) (next-search-id bwd_tmp_ruleid)))
           ($_1 (fold-flat (kb-add-prem $backend $id) 0 $args))
           ($_2 (kb-add-atom $backend ccls_index ($ccls $id)))
           ($_3 (kb-add-atom $backend rules ($id $ccls $args)))
           ($_4 (if (== $backend live) (forward-register-added-rule $args $ccls) ())))
         ())
      (progn (kb-add-atom $backend &kb $expr) (if (== $backend live) (forward-register-added-expr $expr) ()))))

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
