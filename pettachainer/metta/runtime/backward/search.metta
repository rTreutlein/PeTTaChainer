;; Backward search owns scheduler transitions among goals, frontiers, waiters,
;; aggregates, and agenda entries.  A spawned frontier replays compatible
;; durable proofs before deciding whether to wake its child, so historical work
;; is used before new search is scheduled.  A closed ordinary goal wakes only
;; when no producer is represented by a current proof; stable-root re-queries
;; therefore create no agenda work.  Wake propagation permits bounded
;; synchronous re-entry so immediate revisions cannot escape the query budget.
;;
;; The scheduler owns the private &search_wake_active space.  This file also
;; owns the query arena registry: clear-backward-query-state! lists every
;; query-local space, while durable proof-store spaces are cleared separately.

(: SearchState (Alias (Number (Heap AgendaEntry))))
(: AggregateGroupState Type)
(: aggregate-group-state
   (-[det]-> $group $accumulator (List Evidence) (List Number)
       AggregateGroupState))

;; Wake propagation may revisit a goal synchronously through mutually recursive
;; open frontiers.  Two active frames admit the immediate revision while
;; preventing a proof cascade from bypassing the agenda's step budget.
!(bind! &search_wake_active (new-space))

(: clear-backward-query-state! (-[det]-> (List $none)))
(= (clear-backward-query-state!)
   (let $_clear
      (foreach-flat remove-all-atoms
         (&goal &goal_lookup &goal_waiter &goal_child
          &goal_demand_cache &goal_demand_revision &goal_demand_wake
          &goal_current_confidence &root_goal &search_wake_active
          &fold_source
          &frontier_path &frontier_path_lookup &frontier_path_child
          &frontier_path_dead &proof_frontier_path
          &proof_live_cache &proof_invalidated &proof_cycle_cache))
      ()))

;; index-hash seals variables before hashing.  The hash is the generated
;; store predicate's indexed first argument; the full key and alpha check
;; reject collisions.
(: ensure-goal-at-depth
   (-[semidet]-> (| Goal (Statement KBContext Proof TV)) Number Number))
(= (ensure-goal-at-depth $goal $depth)
   (let* (($stored-goal (copy_term $goal))
          ($key (brand ProofGoalKey (goal-key $stored-goal)))
          ($lookup-key (index-hash $key))
          ($hits
             (collapse
                (once
                   (match &goal_lookup
                      ($lookup-key $stored-key $gid)
                      (if (=alpha $stored-key $key)
                         (stored-number $gid)
                         (empty)))))))
      (if (== $hits ())
         (let* (($gid (next-gid))
                ($_goal
                   (once
                      (chainer-add-atom &goal
                         (stored-goal-row
                            $gid $depth $stored-goal false
                            (goal-agenda-state 0 0 0.0 ())))))
                ($_lookup
                   (add-space-atom! &goal_lookup
                      (make-space-row3 $lookup-key $key $gid))))
            $gid)
         (let* (($gid (first-number $hits))
                ($row (goal-by-id $gid))
                ((stored-goal-row
                    $_stored-gid $stored-depth $stored-goal
                    $expanded $state)
                   $row)
                ($_lower
                   (if $expanded ()
                      (if (< $depth $stored-depth)
                         (let* (($_remove (remove-atom &goal $row))
                                ($_add
                                   (once
                                      (chainer-add-atom &goal
                                         (stored-goal-row
                                            $gid $depth $stored-goal
                                            false $state)))))
                            ())
                         ()))))
            $gid))))

;; --- Agenda issue, refresh, and pruning -------------------------------------

(: add-goal-agenda-entry-heap
   (-[semidet]-> (Heap AgendaEntry) StoredGoalRow Number Number AgendaKind Number
       (Heap AgendaEntry)))
(= (add-goal-agenda-entry-heap
      $agenda $row $revision $generation $kind $score)
   (let* (((stored-goal-row
              $gid $depth $goal $_expanded $_state)
             $row)
          ($child-hits
             (case $kind (
                (agenda-aggregate
                   (let (fold-source-row
                           $_fold-gid $child-gid $_args
                           $_base $_budget $_approx)
                      (fold-source-by-id $gid)
                      (collapse (once (goal-by-id $child-gid)))))
                ($_other ()))))
          ($agenda-row
             (case $child-hits (
                (() $row)
                ((cons $child-row $_other-child-rows) $child-row))))
          ((stored-goal-row
              $_agenda-gid $agenda-depth $_agenda-goal
              $agenda-expanded $_agenda-state)
             $agenda-row)
          ($aggregate-bonus
             (if (== $child-hits ()) 0.0
                (if $agenda-expanded 1.0 0.0)))
          ($priority
             (case $goal (
                ((CPU $_fun $_args $_result)
                   (+
                      (backward-agenda-priority
                         $agenda-depth $score
                         (if (== $kind agenda-aggregate)
                            $aggregate-bonus 1.0)
                         $kind)
                      (* 0.000001 $gid)))
                (($type ($_kbid $context $_vars) $_proof $_tv)
                   (+
                      (backward-agenda-priority
                         $agenda-depth $score $aggregate-bonus $kind)
                      (if (if (is-expr $type)
                             (== (car-atom $type) Inheritance)
                             false)
                         (if (goal-has-type-vars? $goal)
                            0.0
                            (* 0.000001 $gid))
                         (if (== $context MAIN)
                            0.0
                            (* -0.000001 $gid))))))))
          ($_metric (increment-backward-query-metric! agenda-pushes)))
      (add_to_heap $agenda $priority
         (agenda-entry $kind $gid
            (agenda-revision-token $revision $generation)))))

(: add-goal-agenda-lanes-heap
   (-[semidet]-> (Heap AgendaEntry) StoredGoalRow Number Number
       AgendaKind Number (List AgendaKind) (Heap AgendaEntry)))
(= (add-goal-agenda-lanes-heap
      $agenda $_row $_revision $_generation
      $_requested-kind $_requested-score ())
   $agenda)
(= (add-goal-agenda-lanes-heap
      $agenda $row $revision $generation
      $requested-kind $requested-score (cons $kind $rest))
   (add-goal-agenda-lanes-heap
      (add-goal-agenda-entry-heap
         $agenda $row $revision $generation $kind
         (if (== $kind $requested-kind)
            $requested-score
            (let (stored-goal-row $gid $_depth $_goal $_expanded $_state)
               $row
               (agenda-kind-score $kind $gid))))
      $row $revision $generation
      $requested-kind $requested-score $rest))

(: request-goal-agenda-kind-heap
   (-[semidet]-> (Heap AgendaEntry) Number AgendaKind
       (Heap AgendaEntry)))
(: request-goal-agenda-kind-score-heap
   (-[semidet]-> (Heap AgendaEntry) Number AgendaKind Number
       (Heap AgendaEntry)))
(= (request-goal-agenda-kind-heap $agenda $gid $kind)
   (request-goal-agenda-kind-score-heap
      $agenda $gid $kind (agenda-kind-score $kind $gid)))
(= (request-goal-agenda-kind-score-heap $agenda $gid $kind $score)
   (let* (($row (goal-by-id $gid))
          ((stored-goal-row
              $_stored-gid $depth $_goal $_expanded $state)
             $row)
          ((goal-agenda-state
              $issued-generation $_issued-revision $issued-score
              $requested-lanes)
             $state)
          ($requested?
             (stored-list-member? $kind $requested-lanes))
          ($issue?
             (if $requested? (> $score $issued-score) true)))
      (if $issue?
         (let* (($revision (goal-demand-revision $gid))
                ($generation (+ $issued-generation 1))
                ($lanes
                   (if $requested? $requested-lanes
                      (cons $kind $requested-lanes)))
                ($_state
                   (set-goal-agenda-state! $row
                      (goal-agenda-state
                         $generation $revision $score $lanes))))
            (add-goal-agenda-lanes-heap
               $agenda $row $revision $generation
               $kind $score $lanes))
         $agenda)))

(: retoken-goal-agenda-entry-heap
   (-[semidet]-> (Heap AgendaEntry) AgendaEntry (Heap AgendaEntry)))
(= (retoken-goal-agenda-entry-heap $agenda
      (agenda-entry $kind $gid
         (agenda-revision-token $_old-revision $generation)))
   ;; claim-owned-goal-agenda-entry! refreshed this state before it returned
   ;; agenda-retoken; reissue exactly that revision and score.
   (let* (($row (goal-by-id $gid))
          ((stored-goal-row
              $_stored-gid $_depth $_goal $_expanded $state)
             $row)
          ((goal-agenda-state
              $generation $revision $score $_lanes)
             $state))
      (add-goal-agenda-entry-heap
         $agenda $row $revision $generation $kind $score)))

(: BackwardAgendaPartition Type)
(: backward-agenda-partition
   (-[det]-> (Heap AgendaEntry) (Heap AgendaEntry)
       BackwardAgendaPartition))

(: partition-backward-agenda
   (-[det]-> (Heap AgendaEntry) (Heap AgendaEntry) (Heap AgendaEntry)
       BackwardAgendaPartition))
(: partition-backward-agenda-pop
   (-[det]-> (Heap AgendaEntry) (Heap AgendaEntry)
       (Number AgendaEntry (Heap AgendaEntry))
       BackwardAgendaPartition))
(= (partition-backward-agenda $agenda $control $expand)
   (case (collapse (heap_pop $agenda)) (
      (() (backward-agenda-partition $control $expand))
      ((cons $pop $_tail)
         (partition-backward-agenda-pop
            $control $expand $pop)))))

(= (partition-backward-agenda-pop
      $control $expand ($priority $entry $rest))
   (if (agenda-entry-owned? $entry)
      (case $entry (
         ((agenda-entry agenda-expand $_gid $_token)
            (partition-backward-agenda $rest $control
               (add_to_heap $expand $priority $entry)))
         ($_other
            (partition-backward-agenda $rest
               (add_to_heap $control $priority $entry) $expand))))
      (partition-backward-agenda $rest $control $expand)))

(: release-agenda-heap! (-[det]-> (Heap AgendaEntry) (List $none)))
(: release-agenda-heap-pop!
   (-[det]-> (Number AgendaEntry (Heap AgendaEntry)) (List $none)))
(= (release-agenda-heap! $agenda)
   (case (collapse (heap_pop $agenda)) (
      (() ())
      ((cons $pop $_tail) (release-agenda-heap-pop! $pop)))))
(= (release-agenda-heap-pop! ($_priority $entry $rest))
   (let $_release (release-pruned-agenda-entry! $entry)
      (release-agenda-heap! $rest)))

(: backward-agenda-prune-to-size
   (-[semidet]-> Number (Heap AgendaEntry) (Heap AgendaEntry)))
(= (backward-agenda-prune-to-size $target $agenda)
   (let (backward-agenda-partition $control $expand)
      (partition-backward-agenda
         $agenda (empty_heap) (empty_heap))
      (let* (($control-size
                (first-number (collapse (heap_size $control))))
             ($expand-limit (max 0 (- $target $control-size)))
             ((heap-split $kept-expand $discarded-expand)
                (heap-split-best
                   $expand-limit $expand (empty_heap)))
             ($_release (release-agenda-heap! $discarded-expand)))
         (heap-merge-into $kept-expand $control))))

(: bounded-backward-agenda-prune
   (-[semidet]-> Number (Heap AgendaEntry) (Heap AgendaEntry)))
(= (bounded-backward-agenda-prune $steps $agenda)
   (if (bounded-agenda-prune-needed? $steps $agenda)
      (backward-agenda-prune-to-size
         (bounded-agenda-target-size $steps) $agenda)
      $agenda))

;; --- Demand wake-up ----------------------------------------------------------

(: wake-goal-demand-heap
   (-[semidet]-> (Heap AgendaEntry) Number (Heap AgendaEntry)))
(= (wake-goal-demand-heap $agenda $gid)
   (let* (($row (goal-by-id $gid))
          ((stored-goal-row
              $_stored-gid $_depth $goal $expanded $_state)
             $row)
          ($wake-descendants?
             (not
                (==
                   (collapse
                      (once
                         (match &goal_demand_wake ($gid)
                            (let $_clear
                               (remove-atom &goal_demand_wake ($gid))
                               true))))
                   ()))))
      (if $expanded
         (if $wake-descendants?
            (if (<= (goal-demand-sum $gid) 0.0) $agenda
               (proof-fold-flat-semidet wake-goal-demand-heap
                  $agenda (goal-demand-child-gids $gid)))
            $agenda)
         (let $score (goal-demand-sum $gid)
            (if (<= $score 0.0) $agenda
               (request-goal-agenda-kind-score-heap
                  $agenda $gid agenda-expand $score))))))

(: schedule-root-goal-heap
   (-[semidet]-> (Heap AgendaEntry) Number (Heap AgendaEntry)))
(= (schedule-root-goal-heap $agenda $gid)
   (let* (((stored-goal-row
              $_stored-gid $_depth $goal $_expanded $_state)
             (goal-by-id $gid))
          ($pids
             (current-proof-ids-for-goal-key
                (proof-goal-key-by-goal-id $gid))))
      (if (replayed-frontier-needs-wake? $goal $pids)
         (wake-goal-demand-heap $agenda $gid)
         $agenda)))

;; --- Frontier advancement and proof propagation -----------------------------

(: frontier-proof-admissible?
   (-[semidet]-> Number AndBundle (List Evidence)
       (List (| FrontierPart UnpoolablePart)) Number
       (List Evidence) (| FrontierPart SkipPart UnpoolablePart) Bool))
(= (frontier-proof-admissible?
      $parent-gid $bundle $seen $parts $pid $evidence $part)
   (let* (($goal (and-bundle-goal $bundle))
          ($parent-proof (frontier-bundle-proof $bundle))
          ($opposite-bi-direction?
             (case $parent-proof (
                ((by (bi-forward $_name) $_dependency)
                   (frontier-opposite-bi-direction?
                      (the Proof $parent-proof) (materialize-proof $pid)))
                ((by (bi-backward $_name) $_dependency)
                   (frontier-opposite-bi-direction?
                      (the Proof $parent-proof) (materialize-proof $pid)))
                ($_other false)))))
      (if
         $opposite-bi-direction?
         false
         (if
            (proof-depends-on-goal-seen?
               $pid $parent-gid
               (candidate-cycle-key $parent-gid (rule $goal)) ())
            (case $goal (
               (($type $_kb $_proof $_tv)
                  (implication-type? (brand Statement $type)))
               ($_other false)))
            (if (frontier-allows-shared-evidence? $bundle) true
               (if (not (evidence-sets-overlap? $seen $evidence)) true
                  (frontier-pool-join?
                     $part $parts $seen $evidence)))))))

(: commit-frontier-result-heap
   (-[semidet]-> (Heap AgendaEntry) Number AndBundle
       (List Evidence) Number (Heap AgendaEntry)))
(: commit-checked-proof-candidate-heap
   (-[semidet]-> (Heap AgendaEntry) Number ProofCandidate
       (Heap AgendaEntry)))

(= (commit-frontier-result-heap
      $agenda $parent-gid $bundle $evidence $path-id)
   (let* (($goal
             (frontier-goal-proof-view (and-bundle-goal $bundle)))
          ($candidate
             (normalize-proof-candidate-evidence
                (proof-candidate
                   (rule $goal) (term-confidence $goal) $evidence
                   (reverse-number-list
                      (frontier-path-rev-proof-ids $path-id)))))
          ($accepted
             (chainer-first-or false
                (collapse
                   (once
                      (classify-goal-proof-candidate
                         $parent-gid $candidate))))))
      ;; Admissibility tested the premises against the open goal; the
      ;; instantiated result is checked for cycles here like any commit.
      (commit-proof-candidate-heap $agenda $parent-gid $accepted $candidate)))

(: spawn-frontier-heap
   (-[semidet]-> (Heap AgendaEntry) Number AndBundle Number
       (List Evidence) (List (| FrontierPart UnpoolablePart)) Number
       FrontierValueSpec (Heap AgendaEntry)))
(: frontier-waiter-step
   (-[semidet]-> FrontierWaiter (Heap AgendaEntry) Number
       (Heap AgendaEntry)))
(: owned-frontier-waiter-step
   (-[semidet]-> FrontierWaiter (Heap AgendaEntry) Number
       (Heap AgendaEntry)))
(: advance-frontier-waiter-heap
   (-[semidet]-> (Heap AgendaEntry) FrontierWaiter Number
       ((| Goal (Statement KBContext Proof TV))
          ProofKind ProofSupport (List Number))
       (| FrontierPart SkipPart UnpoolablePart) Number (List Evidence)
       (Heap AgendaEntry)))
(: replayed-frontier-needs-wake?
   (-[det]-> (| Goal (Statement KBContext Proof TV))
       (List Number) Bool))
(: proof-generated-by-rule?
   (-[det]-> Proof Proof Bool))
(= (proof-generated-by-rule? $proof $rule-proof)
   (if (is-var $proof) false
      (if (and
             (and (is-expr $proof) (is-expr $rule-proof))
             (and (== (car-atom $proof) by)
                  (== (car-atom $rule-proof) by)))
         (=alpha
            (car-atom (cdr-atom $proof))
            (car-atom (cdr-atom $rule-proof)))
         (if (and (is-expr $proof)
                  (== (car-atom $proof) merge/revision))
         (let* (($branches (cdr-atom $proof))
                ($left (car-atom $branches))
                ($right (car-atom (cdr-atom $branches))))
            (or
               (proof-generated-by-rule?
                  (brand Proof $left) $rule-proof)
               (proof-generated-by-rule?
                  (brand Proof $right) $rule-proof)))
         (let ($candidate $pattern)
            (copy_term (quote ($proof $rule-proof)))
            (if (= $pattern $candidate) true false))))))

(: replayed-proofs-use-rule?
   (-[det]-> (List Number) Proof Bool))
(: proof-list-has-aggregate?
   (-[det]-> (List Number) Bool))
(: replayed-rule-needs-wake?
   (-[semidet]-> (List Number)
      (List (| Goal (Statement KBContext Proof TV))) Proof Bool))
(= (proof-list-has-aggregate? ()) false)
(= (proof-list-has-aggregate? (cons $pid $rest))
   (let $row
      (chainer-first-or no-proof-row
         (collapse (once (proof-row-by-id $pid))))
      (case $row (
         (($_output (aggregate $_result) $_support $_children) true)
         ($_other (proof-list-has-aggregate? $rest))))))
(= (replayed-proofs-use-rule? () $_rule-proof) false)
(= (replayed-proofs-use-rule? (cons $pid $rest) $rule-proof)
   (let $row
      (chainer-first-or no-proof-row
         (collapse (once (proof-row-by-id $pid))))
      (case $row (
         (($_output $kind $_support $children)
            (if (proof-list-has-aggregate? $children)
               (replayed-proofs-use-rule? $rest $rule-proof)
               (case $kind (
                  ((rule ($_type $_kb $proof $_tv))
                     (if (proof-generated-by-rule?
                            (brand Proof $proof) $rule-proof)
                        true
                        (replayed-proofs-use-rule?
                           $rest $rule-proof)))
                  ($_other
                     (replayed-proofs-use-rule?
                        $rest $rule-proof))))))
         ($_missing
            (replayed-proofs-use-rule? $rest $rule-proof))))))
(= (replayed-rule-needs-wake? $pids $premises $rule-proof)
   (if (inverted-rule-proof? $rule-proof) false
      (if (generated-reverse-rule-proof? $rule-proof)
         (if (generated-reverse-rule-needed? $pids $premises $rule-proof)
            (not (replayed-proofs-use-rule? $pids $rule-proof))
            false)
         (not (replayed-proofs-use-rule? $pids $rule-proof)))))

(: search-goal-has-untried-rule?
   (-[det]-> (| Goal (Statement KBContext Proof TV))
      (List Number) Bool))
(= (search-goal-has-untried-rule? $goal $pids)
   (case $goal (
      ((CPU $_fun $_args $_result) false)
      (($_type $_kb $_proof $_tv)
         (let $lookup-goal
            (copy_term (data $_type $_kb $_proof $_tv))
            (not
               (==
                  (collapse
                     (once
                        (match ccls_index
                           ($lookup-goal $_rule-id $args)
                           (if (= $lookup-goal $goal)
                              (case $lookup-goal (
                                 (($_rule-type $_rule-kb
                                     $rule-proof $_rule-tv)
                                    (if (replayed-rule-needs-wake?
                                           $pids $args
                                           (brand Proof $rule-proof))
                                       true
                                       (empty)))))
                              (empty)))))
                  ())))))))
(= (replayed-frontier-needs-wake? $premise $pids)
   (if (== $pids ()) true
      (if
         (case $premise (
            ((CPU $fun $_args $_result)
               (aggregate-fold-function? $fun))
            (($type $_kb $_proof $_tv)
               (compound-source? (brand Statement $type)))
            ($_other false)))
         true
         (if (goal-has-type-vars? $premise) true
            (search-goal-has-untried-rule? $premise $pids)))))

(= (spawn-frontier-heap
      $agenda $parent-gid $bundle $score $seen $parts $path-id $value-spec)
   (case (and-bundle-premises $bundle) (
      (() (commit-frontier-result-heap
             $agenda $parent-gid $bundle $seen $path-id))
      ((cons $premise $_rest)
         (let* (((stored-goal-row
                    $_gid $parent-depth $_goal $_expanded $_state)
                   (goal-by-id $parent-gid))
                ($child-gid
                   (ensure-goal-at-depth $premise (+ $parent-depth 1)))
                ($waiter
                   (frontier-waiter
                      $parent-gid $bundle $score $seen $parts $path-id
                      $value-spec))
                ($_wait
                   (register-goal-waiter!
                      $child-gid $parent-gid $waiter))
                ($existing-pids
                   (frontier-existing-proof-ids
                      $parent-gid $bundle $child-gid))
                ($existing-agenda
                   (proof-fold-flat-semidet
                      (frontier-waiter-step $waiter)
                      $agenda $existing-pids))
                ($wake?
                   (replayed-frontier-needs-wake?
                      $premise $existing-pids)))
            (if $wake?
               (wake-goal-demand-heap $existing-agenda $child-gid)
               $existing-agenda))))))

(= (frontier-waiter-step $waiter $agenda $pid)
   (let $branch-waiter (copy_term $waiter)
      (owned-frontier-waiter-step
         $branch-waiter $agenda $pid)))

(= (owned-frontier-waiter-step $waiter $agenda $pid)
   (let (frontier-waiter
            $parent-gid $bundle $score $seen $parts $path-id
            (frontier-value-spec
               $candidate-score $_premise-count $_success-prior))
         $waiter
         (let* (($proof-row (proof-row-by-id $pid))
                (($_output $_kind $support $_children) $proof-row)
                ((proof-support $proof-score $proof-evidence
                    $contribution) $support)
                ($part
                   (the (| FrontierPart SkipPart UnpoolablePart)
                      (frontier-premise-part
                         (proof-support
                            $proof-score $proof-evidence
                            $contribution))))
                ($admissible?
                   (chainer-first-or false
                      (collapse
                         (once
                            (if (frontier-path-live? $path-id)
                               (frontier-proof-admissible?
                                  $parent-gid $bundle $seen $parts
                                  $pid $proof-evidence $part)
                               false))))))
            (if $admissible?
               (advance-frontier-waiter-heap
                  $agenda $waiter $pid $proof-row
                  $part $proof-score $proof-evidence)
               $agenda))))

(= (advance-frontier-waiter-heap
      $agenda
      (frontier-waiter
         $parent-gid $bundle $score $seen $parts $path-id
         (frontier-value-spec
            $candidate-score $_premise-count $_success-prior))
      $pid ($proof-output $proof-kind $_support $_children)
      $part $proof-score $proof-evidence)
   (let* (($next-parts
             (the (List (| FrontierPart UnpoolablePart))
                (frontier-parts-add $parts $part)))
          ($next-seen
             (list_to_set
                (append-flat $seen $proof-evidence)))
          ($next-path-id (ensure-frontier-path $path-id $pid))
          ($_retain-raw-path
             (case $proof-kind (
                ((merged $_output) ())
                ($_raw
                   (case (and-bundle-goal $bundle) (
                      (($_type $_kb $proof $_tv)
                         (if
                            (proof-term-conjunction-dependency?
                               (brand Proof (copy_term $proof)))
                            (remove-atom &proof_frontier_path
                               ($pid $next-path-id))
                            ()))
                      ($_other ())))))))
          ($next-score
             (min $score
                (let $part-score (frontier-part-score $part $proof-score)
                   (if (= $proof-output (CPU $_fun $_args $_res))
                      (max 0.000001 $part-score)
                      $part-score))))
          ($advanced
             (case $part (
                ((pool-part $_pool-key $_pool-tv $_pool-arity
                    $_pool-idxs $_pool-ev $_pool-mtv)
                   (if (frontier-parts-contain-pool? $part $parts)
                      (frontier-pooled-bundle $bundle $pid
                         (frontier-parts-fold $next-parts))
                      (advance-frontier-bundle $bundle $pid)))
                ($_part (advance-frontier-bundle $bundle $pid))))))
      (case $advanced (
         (() $agenda)
         ((and-bundle $goal $premises)
            (let* (($next-bundle
                      (the AndBundle (and-bundle $goal $premises)))
                   ($next-value
                      (frontier-value-spec
                         (min $candidate-score
                            (if (== $premises ()) $next-score
                               (min $next-score
                                  (frontier-remaining-score
                                     $next-bundle $next-parts))))
                         (list-len $premises)
                         (premises-proof-success-prior $premises))))
               (spawn-frontier-heap
                  $agenda $parent-gid $next-bundle $next-score
                  $next-seen $next-parts $next-path-id $next-value)))))))

(: wake-waiter-step
   (-[det]-> Number (Heap AgendaEntry)
       (| FrontierWaiter AggregateWaiter Atom) (Heap AgendaEntry)))
(= (wake-waiter-step $pid $agenda $waiter)
   (case $waiter (
      ((frontier-waiter $parent $bundle $score $seen $parts
          $path $value)
         (chainer-first-or $agenda
            (collapse
               (once
                  (owned-frontier-waiter-step
                     (frontier-waiter
                        $parent $bundle $score $seen $parts $path $value)
                     $agenda $pid)))))
      ((aggregate-waiter $agg $_spec)
         (chainer-first-or $agenda
            (collapse
               (once
                  (schedule-aggregate-heap
                     $agenda (stored-number $agg))))))
      ($_other $agenda))))

(: wake-proof-commit-heap
   (-[det]-> (Heap AgendaEntry) Number Number
       (Heap AgendaEntry)))
(= (wake-proof-commit-heap $agenda $gid $pid)
   (let* (($active-hits
             (collapse
                (once
                   (match &search_wake_active
                      ($gid $depth) (stored-number $depth)))))
          ($depth
             (if (== $active-hits ()) 0
                (first-number $active-hits))))
      (if (>= $depth 2) $agenda
         (let* (($_old
                   (if (== $depth 0) ()
                      (remove-atom &search_wake_active
                         ($gid $depth))))
                ($next-depth (+ $depth 1))
                ($_active
                   (once
                      (add-atom &search_wake_active
                         ($gid $next-depth))))
             ($next
                (chainer-first-or $agenda
                   (collapse
                      (once
                         (let* (($_revision
                                   (bump-goal-demand-revision! $gid))
                                ($waiters
                                   (stored-atom-list
                                      (collapse
                                         (match &goal_waiter
                                            ($gid $waiter) $waiter))))
                                ($propagated
                                   (proof-fold-flat-semidet
                                      (wake-waiter-step $pid)
                                      $agenda $waiters)))
                            (proof-fold-flat-semidet wake-goal-demand-heap
                               $propagated
                               (goal-demand-child-gids $gid)))))))
                ($_done
                   (remove-atom &search_wake_active
                      ($gid $next-depth)))
                ($_restore
                   (if (== $depth 0) ()
                      (once
                         (add-atom &search_wake_active
                            ($gid $depth))))))
            $next))))

(: commit-proof-candidate-heap
   (-[semidet]-> (Heap AgendaEntry) Number Bool ProofCandidate
       (Heap AgendaEntry)))
(= (commit-proof-candidate-heap
      $agenda $gid $accepted
      (proof-candidate $kind $score $evidence $children))
   (if (== $accepted false) $agenda
      (if (candidate-is-cyclic? $gid $kind $children) $agenda
         (commit-checked-proof-candidate-heap
            $agenda $gid
            (proof-candidate $kind $score $evidence $children)))))

(= (commit-checked-proof-candidate-heap
      $agenda $gid
      (proof-candidate $kind $score $evidence $children))
   (let* (($goal-key (proof-goal-key-by-goal-id $gid))
             ($output-key
                (candidate-output-key (candidate-kind-term $kind)))
             ($pid
                (once
                   (store-proof-candidate $gid
                      (proof-candidate
                         $kind $score $evidence $children))))
             ($indexed
                (collapse
                   (once
                      (current-proof-result-id-for-output-key
                         $goal-key $output-key))))
             ($representative
                (case $indexed (
                   ((cons $current $_rest) $current)
                   (() (goal-merged-proof-id-for-pid $gid $pid))))))
         (wake-proof-commit-heap
            $agenda $gid $representative)))

;; --- Fold refresh scheduling -------------------------------------------------

(: schedule-aggregate-heap
   (-[semidet]-> (Heap AgendaEntry) Number (Heap AgendaEntry)))
(= (schedule-aggregate-heap $agenda $agg-gid)
   (let (fold-source-row
           $_gid $_child $_args $base-score $_budget $_approx)
      (fold-source-by-id $agg-gid)
      (request-goal-agenda-kind-score-heap
         $agenda $agg-gid agenda-aggregate $base-score)))
