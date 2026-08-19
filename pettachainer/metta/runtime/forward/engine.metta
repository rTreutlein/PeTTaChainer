;; Forward rule matching, candidate acceptance, agenda execution, and API.
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
             (let $_remove
                (forward-maintain-aggregates!
                   aggregate-remove $old)
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
             (forward-maintain-aggregates!
                aggregate-remove $old))
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
      (($_aggregates
          (forward-maintain-aggregates! aggregate-update $fact))
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
