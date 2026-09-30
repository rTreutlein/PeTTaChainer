!(import_prolog_function nth0)

;; nth0/4 removes the indexed element while unifying it with its third
;; argument. Its relational modes can branch, but every result preserves the
;; element type of the input list.
;; Forward schemas, trigger keys, candidate frontier, and canonical KB output.
(: nth0
   (-[nondet]-> $index (List $item) $item (List $item)))

(: NoForwardOutputCandidate Type)
(: no-forward-output-candidate NoForwardOutputCandidate)

(: ForwardOutputKey Type)
(: forward-output-key
   (-[det]-> KBContext Statement ForwardOutputKey))

(: ForwardFrontierRow Type)
(: forward-frontier-row
   (-[det]-> Number Statement KBContext
       (Statement KBContext Proof TV)
       (List Evidence)
       ForwardFrontierRow))

(: first-forward-output-row
   (-[det]-> (List ForwardDerived) ForwardDerived))
(= (first-forward-output-row (cons $row $_rest)) $row)

(: ForwardCanonicalEvidenceRow Type)
(: forward-canonical-evidence-row
   (-[det]-> Number Statement KBContext
       (Statement KBContext Proof TV)
       (List Evidence)
       ForwardCanonicalEvidenceRow))

(: forward-base-rate-identity
   (-[det]-> KB Statement
       (| ExtractTV ExtractInheritanceTV)
       (| BaseRateEvidenceState BaseRateEvidenceWithPriorState)
       (-[semidet]-> $accumulator $value $accumulator)
       (| BaseRateFinish
          WeightedBaseRateInUniverseFinish
          WeightedBaseRateWithPriorInUniverseFinish)
       AggregateTVMode
       ForwardAggregateIdentityKey))

(: forward-member-inheritance-identity
   (-[det]-> KB Term Term ForwardAggregateIdentityKey))

(: forward-base-rate-descriptor
   (-[det]-> KB Statement
       (| ExtractTV ExtractInheritanceTV)
       (| BaseRateEvidenceState BaseRateEvidenceWithPriorState)
       (-[semidet]-> $accumulator $value $accumulator)
       (| BaseRateFinish
          WeightedBaseRateInUniverseFinish
          WeightedBaseRateWithPriorInUniverseFinish)
       ForwardAggregateDescriptor))

(: forward-member-inheritance-descriptor
   (-[det]-> KB Term Term Statement ForwardAggregateDescriptor))

(: ForwardAggregateIdentityRow Type)
(: forward-aggregate-identity-row
   (-[det]-> ForwardAggregateIdentityKey Number
       ForwardAggregateIdentityRow))

(: ForwardAggregateInterest Type)
(: forward-aggregate-interest
   (-[det]-> ForwardTriggerKey Number ForwardAggregateDescriptor
       ForwardAggregateInterest))

;; Both indexes expose the selective numeric hash as their first generated
;; Prolog argument.  Complete keys remain in the payload to reject collisions.
(: &forward_aggregate_identity
   (SpaceOf (Number ForwardAggregateIdentityRow)))
(: &forward_aggregate_interest_by_trigger
   (SpaceOf (Number ForwardAggregateInterest)))

(: ForwardAggregateState Type)
(: forward-aggregate-state
   (-[det]-> Number Number Number ForwardAggregateState))

(: ForwardAggregateObservationValue Type)
(: no-forward-aggregate-observation-value
   ForwardAggregateObservationValue)
(: forward-base-rate-observation-value
   (-[det]-> (Statement KBContext Proof TV)
       ForwardAggregateObservationValue))
(: forward-member-inheritance-observation-value
   (-[det]-> ForwardDerived ForwardDerived
       ForwardAggregateObservationValue))

(: ForwardAggregateObservation Type)
(: forward-aggregate-observation
   (-[det]-> ForwardAggregateObservationKey
       ForwardAggregateObservationValue Number Number
       ForwardAggregateObservation))

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
(: qitem (-[det]-> ForwardDerived ForwardQueueItem))

;; Total wrapper around SWI's relational heap pop. The foreign predicate binds
;; priority and item through output arguments, which ordinary MeTTa arrows
;; cannot express directly.
(: ForwardAgendaPop Type)
(: no-forward-agenda-pop ForwardAgendaPop)
(: forward-agenda-pop (-[det]-> (Heap ForwardQueueItem) ForwardQueueItem ForwardAgendaPop))

(: forward-pop-agenda (-[semidet]-> (Heap ForwardQueueItem) ForwardAgendaPop))
(= (forward-pop-agenda $agenda)
   (if (heap-empty? $agenda) no-forward-agenda-pop (forward-agenda-popped (heap_pop $agenda))))

(: forward-agenda-popped
   (-[det]-> (Number ForwardQueueItem (Heap ForwardQueueItem)) ForwardAgendaPop))
(= (forward-agenda-popped ($_priority $item $rest)) (forward-agenda-pop $rest $item))

(: ForwardRun
   (Alias ((Heap ForwardQueueItem) (List ForwardOutputKey))))

(: forward-type-trigger-key (-[det]-> KB Statement ForwardTriggerKey))
(= (forward-type-trigger-key $kbid $type)
   (if (is-var $type) (fwd_trigger $kbid any)
      (if (is-expr $type)
         (let $head (car-atom $type) (if (is-var $head) (fwd_trigger $kbid any) (fwd_trigger $kbid $head)))
         (fwd_trigger $kbid $type))))

;; A fact premise is indexed under its type-head trigger and its kb-wide
;; wildcard trigger; a CPU premise only under the global wildcard.
(: forward-premise-keys
   (-[det]-> (| Goal (Statement KBContext Proof TV))
       (ForwardTriggerKey ForwardTriggerKey)))
(= (forward-premise-keys $prem)
   (case $prem (
      (($type ($kbid $_ctx $_vars) $_prf $_tv)
         (data
            (forward-type-trigger-key (brand KB $kbid) (brand Statement $type))
            (fwd_trigger (brand KB $kbid) any)))
      ($_cpu (data fwd_trigger_any fwd_trigger_any)))))

(: forward-fact-key
   (-[det]-> (Statement KBContext Proof TV) ForwardOutputKey))
(= (forward-fact-key ($type ($kbid $ctx $vars) $_prf $_tv))
   (forward-output-key
      (brand KBContext (quote ($kbid $ctx $vars)))
      $type))
(: forward-output-index-hash (-[det]-> ForwardOutputKey Number))
(= (forward-output-index-hash (forward-output-key $kb $type))
   (term_hash (quote ($kb $type))))

(: forward-output-candidate-step
   (-[det]-> (| ForwardDerived NoForwardOutputCandidate)
       ForwardFrontierRow
       ForwardDerived))
(= (forward-output-candidate-step
      no-forward-output-candidate
      (forward-frontier-row
         $_hash $_type $_kb $fact $ev))
   (forward-derived $fact $ev))
(= (forward-output-candidate-step
      (forward-derived $current $current-ev)
      (forward-frontier-row
         $_hash $_type $_kb $fact $ev))
   (let ($merged $merged-ev)
      (merge-proof-candidates
         (data $current $current-ev)
         (data $fact $ev))
      (forward-derived $merged $merged-ev)))

(: forward-output-candidate-for-key
   (-[det]-> ForwardOutputKey
       (| ForwardDerived NoForwardOutputCandidate)))
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

;; &kb contains one canonical fact per grounded output.  The private frontier
;; keeps only the independent, non-dominated candidates required to update that
;; canonical fact when later evidence supersedes just one branch.  Exact-map
;; rows start with a hash of the complete output identity, followed by that
;; identity so unification still rejects the rare hash collision.
(: forward-store-output-candidate!
   (-[nondet]-> ForwardOutputKey
      (| ForwardDerived NoForwardOutputCandidate)
       ForwardOutputChange))
(= (forward-store-output-candidate!
      (forward-output-key $kb $type) $new-candidate)
   (let*
      (($_journal (sk-note-fact! $type $kb))
       ($hash
          (forward-output-index-hash
             (forward-output-key $kb $type)))
       ($old-candidate
          (case (collapse
                (once
                   (match &forward_canonical_evidence
                      (forward-canonical-evidence-row
                         $hash $type $kb $stored-fact $stored-ev)
                      (forward-derived $stored-fact $stored-ev))))
             ((() no-forward-output-candidate)
              ((cons $candidate $_rest) $candidate)))))
      (case $new-candidate
         (((forward-derived $new-fact $new-ev)
            (case $old-candidate
               (((forward-derived $old-fact $old-ev)
                  (if (if (== $old-fact $new-fact) (== $old-ev $new-ev) false)
                     no-forward-change
                     (let*
                        (($_remove-fact (remove-atom &kb $old-fact))
                         ($_remove-evidence
                             (remove-atom &forward_canonical_evidence
                                (forward-canonical-evidence-row
                                   $hash $type $kb $_stored-fact $_stored-ev)))
                         ($_add-fact (chainer-add-atom &kb $new-fact))
                         ($_add-evidence
                             (add-atom &forward_canonical_evidence
                                (forward-canonical-evidence-row
                                   $hash $type $kb $new-fact $new-ev))))
                        (forward-output-replaced $old-fact $new-fact))))
                (no-forward-output-candidate
                   (let*
                      (($_add-fact (chainer-add-atom &kb $new-fact))
                       ($_add-evidence
                           (add-atom &forward_canonical_evidence
                              (forward-canonical-evidence-row
                                 $hash $type $kb $new-fact $new-ev))))
                      (forward-output-added $new-fact))))))
          (no-forward-output-candidate
             (case $old-candidate
                ((no-forward-output-candidate no-forward-change)
                 ((forward-derived $old-fact $_old-ev)
                    (let*
                       (($_remove-fact (remove-atom &kb $old-fact))
                        ($_remove-evidence
                            (remove-atom &forward_canonical_evidence
                               (forward-canonical-evidence-row
                                  $hash $type $kb $_stored-fact $_stored-ev))))
                       (forward-output-removed $old-fact))))))))))

(: forward-refresh-output-key!
   (-[nondet]-> ForwardOutputKey  ForwardOutputChange))
(= (forward-refresh-output-key! $key)
   (forward-store-output-candidate!
      $key (forward-output-candidate-for-key $key)))

(: forward-output-row-for-fact
   (-[semidet]-> (Statement KBContext Proof TV) ForwardDerived))
(= (forward-output-row-for-fact ($type $kb $proof $tv))
   (let*
      (($hash (term_hash (quote ($kb $type)))))
      (once
         (match &forward_canonical_evidence
            (forward-canonical-evidence-row
               $hash $type $kb $canonical $ev)
            (forward-derived $canonical $ev)))))
