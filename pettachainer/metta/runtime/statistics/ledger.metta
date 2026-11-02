;; Statistical contribution storage and lifecycle.
;; Callers choose populations, sample values, temporal hazards and publication
;; policy. This owner replaces contributions, retains exclusion indexes and
;; resets regimes; all mutations use the scoped context facade.

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

;; Storing the value the cache already holds is skipped, since every store
;; wakes the folds over the pattern.
(: store-produced-base-rate! (-[det]-> KB Statement TV $mode (List $none)))
(= (store-produced-base-rate! $kbid $pattern $tv $mode)
   (if (== $tv no-evidence) ()
      (let $entries (base-rate-cache-entries-for-mode $kbid $pattern $mode)
         (if (case $entries (
                ((cons $entry $_rest) (if (== (base-rate-entry-tv $entry) $tv) true (any-flat? base-rate-entry-user? $entries)))
                (() false)))
            ()
            (let* (($stored (copy_term $pattern))
                   ($hash (base-rate-cache-hash $kbid $pattern))
                   ($_old (foreach-flat base-rate-cache-remove-derived-entry! $entries))
                   ($_new
                      (context-add! &base_rate_cache
                         ($hash (base-rate $kbid $stored $tv computed $mode))))
                   ($_readers (base-rate-readers-changed! $kbid $pattern)))
               ())))))

(: fa-id (-[semidet]-> ForwardAggregateIdentityKey Number))
(= (fa-id $a)(let $b (index-hash $a)(once (match &ctx_forward_aggregate_identity ($b (forward-aggregate-identity-row $c $d))(if (=alpha $c $a) $d (empty))))))

;; Keep the typed callback: fold specialization must preserve descriptor sharing.
(: fa-add-interest! (-[det]-> Number ForwardAggregateDescriptor ForwardTriggerKey Atom))
(= (fa-add-interest! $id $descriptor $trigger)
   (let* (($hash (term_hash $trigger))
          ($_interest (once (context-add! &forward_aggregate_interest_by_trigger
             ($hash (forward-aggregate-interest $trigger $id $descriptor))))))
      (if (space-row-present? &ctx_forward_aggregate_triggers ($hash $trigger)) ()
         (let $_added (once (context-add! &forward_aggregate_triggers ($hash $trigger))) ()))))

;; Copy identity and descriptor together to preserve variable sharing.
(: fa-register! (-[det]-> ForwardAggregateIdentityKey ForwardAggregateDescriptor (List ForwardTriggerKey) (List $a)))
(= (fa-register! $identity $descriptor $triggers)
   (if (== (collapse (once (fa-id $identity))) ())
      (let* (($hash (index-hash $identity))
             ($id (next-search-id fwd_aggregate_id))
             (($i $d) (copy_term (quote ($identity $descriptor))))
             ($stored-identity (the ForwardAggregateIdentityKey $i))
             ($stored-descriptor (the ForwardAggregateDescriptor $d))
             ($_identity (once (context-add! &forward_aggregate_identity
                ($hash (forward-aggregate-identity-row $stored-identity $id)))))
             ($_state (once (context-add! &forward_aggregate_state ($id 0.0 0.0 0))))
             ($_interests (foreach-flat (fa-add-interest! $id $stored-descriptor) (the (List ForwardTriggerKey) $triggers))))
         ())
      ()))

(: fa-state (-[semidet]-> Number ForwardAggregateState))
(= (fa-state $id)
   (once (match &ctx_forward_aggregate_state ($id $sum $mass $members)
      (forward-aggregate-state $id $sum $mass $members))))

(: fa-obs (-[det]-> ForwardAggregateObservationKey (List ForwardAggregateObservation)))
(= (fa-obs $a)(let $h (index-hash $a)(collapse (match &ctx_forward_aggregate_observation ($h $a $b $c $d $_sources)(forward-aggregate-observation $a $b $c $d)))))

;; Standard key order, never random KB-hash order: subtraction affects floats.
(: fa-left-out (-[det]-> Number (List Number) (List ForwardAggregateObservation)))
(= (fa-left-out $id $exclude)
   (fold-flat append-flat () (map-flat fa-obs (aggregate-readers $id $exclude))))

(: fa-subtract-step (-[det]-> ForwardAggregateState ForwardAggregateObservation ForwardAggregateState))
(= (fa-subtract-step (forward-aggregate-state $id $sum $mass $members)
      (forward-aggregate-observation $_key $_value $s $m))
   (let $remaining (- $members (if (> $m 0) 1 0))
      (if (<= $remaining 0) (forward-aggregate-state $id 0.0 0.0 0)
         (forward-aggregate-state $id (- $sum $s) (max 0.0 (- $mass $m)) $remaining))))

(: ledger-replace-member! (-[semidet]-> Number (List ForwardAggregateObservation) ForwardAggregateObservation Bool SourceList ForwardAggregateState))
(= (ledger-replace-member! $id $previous (forward-aggregate-observation $key $value $sum $mass) $keep $sources)
   (let* ((($old-sum $old-mass)
             (case $previous (
                (() (data 0.0 0.0))
                ((cons (forward-aggregate-observation $_key $_value $s $m) $_rest) (data $s $m)))))
          ((forward-aggregate-state $_id $total $weight $members) (fa-state $id))
          ($was-counted (if (> $old-mass 0) 1 0))
          ($counted (if (if $keep (> $mass 0) false) 1 0))
          ($new-count (+ $members (- $counted $was-counted)))
          ($new-sum (if (<= $new-count 0) 0.0 (+ $total (- $sum $old-sum))))
          ($new-mass (if (<= $new-count 0) 0.0 (+ $weight (- $mass $old-mass))))
          ($_old-state (once (context-remove! &forward_aggregate_state ($id $total $weight $members))))
          ($_new-state (once (context-add! &forward_aggregate_state ($id $new-sum $new-mass $new-count))))
          ($hash (index-hash $key))
          ($old-sources (chainer-first-or (source-list ()) (collapse (once
             (match &ctx_forward_aggregate_observation ($hash $key $_old-v $_old-s $_old-m $reads) $reads)))))
          ($_sources (update-aggregate-sources! $id $key $old-sources $was-counted $sources $counted))
          ($_old (context-remove! &forward_aggregate_observation ($hash $key $_value $_sum $_mass $_reads)))
          ($_new (if $keep
                    (once (context-add! &forward_aggregate_observation ($hash $key $value $sum $mass $sources))) ())))
      (forward-aggregate-state $id $new-sum $new-mass $new-count)))

(: ledger-instance-changed! (-[det]-> Number SkeletonKey Atom))
(= (ledger-instance-changed! $hash $fold)
   (if (space-row-present? &ctx_sk_instance_changed ($hash $_stored)) ()
      (context-add! &sk_instance_changed ($hash $fold))))

(: ledger-take-change! (-[det]-> Number SkeletonKey Atom))
(= (ledger-take-change! $hash $fold)
   (context-remove! &sk_instance_changed ($hash $fold)))

(: sk-rate-dirty! (-[det]-> SkeletonKey SkeletonKey Atom))
(= (sk-rate-dirty! $fold $member)
   (if (sk-rate-fold? $fold)
      (let* (($hash (index-hash $fold)) ($mhash (index-hash $member)))
         (if (== (collapse (once (match &ctx_sk_rate_dirty ($hash $mhash $stored-fold $stored)
                    (if (=alpha $stored $member) (if (=alpha $stored-fold $fold) true (empty)) (empty)))))
                 ())
            (let* (($_row (context-add! &sk_rate_dirty ($hash $mhash $fold $member)))
                   ($_changed
                      (if (sk-instance-fold-key? $fold)
                         (ledger-instance-changed! $hash $fold)
                         ())))
               ())
            ()))
      ()))

;; Each contributing member is excluded once, in stable sample order.
(: sk-left-out (-[det]-> Number (List Number) (List InstanceSample)))
(= (sk-left-out $hash $exclude)
   (let $members (list_to_set (collapse (let $read (superpose $exclude)
                    (match &ctx_sk_instance_read ($read $hash $read-member $_member) $read-member))))
      (sort-atom (collapse (let $mhash (superpose $members)
         (match &ctx_sk_instance_member ($mhash $hash $_stored $pos-seg $neg-seg $contribution)
            (case $contribution (
               ((InstanceEvidence (BaseRateEvidence $_pw 0.0) (BaseRateEvidence $_nw 0.0)) (empty))
               ($sample (instance-sample $pos-seg $neg-seg $sample))))))))))

(: sk-leave-out-step (-[det]-> Number InstanceRegimeState InstanceSample InstanceRegimeState))
(= (sk-leave-out-step $hash (instance-regimes $hazard $next $pos $neg) (instance-sample $pos-seg $neg-seg (InstanceEvidence $old-pos $old-neg)))
   (let* ((($pos-segs $_pos-at) (regime-take! $hash $hazard 0 $pos $pos-seg $old-pos (BaseRateEvidence 0.0 0.0)))
          (($neg-segs $_neg-at) (regime-take! $hash $hazard 0 $neg $neg-seg $old-neg (BaseRateEvidence 0.0 0.0))))
      (instance-regimes $hazard $next (the (List RegimeSegment) $pos-segs) (the (List RegimeSegment) $neg-segs))))

;; Pure leave-one-out projection in the existing regime segments.
(: ledger-instance-read-excluding (-[det]-> Number InstanceRegimeState (List InstanceSample) InstanceRegimeState))
(= (ledger-instance-read-excluding $hash $tally $left) (fold-flat (sk-leave-out-step $hash) $tally $left))

(: sk-instance-read! (-[det]-> Number Number SkeletonKey KBContext Atom Atom))
(= (sk-instance-read! $hash $mhash $member $kbctx $statement)
   (let* (($read (index-hash (sk-key $statement $kbctx)))
          ($_row (context-add! &sk_instance_read ($read $hash $mhash $member))))
      ()))

(: sk-instance-reads! (-[det]-> Number Number SkeletonKey Atom))
(= (sk-instance-reads! $hash $mhash $member)
   (case $member (
      ((sk-key (ImplicationInstanceSample $a $b $_atv $_btv) $kbctx)
         (foreach-flat (sk-instance-read! $hash $mhash $member $kbctx)
            (cons $b (implication-side-conjuncts (the Statement $a)))))
      ($_other ()))))

(: sk-entry-hash-step (-[det]-> Number Evidence Number))
(= (sk-entry-hash-step $sum $entry) (+ $sum (index-hash $entry)))

(: sk-instance-digest! (-[det]-> Number Number SkeletonKey SkeletonKey SkeletonValue InstanceEvidenceState Atom))
(= (sk-instance-digest! $hash $mhash $fold $member $value (InstanceEvidence (BaseRateEvidence $_pw $pm) (BaseRateEvidence $_nw $nm)))
   (case $member (
      ((sk-key (ImplicationInstanceSample $a $_b $_atv $_btv) $kbctx)
         (let* (($sample-evidence
                  (case $value (
                     ;; A sample's signature is what it observes, whatever role a
                     ;; derived premise read a fact in.
                     ((sk-val $_fact $ev $_deps)
                        (let $kept
                              (evidence-subtraction (evidence-inherited $ev)
                                 (evidence-set (collapse (let* (($conjuncts (implication-side-conjuncts (the Statement $a)))
                                                                ($conjunct (superpose $conjuncts))
                                                                ($facts (kb-facts (the Statement $conjunct) $kbctx))
                                                                (($type $fact-ctx $proof $_tv) (superpose $facts)))
                                                             (fact-evidence-entry $fact-ctx $proof $type)))))
                           (evidence-set (evidence-shared-facts $kept $kept))))
                     ($_none (ev-set 0)))))
                ($observed (fold-flat sk-entry-hash-step 0 (evidence-entries $sample-evidence)))
                ($_support (update-likelihood-support! $fold $member (observation-sources $sample-evidence)
                              (if (> $pm 0) 1 0) (if (> $nm 0) 1 0)))
                ($mass (+ $pm $nm))
                ($sig (if (> $mass 0.0) (index-hash (sk-sample-sig $observed (round-math (* 1000000 (/ $pm $mass))))) 0))
                ($was (chainer-first-or 0 (collapse (once (match &ctx_sk_instance_digest ($hash $stored) $stored)))))
                ($taken (chainer-first-or 0 (collapse (once (match &ctx_sk_instance_sig ($mhash $hash $stored-sig) $stored-sig)))))
                ($digest (+ (- $was $taken) $sig))
                ($_old (remove-data-rows! &sk_instance_digest (quote ($hash $_d))))
                ($_new (context-add! &sk_instance_digest ($hash $digest)))
                ($_old-sig (remove-data-rows! &sk_instance_sig (quote ($mhash $hash $_s))))
                ($_new-sig (context-add! &sk_instance_sig ($mhash $hash $sig))))
            ()))
      ($_other ()))))

;; Replace an instance sample in its original segments; first admission alone
;; registers its read keys. Unknown samples retain their zero contribution.
(: ledger-member-current! (-[det]-> Number Number SkeletonKey SkeletonKey Atom))
(= (ledger-member-current! $hash $mhash $fold $member)
   (remove-variant-row! &sk_rate_dirty (quote ($hash $mhash $fold $member))))

(: ledger-replace-instance!
   (-[det]-> Number SkeletonKey SkeletonKey InstanceRegimeState InstanceEvidenceState SkeletonValue InstanceEvidenceState Atom))
(= (ledger-replace-instance! $hash $fold $member $tally $new $value $start)
   (let* (($mhash (index-hash $member))
          ($_clean (ledger-member-current! $hash $mhash $fold $member))
          ($found
             (collapse (once (match &ctx_sk_instance_member ($mhash $hash $stored $pos-seg $neg-seg $contribution)
                (if (=alpha $stored $member) (instance-sample $pos-seg $neg-seg $contribution) (empty))))))
          ($_digest (sk-instance-digest! $hash $mhash $fold $member $value $new)))
      (sk-instance-store! $hash $fold $mhash $member $tally $new
         (case $found (
            ((cons (instance-sample $was-pos $was-neg $old) $_others)
               (let $_replaced (remove-variant-row! &sk_instance_member (quote ($mhash $hash $member $was-pos $was-neg $old)))
                  (instance-sample $was-pos $was-neg $old)))
            (() (let $_reads (sk-instance-reads! $hash $mhash $member) (instance-sample 0 0 $start))))))))

(: sk-instance-store!
   (-[det]-> Number SkeletonKey Number SkeletonKey InstanceRegimeState InstanceEvidenceState InstanceSample Atom))
(= (sk-instance-store! $hash $fold $mhash $member (instance-regimes $hazard $next $pos $neg) (InstanceEvidence $new-pos $new-neg)
      (instance-sample $pos-seg $neg-seg (InstanceEvidence $old-pos $old-neg)))
   (let* ((($pos-segs $pos-at) (regime-take! $hash $hazard $next $pos $pos-seg $old-pos $new-pos))
          (($neg-segs $neg-at) (regime-take! $hash $hazard (- 0 $next) $neg $neg-seg $old-neg $new-neg))
          ($counted (+ $next 1))
          ($taken (instance-regimes $hazard $counted (the (List RegimeSegment) $pos-segs) (the (List RegimeSegment) $neg-segs)))
          ($_untallied (remove-variant-row! &sk_instance_tally (quote ($hash $fold (instance-regimes $hazard $next $pos $neg)))))
          ($_tallied (context-add! &sk_instance_tally ($hash $fold $taken)))
          ($new (InstanceEvidence $new-pos $new-neg))
          ($_member (context-add! &sk_instance_member ($mhash $hash $member $pos-at $neg-at $new))))
      ()))

(: sk-rate-changed (-[det]-> Number SkeletonKey (List SkeletonKey)))
(= (sk-rate-changed $hash $fold)
   (collapse (match &ctx_sk_rate_dirty ($hash $_mhash $stored $member) (if (=alpha $stored $fold) $member (empty)))))

;; Exclusion is a projection: the stored tally and cache remain authoritative.
(: ledger-read-excluding (-[semidet]-> Number (List ForwardAggregateObservation) ForwardAggregateState))
(= (ledger-read-excluding $id $left)
   (fold-flat fa-subtract-step (fa-state $id) $left))

;; Hazard selection stays with the temporal policy. Reset replays admitted
;; members in their original read-index order, before still-pending members.
(: ledger-reset-regime! (-[det]-> Number SkeletonKey Atom))
(= (ledger-reset-regime! $hash $fold)
   (let* (($members (the (List SkeletonKey) (alpha_unique_keys (collapse (match &ctx_sk_instance_read ($_fr $hash $_fmh $member) $member)))))
          ($pending (sk-rate-changed $hash $fold))
          ($_dirty (remove-data-rows! &sk_rate_dirty (quote ($hash $_dmh $_df $_dm))))
          ($_tally (remove-data-rows! &sk_instance_tally (quote ($hash $_tf $_ta))))
          ($_member (remove-data-rows! &sk_instance_member (quote ($_mmh $hash $_mm $_mp $_mn $_mc))))
          ($_regime (remove-data-rows! &sk_instance_regime (quote ($hash $_rs $_rt))))
          ($_digest (remove-data-rows! &sk_instance_digest (quote ($hash $_dd))))
          ($_sig (remove-data-rows! &sk_instance_sig (quote ($_smh $hash $_ss))))
          ($_read (remove-data-rows! &sk_instance_read (quote ($_rr $hash $_rmh $_rmm)))))
      (foreach-flat (sk-rate-dirty! $fold) (append-flat $members $pending))))

;; User-rate validation, canonicalization, gating and notifications remain in
;; the API controller; this transaction owns the physical replacement only.
(: ledger-set-base-rate! (-[det]-> KB Statement $tv Atom))
(= (ledger-set-base-rate! $kb $pattern $tv)
   (let* (($stored (copy_term $pattern))
          ($hash (base-rate-cache-hash $kb $pattern))
          ($_old (base-rate-cache-remove! $kb $pattern))
          ($_new (context-add! &base_rate_cache ($hash (base-rate $kb $stored $tv user any)))))
      ()))

(: link-aggregate-fold! (-[det]-> Number Number Atom))
(= (link-aggregate-fold! $id $hash)
   (if (space-row-present? &ctx_forward_aggregate_fold ($id $hash)) ()
      (let $_row (context-add! &forward_aggregate_fold ($id $hash)) ())))
