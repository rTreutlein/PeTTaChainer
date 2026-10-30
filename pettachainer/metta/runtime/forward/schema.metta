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

;; A statement's stored facts merged into one candidate: what the facts say
;; about the statement together. Materialized facts are not stored facts: the
;; skeleton derived them. A forward run's copy of a key's value is counted only
;; when asked for: a base rate counts stored facts and hears of copies from the
;; run that made them, while a membership read wants the latest value a run
;; reported. A copy is looked up under the key of the row matched, which an open
;; statement only finds once the match binds it.
(: stored-candidate-step
   (-[det]-> (| ForwardDerived NoForwardOutputCandidate) (Statement KBContext Proof TV) ForwardDerived))
(= (stored-candidate-step $acc ($type $kb $proof $tv))
   (let* (($fact (data $type $kb $proof $tv))
          ($ev (evidence-set (cons (fact-evidence-entry $kb $proof $type) ()))))
      (case $acc (
         (no-forward-output-candidate (forward-derived $fact $ev))
         ((forward-derived $current $current-ev)
            (case (collapse (once (sk-merge-facts false () $current $current-ev 0 $fact $ev 0))) (
               ((cons (sk-paired (sk-val $merged $merged-ev $_deps)) ()) (forward-derived $merged $merged-ev))
               ((cons (sk-overlap $_shared $_deps (sk-val $merged $merged-ev $_fdeps)) ()) (forward-derived $merged $merged-ev))
               ($_none (forward-derived $current $current-ev)))))))))

(: stored-statement-candidate
   (-[det]-> Statement KBContext Bool (| ForwardDerived NoForwardOutputCandidate)))
(= (stored-statement-candidate $type $kb $copies)
   (fold-flat stored-candidate-step no-forward-output-candidate
      (let $facts (kb-facts $type $kb)
         (collapse (let ($ftype $fkb $_proof $_tv) (superpose $facts)
            (let $fact (data $ftype $fkb $_proof $_tv)
               (if (materialized-forward-fact? $fact) (empty)
                  (if $copies $fact
                     (if (space-row-present? &sk_forward_stored ((index-hash (sk-key $ftype $fkb)) $_key $fact $_ev $_deps)) (empty) $fact)))))))))
