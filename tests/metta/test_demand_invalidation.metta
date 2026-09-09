!(import! &self ../../pettachainer/metta/petta_chainer)

(: demand-test-fact
   (-[det]-> Statement Atom $tv (Statement KBContext Proof TV)))
(= (demand-test-fact $statement $proof $tv)
   (assemble-runtime-fact
      $statement (brand KBContext (demandTest MAIN Nil))
      (brand Proof $proof) (the TV $tv)))

(: demand-test-goal (-[semidet]-> Statement Number Number))
(= (demand-test-goal $statement $depth)
   (ensure-goal-at-depth
      (demand-test-fact $statement $proof $tv) $depth))

!(set-backward-query-metrics true)

;; Publication invalidation is independent of the delivery-depth guard. The
;; parent's new 0.8-confidence proof lowers its child's priority from 1 to 0.2
;; even while callbacks are suppressed. A real frontier waiter on the parent
;; would derive the root if delivery ran; it must remain untouched here.
!(test
   (let*
      (($_clear (clear-backward-query-state!))
       ($root (demand-test-goal (PublicationRoot) 0))
       ($parent (demand-test-goal (PublicationParent) 1))
       ($child (demand-test-goal (PublicationChild) 2))
       ($_root (once (add-atom &root_goal (root-goal $root))))
       ($_parent
          (register-goal-waiter! $parent $root
             (frontier-waiter $root
                (and-bundle
                   (demand-test-fact (PublicationRoot) callback-result (STV 1.0 0.8))
                   ((demand-test-fact (PublicationParent) $parent-proof $parent-tv)))
                1.0 () () 0 (frontier-value-spec 1.0 1))))
       ($waiter
          (frontier-waiter $parent
             (and-bundle
                (demand-test-fact (PublicationParent) result $tv)
                ((demand-test-fact (PublicationChild) input $input-tv)))
             1.0 () () 0 (frontier-value-spec 1.0 1)))
       ($_child (register-goal-waiter! $child $parent $waiter))
       ($before (goal-demand-sum $child))
       ($_active (once (add-atom &search_wake_active ($parent 2))))
       ($_metrics (begin-backward-query-metrics!))
       ($agenda
          (commit-proof-candidate-heap (empty_heap) $parent
             (leaf-result-candidate
                (demand-test-fact (PublicationParent) observed (STV 1.0 0.8))
                ((rule-ev demandTest observed)))))
       ($after (goal-demand-sum $child))
       ($current-contribution
          (root-demands-sum (waiter-root-demands (waiter-demand-view $waiter) 2)))
       ($root-untouched (== (goal-live-proof-ids $root) ()))
       ($parent-published (== (length (goal-merged-proof-ids $parent)) 1))
       ($_done (remove-atom &search_wake_active ($parent 2))))
      ((== $before 1.0)
       (< (abs-math (- $after 0.2)) 0.000000000001)
       (< (abs-math (- $after $current-contribution)) 0.000000000001)
       $root-untouched $parent-published
       (query_metric_value proofs-stored)
       (query_metric_value agenda-pushes)
       (heap_size $agenda)))
   (true true true true true 1 0 0))

;; Controlled lower-confidence refinement, not public ingestion: manually
;; stage G <- X,C and H <- X,G, then replace one X candidate with the same
;; evidence at lower confidence. The old consumed path dies, but C is still
;; pending, so neither G nor H publishes. Registering H's replacement waiter
;; leaves G's demand unchanged; its revision must still invalidate C's stale
;; path-dependent priority and cause the pending token to be retokened.
!(test
   (let*
      (($_clear (clear-backward-query-state!))
       ($g
          (ensure-goal-at-depth
             (demand-test-fact (PathG $value) $gp $gtv) 0))
       ($h
          (ensure-goal-at-depth
             (demand-test-fact (PathH $value) $hp $htv) 0))
       ($x (demand-test-goal (PathX) 1))
       ($_root-g (once (add-atom &root_goal (root-goal $g))))
       ($_root-h (once (add-atom &root_goal (root-goal $h))))
       ($g-expanded (expand-goal-heap (empty_heap) 20 1.0 $g))
       ($h-expanded (expand-goal-heap $g-expanded 20 1.0 $h))
       ($old-raw
          (store-proof-candidate $x
             (leaf-result-candidate
                (demand-test-fact (PathX) x-changing (STV 1.0 0.9))
                (cons (rule-ev demandTest x-changing) ()))))
       ($_other
          (store-proof-candidate $x
             (leaf-result-candidate
                (demand-test-fact (PathX) x-fixed (STV 1.0 0.01))
                (cons (rule-ev demandTest x-fixed) ()))))
       ($old-merged (car-atom (goal-merged-proof-ids $x)))
       ($g-frontier
          (spawn-frontier-heap $h-expanded $g
             (and-bundle
                (demand-test-fact (PathG $value) g-proof $gtv)
                ((demand-test-fact (PathX) $xgp $xgtv)
                 (demand-test-fact (PathC $value) $cp $ctv)))
             1.0 () () 0 (frontier-value-spec 1.0 2)))
       ($h-frontier
          (spawn-frontier-heap $g-frontier $h
             (and-bundle
                (demand-test-fact (PathH $value) h-proof $htv)
                ((demand-test-fact (PathX) $xhp $xhtv)
                 (demand-test-fact (PathG $value) $hgp $hgtv)))
             1.0 () () 0 (frontier-value-spec 1.0 2)))
       ($c
          (ensure-goal-at-depth
             (demand-test-fact (PathC $value) $cp $ctv) 1))
       ($old-path (ensure-frontier-path 0 0 $old-merged))
       ($g-before (goal-root-demands $g))
       ($c-before (goal-demand-sum $c))
       ($g-revision-before (goal-demand-revision $g))
       ($_drop (supersede-current-proof! $old-raw))
       ($_replacement
          (store-proof-candidate $x
             (leaf-result-candidate
                (demand-test-fact (PathX) x-changing (STV 1.0 0.01))
                (cons (rule-ev demandTest x-changing) ()))))
       ($new-merged (car-atom (goal-merged-proof-ids $x)))
       ($_delivered (wake-proof-commit-heap $new-merged $h-frontier $x))
       ($g-after (goal-root-demands $g))
       ((stored-goal-row $_gid $_depth $_goal $_expanded
             (goal-agenda-state $generation $revision $_score $pending))
          (goal-by-id $c))
       ($claim
          (claim-goal-agenda-entry!
             (agenda-entry agenda-expand $c
                (agenda-revision-token $revision $generation))))
       ($c-cached (goal-demand-sum $c))
       ($_force-recompute (mark-goal-demand-dirty! $c))
       ($c-fresh (goal-demand-sum $c)))
      ((== $g-before $g-after)
       (not (frontier-path-live? $old-path))
       (> (goal-demand-revision $g) $g-revision-before)
       $pending $claim
       (> $c-before $c-cached)
       (== $c-cached $c-fresh)
       (length (goal-live-proof-ids $g))
       (length (goal-live-proof-ids $h))))
   (true true true true agenda-retoken true true 0 0))

;; Keyed invalidation succeeds without a row, clears every duplicate for its
;; goal, and leaves other goals untouched. Revision bumps retain their exact
;; count even when several obsolete revision rows must be removed.
!(test
   (let*
      (($_clear (clear-backward-query-state!))
       ($gid (demand-test-goal (ClearGoal) 0))
       ($other (demand-test-goal (ClearOther) 0))
       ($absent-confidence (clear-current-confidence! $gid))
       ($absent-demand (mark-goal-demand-dirty! $gid))
       ($unseen (goal-demand-revision $gid))
       ($_confidence-first
          (once (add-atom &goal_current_confidence (current-confidence-row $gid 0.4))))
       ($_confidence-second
          (once (add-atom &goal_current_confidence (current-confidence-row $gid 0.6))))
       ($_confidence-other
          (once (add-atom &goal_current_confidence (current-confidence-row $other 0.9))))
       ($_demand-first
          (once (add-atom &goal_demand_cache (goal-demand-cache-row $gid () ()))))
       ($_demand-second
          (once (add-atom &goal_demand_cache
             (goal-demand-cache-row $gid () ((root-demand $gid 0.5))))))
       ($_demand-other
          (once (add-atom &goal_demand_cache (goal-demand-cache-row $other () ()))))
       ($_metrics (begin-backward-query-metrics!))
       ($first (bump-goal-demand-revision! $gid))
       ($_revision-duplicate
          (once (add-atom &goal_demand_revision (goal-demand-revision-row $gid 99))))
       ($_revision-other
          (once (add-atom &goal_demand_revision (goal-demand-revision-row $other 11))))
       ($clear-confidence (clear-current-confidence! $gid))
       ($clear-demand (mark-goal-demand-dirty! $gid))
       ($second (bump-goal-demand-revision! $gid))
       ($confidence-count
          (length (collapse (match &goal_current_confidence
             (current-confidence-row $gid $_value) remaining))))
       ($demand-count
          (length (collapse (match &goal_demand_cache
             (goal-demand-cache-row $gid $_dependencies $_demands) remaining))))
       ($revisions
          (collapse (match &goal_demand_revision
             (goal-demand-revision-row $gid $revision) $revision)))
       ($other-preserved
          (and
             (space-row-present? &goal_current_confidence (current-confidence-row $other 0.9))
             (and
                (space-row-present? &goal_demand_cache (goal-demand-cache-row $other () ()))
                (== (goal-demand-revision $other) 11))))
       ($bumps (query_metric_value demand-revision-bumps))
       ($_reset (clear-backward-query-state!)))
      ((and (== $absent-confidence ()) (== $absent-demand ()))
       (and (== $clear-confidence ()) (== $clear-demand ()))
       $unseen $first $second $confidence-count $demand-count $revisions
       $other-preserved $bumps (goal-demand-revision $gid)))
   (true true 0 1 2 0 0 (2) true 2 0))

!(set-backward-query-metrics false)

;; The compact registry retains full registration order and multiplicity,
;; including identical waiters, equal projections, and interleaved child IDs.
!(test
   (let* (($_clear (clear-backward-query-state!))
          ($parent (demand-test-goal (ProjectionParent) 1))
          ($child (demand-test-goal (ProjectionChild) 2))
          ($other (demand-test-goal (ProjectionOther) 2))
          ($first (frontier-waiter $parent
             (and-bundle (demand-test-fact (ProjectionParent) first (STV 1 1)) ())
             0.7 () () 0 (frontier-value-spec 0.8 2)))
          ($second (frontier-waiter $parent
             (and-bundle (demand-test-fact (ProjectionParent) second (STV 1 1)) ())
             0.7 () () 0 (frontier-value-spec 0.8 2)))
          ($_first (register-goal-waiter! $child $parent $first))
          ($_other (register-goal-waiter! $other $parent $first))
          ($_second (register-goal-waiter! $child $parent $second))
          ($_duplicate (register-goal-waiter! $child $parent $first))
          ($_cached (register-goal-waiter! $child $parent
             (aggregate-waiter $parent (cached-aggregate-demand (STV 0.2 0.8)))))
          ($_live (register-goal-waiter! $child $parent
             (aggregate-waiter $parent live-aggregate-demand)))
          ($views (collapse (match &goal_waiter ($child $waiter)
             (waiter-demand-view $waiter))))
          ($indexed (collapse (match &goal_waiter_demand ($child $demand) $demand)))
          ($other-indexed (collapse (match &goal_waiter_demand ($other $demand) $demand))))
      ((== $indexed $views)
       (== $views
          ((frontier-demand $parent 0.7 0 0.8 2)
           (frontier-demand $parent 0.7 0 0.8 2)
           (frontier-demand $parent 0.7 0 0.8 2)
           (aggregate-demand $parent (cached-aggregate-demand (STV 0.2 0.8)))
           (aggregate-demand $parent live-aggregate-demand)))
       (== $other-indexed ((frontier-demand $parent 0.7 0 0.8 2)))
       (waiter-demand-view (aggregate-waiter 42 live-aggregate-demand))
       (waiter-demand-view (aggregate-waiter 43 (cached-aggregate-demand (STV 0.2 0.8))))
       (waiter-demand-view irrelevant)
       (goal-shallower? $parent 2)
       (goal-shallower? $parent 1)
       (goal-shallower? 999999999 2)))
   (true true true (aggregate-demand 42 live-aggregate-demand)
      (aggregate-demand 43 (cached-aggregate-demand (STV 0.2 0.8)))
      no-waiter-demand true false false))

;; Binding a retrieved delivery context cannot specialize the registered
;; proof variables or their sharing, nor its independently stored demand row.
!(test
   (let* (($_clear (clear-backward-query-state!))
          ($parent (demand-test-goal (ProjectionOpenParent) 0))
          ($child (demand-test-goal (ProjectionOpenChild) 1))
          ($waiter (frontier-waiter $parent
             (and-bundle
                (demand-test-fact (ProjectionAlias $label $label) $proof (STV 1 1))
                ((demand-test-fact (ProjectionPremise $label) $proof (STV 1 1))))
             0.7 () () 0 (frontier-value-spec 0.8 2)))
          ($_wait (register-goal-waiter! $child $parent $waiter))
          ($bound (collapse (match &goal_waiter
             ($child (frontier-waiter $parent
                (and-bundle ((ProjectionAlias chosen chosen) $_ctx accepted $_tv) $_premises)
                $_score $_seen $_parts $_path $_value)) true)))
          ($full (collapse (match &goal_waiter ($child $saved) $saved)))
          ($views (collapse (match &goal_waiter ($child $saved)
             (waiter-demand-view $saved))))
          ($indexed (collapse (match &goal_waiter_demand ($child $demand) $demand))))
      ((is-var $label) (is-var $proof) (== $bound (true))
       (=alpha $full ($waiter)) (== $indexed $views)))
   (true true true true true))

;; Query reset clears both registries before the next query reuses GIDs.
!(test
   (let* (($_clear (clear-backward-query-state!))
          ($_ids (change-state! bwd_gid 0))
          ($parent (demand-test-goal (ProjectionResetParent) 0))
          ($child (demand-test-goal (ProjectionResetChild) 1))
          ($_wait (register-goal-waiter! $child $parent
             (aggregate-waiter $parent live-aggregate-demand)))
          ($_reset (clear-backward-query-state!))
          ($_ids-again (change-state! bwd_gid 0))
          ($next-parent (demand-test-goal (ProjectionResetNextParent) 0))
          ($next-child (demand-test-goal (ProjectionResetNextChild) 1)))
      ((== $parent $next-parent) (== $child $next-child)
       (== (collapse (match &goal_waiter ($_gid $_waiter) true)) ())
       (== (collapse (match &goal_waiter_demand ($_gid $_demand) true)) ())
       (== (goal-root-demands $next-child) ())))
   (true true true true true))
