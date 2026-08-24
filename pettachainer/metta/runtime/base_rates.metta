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

(: base-rate-cache-remove-entry!
   (-[det]-> BaseRateEntry Bool))
(= (base-rate-cache-remove-entry! $entry)
   (remove-atom &base_rate_cache $entry))

(: base-rate-cache-remove! (-[det]-> KB Statement (List $none)))
(= (base-rate-cache-remove! $kbid $pattern)
   (let $_
      (foreach-flat base-rate-cache-remove-entry!
         (base-rate-cache-entries $kbid $pattern))
      ()))

(: base-rate-cache-remove-derived!
   (-[det]-> KB Statement $mode (List $none)))
(= (base-rate-cache-remove-derived! $kbid $pattern $mode)
   (let $_
      (foreach-flat base-rate-cache-remove-entry!
         (collapse
            (match &base_rate_cache
               (base-rate $kbid $stored $tv $source $mode)
               (if (and (not (== $source user)) (=alpha $stored $pattern))
                  (base-rate $kbid $stored $tv $source $mode)
                  (empty)))))
      ()))

(: base-rate-entry-tv (-[det]-> BaseRateEntry TV))
(= (base-rate-entry-tv
      (base-rate $_kbid $_stored $tv $_source $_mode))
   $tv)

(: base-rate-entry-user? (-[det]-> BaseRateEntry Bool))
(= (base-rate-entry-user?
      (base-rate $_kbid $_stored $_tv $source $_mode))
   (== $source user))

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

(: base-rate-tv-strength (-[det]-> TV Number))
(= (base-rate-tv-strength $tv)
   (case $tv (
      ((STV $strength $_confidence) $strength)
      ((CTV (STV $strength $_confidence) $_negative) $strength)
      (no-evidence 1.0))))

(: unknown-premise-prior (-[det]-> Number))
(= (unknown-premise-prior) 0.5)

(: base-rate-prior-factor (-[det]-> BaseRateEntry Number))
(= (base-rate-prior-factor
      (base-rate $_kbid $_stored $tv $_source $_entry-mode))
   ;; Keep a known-bad branch reachable after every more promising branch has
   ;; been exhausted; a zero score would prevent it from entering the agenda.
   (max 0.000001
      (* (base-rate-tv-strength $tv) (tv-confidence $tv))))

(: selected-base-rate-prior-factor
   (-[det]-> (List BaseRateEntry) Number))
(= (selected-base-rate-prior-factor ()) (unknown-premise-prior))
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

(: base-rate-user-set? (-[det]-> KB Statement Bool))
(= (base-rate-user-set? $kbid $pattern)
   (case (base-rate-cache-entries $kbid $pattern) (
      (() false)
      ((cons $entry $_rest)
         (base-rate-entry-user? $entry)))))

(: store-computed-base-rate!
   (-[det]-> KB Statement TV $mode (List $none)))
(= (store-computed-base-rate! $kbid $pattern $tv $mode)
   (if (base-rate-user-set? $kbid $pattern) ()
      (let*
         (($stored (copy_term $pattern))
          ($_old (base-rate-cache-remove-derived! $kbid $pattern $mode))
          ($_new
             (add-atom &base_rate_cache
                (base-rate $kbid $stored $tv computed $mode))))
         ())))

(: store-forward-base-rate!
   (-[det]-> KB Statement TV $mode (List $none)))
(= (store-forward-base-rate! $kbid $pattern $tv $mode)
   (if (== $tv no-evidence) ()
      (if (base-rate-user-set? $kbid $pattern) ()
         (let*
            (($stored (copy_term $pattern))
             ($_old (base-rate-cache-remove-derived! $kbid $pattern $mode))
             ($_new
                (add-atom &base_rate_cache
                   (base-rate $kbid $stored $tv forward-approx $mode))))
            ()))))

(: invalidate-computed-base-rates! (-[det]-> KB (List $none)))
(= (invalidate-computed-base-rates! $kbid)
   (let*
      (($entries
          (collapse
             (match &base_rate_cache
                (base-rate $kbid $stored $tv $source $mode)
                (if (== $source user) (empty)
                   (base-rate $kbid $stored $tv $source $mode)))))
       ($_ (foreach-flat base-rate-cache-remove-entry! $entries)))
      ()))

(: universe-size-entries (-[det]-> KB (List UniverseSizeEntry)))
(= (universe-size-entries $kbid)
   (collapse
      (match &universe_size (universe-size $kbid $n)
         (universe-size $kbid $n))))

(: universe-size-remove-entry!
   (-[det]-> UniverseSizeEntry Bool))
(= (universe-size-remove-entry! $entry)
   (remove-atom &universe_size $entry))

(: clear-universe-size (-[det]-> KB (List $none)))
(= (clear-universe-size $kbid)
   (let*
      (($_remove
          (foreach-flat universe-size-remove-entry!
             (universe-size-entries $kbid)))
       ($_invalidate (invalidate-computed-base-rates! $kbid)))
      ()))

(: set-universe-size (-[det]-> KB Number (List $none)))
(= (set-universe-size $kbid $n)
   (let*
      (($_old (clear-universe-size $kbid))
       ($_new (add-atom &universe_size (universe-size $kbid $n)))
       ($_invalidate (invalidate-computed-base-rates! $kbid)))
      ()))

(: universe-size-entry-value (-[det]-> UniverseSizeEntry Number))
(= (universe-size-entry-value (universe-size $_kbid $n))
   $n)

(: kb-universe-size
   (-[det]-> KB (| Number UniverseSizeUnavailable)))
(= (kb-universe-size $kbid)
   (case (universe-size-entries $kbid) (
      (() no-universe-size)
      ((cons $entry $_rest)
         (universe-size-entry-value $entry)))))

;; Values recovered from the erased inheritance index are statements by the
;; index's construction invariant. Keep that boundary local so collapse can
;; retain the nominal element type without validating the whole result list.
(: statement-from-atom (-[det]-> Atom Statement))
(= (statement-from-atom $atom)
   (brand Statement $atom))

(: inheritance-subjects (-[det]-> KB (List Statement)))
(= (inheritance-subjects $kbid)
   (list_to_set
      (collapse
         (match &inheritance_subject ($kbid $subj)
            (statement-from-atom $subj)))))

;; Concept metadata and aggregate finalizers are shared by both forward and
;; backward execution, so they must be available before the forward runtime.
(: record-concept-node! (-[det]-> KB Statement (| Bool (List $none))))
(= (record-concept-node! $kbid $node)
   (if (is-var $node) ()
      (once
         (let $row
            (make-space-pair $kbid $node)
            (add-space-atom! &concept_node $row)))))

(: record-inheritance-nodes!
   (-[det]-> KB Statement Statement (| Bool (List $none))))
(= (record-inheritance-nodes! $kbid $subj $concept)
   (progn
      (record-concept-node! $kbid $subj)
      (record-concept-node! $kbid $concept)))

(: default-concept-prior-confidence (-[det]-> Number))
(= (default-concept-prior-confidence) 0.000001)

(: concept-prior-confidence-entries
   (-[det]-> KB (List ConceptPriorConfidence)))
(= (concept-prior-confidence-entries $kbid)
   (collapse
      (match &concept_prior_confidence
         (concept-prior-confidence $kbid $c)
         (concept-prior-confidence $kbid $c))))

(: concept-prior-confidence-remove-entry!
   (-[det]-> ConceptPriorConfidence Bool))
(= (concept-prior-confidence-remove-entry! $entry)
   (remove-atom &concept_prior_confidence $entry))

(: clear-concept-prior-confidence (-[det]-> KB (List $none)))
(= (clear-concept-prior-confidence $kbid)
   (let*
      (($_remove
          (foreach-flat concept-prior-confidence-remove-entry!
             (concept-prior-confidence-entries $kbid)))
       ($_invalidate (invalidate-computed-base-rates! $kbid)))
      ()))

(: set-concept-prior-confidence (-[det]-> KB Number (List $none)))
(= (set-concept-prior-confidence $kbid $c)
   (let*
      (($_old (clear-concept-prior-confidence $kbid))
       ($_new
          (add-atom &concept_prior_confidence
             (concept-prior-confidence $kbid $c)))
       ($_invalidate (invalidate-computed-base-rates! $kbid)))
      ()))

(: concept-prior-confidence-value
   (-[det]-> ConceptPriorConfidence Number))
(= (concept-prior-confidence-value
      (concept-prior-confidence $_kbid $c))
   $c)

(: kb-concept-prior-confidence (-[det]-> KB Number))
(= (kb-concept-prior-confidence $kbid)
   (case (concept-prior-confidence-entries $kbid) (
      (() (default-concept-prior-confidence))
      ((cons $entry $_rest)
         (concept-prior-confidence-value $entry)))))

(: known-concept-node? (-[det]-> KB Statement Bool))
(= (known-concept-node? $kbid $node)
   (not
      (== (collapse
             (once
                (match &concept_node ($kbid $node) true)))
          ())))

(: concept-nodes (-[det]-> KB (List Statement)))
(= (concept-nodes $kbid)
   (list_to_set
      (collapse
         (match &concept_node ($kbid $node)
            (statement-from-atom $node)))))

(: concept-node-prior-tv
   (-[det]-> KB Statement OptionalSTV))
(= (concept-node-prior-tv $kbid $node)
   (if (known-concept-node? $kbid $node)
      (let $n (list-len (concept-nodes $kbid))
         (if (<= $n 0) no-evidence
            (STV (/ 1.0 $n)
               (kb-concept-prior-confidence $kbid))))
      no-evidence))

(: ConceptNodePriorFormula
   (-[det]-> KB Statement OptionalSTV))
(= (ConceptNodePriorFormula $kbid $node)
   (concept-node-prior-tv $kbid $node))

(: resolve-base-rate-prior
   (-[det]-> BaseRatePrior OptionalSTV))
(= (resolve-base-rate-prior (ConceptNodePriorRuntime $kbid $node))
   (concept-node-prior-tv
      (brand KB $kbid) (brand Statement $node)))
(= (resolve-base-rate-prior (STV $s $c)) (STV $s $c))
(= (resolve-base-rate-prior no-evidence) no-evidence)

(: WeightedBaseRateWithPriorTv
   (-[det]-> BaseRateEvidenceWithPriorState OptionalSTV))
(= (WeightedBaseRateWithPriorTv
      (BaseRateEvidenceWithPrior $prior $ev))
   (BaseRateWithPriorFormula
      (resolve-base-rate-prior $prior)
      (WeightedCountBaseRateTv $ev)))

(: member-inheritance-tv
   (-[det]-> KB BaseRateEvidenceState OptionalSTV))
(= (member-inheritance-tv $kbid $ev)
   (let $universe-size (kb-universe-size $kbid)
      (if (== $universe-size no-universe-size)
         (WeightedCountBaseRateTv $ev)
         (WeightedUniverseBaseRateTv
            (the Number $universe-size) $ev))))
