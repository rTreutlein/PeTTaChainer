;; Backward agenda, demand propagation, and proof-frontier expansion state.
;; These mechanisms form one recursive search component: scheduling reads
;; demand while demand changes wake and reschedule existing frontier goals.
;; The backward heap has one payload shape and one revision protocol.
(: SearchState
   (Alias (Number (Heap AgendaEntry))))
(: chainer-first-or (-[det]-> $value (List $value) $value))
(= (chainer-first-or $fallback ()) $fallback)
(= (chainer-first-or $_fallback (cons $value $_rest)) $value)

;; Keep the query arena in one registry.  Tests that need a completely empty
;; proof store clear the durable spaces separately after calling this helper.
(: clear-backward-query-state! (-[det]-> (List $none)))
(= (clear-backward-query-state!)
   (foreach-flat remove-all-atoms
      (&goal &goal_lookup &goal_waiter &goal_waiter_delivery
       &goal_child &goal_current_confidence
       &goal_demand_cache &goal_demand_revision &root_goal
       &goal_demand_wake
       &aggregate &aggregate_search_budget &aggregate_forward_approx
       &proof_invalidated &proof_live_cache
       &frontier_path_lookup &frontier_path &frontier_path_child
       &proof_frontier_path &frontier_path_dead)))

(: AndBundle Type)
(: and-bundle
   (-[det]-> (| Goal (Statement KBContext Proof TV))
       (List (| Goal (Statement KBContext Proof TV)))
       AndBundle))
(= (get-type (and-bundle $goal $premises)) AndBundle)

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
                            0 0 0.0 false false false false)))))
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

(: goal-agenda-kind-requested-in-state?
   (-[det]-> AgendaKind GoalAgendaState Bool))
(= (goal-agenda-kind-requested-in-state? $kind
      (goal-agenda-state
         $_generation $_issued-revision $_issued-score
         $expand $refresh $resume $aggregate))
   (case $kind (
      (agenda-expand $expand)
      (agenda-refresh $refresh)
      (agenda-resume $resume)
      (agenda-aggregate $aggregate))))

(: goal-agenda-state-request
   (-[det]-> AgendaKind Number Number GoalAgendaState GoalAgendaState))
(= (goal-agenda-state-request $kind $issued-revision $issued-score
      (goal-agenda-state
         $generation $_old-revision $_old-score
         $expand $refresh $resume $aggregate))
   (case $kind (
      (agenda-expand
         (goal-agenda-state
            (+ $generation 1) $issued-revision $issued-score
            true $refresh $resume $aggregate))
      (agenda-refresh
         (goal-agenda-state
            (+ $generation 1) $issued-revision $issued-score
            $expand true $resume $aggregate))
      (agenda-resume
         (goal-agenda-state
            (+ $generation 1) $issued-revision $issued-score
            $expand $refresh true $aggregate))
      (agenda-aggregate
         (goal-agenda-state
            (+ $generation 1) $issued-revision $issued-score
            $expand $refresh $resume true)))))

(: goal-agenda-state-clear
   (-[det]-> AgendaKind GoalAgendaState GoalAgendaState))
(= (goal-agenda-state-clear $kind
      (goal-agenda-state
         $generation $issued-revision $issued-score
         $expand $refresh $resume $aggregate))
   (case $kind (
      (agenda-expand
         (goal-agenda-state
            $generation $issued-revision $issued-score
            false $refresh $resume $aggregate))
      (agenda-refresh
         (goal-agenda-state
            $generation $issued-revision $issued-score
            $expand false $resume $aggregate))
      (agenda-resume
         (goal-agenda-state
            $generation $issued-revision $issued-score
            $expand $refresh false $aggregate))
      (agenda-aggregate
         (goal-agenda-state
            $generation $issued-revision $issued-score
            $expand $refresh $resume false)))))

;; Replace a goal row's agenda state. The removal must see the exact stored
;; row, so callers pass the row they fetched via goal-by-id.
(: set-goal-agenda-state!
   (-[semidet]-> StoredGoalRow GoalAgendaState (| Bool (List $none))))
(= (set-goal-agenda-state!
      (stored-goal-row $gid $depth $goal $expanded $state)
      $next-state)
   (progn
      (remove-atom &goal
         (stored-goal-row $gid $depth $goal $expanded $state))
      (once
         (chainer-add-atom &goal
            (stored-goal-row $gid $depth $goal $expanded $next-state)))))

(: goal-agenda-kind-requested? (-[det]-> Number AgendaKind Bool))
(= (goal-agenda-kind-requested? $gid $kind)
   (let $hits (collapse (once (goal-by-id $gid)))
      (case $hits (
         (() false)
         ((cons
             (stored-goal-row
                $_stored-gid $_depth $_goal $_expanded $state)
             $_rest)
            (goal-agenda-kind-requested-in-state? $kind $state))))))

(: goal-agenda-bonus
   (-[det]-> (| Goal (Statement KBContext Proof TV)) Number))
(= (goal-agenda-bonus $goal)
   (let $closed-proof-bonus
      (if (goal-has-type-vars? $goal) 0.0 1.0)
      (case $goal (
         (($_type ($_kbid $_ctx $_vars) $_prf $_tv)
            $closed-proof-bonus)
         ($_other 2.0)))))

(: agenda-kind-score (-[det]-> AgendaKind Number Number))
(= (agenda-kind-score $kind $gid)
   (case $kind (
      (agenda-aggregate
         (let $hits (collapse (once (aggregate-by-id $gid)))
            (case $hits (
               (() 0.0)
               ((cons
                   (stored-aggregate-row
                      $_agg-gid $_child-gid $_args
                      $base-score $_pending $_current-pid)
                   $_rest)
                  $base-score)))))
      ($_goal-kind (goal-demand-sum $gid)))))

(: enqueue-goal-agenda-kind-heap
   (-[semidet]-> (Heap AgendaEntry) Number Number
       (| Goal (Statement KBContext Proof TV))
       GoalAgendaState AgendaKind (Heap AgendaEntry)))
(= (enqueue-goal-agenda-kind-heap
      $agenda $gid $depth $goal
      (goal-agenda-state
         $generation $issued-revision $_issued-score
         $_expand $_refresh $_resume $_aggregate)
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
   (let* (($agenda1
             (if (goal-agenda-kind-requested-in-state?
                    agenda-resume $state)
                (enqueue-goal-agenda-kind-heap
                   $agenda $gid $depth $goal $state agenda-resume)
                $agenda))
          ($agenda2
             (if (goal-agenda-kind-requested-in-state?
                    agenda-expand $state)
                (enqueue-goal-agenda-kind-heap
                   $agenda1 $gid $depth $goal $state agenda-expand)
                $agenda1))
          ($agenda3
             (if (goal-agenda-kind-requested-in-state?
                    agenda-refresh $state)
                (enqueue-goal-agenda-kind-heap
                   $agenda2 $gid $depth $goal $state agenda-refresh)
                $agenda2)))
      (if (goal-agenda-kind-requested-in-state?
             agenda-aggregate $state)
         (enqueue-goal-agenda-kind-heap
            $agenda3 $gid $depth $goal $state agenda-aggregate)
         $agenda3)))

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
               $_expand $_refresh $_resume $_aggregate)
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

(: AgendaEntryDisposition Type)
(: agenda-claimed AgendaEntryDisposition)
(: agenda-retoken AgendaEntryDisposition)
(: agenda-cancelled AgendaEntryDisposition)
(: agenda-stale AgendaEntryDisposition)

(: agenda-entry-owned? (-[det]-> AgendaEntry Bool))
(= (agenda-entry-owned?
      (agenda-entry $kind $gid
         (agenda-revision-token $_demand-revision $generation)))
   (let $hits (collapse (once (goal-by-id $gid)))
      (case $hits (
         (() false)
         ((cons
             (stored-goal-row
                $_stored-gid $_depth $_goal $_expanded
                (goal-agenda-state
                   $current-generation $issued-revision $_issued-score
                   $expand $refresh $resume $aggregate))
             $_rest)
            (if (== $generation $current-generation)
               (goal-agenda-kind-requested-in-state? $kind
                  (goal-agenda-state
                     $current-generation $issued-revision $_issued-score
                     $expand $refresh $resume $aggregate))
               false))))))

(: goal-agenda-issued-score (-[det]-> Number Number))
(= (goal-agenda-issued-score $gid)
   (let $hits (collapse (once (goal-by-id $gid)))
      (case $hits (
         (() 0.0)
         ((cons
             (stored-goal-row
                $_stored-gid $_depth $_goal $_expanded
                (goal-agenda-state
                   $_generation $_issued-revision $issued-score
                   $_expand $_refresh $_resume $_aggregate))
             $_rest)
            $issued-score)))))

(: clear-owned-goal-agenda-kind!
   (-[det]-> Number AgendaKind Number (List $none)))
(= (clear-owned-goal-agenda-kind! $gid $kind $generation)
   (let $_clear
      (collapse
         (clear-owned-goal-agenda-kind-row!
            $gid $kind $generation))
      ()))

(: clear-owned-goal-agenda-kind-row!
   (-[semidet]-> Number AgendaKind Number (List $none)))
(= (clear-owned-goal-agenda-kind-row! $gid $kind $generation)
   (let*
      (($row (goal-by-id $gid))
       ((stored-goal-row
            $_stored-gid $_depth $_goal $_expanded $state)
          $row)
       ((goal-agenda-state
            $generation $_issued-revision $_issued-score
            $_expand $_refresh $_resume $_aggregate)
          $state)
       ($_set
          (set-goal-agenda-state! $row
             (goal-agenda-state-clear $kind $state))))
      ()))

(: claim-equal-score-goal-agenda-kind!
   (-[det]-> Number AgendaKind Number Number Number (List $none)))
(= (claim-equal-score-goal-agenda-kind!
      $gid $kind $generation $revision $score)
   (let $_claim
      (collapse
         (claim-equal-score-goal-agenda-kind-row!
            $gid $kind $generation $revision $score))
      ()))

(: claim-equal-score-goal-agenda-kind-row!
   (-[semidet]-> Number AgendaKind Number Number Number (List $none)))
(= (claim-equal-score-goal-agenda-kind-row!
      $gid $kind $generation $revision $score)
   (let*
      (($row (goal-by-id $gid))
       ((stored-goal-row
            $_stored-gid $_depth $_goal $_expanded $state)
          $row)
       ((goal-agenda-state
            $generation $_issued-revision $_issued-score
            $expand $refresh $resume $aggregate)
          $state)
       ($next-state
          (goal-agenda-state-clear $kind
             (goal-agenda-state
                $generation $revision $score
                $expand $refresh $resume $aggregate)))
       ($_set (set-goal-agenda-state! $row $next-state)))
      ()))

(: agenda-kind-runnable?
   (-[det]-> AgendaKind Number Number Bool))
(= (agenda-kind-runnable? $kind $gid $score)
   (case $kind (
      (agenda-expand
         (let $hits (collapse (once (goal-by-id $gid)))
            (case $hits (
               (() false)
               ((cons
                   (stored-goal-row
                      $_stored-gid $_depth $_goal $expanded $_state)
                   $_rest)
                  (if $expanded false (> $score 0.0)))))))
      (agenda-resume (> $score 0.0))
      (agenda-refresh true)
      (agenda-aggregate
         (if (== (collapse (once (aggregate-by-id $gid))) ())
            false
            true)))))

;; This is the sole entry validation and claim policy. Ownership is checked
;; before evaluating demand so stale entries cannot mutate the demand cache or
;; revision. An owned entry evaluates demand before comparing its token because
;; a cache miss may advance the revision. Claiming clears only its current lane.
(: claim-goal-agenda-entry!
   (-[det]-> AgendaEntry AgendaEntryDisposition))
(= (claim-goal-agenda-entry!
      (agenda-entry $kind $gid
         (agenda-revision-token $demand-revision $generation)))
   (let $entry
      (agenda-entry $kind $gid
         (agenda-revision-token $demand-revision $generation))
      (if (agenda-entry-owned? $entry)
         (let $score (agenda-kind-score $kind $gid)
            (if (== $demand-revision
                   (goal-demand-revision $gid))
               (let* (($_clear
                         (clear-owned-goal-agenda-kind!
                            $gid $kind $generation)))
                  (if (agenda-kind-runnable? $kind $gid $score)
                     agenda-claimed
                     agenda-cancelled))
               (if (== $score (goal-agenda-issued-score $gid))
                  (let $_claim
                     (claim-equal-score-goal-agenda-kind!
                        $gid $kind $generation
                        (goal-demand-revision $gid) $score)
                     (if (agenda-kind-runnable? $kind $gid $score)
                        agenda-claimed
                        agenda-cancelled))
                  (if (agenda-kind-runnable? $kind $gid $score)
                     agenda-retoken
                     (let $_clear
                        (clear-owned-goal-agenda-kind!
                           $gid $kind $generation)
                        agenda-cancelled)))))
         agenda-stale)))

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
               $expand $refresh $resume $aggregate)
             $state)
          ($next-state
             (goal-agenda-state
                $generation $current-revision $_score
                $expand $refresh $resume $aggregate))
          ($_set (set-goal-agenda-state! $row $next-state)))
      (enqueue-goal-agenda-kind-heap
         $agenda $gid $depth $goal $next-state $kind)))

(: release-pruned-agenda-entry! (-[det]-> AgendaEntry (List $none)))
(= (release-pruned-agenda-entry!
      (agenda-entry $kind $gid
         (agenda-revision-token $_demand-revision $generation)))
   (if (== $kind agenda-expand)
      (let $_clear
         (collapse
            (clear-owned-goal-agenda-kind!
               $gid agenda-expand $generation))
         ())
      ()))

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

;; FoldAllCompiled and GroupedFoldAllCompiled both carry the kb and pattern as
;; the first two args; the child goal is the compiled query for that pattern.
(: activate-compiled-query
   (-[nondet]-> CompiledQuery
       (| Goal (Statement KBContext Proof TV))))
(= (activate-compiled-query
      (compiled-query $child-goal $adds))
   (if (or (is-var $child-goal) (is-var $adds))
      (empty)
      (let $_
         (once
            (inject-compiled-adds $adds))
         (typed-runtime-premise $child-goal))))

(: aggregate-child-goal
   (-[nondet]-> Goal
       (| Goal (Statement KBContext Proof TV))))
(= (aggregate-child-goal (CPU $_fun $args $_goalres))
   (let*
      (($kb (car-atom $args))
       ($pattern (car-atom (cdr-atom $args)))
       ($raw-compiled-query
          (eval
             (mm2compileQuery
                $kb
                (: $prf $pattern $tvin))))
       ($compiled-query
          (the CompiledQuery $raw-compiled-query)))
      (activate-compiled-query $compiled-query)))

(: aggregate-step-group-value
   (-[semidet]-> Statement $group-template $child-atom $group))
(= (aggregate-step-group-value $pattern $group $child-atom)
   (let ($pattern ($_ckbid $_cctx $_cvars) $_cprf $_ctv) (copy_term $child-atom) $group))

(: aggregate-foldall-step-acc
   (-[semidet]-> (| ExtractValue ExtractInheritanceTV ExtractTV)
       (-[semidet]-> $accumulator Atom $accumulator)
       $accumulator $child-atom (| TV NoTV) $accumulator))
(= (aggregate-foldall-step-acc $extractor $fun $acc $child-atom $child-tv)
   (case $extractor (
      ((extract-value $pattern $value-template)
         (let ($pattern ($_ckbid $_cctx $_cvars) $_cprf $_ctv)
            (copy_term $child-atom)
            ($fun $acc $value-template)))
      ((extract-inheritance-tv $kbid $_pattern)
         (let ((Inheritance $subj $_concept)
                ($_ckbid $_cctx $_cvars) $_cprf $_ctv)
            (copy_term $child-atom)
            ($fun $acc
               (WeightedTv
                  (inheritance-subject-prior-tv
                     $kbid
                     (brand Statement $subj))
                  $child-tv))))
      (extract-tv
         ($fun $acc $child-tv)))))

(: distribution-sum-count-acc
   (-[det]-> $value DistributionSumCount))
(= (distribution-sum-count-acc $acc)
   (the DistributionSumCount $acc))
(: base-rate-evidence-acc
   (-[det]-> $value BaseRateEvidenceState))
(= (base-rate-evidence-acc $acc)
   (the BaseRateEvidenceState $acc))
(: base-rate-evidence-with-prior-acc
   (-[det]-> $value BaseRateEvidenceWithPriorState))
(= (base-rate-evidence-with-prior-acc $acc)
   (the BaseRateEvidenceWithPriorState $acc))
(: list-aggregate-acc
   (-[det]-> $value (List Atom)))
(= (list-aggregate-acc $acc)
   (the (List Atom) $acc))
(: available-universe-size
   (-[det]-> (| Number UniverseSizeUnavailable) Number))
(= (available-universe-size $size)
   (the Number $size))

;; Aggregate CPU arguments are stored as an open, user-extensible wire format:
;; the finish token determines both the accumulator and result types.  Keep the
;; dispatcher itself dynamic and validate only at the selected typed boundary.
(: finish-aggregate
   (-[semidet]-> Expression Expression Atom))

(= (finish-aggregate $finish $acc)
   (case $finish (
      (identity $acc)
      (dist-average
         (the Distribution
            (once
               (reduce
                  (reduce
                     (DistAverageFromSumCount
                        (distribution-sum-count-acc $acc)))))))
      (base-rate
         (BaseRateTv (base-rate-evidence-acc $acc)))
      (weighted-base-rate
         (WeightedBaseRateTv (base-rate-evidence-acc $acc)))
      (weighted-base-rate-with-prior
         (WeightedBaseRateWithPriorTv
            (base-rate-evidence-with-prior-acc $acc)))
      ((member-inheritance $kbid)
         (member-inheritance-tv $kbid
            (base-rate-evidence-acc $acc)))
      ((weighted-base-rate-in-universe $kbid)
         (let $ev (base-rate-evidence-acc $acc)
            (let $universe-size
               (kb-universe-size $kbid)
               (if (== $universe-size no-universe-size)
                  (WeightedBaseRateTv $ev)
                  (WeightedUniverseBaseRateTv
                     (available-universe-size $universe-size) $ev)))))
      ((weighted-base-rate-with-prior-in-universe $kbid)
         (let (BaseRateEvidenceWithPrior $prior $ev)
            (base-rate-evidence-with-prior-acc $acc)
            (let $universe-size
               (kb-universe-size $kbid)
               (BaseRateWithPriorFormula
                  (resolve-base-rate-prior $prior)
                  (if (== $universe-size no-universe-size)
                     (WeightedBaseRateTv $ev)
                     (WeightedUniverseBaseRateTv
                        (available-universe-size $universe-size) $ev))))))
      (uniform-prior
         (UniformPriorTv (list-aggregate-acc $acc)))
      (uniform-prior-known
         (UniformPriorKnownTv (list-aggregate-acc $acc))))))

;; --- Frontier pooling of same-source projections -----------------------------
;; A conjunction frontier rejects a premise proof whose fact evidence overlaps
;; evidence already consumed (AndFormula would double count it). When the
;; overlapping proofs are marginal projections of the *same* stored or derived
;; (And ...) source, the sharing is exactly accountable: the group of premises
;; is one joint projection of that source. Such premises are pooled into a
;; single part whose TV is the marginal projection while the pool is partial
;; and the source's own TV once every conjunct of the source is in the pool.
;; Parts are folded with AndFormula across parts only, so frontiers whose parts
;; are all independent reproduce the unpooled TVs exactly; pooling only adds
;; results that were previously dropped. Overlap that is not fully explained by
;; a same-source pool keeps today's rejection.

;; Parts, one per consumed premise, in premise order:
;;   (indep-part $tv)                                -- ordinary premise
;;   (pool-part $base $base-tv $arity $idxs $ev $marginal-tv)
;;                                                   -- projections of one source
;;   skip-part                                       -- AndFormula chain steps
;;   unpoolable-part                                 -- unclassifiable premise;
;;                                                      poisons folds so joins
;;                                                      fall back to rejection
(: FrontierPart Type)
(: indep-part (-[det]-> TV FrontierPart))
(: pool-part
   (-[det]-> ProofOutputKey TV Number (List Number)
       (List Evidence) TV FrontierPart))
(: SkipPart Type)
(: skip-part SkipPart)
(: UnpoolablePart Type)
(: unpoolable-part UnpoolablePart)
(: NoPool Type)
(: no-pool NoPool)
(: NoPoolKey Type)
(: no-pool-key NoPoolKey)
(: FrontierWaiter Type)
(: FrontierValueSpec Type)
(: frontier-value-spec
   (-[det]-> Number Number Number FrontierValueSpec))
(: frontier-waiter
   (-[det]-> Number AndBundle Number (List Evidence)
       (List (| FrontierPart UnpoolablePart)) Number
       FrontierValueSpec FrontierWaiter))
(: AggregateWaiter Type)
(: AggregateDemandSpec Type)
(: live-aggregate-demand AggregateDemandSpec)
(: cached-aggregate-demand (-[det]-> TV AggregateDemandSpec))
(: aggregate-waiter
   (-[det]-> Number AggregateDemandSpec AggregateWaiter))
(: RootDemand Type)
(: root-demand (-[det]-> Number Number RootDemand))
(: GoalDemandDependency Type)
(: goal-demand-dependency
   (-[det]-> Number Number GoalDemandDependency))
(: GoalDemandCacheRow Type)
(: goal-demand-cache-row
   (-[det]-> Number (List GoalDemandDependency)
       (List RootDemand) GoalDemandCacheRow))
(: GoalDemandRevisionRow Type)
(: goal-demand-revision-row
   (-[det]-> Number Number GoalDemandRevisionRow))
(: GoalDemandCacheValue Type)
(: goal-demand-cache-value
   (-[det]-> (List GoalDemandDependency)
       (List RootDemand) GoalDemandCacheValue))

;; A shared goal carries one contribution per distinct query root. Alternative
;; waiters from the same root merge by maximum; independent roots add only when
;; the final scalar queue priority is requested.
(: root-demand-put-max
   (-[det]-> RootDemand (List RootDemand) (List RootDemand)))
(= (root-demand-put-max $entry ()) (cons $entry ()))
(= (root-demand-put-max
      (root-demand $root $score)
      (cons (root-demand $head-root $head-score) $rest))
   (if (== $root $head-root)
      (cons (root-demand $root (max $score $head-score)) $rest)
      (cons (root-demand $head-root $head-score)
         (root-demand-put-max (root-demand $root $score) $rest))))

(: root-demands-merge-max
   (-[det]-> (List RootDemand) (List RootDemand) (List RootDemand)))
(= (root-demands-merge-max $acc ()) $acc)
(= (root-demands-merge-max $acc (cons $entry $rest))
   (root-demands-merge-max
      (root-demand-put-max $entry $acc) $rest))

(: root-demands-sum (-[det]-> (List RootDemand) Number))
(= (root-demands-sum ()) 0.0)
(= (root-demands-sum (cons (root-demand $_root $score) $rest))
   (+ $score (root-demands-sum $rest)))

(: root-demands-max (-[det]-> (List RootDemand) Number))
(= (root-demands-max ()) 0.0)
(= (root-demands-max (cons (root-demand $_root $score) $rest))
   (max $score (root-demands-max $rest)))

(: root-demand-entry-member?
   (-[det]-> RootDemand (List RootDemand) Bool))
(= (root-demand-entry-member? $_entry ()) false)
(= (root-demand-entry-member?
      (root-demand $root $score)
      (cons (root-demand $head-root $head-score) $rest))
   (if (== $root $head-root)
      (== $score $head-score)
      (root-demand-entry-member?
         (root-demand $root $score) $rest)))

(: root-demands-same?
   (-[det]-> (List RootDemand) (List RootDemand) Bool))
(= (root-demands-same? () $right) (== $right ()))
(= (root-demands-same? (cons $entry $rest) $right)
   (if (root-demand-entry-member? $entry $right)
      (root-demands-same? $rest $right)
      false))

(: root-goal-demand-seed (-[det]-> Number (List RootDemand)))
(= (root-goal-demand-seed $gid)
   (let $hits
      (collapse (match &root_goal (root-goal $gid) true))
      (if (== $hits ()) ()
         (cons (root-demand $gid 1.0) ()))))

(: frontier-root-demand-step
   (-[det]-> (| Number NoCurrentScore) Number Number Number Number
       RootDemand RootDemand))
(= (frontier-root-demand-step
      $current $candidate $premise-count $success-prior $score-cap
      (root-demand $root $root-bound))
   (root-demand $root
      (min $score-cap
         (root-proof-value-score
            $root-bound $current $candidate
            $premise-count $success-prior))))

(: frontier-root-demands-map
   (-[det]-> (| Number NoCurrentScore) Number Number Number Number
       (List RootDemand) (List RootDemand)))
(= (frontier-root-demands-map
      $_current $_candidate $_premise-count $_success-prior $_score-cap
      ())
   ())
(= (frontier-root-demands-map
      $current $candidate $premise-count $success-prior $score-cap
      (cons $entry $rest))
   (cons
      (frontier-root-demand-step
         $current $candidate $premise-count $success-prior $score-cap
         $entry)
      (frontier-root-demands-map
         $current $candidate $premise-count $success-prior $score-cap
         $rest)))

(: aggregate-root-demands-map
   (-[det]-> AggregateDemandSpec (List RootDemand) (List RootDemand)))
(= (aggregate-root-demands-map live-aggregate-demand $demands) $demands)
(= (aggregate-root-demands-map (cached-aggregate-demand $tv) ()) ())
(= (aggregate-root-demands-map
      (cached-aggregate-demand $tv)
      (cons (root-demand $root $score) $rest))
   (cons
      (root-demand $root
         (cached-base-rate-refinement-score $score $tv))
      (aggregate-root-demands-map
         (cached-aggregate-demand $tv) $rest)))

(: goal-root-demands-walk
   (-[det]-> Number (List RootDemand)))
(: goal-confidence-or-none
   (-[det]-> Number (| Number NoCurrentScore)))
(= (goal-confidence-or-none $gid)
   (let $hits (collapse (once (goal-current-confidence $gid)))
      (case $hits (
         (() no-current)
         ((cons $value $_rest)
            (the (| Number NoCurrentScore) $value))))))

(: waiter-root-demands
   (-[det]-> (| FrontierWaiter AggregateWaiter Atom)
       Number (List RootDemand)))
(= (waiter-root-demands $waiter $child-depth)
   (case $waiter (
      ((frontier-waiter $parent-gid $_bundle $score-cap
          $_seen $_parts $path-id
          (frontier-value-spec $candidate $premise-count $success-prior))
         (let $parent-hits
            (collapse
               (once (goal-by-id (the Number $parent-gid))))
            (case $parent-hits (
               (() ())
               ((cons
                   (stored-goal-row
                      $_gid $parent-depth $_goal $_expanded $_pending)
                   $_rest)
                  (if (< $parent-depth $child-depth)
                     (if
                        (frontier-path-live?
                           (the Number $path-id))
                        (frontier-root-demands-map
                           (goal-confidence-or-none
                              (the Number $parent-gid))
                           (the Number $candidate)
                           (the Number $premise-count)
                           (the Number $success-prior)
                           (the Number $score-cap)
                           (goal-root-demands
                              (the Number $parent-gid)))
                        ())
                     ()))))))
      ((aggregate-waiter $agg-gid $spec)
         (let $parent-hits
            (collapse
               (once (goal-by-id (the Number $agg-gid))))
            (case $parent-hits (
               (() ())
               ((cons
                   (stored-goal-row
                      $_gid $parent-depth $_goal $_expanded $_pending)
                   $_rest)
                  (if (< $parent-depth $child-depth)
                     (aggregate-root-demands-map
                        (the AggregateDemandSpec $spec)
                        (goal-root-demands
                           (the Number $agg-gid)))
                     ()))))))
      ($_other ()))))

(: waiters-root-demands
   (-[det]-> (List (| FrontierWaiter AggregateWaiter Atom))
       Number (List RootDemand)
       (List RootDemand)))
(= (waiters-root-demands () $_child-depth $acc) $acc)
(= (waiters-root-demands (cons $waiter $rest) $child-depth $acc)
   (waiters-root-demands $rest $child-depth
      (root-demands-merge-max $acc
         (waiter-root-demands
            (the (| FrontierWaiter AggregateWaiter Atom) $waiter)
            $child-depth))))

(= (goal-root-demands-walk $gid)
   (let $goal-hits (collapse (once (goal-by-id $gid)))
      (case $goal-hits (
         (() ())
         ((cons
             (stored-goal-row
                $_stored-gid $depth $_goal $_expanded $_pending)
             $_rest)
            (let $waiters
               (stored-atom-list
                  (collapse
                     (match &goal_waiter
                        ($gid $waiter) $waiter)))
               (waiters-root-demands
                  (the
                     (List (| FrontierWaiter AggregateWaiter Atom))
                     $waiters)
                  $depth
                  (root-goal-demand-seed $gid))))))))

(: goal-demand-revision (-[det]-> Number Number))
(= (goal-demand-revision $gid)
   (let $hits
      (stored-atom-list
         (collapse
            (once
               (match &goal_demand_revision
                  (goal-demand-revision-row $gid $revision)
                  $revision))))
      (if (== $hits ()) 0 (first-number $hits))))

(: bump-goal-demand-revision! (-[det]-> Number Number))
(= (bump-goal-demand-revision! $gid)
   (let* (($revision (goal-demand-revision $gid))
          ($next (+ $revision 1))
          ($_metric
             (increment-backward-query-metric! demand-revision-bumps))
          ($_old
             (collapse
                (match &goal_demand_revision
                   (goal-demand-revision-row $gid $_old-revision)
                   (remove-atom &goal_demand_revision
                      (goal-demand-revision-row
                         $gid $_old-revision)))))
          ($_new
             (once
                (add-atom &goal_demand_revision
                   (goal-demand-revision-row $gid $next)))))
      $next))

(: shallower-goal-demand-parents
   (-[det]-> (List Number) Number (List Number)))
(= (shallower-goal-demand-parents () $_child-depth) ())
(= (shallower-goal-demand-parents
      (cons $parent-gid $rest) $child-depth)
   (let $hits (collapse (once (goal-by-id $parent-gid)))
      (case $hits (
         (() (shallower-goal-demand-parents $rest $child-depth))
         ((cons
             (stored-goal-row
                $_gid $parent-depth $_goal $_expanded $_pending)
             $_tail)
            (if (< $parent-depth $child-depth)
               (cons $parent-gid
                  (shallower-goal-demand-parents
                     $rest $child-depth))
               (shallower-goal-demand-parents
                  $rest $child-depth)))))))

(: goal-demand-parent-gids (-[det]-> Number (List Number)))
(= (goal-demand-parent-gids $gid)
   (let $hits (collapse (once (goal-by-id $gid)))
      (case $hits (
         (() ())
         ((cons
             (stored-goal-row
                $_stored-gid $depth $_goal $_expanded $_pending)
             $_rest)
            (let $parents
               (list_to_set
                  (the (List Number)
                     (collapse
                        (match &goal_child
                           ($parent-gid $gid) $parent-gid))))
               (shallower-goal-demand-parents
                  $parents $depth)))))))

(: goal-demand-dependencies
   (-[det]-> (List Number) (List GoalDemandDependency)))
(= (goal-demand-dependencies ()) ())
(= (goal-demand-dependencies (cons $parent-gid $rest))
   (let $revision (goal-demand-revision $parent-gid)
      (cons (goal-demand-dependency $parent-gid $revision)
         (goal-demand-dependencies $rest))))

(: goal-demand-dependencies-current?
   (-[det]-> (List GoalDemandDependency) Bool))
(= (goal-demand-dependencies-current? ()) true)
(= (goal-demand-dependencies-current?
      (cons
         (goal-demand-dependency $parent-gid $revision)
         $rest))
   (if (== (goal-demand-revision $parent-gid) $revision)
      (goal-demand-dependencies-current? $rest)
      false))

(: goal-demand-cache-hit-current?
   (-[det]-> (List GoalDemandCacheValue) Bool))
(= (goal-demand-cache-hit-current? ()) false)
(= (goal-demand-cache-hit-current?
      (cons
         (goal-demand-cache-value $dependencies $_demands)
         $_rest))
   (goal-demand-dependencies-current? $dependencies))

(: goal-demand-cache-value-demands
   (-[det]-> GoalDemandCacheValue (List RootDemand)))
(= (goal-demand-cache-value-demands
      (goal-demand-cache-value $_dependencies $demands))
   $demands)

(: goal-root-demands (-[det]-> Number (List RootDemand)))
(= (goal-root-demands $gid)
   (let* (($_evaluation
             (increment-backward-query-metric! goal-demand-evaluations))
          ($hits
      (stored-atom-list
         (collapse
            (once
               (match &goal_demand_cache
                  (goal-demand-cache-row $gid $dependencies $demands)
                  (goal-demand-cache-value
                     $dependencies $demands)))))))
      (if (goal-demand-cache-hit-current?
            (the (List GoalDemandCacheValue) $hits))
         (let $_hit
            (increment-backward-query-metric! goal-demand-cache-hits)
            (goal-demand-cache-value-demands
               (the GoalDemandCacheValue (car-atom $hits))))
         (let* (($_miss
                   (increment-backward-query-metric!
                      goal-demand-cache-misses))
                ($demands (goal-root-demands-walk $gid))
                ($dependencies
                   (goal-demand-dependencies
                      (goal-demand-parent-gids $gid)))
                ($_old
                   (collapse
                      (match &goal_demand_cache
                         (goal-demand-cache-row
                            $gid $_old-dependencies $_old-demands)
                         (remove-atom &goal_demand_cache
                            (goal-demand-cache-row
                               $gid $_old-dependencies
                               $_old-demands)))))
                ($_store
                   (once
                      (add-atom &goal_demand_cache
                         (goal-demand-cache-row
                            $gid $dependencies $demands))))
                ($_revision (bump-goal-demand-revision! $gid)))
            $demands))))

(: goal-demand-sum (-[det]-> Number Number))
(= (goal-demand-sum $gid)
   (root-demands-sum (goal-root-demands $gid)))

(: mark-goal-demand-dirty! (-[det]-> Number (List $none)))
(= (mark-goal-demand-dirty! $gid)
   (let $_
      (collapse
         (match &goal_demand_cache
            (goal-demand-cache-row $gid $dependencies $demands)
            (remove-atom &goal_demand_cache
               (goal-demand-cache-row
                  $gid $dependencies $demands))))
      ()))

(: goal-demand-dependency-put
   (-[det]-> GoalDemandDependency (List GoalDemandDependency)
       (List GoalDemandDependency)))
(= (goal-demand-dependency-put $entry ()) (cons $entry ()))
(= (goal-demand-dependency-put
      (goal-demand-dependency $parent-gid $revision)
      (cons
         (goal-demand-dependency $head-gid $head-revision)
         $rest))
   (if (== $parent-gid $head-gid)
      (cons (goal-demand-dependency $parent-gid $revision) $rest)
      (cons (goal-demand-dependency $head-gid $head-revision)
         (goal-demand-dependency-put
            (goal-demand-dependency $parent-gid $revision)
            $rest))))

(: update-goal-demand-cache-for-waiter!
   (-[semidet]-> Number Number (List RootDemand)
       (| FrontierWaiter AggregateWaiter Atom) (List $none)))
(= (update-goal-demand-cache-for-waiter!
      $child-gid $parent-gid $current-demands $waiter)
   (let*
      (((stored-goal-row
            $_gid $child-depth $_goal $_expanded $_pending)
          (goal-by-id $child-gid))
       ($hits
          (stored-atom-list
             (collapse
                (once
                   (match &goal_demand_cache
                      (goal-demand-cache-row
                         $child-gid $dependencies $_demands)
                      $dependencies)))))
       ($dependencies
          (the (List GoalDemandDependency)
             (chainer-first-or ()
                (the (List (List GoalDemandDependency)) $hits))))
       ($next-demands
          (root-demands-merge-max $current-demands
             (waiter-root-demands $waiter $child-depth)))
       ($next-dependencies
          (goal-demand-dependency-put
             (goal-demand-dependency $parent-gid
                (goal-demand-revision $parent-gid))
             $dependencies))
       ($_old
          (mark-goal-demand-dirty! $child-gid))
       ($_store
          (once
             (add-atom &goal_demand_cache
                (goal-demand-cache-row
                   $child-gid $next-dependencies $next-demands))))
       ($_revision
          (if (root-demands-same? $current-demands $next-demands)
             0
             (bump-goal-demand-revision! $child-gid)))
       ;; Only an empty-to-live transition can strand descendants that were
       ;; expanded while this goal was reachable solely through a cycle.  Mark
       ;; that rare transition for a transitive wake; ordinary waiter updates
       ;; retain the constant-time direct wake below.
       ($_wake
          (if (and (== $current-demands ())
                   (not (== $next-demands ())))
             (once (add-atom &goal_demand_wake ($child-gid)))
             ())))
      ()))

(: register-goal-waiter!
   (-[semidet]-> Number Number
       (| FrontierWaiter AggregateWaiter Atom) (List $none)))
(= (register-goal-waiter! $child-gid $parent-gid $waiter)
   (let* (($current-demands
              (goal-root-demands $child-gid))
           ($_wait
              (once
                 (chainer-add-atom &goal_waiter
                    ($child-gid $waiter))))
           ($_edge
              (once
                 (chainer-add-atom &goal_child
                    ($parent-gid $child-gid))))
           ($_update
              (update-goal-demand-cache-for-waiter!
                 $child-gid $parent-gid $current-demands $waiter)))
      ()))

(: goal-demand-child-gids (-[det]-> Number (List Number)))
(= (goal-demand-child-gids $gid)
   (list_to_set
      (the (List Number)
         (collapse
            (match &goal_child ($gid $child-gid) $child-gid)))))

(: wake-goal-demand-children-heap
   (-[semidet]-> (Heap AgendaEntry) (List Number)
       (List Number) (Heap AgendaEntry)))
(= (wake-goal-demand-children-heap $agenda () $_visited) $agenda)
(= (wake-goal-demand-children-heap
      $agenda (cons $child-gid $rest) $visited)
   (let $next
      (chainer-first-or $agenda
         (collapse
            (once
               (wake-goal-demand-walk-heap
                  $agenda $child-gid $visited))))
      (wake-goal-demand-children-heap $next $rest $visited)))

(: wake-goal-demand-walk-heap
   (-[semidet]-> (Heap AgendaEntry) Number
       (List Number) (Heap AgendaEntry)))
(= (wake-goal-demand-walk-heap $agenda $gid $visited)
   (if (stored-list-member? $gid $visited) $agenda
      (let* (((stored-goal-row
                   $_stored-gid $_depth $_goal $expanded $_pending)
                (goal-by-id $gid))
             ($next-visited (cons $gid $visited)))
         (if $expanded
            (wake-goal-demand-children-heap
               $agenda (goal-demand-child-gids $gid) $next-visited)
            (schedule-goal-heap $agenda $gid)))))

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
         (let $_clear
            (collapse
               (match &goal_demand_wake ($gid)
                  (remove-atom &goal_demand_wake ($gid))))
            (wake-goal-demand-walk-heap $agenda $gid ())))))
(: AggregateState Type)
(: aggregate-state
   (-[det]-> $accumulator (List Evidence) (List Number) AggregateState))
(: AggregateGroupState Type)
(: aggregate-group-state
   (-[det]-> $group $accumulator (List Evidence) (List Number) AggregateGroupState))

(: frontier-part-tv
   (-[semidet]-> (| FrontierPart UnpoolablePart) TV))
(= (frontier-part-tv $part)
   (case $part (
      ((indep-part $tv) $tv)
      ((pool-part $_base $btv $n $idxs $_ev $mtv)
         (if (== (list-len $idxs) $n) $btv $mtv))
      (unpoolable-part (empty)))))

(: frontier-parts-fold-acc
   (-[semidet]-> TV
       (List (| FrontierPart UnpoolablePart)) TV))
(= (frontier-parts-fold-acc $acc ()) $acc)
(= (frontier-parts-fold-acc $acc (cons $part $rest))
   (frontier-parts-fold-acc (AndFormula $acc (frontier-part-tv $part)) $rest))

(: frontier-parts-fold
   (-[semidet]->
       (List (| FrontierPart UnpoolablePart)) TV))
(= (frontier-parts-fold (cons $first $rest))
   (frontier-parts-fold-acc (frontier-part-tv $first) $rest))

(: frontier-premise-part
   (-[semidet]-> Number
       (| FrontierPart SkipPart UnpoolablePart)))
(= (frontier-premise-part $pid)
   (let (proof-support $_score $evidence $contribution)
      (proof-support-by-id $pid)
      (case $contribution (
         ((independent-contribution $tv)
            (indep-part $tv))
         ((projected-contribution $key $source-tv $arity $idx $marginal-tv)
            (pool-part $key $source-tv $arity
               ($idx) $evidence $marginal-tv))
         (skip-contribution skip-part)
         (unpoolable-contribution unpoolable-part)))))

(: frontier-parts-idx-union
   (-[det]-> (List Number) (List Number) (List Number)))
(= (frontier-parts-idx-union $a ()) $a)
(= (frontier-parts-idx-union $a (cons $i $rest))
   (frontier-parts-idx-union
      (if (stored-list-member? $i $a)
         $a
         (append-number $a $i))
      $rest))

(: frontier-pool-key
   (-[det]-> (| FrontierPart UnpoolablePart)
       (| ProofOutputKey NoPoolKey)))
(= (frontier-pool-key $part)
   (case $part (
      ((pool-part $key $_btv $_n $_idxs $_ev $_mtv) $key)
      ($_ no-pool-key))))

(: frontier-parts-same-pool
   (-[det]-> (List (| FrontierPart UnpoolablePart))
       ProofOutputKey (| FrontierPart NoPool)))
(= (frontier-parts-same-pool () $_key) no-pool)
(= (frontier-parts-same-pool (cons $head $rest) $key)
   (case $head (
      ((pool-part $head-key $btv $n $idxs $ev $mtv)
         (if (=alpha $head-key $key)
            (pool-part $head-key $btv $n $idxs $ev $mtv)
            (frontier-parts-same-pool $rest $key)))
      ($_other (frontier-parts-same-pool $rest $key)))))

(: frontier-parts-join-pool
   (-[semidet]-> (List (| FrontierPart UnpoolablePart))
       FrontierPart
       (List (| FrontierPart UnpoolablePart))))
(= (frontier-parts-join-pool () $pool) (cons $pool ()))
(= (frontier-parts-join-pool (cons $head $rest) (pool-part $key $btv $n $idxs $ev $mtv))
   (if (=alpha (frontier-pool-key $head) $key)
      (let (pool-part $okey $obtv $on $oidxs $oev $omtv) $head
         (cons
            (pool-part $okey $obtv $on
               (frontier-parts-idx-union $oidxs $idxs)
               (list_to_set (append-evidence $oev $ev))
               $omtv)
            $rest))
      (cons $head (frontier-parts-join-pool $rest (pool-part $key $btv $n $idxs $ev $mtv)))))

(: frontier-parts-add
   (-[semidet]-> (List (| FrontierPart UnpoolablePart))
       (| FrontierPart SkipPart UnpoolablePart)
       (List (| FrontierPart UnpoolablePart))))
(: frontier-parts-append-one
   (-[det]-> (List (| FrontierPart UnpoolablePart))
       (| FrontierPart UnpoolablePart)
       (List (| FrontierPart UnpoolablePart))))
(= (frontier-parts-append-one () $part)
   (cons $part ()))
(= (frontier-parts-append-one
      (cons $head $rest) $part)
   (cons $head
      (frontier-parts-append-one $rest $part)))
(= (frontier-parts-add $parts $part)
   (case $part (
      (skip-part $parts)
      ((pool-part $base $btv $n $idxs $ev $mtv)
         (frontier-parts-join-pool $parts (pool-part $base $btv $n $idxs $ev $mtv)))
      ((indep-part $tv)
         (frontier-parts-append-one
            $parts (indep-part $tv)))
      (unpoolable-part
         (frontier-parts-append-one
            $parts unpoolable-part)))))

;; Projections score with their source's confidence: a partial pool's marginal
;; confidence (0 for a strength-0 source) says nothing about the completed
;; pool's, and would starve the frontier before the join that completes it.
(: frontier-part-score
   (-[det]-> (| FrontierPart SkipPart UnpoolablePart) Number Number))
(= (frontier-part-score $part $pscore)
   (case $part (
      ((pool-part $_base $btv $_n $_idxs $_ev $_mtv) (max $pscore (tv-confidence $btv)))
      ($_ $pscore))))

;; A partial pool's marginal TV can have zero confidence (strength-0 source),
;; which zeroes the remaining chain's expected confidence and would starve the
;; frontier before the join that completes the pool. The pool's source
;; confidence is the frontier's real potential.
(: frontier-pool-potential
   (-[det]-> (List (| FrontierPart UnpoolablePart)) Number))
(= (frontier-pool-potential ()) 0.0)
(= (frontier-pool-potential (cons $part $rest))
   (case $part (
      ((pool-part $_k $btv $n $idxs $_ev $_mtv)
         (if (< (list-len $idxs) $n)
            (max (tv-confidence $btv) (frontier-pool-potential $rest))
            (frontier-pool-potential $rest)))
      ($_ (frontier-pool-potential $rest)))))

(: frontier-remaining-score
   (-[det]-> AndBundle (List (| FrontierPart UnpoolablePart)) Number))
(= (frontier-remaining-score $bundle $parts)
   (max
      (premises-expected-confidence
         (copy_term (and-bundle-premises $bundle)))
      (frontier-pool-potential $parts)))

(: frontier-and-step-premise? (-[det]-> $premise Bool))
(= (frontier-and-step-premise? $prem)
   (if (is-expr $prem)
      (if (== (car-atom $prem) CPU)
         (== (car-atom (cdr-atom $prem)) AndFormula)
         false)
      false))

;; Pop the consumed premise AND its AndFormula step, binding the step's output
;; to the parts fold (the chain's pairwise application would double count the
;; pooled source). Yields () when the premise is not directly followed by its
;; AndFormula step; the caller then drops the proof as before.
(: frontier-pooled-bundle
   (-[semidet]-> AndBundle Number TV
       (| AndBundle (List $none))))
(= (frontier-pooled-bundle $bundle $pid $folded)
   (let*
      (($goal (and-bundle-goal $bundle))
       ($premises (and-bundle-premises $bundle)))
      (case $premises (
         ((cons $prem (cons $step $rest))
            (if (frontier-and-step-premise? $step)
               (if (= $prem (proof-output-atom-by-id $pid))
                  (if (= (CPU AndFormula $_fargs $folded) $step)
                     (and-bundle $goal $rest)
                     ())
                  ())
               ()))
         ($_ ())))))

(: and-bundle-goal
   (-[det]-> AndBundle
       (| Goal (Statement KBContext Proof TV))))
(= (and-bundle-goal (and-bundle $goal $_premises)) $goal)
(: and-bundle-premises
   (-[det]-> AndBundle
       (List (| Goal (Statement KBContext Proof TV)))))
(= (and-bundle-premises (and-bundle $_goal $premises)) $premises)

(: advance-frontier-bundle
   (-[semidet]-> AndBundle Number
       (| AndBundle (List $none))))
(= (advance-frontier-bundle $bundle $pid)
   (let*
      (($goal (and-bundle-goal $bundle))
       ($premises (and-bundle-premises $bundle)))
      (case $premises (
           (() ())
           ((cons $prem $rest)
              (if (= $prem (proof-output-atom-by-id $pid))
                 (and-bundle $goal $rest) ()))))))

(: waiter-live? (-[semidet]-> FrontierWaiter Bool))
(= (waiter-live? (frontier-waiter $_parent-gid $_bundle $_score
      $_seen $_parts $path-id $_value-spec))
   (frontier-path-live? $path-id))

;; These compiler-generated joins keep their premise TVs separate instead of
;; combining them through AndFormula. Their premises may therefore share
;; evidence: total implication compares positive/refuting contexts, while a
;; member-inheritance sample pairs an antecedent membership with a consequent
;; that may itself have been derived from that antecedent. The resulting proof
;; still carries the union of both evidence sets, and normal cycle checks apply.
(: shared-evidence-frontier-proof? (-[det]-> $proof Bool))
(= (shared-evidence-frontier-proof? $proof)
   (case $proof (
      ((total-implication-frontier $_inner) true)
      ((inheritance-query-result $inner)
         (shared-evidence-frontier-proof? $inner))
      ((member-inheritance-sample $_antecedent $_consequent) true)
      ($_other false))))

(: frontier-allows-shared-evidence? (-[det]-> AndBundle Bool))
(= (frontier-allows-shared-evidence? $bundle)
   (let $goal (and-bundle-goal $bundle)
      (case $goal (
         (($_type $_kb $proof $_tv)
            (shared-evidence-frontier-proof? $proof))
         ($_other false)))))

(: frontier-needs-raw-proofs? (-[det]-> AndBundle Bool))
(= (frontier-needs-raw-proofs? $bundle)
   (let $goal (and-bundle-goal $bundle)
      (case $goal (
         (($_type $_kb $proof $_tv)
            (proof-term-conjunction-dependency?
               (brand Proof $proof)))
         ($_other false)))))

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
         ((($pscore $pev) (proof-stats-by-id $pid))
          ($proof-output (proof-output-atom-by-id $pid))
          ($frontier-pscore (frontier-proof-score $proof-output $pscore))
          ($part (frontier-premise-part $pid))
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

;; A premise proof joins the frontier's pool for its projection source when a
;; pool for that source already exists and any evidence overlap is fully
;; explained by it. The join applies with or without overlap: projections of
;; one source are never independent, and forward-chained materialization can
;; hide their shared provenance behind distinct fact atoms. Overlap not
;; explained by a pool keeps the double-counting rejection.
(: frontier-pool-join?
   (-[det]-> (| FrontierPart SkipPart UnpoolablePart) (List (| FrontierPart UnpoolablePart)) (List Evidence) (List Evidence) Bool))
(= (frontier-pool-join? $part $parts $seen $pev)
   (case $part (
      ((pool-part $key $_btv $_n $_idxs $_ev $_mtv)
         (let $existing (frontier-parts-same-pool $parts $key)
            (case $existing (
               (no-pool false)
               ((pool-part $_k $_btv2 $_n2 $_idxs2 $oev $_mtv2)
                  (evidence-subset?
                     (evidence-intersection
                        (fact-evidence-only $seen)
                        (fact-evidence-only $pev))
                     (fact-evidence-only $oev)))))))
      ($_ false))))

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

(: stored-atom-list
   (-[det]-> Expression (List Atom)))
(= (stored-atom-list ())
   ())
(= (stored-atom-list (cons $head $rest))
   (cons $head (stored-atom-list $rest)))

;; Select proof paths against the consumer's cycle key before equivalent outputs
;; are merged. A globally valid recursive proof must remain queryable, but it
;; cannot be allowed to poison an independent proof when the same proposition is
;; consumed by one of its own ancestors.
(: noncyclic-proof-source-step
   (-[semidet]-> Number (List (| ProofOutputKey ClosedGoalKey))
       (List Number) Number (List Number)))
(= (noncyclic-proof-source-step $consumer-gid $cycle-keys $acc $pid)
   (if (proof-depends-on-cycle-keys?
         $pid $consumer-gid $cycle-keys)
      $acc
      (cons $pid $acc)))

(: proof-depends-on-cycle-keys?
   (-[semidet]-> Number Number
       (List (| ProofOutputKey ClosedGoalKey)) Bool))
(= (proof-depends-on-cycle-keys? $_pid $_consumer-gid ()) false)
(= (proof-depends-on-cycle-keys?
      $pid $consumer-gid (cons $cycle-key $rest))
   (if (proof-depends-on-goal-seen?
         $pid $consumer-gid $cycle-key ())
      true
      (proof-depends-on-cycle-keys?
         $pid $consumer-gid $rest)))

(: noncyclic-proof-source-ids
   (-[semidet]-> Number (List (| ProofOutputKey ClosedGoalKey))
       Number (List Number)))
(= (noncyclic-proof-source-ids $consumer-gid $cycle-keys $source-gid)
   (reverse-number-list
      (proof-fold-flat-semidet
         (noncyclic-proof-source-step $consumer-gid $cycle-keys)
         ()
         (goal-live-proof-ids $source-gid))))

;; Compound goals are lowered into their child premises, so their proof DAG may
;; not contain a node for the compound itself. Include every recursively lowered
;; leaf in the consumer condition to retain the logical cycle boundary after
;; compilation.
(: compound-cycle-leaf-keys
   (-[det]-> Statement KBContext
       (List (| ProofOutputKey ClosedGoalKey))))
(= (compound-cycle-leaf-keys $type $kb)
   (if (compound-source? $type)
      (compound-cycle-leaf-list-keys
         (the (List Atom) (cdr-atom $type)) $kb)
      (cons
         (proof-output-key (quote ($type $kb))) ())))

(: compound-cycle-leaf-list-keys
   (-[det]-> (List Atom) KBContext
       (List (| ProofOutputKey ClosedGoalKey))))
(= (compound-cycle-leaf-list-keys () $_kb) ())
(= (compound-cycle-leaf-list-keys (cons $type $rest) $kb)
   (append-cycle-keys
      (compound-cycle-leaf-keys
         (brand Statement $type) $kb)
      (compound-cycle-leaf-list-keys $rest $kb)))

(: append-cycle-keys
   (-[det]-> (List (| ProofOutputKey ClosedGoalKey))
       (List (| ProofOutputKey ClosedGoalKey))
       (List (| ProofOutputKey ClosedGoalKey))))
(= (append-cycle-keys () $right) $right)
(= (append-cycle-keys (cons $key $rest) $right)
   (cons $key (append-cycle-keys $rest $right)))

(: frontier-cycle-keys
   (-[semidet]-> Number AndBundle
       (List (| ProofOutputKey ClosedGoalKey))))
(= (frontier-cycle-keys $parent-gid $bundle)
   (let*
      (($goal (and-bundle-goal $bundle))
       ($root-key
          (candidate-cycle-key $parent-gid (rule $goal))))
      (case $goal (
         (($type $kb $proof $_tv)
            (the (List (| ProofOutputKey ClosedGoalKey))
               (cons $root-key
                  (if
                     (if (compound-source? (brand Statement $type))
                        (compound-reconstruction-proof?
                           (brand Proof $proof))
                        false)
                     (compound-cycle-leaf-keys
                        (brand Statement $type)
                        (brand KBContext $kb))
                     ()))))
         ($_other
            (the (List (| ProofOutputKey ClosedGoalKey))
               (cons $root-key ())))))))

(: proof-nested-head? (-[det]-> Proof Atom Bool))
(= (proof-nested-head? $proof $expected)
   (if (is-expr $proof)
      (let $outer-head (car-atom $proof)
         (if (is-expr $outer-head)
            (let $head (car-atom $outer-head)
               (if (is-var $head) false
                  (== $head $expected)))
            false))
      false))

(: bi-direction-proof-label? (-[det]-> Atom Bool))
(= (bi-direction-proof-label? $label)
   (if (is-expr $label)
      (let $head (car-atom $label)
         (if (is-var $head) false
            (if (== $head bi-forward) true
               (== $head bi-backward))))
      false))

(: bi-direction-proof? (-[det]-> Proof Bool))
(= (bi-direction-proof? $proof)
   (if (is-expr $proof)
      (let $head (car-atom $proof)
         (if (is-var $head) false
            (if (== $head by)
               (case (cdr-atom $proof) (
                  ((cons $label (cons $_source ()))
                     (bi-direction-proof-label? $label))
                  ($_other false)))
               false)))
      false))

(: compound-reconstruction-proof? (-[det]-> Proof Bool))
(= (compound-reconstruction-proof? $proof)
   (if (bi-direction-proof? $proof) true
      (proof-nested-head? $proof inverted)))

(: frontier-needs-conditioned-proofs? (-[det]-> AndBundle Bool))
(= (frontier-needs-conditioned-proofs? $bundle)
   (let $goal (and-bundle-goal $bundle)
      (case $goal (
         (($type $_kb $proof $_tv)
            (if (is-var $proof)
               false
               (if (proof-nested-head?
                     (brand Proof $proof) proj)
                  true
                  (if (compound-source? (brand Statement $type))
                     (compound-reconstruction-proof?
                        (brand Proof $proof))
                     false))))
         ($_other false)))))

(: frontier-compatible-source-ids
   (-[semidet]-> Number AndBundle Number (List Number)))
(= (frontier-compatible-source-ids $parent-gid $bundle $child-gid)
   (noncyclic-proof-source-ids
      $parent-gid
      (frontier-cycle-keys $parent-gid $bundle)
      $child-gid))

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
             (store-proof-candidate $agg-gid
                (aggregate-result-candidate $result $ev $children))))
       ($_set (set-aggregate-current-pid! $row $pid))
       ($_deactivate
          (deactivate-current-proofs! $current-pid))
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

(: frontier-existing-proof-ids
   (-[semidet]-> Number AndBundle Number (List Number)))
(= (frontier-existing-proof-ids $parent-gid $bundle $gid)
   (if (frontier-needs-conditioned-proofs? $bundle)
      (let*
         (($compatible
             (frontier-compatible-source-ids
                $parent-gid $bundle $gid))
          ($representatives
             (proof-output-group-representative-pids $gid
                (proof-output-groups $compatible))))
         (if (frontier-needs-raw-proofs? $bundle)
            (list_to_set
               (append-numbers $compatible $representatives))
            $representatives))
      (if (frontier-needs-raw-proofs? $bundle)
         (list_to_set
            (append-numbers
               (goal-live-proof-ids $gid)
               (goal-merged-proof-ids $gid)))
         (goal-merged-proof-ids $gid))))

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

(: base-rate-finish? (-[det]-> $finish Bool))
(= (base-rate-finish? $finish)
   (case $finish (
      (base-rate true)
      (weighted-base-rate true)
      (weighted-base-rate-with-prior true)
      ((weighted-base-rate-in-universe $_kbid) true)
      ((weighted-base-rate-with-prior-in-universe $_kbid) true)
      ((member-inheritance $_kbid) true)
      ($_other false))))

(: BaseRateAggregateKey Type)
(: base-rate-aggregate-key-value
   (-[det]-> KB Statement $mode BaseRateAggregateKey))
(: NoBaseRateAggregateKey Type)
(: no-base-rate-aggregate-key NoBaseRateAggregateKey)

(: base-rate-aggregate-key
   (-[det]-> $arguments
       (| BaseRateAggregateKey NoBaseRateAggregateKey)))
(= (base-rate-aggregate-key $args)
   (case $args (
      (($kbid $pattern $_extractor $_init $_fun $finish $_tv-mode)
         (if (base-rate-finish? $finish)
            (base-rate-aggregate-key-value
               (brand KB $kbid)
               (brand Statement $pattern)
               $finish)
            no-base-rate-aggregate-key))
      ($_other no-base-rate-aggregate-key))))

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
