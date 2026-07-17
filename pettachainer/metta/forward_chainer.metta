!(import_prolog_function nth0)

(= (forward-agenda-dirty-key $kb) (atom_concat fwd_agenda_dirty_ $kb))
(= (forward-agenda-gen-key $kb) (atom_concat fwd_agenda_gen_ $kb))
(= (forward-agenda-scope-key $kb) (atom_concat fwd_agenda_scope_ $kb))
(= (forward-query-run-gen-key $kb) (atom_concat fwd_query_run_gen_ $kb))

(= (forward-type-trigger-key $kbid $type)
   (if (is-var $type) (fwd_trigger $kbid any)
      (if (is-expr $type)
         (let $head (car-atom $type) (if (is-var $head) (fwd_trigger $kbid any) (fwd_trigger $kbid $head)))
         (fwd_trigger $kbid $type))))

(= (forward-indexable-premise-key $prem)
   (if (= $prem ($_type ($kbid $_ctx $_vars) $_prf $_tv)) (forward-type-trigger-key $kbid $_type) ()))

(= (forward-premise-index-key $prem)
   (let $key (forward-indexable-premise-key $prem) (if (== $key ()) fwd_trigger_any $key)))

(= (forward-premise-wildcard-key $prem)
   (if (= $prem ($_type ($kbid $_ctx $_vars) $_prf $_tv)) (fwd_trigger $kbid any) fwd_trigger_any))

(= (forward-load-agenda $kb)
   (let $magenda (catch (get-state (atom_concat fwd_agenda_ $kb)))
      (if-error $magenda (empty_heap) $magenda)))

(= (forward-save-agenda $kb $agenda) (change-state! (atom_concat fwd_agenda_ $kb) $agenda))
(= (forward-set-agenda-dirty $kb $dirty) (change-state! (forward-agenda-dirty-key $kb) $dirty))

(= (forward-agenda-dirty? $kb)
   (let $mdirty (catch (get-state (forward-agenda-dirty-key $kb)))
      (if-error $mdirty true $mdirty)))

(= (forward-current-agenda-gen $kb)
   (let $mgen (catch (get-state (forward-agenda-gen-key $kb)))
      (if-error $mgen 0 $mgen)))

(= (forward-current-query-run-gen $kb)
   (let $mgen (catch (get-state (forward-query-run-gen-key $kb)))
      (if-error $mgen 0 $mgen)))

(= (forward-next-agenda-gen $kb)
   (let*
      (($gen (+ 1 (forward-current-agenda-gen $kb)))
        ($_ (change-state! (forward-agenda-gen-key $kb) $gen)))
      $gen))

(= (forward-next-query-run-gen $kb)
   (let*
      (($gen (+ 1 (forward-current-query-run-gen $kb)))
        ($_ (change-state! (forward-query-run-gen-key $kb) $gen)))
      $gen))

(= (forward-current-agenda-scope $kb)
   (let $mscope (catch (get-state (forward-agenda-scope-key $kb)))
      (if-error $mscope (kb $kb) $mscope)))

(= (forward-set-agenda-scope $kb $scope) (change-state! (forward-agenda-scope-key $kb) $scope))

(= (forward-new-query-scope $kb) (fwd_query_scope $kb (forward-next-query-run-gen $kb)))

(= (mark-forward-agenda-dirty $expr)
   (if (= $expr ($_type ($kbid MAIN Nil) $_prf $_tv))
      (forward-set-agenda-dirty $kbid true)
      ()))

(= (forward-fact-key ($type ($kbid $ctx $vars) $_prf $_tv)) (($kbid $ctx $vars) $type))
(= (forward-fact-kb ($type ($kbid $_ctx $_vars) $_prf $_tv)) $kbid)
(= (forward-output-index-hash ($kb $type)) (term_hash ($kb $type)))

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
                  ((fact-ev $kb $prf $type))
                  (car-atom $frontier-hits)))
            (car-atom $hits))))

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

(= (forward-output-candidate-for-key ($kb $type))
   (let $hash (forward-output-index-hash ($kb $type))
      (fold-flat forward-output-candidate-step ()
         (collapse
            (match &forward_frontier
               ($hash $type $kb $fact $ev)
               ($hash $type $kb $fact $ev))))))

(= (forward-remove-canonical-fact! $fact) (remove-atom &kb $fact))
(= (forward-remove-canonical-evidence! $row)
   (remove-atom &forward_canonical_evidence $row))

;; &kb contains one canonical fact per grounded output.  The private frontier
;; keeps only the independent, non-dominated candidates required to update that
;; canonical fact when later evidence supersedes just one branch.  Exact-map
;; rows start with a hash of the complete output identity, followed by that
;; identity so unification still rejects the rare hash collision.
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

(= (forward-refresh-output-key! $key)
   (forward-store-output-candidate!
      $key (forward-output-candidate-for-key $key)))

(= (forward-output-row-for-fact $fact)
   (let ($type $kb $_prf $_tv) $fact
      (let $hash (forward-output-index-hash ($kb $type))
         (match &forward_canonical_evidence
            ($hash $type $kb $canonical $ev)
            ($canonical $ev)))))

;; Compiler-generated base-rate folds all reduce to additive evidence totals.
;; Keep those totals for forward-processed canonical outputs so each changed
;; output costs one subtraction and one addition instead of another graph fold.
(= (forward-base-rate-supported? $extractor $fun)
   (case $fun (
      (BaseRateAcc (== $extractor extract-tv))
      (WeightedBaseRateAcc
         (if (= $extractor (extract-inheritance-tv $_kbid $_pattern)) true false))
      (WeightedBaseRateWithPriorAcc
         (if (= $extractor (extract-inheritance-tv $_kbid $_pattern)) true false))
      ($_other false))))

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

(= (forward-register-base-rate-premise! $premise)
   (case $premise (
      ((CPU FoldAllCompiled
          ($kbid $pattern $extractor $init $fun $finish $tv-mode)
          $_result)
         (forward-register-base-rate!
            $kbid $pattern $extractor $init $fun $finish $tv-mode))
      ($_other ()))))

(= (register-forward-base-rate-premises! $premises)
   (foreach-flat forward-register-base-rate-premise! $premises))

(= (forward-positive-base-rate-contribution $tv)
   (case $tv (
      ((STV $s $c) (BaseRateEvidence (* $s $c) $c))
      ((CTV $positive $_negative)
         (forward-positive-base-rate-contribution $positive))
      ($_other (BaseRateEvidence 0.0 0.0)))))

(= (forward-inheritance-mass-scale $kbid)
   (let $universe-size (kb-universe-size $kbid)
      (if (== $universe-size no-universe-size)
         (let $n (list-len (inheritance-subjects $kbid))
            (if (<= $n 0) 0.0 (/ 1.0 $n)))
         (if (<= $universe-size 0.0) 0.0 (/ 1.0 $universe-size)))))

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

(= (forward-store-base-rate-state! $id $old-wsum $old-csum $wsum $csum)
   (progn
      (remove-atom &forward_base_rate_state ($id $old-wsum $old-csum))
      (add-atom &forward_base_rate_state ($id $wsum $csum))))

(= (forward-store-base-rate-observation!
      $observation-key $old-observations $fact $weight $count)
   (progn
      (foreach-flat
         (|-> ($old) (remove-atom &forward_base_rate_observation $old))
         $old-observations)
      (add-atom &forward_base_rate_observation
         ($observation-key $fact $weight $count))))

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
          (collapse
             (match &forward_base_rate_observation
                ($observation-key $old-fact $old-weight $old-count)
                ($observation-key $old-fact $old-weight $old-count))))
       (($old-weight $old-count)
          (if (== $old-observations ()) (0.0 0.0)
             (let ($_old-key $_old-fact $ow $oc)
                (car-atom $old-observations) ($ow $oc))))
       ((BaseRateEvidence $weight $count)
          (forward-positive-base-rate-contribution $tv))
       (($old-wsum $old-csum)
          (match &forward_base_rate_state ($id $stored-wsum $stored-csum)
             ($stored-wsum $stored-csum)))
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
             $kbid $extractor $init $fun $wsum $csum))
       ($estimate (aggregate-finish $finish $acc))
       ($_cache
          (store-forward-base-rate! $kbid $cache-pattern $estimate $finish)))
      ()))

(= (forward-update-base-rates-for-key $fact $trigger)
   (match &forward_base_rate_interest
      ($trigger $id $kbid $pattern $extractor $init $fun $finish $_tv-mode)
      (forward-update-base-rate-interest
         $fact $id $kbid $pattern $extractor $init $fun $finish)))

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

(= (forward-invalidate-base-rates-for-key! $fact $trigger)
   (match &forward_base_rate_interest
      ($trigger $_id $kbid $pattern $_extractor $_init $_fun $finish $_tv-mode)
      (base-rate-cache-remove-derived! $kbid $pattern $finish)))

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
(= (forward-remove-base-rate-observation!
      $fact $id $kbid $pattern $extractor $init $fun $finish)
   (let*
      (($output-key (forward-fact-key $fact))
       ($observation-key ($id $output-key))
       ($old-observations
          (collapse
             (match &forward_base_rate_observation
                ($observation-key $old-fact $old-weight $old-count)
                ($observation-key $old-fact $old-weight $old-count)))))
      (if (== $old-observations ()) ()
         (let*
            ((($_key $_old-fact $old-weight $old-count)
                (car-atom $old-observations))
             (($old-wsum $old-csum)
                (match &forward_base_rate_state
                   ($id $stored-wsum $stored-csum)
                   ($stored-wsum $stored-csum)))
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
                             $kbid $extractor $init $fun $wsum $csum))
                       ($estimate (aggregate-finish $finish $acc)))
                      (store-forward-base-rate!
                         $kbid $pattern $estimate $finish)))))
            ()))))

(= (forward-remove-base-rate-observations-for-key! $fact $trigger)
   (match &forward_base_rate_interest
      ($trigger $id $kbid $pattern $extractor $init $fun $finish $_tv-mode)
      (let $stored-pattern (copy_term $pattern)
         (forward-remove-base-rate-observation!
            $fact $id $kbid $stored-pattern
            $extractor $init $fun $finish))))

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

(= (forward-pending-state-key $fact)
   (let $kb (forward-fact-kb $fact)
      (atom_concat fwd_pending_ (term_hash ((forward-current-agenda-scope $kb) (forward-fact-key $fact))))))

(= (forward-pending-score-of $fact)
   (let*
      (($state-key (forward-pending-state-key $fact))
        ($gen (forward-current-agenda-gen (forward-fact-kb $fact)))
        ($entry (catch (get-state $state-key))))
      (if-error $entry
         0.0
         (if (= $entry (pending $stored-key $stored-gen $score))
            (if (and (== $stored-key (forward-fact-key $fact)) (== $stored-gen $gen)) $score 0.0)
            0.0))))

(= (clear-forward-pending-score $fact)
   (change-state!
      (forward-pending-state-key $fact)
      (pending () (forward-current-agenda-gen (forward-fact-kb $fact)) 0.0)))

(= (set-forward-pending-score $fact $score)
   (change-state!
      (forward-pending-state-key $fact)
      (pending (forward-fact-key $fact) (forward-current-agenda-gen (forward-fact-kb $fact)) $score)))

(= (forward-build-agenda $kb)
   (fold-flat
      agenda-push-fact-best
      (empty_heap)
      (collapse
         (match &kb ($type ($kb MAIN Nil) $prf $tv)
            ($type ($kb MAIN Nil) $prf $tv)))))

(= (forward-refresh-agenda $kb)
   (if (forward-agenda-dirty? $kb)
      (let*
         (($_gen (forward-next-agenda-gen $kb))
           ($agenda (forward-build-agenda $kb))
           ($_save (forward-save-agenda $kb $agenda))
           ($_clear-dirty (forward-set-agenda-dirty $kb false)))
         $agenda)
      (forward-load-agenda $kb)))

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

(= (agenda-push-fact $agenda $fact)
   (let $score (term-confidence $fact) (add_to_heap $agenda (- 0 $score) (qitem $score $fact))))

(= (agenda-push-fact-best $agenda $fact)
   (let*
      (($score (term-confidence $fact))
        ($current (forward-pending-score-of $fact)))
      (if (>= $current $score) $agenda
         (let*
            (($nagenda (agenda-push-fact $agenda $fact))
              ($_set (set-forward-pending-score $fact $score)))
            $nagenda))))

(= (forward-seed-agenda-step $agenda $fact)
   (let $rows (collapse (once (forward-output-row-for-fact $fact)))
      (if (== $rows ()) (agenda-push-fact-best $agenda $fact)
         (let ($canonical $_ev) (car-atom $rows)
            (agenda-push-fact-best $agenda $canonical)))))

(= (forward-build-agenda-from-facts $facts)
   (fold-flat forward-seed-agenda-step (empty_heap) $facts))

(= (agenda-push-forward-change $agenda no-forward-change) $agenda)
(= (agenda-push-forward-change $agenda (forward-output-change $old ()))
   (let $_remove (forward-remove-base-rate-observations! $old) $agenda))
(= (agenda-push-forward-change $agenda (forward-output-change $old $fact))
   (let*
      (($_invalidate-old
          (if (== $old ()) () (forward-invalidate-base-rates! $old)))
       ($_invalidate-new (forward-invalidate-base-rates! $fact))
       ($score (term-confidence $fact)))
      (let*
         (($_pending (set-forward-pending-score $fact $score))
          ($nagenda (agenda-push-fact $agenda $fact)))
         $nagenda)))

;; compileadd/removal marks the saved agenda dirty instead of mutating it in
;; place. Apply only the cache bookkeeping here; the next forward run rebuilds
;; and queues the canonical facts under a fresh agenda generation.
(= (forward-apply-unqueued-change! no-forward-change) ())
(= (forward-apply-unqueued-change! (forward-output-change $old ()))
   (forward-remove-base-rate-observations! $old))
(= (forward-apply-unqueued-change! (forward-output-change $old $fact))
   (progn
      (if (== $old ()) () (forward-invalidate-base-rates! $old))
      (forward-invalidate-base-rates! $fact)))

(= (forward-strict-evidence-subset? $subset $superset)
   (and (evidence-subset? $subset $superset)
      (not (evidence-subset? $superset $subset))))

(= (forward-proof-list-refines? $old $new)
   (if (== $old ()) (== $new ())
      (if (== $new ()) false
         (and (forward-proof-refines? (car-atom $old) (car-atom $new))
            (forward-proof-list-refines? (cdr-atom $old) (cdr-atom $new))))))

;; A proof refines another when it has the same rule skeleton and only replaces
;; children by merges containing the earlier child. This distinguishes a
;; genuinely updated application, pToQ(p1) -> pToQ(merge(p1,p2)), from a longer
;; cyclic path such as seed -> keepLoop(seed).
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

(= (forward-candidate-refines? $old-fact $old-ev $new-fact $new-ev)
   (and (forward-strict-evidence-subset? $old-ev $new-ev)
      (forward-proof-refines?
         (proof-atom-proof $old-fact) (proof-atom-proof $new-fact))))

;; A larger evidence set for the same output supersedes the partial estimate
;; even when the new TV has lower confidence.  Disjoint candidates remain in
;; the frontier and are revised together.  Incomparable overlapping candidates
;; retain the existing conservative policy of keeping only the stronger one.
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

(= (forward-frontier-has-exact? ($kb $type) $fact $ev)
   (let $hash (forward-output-index-hash ($kb $type))
      (not (==
         (collapse
            (once
               (match &forward_frontier
                  ($hash $type $kb $fact $ev) true)))
         ()))))

(= (forward-frontier-rejects? ($kb $type) $fact $ev)
   (let $hash (forward-output-index-hash ($kb $type))
      (not (==
         (collapse
            (once
               (match &forward_frontier
                  ($hash $type $kb $old-fact $old-ev)
                  (if (forward-frontier-old-dominates-new?
                         $old-fact $old-ev $fact $ev)
                     true
                     (empty)))))
         ()))))

(= (forward-prune-frontier-for! ($kb $type) $fact $ev)
   (let $hash (forward-output-index-hash ($kb $type))
      (collapse
         (match &forward_frontier
            ($hash $type $kb $old-fact $old-ev)
            (if (forward-frontier-new-dominates-old?
                   $fact $ev $old-fact $old-ev)
               (remove-atom &forward_frontier
                  ($hash $type $kb $old-fact $old-ev))
               ())))))

(= (forward-record-inheritance-nodes! $fact)
   (case $fact (
      (((Inheritance $subj $concept) ($kbid $_ctx $_vars) $_prf $_tv)
         (if (is-var $subj) ()
            (progn
               (add-atom &inheritance_subject ($kbid $subj))
               (record-inheritance-nodes! $kbid $subj $concept))))
      ($_other ()))))

(= (forward-add-frontier-row! ($kb $type) $fact $ev)
   (let*
      (($hash (forward-output-index-hash ($kb $type)))
       ($_nodes (forward-record-inheritance-nodes! $fact))
       ($_frontier
          (chainer-add-atom &forward_frontier
             ($hash $type $kb $fact $ev))))
      ()))

(= (forward-add-first-candidate! $output-key $fact $ev)
   (let $_add (forward-add-frontier-row! $output-key $fact $ev)
      (forward-store-output-candidate!
         $output-key (forward-output-candidate $fact $ev))))

;; Disjoint evidence cannot evict an existing frontier branch.  Merge directly
;; with the cached canonical fact instead of scanning and folding the frontier.
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

(= (forward-candidate-upsert! (forward-derived $fact $ev))
   (let $output-key (forward-fact-key $fact)
      (if (forward-frontier-has-exact? $output-key $fact $ev) no-forward-change
         (let $canonical-rows
            (collapse (once (forward-output-row-for-fact $fact)))
            (if (== $canonical-rows ())
               (forward-add-first-candidate! $output-key $fact $ev)
               (let ($canonical $canonical-ev) (car-atom $canonical-rows)
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

(= (forward-fact-upsert $agenda $derived)
   (agenda-push-forward-change $agenda (forward-candidate-upsert! $derived)))

(= (forward-rule-results-for-key $steps $kb $fact $key)
   (collapse
      (let*
         ((($id $idx) (match prem_index ($key $fact $id $idx) ($id $idx)))
           (($id $ccls $prems) (match rules ($id $ccls $prems) ($id $ccls $prems)))
           ($rprems (nth0 $idx $prems $fact))
           (($trigger-fact $trigger-ev) (forward-output-row-for-fact $fact))
           ((forward-match $result $premise-ev)
              (forward-satisfy-premises $steps $rprems $ccls $trigger-ev)))
         (forward-derived $result
            (rule-result-evidence $result $premise-ev)))))

(= (forward-rule-results $steps $kb $fact)
   (let*
      (($key (forward-premise-index-key $fact))
        ($wildcard-key (forward-premise-wildcard-key $fact))
        ($direct (forward-rule-results-for-key $steps $kb $fact $key))
        ($wildcard
           (if (== $key $wildcard-key) (empty) (forward-rule-results-for-key $steps $kb $fact $wildcard-key))))
      (union-atom $direct $wildcard)))

(= (forward-step-fact $steps $kb $agenda $fact)
   (let*
      (($_clear (clear-forward-pending-score $fact))
        ($_base-rates (forward-update-base-rates $fact))
        ($derived (forward-rule-results $steps $kb $fact))
        ($nagenda (fold-flat forward-fact-upsert $agenda $derived)))
      $nagenda))

(= (forward-loop $steps $kb $agenda)
   (if (or (== (heap_size $agenda) 0) (<= $steps 0)) $agenda
      (let $rest (get_from_heap $agenda $_priority $item)
         (let (qitem $score $fact) $item
            (if (== (forward-pending-score-of $fact) $score)
               (let*
                  (($next-steps (- $steps 1))
                   ($nagenda (bounded-agenda-prune $next-steps (forward-step-fact $steps $kb $rest $fact))))
                  (forward-loop $next-steps $kb $nagenda))
               (forward-loop $steps $kb $rest))))))

(= (forward-target-type $target)
   (if (= $target (: $_name $type $_tv)) $type
      (if (= $target ($fact-type ($_kbid $_ctx $_vars) $_prf $_fact-tv)) $fact-type
         $target)))

(= (forward-select-fact $kb $target)
   (let*
      (($type (forward-target-type $target))
        ($matches
           (collapse
              (once
                 (match &kb ($type ($kb MAIN Nil) $prf $tv)
                    ($type ($kb MAIN Nil) $prf $tv))))))
      (if (== $matches ()) () (car-atom $matches))))

(= (forward-chain-from-facts $steps $kb $facts)
   (let*
      (($old-scope (forward-current-agenda-scope $kb))
        ($scope (forward-new-query-scope $kb))
        ($_scope (forward-set-agenda-scope $kb $scope))
        ($agenda (forward-build-agenda-from-facts $facts))
        ($_run (forward-loop $steps $kb $agenda))
        ($_dirty (forward-set-agenda-dirty $kb true))
        ($_restore (forward-set-agenda-scope $kb $old-scope)))
      true))

(= (forward-chain-from-fact $steps $kb $fact)
   (let*
      (($old-scope (forward-current-agenda-scope $kb))
        ($scope (forward-new-query-scope $kb))
        ($_scope (forward-set-agenda-scope $kb $scope))
        ($agenda (forward-seed-agenda-step (empty_heap) $fact))
        ($_run (forward-loop $steps $kb $agenda))
        ($_dirty (forward-set-agenda-dirty $kb true))
        ($_restore (forward-set-agenda-scope $kb $old-scope)))
      true))

(= (forward-chain $steps $kb)
   (let*
      (($_scope (forward-set-agenda-scope $kb (kb $kb)))
        ($agenda (forward-refresh-agenda $kb))
        ($nagenda (forward-loop $steps $kb $agenda))
        ($_save (forward-save-agenda $kb $nagenda)))
      true))

(= (forward-chain-from $steps $kb $target)
   (let $fact (forward-select-fact $kb $target)
      (if (== $fact ()) false (forward-chain-from-fact $steps $kb $fact))))

(= (forward-has-derived? $kb $type)
   (not (==
      (collapse
         (match &kb ($type ($kb MAIN Nil) $prf $_tv)
            $prf))
      ())))
