;; Main backward search loop, cache harvesting, and public runners.
;; Install only the empirical Member producer for a concrete Inheritance
;; subgoal. The root query's total-implication scaffold is intentionally not
;; copied here: ordinary premise resolution already sees those direct/rule
;; proofs, and adding the scaffold beside them would duplicate evidence.
(: inject-special-subgoal-query-adds
   (-[semidet]-> (| Goal (Statement KBContext Proof TV))
       (List $none)))
(= (inject-special-subgoal-query-adds $goal)
   (case $goal (
      (($type ($kbid MAIN Nil) $prf $tv)
         (if (implication-type? (brand Statement $type))
            (let $compiled-queries
               (collapse
                  (mm2compileQuery
                     (brand KB $kbid)
                     (: $prf $type $tv)))
               (foreach-flat
                  inject-compiled-query-adds
                  $compiled-queries))
            (if (= $type (Inheritance $subj $concept))
               (if (concrete-inheritance-link?
                       (brand Term $subj) (brand Term $concept))
                  (once
                     (inject-compiled-adds
                        (map-flat internalize-runtime-addition
                           (compiled-adds-mm2stmts
                              (compile-member-inheritance-query-adds
                                 (brand KB $kbid)
                                 (brand Term $subj) (brand Term $concept))))))
                  ())
               ())))
      ($_other ()))))

(: expand-goal-heap
   (-[semidet]-> (Heap AgendaEntry) Number Number Number
       (Heap AgendaEntry)))
(= (expand-goal-heap $agenda $steps $score $gid)
   (let*
      (((stored-goal-row
            $_stored-gid $depth $goal $expanded $pending)
          (goal-by-id $gid))
       ($_expand
          (progn
             (remove-atom &goal
                (stored-goal-row
                   $gid $depth $goal $expanded $pending))
             (once
                (chainer-add-atom &goal
                   (stored-goal-row
                      $gid $depth $goal true $pending)))))
       ($_query-adds (if (> $depth 0) (inject-special-subgoal-query-adds $goal) ())))
      (if (case $goal (
             ((CPU $fun $_args $_res) (aggregate-fold-function? $fun))
             ($_other false)))
         (once
            (spawn-aggregate-goal-heap
               $agenda $steps $score $gid (the Goal $goal)))
         (expand-direct-goal-heap $agenda $steps $gid $goal))))

(: search-agenda-step
   (-[nondet]-> Number (Heap AgendaEntry) AgendaEntry SearchState))
(= (search-agenda-step $steps $agenda $entry)
   (case (claim-goal-agenda-entry! $entry) (
      (agenda-stale
         (let $_metric
            (increment-backward-query-metric! stale-agenda-entries)
            (search-agenda-heap $steps $agenda)))
      (agenda-cancelled
         (search-agenda-heap $steps $agenda))
      (agenda-retoken
         (let $next
            (chainer-first-or $agenda
               (collapse
                  (once
                     (retoken-goal-agenda-entry-heap
                        $agenda $entry))))
            (search-agenda-heap $steps $next)))
      (agenda-claimed
         (search-claimed-agenda-entry
            $steps $agenda $entry)))))

(: search-claimed-agenda-entry
   (-[nondet]-> Number (Heap AgendaEntry) AgendaEntry SearchState))

(= (search-claimed-agenda-entry $steps $agenda
      (agenda-entry $kind $gid $_token))
   (if (if (== $kind agenda-expand) true (== $kind agenda-aggregate))
      (let* (($next-steps (- $steps 1))
             ($nagenda
                (once
                   (bounded-backward-agenda-prune $next-steps
                      (if (== $kind agenda-expand)
                         (expand-goal-heap
                            $agenda $steps
                            (root-demands-max (goal-root-demands $gid))
                            $gid)
                         (once (run-aggregate-heap $agenda $gid)))))))
         (search-agenda-heap $next-steps $nagenda))
      (search-agenda-heap $steps $agenda)))

(: search-agenda-heap
   (-[nondet]-> Number (Heap AgendaEntry) SearchState))
(= (search-agenda-heap $steps $agenda)
   (if (<= $steps 0)
      (data $steps $agenda)
      (if (== (heap_size $agenda) 0)
         (data $steps $agenda)
         (let*
            (($_metric (increment-backward-query-metric! agenda-pops))
             (($_priority $item $rest)
                (heap_pop $agenda)))
            (search-agenda-step $steps $rest
               (the AgendaEntry $item))))))

(: merge-computed-member-inheritance-child!
   (-[det]-> Number Number (List $none)))
(= (merge-computed-member-inheritance-child! $id $pid)
   (collapse
      (let*
         (($fact (proof-fact-output-by-id $pid))
          (((MemberInheritanceSample
               $obj $_subj $_concept $atv $btv)
            $_kbctx $_proof $_sample-tv)
             $fact)
          (($_score $evidence) (proof-stats-by-id $pid))
          ((BaseRateEvidence $weight $mass)
             (forward-weighted-base-rate-contribution
                (the TV $atv) (the TV $btv)))
          ($candidate (forward-output-candidate $fact $evidence)))
         (forward-merge-computed-member-observation!
            $id
            (forward-aggregate-observation
               (brand ForwardAggregateObservationKey
                  (quote ($id $obj)))
               (forward-member-inheritance-observation-value
                  $candidate $candidate)
               $weight $mass)))))

(: harvest-base-rate-child!
   (-[det]-> Number ForwardAggregateDescriptor Number (List $none)))
(= (harvest-base-rate-child! $id $desc $pid)
   (collapse
      (let*
         (($fact (proof-fact-output-by-id $pid))
          ((fa-sample $key $value $weight $mass $keep)
             (fa-sample-for $fact $desc))
          ($obs-key
             (brand ForwardAggregateObservationKey
                (quote ($id $key)))))
         (fa-swap!
            $id
            (fa-obs $obs-key)
            (forward-aggregate-observation
               $obs-key $value $weight $mass)
            $keep))))

;; A computed fold retains the accepted child proof IDs that produced its
;; snapshot.  Import those already overlap-resolved components into the same
;; per-object state used by forward chaining, so later selected deltas revise
;; the computed snapshot instead of replacing it with a partial approximation.
(: harvest-computed-aggregate-state!
   (-[det]-> $arguments Number (List $none)))
(= (harvest-computed-aggregate-state! $args $current-pid)
   (case $args (
      (($kbid
          (MemberInheritanceSample $obj $subj $concept $atv $btv)
          (extract-value
             (MemberInheritanceSample $obj $subj $concept $atv $btv)
             (WeightedTv $atv $btv))
          (BaseRateEvidence 0.0 0.0)
          WeightedBaseRateAcc
          (member-inheritance $kbid)
          result-tv)
         (let $_harvest
            (collapse
               (let $id
                  (forward-member-inheritance-id
                     (brand KB $kbid)
                     (brand Term $subj)
                     (brand Term $concept))
                  (foreach-flat
                     (merge-computed-member-inheritance-child! $id)
                     (proof-children-by-id $current-pid))))
            ()))
      (($kbid $pattern $_extractor $_init $_fun $finish $_tv-mode)
         (if (base-rate-finish? $finish)
            (let $_harvest
               (collapse
                  (let (data $id $desc)
                     (fa-ordinary-row
                        (brand KB $kbid) (brand Statement $pattern))
                     (foreach-flat
                        (harvest-base-rate-child!
                           $id
                           (the ForwardAggregateDescriptor $desc))
                        (proof-children-by-id $current-pid))))
               ())
            ()))
      ($_other ()))))

(: harvest-base-rates (-[det]-> (List $none)))
(= (harvest-base-rates)
   (let $_
      (collapse
         (match &aggregate
            (stored-aggregate-row
               $agg-gid $_child $args
               $_base $_pending $current-pid)
            (case (base-rate-aggregate-key $args) (
               (no-base-rate-aggregate-key ())
               ((base-rate-aggregate-key-value $kbid $pattern $mode)
                  (case $current-pid (
                     (() ())
                     ((cons $stored-pid $_rest)
                        (let $pid (stored-number $stored-pid)
                           (if (= (proof-output-atom-by-id $pid)
                                  (CPU $_fun $_out-args (STV $s $c)))
                              (let* (($_components
                                        (harvest-computed-aggregate-state!
                                           $args $pid))
                                     ($_cache
                                        (store-computed-base-rate!
                                           $kbid
                                           $pattern
                                           (STV $s $c)
                                           $mode))
                                     ($_supersede
                                        (if (ba-materialized? $agg-gid) ()
                                           (supersede-current-proof! $pid))))
                                 ())
                              ()))))))))))
      ()))

(: harvest-complete-member-inheritance-empty-caches! (-[det]-> (List $none)))
(= (harvest-complete-member-inheritance-empty-caches!)
   (let $_
      (collapse
         (match &aggregate
            (stored-aggregate-row
               $agg-gid $_child
               ($kbid
                (MemberInheritanceSample
                   $_obj $subj $concept $_atv $_btv)
                $_extractor $_init $_fun
                (member-inheritance $kbid) $_tv-mode)
               $_base 0.0 $current-pid)
            (match &aggregate_search_budget
               (aggregate-search-budget-row $agg-gid $budget)
               (case (collapse
                        (proof-output-atom-by-id
                           (first-number (the (List Number) $current-pid)))) (
                  ((cons (CPU $_fold $_stored-args no-evidence) $_outputs)
                     (let* (($_cache
                               (forward-store-member-inheritance-empty-cache!
                                  (brand KB $kbid)
                                  (brand Term $subj)
                                  (brand Term $concept)
                                  $budget))
                            ($_retire
                               (collapse
                                  (deactivate-current-proofs!
                                     (the (List Number) $current-pid)))))
                        ()))
                  ($_other ()))))))
      ()))

;; Internal queue operations are semidet because an arbitrary numeric ID may
;; be absent.  The public runner creates its root ID immediately above, so turn
;; an impossible missing-root result into an empty, deterministic search
;; rather than letting the whole query vanish.
(: schedule-execution-root-goal-heap
   (-[semidet]-> Bool (Heap AgendaEntry) Number (Heap AgendaEntry)))
(= (schedule-execution-root-goal-heap $reuse? $agenda $gid)
   ;; The reuse flag must gate the lineage probe with a nested if:
   ;; and-evaluation is strict, so an (and $reuse? probe) form would
   ;; pay the per-root probe on every non-materializing query.
   (if $reuse?
      (if (== (current-materialized-root-results $gid) ())
         (schedule-root-goal-heap $agenda $gid)
         $agenda)
      (schedule-root-goal-heap $agenda $gid)))
(: execute-backward
   (-[nondet]-> Number
       (List (| Goal (Statement KBContext Proof TV)))
       Bool (List (List RuntimeResult))))
(= (execute-backward $steps $goals $materialize?)
   (let*
      (;; Goals, waiters, and aggregate execution rows belong to one search.
       ;; Completed proof rows and their dependency indexes are monotonic
       ;; knowledge and intentionally survive this reset.
       ($_clear (clear-backward-query-state!))
       ($_reset
          (foreach-flat
             (|-> ($key) (change-state! $key 0))
             (bwd_gid bwd_frontier_path)))
       ($root-gids
          (map-flat
             (|-> ($goal) (ensure-goal-at-depth $goal 0))
             $goals))
       ($scheduled-root-gids (list_to_set $root-gids))
       ($_root-markers
          (foreach-flat
             (|-> ($gid)
                (once (add-atom &root_goal (root-goal $gid))))
             $scheduled-root-gids))
       ($_root-count
          (change-state! bwd_root_count
             (length $scheduled-root-gids)))
       ($agenda0
          (proof-fold-flat-semidet
             (schedule-execution-root-goal-heap
                (if $materialize?
                   (not (pending-base-rate-retires?))
                   false))
             (empty_heap) $scheduled-root-gids))
       ;; A semidet failure anywhere in the search loop lands in the empty
       ;; case here. That is always an engine defect, never a legitimate
       ;; quiescence, so announce it instead of silently returning whatever
       ;; partial proof store the search had built by then.
       ($search-hits
          (collapse
             (once
                (if (<= $steps 0)
                   (data 0 $agenda0)
                   (search-agenda-heap (+ $steps 1) $agenda0)))))
       ($_abort
          (if (== $search-hits ())
             (let* (($_metric
                       (increment-backward-query-metric!
                          search-aborts))
                    ($_announcement
                       (println!
                          (backward-search-aborted steps $steps))))
                ())
             ()))
       ($results
          (map-flat
             (|-> ($root-gid)
                (chainer-first-or ()
                   (collapse
                      (once
                         (root-goal-results-with-materialization
                            $root-gid $materialize?)))))
             $root-gids))
       ($_harvest (harvest-base-rates))
       ($_empty-member-cache
          (harvest-complete-member-inheritance-empty-caches!)))
      $results))

(: chainer-many
   (-[nondet]-> Number
       (List (| Goal (Statement KBContext Proof TV)))
       (List (List RuntimeResult))))
(= (chainer-many $steps $goals)
   (execute-backward $steps $goals false))

(: chainer
   (-[nondet]-> Number (| Goal (Statement KBContext Proof TV))
       (List RuntimeResult)))
(= (chainer $steps $goal)
   (chainer-first-or ()
      (execute-backward $steps ($goal) false)))

(: chainer-materialize
   (-[nondet]-> Number (| Goal (Statement KBContext Proof TV))
       (List RuntimeResult)))
(= (chainer-materialize $steps $goal)
   (chainer-first-or ()
      (execute-backward $steps ($goal) true)))

(: chainer-many-materialize
   (-[nondet]-> Number
       (List (| Goal (Statement KBContext Proof TV)))
       (List (List RuntimeResult))))
(= (chainer-many-materialize $steps $goals)
   (execute-backward $steps $goals true))
