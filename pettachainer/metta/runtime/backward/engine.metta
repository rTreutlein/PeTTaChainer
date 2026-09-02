;; Main backward search loop, cache harvesting, and public runners.
;; Install only the empirical Member producer for a concrete Inheritance
;; subgoal. The root query's total-implication scaffold is intentionally not
;; copied here: ordinary premise resolution already sees those direct/rule
;; proofs, and adding the scaffold beside them would duplicate evidence.
(: inject-member-inheritance-subgoal-adds
   (-[semidet]-> KB Term Term (List $none)))
(= (inject-member-inheritance-subgoal-adds $kb $subj $concept)
   (let*
      (($compiled-adds
          (compile-member-inheritance-query-adds $kb $subj $concept))
       ($runtime-adds
          (map-flat internalize-runtime-addition
             (compiled-adds-mm2stmts $compiled-adds))))
      (once (inject-compiled-adds $runtime-adds))))

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
                  (inject-member-inheritance-subgoal-adds
                     (brand KB $kbid)
                     (brand Term $subj) (brand Term $concept))
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
       ($_query-adds (if (> $depth 0) (inject-special-subgoal-query-adds $goal) ()))
       ($nagenda0
          (if (= $goal (CPU $fun $_args $_res))
             (if (aggregate-fold-function? $fun)
                (once
                   (spawn-aggregate-goal-heap
                      $agenda $steps $score $gid (the Goal $goal)))
                (expand-direct-goal-heap
                   $agenda $steps $gid $goal))
             (expand-direct-goal-heap $agenda $steps $gid $goal)))
       ($nagenda (if (== $nagenda0 ()) (empty_heap) $nagenda0)))
      $nagenda))

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
   (case $kind (
      (agenda-expand
         (let* (($fresh-max
                   (root-demands-max
                      (goal-root-demands $gid)))
                ($next-steps (- $steps 1))
                ($nagenda
                   (once
                      (bounded-backward-agenda-prune $next-steps
                         (expand-goal-heap
                            $agenda $steps $fresh-max $gid)))))
            (search-agenda-heap $next-steps $nagenda)))
      (agenda-aggregate
         (let* (($next-steps (- $steps 1))
                ($nagenda
                   (once
                      (bounded-backward-agenda-prune $next-steps
                         (once (run-aggregate-heap $agenda $gid))))))
            (search-agenda-heap $next-steps $nagenda)))
      (agenda-refresh
         (search-agenda-heap $steps $agenda))
      (agenda-resume
         (search-agenda-heap $steps $agenda)))))

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

(: computed-member-inheritance-observation
   (-[semidet]-> Number Number ForwardAggregateObservation))
(= (computed-member-inheritance-observation $id $pid)
   (computed-member-inheritance-observation-for-fact
      $id $pid (proof-fact-output-by-id $pid)))

(: computed-member-inheritance-observation-for-fact
   (-[semidet]-> Number Number (Statement KBContext Proof TV)
       ForwardAggregateObservation))
(= (computed-member-inheritance-observation-for-fact
      $id $pid
      ((MemberInheritanceSample
          $obj $_subj $_concept $atv $btv)
       $_kbctx $_proof $_sample-tv))
   (let*
      ((($_score $evidence) (proof-stats-by-id $pid))
       ($antecedent-tv (the TV $atv))
       ($consequent-tv (the TV $btv))
       ((BaseRateEvidence $weight $mass)
          (forward-weighted-base-rate-contribution
             $antecedent-tv $consequent-tv))
       ($sample (proof-fact-output-by-id $pid))
       ($candidate (forward-output-candidate $sample $evidence)))
      (forward-aggregate-observation
         (brand ForwardAggregateObservationKey
            (quote ($id $obj)))
         (forward-member-inheritance-observation-value
            $candidate $candidate)
         $weight $mass)))

(: merge-computed-member-inheritance-child!
   (-[det]-> Number Number (List $none)))
(= (merge-computed-member-inheritance-child! $id $pid)
   (collapse
      (forward-merge-computed-member-observation!
         $id (computed-member-inheritance-observation $id $pid))))

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

(: harvest-base-rate-entry
   (-[semidet]-> Number $arguments (List Number) (List $none)))
(= (harvest-base-rate-entry $agg-gid $args $current-pid)
   (let $key (base-rate-aggregate-key $args)
      (case $key (
         (no-base-rate-aggregate-key ())
         ((base-rate-aggregate-key-value $kbid $pattern $mode)
            (if (== $current-pid ()) ()
               (let*
                  (((cons $pid $_rest) $current-pid)
                   ($output (proof-output-atom-by-id $pid)))
                  (if (= $output (CPU $_fun $_out-args (STV $s $c)))
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
                     ()))))))))

(: harvest-base-rates (-[det]-> (List $none)))
(= (harvest-base-rates)
   (let $_
      (collapse
         (match &aggregate
            (stored-aggregate-row
               $agg-gid $_child $args
               $_base $_pending $current-pid)
            (harvest-base-rate-entry
               $agg-gid $args $current-pid)))
      ()))

(: aggregate-no-evidence-pid?
   (-[det]-> (List Number) Bool))
(= (aggregate-no-evidence-pid? $current-pid)
   (case $current-pid (
      (() false)
      ((cons $pid $_rest)
         (case (collapse
                  (proof-output-atom-by-id $pid)) (
            ((cons (CPU $_fold $_stored-args no-evidence) $_rest)
               true)
            ($_other false)))))))

(: harvest-complete-member-inheritance-empty-cache!
   (-[det]-> Number $arguments (List Number) (List $none)))
(= (harvest-complete-member-inheritance-empty-cache!
      $budget $args $current-pid)
   (case $args (
      (($kbid
          (MemberInheritanceSample
             $_obj $subj $concept $_atv $_btv)
          $_extractor $_init $_fun
          (member-inheritance $kbid) $_tv-mode)
         (if (aggregate-no-evidence-pid? $current-pid)
            (let* (($_cache
                      (forward-store-member-inheritance-empty-cache!
                         (brand KB $kbid)
                         (brand Term $subj)
                         (brand Term $concept)
                         $budget))
                   ($_retire
                      (collapse
                         (deactivate-current-proofs! $current-pid))))
               ())
            ()))
      ($_other ()))))

(: harvest-complete-member-inheritance-empty-caches! (-[det]-> (List $none)))
(= (harvest-complete-member-inheritance-empty-caches!)
   (let $_
      (collapse
         (match &aggregate
            (stored-aggregate-row
               $agg-gid $_child $args $_base 0.0 $current-pid)
            (match &aggregate_search_budget
               (aggregate-search-budget-row $agg-gid $budget)
               (harvest-complete-member-inheritance-empty-cache!
                  $budget $args $current-pid))))
      ()))

;; Internal queue operations are semidet because an arbitrary numeric ID may
;; be absent.  The public runner creates its root ID immediately above, so turn
;; an impossible missing-root result into an empty, deterministic search
;; rather than letting the whole query vanish.
(: schedule-execution-root-goals-heap
   (-[semidet]-> (Heap AgendaEntry) (List Number) Bool
       (Heap AgendaEntry)))
(= (schedule-execution-root-goals-heap $agenda () $_reuse?) $agenda)
(= (schedule-execution-root-goals-heap $agenda (cons $gid $rest) $reuse?)
   (let $next
      ;; The reuse flag must gate the lineage probe with a nested if:
      ;; and-evaluation is strict, so an (and $reuse? probe) form would
      ;; pay the per-root probe on every non-materializing query.
      (if $reuse?
         (if (== (current-materialized-root-results $gid) ())
            (schedule-root-goals-heap $agenda (cons $gid ()))
            $agenda)
         (schedule-root-goals-heap $agenda (cons $gid ())))
      (schedule-execution-root-goals-heap $next $rest $reuse?)))
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
       ($_root-markers (mark-root-goals $scheduled-root-gids))
       ($_root-count
          (change-state! bwd_root_count
             (length $scheduled-root-gids)))
       ($agenda0
          (schedule-execution-root-goals-heap
             (empty_heap) $scheduled-root-gids
             (if $materialize?
                (not (pending-base-rate-retires?))
                false)))
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
       ($search-result
          (case $search-hits (
             (() (let* (($_metric
                           (increment-backward-query-metric!
                              search-aborts))
                        ($_announcement
                           (println!
                              (backward-search-aborted steps $steps))))
                    (data 0 $agenda0)))
             ((cons $found $_rest) $found))))
       (($_steps-left $_agenda1)
          $search-result)
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
