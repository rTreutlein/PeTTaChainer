;; Incremental aggregate subscriptions maintained as canonical outputs change.
;; Both supported families reduce to additive evidence totals.  Their
;; descriptors retain the family-specific extraction and cache policy while a
;; single hash-indexed subscription/state/observation mechanism owns updates.
;; Registration identity includes open compiler variables. Hash an
;; alpha-invariant ground skeleton, then retain and compare the complete key so
;; hash collisions cannot change deduplication.
(: forward-base-rate-identity-key-leaf (-[det]-> Atom Atom))
(= (forward-base-rate-identity-key-leaf $atom)
   (if (is-var $atom) forward-base-rate-identity-variable $atom))

(: forward-aggregate-identity-hash
   (-[det]-> ForwardAggregateIdentityKey Number))
(= (forward-aggregate-identity-hash
      (forward-base-rate-identity
         $kbid $pattern $extractor $init $fun $finish $tv-mode))
   (term_hash
      (map-nested forward-base-rate-identity-key-leaf
         (quote
            ($kbid $pattern ($extractor $init)
               $fun $finish $tv-mode)))))
(= (forward-aggregate-identity-hash
      (forward-member-inheritance-identity $kbid $subj $concept))
   (term_hash (quote ($kbid $subj $concept))))

(: forward-register-aggregate!
   (-[det]-> ForwardAggregateIdentityKey ForwardAggregateDescriptor
       ForwardTriggerKey Bool ForwardTriggerKey (List $none)))
(= (forward-register-aggregate!
      $identity $descriptor $trigger $has-other-trigger? $other-trigger)
   (let*
      (($identity-hash (forward-aggregate-identity-hash $identity))
       ($trigger-hash (term_hash $trigger))
       ($hits
          (collapse
             (once
                (match &forward_aggregate_identity
                   ($identity-hash
                      (forward-aggregate-identity-row
                         $stored-identity $stored-id))
                   (if (=alpha $stored-identity $identity)
                      $stored-id
                      (empty)))))))
      (if (== $hits ())
         (let*
            (($id (next-search-id fwd_aggregate_id))
             (($stored-identity $stored-descriptor)
                (copy_term (quote ($identity $descriptor))))
             ($typed-stored-identity
                (the ForwardAggregateIdentityKey $stored-identity))
             ($typed-stored-descriptor
                (the ForwardAggregateDescriptor $stored-descriptor))
             ($_identity
                (once
                   (add-atom &forward_aggregate_identity
                      ($identity-hash
                         (forward-aggregate-identity-row
                            $typed-stored-identity $id)))))
             ($_trigger
                (once
                   (add-atom &forward_aggregate_interest_by_trigger
                      ($trigger-hash
                         (forward-aggregate-interest
                            $trigger $id $typed-stored-descriptor)))))
             ($_other-trigger
                (if $has-other-trigger?
                   (let*
                      (($second-hash (term_hash $other-trigger))
                       ($_stored
                         (once
                            (add-atom
                               &forward_aggregate_interest_by_trigger
                               ($second-hash
                                  (forward-aggregate-interest
                                     $other-trigger $id
                                     $typed-stored-descriptor))))))
                      ())
                   ()))
             ($_state
                (once
                   (add-atom &forward_aggregate_state
                      (forward-aggregate-state $id 0.0 0.0)))))
            ())
         ())))

;; Query-local additions do not register ordinary base-rate folds. Keep their
;; hot path to the one Member-inheritance shape instead of testing every
;; base-rate descriptor during each backward query compilation.
(: forward-register-member-aggregate-premise!
   (-[det]-> (| Goal (Statement KBContext Proof TV)) (List $none)))
(= (forward-register-member-aggregate-premise! $premise)
   (case $premise (
      ((CPU FoldAllCompiled
          ($kbid
             (MemberInheritanceSample $obj $subj $concept $atv $btv)
             (extract-value
                (MemberInheritanceSample $obj $subj $concept $atv $btv)
                (WeightedTv $atv $btv))
             (BaseRateEvidence 0.0 0.0)
             WeightedBaseRateAcc
             (member-inheritance $kbid)
             result-tv)
          $_result)
         (if (== (extract-vars $subj) ())
            (if (== (extract-vars $concept) ())
               (let*
                  (($typed-kbid (brand KB $kbid))
                   ($typed-subj (brand Term $subj))
                   ($typed-concept (brand Term $concept))
                   ($pattern
                      (brand Statement
                         (MemberInheritanceSample
                            $obj $subj $concept $atv $btv)))
                   ($subject-trigger
                      (fwd_member $typed-kbid $typed-subj))
                   ($distinct-triggers?
                      (not (== $typed-subj $typed-concept)))
                   ($concept-trigger
                      (fwd_member $typed-kbid $typed-concept)))
                  (forward-register-aggregate!
                     (forward-member-inheritance-identity
                        $typed-kbid $typed-subj $typed-concept)
                     (forward-member-inheritance-descriptor
                        $typed-kbid $typed-subj $typed-concept $pattern)
                     $subject-trigger
                     $distinct-triggers? $concept-trigger))
               ())
            ()))
      ($_other ()))))

(: forward-register-aggregate-premise!
   (-[det]-> Bool (| Goal (Statement KBContext Proof TV))
       (List $none)))
(= (forward-register-aggregate-premise! $register-base-rates? $premise)
   (if $register-base-rates?
      (case $premise (
      ((CPU FoldAllCompiled
          ($kbid $pattern extract-tv
             (BaseRateEvidence $initial-weight $initial-count)
             BaseRateAcc base-rate result-tv)
          $_result)
         (let*
            (($typed-kbid (brand KB $kbid))
             ($typed-pattern (brand Statement $pattern))
             ($init
                (BaseRateEvidence $initial-weight $initial-count)))
            (forward-register-aggregate!
               (forward-base-rate-identity
                  $typed-kbid $typed-pattern extract-tv
                  $init BaseRateAcc base-rate result-tv)
               (forward-base-rate-descriptor
                  $typed-kbid $typed-pattern extract-tv
                  $init BaseRateAcc base-rate)
               (forward-type-trigger-key
                  $typed-kbid $typed-pattern)
               false fwd_trigger_any)))
      ((CPU FoldAllCompiled
          ($kbid $pattern
             (extract-inheritance-tv $extract-kb $extract-pattern)
             (BaseRateEvidence $initial-weight $initial-count)
             WeightedBaseRateAcc
             (weighted-base-rate-in-universe $finish-kb)
             result-tv)
          $_result)
         (let*
            (($typed-kbid (brand KB $kbid))
             ($typed-pattern (brand Statement $pattern))
             ($extractor
                (extract-inheritance-tv
                   (brand KB $extract-kb)
                   (brand Statement $extract-pattern)))
             ($init
                (BaseRateEvidence $initial-weight $initial-count))
             ($finish
                (weighted-base-rate-in-universe
                   (brand KB $finish-kb))))
            (forward-register-aggregate!
               (forward-base-rate-identity
                  $typed-kbid $typed-pattern $extractor
                  $init WeightedBaseRateAcc $finish result-tv)
               (forward-base-rate-descriptor
                  $typed-kbid $typed-pattern $extractor
                  $init WeightedBaseRateAcc $finish)
               (forward-type-trigger-key
                  $typed-kbid $typed-pattern)
               false fwd_trigger_any)))
      ((CPU FoldAllCompiled
          ($kbid $pattern
             (extract-inheritance-tv $extract-kb $extract-pattern)
             (BaseRateEvidenceWithPrior $prior
                (BaseRateEvidence $initial-weight $initial-count))
             WeightedBaseRateWithPriorAcc
             (weighted-base-rate-with-prior-in-universe $finish-kb)
             result-tv)
          $_result)
         (let*
            (($typed-kbid (brand KB $kbid))
             ($typed-pattern (brand Statement $pattern))
             ($extractor
                (extract-inheritance-tv
                   (brand KB $extract-kb)
                   (brand Statement $extract-pattern)))
             ($init
                (BaseRateEvidenceWithPrior
                   (brand BaseRatePrior $prior)
                   (BaseRateEvidence
                      $initial-weight $initial-count)))
             ($finish
                (weighted-base-rate-with-prior-in-universe
                   (brand KB $finish-kb))))
            (forward-register-aggregate!
               (forward-base-rate-identity
                  $typed-kbid $typed-pattern $extractor $init
                  WeightedBaseRateWithPriorAcc $finish result-tv)
               (forward-base-rate-descriptor
                  $typed-kbid $typed-pattern $extractor $init
                  WeightedBaseRateWithPriorAcc $finish)
               (forward-type-trigger-key
                  $typed-kbid $typed-pattern)
               false fwd_trigger_any)))
         ($_other
            (forward-register-member-aggregate-premise! $premise))))
      (forward-register-member-aggregate-premise! $premise)))

(: register-forward-aggregate-premises!
   (-[det]-> Bool (List (| Goal (Statement KBContext Proof TV)))
       (List $none)))
(= (register-forward-aggregate-premises!
      $register-base-rates? $premises)
   (foreach-flat
      (forward-register-aggregate-premise! $register-base-rates?)
      $premises))

(: forward-positive-base-rate-contribution
   (-[det]-> TV BaseRateEvidenceState))
(= (forward-positive-base-rate-contribution $tv)
   (case $tv (
      ((STV $s $c) (BaseRateEvidence (* $s $c) $c))
      ((CTV $positive $_negative)
         (forward-positive-base-rate-contribution $positive))
      ($_other (BaseRateEvidence 0.0 0.0)))))

(: forward-weighted-base-rate-contribution
   (-[det]-> TV TV BaseRateEvidenceState))
(= (forward-weighted-base-rate-contribution $mass-tv $value-tv)
   (case $mass-tv (
      ((STV $mass $mass-confidence)
         (case $value-tv (
            ((STV $strength $confidence)
               (let $weight
                  (* (* $mass $mass-confidence) $confidence)
                  (BaseRateEvidence
                     (* $strength $weight) $weight)))
            ((CTV $positive $_negative)
               (forward-weighted-base-rate-contribution
                  $mass-tv $positive))
            ($_other-value
               (BaseRateEvidence 0.0 0.0)))))
      ($_other-mass
         (BaseRateEvidence 0.0 0.0)))))

(: forward-inheritance-mass-scale (-[det]-> KB Number))
(= (forward-inheritance-mass-scale $kbid)
   (let $universe-size (kb-universe-size $kbid)
      (if (== $universe-size no-universe-size)
         (let $n (list-len (inheritance-subjects $kbid))
            (if (<= $n 0) 0.0 (/ 1.0 $n)))
         (let $size (the Number $universe-size)
            (if (<= $size 0.0) 0.0 (/ 1.0 $size))))))

(: forward-base-rate-accumulator
   (-[det]-> KB
       (| ExtractTV ExtractInheritanceTV)
       (| BaseRateEvidenceState BaseRateEvidenceWithPriorState)
       (-[semidet]-> $accumulator $value $accumulator)
       Number Number
       (| BaseRateEvidenceState BaseRateEvidenceWithPriorState)))
(= (forward-base-rate-accumulator
      $_kbid $_extractor (BaseRateEvidence $_iw $_ic) BaseRateAcc $wsum $csum)
   (BaseRateEvidence $wsum $csum))
(= (forward-base-rate-accumulator
      $kbid (extract-inheritance-tv $_ekbid $_pattern)
      (BaseRateEvidence $_iw $_ic) WeightedBaseRateAcc $wsum $csum)
   (let $scale (forward-inheritance-mass-scale $kbid)
      (BaseRateEvidence (* $scale $wsum) (* $scale $csum))))
(= (forward-base-rate-accumulator
      $kbid (extract-inheritance-tv $_ekbid $_pattern)
      (BaseRateEvidenceWithPrior $prior (BaseRateEvidence $_iw $_ic))
      WeightedBaseRateWithPriorAcc $wsum $csum)
   (let $scale (forward-inheritance-mass-scale $kbid)
      (BaseRateEvidenceWithPrior $prior
         (BaseRateEvidence (* $scale $wsum) (* $scale $csum)))))

(: forward-store-aggregate-state!
   (-[det]-> Number Number Number Number Number Bool))
(= (forward-store-aggregate-state! $id $old-wsum $old-csum $wsum $csum)
   (progn
      (once
         (remove-atom &forward_aggregate_state
            (forward-aggregate-state
               $id $old-wsum $old-csum)))
      (once
         (add-atom &forward_aggregate_state
            (forward-aggregate-state $id $wsum $csum)))))

(: forward-aggregate-state-by-id
   (-[semidet]-> Number ForwardAggregateState))
(= (forward-aggregate-state-by-id $id)
   (once
      (match &forward_aggregate_state
         (forward-aggregate-state $id $wsum $csum)
         (forward-aggregate-state $id $wsum $csum))))

(: forward-remove-aggregate-observation!
   (-[det]-> ForwardAggregateObservation (| Bool (List $none))))
(= (forward-remove-aggregate-observation! $observation)
   (once
      (remove-atom &forward_aggregate_observation $observation)))

;; Forward incremental folds support exactly these three additive accumulator
;; shapes. Keep their finalization local so calls are compiled only after the
;; implementation is available.
(: forward-finish-aggregate
   (-[semidet]-> (| BaseRateFinish
          WeightedBaseRateInUniverseFinish
          WeightedBaseRateWithPriorInUniverseFinish)
       (| BaseRateEvidenceState BaseRateEvidenceWithPriorState)
       TV))
(= (forward-finish-aggregate
      base-rate (BaseRateEvidence $wsum $csum))
   (BaseRateTv (BaseRateEvidence $wsum $csum)))
(= (forward-finish-aggregate
      (weighted-base-rate-in-universe $kbid)
      (BaseRateEvidence $wsum $msum))
   (let $ev (BaseRateEvidence $wsum $msum)
      (let $universe-size (kb-universe-size $kbid)
         (if (== $universe-size no-universe-size)
            (WeightedBaseRateTv $ev)
            (WeightedUniverseBaseRateTv
               (the Number $universe-size) $ev)))))
(= (forward-finish-aggregate
      (weighted-base-rate-with-prior-in-universe $kbid)
      (BaseRateEvidenceWithPrior $prior $ev))
   (let $universe-size (kb-universe-size $kbid)
      (BaseRateWithPriorFormula
         (resolve-base-rate-prior
            $prior)
         (if (== $universe-size no-universe-size)
            (WeightedBaseRateTv $ev)
            (WeightedUniverseBaseRateTv
               (the Number $universe-size) $ev)))))

(: forward-finish-stored-aggregate
   (-[semidet]-> (| BaseRateFinish
          WeightedBaseRateInUniverseFinish
          WeightedBaseRateWithPriorInUniverseFinish)
       (| BaseRateEvidenceState BaseRateEvidenceWithPriorState)
       TV))
(= (forward-finish-stored-aggregate $finish $acc)
   (case $finish (
      (base-rate
         (forward-finish-aggregate base-rate $acc))
      ((weighted-base-rate-in-universe $kbid)
         (forward-finish-aggregate
            (weighted-base-rate-in-universe
               $kbid)
            $acc))
      ((weighted-base-rate-with-prior-in-universe $kbid)
         (forward-finish-aggregate
            (weighted-base-rate-with-prior-in-universe
               $kbid)
            $acc)))))

(: forward-member-canonical
   (-[det]-> KB Term Term
       (| ForwardOutputCandidate NoForwardOutputCandidate)))
(= (forward-member-canonical $kbid $obj $class)
   (let $rows
      (collapse
         (once
            (forward-member-output-row $kbid $obj $class)))
      (if (== $rows ())
         no-forward-output-candidate
         (let (forward-output-row $fact $evidence)
            (first-forward-output-row $rows)
            (forward-output-candidate $fact $evidence)))))

(: forward-member-output-row
   (-[nondet]-> KB Term Term  ForwardOutputRow))
(= (forward-member-output-row $kbid $obj $class)
   (let*
      (($type (brand Statement (Member $obj $class)))
       ($kb (make-kb-context $kbid MAIN Nil))
       ($hash (term_hash (quote ($kb $type))))
       ($rows
          (collapse
             (once
                (match &forward_canonical_evidence
                   (forward-canonical-evidence-row
                      $hash $type $kb $canonical $evidence)
                   (forward-output-row
                      $canonical $evidence)))))
       ($stored
          (collapse
             (once
                (match &kb
                   (@ $fact ($type $kb $proof $tv))
                   (forward-output-row
                      $fact
                      (forward-fact-evidence
                         $type $kb $proof $tv)))))))
      (if (== $rows ())
         (emit-stored-forward-output-rows $stored)
         (emit-stored-forward-output-rows $rows))))

(: ForwardMemberInheritanceComputedRow Type)
(: forward-member-inheritance-computed-row
   (-[det]-> Number ForwardMemberInheritanceComputedRow))

;; An empty fold is derived cache state, not knowledge or evidence. Keep only
;; the largest search budget known to have settled empty for each registered
;; Member-inheritance identity. Matching Member additions refine the existing
;; subscription directly; unrelated monotonic additions do not invalidate it.
(: ForwardMemberInheritanceEmptyCacheRow Type)
(: forward-member-inheritance-empty-cache-row
   (-[det]-> Number Number ForwardMemberInheritanceEmptyCacheRow))

(: forward-remove-member-inheritance-empty-cache-row!
   (-[det]-> ForwardMemberInheritanceEmptyCacheRow
       (| Bool (List $none))))
(= (forward-remove-member-inheritance-empty-cache-row! $row)
   (once
      (remove-atom &forward_member_inheritance_empty_cache $row)))

(: forward-member-inheritance-id
   (-[semidet]-> KB Term Term Number))
(= (forward-member-inheritance-id $kbid $subj $concept)
   (let*
      (($identity
          (forward-member-inheritance-identity
             $kbid $subj $concept))
       ($identity-hash
          (forward-aggregate-identity-hash $identity)))
      (once
         (match &forward_aggregate_identity
            ($identity-hash
               (forward-aggregate-identity-row
                  $stored-identity $id))
            (if (== $stored-identity $identity)
               $id
               (empty))))))

(: forward-member-inheritance-empty-cache-hit?
   (-[det]-> KB Term Term Number Bool))
(= (forward-member-inheritance-empty-cache-hit?
      $kbid $subj $concept $budget)
   (not
      (==
         (collapse
            (once
               (let $id
                  (forward-member-inheritance-id
                     $kbid $subj $concept)
                  (match &forward_member_inheritance_empty_cache
                     (forward-member-inheritance-empty-cache-row
                        $id $stored-budget)
                     (if (>= $stored-budget $budget)
                        true
                        (empty))))))
         ())))

(: forward-clear-member-inheritance-empty-cache!
   (-[det]-> Number (List $none)))
(= (forward-clear-member-inheritance-empty-cache! $id)
   (let $rows
      (collapse
         (match &forward_member_inheritance_empty_cache
            (forward-member-inheritance-empty-cache-row
               $id $stored-budget)
            (forward-member-inheritance-empty-cache-row
               $id $stored-budget)))
      (foreach-flat
         forward-remove-member-inheritance-empty-cache-row!
         $rows)))

(: forward-store-member-inheritance-empty-cache-for-id!
   (-[det]-> Number Number (List $none)))
(= (forward-store-member-inheritance-empty-cache-for-id! $id $budget)
   (if (not
         (==
            (collapse
               (once
                  (match &forward_member_inheritance_empty_cache
                     (forward-member-inheritance-empty-cache-row
                        $id $stored-budget)
                     (if (>= $stored-budget $budget) true (empty)))))
            ()))
      ()
      (let*
         (($_clear
             (forward-clear-member-inheritance-empty-cache! $id))
          ($_add
             (once
                (add-atom &forward_member_inheritance_empty_cache
                   (forward-member-inheritance-empty-cache-row
                      $id $budget)))))
         ())))

(: forward-store-member-inheritance-empty-cache!
   (-[det]-> KB Term Term Number (List $none)))
(= (forward-store-member-inheritance-empty-cache!
      $kbid $subj $concept $budget)
   (let $_
      (collapse
         (let $id
            (forward-member-inheritance-id $kbid $subj $concept)
            (forward-store-member-inheritance-empty-cache-for-id!
               $id $budget)))
      ()))

(: forward-store-member-inheritance-cache!
   (-[det]-> Number KB Statement TV (List $none)))
(= (forward-store-member-inheritance-cache!
      $id $kbid $pattern $tv)
   (let $_empty
      (forward-clear-member-inheritance-empty-cache! $id)
      (if (not (==
            (collapse
               (once
                  (match &forward_member_inheritance_computed
                     (forward-member-inheritance-computed-row $id)
                     true)))
            ()))
         (let*
            (($mode (member-inheritance $kbid))
             ($old-entries
                (base-rate-cache-entries-for-mode
                   $kbid $pattern $mode))
             ($changed?
                (if (== $old-entries ()) false
                   (base-rate-cache-tv-changed?
                      $old-entries $tv)))
             ($_cache
                (store-computed-base-rate!
                   $kbid $pattern $tv $mode))
             ($_revision
                (if $changed?
                   (let $_next
                      (bump-aggregate-revision!
                         (base-rate-aggregate-identity
                            $kbid $pattern $mode))
                      ())
                   ())))
            ())
         (store-forward-base-rate!
            $kbid $pattern $tv (member-inheritance $kbid)))))

;; Backward folds have already resolved proof overlap and dominance before
;; exposing their child snapshots. Replace the matching object's component,
;; while retaining objects absent from a bounded computed pass.
(: forward-merge-computed-member-observation!
   (-[semidet]-> Number ForwardAggregateObservation (List $none)))
(= (forward-merge-computed-member-observation!
      $id
      (forward-aggregate-observation
         $key
         (forward-member-inheritance-observation-value
            $subject $concept)
         $weight $mass))
   (let*
      (($old-observations
          (collapse
             (match &forward_aggregate_observation
                (forward-aggregate-observation
                   $key
                   (forward-member-inheritance-observation-value
                      $old-subject $old-concept)
                   $old-weight $old-mass)
                (forward-aggregate-observation
                   $key
                   (forward-member-inheritance-observation-value
                      $old-subject $old-concept)
                   $old-weight $old-mass))))
       ((forward-aggregate-state $_state-id $old-wsum $old-msum)
          (forward-aggregate-state-by-id $id))
       ($new-observation
          (forward-aggregate-observation
             $key
             (forward-member-inheritance-observation-value
                $subject $concept)
             $weight $mass)))
      (if (== $old-observations ())
         (let*
            (($_state
                (forward-store-aggregate-state!
                   $id $old-wsum $old-msum
                   (+ $old-wsum $weight) (+ $old-msum $mass)))
             ($_observation
                (once
                   (add-atom &forward_aggregate_observation
                      $new-observation))))
            ())
         (let $old-observation (car-atom $old-observations)
            (let
               (forward-aggregate-observation
                  $_old-key
                  (forward-member-inheritance-observation-value
                     $_old-subject $_old-concept)
                  $old-weight $old-mass)
               $old-observation
               (let*
                  (((forward-output-candidate $_osubject $old-subject-ev)
                      $_old-subject)
                   ((forward-output-candidate $_oconcept $old-concept-ev)
                      $_old-concept)
                   ((forward-output-candidate $_nsubject $new-subject-ev)
                      $subject)
                   ((forward-output-candidate $_nconcept $new-concept-ev)
                      $concept)
                   ($old-ev
                      (list_to_set
                         (append-evidence
                            $old-subject-ev $old-concept-ev)))
                   ($new-ev
                      (list_to_set
                         (append-evidence
                            $new-subject-ev $new-concept-ev))))
                  (if (evidence-subset? $new-ev $old-ev) ()
                     (if (and
                           (not (evidence-subset? $old-ev $new-ev))
                           (<= $mass $old-mass))
                        ()
                        (let*
                           (($_state
                               (forward-store-aggregate-state!
                                  $id $old-wsum $old-msum
                                  (+ (- $old-wsum $old-weight) $weight)
                                  (+ (- $old-msum $old-mass) $mass)))
                            ($_old
                               (foreach-flat
                                  forward-remove-aggregate-observation!
                                  $old-observations))
                            ($_new
                               (once
                                  (add-atom
                                     &forward_aggregate_observation
                                     $new-observation))))
                           ())))))))))

(: forward-mark-member-inheritance-computed!
   (-[det]-> Number (| Bool (List $none))))
(= (forward-mark-member-inheritance-computed! $id)
   (once
      (add-atom &forward_member_inheritance_computed
         (forward-member-inheritance-computed-row $id))))

(: forward-aggregate-sample
   (-[det]-> Atom ForwardAggregateObservationValue Number Number
       Atom))
(: forward-empty-aggregate-sample
   (-[det]-> Atom Atom))

(: forward-aggregate-sample-for-fact
   (-[semidet]-> (Statement KBContext Proof TV)
       ForwardAggregateDescriptor Atom))
(= (forward-aggregate-sample-for-fact
      $fact
      (forward-base-rate-descriptor
         $_kbid $pattern $_extractor $_init $_fun $_finish))
   (let*
      ((($type ($_fact-kbid $_ctx $_vars) $_proof $tv)
          (copy_term $fact))
       ($_pattern (let $pattern $type ok))
       ((BaseRateEvidence $weight $count)
          (forward-positive-base-rate-contribution $tv)))
      (forward-aggregate-sample
         (forward-fact-key $fact)
         (forward-base-rate-observation-value $fact)
         $weight $count)))
(= (forward-aggregate-sample-for-fact
      $fact
      (forward-member-inheritance-descriptor
         $kbid $subj $concept $_pattern))
   (let*
      ((((Member $obj $_class) ($_fact-kbid MAIN Nil) $_proof $_tv)
          (copy_term $fact))
       ($typed-obj (brand Term $obj))
       ($subject (forward-member-canonical $kbid $typed-obj $subj))
       ($consequent
          (forward-member-canonical $kbid $typed-obj $concept)))
      (case $subject (
         ((forward-output-candidate $subject-fact $_subject-ev)
            (case $consequent (
               ((forward-output-candidate
                     $consequent-fact $_consequent-ev)
                  (let*
                     ((($_stype $_skb $_sprf $atv) $subject-fact)
                      (($_ctype $_ckb $_cprf $btv) $consequent-fact)
                      ((BaseRateEvidence $weight $mass)
                         (forward-weighted-base-rate-contribution
                            $atv $btv)))
                     (forward-aggregate-sample
                        $typed-obj
                        (forward-member-inheritance-observation-value
                           $subject $consequent)
                        $weight $mass)))
               (no-forward-output-candidate
                  (forward-empty-aggregate-sample $typed-obj)))))
         (no-forward-output-candidate
            (forward-empty-aggregate-sample $typed-obj))))))

(: forward-store-aggregate-cache!
   (-[semidet]-> ForwardAggregateMaintenance Number
       ForwardAggregateDescriptor Number Number (List $none)))
(= (forward-store-aggregate-cache!
      $maintenance $_id
      (forward-base-rate-descriptor
         $kbid $pattern $extractor $init $fun $finish)
      $wsum $csum)
   (if (and (== $maintenance aggregate-remove) (<= $csum 0.0))
      (base-rate-cache-remove-derived! $kbid $pattern $finish)
      (let*
         (($acc
             (forward-base-rate-accumulator
                $kbid $extractor $init $fun $wsum $csum))
          ($estimate
             (forward-finish-stored-aggregate $finish $acc)))
         (store-forward-base-rate!
            $kbid $pattern $estimate $finish))))
(= (forward-store-aggregate-cache!
      $_maintenance $id
      (forward-member-inheritance-descriptor
         $kbid $_subj $_concept $pattern)
      $wsum $msum)
   (if (<= $msum 0.0)
      (base-rate-cache-remove-derived!
         $kbid $pattern (member-inheritance $kbid))
      (forward-store-member-inheritance-cache!
         $id $kbid $pattern
         (member-inheritance-tv $kbid
            (BaseRateEvidence $wsum $msum)))))

(: forward-update-aggregate-interest!
   (-[semidet]-> (Statement KBContext Proof TV) Number
       ForwardAggregateDescriptor (List $none)))
(= (forward-update-aggregate-interest! $fact $id $descriptor)
   (let*
      (($cache-descriptor (copy_term $descriptor))
       ($sample
          (forward-aggregate-sample-for-fact $fact $descriptor))
       (($item $value $weight $count $present?)
          (case $sample (
             ((forward-aggregate-sample
                   $item $value $weight $count)
                (data $item $value $weight $count true))
             ((forward-empty-aggregate-sample $item)
                (data $item no-forward-aggregate-observation-value
                   0.0 0.0 false)))))
       ($observation-key
          (brand ForwardAggregateObservationKey
             (quote ($id $item))))
       ($old-observations
          (collapse
             (match &forward_aggregate_observation
                (forward-aggregate-observation
                   $observation-key $old-value
                   $old-weight $old-count)
                (forward-aggregate-observation
                   $observation-key $old-value
                   $old-weight $old-count))))
       (($old-weight $old-count)
          (if (== $old-observations ())
             (data 0.0 0.0)
             (let
                (forward-aggregate-observation
                   $_key $_value $old-weight $old-count)
                (car-atom $old-observations)
                (data $old-weight $old-count))))
       ((forward-aggregate-state $_stored-id $old-wsum $old-csum)
          (forward-aggregate-state-by-id $id))
       ($wsum (+ (- $old-wsum $old-weight) $weight))
       ($csum (+ (- $old-csum $old-count) $count))
       ($_state
          (forward-store-aggregate-state!
             $id $old-wsum $old-csum $wsum $csum))
       ($_old
          (foreach-flat
             forward-remove-aggregate-observation!
             $old-observations))
       ($_observation
          (if $present?
             (once
                (add-atom &forward_aggregate_observation
                   (forward-aggregate-observation
                      $observation-key $value $weight $count)))
             ()))
       ($_cache
          (forward-store-aggregate-cache!
             aggregate-update $id $cache-descriptor $wsum $csum)))
      ()))

(: forward-aggregate-observation-item
   (-[semidet]-> (Statement KBContext Proof TV)
       ForwardAggregateDescriptor Atom))
(= (forward-aggregate-observation-item
      $fact
      (forward-base-rate-descriptor
         $_kbid $_pattern $_extractor $_init $_fun $_finish))
   (forward-fact-key $fact))
(= (forward-aggregate-observation-item
      $fact
      (forward-member-inheritance-descriptor
         $_kbid $_subj $_concept $_pattern))
   (let ((Member $obj $_class) ($_fact-kbid MAIN Nil) $_proof $_tv)
      (copy_term $fact)
      (brand Term $obj)))

(: forward-remove-aggregate-interest!
   (-[semidet]-> (Statement KBContext Proof TV) Number
       ForwardAggregateDescriptor (List $none)))
(= (forward-remove-aggregate-interest! $fact $id $descriptor)
   (let*
      (($cache-descriptor (copy_term $descriptor))
       ($item (forward-aggregate-observation-item $fact $descriptor))
       ($observation-key
          (brand ForwardAggregateObservationKey
             (quote ($id $item))))
       ($old-observations
          (collapse
             (match &forward_aggregate_observation
                (forward-aggregate-observation
                   $observation-key $old-value
                   $old-weight $old-count)
                (forward-aggregate-observation
                   $observation-key $old-value
                   $old-weight $old-count)))))
      (if (== $old-observations ())
         ;; Removal can run twice around canonical refresh. Member folds must
         ;; republish a surviving computed state; ordinary base rates do not.
         (case $cache-descriptor (
            ((forward-member-inheritance-descriptor
                  $_kbid $_subj $_concept $_pattern)
               (let
                  (forward-aggregate-state $_state-id $wsum $csum)
                  (forward-aggregate-state-by-id $id)
                  (if (<= $csum 0.0) ()
                     (forward-store-aggregate-cache!
                        aggregate-update $id $cache-descriptor
                        $wsum $csum))))
            ($_base-rate ())))
         (let*
            (((forward-aggregate-observation
                  $_key $_value $old-weight $old-count)
                (car-atom $old-observations))
             ((forward-aggregate-state
                   $_state-id $old-wsum $old-csum)
                (forward-aggregate-state-by-id $id))
             ($wsum (- $old-wsum $old-weight))
             ($csum (- $old-csum $old-count))
             ($_state
                (forward-store-aggregate-state!
                   $id $old-wsum $old-csum $wsum $csum))
             ($_old
                (foreach-flat
                   forward-remove-aggregate-observation!
                   $old-observations))
             ($_cache
                (forward-store-aggregate-cache!
                   aggregate-remove $id $cache-descriptor
                   $wsum $csum)))
            ;; A surviving canonical Member proof replaces the removed side;
            ;; with no support, the joined observation remains absent.
            (case $cache-descriptor (
               ((forward-member-inheritance-descriptor
                     $_kbid $_subj $_concept $_pattern)
                  (progn
                     (forward-update-aggregate-interest!
                        $fact $id $cache-descriptor)
                     ()))
               ($_base-rate ())))))))

(: forward-maintain-aggregates-for-key!
   (-[nondet]-> ForwardAggregateMaintenance
       (Statement KBContext Proof TV) ForwardTriggerKey (List $none)))
(= (forward-maintain-aggregates-for-key!
      $maintenance $fact $trigger)
   (let $trigger-hash (term_hash $trigger)
      (match &forward_aggregate_interest_by_trigger
         ($trigger-hash
            (forward-aggregate-interest
               $stored-trigger $id $descriptor))
         (if (== $stored-trigger $trigger)
            (case $maintenance (
               (aggregate-update
                  (forward-update-aggregate-interest!
                     $fact $id (copy_term $descriptor)))
               (aggregate-remove
                  (forward-remove-aggregate-interest!
                     $fact $id (copy_term $descriptor)))))
            (empty)))))

(: forward-maintain-member-aggregates!
   (-[det]-> ForwardAggregateMaintenance
       (Statement KBContext Proof TV) (List $none)))
(= (forward-maintain-member-aggregates! $maintenance $fact)
   (case $fact (
      (((Member $_obj $class) ($kbid MAIN Nil) $_proof $_tv)
         (collapse
            (forward-maintain-aggregates-for-key!
               $maintenance $fact
               (fwd_member
                  (brand KB $kbid) (brand Term $class)))))
      ($_other ()))))

(: forward-bump-member-aggregate-revisions!
   (-[det]-> KB Term (List $none)))
(= (forward-bump-member-aggregate-revisions! $kbid $class)
   (let* (($trigger (fwd_member $kbid $class))
          ($hash (term_hash $trigger))
          ($_
            (collapse
               (match &forward_aggregate_interest_by_trigger
                  ($hash
                     (forward-aggregate-interest
                        $stored-trigger $_id
                        (forward-member-inheritance-descriptor
                           $stored-kbid $_subj $_concept $pattern)))
                  (if (== $stored-trigger $trigger)
                     (let $_revision
                        (bump-aggregate-revision!
                           (base-rate-aggregate-identity
                              $stored-kbid $pattern
                              (member-inheritance $stored-kbid)))
                        ())
                     (empty))))))
      ()))

(: forward-maintain-aggregates!
   (-[det]-> ForwardAggregateMaintenance
       (Statement KBContext Proof TV) (List $none)))
(= (forward-maintain-aggregates! $maintenance $fact)
   (let*
      (($trigger (forward-premise-index-key $fact))
       ($wildcard (forward-premise-wildcard-key $fact))
       ($_direct
          (collapse
             (forward-maintain-aggregates-for-key!
                $maintenance $fact $trigger)))
       ($_wildcard
          (if (== $trigger $wildcard) ()
             (collapse
                (forward-maintain-aggregates-for-key!
                   $maintenance $fact $wildcard))))
       ($_member
          (forward-maintain-member-aggregates!
             $maintenance $fact)))
      ()))

;; Knowledge insertion already refreshes the canonical fact. Update only the
;; affected Member join, not ordinary base-rate folds which remain lazy until
;; a forward run processes the fact.
(: forward-apply-unqueued-member-change!
   (-[det]-> ForwardOutputChange (List $none)))
(= (forward-apply-unqueued-member-change! $change)
   (case $change (
      (no-forward-change ())
      ((forward-output-added $fact)
         (forward-maintain-member-aggregates!
            aggregate-update $fact))
      ((forward-output-replaced $_old $fact)
         (forward-maintain-member-aggregates!
            aggregate-update $fact))
      ((forward-output-removed $_old) ()))))

(: forward-invalidate-base-rates-for-key!
   (-[nondet]-> (Statement KBContext Proof TV)
      ForwardTriggerKey  (List $none)))
(= (forward-invalidate-base-rates-for-key! $fact $trigger)
   (let $trigger-hash (term_hash $trigger)
      (match &forward_aggregate_interest_by_trigger
         ($trigger-hash
            (forward-aggregate-interest
               $stored-trigger $_id
               (forward-base-rate-descriptor
                  $kbid $pattern $_extractor $_init $_fun $finish)))
         (if (== $stored-trigger $trigger)
            (base-rate-cache-remove-derived!
               $kbid (copy_term $pattern) $finish)
            (empty)))))

(: forward-invalidate-base-rates! (-[det]-> (Statement KBContext Proof TV) (List $none)))
(= (forward-invalidate-base-rates! $fact)
   (let*
      (($trigger (forward-premise-index-key $fact))
       ($wildcard (forward-premise-wildcard-key $fact))
       ($_direct
          (collapse (forward-invalidate-base-rates-for-key! $fact $trigger)))
      ($_wildcard
          (if (== $trigger $wildcard) ()
             (collapse
                (forward-invalidate-base-rates-for-key! $fact $wildcard)))))
      ()))
