!(import_prolog_function nth0)

(: ForwardDerived Type)
(: forward-derived
   (-> ($type $kb $proof TV) (List Evidence) ForwardDerived))
(: ForwardMatch Type)
(: forward-match
   (-> ($type $kb $proof TV) (List Evidence) ForwardMatch))

(: ForwardTriggerKey Type)
(: fwd_trigger (-> $kb $head ForwardTriggerKey))
(: fwd_trigger_any ForwardTriggerKey)

(: ForwardOutputCandidate Type)
(: forward-output-candidate
   (-> ($type $kb $proof TV) (List Evidence) ForwardOutputCandidate))

(: ForwardOutputChange Type)
(: no-forward-change ForwardOutputChange)
(: forward-output-change
   (-> $old-fact $new-fact ForwardOutputChange))

(: ForwardQueueItem Type)
(: qitem (-> ($type $kb $proof TV) ForwardQueueItem))

(: ForwardRun Type)
(: forward-run (-> $heap (List $output-key) ForwardRun))

(: forward-type-trigger-key (-> $kb $type ForwardTriggerKey))
(= (forward-type-trigger-key $kbid $type)
   (if (is-var $type) (fwd_trigger $kbid any)
      (if (is-expr $type)
         (let $head (car-atom $type) (if (is-var $head) (fwd_trigger $kbid any) (fwd_trigger $kbid $head)))
         (fwd_trigger $kbid $type))))

(: forward-indexable-premise-key
   (-> $premise (| ForwardTriggerKey (List $no-key))))
(= (forward-indexable-premise-key $prem)
   (if (= $prem ($_type ($kbid $_ctx $_vars) $_prf $_tv)) (forward-type-trigger-key $kbid $_type) ()))

(: forward-premise-index-key (-> $premise ForwardTriggerKey))
(= (forward-premise-index-key $prem)
   (let $key (forward-indexable-premise-key $prem)
      (if (== $key ()) fwd_trigger_any (the ForwardTriggerKey $key))))

(: forward-premise-wildcard-key (-> $premise ForwardTriggerKey))
(= (forward-premise-wildcard-key $prem)
   (if (= $prem ($_type ($kbid $_ctx $_vars) $_prf $_tv)) (fwd_trigger $kbid any) fwd_trigger_any))

(: forward-fact-key
   (-> ($type ($kb $context $variables) $proof $truth-value) (($kb $context $variables) $type)))
(= (forward-fact-key ($type ($kbid $ctx $vars) $_prf $_tv)) (($kbid $ctx $vars) $type))
(: forward-fact-kb
   (-> ($type ($kb $context $variables) $proof $truth-value) $kb))
(= (forward-fact-kb ($_type ($kbid $_ctx $_vars) $_prf $_tv)) $kbid)
(: forward-output-index-hash (-> ($kb $type) Number))
(= (forward-output-index-hash ($kb $type))
   (the Number (term_hash ($kb $type))))

(: forward-fact-evidence
   (-> ($type $kb $proof $truth-value) (List $evidence)))
(= (forward-fact-evidence ($type $kb $prf $tv))
   (let*
      (($fact ($type $kb $prf $tv))
       ($hash (forward-output-index-hash ($kb $type)))
       ($hits
         (collapse
            (once
               (match &forward_canonical_evidence
                  ($hash $type $kb $fact $ev) $ev)))))
         (if (== $hits ())
            (let $frontier-hits
               (collapse
                  (once
                     (match &forward_frontier
                        ($hash $type $kb $fact $ev) $ev)))
               (if (== $frontier-hits ())
                  (cons (fact-ev $kb $prf $type) ())
                  (car-atom $frontier-hits)))
            (car-atom $hits))))

(: forward-output-candidate-step
   (-> (| ForwardOutputCandidate (List $no-candidate)) (Number $type $kb $fact (List $evidence)) ForwardOutputCandidate))
(= (forward-output-candidate-step () ($_hash $_type $_kb $fact $ev))
   (forward-output-candidate $fact $ev))
(= (forward-output-candidate-step
      (forward-output-candidate $current $current-ev)
      ($_hash $_type $_kb $fact $ev))
   (let ($merged $merged-ev)
      (merge-proof-candidates
         ($current $current-ev)
         ($fact $ev))
      (forward-output-candidate $merged $merged-ev)))

(: forward-output-candidate-for-key
   (-> ($kb $type) (| ForwardOutputCandidate (List $no-candidate))))
(= (forward-output-candidate-for-key ($kb $type))
   (let $hash (forward-output-index-hash ($kb $type))
      (fold-flat forward-output-candidate-step ()
         (collapse
            (match &forward_frontier
               ($hash $type $kb $fact $ev)
               ($hash $type $kb $fact $ev))))))

(: forward-remove-canonical-fact! (-> ($type $kb $proof TV) Bool))
(= (forward-remove-canonical-fact! $fact) (remove-atom &kb $fact))
(: forward-remove-canonical-evidence! (-> $evidence-row Bool))
(= (forward-remove-canonical-evidence! $row)
   (remove-atom &forward_canonical_evidence $row))

;; &kb contains one canonical fact per grounded output.  The private frontier
;; keeps only the independent, non-dominated candidates required to update that
;; canonical fact when later evidence supersedes just one branch.  Exact-map
;; rows start with a hash of the complete output identity, followed by that
;; identity so unification still rejects the rare hash collision.
(: forward-store-output-candidate!
   (-> ($kb $type) (| ForwardOutputCandidate (List $no-candidate)) ForwardOutputChange))
(= (forward-store-output-candidate! ($kb $type) $new-candidate)
   (let*
      (($hash (forward-output-index-hash ($kb $type)))
       ($old-evidence-rows
          (collapse
             (match &forward_canonical_evidence
                ($hash $type $kb $stored-fact $stored-ev)
                ($hash $type $kb $stored-fact $stored-ev))))
       ($old-row
          (if (== $old-evidence-rows ()) ()
             (car-atom $old-evidence-rows)))
       ($old-fact
          (if (== $old-row ()) ()
             (let ($_hash $_type $_kb $fact $_ev) $old-row $fact)))
       ($old-ev
          (if (== $old-row ()) ()
             (let ($_hash $_type $_kb $_fact $ev) $old-row $ev))))
      (if (= $new-candidate (forward-output-candidate $new-fact $new-ev))
         (if (not (== $old-fact ()))
            (if (and (== $old-fact $new-fact) (== $old-ev $new-ev))
               no-forward-change
               (let*
                  (($_remove-fact
                       (forward-remove-canonical-fact! $old-fact))
                   ($_remove-evidence
                       (foreach-flat forward-remove-canonical-evidence! $old-evidence-rows))
                   ($_add-fact (chainer-add-atom &kb $new-fact))
                   ($_add-evidence
                       (add-atom &forward_canonical_evidence
                          ($hash $type $kb $new-fact $new-ev))))
                  (forward-output-change $old-fact $new-fact)))
            (let*
               (($_add-fact (chainer-add-atom &kb $new-fact))
                ($_add-evidence
                    (add-atom &forward_canonical_evidence
                       ($hash $type $kb $new-fact $new-ev))))
               (forward-output-change () $new-fact)))
         (if (== $old-fact ()) no-forward-change
            (let*
               (($_remove-fact
                    (forward-remove-canonical-fact! $old-fact))
                ($_remove-evidence
                    (foreach-flat forward-remove-canonical-evidence! $old-evidence-rows)))
               (forward-output-change $old-fact ()))))))

(: forward-refresh-output-key! (-> ($kb $type) ForwardOutputChange))
(= (forward-refresh-output-key! $key)
   (forward-store-output-candidate!
      $key (forward-output-candidate-for-key $key)))

(: forward-output-row-for-fact
   (-> ($type $kb $proof $truth-value) (($type $kb $proof $truth-value) (List $evidence))))
(= (forward-output-row-for-fact $fact)
   (let ($type $kb $_prf $_tv) $fact
      (let $hash (forward-output-index-hash ($kb $type))
         (match &forward_canonical_evidence
            ($hash $type $kb $canonical $ev)
            ($canonical $ev)))))

;; Compiler-generated base-rate folds all reduce to additive evidence totals.
;; Keep those totals for forward-processed canonical outputs so each changed
;; output costs one subtraction and one addition instead of another graph fold.
(: forward-base-rate-supported? (-> $extractor $accumulator Bool))
(= (forward-base-rate-supported? $extractor $fun)
   (case $fun (
      (BaseRateAcc (== $extractor extract-tv))
      (WeightedBaseRateAcc
         (if (= $extractor (extract-inheritance-tv $_kbid $_pattern)) true false))
      (WeightedBaseRateWithPriorAcc
         (if (= $extractor (extract-inheritance-tv $_kbid $_pattern)) true false))
      ($_other false))))

(: forward-register-base-rate!
   (-> $kb $pattern $extractor $initial $accumulator $finish $tv-mode (List $none)))
(= (forward-register-base-rate!
      $kbid $pattern $extractor $init $fun $finish $tv-mode)
   (if (not (forward-base-rate-supported? $extractor $fun)) ()
      (let*
         (($trigger (forward-type-trigger-key $kbid $pattern))
          ($hits
             (collapse
                (once
                   (match &forward_base_rate_interest
                      ($trigger $stored-id $kbid $stored-pattern
                         $stored-extractor $stored-init $fun $finish $tv-mode)
                      (if (and (=alpha $stored-pattern $pattern)
                               (=alpha ($stored-extractor $stored-init)
                                  ($extractor $init)))
                         $stored-id
                         (empty)))))))
         (if (== $hits ())
            (let*
               (($id (next-search-id fwd_br_id))
                (($stored-pattern $stored-extractor $stored-init)
                   (copy_term ($pattern $extractor $init)))
                ($_interest
                   (add-atom &forward_base_rate_interest
                      ($trigger $id $kbid $stored-pattern $stored-extractor
                         $stored-init $fun $finish $tv-mode)))
                ($_state
                   (add-atom &forward_base_rate_state ($id 0.0 0.0))))
               ())
            ()))))

(: forward-register-base-rate-premise! (-> $premise (List $none)))
(= (forward-register-base-rate-premise! $premise)
   (case $premise (
      ((CPU FoldAllCompiled
          ($kbid $pattern $extractor $init $fun $finish $tv-mode)
          $_result)
         (forward-register-base-rate!
            $kbid $pattern $extractor $init $fun $finish $tv-mode))
      ($_other ()))))

(: register-forward-base-rate-premises!
   (-> (List Expression) (List $none)))
(= (register-forward-base-rate-premises! $premises)
   (foreach-flat forward-register-base-rate-premise! $premises))

;; compile-inheritance-query emits this one two-sided fold shape.  Register it
;; separately from ordinary base rates: its contribution is keyed by the
;; shared Member object and must be recomputed from both canonical outputs.
(: forward-register-member-inheritance-premise!
   (-> Expression (List $none)))
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
         (if (or
                (not (== (extract-vars $subj) ()))
                (not (== (extract-vars $concept) ()))) ()
            (let*
            (($pattern
                (MemberInheritanceSample $obj $subj $concept $atv $btv))
             ($key (fwd_member $kbid $subj $concept))
             ($hits
                (collapse
                   (once
                      (match &forward_member_inheritance_identity
                         ($key $stored-id) $stored-id)))))
            (if (== $hits ())
               (let*
                  (($id (next-search-id fwd_member_inheritance_id))
                   (($stored-pattern $stored-subj $stored-concept)
                      (copy_term ($pattern $subj $concept)))
                   ($_identity
                      (add-atom &forward_member_inheritance_identity
                         ($key $id)))
                   ($_subject
                      (add-atom &forward_member_inheritance_interest
                         ((fwd_member $kbid $stored-subj) $id $kbid
                            $stored-subj $stored-concept $stored-pattern)))
                   ($_concept
                      (if (== $stored-subj $stored-concept) ()
                         (add-atom &forward_member_inheritance_interest
                            ((fwd_member $kbid $stored-concept) $id $kbid
                               $stored-subj $stored-concept $stored-pattern))))
                   ($_state
                      (add-atom &forward_member_inheritance_state
                         ($id 0.0 0.0))))
                  ())
               ()))))
      ($_other ()))))

(: register-forward-member-inheritance-premises!
   (-> (List Expression) (List $none)))
(= (register-forward-member-inheritance-premises! $premises)
   (foreach-flat forward-register-member-inheritance-premise! $premises))

(: forward-positive-base-rate-contribution
   (-> TV BaseRateEvidenceState))
(= (forward-positive-base-rate-contribution $tv)
   (case $tv (
      ((STV $s $c) (BaseRateEvidence (* $s $c) $c))
      ((CTV $positive $_negative)
         (forward-positive-base-rate-contribution $positive))
      ($_other (BaseRateEvidence 0.0 0.0)))))

(: forward-inheritance-mass-scale (-> $kb Number))
(= (forward-inheritance-mass-scale $kbid)
   (let $universe-size (kb-universe-size $kbid)
      (if (== $universe-size no-universe-size)
         (let $n (list-len (inheritance-subjects $kbid))
            (if (<= $n 0) 0.0 (/ 1.0 $n)))
         (let $size (the Number $universe-size)
            (if (<= $size 0.0) 0.0 (/ 1.0 $size))))))

(: forward-base-rate-accumulator
   (-> $kb $extractor (| BaseRateEvidenceState BaseRateEvidenceWithPriorState) $accumulator Number Number (| BaseRateEvidenceState BaseRateEvidenceWithPriorState)))
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
   (-> $id Number Number Number Number Bool))
(= (forward-store-base-rate-state! $id $old-wsum $old-csum $wsum $csum)
   (progn
      (remove-atom &forward_base_rate_state ($id $old-wsum $old-csum))
      (add-atom &forward_base_rate_state ($id $wsum $csum))))

(: forward-store-base-rate-observation!
   (-> $observation-key (List ($stored-key $fact Number Number)) $fact Number Number Bool))
(= (forward-store-base-rate-observation!
      $observation-key $old-observations $fact $weight $count)
   (progn
      (foreach-flat
         (|-> ($old) (remove-atom &forward_base_rate_observation $old))
         $old-observations)
      (add-atom &forward_base_rate_observation
         ($observation-key $fact $weight $count))))

(: forward-update-base-rate-interest
   (-> ($type $fact-kb $proof TV) $id $kb $pattern $extractor $initial $function $finish (List $none)))
(= (forward-update-base-rate-interest
      $fact $id $kbid $pattern $extractor $init $fun $finish)
   (let*
      (($cache-pattern (copy_term $pattern))
       (($type ($fact-kbid MAIN Nil) $_prf $tv) (copy_term $fact))
       ($_kb (let $kbid $fact-kbid ok))
       ($_pattern (let $pattern $type ok))
       ($output-key (forward-fact-key $fact))
       ($observation-key ($id $output-key))
       ($old-observations
          (the (List ($stored-key $stored-fact Number Number))
             (collapse
                (match &forward_base_rate_observation
                   ($observation-key $old-fact $old-weight $old-count)
                   ($observation-key $old-fact $old-weight $old-count)))))
       (($old-weight $old-count)
          (if (== $old-observations ()) (0.0 0.0)
             (let (cons ($_old-key $_old-fact $ow $oc) $_rest)
                $old-observations
                ($ow $oc))))
       ((BaseRateEvidence $weight $count)
          (forward-positive-base-rate-contribution $tv))
       (($old-wsum $old-csum)
          (the (Number Number)
             (match &forward_base_rate_state ($id $stored-wsum $stored-csum)
                ($stored-wsum $stored-csum))))
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
             $kbid $extractor
             (the (| BaseRateEvidenceState BaseRateEvidenceWithPriorState) $init)
             $fun $wsum $csum))
       ($estimate (the TV (eval (finish-aggregate $finish $acc))))
       ($_cache
          (store-forward-base-rate! $kbid $cache-pattern $estimate $finish)))
      ()))

(: forward-update-base-rates-for-key
   (-> ($type $kb $proof TV) ForwardTriggerKey (List $none)))
(= (forward-update-base-rates-for-key $fact $trigger)
   (match &forward_base_rate_interest
      ($trigger $id $kbid $pattern $extractor $init $fun $finish $_tv-mode)
      (forward-update-base-rate-interest
         $fact $id $kbid $pattern $extractor $init $fun $finish)))

(: forward-update-base-rates
   (-> ($type $kb $proof TV) (List $none)))
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
   (-> $kb $object $class
       (| (List $none)
          (($type $kb $proof TV) (List Evidence)))))
(= (forward-member-canonical $kbid $obj $class)
   (let $rows
      (collapse
         (once
            (forward-output-row-for-fact
               ((Member $obj $class) ($kbid MAIN Nil) $_prf $_tv))))
      (if (== $rows ()) () (car-atom $rows))))

(: forward-store-member-inheritance-state!
   (-> Number Number Number Number Number Bool))
(= (forward-store-member-inheritance-state!
      $id $old-wsum $old-msum $wsum $msum)
   (progn
      (remove-atom &forward_member_inheritance_state
         ($id $old-wsum $old-msum))
      (add-atom &forward_member_inheritance_state ($id $wsum $msum))))

(: forward-update-member-inheritance-interest
   (-> $object Number $kb $subject $concept $pattern (List $none)))
(= (forward-update-member-inheritance-interest
      $obj $id $kbid $subj $concept $pattern)
   (let*
      (($observation-key ($id $obj))
       ($old-observations
          (collapse
             (match &forward_member_inheritance_observation
                ($observation-key $old-subject $old-concept
                   $old-weight $old-mass)
                ($observation-key $old-subject $old-concept
                   $old-weight $old-mass))))
       (($old-weight $old-mass)
          (if (== $old-observations ()) (0.0 0.0)
             (let ($_key $_asubj $_aconcept $weight $mass)
                (car-atom $old-observations) ($weight $mass))))
       ($subject (forward-member-canonical $kbid $obj $subj))
       ($consequent (forward-member-canonical $kbid $obj $concept))
       (($weight $mass)
          (if (or (== $subject ()) (== $consequent ())) (0.0 0.0)
             (let*
                ((($subject-fact $_subject-ev) $subject)
                 (($consequent-fact $_consequent-ev) $consequent)
                 (($_stype $_skb $_sprf $atv) $subject-fact)
                 (($_ctype $_ckb $_cprf $btv) $consequent-fact)
                 ((BaseRateEvidence $joined-weight $joined-mass)
                    (WeightedBaseRateAcc
                       (BaseRateEvidence 0.0 0.0)
                       (WeightedTv $atv $btv))))
                ($joined-weight $joined-mass))))
       (($old-wsum $old-msum)
          (match &forward_member_inheritance_state
             ($id $stored-wsum $stored-msum)
             ($stored-wsum $stored-msum)))
       ($wsum
          (+ (- (the Number $old-wsum) (the Number $old-weight))
             (the Number $weight)))
       ($msum
          (+ (- (the Number $old-msum) (the Number $old-mass))
             (the Number $mass)))
       ($_state
          (forward-store-member-inheritance-state!
             $id $old-wsum $old-msum $wsum $msum))
       ($_old
          (foreach-flat
             (|-> ($row)
                (remove-atom &forward_member_inheritance_observation $row))
             $old-observations))
       ($_observation
          (if (or (== $subject ()) (== $consequent ())) ()
             (add-atom &forward_member_inheritance_observation
                ($observation-key $subject $consequent $weight $mass))))
       ($_cache
          (if (<= $msum 0.0)
             (base-rate-cache-remove-derived!
                $kbid $pattern (member-inheritance $kbid))
             (store-forward-base-rate! $kbid $pattern
                (member-inheritance-tv $kbid
                   (BaseRateEvidence $wsum $msum))
                (member-inheritance $kbid)))))
      ()))

(: forward-update-member-inheritances-for-key
   (-> $kb $object $class (List $none)))
(= (forward-update-member-inheritances-for-key $kbid $obj $class)
   (let $_
      (collapse
         (match &forward_member_inheritance_interest
            ((fwd_member $kbid $class) $id $kbid
               $subj $concept $pattern)
            (forward-update-member-inheritance-interest
               $obj (the Number $id) $kbid $subj $concept
               (copy_term $pattern))))
      ()))

(: forward-remove-member-inheritance-observation!
   (-> $object Number $kb $subject $concept $pattern (List $none)))
(= (forward-remove-member-inheritance-observation!
      $obj $id $kbid $subj $concept $pattern)
   (let*
      (($observation-key ($id $obj))
       ($old-observations
          (collapse
             (match &forward_member_inheritance_observation
                ($observation-key $old-subject $old-concept
                   $old-weight $old-mass)
                ($observation-key $old-subject $old-concept
                   $old-weight $old-mass)))))
      (if (== $old-observations ())
         ;; Removal invalidation may run after the canonical-change hook has
         ;; already subtracted this row. Republish the surviving indexed state
         ;; without touching ordinary base-rate cache behavior.
         (let ($wsum $msum)
            (match &forward_member_inheritance_state ($id $wsum $msum)
               (if (<= (the Number $msum) 0.0) ()
                  (store-forward-base-rate! $kbid $pattern
                     (member-inheritance-tv $kbid
                        (BaseRateEvidence
                           (the Number $wsum) (the Number $msum)))
                     (member-inheritance $kbid)))))
         (let*
            ((($_key $_subject $_concept $old-weight $old-mass)
                (car-atom $old-observations))
             (($old-wsum $old-msum)
                (match &forward_member_inheritance_state
                   ($id $stored-wsum $stored-msum)
                   ($stored-wsum $stored-msum)))
             ($wsum (- (the Number $old-wsum) (the Number $old-weight)))
             ($msum (- (the Number $old-msum) (the Number $old-mass)))
             ($_state
                (forward-store-member-inheritance-state!
                   $id $old-wsum $old-msum $wsum $msum))
             ($_old
                (foreach-flat
                   (|-> ($row)
                      (remove-atom &forward_member_inheritance_observation $row))
                   $old-observations))
             ($_cache
                (if (<= $msum 0.0)
                   (base-rate-cache-remove-derived!
                      $kbid $pattern (member-inheritance $kbid))
                   (store-forward-base-rate! $kbid $pattern
                      (member-inheritance-tv $kbid
                         (BaseRateEvidence $wsum $msum))
                      (member-inheritance $kbid))))
             ;; If another proof still supports the removed side, add its
             ;; refreshed canonical join after subtracting the stale one.
             ($_replacement
                (if (or
                       (== (forward-member-canonical $kbid $obj $subj) ())
                       (== (forward-member-canonical $kbid $obj $concept) ()))
                   ()
                   (forward-update-member-inheritance-interest
                      $obj $id $kbid $subj $concept (copy_term $pattern)))))
            ()))))

(: forward-remove-member-inheritances-for-key
   (-> $kb $object $class (List $none)))
(= (forward-remove-member-inheritances-for-key $kbid $obj $class)
   (let $_
      (collapse
         (match &forward_member_inheritance_interest
            ((fwd_member $kbid $class) $id $kbid
               $subj $concept $pattern)
            (forward-remove-member-inheritance-observation!
               $obj (the Number $id) $kbid $subj $concept
               (copy_term $pattern))))
      ()))

(: forward-remove-member-inheritances
   (-> ($type $kb $proof TV) (List $none)))
(= (forward-remove-member-inheritances $fact)
   (case $fact (
      (((Member $obj $class) ($kbid MAIN Nil) $_prf $_tv)
         (forward-remove-member-inheritances-for-key $kbid $obj $class))
      ($_other ()))))

(: forward-update-member-inheritances
   (-> ($type $kb $proof TV) (List $none)))
(= (forward-update-member-inheritances $fact)
   (case $fact (
      (((Member $obj $class) ($kbid MAIN Nil) $_prf $_tv)
         (forward-update-member-inheritances-for-key $kbid $obj $class))
      ($_other ()))))

(: forward-invalidate-base-rates-for-key!
   (-> $fact ForwardTriggerKey (List $none)))
(= (forward-invalidate-base-rates-for-key! $fact $trigger)
   (match &forward_base_rate_interest
      ($trigger $_id $kbid $pattern $_extractor $_init $_fun $finish $_tv-mode)
      (base-rate-cache-remove-derived! $kbid $pattern $finish)))

(: forward-invalidate-base-rates! (-> ($type $kb $proof TV) (List $none)))
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
   (-> ($type $fact-kb $proof TV) $id $kb $pattern $extractor $initial $function $finish (List $none)))
(= (forward-remove-base-rate-observation!
      $fact $id $kbid $pattern $extractor $init $fun $finish)
   (let*
      (($output-key (forward-fact-key $fact))
       ($observation-key ($id $output-key))
       ($old-observations
          (the (List ($stored-key $stored-fact Number Number))
             (collapse
                (match &forward_base_rate_observation
                   ($observation-key $old-fact $old-weight $old-count)
                   ($observation-key $old-fact $old-weight $old-count))))))
      (if (== $old-observations ()) ()
         (let*
            (((cons ($_key $_old-fact $old-weight $old-count) $_rest)
                $old-observations)
             (($old-wsum $old-csum)
                (the (Number Number)
                   (match &forward_base_rate_state
                      ($id $stored-wsum $stored-csum)
                      ($stored-wsum $stored-csum))))
             ($wsum (- $old-wsum $old-weight))
             ($csum (- $old-csum $old-count))
             ($_state
                (forward-store-base-rate-state!
                   $id $old-wsum $old-csum $wsum $csum))
             ($_observations
                (foreach-flat
                   (|-> ($old)
                      (remove-atom &forward_base_rate_observation $old))
                   $old-observations))
             ($_cache
                (if (<= $csum 0.0)
                   (base-rate-cache-remove-derived! $kbid $pattern $finish)
                   (let*
                      (($acc
                          (forward-base-rate-accumulator
                             $kbid $extractor
                             (the (| BaseRateEvidenceState BaseRateEvidenceWithPriorState) $init)
                             $fun $wsum $csum))
                       ($estimate
                          (the TV (eval (finish-aggregate $finish $acc)))))
                      (store-forward-base-rate!
                         $kbid $pattern $estimate $finish)))))
            ()))))

(: forward-remove-base-rate-observations-for-key!
   (-> ($type $kb $proof TV) ForwardTriggerKey (List $none)))
(= (forward-remove-base-rate-observations-for-key! $fact $trigger)
   (match &forward_base_rate_interest
      ($trigger $id $kbid $pattern $extractor $init $fun $finish $_tv-mode)
      (let $stored-pattern (copy_term $pattern)
         (forward-remove-base-rate-observation!
            $fact $id $kbid $stored-pattern
            $extractor $init $fun $finish))))

(: forward-remove-base-rate-observations!
   (-> ($type $kb $proof TV) (List $none)))
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
   (-> Number (List Expression) ($type $kb $proof TV)
       (List Evidence) ForwardMatch))
(= (forward-satisfy-premises $steps () $goal $ev) (forward-match $goal $ev))
(= (forward-satisfy-premises $steps (cons $prem $rest) $goal $ev)
   (if (= $prem (CPU $fun $args $res))
      (let $res (reduce (cpu-call $steps $fun $args))
         (forward-satisfy-premises $steps $rest $goal $ev))
      (if (= $prem ($_type ($_kbid $_ctx $_vars) $_prf $_tv))
         (match &kb $prem
            (forward-satisfy-premises $steps $rest $goal
               (list_to_set (append $ev (forward-fact-evidence $prem)))))
         (empty))))

(: agenda-push-fact (-> $heap ($type $kb $proof TV) $heap))
(= (agenda-push-fact $agenda $fact)
   (add_to_heap $agenda (- 0 (term-confidence $fact)) (qitem $fact)))

(: forward-seed-agenda-step (-> $heap ($type $kb $proof TV) $heap))
(= (forward-seed-agenda-step $agenda $fact)
   (let $rows (collapse (once (forward-output-row-for-fact $fact)))
      (if (== $rows ()) (agenda-push-fact $agenda $fact)
         (let ($canonical $_ev) (car-atom $rows)
            (agenda-push-fact $agenda $canonical)))))

(: forward-build-agenda-from-facts
   (-> (List ($type $kb $proof TV)) $heap))
(= (forward-build-agenda-from-facts $facts)
   (fold-flat forward-seed-agenda-step (empty_heap) (list_to_set $facts)))

(: agenda-push-forward-change (-> $heap ForwardOutputChange $heap))
(= (agenda-push-forward-change $agenda no-forward-change) $agenda)
(= (agenda-push-forward-change $agenda (forward-output-change $old ()))
   (let*
      (($_remove-base-rate (forward-remove-base-rate-observations! $old))
       ($_remove-member (forward-remove-member-inheritances $old)))
      $agenda))
(= (agenda-push-forward-change $agenda (forward-output-change $old $fact))
   (let*
      (($_invalidate-old
          (if (== $old ()) () (forward-invalidate-base-rates! $old)))
       ($_invalidate-new (forward-invalidate-base-rates! $fact)))
      (agenda-push-fact $agenda $fact)))

;; Apply cache bookkeeping for canonical changes made outside a forward run.
(: forward-apply-unqueued-change!
   (-> ForwardOutputChange (| (List $none) Bool)))
(= (forward-apply-unqueued-change! no-forward-change) ())
(= (forward-apply-unqueued-change! (forward-output-change $old ()))
   (progn
      (forward-remove-base-rate-observations! $old)
      (forward-remove-member-inheritances $old)))
(= (forward-apply-unqueued-change! (forward-output-change $old $fact))
   (progn
      (if (== $old ()) () (forward-invalidate-base-rates! $old))
      (forward-invalidate-base-rates! $fact)))

(: forward-strict-evidence-subset?
   (-> (List $evidence) (List $evidence) Bool))
(= (forward-strict-evidence-subset? $subset $superset)
   (and (evidence-subset? $subset $superset)
      (not (evidence-subset? $superset $subset))))

(: forward-proof-list-refines? (-> (List $proof) (List $proof) Bool))
(= (forward-proof-list-refines? $old $new)
   (if (== $old ()) (== $new ())
      (if (== $new ()) false
         (and (forward-proof-refines? (car-atom $old) (car-atom $new))
            (forward-proof-list-refines? (cdr-atom $old) (cdr-atom $new))))))

;; A proof refines another when it has the same rule skeleton and only replaces
;; children by merges containing the earlier child. This distinguishes a
;; genuinely updated application, pToQ(p1) -> pToQ(merge(p1,p2)), from a longer
;; cyclic path such as seed -> keepLoop(seed).
(: forward-proof-refines? (-> $proof $proof Bool))
(= (forward-proof-refines? $old $new)
   (if (== $old $new) true
      (if (is-expr $new)
         (if (= $new (merge/revision $left $right))
            (or (forward-proof-refines? $old $left)
               (forward-proof-refines? $old $right))
            (if (and (is-expr $old)
                     (== (car-atom $old) (car-atom $new)))
               (forward-proof-list-refines?
                  (cdr-atom $old) (cdr-atom $new))
               false))
         false)))

(: forward-candidate-refines?
   (-> ($old-type $old-kb $old-proof TV) (List $evidence) ($new-type $new-kb $new-proof TV) (List $evidence) Bool))
(= (forward-candidate-refines? $old-fact $old-ev $new-fact $new-ev)
   (and (forward-strict-evidence-subset? $old-ev $new-ev)
      (forward-proof-refines?
         (proof-atom-proof $old-fact) (proof-atom-proof $new-fact))))

;; A larger evidence set for the same output supersedes the partial estimate
;; even when the new TV has lower confidence.  Disjoint candidates remain in
;; the frontier and are revised together.  Incomparable overlapping candidates
;; retain the existing conservative policy of keeping only the stronger one.
(: forward-frontier-old-dominates-new?
   (-> ($old-type $old-kb $old-proof TV) (List $evidence) ($new-type $new-kb $new-proof TV) (List $evidence) Bool))
(= (forward-frontier-old-dominates-new? $old-fact $old-ev $new-fact $new-ev)
   (if (== (proof-atom-proof $old-fact) (proof-atom-proof $new-fact)) false
      (if (projection-dominates?
             (proof-atom-proof $old-fact) (proof-atom-proof $new-fact))
         true
         (if (projection-dominates?
                (proof-atom-proof $new-fact) (proof-atom-proof $old-fact))
            false
            (if (forward-candidate-refines?
                   $old-fact $old-ev $new-fact $new-ev) false
               (if (forward-candidate-refines?
                      $new-fact $new-ev $old-fact $old-ev) true
                  (if (evidence-sets-overlap? $old-ev $new-ev)
                     (>= (term-confidence $old-fact) (term-confidence $new-fact))
                     false)))))))

(: forward-frontier-new-dominates-old?
   (-> ($new-type $new-kb $new-proof TV) (List $evidence) ($old-type $old-kb $old-proof TV) (List $evidence) Bool))
(= (forward-frontier-new-dominates-old? $new-fact $new-ev $old-fact $old-ev)
   (if (== (proof-atom-proof $old-fact) (proof-atom-proof $new-fact)) true
      (if (projection-dominates?
             (proof-atom-proof $new-fact) (proof-atom-proof $old-fact))
         true
         (if (projection-dominates?
                (proof-atom-proof $old-fact) (proof-atom-proof $new-fact))
            false
            (if (forward-candidate-refines?
                   $old-fact $old-ev $new-fact $new-ev) true
               (if (forward-candidate-refines?
                      $new-fact $new-ev $old-fact $old-ev) false
                  (if (evidence-sets-overlap? $old-ev $new-ev)
                     (> (term-confidence $new-fact) (term-confidence $old-fact))
                     false)))))))

(: forward-frontier-has-exact?
   (-> ($kb $type) $fact (List $evidence) Bool))
(= (forward-frontier-has-exact? ($kb $type) $fact $ev)
   (let $hash (forward-output-index-hash ($kb $type))
      (not (==
         (collapse
            (once
               (match &forward_frontier
                  ($hash $type $kb $fact $ev) true)))
         ()))))

(: forward-frontier-rejects?
   (-> ($kb $type) $fact (List $evidence) Bool))
(= (forward-frontier-rejects? ($kb $type) $fact $ev)
   (let $hash (forward-output-index-hash ($kb $type))
      (not (==
         (collapse
            (once
               (match &forward_frontier
                  ($hash $type $kb $old-fact $old-ev)
                  (if (forward-frontier-old-dominates-new?
                         $old-fact (the (List Evidence) $old-ev) $fact $ev)
                     true
                     (empty)))))
         ()))))

(: forward-prune-frontier-for!
   (-> ($kb $type) $fact (List $evidence) (List $none)))
(= (forward-prune-frontier-for! ($kb $type) $fact $ev)
   (let $hash (forward-output-index-hash ($kb $type))
      (collapse
         (match &forward_frontier
            ($hash $type $kb $old-fact $old-ev)
            (if (forward-frontier-new-dominates-old?
                   $fact $ev $old-fact (the (List Evidence) $old-ev))
               (remove-atom &forward_frontier
                  ($hash $type $kb $old-fact $old-ev))
               ())))))

(: forward-record-inheritance-nodes!
   (-> $fact (| Bool (List $none))))
(= (forward-record-inheritance-nodes! $fact)
   (case $fact (
      (((Inheritance $subj $concept) ($kbid $_ctx $_vars) $_prf $_tv)
         (if (is-var $subj) ()
            (progn
               (add-atom &inheritance_subject ($kbid $subj))
               (record-inheritance-nodes! $kbid $subj $concept))))
      ($_other ()))))

(: forward-add-frontier-row!
   (-> ($kb $type) $fact (List $evidence) (List $none)))
(= (forward-add-frontier-row! ($kb $type) $fact $ev)
   (let*
      (($hash (forward-output-index-hash ($kb $type)))
       ($_nodes (forward-record-inheritance-nodes! $fact))
       ($_frontier
          (chainer-add-atom &forward_frontier
             ($hash $type $kb $fact $ev))))
      ()))

(: forward-add-first-candidate!
   (-> ($kb $type) $fact (List $evidence) ForwardOutputChange))
(= (forward-add-first-candidate! $output-key $fact $ev)
   (let $_add (forward-add-frontier-row! $output-key $fact $ev)
      (forward-store-output-candidate!
         $output-key (forward-output-candidate $fact $ev))))

;; Disjoint evidence cannot evict an existing frontier branch.  Merge directly
;; with the cached canonical fact instead of scanning and folding the frontier.
(: forward-add-disjoint-candidate!
   (-> ($kb $type) $canonical (List $evidence) $fact (List $evidence) ForwardOutputChange))
(= (forward-add-disjoint-candidate!
      $output-key $canonical $canonical-ev $fact $ev)
   (let*
      (($_add (forward-add-frontier-row! $output-key $fact $ev))
       (($merged $merged-ev)
          (merge-proof-candidates
             ($canonical $canonical-ev)
             ($fact $ev))))
      (forward-store-output-candidate!
         $output-key (forward-output-candidate $merged $merged-ev))))

(: forward-candidate-upsert! (-> ForwardDerived ForwardOutputChange))
(= (forward-candidate-upsert! (forward-derived $fact $ev))
   (let $output-key (forward-fact-key $fact)
      (if (forward-frontier-has-exact? $output-key $fact $ev) no-forward-change
         (let $canonical-rows
            (collapse (once (forward-output-row-for-fact $fact)))
            (if (== $canonical-rows ())
               (forward-add-first-candidate! $output-key $fact $ev)
               (let ($canonical $canonical-ev-raw) (car-atom $canonical-rows)
                  (let $canonical-ev
                     (the (List Evidence) $canonical-ev-raw)
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
                              (forward-refresh-output-key! $output-key)))))))))))

(: forward-rule-results-for-key
   (Number $kb $fact ForwardTriggerKey -[det]-> (List ForwardDerived)))
(= (forward-rule-results-for-key $steps $kb $fact $key)
   (collapse
      (let*
         ((($id $idx) (match prem_index ($key $fact $id $idx) ($id $idx)))
           (($id $ccls $prems) (match rules ($id $ccls $prems) ($id $ccls $prems)))
           ($rprems
              (the (List Expression) (nth0 $idx $prems $fact)))
           (($trigger-fact $trigger-ev-raw)
              (forward-output-row-for-fact $fact))
           ($trigger-ev (the (List Evidence) $trigger-ev-raw))
           ((forward-match $result $premise-ev)
              (forward-satisfy-premises
                 $steps $rprems $ccls $trigger-ev)))
         (forward-derived $result
            (rule-result-evidence $result $premise-ev)))))

(: forward-rule-results
   (Number $kb $fact -[det]-> (List ForwardDerived)))
(= (forward-rule-results $steps $kb $fact)
   (let*
      (($key (forward-premise-index-key $fact))
        ($wildcard-key (forward-premise-wildcard-key $fact))
        ($direct (forward-rule-results-for-key $steps $kb $fact $key))
        ($wildcard
           (if (== $key $wildcard-key) (the (List ForwardDerived) ())
              (forward-rule-results-for-key
                 $steps $kb $fact $wildcard-key))))
      (union-atom $direct $wildcard)))

(: forward-run-apply-derived
   (-> ForwardRun ForwardDerived ForwardRun))
(= (forward-run-apply-derived (forward-run $agenda $changed) $derived)
   (let $change (forward-candidate-upsert! $derived)
      (let $nagenda (agenda-push-forward-change $agenda $change)
         (if (= $change (forward-output-change $_old $fact))
            ;; Keep output identities, not intermediate fact versions. At the
            ;; end of the run each identity resolves to its final canonical fact.
            (forward-run $nagenda (cons (forward-fact-key $fact) $changed))
            (forward-run $nagenda $changed)))))

(: forward-step-fact
   (-> Number $kb ForwardRun ($type $fact-kb $proof TV) ForwardRun))
(= (forward-step-fact $steps $kb $run $fact)
   (let*
      (($_base-rates (forward-update-base-rates $fact))
        ($_member-inheritances (forward-update-member-inheritances $fact))
        ($derived (forward-rule-results $steps $kb $fact))
        ($nrun (fold-flat forward-run-apply-derived $run $derived)))
      $nrun))

;; If several derivations update one output before it is processed, only its
;; latest canonical version should run.  Explicit non-KB seeds have no
;; canonical row and are therefore always current.
(: forward-queued-fact-current? (-> ($type $kb $proof TV) Bool))
(= (forward-queued-fact-current? $fact)
   (let $rows (collapse (once (forward-output-row-for-fact $fact)))
      (if (== $rows ()) true
         (let ($canonical $_ev) (car-atom $rows)
            (== $canonical $fact)))))

(: forward-loop (-> Number $kb ForwardRun ForwardRun))
(= (forward-loop $steps $kb (forward-run $agenda $changed))
   (if (or (== (heap_size $agenda) 0) (<= $steps 0))
      (forward-run $agenda $changed)
      (let $rest (get_from_heap $agenda $_priority $item)
         (let (qitem $fact) (the ForwardQueueItem $item)
            (if (forward-queued-fact-current? $fact)
               (let*
                  (($next-steps (- $steps 1))
                   ((forward-run $nagenda $nchanged)
                      (forward-step-fact $steps $kb
                         (forward-run $rest $changed) $fact)))
                  (forward-loop $next-steps $kb
                     (forward-run
                        (bounded-agenda-prune $next-steps $nagenda)
                        $nchanged)))
               (forward-loop $steps $kb (forward-run $rest $changed)))))))

(: forward-canonical-fact-for-key
   (-> ($kb $type) ($type $kb $proof TV)))
(= (forward-canonical-fact-for-key ($kb $type))
   (let $hash (forward-output-index-hash ($kb $type))
      (the ($type $kb $proof TV)
         (match &forward_canonical_evidence
            ($hash $type $kb $fact $_ev) $fact))))

(: forward-run-changed-facts
   (-> ForwardRun (List ($type $kb $proof TV))))
(= (forward-run-changed-facts (forward-run $_agenda $changed))
   (map-flat forward-canonical-fact-for-key (list_to_set $changed)))

(: forward-chain
   (Number $kb (List ($type $fact-kb $proof TV))
      -[det]-> (List ($type $fact-kb $proof TV))))
(= (forward-chain $steps $kb $facts)
   (let*
      (($agenda (forward-build-agenda-from-facts $facts))
       ($run (forward-loop $steps $kb (forward-run $agenda ()))))
      (forward-run-changed-facts $run)))

(: forward-has-derived? (-> $kb $type Bool))
(= (forward-has-derived? $kb $type)
   (not (==
      (collapse
         (match &kb ($type ($kb MAIN Nil) $prf $_tv)
            $prf))
      ())))
