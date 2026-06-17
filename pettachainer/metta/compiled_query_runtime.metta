(= (assert-space-atom-ref $space $expr)
   (let*
      (($term (Predicate (cons $space $expr)))
        ($_ (callPredicate (Predicate (assertz $term $ref)))))
      $ref))

(= (erase-clause-ref $ref) (callPredicate (Predicate (erase $ref))))

(= (track-temp-query-ref $ref) (add-atom &temp_query_ref (clause_ref $ref)))

(= (record-concept-node! $kbid $node)
   (if (is-var $node) ()
      (add-atom &concept_node ($kbid $node))))

(= (record-inheritance-nodes! $kbid $subj $concept)
   (progn
      (record-concept-node! $kbid $subj)
      (record-concept-node! $kbid $concept)))

(= (kb-add-atom live &kb (: ($kbid $_ctx $_vars) $prf (Inheritance $subj $concept) $tv))
   (progn
      (if (is-var $subj) () (add-atom &inheritance_subject ($kbid $subj)))
      (record-inheritance-nodes! $kbid $subj $concept)
      (add-atom &kb (: ($kbid $_ctx $_vars) $prf (Inheritance $subj $concept) $tv))))
(= (kb-add-atom live $space $expr) (add-atom $space $expr))
(= (kb-add-atom temp $space $expr) (track-temp-query-ref (assert-space-atom-ref $space $expr)))

(= (kb-add-prem $backend $id $idx $prem)
   (let $key (forward-indexable-premise-key $prem)
      (progn (if (== $key ()) () (kb-add-atom $backend prem_index ($key $prem $id $idx))) (+ $idx 1))))

(= (kb-add-ccl-head-index $backend $id $ccls)
   (let $key (forward-indexable-premise-key $ccls)
      (if (== $key ()) () (kb-add-atom $backend ccls_head_index ($key $id)))))

(= (base-rate-entry-kbid (base-rate $kbid $_pattern $_tv $_source)) $kbid)

(= (base-rate-cache-entries $kbid $pattern)
   (collapse
      (match &base_rate_cache (base-rate $kbid $stored $tv $source)
         (if (=alpha $stored $pattern) (base-rate $kbid $stored $tv $source) (empty)))))

(= (base-rate-cache-remove-entry! $entry) (remove-atom &base_rate_cache $entry))

(= (base-rate-cache-remove! $kbid $pattern)
   (let $_ (foreach-flat base-rate-cache-remove-entry! (base-rate-cache-entries $kbid $pattern)) ()))

(= (cached-base-rate $kbid $pattern)
   (let $entries (base-rate-cache-entries $kbid $pattern)
      (if (== $entries ()) ()
         (let (base-rate $_kbid $_stored $tv $_source) (car-atom $entries) ($tv)))))

(= (base-rate-user-set? $kbid $pattern)
   (let $entries (base-rate-cache-entries $kbid $pattern)
      (if (== $entries ()) false
         (let (base-rate $_kbid $_stored $_tv $source) (car-atom $entries) (== $source user)))))

(= (set-base-rate $kbid $pattern $tv)
   (let*
      (($stored (copy_term $pattern))
       ($_old (base-rate-cache-remove! $kbid $pattern))
       ($_new (add-atom &base_rate_cache (base-rate $kbid $stored $tv user))))
      ()))

(= (clear-base-rate $kbid $pattern) (base-rate-cache-remove! $kbid $pattern))

(= (store-computed-base-rate! $kbid $pattern $tv)
   (if (base-rate-user-set? $kbid $pattern) ()
      (let*
         (($stored (copy_term $pattern))
          ($_old (base-rate-cache-remove! $kbid $pattern))
          ($_new (add-atom &base_rate_cache (base-rate $kbid $stored $tv computed))))
         ())))

(= (invalidate-computed-base-rates! $kbid)
   (let*
      (($entries
          (collapse
             (match &base_rate_cache (base-rate $kbid $stored $tv computed)
                (base-rate $kbid $stored $tv computed))))
       ($_ (foreach-flat base-rate-cache-remove-entry! $entries)))
      ()))

(= (kb-expr-kbid $expr)
   (if (= $expr ($_type ($kbid $_ctx $_vars) $_prf $_tv)) $kbid ()))

(= (record-inheritance-subject! live (: ($kbid $_ctx $_vars) $_prf (Inheritance $subj $_concept) $_tv))
   (if (is-var $subj) ()
      (add-atom &inheritance_subject ($kbid $subj))))
(= (record-inheritance-subject! $_backend $_expr) ())

(= (record-inheritance-concepts! live (: ($kbid $_ctx $_vars) $_prf (Inheritance $subj $concept) $_tv))
   (record-inheritance-nodes! $kbid $subj $concept))
(= (record-inheritance-concepts! $_backend $_expr) ())

(= (observed-inheritance-subject? $kbid $subj)
   (not (== (collapse (once (match &inheritance_subject ($kbid $subj) true))) ())))

(= (known-concept-node? $kbid $node)
   (not (== (collapse (once (match &concept_node ($kbid $node) true))) ())))

(= (concept-nodes $kbid)
   (list_to_set (collapse (match &concept_node ($kbid $node) $node))))

(= (concept-node-prior-tv $kbid $node)
   (if (known-concept-node? $kbid $node)
      (let $n (list-len (concept-nodes $kbid))
         (if (<= $n 0) no-evidence (STV (/ 1.0 $n) (count-confidence $n))))
      no-evidence))

(= (ConceptNodePriorFormula $kbid $node) (concept-node-prior-tv $kbid $node))

(= (inheritance-subjects $kbid)
   (list_to_set (collapse (match &inheritance_subject ($kbid $subj) $subj))))

(= (inheritance-subject-prior-tv $kbid $subj)
   (if (observed-inheritance-subject? $kbid $subj)
      (let $n (list-len (inheritance-subjects $kbid))
         (if (<= $n 0) no-evidence (STV (/ 1.0 $n) 1.0)))
      no-evidence))

(= (kb-add-expr $backend $expr)
   (if (= $expr (rules ($args |- $ccls)))
      (let*
         (($id (if (== $backend live) (next-search-id ruleid) (next-search-id bwd_tmp_ruleid)))
           ($_1 (fold-flat (kb-add-prem $backend $id) 0 $args))
           ($_2 (kb-add-atom $backend ccls_index ($ccls $id)))
           ($_3 (kb-add-ccl-head-index $backend $id $ccls))
           ($_4 (kb-add-atom $backend rules ($id $ccls $args)))
           ($_5 (if (== $backend live)
                   (progn
                      (mark-forward-agenda-dirty $ccls)
                      (invalidate-computed-base-rates! (kb-expr-kbid $ccls)))
                   ())))
         ())
      (progn
         (kb-add-atom $backend &kb $expr)
         (record-inheritance-subject! $backend $expr)
         (if (== $backend live)
            (progn
               (mark-forward-agenda-dirty $expr)
               (invalidate-computed-base-rates! (kb-expr-kbid $expr)))
            ()))))

(= (clear-temp-query-adds)
   (progn
      (collapse
         (match &temp_query_ref (clause_ref $ref)
            (progn (erase-clause-ref $ref) (remove-atom &temp_query_ref (clause_ref $ref)))))
      ()))

(= (inject-compiled-adds $adds) (if (= $adds ()) () (foreach-flat (kb-add-expr temp) $adds)))

(= (query $steps $kb $stmt)
   (let*
      (((compiled-query $goal $adds) (mm2compileQuery $kb $stmt))
        ($_clear-temp-before (clear-temp-query-adds))
        ($_ (inject-compiled-adds $adds))
        ($results (chainer $steps $goal))
        ($eres (map-flat externalize-proof-structure $results))
        ($pres (map-flat pretty $eres))
        ($_clear-temp-after (clear-temp-query-adds)))
      (superpose
         $pres)))

(= (query-materialize $steps $kb $stmt)
   (let*
      (((compiled-query $goal $adds) (mm2compileQuery $kb $stmt))
        ($_clear-temp-before (clear-temp-query-adds))
        ($_ (inject-compiled-adds $adds))
        ($results (chainer-materialize $steps $goal))
        ($eres (map-flat externalize-proof-structure $results))
        ($pres (map-flat pretty $eres))
        ($_clear-temp-after (clear-temp-query-adds)))
      (superpose
         $pres)))
