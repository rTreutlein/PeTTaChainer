;; Demand: how much each backward goal is currently wanted, and by whom.
;;
;; This layer owns the waiter registry — the parent goals and aggregates
;; waiting on a child's proofs — and the demand value derived from it: a list
;; of per-query-root contributions, merged by maximum within a root and
;; summed across roots only when a scalar queue priority is requested.
;; Demand is memoized per goal under a revision counter; a cached value
;; records the revisions of the goals it depends on, so staleness is a
;; comparison rather than a recomputation. An empty-to-live registration also
;; marks &goal_demand_wake so the scheduler wakes existing descendants.
;;
;; It is a separate layer because demand answers "what is this goal worth
;; right now" from waiters, parent confidence, and frontier-path liveness.
;; That keeps priority policy separate from queue mechanics (search.metta), and
;; gives the scheduler a single staleness protocol: compare a goal's demand
;; revision against the revision its agenda token was issued at.
;;
;; This file loads before the rest of the search component, so it also hosts
;; the component's shared row types (AndBundle, the FrontierPart family,
;; FrontierWaiter, AggregateWaiter, the demand cache rows) and two small list
;; utilities. The frontier-part pooling model is documented at its
;; declarations below; the algebra over parts lives in frontier_parts.metta.

(: AndBundle Type)
(: and-bundle
   (-[det]-> (| Goal (Statement KBContext Proof TV))
       (List (| Goal (Statement KBContext Proof TV)))
       AndBundle))
(= (get-type (and-bundle $goal $premises)) AndBundle)

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
(: NoPoolKey Type)
(: no-pool-key NoPoolKey)
(: FrontierWaiter Type)
(: FrontierValueSpec Type)
(: frontier-value-spec
   (-[det]-> Number Number FrontierValueSpec))
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
;; A shared goal carries one contribution per distinct query root. Alternative
;; waiters from the same root merge by maximum; independent roots add only when
;; the final scalar queue priority is requested.
(: root-demand-put-max
   (-[det]-> (List RootDemand) RootDemand (List RootDemand)))
(= (root-demand-put-max () $entry) (cons $entry ()))
(= (root-demand-put-max
      (cons (root-demand $head-root $head-score) $rest)
      (root-demand $root $score))
   (if (== $root $head-root)
      (cons (root-demand $root (max $score $head-score)) $rest)
      (cons (root-demand $head-root $head-score)
         (root-demand-put-max $rest (root-demand $root $score)))))

(: root-demands-sum (-[det]-> (List RootDemand) Number))
(= (root-demands-sum ()) 0.0)
(= (root-demands-sum (cons (root-demand $_root $score) $rest))
   (+ $score (root-demands-sum $rest)))

(: root-demands-max (-[det]-> (List RootDemand) Number))
(= (root-demands-max ()) 0.0)
(= (root-demands-max (cons (root-demand $_root $score) $rest))
   (max $score (root-demands-max $rest)))

(: root-goal-demand-seed (-[det]-> Number (List RootDemand)))
(= (root-goal-demand-seed $gid)
   (let $hits
      (collapse (match &root_goal (root-goal $gid) true))
      (if (== $hits ()) ()
         (cons (root-demand $gid 1.0) ()))))

(: frontier-root-demand-step
   (-[det]-> (| Number NoCurrentScore) Number Number Number
       RootDemand RootDemand))
(= (frontier-root-demand-step
      $current $candidate $premise-count $score-cap
      (root-demand $root $root-bound))
   (root-demand $root
      (min $score-cap
         (root-proof-value-score
            $root-bound $current $candidate
            $premise-count))))

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

(: goal-shallower? (-[det]-> Number Number Bool))
(= (goal-shallower? $gid $depth)
   (let $hits
      (collapse (once (match &goal
         (stored-goal-row $gid $goal-depth $_goal $_expanded $_pending)
         (stored-number $goal-depth))))
      (case $hits (
         ((cons $goal-depth $_rest) (< (the Number $goal-depth) $depth))
         ($_other false)))))

;; Demand traversals carry only scheduling inputs. Proof-bearing waiter
;; context stays in the delivery registry rather than being copied into every
;; demand walk. Projection preserves registry order and multiplicity.
(: WaiterDemand Type)
(: frontier-demand (-[det]-> Number Number Number Number Number WaiterDemand))
(: aggregate-demand (-[det]-> Number AggregateDemandSpec WaiterDemand))
(: no-waiter-demand WaiterDemand)
(: waiter-demand-view
   (-[det]-> Atom WaiterDemand))
(= (waiter-demand-view $waiter)
   (case $waiter (
      ((frontier-waiter $parent $_bundle $score $_seen $_parts $path
          (frontier-value-spec $candidate $count))
         (frontier-demand (the Number $parent) (the Number $score)
            (the Number $path) (the Number $candidate) (the Number $count)))
      ((aggregate-waiter $parent $spec)
         (aggregate-demand (the Number $parent) (the AggregateDemandSpec $spec)))
      ($_other no-waiter-demand))))

(: waiter-root-demands
   (-[det]-> WaiterDemand Number (List RootDemand)))
(= (waiter-root-demands $waiter $child-depth)
   (case $waiter (
      ((frontier-demand $parent-gid $score-cap $path-id $candidate $premise-count)
         (if (goal-shallower? $parent-gid $child-depth)
            (if (frontier-path-live? $path-id)
               (map-flat
                  (frontier-root-demand-step
                     (goal-confidence-or-none $parent-gid)
                     $candidate
                     $premise-count
                     $score-cap)
                  (goal-root-demands $parent-gid))
               ())
            ()))
      ((aggregate-demand $agg-gid $spec)
         (if (goal-shallower? $agg-gid $child-depth)
            (aggregate-root-demands-map
               $spec
               (goal-root-demands $agg-gid))
            ()))
      (no-waiter-demand ()))))

(: waiter-demands-step
   (-[det]-> Number (List RootDemand) WaiterDemand (List RootDemand)))
(= (waiter-demands-step $child-depth $acc $waiter)
   (fold-flat root-demand-put-max $acc
      (waiter-root-demands $waiter $child-depth)))

(= (goal-root-demands-walk $gid)
   (let $goal-hits (collapse (once (goal-by-id $gid)))
      (case $goal-hits (
         (() ())
         ((cons
             (stored-goal-row
                $_stored-gid $depth $_goal $_expanded $_pending)
             $_rest)
            (let $waiters
               (collapse
                  (match &goal_waiter
                     ($gid $waiter) (waiter-demand-view $waiter)))
               (fold-flat (waiter-demands-step $depth)
                  (root-goal-demand-seed $gid)
                  (the
                     (List WaiterDemand)
                     $waiters))))))))

(: shallower-parent-step
   (-[det]-> Number (List Number) Number (List Number)))
(= (shallower-parent-step $child-depth $acc $parent-gid)
   (if (goal-shallower? $parent-gid $child-depth)
      (cons $parent-gid $acc)
      $acc))

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
               (reverse-number-list
                  (fold-flat (shallower-parent-step $depth) () $parents))))))))

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

(: mark-goal-demand-dirty! (-[det]-> Number (List $none)))
(= (mark-goal-demand-dirty! $gid)
   (let $_
      (remove-atom &goal_demand_cache
         (goal-demand-cache-row $gid $_dependencies $_demands))
      ()))

(: goal-root-demands (-[det]-> Number (List RootDemand)))
(= (goal-root-demands $gid)
   (let*
      (($_evaluation
          (increment-backward-query-metric! goal-demand-evaluations))
       ($hits
          (collapse
             (let (goal-demand-cache-row $_gid $dependencies $demands)
                (once
                   (match &goal_demand_cache
                      (goal-demand-cache-row $gid $dependencies $demands)
                      (goal-demand-cache-row $gid $dependencies $demands)))
                (if (goal-demand-dependencies-current? $dependencies)
                   $demands
                   (empty))))))
      (if (not (== $hits ()))
         (let $_hit
            (increment-backward-query-metric! goal-demand-cache-hits)
            (the (List RootDemand) (car-atom $hits)))
         (let* (($_miss
                   (increment-backward-query-metric!
                      goal-demand-cache-misses))
                ($demands (goal-root-demands-walk $gid))
                ($dependencies
                   (map-flat
                      (|-> ($parent-gid)
                         (goal-demand-dependency
                            $parent-gid (goal-demand-revision $parent-gid)))
                      (goal-demand-parent-gids $gid)))
                ($_old (mark-goal-demand-dirty! $gid))
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
          (fold-flat root-demand-put-max $current-demands
             (waiter-root-demands (waiter-demand-view $waiter) $child-depth)))
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
       ;; Demand equality does not imply unchanged child priorities: this
       ;; revision can expose a dead frontier path in a descendant's cache
       ;; even when this goal has published no proof. Replay is separate.
       ($_revision (bump-goal-demand-revision! $child-gid))
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
              (if (space-row-present? &goal_child ($parent-gid $child-gid)) ()
                 (once (chainer-add-atom &goal_child ($parent-gid $child-gid)))))
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

(: and-bundle-goal
   (-[det]-> AndBundle
       (| Goal (Statement KBContext Proof TV))))
(= (and-bundle-goal (and-bundle $goal $_premises)) $goal)
(: and-bundle-premises
   (-[det]-> AndBundle
       (List (| Goal (Statement KBContext Proof TV)))))
(= (and-bundle-premises (and-bundle $_goal $premises)) $premises)

(: stored-atom-list
   (-[det]-> Expression (List Atom)))
(= (stored-atom-list ())
   ())
(= (stored-atom-list (cons $head $rest))
   (cons $head (stored-atom-list $rest)))
