!(import_prolog_function nth0)

;; nth0/4 removes the indexed element while unifying it with its third
;; argument. Its relational modes can branch, but every result preserves the
;; element type of the input list.
;; Forward schemas, trigger keys, candidate frontier, and canonical KB output.
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
