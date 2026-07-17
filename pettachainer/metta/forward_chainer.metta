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

(= (forward-fact-evidence $fact)
   (let $key (forward-fact-key $fact)
      (let $hits
         (collapse
            (once
               (match &forward_fact_evidence ($key $fact $ev) $ev)))
         (if (== $hits ())
            (let ($type $kb $prf $_tv) $fact ((fact-ev $kb $prf $type)))
            (car-atom $hits)))))

(= (forward-output-candidate-step () $fact)
   (forward-output-candidate $fact (forward-fact-evidence $fact)))
(= (forward-output-candidate-step (forward-output-candidate $current $current-ev) $fact)
   (let ($merged $merged-ev)
      (merge-proof-candidates
         ($current $current-ev)
         ($fact (forward-fact-evidence $fact)))
      (forward-output-candidate $merged $merged-ev)))

(= (forward-output-candidate-for-key (($kbid $ctx $vars) $type))
   (fold-flat forward-output-candidate-step ()
      (collapse
         (match &kb ($type ($kbid $ctx $vars) $prf $tv)
            ($type ($kbid $ctx $vars) $prf $tv)))))

(= (forward-remove-output-row! $row) (remove-atom &forward_output $row))

;; &kb retains individual asserted/materialized derivations for the backward
;; proof store.  Forward rules consume this canonical merged-output view so a
;; revised derivation replaces its old value instead of becoming new evidence.
(= (forward-refresh-output-key! $key)
   (let*
      (($old-rows
          (collapse
             (match &forward_output ($key $old-fact $old-ev)
                ($key $old-fact $old-ev))))
       ($old (if (== $old-rows ()) () (car-atom $old-rows)))
       ($new-candidate (forward-output-candidate-for-key $key)))
      (if (= $new-candidate (forward-output-candidate $new-fact $new-ev))
         (if (= $old ($key $old-fact $old-ev))
            (if (and (== $old-fact $new-fact) (== $old-ev $new-ev))
               no-forward-change
               (let*
                  (($_remove (foreach-flat forward-remove-output-row! $old-rows))
                   ($_add (add-atom &forward_output ($key $new-fact $new-ev))))
                  (forward-output-change $old-fact $new-fact)))
            (let $_add (add-atom &forward_output ($key $new-fact $new-ev))
               (forward-output-change () $new-fact)))
         (if (== $old-rows ()) no-forward-change
            (let $_remove (foreach-flat forward-remove-output-row! $old-rows)
               (forward-output-change (let ($_key $old-fact $_old-ev) $old $old-fact) ()))))))

(= (forward-refresh-output! $fact)
   (forward-refresh-output-key! (forward-fact-key $fact)))

(= (forward-output-row-for-fact $fact)
   (let $key (forward-fact-key $fact)
      (match &forward_output ($key $canonical $ev)
         ($canonical $ev))))

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
         (match &forward_output ((($kb MAIN Nil) $_type) ($type ($kb MAIN Nil) $prf $tv) $_ev)
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
         (match &forward_output ($_key $prem $prem-ev)
            (forward-satisfy-premises $steps $rest $goal
               (list_to_set (append $ev $prem-ev))))
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

(= (forward-remove-derived-row! ($derivation-key $output-key $fact $ev))
   (let*
      (($_row (remove-atom &forward_derivation ($derivation-key $output-key $fact $ev)))
       ($_evidence (remove-atom &forward_fact_evidence ($output-key $fact $ev)))
       ($_fact (remove-atom &kb $fact)))
      ()))

(= (forward-record-inheritance-nodes! $fact)
   (case $fact (
      (((Inheritance $subj $concept) ($kbid $_ctx $_vars) $_prf $_tv)
         (if (is-var $subj) ()
            (progn
               (add-atom &inheritance_subject ($kbid $subj))
               (record-inheritance-nodes! $kbid $subj $concept))))
      ($_other ()))))

(= (forward-refresh-key-step $agenda $key)
   (agenda-push-forward-change $agenda (forward-refresh-output-key! $key)))

(= (forward-fact-upsert $agenda (forward-derived $derivation-key $fact $ev))
   (let*
      (($output-key (forward-fact-key $fact))
       ($old-rows
          (collapse
             (match &forward_derivation ($derivation-key $old-key $old-fact $old-ev)
                ($derivation-key $old-key $old-fact $old-ev)))))
      (if (= $old-rows (($derivation-key $output-key $fact $ev))) $agenda
         (let*
            (($old-keys
                (map-flat (|-> (($_derivation-key $old-key $_old-fact $_old-ev)) $old-key)
                   $old-rows))
             ($_remove (foreach-flat forward-remove-derived-row! $old-rows))
             ($_nodes (forward-record-inheritance-nodes! $fact))
             ($_fact (chainer-add-atom &kb $fact))
             ($_row
                (add-atom &forward_derivation
                   ($derivation-key $output-key $fact $ev)))
             ($_evidence
                (add-atom &forward_fact_evidence ($output-key $fact $ev)))
             ($refresh-keys (list_to_set (cons $output-key $old-keys))))
            (fold-flat forward-refresh-key-step $agenda $refresh-keys)))))

(= (forward-premise-derivation-key-step $keys $premise)
   (case $premise (
      ((CPU $_fun $_args $_res) $keys)
      ($_fact (append $keys ((forward-fact-key $premise)))))))

(= (forward-rule-results-for-key $steps $kb $fact $key)
   (collapse
      (let*
         ((($id $idx) (match prem_index ($key $fact $id $idx) ($id $idx)))
           (($id $ccls $prems) (match rules ($id $ccls $prems) ($id $ccls $prems)))
           ($rprems (nth0 $idx $prems $fact))
           (($trigger-fact $trigger-ev) (forward-output-row-for-fact $fact))
           ((forward-match $result $premise-ev)
              (forward-satisfy-premises $steps $rprems $ccls $trigger-ev))
           ($derivation-key
              (forward-rule $id
                 (fold-flat forward-premise-derivation-key-step () $prems))))
         (forward-derived $derivation-key $result
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
                 (match &forward_output ((($kb MAIN Nil) $type) ($type ($kb MAIN Nil) $prf $tv) $_ev)
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
         (match &forward_output ((($kb MAIN Nil) $type) ($_type ($kb MAIN Nil) $prf $_tv) $_ev)
            $prf))
      ())))
