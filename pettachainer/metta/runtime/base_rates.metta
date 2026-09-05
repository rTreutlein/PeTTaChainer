;; Shared base-rate caches, universe metadata, concept priors, and finalizers.
;; Base-rate cache operations are shared by forward chaining and the compiled
;; query runtime, so they must be available before either consumer is loaded.
(: base-rate-finish? (-[det]-> $finish Bool))
(= (base-rate-finish? $finish)
   (case $finish (
      (base-rate true)
      (weighted-base-rate true)
      (weighted-base-rate-with-prior true)
      ((weighted-base-rate-in-universe $_kbid) true)
      ((weighted-base-rate-with-prior-in-universe $_kbid) true)
      ((member-inheritance $_kbid) true)
      ($_other false))))

(: BaseRateAggregateKey Type)
(: base-rate-aggregate-key-value
   (-[det]-> KB Statement $mode BaseRateAggregateKey))
(: NoBaseRateAggregateKey Type)
(: no-base-rate-aggregate-key NoBaseRateAggregateKey)

(: base-rate-aggregate-key
   (-[det]-> $arguments
       (| BaseRateAggregateKey NoBaseRateAggregateKey)))
(= (base-rate-aggregate-key $args)
   (case $args (
      (($kbid $pattern $_extractor $_init $_fun $finish $_tv-mode)
         (if (base-rate-finish? $finish)
            (base-rate-aggregate-key-value
               (brand KB $kbid)
               (brand Statement $pattern)
               $finish)
            no-base-rate-aggregate-key))
      ($_other no-base-rate-aggregate-key))))


;; Base-rate fold goals register (key-hash key kb goal-key) once at spawn.
;; Their current snapshots are read through the ordinary result index.
(: register-base-rate-fold!
   (-[det]-> BaseRateAggregateKey ProofGoalKey (List $none)))
(= (register-base-rate-fold! $key $gkey)
   (let* (($lookup (index-hash $key))
          ($known
             (collapse
                (once
                   (match &base_rate_fold
                      ($lookup $stored-key $_kb $stored-gkey)
                      (if (=alpha $stored-key $key)
                         (if (=alpha $stored-gkey $gkey) true (empty))
                         (empty)))))))
      (if (== $known ())
         (case $key (
            ((base-rate-aggregate-key-value $kbid $_pattern $_mode)
               (let $_row
                  (add-space-atom! &base_rate_fold
                     (make-space-row4 $lookup $key $kbid $gkey))
                  ()))))
         ())))






(: base-rate-cache-entries (-[det]-> KB Statement (List BaseRateEntry)))
(= (base-rate-cache-entries $kbid $pattern)
   (collapse
      (match &base_rate_cache (base-rate $kbid $stored $tv $source $mode)
         (if (=alpha $stored $pattern)
            (base-rate $kbid $stored $tv $source $mode)
            (empty)))))

(: base-rate-cache-entries-for-mode
   (-[det]-> KB Statement $mode (List BaseRateEntry)))
(= (base-rate-cache-entries-for-mode $kbid $pattern $mode)
   (collapse
      (match &base_rate_cache (base-rate $kbid $stored $tv $source $emode)
         (if (and (=alpha $stored $pattern)
                  (or (== $emode any) (== $emode $mode)))
            (base-rate $kbid $stored $tv $source $emode)
            (empty)))))

(: base-rate-cache-remove-derived-entry!
   (-[det]-> BaseRateEntry (List $none)))
(= (base-rate-cache-remove-derived-entry!
      (base-rate $kbid $stored $tv $source $mode))
   (if (== $source user) ()
      (let $_removed
         (remove-atom &base_rate_cache
            (base-rate $kbid $stored $tv $source $mode))
         ())))

(: base-rate-cache-remove! (-[det]-> KB Statement (List $none)))
(= (base-rate-cache-remove! $kbid $pattern)
   (let $_
      (collapse
         (match &base_rate_cache (base-rate $kbid $stored $tv $source $mode)
            (if (=alpha $stored $pattern)
               (remove-atom &base_rate_cache
                  (base-rate $kbid $stored $tv $source $mode))
               (empty))))
      ()))

(: base-rate-entry-tv (-[det]-> BaseRateEntry TV))
(= (base-rate-entry-tv
      (base-rate $_kbid $_stored $tv $_source $_mode))
   $tv)

(: base-rate-entry-user? (-[det]-> BaseRateEntry Bool))
(= (base-rate-entry-user?
      (base-rate $_kbid $_stored $_tv $source $_mode))
   (== $source user))

(: base-rate-cache-user-present?
   (-[det]-> (List BaseRateEntry) Bool))
(= (base-rate-cache-user-present? ()) false)
(= (base-rate-cache-user-present? (cons $entry $rest))
   (if (base-rate-entry-user? $entry) true
      (base-rate-cache-user-present? $rest)))

(: base-rate-entry-source (-[det]-> BaseRateEntry BaseRateSource))
(= (base-rate-entry-source
      (base-rate $_kbid $_stored $_tv $source $_mode))
   $source)



(: matching-base-rate-cache-entries
   (-[det]-> KB Statement (List BaseRateEntry)))
(= (matching-base-rate-cache-entries $kbid $pattern)
   (collapse
      (match &base_rate_cache
         (base-rate $kbid $stored $tv $source $mode)
         (let*
            (($stored-copy (copy_term $stored))
             ($pattern-copy (copy_term $pattern))
             ($unifies
                (collapse
                   (let $stored-copy $pattern-copy true))))
            (if (== $unifies ()) (empty)
               (base-rate $kbid $stored $tv $source $mode))))))

(: base-rate-prior-factor (-[det]-> BaseRateEntry Number))
(= (base-rate-prior-factor
      (base-rate $_kbid $_stored $tv $_source $_entry-mode))
   ;; Keep a known-bad branch reachable after every more promising branch has
   ;; been exhausted; a zero score would prevent it from entering the agenda.
   (max 0.000001
      (* (case $tv (
            ((STV $strength $_confidence) $strength)
            ((CTV (STV $strength $_confidence) $_negative) $strength)
            (no-evidence 1.0)))
         (tv-confidence $tv))))

;; A missing rate receives the neutral scheduler-only exploration prior.
(: selected-base-rate-prior-factor
   (-[det]-> (List BaseRateEntry) Number))
(= (selected-base-rate-prior-factor ()) 0.5)
(= (selected-base-rate-prior-factor (cons $entry $rest))
   (if (== $rest ())
      (base-rate-prior-factor $entry)
      (min (base-rate-prior-factor $entry)
         (selected-base-rate-prior-factor $rest))))

(: premise-base-rate-prior
   (-[det]-> (| Goal (Statement KBContext Proof TV)) Number))
(= (premise-base-rate-prior $premise)
   (case $premise (
      ((CPU $_fun $_args $_result) 1.0)
      (($type ($kbid $_ctx $_vars) $_proof $_tv)
         (let $exact (base-rate-cache-entries $kbid $type)
            ;; Exact rates override generalized matches. Among ambiguous
            ;; generalized patterns, the minimum is deterministic and avoids
            ;; selecting an accidentally optimistic prior.
            (if (not (== $exact ()))
               (selected-base-rate-prior-factor $exact)
               (selected-base-rate-prior-factor
                  (matching-base-rate-cache-entries $kbid $type))))))))

(: premises-proof-success-prior
   (-[det]-> (List (| Goal (Statement KBContext Proof TV))) Number))
(= (premises-proof-success-prior ()) 1.0)
(= (premises-proof-success-prior (cons $premise $rest))
   (* (premise-base-rate-prior $premise)
      (premises-proof-success-prior $rest)))

(: cached-base-rate
   (-[nondet]-> KB Statement (List TV)))
(= (cached-base-rate $kbid $pattern)
   (case (base-rate-cache-entries $kbid $pattern) (
      (() ())
      ((cons $entry $_rest)
         (cons (base-rate-entry-tv $entry) ())))))

(: store-produced-base-rate!
   (-[det]-> KB Statement TV BaseRateSource $mode (List $none)))
(= (store-produced-base-rate! $kbid $pattern $tv $source $mode)
   (if (== $tv no-evidence) ()
      (let $entries (base-rate-cache-entries-for-mode $kbid $pattern $mode)
         (if (base-rate-cache-user-present? $entries)
            ()
            (let* (($stored (copy_term $pattern))
                   ($_old
                      (foreach-flat
                         base-rate-cache-remove-derived-entry! $entries))
                   ($_new
                      (add-atom &base_rate_cache
                         (base-rate $kbid $stored $tv $source $mode))))
               ())))))

(: remove-produced-base-rate!
   (-[det]-> KB Statement $mode (List $none)))
(= (remove-produced-base-rate! $kbid $pattern $mode)
   (let $_old
      (foreach-flat base-rate-cache-remove-derived-entry!
         (base-rate-cache-entries-for-mode $kbid $pattern $mode))
      ()))
(: invalidate-computed-base-rates! (-[det]-> KB (List $none)))
(= (invalidate-computed-base-rates! $kbid)
   (let*
      (($_computed
          (remove-atom &base_rate_cache
             (base-rate $kbid $_s1 $_tv1 computed $_m1)))
       ($_forward
          (remove-atom &base_rate_cache
             (base-rate $kbid $_s2 $_tv2 forward-approx $_m2))))
      ()))




(: inheritance-subjects (-[det]-> KB (List Statement)))
(= (inheritance-subjects $kbid)
   (list_to_set
      (collapse
         (match &inheritance_subject ($kbid $subj)
            (brand Statement $subj)))))

;; Concept metadata and aggregate finalizers are shared by both forward and
;; backward execution, so they must be available before the forward runtime.
(: record-concept-node! (-[det]-> KB Statement (| Bool (List $none))))
(= (record-concept-node! $kbid $node)
   (if (is-var $node) ()
      (once
         (add-space-atom! &concept_node (make-space-pair $kbid $node)))))

(: record-inheritance-nodes!
   (-[det]-> KB Statement Statement (| Bool (List $none))))
(= (record-inheritance-nodes! $kbid $subj $concept)
   (progn
      (record-concept-node! $kbid $subj)
      (record-concept-node! $kbid $concept)))

(: clear-concept-prior-confidence (-[det]-> KB (List $none)))
(= (clear-concept-prior-confidence $kbid)
   (let*
      (($_remove
          (remove-atom &concept_prior_confidence
             (concept-prior-confidence $kbid $_c)))
       ($_invalidate (invalidate-computed-base-rates! $kbid)))
      ()))

(: set-concept-prior-confidence (-[det]-> KB Number (List $none)))
(= (set-concept-prior-confidence $kbid $c)
   (let*
      (($_old (clear-concept-prior-confidence $kbid))
       ($_new
          (add-atom &concept_prior_confidence
             (concept-prior-confidence $kbid $c))))
      ()))

(: known-concept-node? (-[det]-> KB Statement Bool))
(= (known-concept-node? $kbid $node)
   (space-row-present? &concept_node ($kbid $node)))

(: concept-nodes (-[det]-> KB (List Statement)))
(= (concept-nodes $kbid)
   (list_to_set
      (collapse
         (match &concept_node ($kbid $node)
            (brand Statement $node)))))

(: concept-node-prior-tv
   (-[det]-> KB Statement OptionalSTV))
(= (concept-node-prior-tv $kbid $node)
   (if (known-concept-node? $kbid $node)
      (let $n (list-len (concept-nodes $kbid))
         (if (<= $n 0) no-evidence
            (STV (/ 1.0 $n)
               (chainer-first-or 0.000001
                  (collapse
                     (match &concept_prior_confidence
                        (concept-prior-confidence $kbid $c)
                        (stored-number $c)))))))
      no-evidence))

(: resolve-base-rate-prior
   (-[det]-> BaseRatePrior OptionalSTV))
(= (resolve-base-rate-prior (ConceptNodePriorRuntime $kbid $node))
   (concept-node-prior-tv
      (brand KB $kbid) (brand Statement $node)))
(= (resolve-base-rate-prior (STV $s $c)) (STV $s $c))
(= (resolve-base-rate-prior no-evidence) no-evidence)

(: member-inheritance-tv
   (-[det]-> KB BaseRateEvidenceState OptionalSTV))
(= (member-inheritance-tv $_kbid $ev) (WeightedCountBaseRateTv $ev))
