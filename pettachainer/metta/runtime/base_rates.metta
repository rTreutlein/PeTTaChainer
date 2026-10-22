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

;; A KB may read each computed base rate as a Beta estimate: its n
;; observations plus k pseudo-observations of complete ignorance at 0.5, so a
;; rate over few observations is uncertain in its strength as well as its
;; confidence. The confidence n/(n+k) is unchanged, and n is recovered from it.
;; Opt-in per KB, set before adding knowledge; user base rates are kept as set.
(: set-base-rate-smoothing (-[det]-> KB Bool Bool))
(= (set-base-rate-smoothing $kb $enabled)
   (let* (($_old
             (collapse (match &base_rate_smoothing ($kb $stored)
                (remove-atom &base_rate_smoothing ($kb $stored)))))
          ($_new (add-atom &base_rate_smoothing ($kb $enabled))))
      $enabled))

(: smoothed-base-rate-tv (-[det]-> KB Atom Atom))
(= (smoothed-base-rate-tv $kb $tv)
   (case $tv (
      ((STV $s $c)
         (if (== (collapse (once (match &base_rate_smoothing ($kb true) true))) ()) $tv
            (let* (($n (confidence-to-count $c)) ($k (evidence-confidence-k)))
               (STV (/ (+ (* $s $n) (* 0.5 $k)) (+ $n $k)) $c))))
      ($_other $tv))))

(: BaseRateAggregateKey Type)
(: base-rate-aggregate-key-value (-[det]-> KB Statement $mode BaseRateAggregateKey))
(: NoBaseRateAggregateKey Type)
(: no-base-rate-aggregate-key NoBaseRateAggregateKey)

(: base-rate-aggregate-key (-[det]-> $arguments (| BaseRateAggregateKey NoBaseRateAggregateKey)))
(= (base-rate-aggregate-key $args)
   (case $args (
      (($kbid $pattern $_extractor $_init $_fun $finish $_tv-mode)
         (if (base-rate-finish? $finish)
            (base-rate-aggregate-key-value (brand KB $kbid) (brand Statement $pattern) $finish)
            no-base-rate-aggregate-key))
      ($_other no-base-rate-aggregate-key))))

;; Cache rows lead with a hash of the knowledge base and pattern, so a lookup
;; reads only that pattern's entries; the alpha comparison rejects collisions.
(: base-rate-cache-hash (-[det]-> KB Statement Number))
(= (base-rate-cache-hash $kbid $pattern) (index-hash (quote ($kbid $pattern))))

(: base-rate-cache-entries (-[det]-> KB Statement (List BaseRateEntry)))
(= (base-rate-cache-entries $kbid $pattern)
   (let $hash (base-rate-cache-hash $kbid $pattern)
      (collapse
         (match &ctx_base_rate_cache ($hash (base-rate $kbid $stored $tv $source $mode))
            (if (=alpha $stored $pattern) (base-rate $kbid $stored $tv $source $mode) (empty))))))

;; Binding the hash in a let around this match makes the checker lose the
;; entries' determinism at foreach-flat callers, so it is passed in.
(: base-rate-cache-mode-rows (-[det]-> Number KB Statement $mode (List BaseRateEntry)))
(= (base-rate-cache-mode-rows $hash $kbid $pattern $mode)
   (collapse
      (match &ctx_base_rate_cache ($hash (base-rate $kbid $stored $tv $source $emode))
         (if (and (=alpha $stored $pattern) (or (== $emode any) (== $emode $mode)))
            (base-rate $kbid $stored $tv $source $emode)
            (empty)))))

(: base-rate-cache-entries-for-mode (-[det]-> KB Statement $mode (List BaseRateEntry)))
(= (base-rate-cache-entries-for-mode $kbid $pattern $mode)
   (base-rate-cache-mode-rows (base-rate-cache-hash $kbid $pattern) $kbid $pattern $mode))

(: base-rate-cache-remove-derived-entry! (-[det]-> BaseRateEntry (List $none)))
(= (base-rate-cache-remove-derived-entry! (base-rate $kbid $stored $tv $source $mode))
   (if (== $source user) ()
      (let* (($hash (base-rate-cache-hash $kbid $stored))
             ;; Exactly this row: an open pattern would also remove another
             ;; pattern's entry that unifies with it.
             ($_removed
                (remove-variant-row! &base_rate_cache
                   (quote ($hash (base-rate $kbid $stored $tv computed $mode))))))
         ())))

(: base-rate-cache-remove! (-[det]-> KB Statement (List $none)))
(= (base-rate-cache-remove! $kbid $pattern)
   (let* (($hash (base-rate-cache-hash $kbid $pattern))
          ($_
             (collapse
                (match &ctx_base_rate_cache ($hash (base-rate $kbid $stored $tv $source $mode))
                   (if (=alpha $stored $pattern)
                      (context-remove! &base_rate_cache
                         (quote ($hash (base-rate $kbid $stored $tv $source $mode))))
                      (empty))))))
      ()))

(: base-rate-entry-tv (-[det]-> BaseRateEntry TV))
(= (base-rate-entry-tv (base-rate $_kbid $_stored $tv $_source $_mode)) $tv)

(: base-rate-entry-user? (-[det]-> BaseRateEntry Bool))
(= (base-rate-entry-user? (base-rate $_kbid $_stored $_tv $source $_mode)) (== $source user))

(: base-rate-cache-user-present? (-[det]-> (List BaseRateEntry) Bool))
(= (base-rate-cache-user-present? ()) false)
(= (base-rate-cache-user-present? (cons $entry $rest))
   (if (base-rate-entry-user? $entry) true (base-rate-cache-user-present? $rest)))

(: cached-base-rate (-[nondet]-> KB Statement (List TV)))
(= (cached-base-rate $kbid $pattern)
   (case (base-rate-cache-entries $kbid $pattern) (
      (() ())
      ((cons $entry $_rest) (cons (base-rate-entry-tv $entry) ())))))

;; The keys reading a pattern's cache entries through a fold, in any mode,
;; recompute when one changes.
(: base-rate-readers-changed! (-[det]-> KB Statement (List $none)))
(= (base-rate-readers-changed! $kbid $pattern)
   (let* (($hash (base-rate-cache-hash $kbid $pattern))
          ($_dirty (collapse (match &ctx_sk_rate_readers ($hash $key) (sk-dirty! $key)))))
      ()))

(: store-produced-base-rate! (-[det]-> KB Statement TV $mode (List $none)))
(= (store-produced-base-rate! $kbid $pattern $tv $mode)
   (if (== $tv no-evidence) ()
      (let $entries (base-rate-cache-entries-for-mode $kbid $pattern $mode)
         (if (base-rate-cache-user-present? $entries)
            ()
            (let* (($stored (copy_term $pattern))
                   ($hash (base-rate-cache-hash $kbid $pattern))
                   ($_old (foreach-flat base-rate-cache-remove-derived-entry! $entries))
                   ($_new
                      (context-add! &base_rate_cache
                         ($hash (base-rate $kbid $stored $tv computed $mode))))
                   ($_readers (base-rate-readers-changed! $kbid $pattern)))
               ())))))

(: remove-produced-base-rate! (-[det]-> KB Statement $mode (List $none)))
(= (remove-produced-base-rate! $kbid $pattern $mode)
   (let* (($_old
             (foreach-flat base-rate-cache-remove-derived-entry!
                (base-rate-cache-entries-for-mode $kbid $pattern $mode)))
          ($_readers (base-rate-readers-changed! $kbid $pattern)))
      ()))
(: invalidate-computed-base-rates! (-[det]-> KB (List $none)))
(= (invalidate-computed-base-rates! $kbid)
   (let $_computed
      (context-remove! &base_rate_cache (quote ($_h1 (base-rate $kbid $_s1 $_tv1 computed $_m1))))
      ()))

;; Inheritance subjects and concept nodes are recorded once per KB, and their
;; number per KB is kept as they arrive: priors divide by it on every fold step.
(: KbNodeKind Type)
(: subject-node KbNodeKind)
(: concept-node KbNodeKind)
(: &kb_node_count (SpaceOf (KB KbNodeKind Number)))
!(bind! &kb_node_count (new-space))

(: kb-node-count (-[det]-> KB KbNodeKind Number))
(= (kb-node-count $kbid $kind)
   (case (collapse (once (match &kb_node_count ($kbid $kind $count) $count))) (
      ((cons $count $_rest) $count)
      (() 0))))

;; A node joins its space (&inheritance_subject or &concept_node) once per KB,
;; and its kind's count grows by one.
(: record-kb-node! (-[det]-> $space KbNodeKind KB Statement Atom))
(= (record-kb-node! $space $kind $kbid $node)
   (if (is-var $node) ()
      (if (space-row-present? $space ($kbid $node)) ()
         (let* (($_row (add-space-atom! $space (make-space-pair $kbid $node)))
                ($count (kb-node-count $kbid $kind))
                ($_old (collapse (match &kb_node_count ($kbid $kind $old) (remove-atom &kb_node_count ($kbid $kind $old)))))
                ($next (+ $count 1))
                ($_new (add-atom &kb_node_count ($kbid $kind $next))))
            ()))))

(: record-inheritance-nodes! (-[det]-> KB Statement Statement Atom))
(= (record-inheritance-nodes! $kbid $subj $concept)
   (let $_subject (record-kb-node! &concept_node concept-node $kbid $subj)
      (record-kb-node! &concept_node concept-node $kbid $concept)))

(: clear-concept-prior-confidence (-[det]-> KB (List $none)))
(= (clear-concept-prior-confidence $kbid)
   (let*
      (($_remove (remove-atom &concept_prior_confidence (concept-prior-confidence $kbid $_c)))
       ($_invalidate (invalidate-computed-base-rates! $kbid)))
      ()))

(: set-concept-prior-confidence (-[det]-> KB Number (List $none)))
(= (set-concept-prior-confidence $kbid $c)
   (let*
      (($_old (clear-concept-prior-confidence $kbid))
       ($_new (add-atom &concept_prior_confidence (concept-prior-confidence $kbid $c))))
      ()))

(: known-concept-node? (-[det]-> KB Statement Bool))
(= (known-concept-node? $kbid $node) (space-row-present? &concept_node ($kbid $node)))

(: concept-node-prior-tv (-[det]-> KB Statement OptionalSTV))
(= (concept-node-prior-tv $kbid $node)
   (if (known-concept-node? $kbid $node)
      (let $n (kb-node-count $kbid concept-node)
         (if (<= $n 0) no-evidence
            (STV (/ 1.0 $n)
               (chainer-first-or 0.000001
                  (collapse
                     (match &concept_prior_confidence
                        (concept-prior-confidence $kbid $c)
                        (stored-number $c)))))))
      no-evidence))

(: resolve-base-rate-prior (-[det]-> BaseRatePrior OptionalSTV))
(= (resolve-base-rate-prior (ConceptNodePriorRuntime $kbid $node))
   (concept-node-prior-tv (brand KB $kbid) (brand Statement $node)))
(= (resolve-base-rate-prior (STV $s $c)) (STV $s $c))
(= (resolve-base-rate-prior no-evidence) no-evidence)

(: member-inheritance-tv (-[det]-> KB BaseRateEvidenceState OptionalSTV))
(= (member-inheritance-tv $_kbid $ev) (WeightedCountBaseRateTv $ev))
