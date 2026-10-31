;; Forward schemas: trigger and output keys, aggregate identities and
;; observations, and the stored facts of a statement.

(datatype NoForwardOutputCandidate no-forward-output-candidate)

(: forward-base-rate-identity
   (-[det]-> KB Statement ForwardAggregateIdentityKey))

(: forward-class-link-identity (-[det]-> KB Term Term ForwardAggregateIdentityKey))

(: forward-base-rate-descriptor
   (-[det]-> KB Statement ForwardAggregateDescriptor))

;; A class link's instance fold, by its skeleton key.
(: forward-class-link-descriptor
   (-[det]-> KB Term Term SkeletonKey ForwardAggregateDescriptor))

(datatype ForwardAggregateIdentityRow (forward-aggregate-identity-row ForwardAggregateIdentityKey Number))

(datatype ForwardAggregateInterest
   (forward-aggregate-interest ForwardTriggerKey Number ForwardAggregateDescriptor))

(datatype ForwardAggregateState (forward-aggregate-state Number Number Number Number))

(datatype ForwardAggregateObservationValue
   no-forward-aggregate-observation-value
   (forward-base-rate-observation-value (Statement KBContext Proof TV)))

(datatype ForwardAggregateObservation
   (forward-aggregate-observation ForwardAggregateObservationKey ForwardAggregateObservationValue Number Number))

;; Materialized facts are marked in &materialized_facts. They are never leaves:
;; the backward chainer re-derives them.
(datatype MaterializedRow
   (materialized-row Number Statement KBContext (Statement KBContext Proof TV) EvidenceSet))
(: materialized-forward-fact? (-[det]-> (Statement KBContext Proof TV) Bool))
(= (materialized-forward-fact? ($type $kb $proof $tv))
   (let $hash (forward-output-index-hash (forward-output-key $kb $type))
      (space-row-present? &materialized_facts
         (materialized-row $hash $type $kb ($type $kb $proof $tv) $_ev))))
