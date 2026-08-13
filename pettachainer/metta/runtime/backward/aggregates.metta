;; Backward aggregate restoration, refinement, and snapshot commitment.
;; Ordinary aggregate snapshots use the durable proof index as a base-rate-like
;; cache. A scalar fold has one representative; a grouped fold retains the
;; latest representative for every grounded group/output key. Specialized base
;; rates continue to use &base_rate_cache instead of this generic path.
(: durable-aggregate-current-pids
   (-[semidet]-> Number $arguments (List Number)))
(= (durable-aggregate-current-pids $agg-gid $args)
   (case (base-rate-aggregate-key $args) (
      ((base-rate-aggregate-key-value $_kbid $_pattern $_mode) ())
      (no-base-rate-aggregate-key
         (latest-proof-output-group-ids
            (aggregate-snapshot-groups
               (goal-proof-ids $agg-gid)))))))

(: aggregate-current-pid-shape
   (-[semidet]-> $arguments (List Number) (| Number (List Number))))
(= (aggregate-current-pid-shape $args $pids)
   (case $args (
      (($_kb $_pattern $_group $_extractor $_init $_fun $_finish $_tv-mode)
         $pids)
      ($_other
         (case $pids (
            (() ())
            ((cons $pid $_rest) $pid)))))))

(: durable-aggregate-current-pid
   (-[semidet]-> Number $arguments (| Number (List Number))))
(= (durable-aggregate-current-pid $agg-gid $args)
   (aggregate-current-pid-shape $args
      (durable-aggregate-current-pids $agg-gid $args)))

(: commit-cached-aggregate-heap
   (-[semidet]-> (Heap (| QueueGoal QueueAggregate)) Number $arguments TV (Heap (| QueueGoal QueueAggregate))))
(= (commit-cached-aggregate-heap $agenda $agg-gid $args $tv)
   (let*
      (($result (CPU FoldAllCompiled $args $tv))
       ($pid
          (once
             (store-proof-candidate $agg-gid
                (aggregate-result-candidate $result () ())))))
      (wake-proof-commit-heap $agenda $agg-gid $pid)))

(: ensure-aggregate-child-goal
   (-[nondet]-> Number Goal $arguments Number Number))
(= (ensure-aggregate-child-goal $agg-gid $goal-view $args $score)
   (let*
      (($child-goal (aggregate-child-goal $goal-view))
       ((stored-goal-row
           $_stored-gid $depth $_goal $_expanded $_pending)
          (goal-by-id $agg-gid))
       ($child-gid (ensure-goal-at-depth $child-goal (+ 1 $depth)))
       ($durable-current
          (durable-aggregate-current-pid $agg-gid $args))
       ($hits
          (collapse
             (once
                (match &aggregate
                   (stored-aggregate-row
                      $agg-gid $_child $_args
                      $_base $_pending1 $_current)
                   true))))
       ($_agg
          (if (== $hits ())
             (progn
                (once
                   (chainer-add-atom &aggregate
                      (stored-aggregate-row
                         $agg-gid $child-gid $args $score 0.0
                         $durable-current)))
                ())
             ())))
      $child-gid))

(: spawn-refining-aggregate-heap
   (-[nondet]-> (Heap (| QueueGoal QueueAggregate)) Number Number Goal $arguments TV BaseRateSource (Heap (| QueueGoal QueueAggregate))))
(= (spawn-refining-aggregate-heap $agenda $score $agg-gid $goal-view $args $tv $source)
   (let*
      (($child-gid (ensure-aggregate-child-goal $agg-gid $goal-view $args $score))
       ($pid
          (once
             (store-proof-candidate $agg-gid
                (aggregate-result-candidate
                   (CPU FoldAllCompiled $args $tv) () ()))))
       ($_source
          (if (== $source forward-approx)
             (add-atom &aggregate_forward_approx ($agg-gid))
             ()))
       ($_set
          (progn
             (remove-atom &aggregate
                (stored-aggregate-row
                   $agg-gid $child-gid $args $score 0.0 ()))
             (once
                (chainer-add-atom &aggregate
                   (stored-aggregate-row
                      $agg-gid $child-gid $args $score 0.0 $pid)))))
       ($_wait
          (register-goal-waiter! $child-gid $agg-gid
             (aggregate-waiter $agg-gid
                (cached-aggregate-demand $tv))))
       ($agenda1 (wake-proof-commit-heap $agenda $agg-gid $pid))
       ($nagenda (wake-goal-demand-heap $agenda1 $child-gid)))
      $nagenda))

(: spawn-aggregate-goal-heap
   (-[nondet]-> (Heap (| QueueGoal QueueAggregate)) Number Number Number Goal (Heap (| QueueGoal QueueAggregate))))
(= (spawn-aggregate-goal-heap $agenda $steps $score $agg-gid $goal-view)
   (let*
      (($args (copy_term (let (CPU $_agg-fun $view-args $_goalres) $goal-view $view-args)))
       ($_budget
          (once
             (chainer-add-atom &aggregate_search_budget
                (aggregate-search-budget-row $agg-gid $steps))))
       ($cache-key (base-rate-aggregate-key $args)))
      (case $cache-key (
         ((base-rate-aggregate-key-value $kbid $pattern $mode)
            (spawn-aggregate-goal-cached-or-live-heap
               $agenda $steps $score $agg-gid $goal-view $args
               (base-rate-cache-entries-for-mode
                  $kbid
                  $pattern
                  $mode)))
         (no-base-rate-aggregate-key
            (spawn-aggregate-goal-live-heap
               $agenda $score $agg-gid $goal-view $args))))))

(: spawn-aggregate-goal-cached-or-live-heap
   (-[nondet]-> (Heap (| QueueGoal QueueAggregate))
       Number Number Number Goal $arguments (List BaseRateEntry)
       (Heap (| QueueGoal QueueAggregate))))
(= (spawn-aggregate-goal-cached-or-live-heap
      $agenda $steps $score $agg-gid $goal-view $args $entries)
   (case $entries (
      (() (if (member-inheritance-empty-cache-hit? $steps $args)
             $agenda
             (spawn-aggregate-goal-live-heap
                $agenda $score $agg-gid $goal-view $args)))
      ((cons $entry $_rest)
         (let*
            (($tv (base-rate-entry-tv $entry))
             ($source (base-rate-entry-source $entry)))
            (if (== $source user)
               (commit-cached-aggregate-heap
                  $agenda $agg-gid $args $tv)
               (spawn-refining-aggregate-heap
                  $agenda $score $agg-gid $goal-view
                  $args $tv $source)))))))

(: member-inheritance-empty-cache-hit?
   (-[det]-> Number $arguments Bool))
(= (member-inheritance-empty-cache-hit? $steps $args)
   (case $args (
      (($kbid
          (MemberInheritanceSample $_obj $subj $concept $_atv $_btv)
          $_extractor $_init $_fun (member-inheritance $kbid) $_tv-mode)
         (forward-member-inheritance-empty-cache-hit?
            (brand KB $kbid) (brand Term $subj) (brand Term $concept)
            $steps))
      ($_other false))))

(: AggregateSearchBudgetRow Type)
(: aggregate-search-budget-row
   (-[det]-> Number Number AggregateSearchBudgetRow))

(: spawn-aggregate-goal-live-heap
   (-[nondet]-> (Heap (| QueueGoal QueueAggregate)) Number Number Goal $arguments (Heap (| QueueGoal QueueAggregate))))
(= (spawn-aggregate-goal-live-heap $agenda $score $agg-gid $goal-view $args)
   (let*
      (($child-gid (ensure-aggregate-child-goal $agg-gid $goal-view $args $score))
       ($_wait
          (register-goal-waiter! $child-gid $agg-gid
             (aggregate-waiter
                $agg-gid live-aggregate-demand)))
       ($agenda1 (wake-goal-demand-heap $agenda $child-gid))
       ($nagenda (schedule-aggregate-heap $agenda1 $agg-gid)))
      $nagenda))

(: aggregate-args-grouped? (-[det]-> $arguments Bool))
(= (aggregate-args-grouped? $args)
   (case $args (
      (($_kb $_pattern $_group $_extractor $_init $_fun $_finish $_tv-mode)
         true)
      ($_other false))))

(: aggregate-proof-fold-step
   (-[semidet]-> (KB Statement
          (| ExtractValue ExtractInheritanceTV ExtractTV) $initial
          (-[semidet]-> $accumulator $value $accumulator)
          $finish AggregateTVMode)
       AggregateState Number AggregateState))
(: aggregate-child-tv
   (-[det]-> (| Goal (Statement KBContext Proof TV))
       (| TV NoTV)))
(= (aggregate-child-tv $child)
   (case $child (
      ((CPU $_formula $_arguments $_result) no-tv)
      (($_type $_kb $_proof $tv) $tv))))

(= (aggregate-proof-fold-step $args (aggregate-state $acc $ev $children) $pid)
   (let*
      ((($_agg-kb $_agg-pattern $extractor $_agg-init $fun $_agg-finish $_agg-tv-mode) (copy_term $args))
       ($child-atom (proof-output-atom-by-id $pid))
       (($_pscore $pev) (proof-stats-by-id $pid))
       ($child-tv (aggregate-child-tv $child-atom))
       ($nacc (aggregate-foldall-step-acc $extractor $fun $acc $child-atom $child-tv))
       ($nev
          (list_to_set (append-evidence $ev $pev)))
       ($nchildren
          (append-number $children $pid)))
      (aggregate-state $nacc $nev $nchildren)))

;; Cycle rejection must happen before equivalent outputs are merged.  Otherwise
;; one recursive proof can make a merged representative look cyclic and hide an
;; independent direct proof of the same grounded atom from the aggregate.
(: aggregate-fold-source-ids
   (-[semidet]-> Number Number (List Number)))
(= (aggregate-fold-source-ids $agg-gid $child-gid)
   (proof-output-group-representative-pids $child-gid
      (proof-output-groups
         (noncyclic-proof-source-ids
            $agg-gid (closed-goal) $child-gid))))

(: aggregate-final-state
   (-[semidet]-> Number Number
       (KB Statement
          (| ExtractValue ExtractInheritanceTV ExtractTV) $initial
          (-[semidet]-> $accumulator $value $accumulator)
          $finish AggregateTVMode)
       AggregateState))
(= (aggregate-final-state $agg-gid $child-gid $args)
   (let*
      ((($_kb $_pattern $_extractor $init-acc $_fun $_finish $_tv-mode) (copy_term $args)))
      (proof-fold-flat-semidet (aggregate-proof-fold-step $args)
         (aggregate-state $init-acc () ())
         (aggregate-fold-source-ids $agg-gid $child-gid))))

(: aggregate-group-update
   (-[semidet]-> (| ExtractValue ExtractInheritanceTV ExtractTV)
       (-[semidet]-> $accumulator $value $accumulator)
       $accumulator $group $child-atom (| TV NoTV)
       (List Evidence) Number
       (List AggregateGroupState) (List AggregateGroupState)))
(= (aggregate-group-update $extractor $fun $init $group $child-atom $child-tv $pev $pid ())
   (let*
      (($nacc (aggregate-foldall-step-acc $extractor $fun $init $child-atom $child-tv))
       ($nev (list_to_set $pev)))
      (cons (aggregate-group-state $group $nacc $nev ($pid)) ())))
(= (aggregate-group-update $extractor $fun $init $group $child-atom $child-tv $pev $pid (cons (aggregate-group-state $old-group $acc $ev $children) $rest))
   (if (== $group $old-group)
      (let*
         (($nacc (aggregate-foldall-step-acc $extractor $fun $acc $child-atom $child-tv))
          ($nev
             (list_to_set (append-evidence $ev $pev)))
          ($nchildren
             (append-number $children $pid)))
         (cons (aggregate-group-state $old-group $nacc $nev $nchildren) $rest))
      (cons (aggregate-group-state $old-group $acc $ev $children)
         (aggregate-group-update $extractor $fun $init $group $child-atom $child-tv $pev $pid $rest))))

(: grouped-aggregate-proof-fold-step
   (-[semidet]-> (KB Statement $group-template
          (| ExtractValue ExtractInheritanceTV ExtractTV) $initial
          (-[semidet]-> $accumulator $value $accumulator)
          $finish AggregateTVMode)
       (List AggregateGroupState) Number (List AggregateGroupState)))
(= (grouped-aggregate-proof-fold-step $args $states $pid)
   (let*
      ((($_agg-kb $pattern $group-template $extractor $init $fun $_finish $_tv-mode) (copy_term $args))
       ($child-atom (proof-output-atom-by-id $pid))
       (($_pscore $pev) (proof-stats-by-id $pid))
       ($group (aggregate-step-group-value $pattern $group-template $child-atom))
       ($child-tv (aggregate-child-tv $child-atom)))
      (aggregate-group-update $extractor $fun $init $group $child-atom $child-tv $pev $pid $states)))

(: grouped-aggregate-final-states
   (-[semidet]-> Number Number
       (KB Statement $group-template
          (| ExtractValue ExtractInheritanceTV ExtractTV) $initial
          (-[semidet]-> $accumulator $value $accumulator)
          $finish AggregateTVMode)
       (List AggregateGroupState)))
(= (grouped-aggregate-final-states $agg-gid $child-gid $args)
   (proof-fold-flat-semidet (grouped-aggregate-proof-fold-step $args)
      ()
      (aggregate-fold-source-ids $agg-gid $child-gid)))

(: grouped-aggregate-result
   (-[semidet]-> (KB Statement $group-template
          (| ExtractValue ExtractInheritanceTV ExtractTV) $initial
          (-[semidet]-> $accumulator $value $accumulator)
          AggregateFinish
          AggregateTVMode)
       AggregateGroupState Goal))
(= (grouped-aggregate-result $args (aggregate-group-state $group $acc $_ev $_children))
   (let*
      ((($kb $pattern $_group-template $extractor $init $fun $finish $tv-mode)
          $args)
       ($grouped-args
          (quote
             ($kb $pattern $group $extractor $init $fun $finish $tv-mode)))
       ($result (finish-aggregate $finish $acc)))
      (CPU GroupedFoldAllCompiled $grouped-args $result)))

(: commit-grouped-aggregate-state-heap
   (-[semidet]-> Number
       (KB Statement $group-template
          (| ExtractValue ExtractInheritanceTV ExtractTV) $initial
          (-[semidet]-> $accumulator $value $accumulator)
          AggregateFinish
          AggregateTVMode)
       (Heap (| QueueGoal QueueAggregate)) AggregateGroupState (Heap (| QueueGoal QueueAggregate))))
(: aggregate-candidate-current-in-pids?
   (-[semidet]-> ProofCandidate (List Number) Bool))
(= (aggregate-candidate-current-in-pids?
      $_candidate ())
   false)
(= (aggregate-candidate-current-in-pids?
      (proof-candidate $kind $score $ev $children)
      (cons $pid $rest))
   (let*
      (($output (candidate-kind-term $kind))
       ($stored-output (proof-output-atom-by-id $pid))
       (($stored-score $stored-ev) (proof-stats-by-id $pid)))
      (if (and (=alpha $stored-output $output)
               (and (== $stored-score $score) (== $stored-ev $ev)))
         true
         (aggregate-candidate-current-in-pids?
            (proof-candidate $kind $score $ev $children) $rest))))

(: grouped-aggregate-candidate-current?
   (-[semidet]-> Number ProofCandidate Bool))
(= (grouped-aggregate-candidate-current? $agg-gid $candidate)
   (let
      (stored-aggregate-row
         $_stored-agg-gid $_child-gid $_args
         $_base-score $_pending $current-pids)
      (aggregate-by-id $agg-gid)
      (aggregate-candidate-current-in-pids?
         $candidate (the (List Number) $current-pids))))

(= (commit-grouped-aggregate-state-heap $agg-gid $args $agenda (aggregate-group-state $group $acc $ev $children))
   (let*
      (($result (grouped-aggregate-result $args (aggregate-group-state $group $acc $ev $children)))
       ($candidate (aggregate-result-candidate $result $ev $children))
       ($accepted
          (if (grouped-aggregate-candidate-current? $agg-gid $candidate)
             false
             (classify-goal-proof-candidate $agg-gid $candidate))))
      (commit-grouped-aggregate-candidate-heap $agenda
         $agg-gid
         $accepted
         $candidate)))

(: append-grouped-aggregate-current-pid!
   (-[semidet]-> Number Number (| Bool (List $none))))
(: grouped-current-pids-without-key
   (-[semidet]-> (List Number) ProofOutputKey (List Number)))
(= (grouped-current-pids-without-key () $_key) ())
(= (grouped-current-pids-without-key
      (cons $pid $rest) $key)
   (if (=alpha (aggregate-snapshot-key-by-id $pid) $key)
      (grouped-current-pids-without-key $rest $key)
      (cons $pid
         (grouped-current-pids-without-key $rest $key))))

(: grouped-current-pids-for-key
   (-[semidet]-> (List Number) ProofOutputKey (List Number)))
(= (grouped-current-pids-for-key () $_key) ())
(= (grouped-current-pids-for-key (cons $pid $rest) $key)
   (if (=alpha (aggregate-snapshot-key-by-id $pid) $key)
      (cons $pid (grouped-current-pids-for-key $rest $key))
      (grouped-current-pids-for-key $rest $key)))

(= (append-grouped-aggregate-current-pid! $agg-gid $pid)
   (let*
      (((stored-aggregate-row
            $_stored-agg-gid $child-gid $args
            $base-score $pending $stored-current-pids)
          (aggregate-by-id $agg-gid))
       ($current-pids (the (List Number) $stored-current-pids))
       ($key (aggregate-snapshot-key-by-id $pid))
       ($replaced
          (grouped-current-pids-for-key $current-pids $key))
       ($next-pids
          (cons $pid
             (grouped-current-pids-without-key
                $current-pids $key)))
       ($_set
          (progn
             (remove-atom &aggregate
                (stored-aggregate-row
                   $agg-gid $child-gid $args $base-score
                   $pending $current-pids))
             (once
                (chainer-add-atom &aggregate
                   (stored-aggregate-row
                      $agg-gid $child-gid $args $base-score
                      $pending $next-pids)))))
       ($_deactivate (deactivate-current-proofs! $replaced)))
      true))

(: commit-grouped-aggregate-candidate-heap
   (-[semidet]-> (Heap (| QueueGoal QueueAggregate)) Number Bool ProofCandidate (Heap (| QueueGoal QueueAggregate))))
(= (commit-grouped-aggregate-candidate-heap $agenda $agg-gid $accepted (proof-candidate $kind $score $ev $children))
   (if (== $accepted false) $agenda
      (if (candidate-is-cyclic? $agg-gid $kind $children) $agenda
         (let*
            (($pid
                (once
                   (store-proof-candidate $agg-gid
                      (proof-candidate $kind $score $ev $children))))
             ($_set (append-grouped-aggregate-current-pid! $agg-gid $pid)))
            (wake-proof-commit-heap $agenda $agg-gid $pid)))))

(: run-grouped-aggregate-heap
   (-[semidet]-> (Heap (| QueueGoal QueueAggregate)) Number Number
       (KB Statement $group-template
          (| ExtractValue ExtractInheritanceTV ExtractTV) $initial
          (-[semidet]-> $accumulator $value $accumulator)
          AggregateFinish
          AggregateTVMode)
       (Heap (| QueueGoal QueueAggregate))))
(= (run-grouped-aggregate-heap $agenda $agg-gid $child-gid $args)
   (proof-fold-flat-semidet (commit-grouped-aggregate-state-heap $agg-gid $args)
      $agenda
      (grouped-aggregate-final-states $agg-gid $child-gid $args)))

(: aggregate-commit-evidence
   (-[det]-> $finish (List Evidence) (List Evidence)))
(= (aggregate-commit-evidence $finish $ev)
   (if (background-aggregate-finish? $finish) () $ev))

(: run-aggregate-heap (-[nondet]-> (Heap (| QueueGoal QueueAggregate)) Number (Heap (| QueueGoal QueueAggregate))))
(= (run-aggregate-heap $agenda $agg-gid)
   (let*
      (((stored-aggregate-row
            $_stored-agg-gid $child-gid $args
            $base-score $pending $current-pid)
          (aggregate-by-id $agg-gid))
       ($grouped? (aggregate-args-grouped? $args))
       ($_clear
          (progn
             (remove-atom &aggregate
                (stored-aggregate-row
                   $agg-gid $child-gid $args $base-score
                   $pending $current-pid))
             (once
                (chainer-add-atom &aggregate
                   (stored-aggregate-row
                      $agg-gid $child-gid $args $base-score
                      0.0 $current-pid))))))
      (if $grouped?
         (run-grouped-aggregate-heap
            $agenda $agg-gid $child-gid
            (the
               (KB Statement $group-template
                  (| ExtractValue ExtractInheritanceTV ExtractTV) $initial
                  (-[semidet]-> $accumulator $value $accumulator)
                  AggregateFinish
                  AggregateTVMode)
               (copy_term $args)))
         (let*
            (((aggregate-state $acc $ev $children)
                (aggregate-final-state
                   $agg-gid $child-gid
                   (the
                      (KB Statement
                         (| ExtractValue ExtractInheritanceTV ExtractTV) $initial
                         (-[semidet]-> $accumulator $value $accumulator)
                         AggregateFinish
                         AggregateTVMode)
                      (copy_term $args))))
             (($_kb $_pattern $_extractor $_init $_fun $finish $_tv-mode)
                $args)
             ($result
                (CPU FoldAllCompiled $args
                   (finish-aggregate $finish $acc)))
             ($commit-ev (aggregate-commit-evidence $finish $ev)))
            (if
               (base-rate-refinement-degrades?
                  $agg-gid $finish $current-pid $result)
               $agenda
               (if
                  (aggregate-snapshot-changed?
                     $current-pid $result $commit-ev)
                  (commit-aggregate-snapshot-heap
                     $agenda $agg-gid $result $commit-ev $children)
                  $agenda))))))

; Background aggregates (node priors / base rates) summarise the whole store
; rather than chaining specific evidence, so their committed proof carries no
; evidence dependency -- this keeps them from forming evidence cycles with the
; very premises they are computed alongside.
(: background-aggregate-finish? (-[det]-> $finish Bool))
(= (background-aggregate-finish? $finish)
   (if (base-rate-finish? $finish) true
      (if (== $finish uniform-prior) true (== $finish uniform-prior-known))))

(: base-rate-refinement-degrades?
   (-[semidet]-> Number $finish (| Number (List Number)) $result Bool))
(= (base-rate-refinement-degrades? $agg-gid $finish $current-pid $result)
   (if (not (==
         (collapse (once (match &aggregate_forward_approx ($agg-gid) true)))
         ()))
      false
      (if (base-rate-finish? $finish)
      (if (== $current-pid ()) false
         (let*
            (($new-tv (let (CPU $_fun $_args $ntv) $result $ntv))
             ($current-tv
                (let (CPU $_cfun $_cargs $ctv)
                   (proof-output-atom-by-id (the Number $current-pid))
                   $ctv)))
            (if (= $current-tv (STV $_cs $_cc))
               (if (= $new-tv (STV $_ns $_nc))
                  (< (tv-confidence $new-tv) (tv-confidence $current-tv))
                  true)
               false)))
      false)))

(: direct-goal-results-view
   (-[nondet]-> Number (| Goal (Statement KBContext Proof TV))
       (| Goal (Statement KBContext Proof TV))))
(= (direct-goal-results-view $steps (CPU $fun $args $res))
   (let $computed (reduce (cpu-call $steps $fun $args))
      (if (= $res $computed)
         (CPU $fun $args $computed)
         (empty))))
(= (direct-goal-results-view $steps ($type $kb $prf $tv))
   (match &kb
      (@ $fact ($type $kb $prf $tv))
      (if (backward-acyclic-term? $fact)
         $fact
         (empty))))

(: expand-direct-goal-step
   (-[semidet]-> Number (| Goal (Statement KBContext Proof TV))
       (Heap (| QueueGoal QueueAggregate))
       (| Goal (Statement KBContext Proof TV))
       (Heap (| QueueGoal QueueAggregate))))
(= (expand-direct-goal-step $gid $_goal $agenda $result)
   (let*
      (($ev (leaf-evidence-for-result $result))
       ($candidate (leaf-result-candidate $result $ev))
       ($accepted (classify-goal-proof-candidate $gid $candidate))
       ($nagenda (commit-proof-candidate-heap $agenda $gid $accepted $candidate)))
      $nagenda))

(: expand-direct-goal-heap
   (-[semidet]-> (Heap (| QueueGoal QueueAggregate)) Number Number
       (| Goal (Statement KBContext Proof TV))
       (Heap (| QueueGoal QueueAggregate))))
(= (expand-direct-goal-heap $agenda $steps $gid $goal)
   (let*
      (($results (collapse (direct-goal-results-view $steps $goal)))
       ($agenda1
          (proof-fold-flat-semidet
             (expand-direct-goal-step $gid $goal) $agenda $results)))
      (expand-rule-goal-heap $agenda1 $gid $goal)))

(: inject-compiled-query-adds
   (-[semidet]-> CompiledQuery (List $none)))
(= (inject-compiled-query-adds (compiled-query $_goal $adds))
   (if (is-var $adds)
      (empty)
      (once
         (inject-compiled-adds $adds))))
