;; Forward schemas: trigger and output keys, aggregate identities and
;; observations, and the stored facts of a statement.

(: NoForwardOutputCandidate Type)
(: no-forward-output-candidate NoForwardOutputCandidate)

(: ForwardOutputKey Type)
(: forward-output-key
   (-[det]-> KBContext Statement ForwardOutputKey))

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


;; The skeleton fold key each base-rate aggregate is the estimate of: aggregate
;; id, fold key hash. A member whose value depends on that key was derived
;; through the estimate and does not count in it.
(: &forward_aggregate_fold (SpaceOf (Number Number)))
!(bind! &forward_aggregate_fold (new-space))
(: link-aggregate-fold! (-[det]-> Number Number Atom))
(= (link-aggregate-fold! $id $hash)
   (if (space-row-present? &forward_aggregate_fold ($id $hash)) ()
      (let $_row (add-atom &forward_aggregate_fold ($id $hash)) ())))

;; Materialized facts are marked in &materialized_facts. They are never leaves:
;; the backward chainer re-derives them.
(: MaterializedRow Type)
(: materialized-row
   (-[det]-> Number Statement KBContext (Statement KBContext Proof TV)
       (List Evidence) MaterializedRow))
(: materialized-forward-fact? (-[det]-> (Statement KBContext Proof TV) Bool))
(= (materialized-forward-fact? ($type $kb $proof $tv))
   (let $hash (forward-output-index-hash (forward-output-key $kb $type))
      (space-row-present? &materialized_facts
         (materialized-row $hash $type $kb ($type $kb $proof $tv) $_ev))))

;; A statement's stored facts merged into one candidate: what the facts say
;; about the statement together. Materialized facts and a forward run's copy of
;; a key's value are not stored facts: the skeleton derived them.
(: stored-candidate-step
   (-[det]-> (| ForwardDerived NoForwardOutputCandidate) (Statement KBContext Proof TV) ForwardDerived))
(= (stored-candidate-step $acc ($type $kb $proof $tv))
   (let* (($fact (data $type $kb $proof $tv))
          ($ev (cons (fact-evidence-entry $kb $proof $type) ())))
      (case $acc (
         (no-forward-output-candidate (forward-derived $fact $ev))
         ((forward-derived $current $current-ev)
            (let ($merged $merged-ev) (merge-proof-candidates (data $current $current-ev) (data $fact $ev))
               (forward-derived $merged $merged-ev)))))))

(: stored-statement-candidate
   (-[det]-> Statement KBContext (| ForwardDerived NoForwardOutputCandidate)))
(= (stored-statement-candidate $type $kb)
   (fold-flat stored-candidate-step no-forward-output-candidate
      (let $copy-hash (index-hash (sk-key $type $kb))
         (collapse (match &kb ($type $kb $proof $tv)
            (let $fact (data $type $kb $proof $tv)
               (if (materialized-forward-fact? $fact) (empty)
                  (if (space-row-present? &sk_forward_stored ($copy-hash $_key $fact $_ev $_deps)) (empty) $fact))))))))
