(= (compiled-query-goal-head (goal $query)) $query)
(= (compiled-query-goal-head $compiled-query)
   (let (goal $query) (car-atom $compiled-query) $query))

(= (compiled-query-adds (goal $query)) ())
(= (compiled-query-adds $compiled-query) (cdr-atom $compiled-query))

(= (aggregate-compiled-query $kb $pattern)
   (internalize-proof-structure-list (collapse (mm2compileQuery $kb (: $prf $pattern $tvin)))))

(= (assert-space-atom-ref $space $expr)
   (let*
      (($term (Predicate (cons $space $expr)))
        ($_ (callPredicate (Predicate (assertz $term $ref)))))
      $ref))

(= (erase-clause-ref $ref) (callPredicate (Predicate (erase $ref))))

(= (track-temp-query-ref $ref) (add-atom &temp_query_ref (clause_ref $ref)))

(= (temp-add-prem $id $idx $prem)
   (let $key (forward-indexable-premise-key $prem)
      (progn
         (if (== $key ()) ()
            (let*
               (($ref (assert-space-atom-ref prem_index ($key $prem $id $idx)))
                 ($_track (track-temp-query-ref $ref)))
               ()))
         (+ $idx 1))))

(= (next-temp-query-id) (next-search-id bwd_tmp_ruleid))

(= (temp-add-to-kb $expr)
   (if (= $expr (rules ($args |- $ccls)))
      (let*
         (($id (next-temp-query-id))
           ($_1 (fold-flat (temp-add-prem $id) 0 $args))
           ($ccls-ref (assert-space-atom-ref ccls_index ($ccls $id)))
           ($_2 (track-temp-query-ref $ccls-ref))
           ($rule-ref (assert-space-atom-ref rules ($id $ccls $args)))
           ($_3 (track-temp-query-ref $rule-ref)))
         ())
      (progn
         (let $ref (assert-space-atom-ref &kb $expr)
            (track-temp-query-ref $ref)))))

(= (clear-temp-query-adds)
   (progn
      (collapse
         (match &temp_query_ref (clause_ref $ref)
            (progn
               (erase-clause-ref $ref)
               (remove-atom &temp_query_ref (clause_ref $ref)))))
      ()))

(= (inject-compiled-adds $adds) (if (= $adds ()) () (foreach-flat temp-add-to-kb $adds)))

(= (query $steps $kb $stmt)
   (let*
      (($compiled-query
           (internalize-proof-structure-list (collapse (mm2compileQuery $kb $stmt))))
        ($adds (compiled-query-adds $compiled-query))
        ($_clear-temp-before (clear-temp-query-adds))
        ($_ (inject-compiled-adds $adds))
        ($goal (compiled-query-goal-head $compiled-query))
        ($results (chainer $steps $goal))
        ($eres (map-flat externalize-proof-structure $results))
        ($pres (map-flat pretty $eres))
        ($_clear-temp-after (clear-temp-query-adds)))
      (superpose $pres)))
