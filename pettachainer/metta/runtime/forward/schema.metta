;; Forward schemas: trigger and output keys, aggregate identities and
;; observations, and the stored facts of a statement.

(datatype NoForwardOutputCandidate no-forward-output-candidate)

(datatype ForwardOutputKey (forward-output-key KBContext Statement))

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

(: forward-type-trigger-key (-[det]-> KB Statement ForwardTriggerKey))
(= (forward-type-trigger-key $kbid $type)
   (if (is-var $type) (fwd_trigger $kbid any)
      (if (is-expr $type)
         (let $head (car-atom $type) (if (is-var $head) (fwd_trigger $kbid any) (fwd_trigger $kbid $head)))
         (fwd_trigger $kbid $type))))

;; A fact premise is indexed under its type-head trigger and its kb-wide
;; wildcard trigger; a CPU premise only under the global wildcard.
(: forward-premise-keys
   (-[det]-> (| Goal (Statement KBContext Proof TV)) (ForwardTriggerKey ForwardTriggerKey)))
(= (forward-premise-keys $prem)
   (case $prem (
      (($type ($kbid $_ctx $_vars) $_prf $_tv)
         (data
            (forward-type-trigger-key (brand KB $kbid) (brand Statement $type))
            (fwd_trigger (brand KB $kbid) any)))
      ($_cpu (data fwd_trigger_any fwd_trigger_any)))))

(: forward-fact-key (-[det]-> (Statement KBContext Proof TV) ForwardOutputKey))
(= (forward-fact-key ($type ($kbid $ctx $vars) $_prf $_tv))
   (forward-output-key (brand KBContext (quote ($kbid $ctx $vars))) $type))
(: forward-output-index-hash (-[det]-> ForwardOutputKey Number))
(= (forward-output-index-hash (forward-output-key $kb $type)) (term_hash (quote ($kb $type))))

(: link-aggregate-fold! (-[det]-> Number Number Atom))
(= (link-aggregate-fold! $id $hash)
   (if (space-row-present? &ctx_forward_aggregate_fold ($id $hash)) ()
      (let $_row (context-add! &forward_aggregate_fold ($id $hash)) ())))

;; Materialized facts are marked in &materialized_facts. They are never leaves:
;; the backward chainer re-derives them.
(datatype MaterializedRow
   (materialized-row Number Statement KBContext (Statement KBContext Proof TV) EvidenceSet))
(: materialized-forward-fact? (-[det]-> (Statement KBContext Proof TV) Bool))
(= (materialized-forward-fact? ($type $kb $proof $tv))
   (let $hash (forward-output-index-hash (forward-output-key $kb $type))
      (space-row-present? &materialized_facts
         (materialized-row $hash $type $kb ($type $kb $proof $tv) $_ev))))
