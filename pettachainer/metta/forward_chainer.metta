!(import_prolog_function nth0)

;; nth0/4 removes the indexed element while unifying it with its third
;; argument. Its relational modes can branch, but every result preserves the
;; element type of the input list.
(: nth0
   (-[nondet]-> $index (List $item) $item (List $item)))

(: term_hash (-[det]-> $expression Number))

(: ForwardMemberInheritanceIdentityKey Type)
(: fwd_member_identity
   (-[det]-> KB Term Term ForwardMemberInheritanceIdentityKey))

(: ForwardMemberInheritanceIdentityRow Type)
(: forward-member-inheritance-identity-row
   (-[det]-> ForwardMemberInheritanceIdentityKey Number
       ForwardMemberInheritanceIdentityRow))

(: ForwardOutputCandidate Type)
(: forward-output-candidate
   (-[det]-> (Statement KBContext Proof TV)
       (List Evidence) ForwardOutputCandidate))

(: NoForwardOutputCandidate Type)
(: no-forward-output-candidate NoForwardOutputCandidate)

(: ForwardOutputKey Type)
(: forward-output-key
   (-[det]-> KBContext Statement ForwardOutputKey))

(: ForwardOutputRow Type)
(: forward-output-row
   (-[det]-> (Statement KBContext Proof TV) (List Evidence) ForwardOutputRow))

(: ForwardFrontierRow Type)
(: forward-frontier-row
   (-[det]-> Number Statement KBContext
       (Statement KBContext Proof TV)
       (List Evidence)
       ForwardFrontierRow))

(: first-forward-output-row
   (-[det]-> (List ForwardOutputRow) ForwardOutputRow))
(= (first-forward-output-row (cons $row $_rest)) $row)

;; Dynamic-space collection erases both the list element type and the row's
;; constructor roles. Iterate that representation directly and reconstruct one
;; typed row at a time, avoiding a reflective check of the complete list.
(: emit-stored-forward-output-rows
   (-[nondet]-> Atom ForwardOutputRow))
(= (emit-stored-forward-output-rows
      (cons
         (forward-output-row
            $fact $evidence)
         $_rest))
   (forward-output-row
      $fact
      (stored-evidence-list $evidence)))
(= (emit-stored-forward-output-rows
      (cons $_row $rest))
   (emit-stored-forward-output-rows $rest))

(: ForwardCanonicalEvidenceRow Type)
(: forward-canonical-evidence-row
   (-[det]-> Number Statement KBContext
       (Statement KBContext Proof TV)
       (List Evidence)
       ForwardCanonicalEvidenceRow))

(: ForwardBaseRateInterestRow Type)
(: forward-base-rate-interest-row
   (-[det]-> ForwardTriggerKey Number KB Statement
       (| ExtractTV ExtractInheritanceTV)
       (| BaseRateEvidenceState BaseRateEvidenceWithPriorState)
       (-[semidet]-> $accumulator $value $accumulator)
       (| BaseRateFinish
          WeightedBaseRateInUniverseFinish
          WeightedBaseRateWithPriorInUniverseFinish)
       AggregateTVMode
       ForwardBaseRateInterestRow))

(: ForwardMemberInheritanceInterestRow Type)
(: forward-member-inheritance-interest-row
   (-[det]-> ForwardTriggerKey Number KB Term Term Statement
       ForwardMemberInheritanceInterestRow))

(: ForwardBaseRateState Type)
(: forward-base-rate-state
   (-[det]-> Number Number Number ForwardBaseRateState))

(: ForwardBaseRateObservationKey (Newtype Atom))

(: ForwardMemberInheritanceObservationKey
   (Newtype Atom))

(: ForwardOutputChange Type)
(: no-forward-change ForwardOutputChange)
(: forward-output-added
   (-[det]-> (Statement KBContext Proof TV) ForwardOutputChange))
(: forward-output-removed
   (-[det]-> (Statement KBContext Proof TV) ForwardOutputChange))
(: forward-output-replaced
   (-[det]-> (Statement KBContext Proof TV)
       (Statement KBContext Proof TV)
       ForwardOutputChange))

(: ForwardQueueItem (Newtype Atom))
(: qitem (-[det]-> (Statement KBContext Proof TV) ForwardQueueItem))

;; Total wrapper around SWI's relational heap pop. The foreign predicate binds
;; priority and item through output arguments, which ordinary MeTTa arrows
;; cannot express directly.
(: ForwardAgendaPop Type)
(: no-forward-agenda-pop ForwardAgendaPop)
(: forward-agenda-pop (-[det]-> (Heap ForwardQueueItem) ForwardQueueItem ForwardAgendaPop))

(: forward-pop-agenda (-[det]-> (Heap ForwardQueueItem) ForwardAgendaPop))
(= (forward-pop-agenda $agenda)
   (let $pops
      (collapse
         (once
            (let ($_priority $item $rest)
               (heap_pop $agenda)
               (forward-agenda-pop
                  $rest $item))))
      (if (== $pops ())
         no-forward-agenda-pop
         (car-atom $pops))))

(: ForwardRun
   (Alias ((Heap ForwardQueueItem) (List ForwardOutputKey))))

(: forward-type-trigger-key (-[det]-> KB Statement ForwardTriggerKey))
(= (forward-type-trigger-key $kbid $type)
   (if (is-var $type) (fwd_trigger $kbid any)
      (if (is-expr $type)
         (let $head (car-atom $type) (if (is-var $head) (fwd_trigger $kbid any) (fwd_trigger $kbid $head)))
         (fwd_trigger $kbid $type))))

(: forward-indexable-premise-key
   (-[det]-> (| Goal (Statement KBContext Proof TV))
       (| ForwardTriggerKey (List $no-key))))
(= (forward-indexable-premise-key $prem)
   (once
      (if (= $prem ($_type ($kbid $_ctx $_vars) $_prf $_tv))
         (forward-type-trigger-key
            (brand KB $kbid) (brand Statement $_type))
         ())))

(: forward-premise-index-key
   (-[det]-> (| Goal (Statement KBContext Proof TV))
       ForwardTriggerKey))
(= (forward-premise-index-key $prem)
   (once
      (if (= $prem ($_type ($kbid $_ctx $_vars) $_prf $_tv))
         (forward-type-trigger-key
            (brand KB $kbid) (brand Statement $_type))
         fwd_trigger_any)))

(: forward-premise-wildcard-key
   (-[det]-> (| Goal (Statement KBContext Proof TV))
       ForwardTriggerKey))
(= (forward-premise-wildcard-key $prem)
   (once
      (if (= $prem ($_type ($kbid $_ctx $_vars) $_prf $_tv))
         (fwd_trigger (brand KB $kbid) any)
         fwd_trigger_any)))

(: forward-fact-key
   (-[det]-> (Statement KBContext Proof TV) ForwardOutputKey))
(= (forward-fact-key ($type ($kbid $ctx $vars) $_prf $_tv))
   (forward-output-key
      (brand KBContext (quote ($kbid $ctx $vars)))
      $type))
(: forward-fact-kb
   (-[det]-> (Statement KBContext Proof TV) KB))
(= (forward-fact-kb ($_type ($kbid $_ctx $_vars) $_prf $_tv))
   $kbid)
(: forward-output-index-hash (-[det]-> ForwardOutputKey Number))
(= (forward-output-index-hash (forward-output-key $kb $type))
   (term_hash (quote ($kb $type))))

(: forward-output-candidate-step
   (-[det]-> (| ForwardOutputCandidate NoForwardOutputCandidate)
       ForwardFrontierRow
       ForwardOutputCandidate))
(= (forward-output-candidate-step
      no-forward-output-candidate
      (forward-frontier-row
         $_hash $_type $_kb $fact $ev))
   (forward-output-candidate $fact $ev))
(= (forward-output-candidate-step
      (forward-output-candidate $current $current-ev)
      (forward-frontier-row
         $_hash $_type $_kb $fact $ev))
   (let $merged-state
      (merge-proof-candidates
         (proof-candidate-pair $current $current-ev)
         (proof-candidate-pair $fact $ev))
      (forward-output-candidate
         (fst $merged-state)
         (snd $merged-state))))

(: forward-output-candidate-for-key
   (-[det]-> ForwardOutputKey
       (| ForwardOutputCandidate NoForwardOutputCandidate)))
(= (forward-output-candidate-for-key
      (forward-output-key $kb $type))
   (let $hash
      (forward-output-index-hash
         (forward-output-key $kb $type))
      (fold-flat
         forward-output-candidate-step no-forward-output-candidate
         (collapse
            (match &forward_frontier
               (forward-frontier-row
                  $hash $type $kb $fact $ev)
               (forward-frontier-row
                  $hash $type $kb $fact $ev))))))

(: forward-remove-canonical-fact!
   (-[det]-> (Statement KBContext Proof TV) Bool))
(= (forward-remove-canonical-fact! $fact) (remove-atom &kb $fact))
(: forward-remove-canonical-evidence!
   (-[det]-> ForwardCanonicalEvidenceRow Bool))
(= (forward-remove-canonical-evidence! $row)
   (remove-atom &forward_canonical_evidence $row))

(: forward-candidate-from-canonical-rows
   (-[det]-> (List ForwardCanonicalEvidenceRow)
       (| ForwardOutputCandidate NoForwardOutputCandidate)))
(= (forward-candidate-from-canonical-rows $rows)
   (case $rows
      ((() no-forward-output-candidate)
       ((cons
          (forward-canonical-evidence-row
             $_hash $_type $_kb $fact $evidence)
          $_rest)
        (forward-output-candidate $fact $evidence)))))

;; &kb contains one canonical fact per grounded output.  The private frontier
;; keeps only the independent, non-dominated candidates required to update that
;; canonical fact when later evidence supersedes just one branch.  Exact-map
;; rows start with a hash of the complete output identity, followed by that
;; identity so unification still rejects the rare hash collision.
(: forward-replace-output-candidate!
   (-[nondet]-> Number Statement KBContext
      (Statement KBContext Proof TV) (List Evidence)
      (Statement KBContext Proof TV) (List Evidence)
      (List ForwardCanonicalEvidenceRow)
       ForwardOutputChange))
(= (forward-replace-output-candidate!
      $hash $type $kb $new-fact $new-ev $old-fact $old-ev
      $old-evidence-rows)
   (if (and
         (== $old-fact $new-fact)
         (== $old-ev $new-ev))
      no-forward-change
      (let*
         (($_remove-fact
              (forward-remove-canonical-fact! $old-fact))
          ($_remove-evidence
              (foreach-flat
                 forward-remove-canonical-evidence!
                 $old-evidence-rows))
          ($_add-fact
              (chainer-add-atom &kb $new-fact))
          ($_add-evidence
              (add-atom &forward_canonical_evidence
                 (forward-canonical-evidence-row
                    $hash $type $kb $new-fact $new-ev))))
         (forward-output-replaced $old-fact $new-fact))))

(: forward-add-output-candidate!
   (-[nondet]-> Number Statement KBContext
      (Statement KBContext Proof TV) (List Evidence)
       ForwardOutputChange))
(= (forward-add-output-candidate!
      $hash $type $kb $new-fact $new-ev)
   (let*
      (($_add-fact
           (chainer-add-atom &kb $new-fact))
       ($_add-evidence
           (add-atom &forward_canonical_evidence
              (forward-canonical-evidence-row
                 $hash $type $kb $new-fact $new-ev))))
      (forward-output-added $new-fact)))

(: forward-remove-output-candidate!
   (-[nondet]-> (Statement KBContext Proof TV)
      (List ForwardCanonicalEvidenceRow)
       ForwardOutputChange))
(= (forward-remove-output-candidate! $old-fact $old-evidence-rows)
   (let*
      (($_remove-fact
           (forward-remove-canonical-fact! $old-fact))
       ($_remove-evidence
           (foreach-flat
              forward-remove-canonical-evidence!
              $old-evidence-rows)))
      (forward-output-removed $old-fact)))

(: forward-store-output-candidate!
   (-[nondet]-> ForwardOutputKey
      (| ForwardOutputCandidate NoForwardOutputCandidate)
       ForwardOutputChange))
(= (forward-store-output-candidate!
      (forward-output-key $kb $type) $new-candidate)
   (let*
      (($hash
          (forward-output-index-hash
             (forward-output-key $kb $type)))
       ($old-evidence-rows
          (collapse
             (match &forward_canonical_evidence
                (forward-canonical-evidence-row
                   $hash $type $kb $stored-fact $stored-ev)
                (forward-canonical-evidence-row
                   $hash $type $kb $stored-fact $stored-ev))))
       ($old-candidate
          (forward-candidate-from-canonical-rows
             $old-evidence-rows)))
      (case $new-candidate
         (((forward-output-candidate $new-fact $new-ev)
            (case $old-candidate
               (((forward-output-candidate $old-fact $old-ev)
                  (forward-replace-output-candidate!
                     $hash $type $kb
                     $new-fact $new-ev $old-fact $old-ev
                     $old-evidence-rows))
                (no-forward-output-candidate
                   (forward-add-output-candidate!
                      $hash $type $kb $new-fact $new-ev)))))
          (no-forward-output-candidate
             (case $old-candidate
                ((no-forward-output-candidate no-forward-change)
                 ((forward-output-candidate $old-fact $_old-ev)
                    (forward-remove-output-candidate!
                       $old-fact $old-evidence-rows)))))))))

(: forward-refresh-output-key!
   (-[nondet]-> ForwardOutputKey  ForwardOutputChange))
(= (forward-refresh-output-key! $key)
   (forward-store-output-candidate!
      $key (forward-output-candidate-for-key $key)))

(: forward-output-row-for-fact
   (-[semidet]-> (Statement KBContext Proof TV) ForwardOutputRow))
(= (forward-output-row-for-fact ($type $kb $proof $tv))
   (let*
      (($hash (term_hash (quote ($kb $type)))))
      (once
         (match &forward_canonical_evidence
            (forward-canonical-evidence-row
               $hash $type $kb $canonical $ev)
            (forward-output-row $canonical $ev)))))

;; Compiler-generated base-rate folds all reduce to additive evidence totals.
;; Keep those totals for forward-processed canonical outputs so each changed
;; output costs one subtraction and one addition instead of another graph fold.
(: forward-base-rate-supported?
   (-[det]-> (| ExtractTV ExtractInheritanceTV)
       (-[semidet]-> $accumulator $value $accumulator)
       Bool))
(= (forward-base-rate-supported? $extractor $fun)
   (case $fun (
      (BaseRateAcc (== $extractor extract-tv))
      (WeightedBaseRateAcc
         (if (= $extractor (extract-inheritance-tv $_kbid $_pattern)) true false))
      (WeightedBaseRateWithPriorAcc
         (if (= $extractor (extract-inheritance-tv $_kbid $_pattern)) true false))
      ($_other false))))

(: forward-register-base-rate!
   (-[det]-> KB Statement
       (| ExtractTV ExtractInheritanceTV)
       $accumulator
       (-[semidet]-> $accumulator $value $accumulator)
       (| BaseRateFinish
          WeightedBaseRateInUniverseFinish
          WeightedBaseRateWithPriorInUniverseFinish)
       AggregateTVMode
       (List $none)))
(= (forward-register-base-rate!
      $kbid $pattern $extractor $init $fun $finish $tv-mode)
   (if (forward-base-rate-supported? $extractor $fun)
      (let*
         (($trigger (forward-type-trigger-key $kbid $pattern))
          ($hits
             (collapse
                (once
                   (match &forward_base_rate_interest
                      (forward-base-rate-interest-row
                         $trigger $stored-id $kbid $stored-pattern
                         $stored-extractor $stored-init
                         $fun $finish $tv-mode)
                      (if (and (=alpha $stored-pattern $pattern)
                               (=alpha
                                  (quote ($stored-extractor $stored-init))
                                  (quote ($extractor $init))))
                         $stored-id
                         (empty)))))))
         (if (== $hits ())
            (let*
               (($id (next-search-id fwd_br_id))
                ($stored (copy_term (quote ($pattern $extractor $init))))
                ($stored-pattern (car-atom $stored))
                ($stored-extractor (car-atom (cdr-atom $stored)))
                ($stored-init
                   (car-atom (cdr-atom (cdr-atom $stored))))
                ($_interest
                   (once
                      (add-atom &forward_base_rate_interest
                         (forward-base-rate-interest-row
                            $trigger $id $kbid $stored-pattern
                            $stored-extractor $stored-init
                            $fun $finish $tv-mode))))
                ($_state
                   (once
                      (add-atom &forward_base_rate_state
                         (forward-base-rate-state
                            $id 0.0 0.0)))))
               ())
            ()))
      ()))

(: forward-register-base-rate-premise!
   (-[det]-> (| Goal (Statement KBContext Proof TV))
       (List $none)))
(= (forward-register-base-rate-premise! $premise)
   (case $premise (
      ((CPU FoldAllCompiled
          ($kbid $pattern extract-tv
             (BaseRateEvidence $initial-weight $initial-count)
             BaseRateAcc base-rate result-tv)
          $_result)
         (forward-register-base-rate!
            (brand KB $kbid) (brand Statement $pattern)
            extract-tv
            (BaseRateEvidence $initial-weight $initial-count)
            BaseRateAcc base-rate result-tv))
      ((CPU FoldAllCompiled
          ($kbid $pattern
             (extract-inheritance-tv $extract-kb $extract-pattern)
             (BaseRateEvidence $initial-weight $initial-count)
             WeightedBaseRateAcc
             (weighted-base-rate-in-universe $finish-kb)
             result-tv)
          $_result)
         (forward-register-base-rate!
            (brand KB $kbid) (brand Statement $pattern)
            (extract-inheritance-tv
               (brand KB $extract-kb)
               (brand Statement $extract-pattern))
            (BaseRateEvidence $initial-weight $initial-count)
            WeightedBaseRateAcc
            (weighted-base-rate-in-universe
               (brand KB $finish-kb))
            result-tv))
      ((CPU FoldAllCompiled
          ($kbid $pattern
             (extract-inheritance-tv $extract-kb $extract-pattern)
             (BaseRateEvidenceWithPrior $prior
                (BaseRateEvidence $initial-weight $initial-count))
             WeightedBaseRateWithPriorAcc
             (weighted-base-rate-with-prior-in-universe $finish-kb)
             result-tv)
          $_result)
         (forward-register-base-rate!
            (brand KB $kbid) (brand Statement $pattern)
            (extract-inheritance-tv
               (brand KB $extract-kb)
               (brand Statement $extract-pattern))
            (BaseRateEvidenceWithPrior
               (brand BaseRatePrior $prior)
               (BaseRateEvidence $initial-weight $initial-count))
            WeightedBaseRateWithPriorAcc
            (weighted-base-rate-with-prior-in-universe
               (brand KB $finish-kb))
            result-tv))
      ($_other ()))))

(: register-forward-base-rate-premises!
   (-[det]-> (List (| Goal (Statement KBContext Proof TV))) (List $none)))
(= (register-forward-base-rate-premises! $premises)
   (foreach-flat forward-register-base-rate-premise! $premises))

;; compile-inheritance-query emits this one two-sided fold shape.  Register it
;; separately from ordinary base rates: its contribution is keyed by the
;; shared Member object and must be recomputed from both canonical outputs.
(: forward-register-member-inheritance-premise!
   (-[det]-> (| Goal (Statement KBContext Proof TV))
       (List $none)))
(= (forward-register-member-inheritance-premise! $premise)
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
            (($pattern
                (MemberInheritanceSample $obj $subj $concept $atv $btv))
             ($key
                (fwd_member_identity
                   (brand KB $kbid)
                   (brand Term $subj)
                   (brand Term $concept)))
             ($hits
                (collapse
                   (once
                      (match &forward_member_inheritance_identity
                         (forward-member-inheritance-identity-row
                            $key $stored-id)
                         $stored-id)))))
            (if (== $hits ())
               (let*
                  (($id (next-search-id fwd_member_inheritance_id))
                   ($stored (copy_term (quote ($pattern $subj $concept))))
                   ($stored-pattern (car-atom $stored))
                   ($stored-subj (car-atom (cdr-atom $stored)))
                   ($stored-concept
                      (car-atom (cdr-atom (cdr-atom $stored))))
                   ($typed-stored-subj
                      (brand Term $stored-subj))
                   ($typed-stored-concept
                      (brand Term $stored-concept))
                   ($typed-stored-pattern
                      (brand Statement $stored-pattern))
                   ($_identity
                      (once
                         (add-atom &forward_member_inheritance_identity
                            (forward-member-inheritance-identity-row
                               $key $id))))
                   ($_subject
                      (once
                         (add-atom &forward_member_inheritance_interest
                            (forward-member-inheritance-interest-row
                               (fwd_member $kbid $stored-subj)
                               $id $kbid
                               $typed-stored-subj
                               $typed-stored-concept
                               $typed-stored-pattern))))
                   ($_concept
                      (if (== $stored-subj $stored-concept) ()
                         (once
                            (add-atom &forward_member_inheritance_interest
                               (forward-member-inheritance-interest-row
                                  (fwd_member $kbid $stored-concept)
                                  $id $kbid
                                  $typed-stored-subj
                                  $typed-stored-concept
                                  $typed-stored-pattern)))))
                   ($_state
                      (once
                         (add-atom &forward_member_inheritance_state
                            (forward-member-inheritance-state
                               $id 0.0 0.0)))))
                  ())
               ()))
               ())
            ()))
      ($_other ()))))

(: register-forward-member-inheritance-premises!
   (-[det]-> (List (| Goal (Statement KBContext Proof TV))) (List $none)))
(= (register-forward-member-inheritance-premises! $premises)
   (foreach-flat forward-register-member-inheritance-premise! $premises))

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

(: forward-store-base-rate-state!
   (-[det]-> Number Number Number Number Number Bool))
(= (forward-store-base-rate-state! $id $old-wsum $old-csum $wsum $csum)
   (progn
      (once
         (remove-atom &forward_base_rate_state
            (forward-base-rate-state
               $id $old-wsum $old-csum)))
      (once
         (add-atom &forward_base_rate_state
            (forward-base-rate-state $id $wsum $csum)))))

(: forward-base-rate-state-by-id
   (-[semidet]-> Number ForwardBaseRateState))
(= (forward-base-rate-state-by-id $id)
   (once
      (match &forward_base_rate_state
         (forward-base-rate-state $id $wsum $csum)
         (forward-base-rate-state $id $wsum $csum))))

(: ForwardBaseRateObservation
   (-[det]-> ForwardBaseRateObservationKey
       (Statement KBContext Proof TV)
       Number Number ForwardBaseRateObservation))

(: forward-remove-base-rate-observation!
   (-[det]-> ForwardBaseRateObservation (| Bool (List $none))))
(= (forward-remove-base-rate-observation! $observation)
   (once
      (remove-atom &forward_base_rate_observation $observation)))

(: forward-store-base-rate-observation!
   (-[det]-> ForwardBaseRateObservationKey
       (List ForwardBaseRateObservation)
       (Statement KBContext Proof TV) Number Number Bool))
(= (forward-store-base-rate-observation!
      $observation-key $old-observations $fact $weight $count)
   (progn
      (foreach-flat
         forward-remove-base-rate-observation!
         $old-observations)
      (once
         (add-atom &forward_base_rate_observation
            (ForwardBaseRateObservation
               $observation-key $fact $weight $count)))))

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

(: forward-update-base-rate-interest
   (-[semidet]-> (Statement KBContext Proof TV) Number KB Statement
       (| ExtractTV ExtractInheritanceTV)
       (| BaseRateEvidenceState BaseRateEvidenceWithPriorState)
       (-[semidet]-> $accumulator $value $accumulator)
       (| BaseRateFinish
          WeightedBaseRateInUniverseFinish
          WeightedBaseRateWithPriorInUniverseFinish)
       (List $none)))
(= (forward-update-base-rate-interest
      $fact $id $kbid $pattern $extractor $init $fun $finish)
   (let*
      (($cache-pattern (copy_term $pattern))
       (($type ($fact-kbid $_ctx $_vars) $_proof $tv)
          (copy_term $fact))
       ;; The trigger key already includes the KB, so this row cannot have
       ;; come from another knowledge base. Avoid re-unifying the nominal KB
       ;; value through the erased KBContext representation.
       ($_pattern (let $pattern $type ok))
       ($output-key (forward-fact-key $fact))
       ($observation-key
          (brand ForwardBaseRateObservationKey
             (quote ($id $output-key))))
       ($old-observations
          (collapse
             (match &forward_base_rate_observation
                (ForwardBaseRateObservation
                   $observation-key $old-fact $old-weight $old-count)
                (ForwardBaseRateObservation
                   $observation-key $old-fact $old-weight $old-count))))
       ($old-values
          (if (== $old-observations ()) (quote (0.0 0.0))
             (let (cons
                     (ForwardBaseRateObservation
                        $_old-key $_old-fact $ow $oc)
                     $_rest)
                $old-observations
                (quote ($ow $oc)))))
       ($old-weight (fst $old-values))
       ($old-count (snd $old-values))
       ((BaseRateEvidence $weight $count)
          (forward-positive-base-rate-contribution $tv))
       ((forward-base-rate-state
            $_stored-id $old-wsum $old-csum)
          (forward-base-rate-state-by-id $id))
       ($wsum (+ (- $old-wsum $old-weight) $weight))
       ($csum (+ (- $old-csum $old-count) $count))
       ($_state
          (forward-store-base-rate-state!
             $id $old-wsum $old-csum $wsum $csum))
       ($_observation
          (forward-store-base-rate-observation!
             $observation-key $old-observations $fact $weight $count))
       ($acc
             (forward-base-rate-accumulator
                $kbid
                $extractor $init $fun $wsum $csum))
       ($estimate
          (forward-finish-stored-aggregate $finish $acc))
       ($_cache
          (store-forward-base-rate!
             $kbid $cache-pattern $estimate $finish)))
      ()))

(: forward-update-base-rates-for-key
   (-[nondet]-> (Statement KBContext Proof TV) ForwardTriggerKey  (List $none)))
(= (forward-update-base-rates-for-key $fact $trigger)
   (match &forward_base_rate_interest
      (forward-base-rate-interest-row
         $trigger $id $kbid $pattern
         $extractor $init $fun $finish $_tv-mode)
      (forward-update-base-rate-interest
         $fact $id
         $kbid (copy_term $pattern)
         $extractor $init $fun $finish)))

(: forward-update-base-rates
   (-[det]-> (Statement KBContext Proof TV) (List $none)))
(= (forward-update-base-rates $fact)
   (let*
      (($kbid (forward-fact-kb $fact))
       ($trigger (forward-premise-index-key $fact))
       ($wildcard (forward-premise-wildcard-key $fact))
       ($_direct (collapse (forward-update-base-rates-for-key $fact $trigger)))
       ($_wildcard
          (if (== $trigger $wildcard) ()
             (collapse (forward-update-base-rates-for-key $fact $wildcard)))))
      ()))

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

(: forward-store-member-inheritance-state!
   (-[det]-> Number Number Number Number Number Bool))
(= (forward-store-member-inheritance-state!
      $id $old-wsum $old-msum $wsum $msum)
   (progn
      (once
         (remove-atom &forward_member_inheritance_state
            (forward-member-inheritance-state
               $id $old-wsum $old-msum)))
      (once
         (add-atom &forward_member_inheritance_state
            (forward-member-inheritance-state
               $id $wsum $msum)))))

(: ForwardMemberInheritanceObservation
   (-[det]-> ForwardMemberInheritanceObservationKey
       ForwardOutputCandidate ForwardOutputCandidate Number Number
       ForwardMemberInheritanceObservation))

(: forward-remove-member-inheritance-observation!
   (-[det]-> ForwardMemberInheritanceObservation
       (| Bool (List $none))))
(= (forward-remove-member-inheritance-observation! $observation)
   (once
      (remove-atom
         &forward_member_inheritance_observation $observation)))

(: ForwardMemberInheritanceState Type)
(: forward-member-inheritance-state
   (-[det]-> Number Number Number ForwardMemberInheritanceState))

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

(: forward-member-inheritance-empty-cache-hit?
   (-[det]-> KB Term Term Number Bool))
(= (forward-member-inheritance-empty-cache-hit?
      $kbid $subj $concept $budget)
   (not
      (==
         (collapse
            (once
               (match &forward_member_inheritance_identity
                  (forward-member-inheritance-identity-row
                     (fwd_member_identity $kbid $subj $concept) $id)
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
         (match &forward_member_inheritance_identity
            (forward-member-inheritance-identity-row
               (fwd_member_identity $kbid $subj $concept) $id)
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
         (store-computed-base-rate!
            $kbid $pattern $tv (member-inheritance $kbid))
         (store-forward-base-rate!
            $kbid $pattern $tv (member-inheritance $kbid)))))

;; Backward folds have already resolved proof overlap and dominance before
;; exposing their child snapshots. Replace the matching object's component,
;; while retaining objects absent from a bounded computed pass.
(: forward-merge-computed-member-observation!
   (-[semidet]-> Number ForwardMemberInheritanceObservation (List $none)))
(= (forward-merge-computed-member-observation!
      $id
      (ForwardMemberInheritanceObservation
         $key $subject $concept $weight $mass))
   (let*
      (($old-observations
          (collapse
             (match &forward_member_inheritance_observation
                (ForwardMemberInheritanceObservation
                   $key $old-subject $old-concept $old-weight $old-mass)
                (ForwardMemberInheritanceObservation
                   $key $old-subject $old-concept $old-weight $old-mass))))
       ((forward-member-inheritance-state
            $_state-id $old-wsum $old-msum)
          (once
             (match &forward_member_inheritance_state
                (forward-member-inheritance-state
                   $id $stored-wsum $stored-msum)
                (forward-member-inheritance-state
                   $id $stored-wsum $stored-msum))))
       ($new-observation
          (ForwardMemberInheritanceObservation
             $key $subject $concept $weight $mass)))
      (if (== $old-observations ())
         (let*
            (($_state
                (forward-store-member-inheritance-state!
                   $id $old-wsum $old-msum
                   (+ $old-wsum $weight) (+ $old-msum $mass)))
             ($_observation
                (once
                   (add-atom &forward_member_inheritance_observation
                      $new-observation))))
            ())
         (let $old-observation (car-atom $old-observations)
            (let
               (ForwardMemberInheritanceObservation
                  $_old-key $_old-subject $_old-concept
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
                               (forward-store-member-inheritance-state!
                                  $id $old-wsum $old-msum
                                  (+ (- $old-wsum $old-weight) $weight)
                                  (+ (- $old-msum $old-mass) $mass)))
                            ($_old
                               (foreach-flat
                                  forward-remove-member-inheritance-observation!
                                  $old-observations))
                            ($_new
                               (once
                                  (add-atom
                                     &forward_member_inheritance_observation
                                     $new-observation))))
                           ())))))))))

(: forward-mark-member-inheritance-computed!
   (-[det]-> Number (| Bool (List $none))))
(= (forward-mark-member-inheritance-computed! $id)
   (once
      (add-atom &forward_member_inheritance_computed
         (forward-member-inheritance-computed-row $id))))

(: forward-update-member-inheritance-interest
   (-[semidet]-> Term Number KB Term Term Statement (List $none)))
(= (forward-update-member-inheritance-interest
      $obj $id $kbid $subj $concept $pattern)
   (let*
      (($observation-key
          (brand ForwardMemberInheritanceObservationKey
             (quote ($id $obj))))
       ($old-observations
          (collapse
             (match &forward_member_inheritance_observation
                (ForwardMemberInheritanceObservation
                   $observation-key $old-subject $old-concept
                   $old-weight $old-mass)
                (ForwardMemberInheritanceObservation
                   $observation-key $old-subject $old-concept
                   $old-weight $old-mass))))
       (($old-weight $old-mass)
          (if (== $old-observations ())
             (data 0.0 0.0)
             (let
                (ForwardMemberInheritanceObservation
                   $_key $_asubj $_aconcept $old-weight $old-mass)
                (car-atom $old-observations)
                (data $old-weight $old-mass))))
       ($subject (forward-member-canonical $kbid $obj $subj))
       ($consequent (forward-member-canonical $kbid $obj $concept))
       (($weight $mass)
          (if (or
                (== $subject no-forward-output-candidate)
                (== $consequent no-forward-output-candidate))
             (data 0.0 0.0)
             (let*
                (((forward-output-candidate
                     $subject-fact $_subject-ev)
                    $subject)
                 ((forward-output-candidate
                     $consequent-fact $_consequent-ev)
                    $consequent)
                 (($_stype $_skb $_sprf $atv) $subject-fact)
                 (($_ctype $_ckb $_cprf $btv) $consequent-fact)
                 ((BaseRateEvidence $joined-weight $joined-mass)
                    (forward-weighted-base-rate-contribution
                       $atv $btv)))
                (data
                   $joined-weight $joined-mass))))
       ((forward-member-inheritance-state
            $_state-id $old-wsum $old-msum)
          (once
             (match &forward_member_inheritance_state
                (forward-member-inheritance-state
                   $id $stored-wsum $stored-msum)
                (forward-member-inheritance-state
                   $id $stored-wsum $stored-msum))))
       ($wsum (+ (- $old-wsum $old-weight) $weight))
       ($msum (+ (- $old-msum $old-mass) $mass))
       ($_state
          (forward-store-member-inheritance-state!
             $id $old-wsum $old-msum $wsum $msum))
       ($_old
          (foreach-flat
             forward-remove-member-inheritance-observation!
             $old-observations))
       ($_observation
          (if (or
                (== $subject no-forward-output-candidate)
                (== $consequent no-forward-output-candidate))
             ()
             (once
                (add-atom &forward_member_inheritance_observation
                   (ForwardMemberInheritanceObservation
                      $observation-key $subject $consequent
                      $weight $mass)))))
       ($_cache
          (if (<= $msum 0.0)
             (base-rate-cache-remove-derived!
                $kbid $pattern (member-inheritance $kbid))
             (forward-store-member-inheritance-cache!
                $id $kbid $pattern
                (member-inheritance-tv $kbid
                   (BaseRateEvidence $wsum $msum))))))
      ()))

(: forward-update-member-inheritances-for-key
   (-[det]-> KB Term Term (List $none)))
(= (forward-update-member-inheritances-for-key $kbid $obj $class)
   (let $_
      (collapse
         (match &forward_member_inheritance_interest
            (forward-member-inheritance-interest-row
               $stored-trigger $id $stored-kbid
               $subj $concept $pattern)
            (if (and (== $stored-kbid $kbid)
                     (== $stored-trigger
                         (quote (fwd_member $kbid $class))))
               (forward-update-member-inheritance-interest
                  $obj $id $kbid
                  $subj $concept (copy_term $pattern))
               (empty))))
      ()))

(: forward-remove-member-inheritance-observation!
   (-[semidet]-> Term Number KB Term Term Statement (List $none)))
(= (forward-remove-member-inheritance-observation!
      $obj $id $kbid $subj $concept $pattern)
   (let*
      (($observation-key
          (brand ForwardMemberInheritanceObservationKey
             (quote ($id $obj))))
       ($old-observations
          (collapse
             (match &forward_member_inheritance_observation
                (ForwardMemberInheritanceObservation
                   $observation-key $old-subject $old-concept
                   $old-weight $old-mass)
                (ForwardMemberInheritanceObservation
                   $observation-key $old-subject $old-concept
                   $old-weight $old-mass)))))
      (if (== $old-observations ())
         ;; Removal invalidation may run after the canonical-change hook has
         ;; already subtracted this row. Republish the surviving indexed state
         ;; without touching ordinary base-rate cache behavior.
         (let*
            (((forward-member-inheritance-state
                  $_state-id $wsum $msum)
               (once
                  (match &forward_member_inheritance_state
                     (forward-member-inheritance-state
                        $id $stored-wsum $stored-msum)
                     (forward-member-inheritance-state
                        $id $stored-wsum $stored-msum)))))
               (if (<= $msum 0.0) ()
                  (forward-store-member-inheritance-cache!
                     $id $kbid $pattern
                     (member-inheritance-tv $kbid
                        (BaseRateEvidence
                           $wsum $msum)))))
         (let*
            (((ForwardMemberInheritanceObservation
                  $_key $_subject $_concept $old-weight $old-mass)
                (car-atom $old-observations))
             ((forward-member-inheritance-state
                   $_state-id $old-wsum $old-msum)
                (once
                   (match &forward_member_inheritance_state
                      (forward-member-inheritance-state
                         $id $stored-wsum $stored-msum)
                      (forward-member-inheritance-state
                         $id $stored-wsum $stored-msum))))
             ($wsum (- $old-wsum $old-weight))
             ($msum (- $old-msum $old-mass))
             ($_state
                (forward-store-member-inheritance-state!
                   $id $old-wsum $old-msum $wsum $msum))
             ($_old
                (foreach-flat
                   forward-remove-member-inheritance-observation!
                   $old-observations))
             ($_cache
                (if (<= $msum 0.0)
                   (base-rate-cache-remove-derived!
                      $kbid $pattern (member-inheritance $kbid))
                   (forward-store-member-inheritance-cache!
                      $id $kbid $pattern
                      (member-inheritance-tv $kbid
                         (BaseRateEvidence $wsum $msum)))))
             ($replacement-pattern
                (copy_term $pattern)))
            ;; If another proof still supports the removed side, this replaces
            ;; the stale observation; with no support it remains absent.
            (progn
               (forward-update-member-inheritance-interest
                  $obj $id $kbid $subj $concept
                  $replacement-pattern)
               ())))))

(: forward-remove-member-inheritances-for-key
   (-[det]-> KB Term Term (List $none)))
(= (forward-remove-member-inheritances-for-key $kbid $obj $class)
   (let $_
      (collapse
         (match &forward_member_inheritance_interest
            (forward-member-inheritance-interest-row
               $stored-trigger $id $stored-kbid
               $subj $concept $pattern)
            (if (and (== $stored-kbid $kbid)
                     (== $stored-trigger
                         (quote (fwd_member $kbid $class))))
               (forward-remove-member-inheritance-observation!
                  $obj $id $kbid
                  $subj $concept (copy_term $pattern))
               (empty))))
      ()))

(: forward-remove-member-inheritances
   (-[det]-> (Statement KBContext Proof TV) (List $none)))
(= (forward-remove-member-inheritances $fact)
   (forward-remove-member-inheritances-raw $fact))

(: forward-remove-member-inheritances-raw
   (-[det]-> Atom (List $none)))
(= (forward-remove-member-inheritances-raw $fact)
   (case $fact (
      (((Member $obj $class) ($kbid MAIN Nil) $_prf $_tv)
         (let*
            (($typed-kbid (brand KB $kbid))
             ($typed-obj (brand Term $obj))
             ($typed-class (brand Term $class)))
            (forward-remove-member-inheritances-for-key
               $typed-kbid $typed-obj $typed-class)))
      ($_other ()))))

(: forward-update-member-inheritances
   (-[det]-> (Statement KBContext Proof TV) (List $none)))
(= (forward-update-member-inheritances $fact)
   (forward-update-member-inheritances-raw $fact))

;; Knowledge insertion already refreshes the canonical fact. If an empty or
;; populated Member-inheritance subscription exists, update only that affected
;; object's sufficient statistic. This is bounded cache maintenance, not eager
;; rule inference and not invalidation of the older approximation.
(: forward-apply-unqueued-member-change!
   (-[det]-> ForwardOutputChange (List $none)))
(= (forward-apply-unqueued-member-change! $change)
   (case $change (
      (no-forward-change ())
      ((forward-output-added $fact)
         (forward-update-member-inheritances $fact))
      ((forward-output-replaced $_old $fact)
         (forward-update-member-inheritances $fact))
      ((forward-output-removed $_old) ()))))

(: forward-update-member-inheritances-raw
   (-[det]-> Atom (List $none)))
(= (forward-update-member-inheritances-raw $fact)
   (case $fact (
      (((Member $obj $class) ($kbid MAIN Nil) $_prf $_tv)
         (let*
            (($typed-kbid (brand KB $kbid))
             ($typed-obj (brand Term $obj))
             ($typed-class (brand Term $class)))
            (forward-update-member-inheritances-for-key
               $typed-kbid $typed-obj $typed-class)))
      ($_other ()))))

(: forward-invalidate-base-rates-for-key!
   (-[nondet]-> (Statement KBContext Proof TV)
      ForwardTriggerKey  (List $none)))
(= (forward-invalidate-base-rates-for-key! $fact $trigger)
   (match &forward_base_rate_interest
      (forward-base-rate-interest-row
         $trigger $_id $kbid $pattern
         $_extractor $_init $_fun $finish $_tv-mode)
      (base-rate-cache-remove-derived!
         $kbid (copy_term $pattern) $finish)))

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

;; A removed canonical output will never be popped from the agenda, so remove
;; its sufficient-statistic contribution immediately.  Changed outputs keep
;; the observation until the replacement is processed; that update subtracts
;; the old value and adds the new one atomically.
(: forward-remove-base-rate-observation!
   (-[semidet]-> (Statement KBContext Proof TV) Number KB Statement
       (| ExtractTV ExtractInheritanceTV)
       (| BaseRateEvidenceState BaseRateEvidenceWithPriorState)
       (-[semidet]-> $accumulator $value $accumulator)
       (| BaseRateFinish
          WeightedBaseRateInUniverseFinish
          WeightedBaseRateWithPriorInUniverseFinish)
       (List $none)))
(= (forward-remove-base-rate-observation!
      $fact $id $kbid $pattern $extractor $init $fun $finish)
   (let*
      (($output-key (forward-fact-key $fact))
       ($observation-key
          (brand ForwardBaseRateObservationKey
             (quote ($id $output-key))))
       ($old-observations
          (collapse
             (match &forward_base_rate_observation
                (ForwardBaseRateObservation
                   $observation-key $old-fact $old-weight $old-count)
                (ForwardBaseRateObservation
                   $observation-key $old-fact $old-weight $old-count)))))
      (if (== $old-observations ()) ()
         (let*
            (((cons
                  (ForwardBaseRateObservation
                     $_key $_old-fact $old-weight $old-count)
                  $_rest)
                $old-observations)
             ((forward-base-rate-state
                  $_stored-id $old-wsum $old-csum)
                (forward-base-rate-state-by-id $id))
             ($wsum (- $old-wsum $old-weight))
             ($csum (- $old-csum $old-count))
             ($_state
                (forward-store-base-rate-state!
                   $id $old-wsum $old-csum $wsum $csum))
             ($_observations
                (foreach-flat
                   forward-remove-base-rate-observation!
                   $old-observations))
             ($_cache
                (if (<= $csum 0.0)
                   (base-rate-cache-remove-derived! $kbid $pattern $finish)
                   (let*
                      (($acc
                          (forward-base-rate-accumulator
                             $kbid $extractor $init
                             $fun $wsum $csum))
                       ($estimate
                          (forward-finish-stored-aggregate
                             $finish $acc)))
                      (store-forward-base-rate!
                         $kbid $pattern $estimate $finish)))))
            ()))))

(: forward-remove-base-rate-observations-for-key!
   (-[nondet]-> (Statement KBContext Proof TV) ForwardTriggerKey  (List $none)))
(= (forward-remove-base-rate-observations-for-key! $fact $trigger)
   (match &forward_base_rate_interest
      (forward-base-rate-interest-row
         $trigger $id $kbid $pattern
         $extractor $init $fun $finish $_tv-mode)
      (forward-remove-base-rate-observation!
         $fact $id
         $kbid (copy_term $pattern)
         $extractor $init $fun $finish)))

(: forward-remove-base-rate-observations!
   (-[det]-> (Statement KBContext Proof TV) (List $none)))
(= (forward-remove-base-rate-observations! $fact)
   (let*
      (($trigger (forward-premise-index-key $fact))
       ($wildcard (forward-premise-wildcard-key $fact))
       ($_direct
          (collapse
             (forward-remove-base-rate-observations-for-key!
                $fact $trigger)))
       ($_wildcard
          (if (== $trigger $wildcard) ()
             (collapse
                (forward-remove-base-rate-observations-for-key!
                   $fact $wildcard)))))
      ()))

(: forward-satisfy-premises
   (-[nondet]-> Number
       (List (| Goal (Statement KBContext Proof TV)))
       (Statement KBContext Proof TV)
       (List Evidence)
       ((Statement KBContext Proof TV) (List Evidence))))
(= (forward-satisfy-premises $steps () $goal $ev)
   (data $goal $ev))
(= (forward-satisfy-premises $steps (cons $prem $rest) $goal $ev)
   (if (= $prem (CPU $fun $args $res))
      (let $res (reduce (cpu-call $steps $fun $args))
         (forward-satisfy-premises $steps $rest $goal $ev))
      (if (= $prem ($_type ($_kbid $_ctx $_vars) $_prf $_tv))
         (match &kb $prem
            (forward-satisfy-premises $steps $rest $goal
               (list_to_set
                  (append $ev
                     (forward-fact-evidence
                        (brand Statement $_type)
                        (brand KBContext ($_kbid $_ctx $_vars))
                        (brand Proof $_prf) (the TV $_tv))))))
         (empty))))

(: agenda-push-fact (-[det]-> (Heap ForwardQueueItem) (Statement KBContext Proof TV) (Heap ForwardQueueItem)))
(= (agenda-push-fact $agenda $fact)
   (add_to_heap $agenda (- 0 (term-confidence $fact)) (qitem $fact)))

(: forward-seed-agenda-step (-[det]-> (Heap ForwardQueueItem) (Statement KBContext Proof TV) (Heap ForwardQueueItem)))
(= (forward-seed-agenda-step $agenda $fact)
   (let $rows (collapse (once (forward-output-row-for-fact $fact)))
      (if (== $rows ()) (agenda-push-fact $agenda $fact)
         (let (forward-output-row $canonical $_ev)
            (first-forward-output-row $rows)
            (agenda-push-fact $agenda $canonical)))))

(: forward-build-agenda-from-facts
   (-[det]-> (List (Statement KBContext Proof TV)) (Heap ForwardQueueItem)))
(= (forward-build-agenda-from-facts $facts)
   (fold-flat forward-seed-agenda-step (empty_heap) (list_to_set $facts)))

(: forward-agenda-identity (-[det]-> (Heap ForwardQueueItem) (Heap ForwardQueueItem)))
(= (forward-agenda-identity $agenda) $agenda)

(: agenda-push-forward-change (-[det]-> (Heap ForwardQueueItem) ForwardOutputChange (Heap ForwardQueueItem)))
(= (agenda-push-forward-change $agenda $change)
   (once
      (case $change
         ((no-forward-change
             (forward-agenda-identity $agenda))
          ((forward-output-removed $old)
             (let*
                (($_remove-base-rate
                    (forward-remove-base-rate-observations! $old))
                 ($_remove-member
                    (forward-remove-member-inheritances $old)))
                (forward-agenda-identity $agenda)))
          ((forward-output-added $fact)
             (let $_invalidate
                (forward-invalidate-base-rates! $fact)
                (agenda-push-fact $agenda $fact)))
          ((forward-output-replaced $old $fact)
             (let*
                (($_invalidate-old
                    (forward-invalidate-base-rates! $old))
                 ($_invalidate-new
                    (forward-invalidate-base-rates! $fact)))
                (agenda-push-fact $agenda $fact)))))))

;; Apply cache bookkeeping for canonical changes made outside a forward run.
(: forward-apply-unqueued-change!
   (-[det]-> ForwardOutputChange (| (List $none) Bool)))
(= (forward-apply-unqueued-change! $change)
   (once
      (case $change
         ((no-forward-change ())
          ((forward-output-removed $old)
             (progn
                (forward-remove-base-rate-observations! $old)
                (forward-remove-member-inheritances $old)))
          ((forward-output-added $fact)
             (forward-invalidate-base-rates! $fact))
          ((forward-output-replaced $old $fact)
             (progn
                (forward-invalidate-base-rates! $old)
                (forward-invalidate-base-rates! $fact)))))))

(: forward-strict-evidence-subset?
   (-[det]-> (List Evidence) (List Evidence) Bool))
(= (forward-strict-evidence-subset? $subset $superset)
   (and (evidence-subset? $subset $superset)
      (not (evidence-subset? $superset $subset))))

;; These predicates are mutually recursive; publish both contracts before
;; either body so determinism and bound-Bool certification can analyze the SCC.
(: forward-proof-list-refines? (-[det]-> (List Proof) (List Proof) Bool))
(: forward-proof-refines? (-[det]-> Proof Proof Bool))
(= (forward-proof-list-refines? $old $new)
   (if (== $old ()) (== $new ())
      (if (== $new ()) false
         (let*
            (($old-first (car-atom $old))
             ($new-first (car-atom $new))
             ($old-rest (cdr-atom $old))
             ($new-rest (cdr-atom $new)))
            (and (forward-proof-refines? $old-first $new-first)
               (forward-proof-list-refines? $old-rest $new-rest))))))

;; A proof refines another when it has the same rule skeleton and only replaces
;; children by merges containing the earlier child. This distinguishes a
;; genuinely updated application, pToQ(p1) -> pToQ(merge(p1,p2)), from a longer
;; cyclic path such as seed -> keepLoop(seed).
(= (forward-proof-refines? $old $new)
   (if (== $old $new) true
      (if (is-expr $new)
         (if (= $new (merge/revision $left $right))
            (or
               (forward-proof-refines? $old (brand Proof $left))
               (forward-proof-refines? $old (brand Proof $right)))
            (if (and (is-expr $old)
                     (== (car-atom $old) (car-atom $new)))
               (let*
                  (($old-tail (cdr-atom $old))
                   ($new-tail (cdr-atom $new))
                   ($old-children (proof-children $old-tail))
                   ($new-children (proof-children $new-tail)))
                  (forward-proof-list-refines?
                     $old-children $new-children))
               false))
         false)))

(: forward-candidate-refines?
   (-[det]-> (Statement KBContext Proof TV) (List Evidence)
       (Statement KBContext Proof TV) (List Evidence) Bool))
(= (forward-candidate-refines? $old-fact $old-ev $new-fact $new-ev)
   (let*
      (($old-proof (proof-atom-proof $old-fact))
       ($new-proof (proof-atom-proof $new-fact)))
      (and (forward-strict-evidence-subset? $old-ev $new-ev)
         (forward-proof-refines? $old-proof $new-proof))))

;; A larger evidence set for the same output supersedes the partial estimate
;; even when the new TV has lower confidence.  Disjoint candidates remain in
;; the frontier and are revised together.  Incomparable overlapping candidates
;; retain the existing conservative policy of keeping only the stronger one.
(: forward-frontier-old-dominates-new?
   (-[det]-> (Statement KBContext Proof TV) (List Evidence)
       (Statement KBContext Proof TV) (List Evidence) Bool))
(= (forward-frontier-old-dominates-new? $old-fact $old-ev $new-fact $new-ev)
   (let*
      (($old-proof (proof-atom-proof $old-fact))
       ($new-proof (proof-atom-proof $new-fact)))
      (if (== $old-proof $new-proof) false
         (if (projection-dominates? $old-proof $new-proof)
            true
            (if (projection-dominates? $new-proof $old-proof)
               false
               (if (forward-candidate-refines?
                      $old-fact $old-ev $new-fact $new-ev) false
                  (if (forward-candidate-refines?
                         $new-fact $new-ev $old-fact $old-ev) true
                     (if (evidence-sets-overlap? $old-ev $new-ev)
                        (>= (term-confidence $old-fact)
                            (term-confidence $new-fact))
                        false))))))))

(: forward-frontier-new-dominates-old?
   (-[det]-> (Statement KBContext Proof TV) (List Evidence)
       (Statement KBContext Proof TV) (List Evidence) Bool))
(= (forward-frontier-new-dominates-old? $new-fact $new-ev $old-fact $old-ev)
   (let*
      (($old-proof (proof-atom-proof $old-fact))
       ($new-proof (proof-atom-proof $new-fact)))
      (if (== $old-proof $new-proof) true
         (if (projection-dominates? $new-proof $old-proof)
            true
            (if (projection-dominates? $old-proof $new-proof)
               false
               (if (forward-candidate-refines?
                      $old-fact $old-ev $new-fact $new-ev) true
                  (if (forward-candidate-refines?
                         $new-fact $new-ev $old-fact $old-ev) false
                     (if (evidence-sets-overlap? $old-ev $new-ev)
                        (> (term-confidence $new-fact)
                           (term-confidence $old-fact))
                        false))))))))

(: forward-frontier-has-exact?
   (-[det]-> ForwardOutputKey
       (Statement KBContext Proof TV) (List Evidence) Bool))
(= (forward-frontier-has-exact?
      (forward-output-key $kb $type) $fact $ev)
   (let $hash
      (forward-output-index-hash
         (forward-output-key $kb $type))
      (not (==
         (collapse
            (once
               (match &forward_frontier
                  (forward-frontier-row
                     $hash $type $kb $fact $ev)
                  true)))
         ()))))

(: forward-frontier-rejects?
   (-[det]-> ForwardOutputKey
       (Statement KBContext Proof TV) (List Evidence) Bool))
(= (forward-frontier-rejects?
      (forward-output-key $kb $type) $fact $ev)
   (let $hash
      (forward-output-index-hash
         (forward-output-key $kb $type))
      (not (==
         (collapse
            (once
               (match &forward_frontier
                  (forward-frontier-row
                     $hash $type $kb $old-fact $old-ev)
                  (if (forward-frontier-old-dominates-new?
                         $old-fact $old-ev $fact $ev)
                     true
                     (empty)))))
         ()))))

(: forward-prune-frontier-for!
   (-[det]-> ForwardOutputKey
       (Statement KBContext Proof TV) (List Evidence) (List $none)))
(= (forward-prune-frontier-for!
      (forward-output-key $kb $type) $fact $ev)
   (let $hash
      (forward-output-index-hash
         (forward-output-key $kb $type))
      (collapse
         (match &forward_frontier
            (forward-frontier-row
               $hash $type $kb $old-fact $old-ev)
            (if (forward-frontier-new-dominates-old?
                   $fact $ev $old-fact $old-ev)
               (remove-atom &forward_frontier
                  (forward-frontier-row
                     $hash $type $kb $old-fact $old-ev))
               ())))))

(: forward-record-inheritance-nodes!
   (-[det]-> (Statement KBContext Proof TV)
       (| Bool (List $none))))
(= (forward-record-inheritance-nodes! $fact)
   (case $fact (
      (((Inheritance $subj $concept) ($kbid $_ctx $_vars) $_prf $_tv)
         (if (is-var $subj) ()
            (progn
               (once
                  (let $row
                     (make-space-pair $kbid $subj)
                     (add-space-atom! &inheritance_subject $row)))
               (record-inheritance-nodes!
                  $kbid
                  (brand Statement $subj)
                  (brand Statement $concept)))))
      ($_other ()))))

(: forward-add-frontier-row!
   (-[nondet]-> ForwardOutputKey
      (Statement KBContext Proof TV) (List Evidence)
       (List $none)))
(= (forward-add-frontier-row!
      (forward-output-key $kb $type) $fact $ev)
   (let*
      (($hash
          (forward-output-index-hash
             (forward-output-key $kb $type)))
       ($_nodes (forward-record-inheritance-nodes! $fact))
       ($_frontier
          (chainer-add-atom &forward_frontier
             (forward-frontier-row
                $hash $type $kb $fact $ev))))
      ()))

(: forward-add-first-candidate!
   (-[nondet]-> ForwardOutputKey
      (Statement KBContext Proof TV) (List Evidence)
       ForwardOutputChange))
(= (forward-add-first-candidate! $output-key $fact $ev)
   (let $_add (forward-add-frontier-row! $output-key $fact $ev)
      (forward-store-output-candidate!
         $output-key (forward-output-candidate $fact $ev))))

;; Disjoint evidence cannot evict an existing frontier branch.  Merge directly
;; with the cached canonical fact instead of scanning and folding the frontier.
(: forward-add-disjoint-candidate!
   (-[nondet]-> ForwardOutputKey
      (Statement KBContext Proof TV) (List Evidence)
      (Statement KBContext Proof TV) (List Evidence)
       ForwardOutputChange))
(= (forward-add-disjoint-candidate!
      $output-key $canonical $canonical-ev $fact $ev)
   (let*
      (($_add (forward-add-frontier-row! $output-key $fact $ev))
       ($merged-state
          (merge-proof-candidates
             (proof-candidate-pair $canonical $canonical-ev)
             (proof-candidate-pair $fact $ev))))
      (forward-store-output-candidate!
         $output-key
         (forward-output-candidate
            (fst $merged-state) (snd $merged-state)))))

(: forward-candidate-upsert!
   (-[nondet]-> ForwardDerived  ForwardOutputChange))
(= (forward-candidate-upsert! (forward-derived $fact $ev))
   (let $output-key (forward-fact-key $fact)
      (if (forward-frontier-has-exact? $output-key $fact $ev) no-forward-change
         (let $canonical-rows
            (collapse (once (forward-output-row-for-fact $fact)))
            (if (== $canonical-rows ())
               (forward-add-first-candidate! $output-key $fact $ev)
                  (let (forward-output-row
                        $canonical $canonical-ev)
                  (first-forward-output-row $canonical-rows)
                     (if (not (evidence-sets-overlap? $canonical-ev $ev))
                        (forward-add-disjoint-candidate!
                           $output-key $canonical $canonical-ev $fact $ev)
                        (if (forward-frontier-rejects? $output-key $fact $ev)
                           no-forward-change
                           (let*
                              (($_prune
                                   (forward-prune-frontier-for!
                                      $output-key $fact $ev))
                               ($_add
                                   (forward-add-frontier-row!
                                      $output-key $fact $ev)))
                              (forward-refresh-output-key! $output-key))))))))))

(: forward-rule-results-for-key
   (-[det]-> Number KB (Statement KBContext Proof TV)
      ForwardTriggerKey  (List ForwardDerived)))
(= (forward-rule-results-for-key $steps $kb $fact $key)
   (collapse
      (let*
         ((($id $idx) (match prem_index ($key $fact $id $idx) ($id $idx)))
           ((runtime-rule-row $id $ccls $prems)
              (match rules
                 (runtime-rule-row $id $ccls $prems)
                 (runtime-rule-row $id $ccls $prems)))
           ($rprems
              (nth0 $idx $prems $fact))
           ((forward-output-row
                $trigger-fact $trigger-ev)
              (forward-output-row-for-fact $fact))
           (($result $premise-ev)
              (forward-satisfy-premises
                 $steps $rprems $ccls $trigger-ev)))
         (forward-derived $result
            (rule-result-evidence $result $premise-ev)))))

(: append-forward-derived
   (-[det]-> (List ForwardDerived) (List ForwardDerived)
       (List ForwardDerived)))
(= (append-forward-derived () $right) $right)
(= (append-forward-derived (cons $head $tail) $right)
   (cons $head (append-forward-derived $tail $right)))

(: forward-rule-results
   (-[det]-> Number KB (Statement KBContext Proof TV)
       (List ForwardDerived)))
(= (forward-rule-results $steps $kb $fact)
   (let*
      (($key (forward-premise-index-key $fact))
        ($wildcard-key (forward-premise-wildcard-key $fact))
        ($direct (forward-rule-results-for-key $steps $kb $fact $key)))
      (if (== $key $wildcard-key)
         $direct
         (append-forward-derived $direct
            (forward-rule-results-for-key
               $steps $kb $fact $wildcard-key)))))

(: forward-run-apply-derived
   (-[det]-> ForwardRun ForwardDerived ForwardRun))
(= (forward-run-apply-derived ($agenda $changed) $derived)
   (let $changes (collapse (once (forward-candidate-upsert! $derived)))
      (let $change
         (if (== $changes ()) no-forward-change (car-atom $changes))
      (let $nagenda (agenda-push-forward-change $agenda $change)
         (case $change
            (((forward-output-added $fact)
                ;; Keep output identities, not intermediate fact versions. At
                ;; the end of the run each identity resolves to its final
                ;; canonical fact.
                (data
                   $nagenda (cons (forward-fact-key $fact) $changed)))
             ((forward-output-replaced $_old $fact)
                (data
                   $nagenda (cons (forward-fact-key $fact) $changed)))
             ($_other
                (data $nagenda $changed))))))))

(: forward-step-fact
   (-[det]-> Number KB ForwardRun (Statement KBContext Proof TV) ForwardRun))
(= (forward-step-fact $steps $kb $run $fact)
   (let*
      (($_base-rates (forward-update-base-rates $fact))
       ($_member-inheritances (forward-update-member-inheritances $fact))
       ($nrun
          (fold-flat forward-run-apply-derived $run
             (forward-rule-results $steps $kb $fact))))
      $nrun))

;; If several derivations update one output before it is processed, only its
;; latest canonical version should run.  Explicit non-KB seeds have no
;; canonical row and are therefore always current.
(: forward-queued-fact-current? (-[det]-> (Statement KBContext Proof TV) Bool))
(= (forward-queued-fact-current? $fact)
   (let $rows (collapse (once (forward-output-row-for-fact $fact)))
      (if (== $rows ()) true
         (let (forward-output-row $canonical $_ev)
            (first-forward-output-row $rows)
            (== $canonical $fact)))))

(: forward-loop (-[det]-> Number KB ForwardRun ForwardRun))
(= (forward-loop $steps $kb ($agenda $changed))
   (if (<= $steps 0)
       (data $agenda $changed)
       (case (forward-pop-agenda $agenda) (
          (no-forward-agenda-pop
             (data $agenda $changed))
          ((forward-agenda-pop $rest (qitem $fact))
             (if (forward-queued-fact-current? $fact)
                (let*
                   (($next-steps (- $steps 1))
                    (($nagenda $nchanged)
                       (forward-step-fact $steps $kb
                          (data $rest $changed) $fact)))
                   (forward-loop $next-steps $kb
                      (data
                         (bounded-agenda-prune $next-steps $nagenda)
                         $nchanged)))
                (forward-loop
                   $steps $kb
                   (data $rest $changed))))))))

(: forward-canonical-fact-for-key
   (-[semidet]-> ForwardOutputKey (Statement KBContext Proof TV)))
(= (forward-canonical-fact-for-key
      (forward-output-key $kb $type))
   (let $hash
      (forward-output-index-hash
         (forward-output-key $kb $type))
      (once
         (match &forward_canonical_evidence
            (forward-canonical-evidence-row
               $hash $type $kb $fact $_ev)
            $fact))))

(: forward-canonical-facts-for-keys
   (-[det]-> (List ForwardOutputKey)
       (List (Statement KBContext Proof TV))))
(= (forward-canonical-facts-for-keys ()) ())
(= (forward-canonical-facts-for-keys (cons $key $rest))
   (let $rows
      (collapse (once (forward-canonical-fact-for-key $key)))
      (if (== $rows ())
         (forward-canonical-facts-for-keys $rest)
         (cons (car-atom $rows)
            (forward-canonical-facts-for-keys $rest)))))

(: forward-run-changed-facts
   (-[det]-> ForwardRun (List (Statement KBContext Proof TV))))
(= (forward-run-changed-facts ($_agenda $changed))
   (forward-canonical-facts-for-keys
      (list_to_set $changed)))

(: forward-chain
   (-[nondet]-> Number KB (List (Statement KBContext Proof TV))
       (List (Statement KBContext Proof TV))))
(= (forward-chain $steps $kb $facts)
   (let $agenda
      (forward-build-agenda-from-facts $facts)
      (let $run
         (forward-loop $steps $kb (data $agenda ()))
         (forward-run-changed-facts $run))))

(: forward-has-derived? (-[det]-> KB Statement Bool))
(= (forward-has-derived? $kb $type)
   (not (==
      (collapse
         (match &kb ($type ($kb MAIN Nil) $prf $_tv)
            $prf))
      ())))
