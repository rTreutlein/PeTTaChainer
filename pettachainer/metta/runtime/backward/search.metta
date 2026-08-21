;; Backward scheduler spine: the agenda heap loop that decides what runs next.
;;
;; This layer constructs and evolves the (Heap AgendaEntry): enqueueing
;; goals, aggregates, and frontier waiters; waking demand-dirty subtrees;
;; committing proof candidates and aggregate snapshots; spawning child
;; frontiers; and pruning the agenda under a size bound. Every function
;; threads the heap through and returns the next heap. Policy questions are
;; delegated: entry validity to agenda.metta, priority values to
;; demand.metta, TV and admissibility to frontier_parts.metta, proof facts
;; to the proof store.
;;
;; It is one file because these functions form one mutually recursive
;; component — advancing a waiter can spawn a goal whose registration wakes
;; other goals back into the same heap — and the checker permits mutual
;; recursion only within a file. The heap has one payload shape and one
;; revision protocol: an entry records the demand revision and score at
;; issue time and is revalidated at pop, never edited in the queue.
;;
;; This file also owns the query arena registry:
;; clear-backward-query-state! lists every per-query space; the durable
;; proof-store spaces are cleared separately.
(: SearchState
   (Alias (Number (Heap AgendaEntry))))

;; Keep the query arena in one registry.  Tests that need a completely empty
;; proof store clear the durable spaces separately after calling this helper.
(: clear-backward-query-state! (-[det]-> (List $none)))
(= (clear-backward-query-state!)
   (foreach-flat remove-all-atoms
      (&goal &goal_lookup &goal_waiter &goal_waiter_delivery
       &goal_child &goal_current_confidence
       &goal_demand_cache &goal_demand_revision
       &goal_demand_wake_visited &root_goal
       &goal_demand_wake
       &aggregate &aggregate_search_budget &aggregate_forward_approx
       &proof_invalidated &proof_live_cache
       &frontier_path_lookup &frontier_path &frontier_path_child
       &proof_frontier_path &frontier_path_dead)))

(: ensure-goal-at-depth
   (-[semidet]-> (| Goal
          (Statement KBContext Proof TV))
       Number Number))
(= (ensure-goal-at-depth $goal $depth)
   (let*
      (($stored-goal (copy_term $goal))
       ($goal-key (goal-key $stored-goal))
       ($lookup-key (copy_term $goal-key))
       ($hits
          (collapse
             (once
                (match &goal_lookup ($lookup-key $stored-key $gid)
                   (if (=alpha $stored-key $goal-key)
                      (stored-number $gid)
                      (empty)))))))
      (if (== $hits ())
         (let*
            (($gid (next-gid))
             ($index-key (copy_term $goal-key))
             ($_1
                (once
                   (chainer-add-atom &goal
                      (stored-goal-row
                         $gid $depth $stored-goal false
                         (goal-agenda-state
                            0 0 0.0 ())))))
             ($_2
                (once
                   (chainer-add-atom &goal_lookup
                      ($index-key $goal-key $gid)))))
            $gid)
         (first-number $hits))))

(: schedule-goal-heap
   (-[semidet]-> (Heap AgendaEntry) Number (Heap AgendaEntry)))
(= (schedule-goal-heap $agenda $gid)
   (let* (((stored-goal-row
               $_stored-gid $_depth $_goal $expanded $_agenda-state)
             (goal-by-id $gid))
          ($score (goal-demand-sum $gid)))
      (if $expanded $agenda
         (if (<= $score 0.0) $agenda
            (request-goal-agenda-kind-heap
               $agenda $gid agenda-expand)))))

(: mark-root-goals (-[semidet]-> (List Number) (List $none)))
(= (mark-root-goals ()) ())
(= (mark-root-goals (cons $gid $rest))
   (let $_mark
      (once (chainer-add-atom &root_goal (root-goal $gid)))
      (mark-root-goals $rest)))

;; A foreign heap loses its nominal payload type through fold-flat. Keep the
;; typed schedule boundary explicit while constructing the one shared root
;; agenda.
(: schedule-root-goals-heap
   (-[det]-> (Heap AgendaEntry) (List Number) (Heap AgendaEntry)))
(= (schedule-root-goals-heap $agenda ()) $agenda)
(= (schedule-root-goals-heap $agenda (cons $gid $rest))
   (let $next
      (chainer-first-or $agenda
         (collapse
            (once (schedule-goal-heap $agenda $gid))))
      (schedule-root-goals-heap $next $rest)))

(: enqueue-goal-agenda-kind-heap
   (-[semidet]-> (Heap AgendaEntry) Number Number
       (| Goal (Statement KBContext Proof TV))
       GoalAgendaState AgendaKind (Heap AgendaEntry)))
(= (enqueue-goal-agenda-kind-heap
      $agenda $gid $depth $goal
      (goal-agenda-state
         $generation $issued-revision $_issued-score
         $_requested-lanes)
      $kind)
   (let* (($score (agenda-kind-score $kind $gid))
          ($effective-depth
             (if (== $kind agenda-aggregate) (+ $depth 1) $depth))
          ($bonus
             (if (== $kind agenda-aggregate)
                0.0
                (goal-agenda-bonus $goal)))
          ($priority
             (backward-agenda-priority
                $effective-depth $score $bonus $kind))
          ($token
             (agenda-revision-token
                $issued-revision $generation))
          ($_metric
             (increment-backward-query-metric! agenda-pushes)))
      (add_to_heap $agenda $priority
         (agenda-entry $kind $gid $token))))

(: enqueue-requested-goal-agenda-heap
   (-[semidet]-> (Heap AgendaEntry) Number Number
       (| Goal (Statement KBContext Proof TV)) GoalAgendaState
       (Heap AgendaEntry)))
(= (enqueue-requested-goal-agenda-heap
      $agenda $gid $depth $goal $state)
   (enqueue-requested-goal-agenda-kinds-heap
      $agenda $gid $depth $goal $state
      (agenda-resume agenda-expand agenda-refresh agenda-aggregate)))

(: enqueue-requested-goal-agenda-kinds-heap
   (-[semidet]-> (Heap AgendaEntry) Number Number
       (| Goal (Statement KBContext Proof TV)) GoalAgendaState
       (List AgendaKind) (Heap AgendaEntry)))
(= (enqueue-requested-goal-agenda-kinds-heap
      $agenda $_gid $_depth $_goal $_state ())
   $agenda)
(= (enqueue-requested-goal-agenda-kinds-heap
      $agenda $gid $depth $goal $state (cons $kind $rest))
   (let $next-agenda
      (if (goal-agenda-kind-requested-in-state? $kind $state)
         (enqueue-goal-agenda-kind-heap
            $agenda $gid $depth $goal $state $kind)
         $agenda)
      (enqueue-requested-goal-agenda-kinds-heap
         $next-agenda $gid $depth $goal $state $rest)))

(: request-goal-agenda-kind-heap
   (-[semidet]-> (Heap AgendaEntry) Number AgendaKind
       (Heap AgendaEntry)))
(= (request-goal-agenda-kind-heap $agenda $gid $kind)
   (let* (($current-score (agenda-kind-score $kind $gid))
          ($current-revision (goal-demand-revision $gid))
          ($row (goal-by-id $gid))
          ((stored-goal-row
               $_stored-gid $depth $goal $_expanded $state)
             $row)
          ((goal-agenda-state
               $_generation $issued-revision $issued-score
               $_requested-lanes)
             $state)
          ($coalesced
             (if
                (goal-agenda-kind-requested-in-state? $kind $state)
                (if (== $issued-revision $current-revision)
                   true
                   (<= $current-score $issued-score))
                false)))
      (if $coalesced $agenda
         (let* (($next-state
                   (goal-agenda-state-request
                      $kind $current-revision $current-score $state))
                ($_set (set-goal-agenda-state! $row $next-state)))
            (enqueue-requested-goal-agenda-heap
               $agenda $gid $depth $goal $next-state)))))

(: schedule-aggregate-heap
   (-[semidet]-> (Heap AgendaEntry) Number (Heap AgendaEntry)))
(= (schedule-aggregate-heap $agenda $agg-gid)
   (let*
      (($row (aggregate-by-id $agg-gid))
       ((stored-aggregate-row
            $_stored-agg-gid $_child-gid $_args
            $base-score $_current $_current-pid)
          $row)
       ($requested
          (goal-agenda-kind-requested?
             $agg-gid agenda-aggregate))
       ($_set
          (if $requested ()
             (set-aggregate-pending! $row $base-score))))
      (request-goal-agenda-kind-heap
         $agenda $agg-gid agenda-aggregate)))

(: retoken-goal-agenda-entry-heap
   (-[semidet]-> (Heap AgendaEntry) AgendaEntry (Heap AgendaEntry)))
(= (retoken-goal-agenda-entry-heap $agenda
      (agenda-entry $kind $gid
         (agenda-revision-token $_demand-revision $generation)))
   (let* (($_score (agenda-kind-score $kind $gid))
          ($current-revision (goal-demand-revision $gid))
          ($row (goal-by-id $gid))
          ((stored-goal-row
               $_stored-gid $depth $goal $_expanded $state)
             $row)
          ((goal-agenda-state
               $generation $_issued-revision $_issued-score
               $requested-lanes)
             $state)
          ($next-state
             (goal-agenda-state
                $generation $current-revision $_score
                $requested-lanes))
          ($_set (set-goal-agenda-state! $row $next-state)))
      (enqueue-goal-agenda-kind-heap
         $agenda $gid $depth $goal $next-state $kind)))

(: BackwardAgendaPartition Type)
(: backward-agenda-partition
   (-[det]-> (Heap AgendaEntry) (Heap AgendaEntry)
       BackwardAgendaPartition))

(: partition-backward-agenda
   (-[det]-> (Heap AgendaEntry) (Heap AgendaEntry)
       (Heap AgendaEntry) BackwardAgendaPartition))
(= (partition-backward-agenda $src $controls $expands)
   (case (collapse (heap_pop $src)) (
      (() (backward-agenda-partition $controls $expands))
      ((cons $pop $_rest)
         (partition-backward-agenda-pop $controls $expands $pop)))))

(: partition-backward-agenda-pop
   (-[det]-> (Heap AgendaEntry) (Heap AgendaEntry)
       (Number AgendaEntry (Heap AgendaEntry))
       BackwardAgendaPartition))
(= (partition-backward-agenda-pop
      $controls $expands
      ($priority (agenda-entry $kind $gid $token) $rest))
   (let $entry (agenda-entry $kind $gid $token)
      (if (agenda-entry-owned? $entry)
         (if (== $kind agenda-expand)
            (partition-backward-agenda $rest $controls
               (add_to_heap $expands $priority $entry))
            (partition-backward-agenda $rest
               (add_to_heap $controls $priority $entry) $expands))
         (partition-backward-agenda $rest $controls
            $expands))))

(: release-pruned-agenda-heap!
   (-[det]-> (Heap AgendaEntry) (List $none)))
(= (release-pruned-agenda-heap! $agenda)
   (case (collapse (heap_pop $agenda)) (
      (() ())
      ((cons $pop $_tail)
         (release-pruned-agenda-heap-pop! $pop)))))

(: release-pruned-agenda-heap-pop!
   (-[det]-> (Number AgendaEntry (Heap AgendaEntry)) (List $none)))
(= (release-pruned-agenda-heap-pop! ($_priority $entry $rest))
   (let $_release (release-pruned-agenda-entry! $entry)
      (release-pruned-agenda-heap! $rest)))

(: backward-agenda-prune-to-size
   (-[det]-> Number (Heap AgendaEntry) (Heap AgendaEntry)))
(= (backward-agenda-prune-to-size $target $agenda)
   (let*
       (((backward-agenda-partition $controls $expands)
          (partition-backward-agenda
             $agenda (empty_heap) (empty_heap)))
       ($control-size-values (collapse (heap_size $controls)))
       ($control-count
          (if (== $control-size-values ())
             0
             (car-atom $control-size-values)))
       ($expand-slots (max 0 (- $target $control-count)))
       ((heap-split $kept-expands $dropped-expands)
          (heap-split-best
             $expand-slots $expands (empty_heap)))
       ($_release
          (release-pruned-agenda-heap! $dropped-expands)))
      (heap-merge-into $controls $kept-expands)))

(: bounded-backward-agenda-prune
   (-[det]-> Number (Heap AgendaEntry) (Heap AgendaEntry)))
(= (bounded-backward-agenda-prune $steps $agenda)
   (if (bounded-agenda-prune-needed? $steps $agenda)
      (backward-agenda-prune-to-size
         (bounded-agenda-target-size $steps) $agenda)
      $agenda))

(: wake-goal-demand-children-heap
   (-[semidet]-> (Heap AgendaEntry) (List Number)
       (Heap AgendaEntry)))
(= (wake-goal-demand-children-heap $agenda ()) $agenda)
(= (wake-goal-demand-children-heap
      $agenda (cons $child-gid $rest))
   (let $next
      (chainer-first-or $agenda
         (collapse
            (once
               (wake-goal-demand-walk-heap
                  $agenda $child-gid))))
      (wake-goal-demand-children-heap $next $rest)))

;; Visited marks live in a space scoped to the whole wake so each goal is
;; visited once per wake. A path-local visited list re-walks shared
;; descendants once per distinct path, which is exponential in DAG depth.
(: wake-goal-demand-walk-heap
   (-[semidet]-> (Heap AgendaEntry) Number
       (Heap AgendaEntry)))
(= (wake-goal-demand-walk-heap $agenda $gid)
   (let $seen
      (collapse
         (once (match &goal_demand_wake_visited ($gid) true)))
      (if (not (== $seen ())) $agenda
         (let* (($_mark
                   (once
                      (add-atom &goal_demand_wake_visited ($gid))))
                ((stored-goal-row
                     $_stored-gid $_depth $_goal $expanded $_pending)
                   (goal-by-id $gid)))
            (if $expanded
               (wake-goal-demand-children-heap
                  $agenda (goal-demand-child-gids $gid))
               (schedule-goal-heap $agenda $gid))))))

;; Most waiter registrations wake only their direct goal.  A goal that has just
;; acquired its first live root demand also wakes the already-expanded frontier
;; beneath it, preserving the cycle-recovery behavior without repeatedly
;; traversing the same DAG.
(: wake-goal-demand-heap
   (-[semidet]-> (Heap AgendaEntry) Number (Heap AgendaEntry)))
(= (wake-goal-demand-heap $agenda $gid)
   (let $hits
      (collapse
         (once
            (match &goal_demand_wake ($gid) true)))
      (if (== $hits ())
         (schedule-goal-heap $agenda $gid)
         (let* (($_clear
                   (collapse
                      (match &goal_demand_wake ($gid)
                         (remove-atom &goal_demand_wake ($gid)))))
                ($_fresh
                   (collapse
                      (match &goal_demand_wake_visited ($vgid)
                         (remove-atom
                            &goal_demand_wake_visited ($vgid))))))
            (wake-goal-demand-walk-heap $agenda $gid)))))
(: AggregateState Type)
(: aggregate-state
   (-[det]-> $accumulator (List Evidence) (List Number) AggregateState))
(: AggregateGroupState Type)
(: aggregate-group-state
   (-[det]-> $group $accumulator (List Evidence) (List Number) AggregateGroupState))

(: advance-frontier-waiter-heap
   (-[semidet]-> (Heap AgendaEntry) FrontierWaiter Number
       (Heap AgendaEntry)))
(= (advance-frontier-waiter-heap $agenda
      (frontier-waiter $parent-gid $bundle $score
         $seen $parts $path-id $value-spec)
      $pid)
   (if (waiter-live? (frontier-waiter $parent-gid $bundle $score
         $seen $parts $path-id $value-spec))
      (let*
         ((($proof-output $_kind $support $_children)
             (proof-row-by-id $pid))
          ((proof-support $pscore $pev $_contribution) $support)
          ($frontier-pscore (frontier-proof-score $proof-output $pscore))
          ($part (frontier-premise-part $support))
          ($overlap
             (if (frontier-allows-shared-evidence? $bundle)
                false
                (premise-evidence-overlap? $seen $pev))))
         (if (frontier-pool-join? $part $parts $seen $pev)
            (frontier-advance-pooled-heap $agenda $parent-gid $bundle
               $score $seen $parts $path-id $value-spec
               $pid $pev $part)
            (if $overlap $agenda
               (let $next-bundle (advance-frontier-bundle (copy_term $bundle) $pid)
                  (if (== $next-bundle ()) $agenda
                     (let*
                        (($typed-next-bundle
                            (the AndBundle $next-bundle))
                         ($nparts (frontier-parts-add $parts $part))
                         ($next-score
                            (min-atom ($score
                                       (if (== $part skip-part)
                                          (max $frontier-pscore
                                             (frontier-pool-potential $nparts))
                                          (frontier-part-score $part $frontier-pscore))
                                       (frontier-remaining-score
                                          $typed-next-bundle $nparts)))))
                        (spawn-frontier-heap $agenda
                           $parent-gid
                           $typed-next-bundle
                           $next-score
                           (list_to_set
                              (append-evidence $seen $pev))
                           $nparts
                           (ensure-frontier-path $path-id $pid)
                           $value-spec)))))))
      $agenda))

(: frontier-advance-pooled-heap
   (-[semidet]-> (Heap AgendaEntry) Number AndBundle Number
       (List Evidence)
       (List (| FrontierPart UnpoolablePart))
       Number FrontierValueSpec Number (List Evidence)
       (| FrontierPart SkipPart UnpoolablePart)
       (Heap AgendaEntry)))
(= (frontier-advance-pooled-heap $agenda $parent-gid $bundle
      $score $seen $parts $path-id $value-spec $pid $pev $part)
   (let*
      (($nparts (frontier-parts-add $parts $part))
       ($folded-hits
          (collapse
             (frontier-parts-fold $nparts))))
      (if (== $folded-hits ()) $agenda
         (let $next-bundle
            (frontier-pooled-bundle
               (copy_term $bundle) $pid
               (car-atom $folded-hits))
            (if (== $next-bundle ()) $agenda
               (let*
                  (($typed-next-bundle
                      (the AndBundle $next-bundle))
                   ($next-score
                      (min-atom ($score
                                 (frontier-part-score $part 0.000001)
                                 (frontier-remaining-score
                                    $typed-next-bundle $nparts)))))
                  (spawn-frontier-heap $agenda
                     $parent-gid
                     $typed-next-bundle
                     $next-score
                     (list_to_set
                        (append-evidence $seen $pev))
                     $nparts
                     (ensure-frontier-path $path-id $pid)
                     $value-spec)))))))

(: advance-conditioned-frontier-waiter-heap
   (-[semidet]-> (Heap AgendaEntry) Number Number
       FrontierWaiter (Heap AgendaEntry)))
(= (advance-conditioned-frontier-waiter-heap
      $agenda $child-gid $pid
      (frontier-waiter $parent-gid $bundle $score
         $seen $parts $path-id $value-spec))
   (let $waiter
      (frontier-waiter $parent-gid $bundle $score
         $seen $parts $path-id $value-spec)
      (let*
         (($key (proof-output-key-by-id $pid))
          ($compatible
             (frontier-compatible-source-ids
                $parent-gid $bundle $child-gid))
          ($pids
             (reverse-number-list
                (proof-fold-flat-semidet
                   (proof-output-group-for-key-step $key)
                   () $compatible))))
         (if (== $pids ())
            $agenda
            (let*
               (($representative-pid
                   (proof-output-group-representative-pid $child-gid
                      (proof-output-group $key $pids)))
                ($agenda1
                   (if (frontier-needs-raw-proofs? $bundle)
                      (if (stored-list-member? $pid $compatible)
                         (if (not (== $representative-pid $pid))
                            (advance-frontier-waiter-heap
                               $agenda $waiter $pid)
                            $agenda)
                         $agenda)
                      $agenda)))
               (advance-frontier-waiter-heap
                  $agenda1 $waiter $representative-pid))))))

(: advance-unconditioned-frontier-waiter-heap
   (-[semidet]-> (Heap AgendaEntry) Number Number
       FrontierWaiter (Heap AgendaEntry)))
(= (advance-unconditioned-frontier-waiter-heap
      $agenda $child-gid $pid
      (frontier-waiter $parent-gid $bundle $score
         $seen $parts $path-id $value-spec))
   (let*
      (($waiter
          (frontier-waiter $parent-gid $bundle $score
             $seen $parts $path-id $value-spec))
       ($representative-pid
          (goal-merged-proof-id-for-pid $child-gid $pid)))
      (if (== $representative-pid $pid)
         (advance-frontier-waiter-heap $agenda $waiter $pid)
         (advance-frontier-waiter-heap
            (if (frontier-needs-raw-proofs? $bundle)
               (advance-frontier-waiter-heap $agenda $waiter $pid)
               $agenda)
            $waiter $representative-pid))))

;; Compound reconstruction and strict projection frontiers need a
;; parent-conditioned representative.  All other frontiers retain their exact
;; established raw/merged scheduling semantics.
(: advance-frontier-proof-waiters-heap
   (-[semidet]-> (Heap AgendaEntry) Number Number
       (List Atom) (Heap AgendaEntry)))
(= (advance-frontier-proof-waiters-heap
      $agenda $_child-gid $_pid ())
   $agenda)
(= (advance-frontier-proof-waiters-heap
      $agenda $child-gid $pid (cons $waiter $rest))
   (case $waiter
      (((frontier-waiter $parent-gid $bundle $score
           $seen $parts $path-id $value-spec)
          (let*
             (($typed-waiter
                 (frontier-waiter $parent-gid $bundle $score
                    $seen $parts $path-id $value-spec))
              ($nagenda
                 (if (frontier-needs-conditioned-proofs? $bundle)
                    (advance-conditioned-frontier-waiter-heap
                       $agenda $child-gid $pid $typed-waiter)
                    (advance-unconditioned-frontier-waiter-heap
                       $agenda $child-gid $pid $typed-waiter))))
             (advance-frontier-proof-waiters-heap
                $nagenda $child-gid $pid $rest)))
       ($_other
          (advance-frontier-proof-waiters-heap
             $agenda $child-gid $pid $rest)))))

(: schedule-aggregate-waiters-heap
   (-[semidet]-> (Heap AgendaEntry) (List Atom) (Heap AgendaEntry)))
(= (schedule-aggregate-waiters-heap $agenda ()) $agenda)
(= (schedule-aggregate-waiters-heap $agenda (cons $waiter $rest))
   (case $waiter
      (((aggregate-waiter $agg-gid $_spec)
          (schedule-aggregate-waiters-heap
             (schedule-aggregate-heap $agenda $agg-gid)
             $rest))
       ($_other
          (schedule-aggregate-waiters-heap $agenda $rest)))))

(: wake-proof-commit-heap
   (-[semidet]-> (Heap AgendaEntry) Number Number (Heap AgendaEntry)))
(= (wake-proof-commit-heap $agenda $gid $pid)
   (let*
      (($_demand-cache (mark-goal-demand-dirty! $gid))
       ($_demand-revision (bump-goal-demand-revision! $gid))
       ($waiters
          (stored-atom-list
             (collapse
                (match &goal_waiter
                   ($gid $waiter) $waiter))))
       ($agenda2
          (advance-frontier-proof-waiters-heap
             $agenda $gid $pid $waiters))
       ($agenda3
          (schedule-aggregate-waiters-heap $agenda2 $waiters)))
      $agenda3))

(: commit-proof-candidate-heap
   (-[semidet]-> (Heap AgendaEntry) Number Bool ProofCandidate
       (Heap AgendaEntry)))
(= (commit-proof-candidate-heap $agenda $gid $accepted
      (proof-candidate $kind $score $ev $children))
   (if (== $accepted false) $agenda
      (if (candidate-is-cyclic? $gid $kind $children) $agenda
         (let $pid
            (once
               (store-proof-candidate $gid
                  (proof-candidate $kind $score $ev $children)))
            (wake-proof-commit-heap $agenda $gid $pid)))))

(: commit-aggregate-snapshot-heap
   (-[semidet]-> (Heap AgendaEntry) Number
       (| Goal (Statement KBContext Proof TV))
       (List Evidence) (List Number) (Heap AgendaEntry)))
(= (commit-aggregate-snapshot-heap $agenda $agg-gid $result $ev $children)
   (let*
      (($row (aggregate-by-id $agg-gid))
       ((stored-aggregate-row
            $_stored-agg-gid $_child-gid $_args
            $_base-score $_pending $current-pid)
          $row)
       ($pid
          (once
             (store-aggregate-proof-candidate $agg-gid
                (aggregate-result-candidate $result $ev $children))))
       ($_set
          (set-aggregate-current-pid! $row (cons $pid ())))
       ($_replace
          (if (aggregate-current-pids-stale? $current-pid)
             (supersede-current-proofs! $current-pid)
             (deactivate-current-proofs! $current-pid)))
       ($nagenda (wake-proof-commit-heap $agenda $agg-gid $pid)))
      $nagenda))

(: spawn-frontier-goal-heap
   (-[semidet]-> (Heap AgendaEntry) Number
       FrontierWaiter (Heap AgendaEntry)))

(: advance-frontier-waiter-fold-step
   (-[semidet]-> FrontierWaiter (Heap AgendaEntry) Number
       (Heap AgendaEntry)))
(= (advance-frontier-waiter-fold-step $waiter $agenda $pid)
   (advance-frontier-waiter-heap $agenda $waiter $pid))

(= (spawn-frontier-goal-heap $agenda $gid
      (frontier-waiter $parent-gid $bundle $waiter-score
         $seen $parts $path-id $value-spec))
   (let*
      (($waiter
          (frontier-waiter $parent-gid $bundle $waiter-score
             $seen $parts $path-id $value-spec))
       ($_1 (register-goal-waiter! $gid $parent-gid $waiter))
       ($agenda1
          (proof-fold-flat-semidet (advance-frontier-waiter-fold-step $waiter)
             $agenda
             (frontier-existing-proof-ids
                $parent-gid $bundle $gid)))
       ($nagenda (wake-goal-demand-heap $agenda1 $gid)))
      $nagenda))

(: spawn-frontier-heap
   (-[semidet]-> (Heap AgendaEntry) Number AndBundle Number
       (List Evidence) (List (| FrontierPart UnpoolablePart)) Number
       FrontierValueSpec (Heap AgendaEntry)))
(= (spawn-frontier-heap $agenda $parent-gid $bundle $score
      $seen $parts $path-id $value-spec)
   (let*
      (($goal (and-bundle-goal $bundle))
       ($premises (and-bundle-premises $bundle)))
      (case $premises (
           (()
              (let*
                 (($pid-list
                     (reverse-number-list
                        (frontier-path-rev-proof-ids $path-id)))
                  ($proof-score (term-confidence $goal))
                  ($candidate
                     (normalize-proof-candidate-evidence
                        (proof-candidate
                           (rule $goal) $proof-score $seen $pid-list)))
                  ((proof-candidate $_kind $_candidate-score $candidate-ev $_children) $candidate))
                 (commit-proof-candidate-heap $agenda
                    $parent-gid
                    (classify-goal-proof-candidate $parent-gid $candidate)
                    $candidate)))
           ((cons $prem $_rest)
              (let*
                 (((stored-goal-row
                       $_stored-gid $parent-depth
                       $_goal1 $_expanded $_pending)
                    (goal-by-id $parent-gid))
                  ($gid (ensure-goal-at-depth $prem (+ 1 $parent-depth)))
                  ($stored-bundle (copy_term $bundle)))
                 (spawn-frontier-goal-heap $agenda
                    $gid
                    (frontier-waiter $parent-gid
                       $stored-bundle
                       $score
                       $seen
                       $parts
                       $path-id
                       $value-spec))))))))
