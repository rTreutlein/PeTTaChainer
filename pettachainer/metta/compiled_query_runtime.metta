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
(= (kb-add-atom live &kb (: ($kbid $_ctx $_vars) $prf (Member $obj $class) $tv))
   (progn
      (record-concept-node! $kbid $class)
      (add-atom &kb (: ($kbid $_ctx $_vars) $prf (Member $obj $class) $tv))))
(= (kb-add-atom live $space $expr) (add-atom $space $expr))
(= (kb-add-atom temp $space $expr) (track-temp-query-ref (assert-space-atom-ref $space $expr)))

(= (kb-add-prem $backend $id $idx $prem)
   (let $key (forward-indexable-premise-key $prem)
      (progn (if (== $key ()) () (kb-add-atom $backend prem_index ($key $prem $id $idx))) (+ $idx 1))))

(= (kb-add-ccl-head-index $backend $id $ccls)
   (let $key (forward-indexable-premise-key $ccls)
      (if (== $key ()) () (kb-add-atom $backend ccls_head_index ($key $id)))))

;; Cache entries carry the finish mode that produced them. User-provided base
;; rates are stored with mode `any` so they override every fold mode, while a
;; computed entry only applies to the mode that produced it -- otherwise a
;; weighted fold and a plain base-rate fold over the same pattern would alias to
;; one cached value.
(= (base-rate-entry-kbid (base-rate $kbid $_pattern $_tv $_source $_mode)) $kbid)

;; All entries whose stored pattern matches, ignoring finish mode. Used for
;; user-override checks, inspection, and removal/invalidation.
(= (base-rate-cache-entries $kbid $pattern)
   (collapse
      (match &base_rate_cache (base-rate $kbid $stored $tv $source $mode)
         (if (=alpha $stored $pattern) (base-rate $kbid $stored $tv $source $mode) (empty)))))

;; Entries usable by a fold running in finish mode $mode: user entries (mode
;; `any`) plus computed entries produced by the same mode.
(= (base-rate-cache-entries-for-mode $kbid $pattern $mode)
   (collapse
      (match &base_rate_cache (base-rate $kbid $stored $tv $source $emode)
         (if (and (=alpha $stored $pattern) (or (== $emode any) (== $emode $mode)))
            (base-rate $kbid $stored $tv $source $emode)
            (empty)))))

(= (base-rate-cache-remove-entry! $entry) (remove-atom &base_rate_cache $entry))

(= (base-rate-cache-remove! $kbid $pattern)
   (let $_ (foreach-flat base-rate-cache-remove-entry! (base-rate-cache-entries $kbid $pattern)) ()))

;; Remove only the computed entry for one (kbid, pattern, mode), leaving other
;; modes' computed entries and any user override untouched.
(= (base-rate-cache-remove-computed! $kbid $pattern $mode)
   (let $_
      (foreach-flat base-rate-cache-remove-entry!
         (collapse
            (match &base_rate_cache (base-rate $kbid $stored $tv computed $mode)
               (if (=alpha $stored $pattern) (base-rate $kbid $stored $tv computed $mode) (empty)))))
      ()))

(= (cached-base-rate $kbid $pattern)
   (let $entries (base-rate-cache-entries $kbid $pattern)
      (if (== $entries ()) ()
         (let (base-rate $_kbid $_stored $tv $_source $_mode) (car-atom $entries) ($tv)))))

(= (base-rate-user-set? $kbid $pattern)
   (let $entries (base-rate-cache-entries $kbid $pattern)
      (if (== $entries ()) false
         (let (base-rate $_kbid $_stored $_tv $source $_mode) (car-atom $entries) (== $source user)))))

(= (set-base-rate $kbid $pattern $tv)
   (let*
      (($stored (copy_term $pattern))
       ($_old (base-rate-cache-remove! $kbid $pattern))
       ($_new (add-atom &base_rate_cache (base-rate $kbid $stored $tv user any))))
      ()))

(= (clear-base-rate $kbid $pattern) (base-rate-cache-remove! $kbid $pattern))

(= (universe-size-entries $kbid)
   (collapse
      (match &universe_size (universe-size $kbid $n)
         (universe-size $kbid $n))))

(= (universe-size-remove-entry! $entry) (remove-atom &universe_size $entry))

(= (clear-universe-size $kbid)
   (let $_ (foreach-flat universe-size-remove-entry! (universe-size-entries $kbid)) ()))

(= (set-universe-size $kbid $n)
   (let*
      (($_old (clear-universe-size $kbid))
       ($_new (add-atom &universe_size (universe-size $kbid $n))))
      ()))

(= (kb-universe-size $kbid)
   (let $entries (universe-size-entries $kbid)
      (if (== $entries ()) no-universe-size
         (let (universe-size $_kbid $n) (car-atom $entries) $n))))

(= (store-computed-base-rate! $kbid $pattern $tv $mode)
   (if (base-rate-user-set? $kbid $pattern) ()
      (let*
         (($stored (copy_term $pattern))
          ($_old (base-rate-cache-remove-computed! $kbid $pattern $mode))
          ($_new (add-atom &base_rate_cache (base-rate $kbid $stored $tv computed $mode))))
         ())))

(= (invalidate-computed-base-rates! $kbid)
   (let*
      (($entries
          (collapse
             (match &base_rate_cache (base-rate $kbid $stored $tv computed $mode)
                (base-rate $kbid $stored $tv computed $mode))))
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

(= (member-consequent-tv $kbid $obj $concept)
   (let $hits
      (collapse
         (match &kb ((Member $obj $concept) ($kbid $_ctx $_vars) $_prf $tv) $tv))
      (if (== $hits ()) no-evidence (car-atom $hits))))

(= (member-inheritance-acc $_kbid $_concept $acc ()) $acc)
(= (member-inheritance-acc $kbid $concept $acc (cons (member-ant $obj $atv) $rest))
   (let $btv (member-consequent-tv $kbid $obj $concept)
      (member-inheritance-acc
         $kbid
         $concept
         (WeightedBaseRateAcc $acc (WeightedTv $atv $btv))
         $rest)))

(= (member-inheritance-tv $kbid $ev)
   (let $universe-size (kb-universe-size $kbid)
      (if (== $universe-size no-universe-size)
         (WeightedCountBaseRateTv $ev)
         (WeightedUniverseBaseRateTv $universe-size $ev))))

(= (MemberInheritanceFormula $kbid $subj $concept)
   (let $ants
      (collapse
         (match &kb ((Member $obj $subj) ($kbid $_ctx $_vars) $_prf $atv)
            (member-ant $obj $atv)))
      (if (== $ants ()) (empty)
         (member-inheritance-tv
            $kbid
            (member-inheritance-acc
               $kbid
               $concept
               (BaseRateEvidence 0.0 0.0)
               $ants)))))

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

(= (run-compiled-query $steps (compiled-query $goal $adds))
   (let*
      (($_clear-temp-before (clear-temp-query-adds))
        ($_ (inject-compiled-adds $adds))
        ($results (chainer $steps $goal))
        ($eres (map-flat externalize-proof-structure $results))
        ($pres (map-flat pretty $eres))
        ($_clear-temp-after (clear-temp-query-adds)))
      $pres))

(= (run-compiled-query-materialize $steps (compiled-query $goal $adds))
   (let*
      (($_clear-temp-before (clear-temp-query-adds))
        ($_ (inject-compiled-adds $adds))
        ($results (chainer-materialize $steps $goal))
        ($eres (map-flat externalize-proof-structure $results))
        ($pres (map-flat pretty $eres))
        ($_clear-temp-after (clear-temp-query-adds)))
      $pres))

(= (query $steps $kb $stmt)
   (let $pres
      (fold-flat append () (map-flat (run-compiled-query $steps) (collapse (mm2compileQuery $kb $stmt))))
      (superpose
         $pres)))

(= (query-materialize $steps $kb $stmt)
   (let $pres
      (fold-flat append () (map-flat (run-compiled-query-materialize $steps) (collapse (mm2compileQuery $kb $stmt))))
      (superpose
         $pres)))
