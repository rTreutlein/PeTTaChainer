!(import! &self ../../pettachainer/metta/petta_chainer)

;; Selection helpers must reduce to one boolean. A specific equation plus a
;; catch-all equation would leak both true and false into scheduler decisions.
!(test
   (collapse
      (shared-evidence-frontier-proof?
         (total-implication-frontier sample-proof)))
   (true))

!(test
   (collapse
      (shared-evidence-frontier-proof?
         (inheritance-query-result
            (total-implication-frontier sample-proof))))
   (true))

!(test
   (collapse
      (shared-evidence-frontier-proof?
         (member-inheritance-sample antecedent-proof consequent-proof)))
   (true))

!(test
   (collapse (shared-evidence-frontier-proof? ordinary-proof))
   (false))

!(test
   (collapse
      (inheritance-lift-rule-goal?
         (assemble-runtime-fact
            (brand Statement (Inheritance A B))
            (brand KBContext (kb MAIN Nil))
            (brand Proof
               ((inheritance-rule-lift rule) source instance))
            (STV 1.0 1.0))))
   (true))

!(test
   (collapse
      (inheritance-lift-rule-goal?
         (assemble-runtime-fact
            (brand Statement (Inheritance A B))
            (brand KBContext (kb MAIN Nil))
            (brand Proof ordinary-proof)
            (STV 1.0 1.0))))
   (false))

!(test (tv-confidence (STV 0.7 0.35)) 0.35)

!(test (tv-confidence maybeUnknown) 1.0)

!(test (tv-confidence (CTV (STV 0.9 0.7) (STV 0.1 0.4))) 0.4)

!(test (expected-tv no-evidence) no-evidence)

!(test
   (term-confidence
      (CPU CTVModusPonensFormula ((STV 0.8 0.9) (CTV (STV 1.0 0.6) (STV 0.0 0.4))) $out))
   0.8999975376989856)

!(test (CTVModusPonensFormula (STV 0.5 1.0) (CTV (STV 1.0 0.5) (STV 0.1 0.5))) (STV 0.55 0.916683750966784))

!(test (CTVModusPonensFormula (STV 0.5 1.0) (CTV (STV 0.8 0.6) (STV 0.0 0.0))) (STV 0.4 0.8993337363827603))

!(test (CTVFormula (STV 1.0 1.0) (CTV (STV 0.9 0.950213) (STV 0 1))) (STV 0.9 0.9502129991872743))

!(test (cpu-expected-confidence CTVFormula ((STV 1.0 1.0) (CTV (STV 0.9 0.950213) (STV 0 1)))) 0.9502129991872743)

!(test (term-confidence (CPU NotFormula ((STV 0.75 0.6)) $out)) 0.6)

!(test (term-confidence (CPU AndFormula ((STV 0.8 0.4) (STV 0.9 0.7)) $out)) 0.47929561423062006)

!(test (term-confidence (CPU OrFormula ((STV 0.8 0.4) (STV 0.9 0.7)) $out)) 0.8322690087859733)

;; A direct CPU goal is a filter as well as a computation.  A mismatched
;; requested result must not become a stored proof candidate.
!(test
   (collapse
      (direct-goal-results-view 1
         (CPU NotEqual (same same) true)))
   ())

!(test
   (collapse
      (direct-goal-results-view 1
         (CPU NotEqual (left right) true)))
   ((CPU NotEqual (left right) true)))

;; Inverse OR projection propagates uncertainty from both the total and the
;; known child rather than copying their minimum confidence.
!(test
   (OrProjection (STV 0.75 0.9) (STV 0.5 1.0))
   (STV 0.5 0.7498916209608741))

!(test (LikelierThanFormula (STV 0.9 0.6) (STV 0.4 0.8)) (STV 0.54 0.6))

!(test (LikelierThanFormula (STV 0.4 0.6) (STV 0.9 0.8)) (STV 0.039999999999999994 0.6))

!(test (term-confidence (CPU LikelierThanFormula ((STV 0.8 0.4) (STV 0.9 0.7)) $out)) 0.4)

!(test
   (term-confidence (CPU CTVInversionFormula ($a $b (CTV (STV 0.8 0.632121) (STV 0.1 0.632121))) $out))
   0.5689089)

!(test
   (CTVInversionFormula (STV 0.2 1.0) (STV 0.24 1.0) (CTV (STV 0.8 1.0) (STV 0.1 1.0)))
   (CTV (STV 0.6666666666666669 0.9985188611281907) (STV 0.05263157894736841 0.9999538033069306)))

!(test
   (CTVInversionFormula (STV 0.0 1.0) (STV 0.1 1.0) (CTV (STV 0.8 1.0) (STV 0.1 1.0)))
   (CTV (STV 0.0 0.993640649761643) (STV 0.0 0.9999950617533683)))

!(test
   (premises-expected-confidence
      (cons (CPU CTVModusPonensFormula ((STV 1.0 1.0) (CTV (STV 1.0 0.2) (STV 0.0 1.0))) $tv1)
         (cons (CPU CTVModusPonensFormula ($tv1 (CTV (STV 1.0 0.55) (STV 0.0 1.0))) $tv2) ())))
   0.1716299316527129)

!(test
   (premises-expected-confidence
      (cons (CPU CTVModusPonensFormula ((STV 0.25 1.0) (CTV (STV 1.0 0.8) (STV 0.0 1.0))) $tv) ()))
   0.9998999264084577)

!(test
   (premises-expected-confidence
      (cons (CPU NotFormula ((STV 0.75 1.0)) $not-tv)
         (cons (CPU CTVModusPonensFormula ($not-tv (CTV (STV 1.0 0.8) (STV 0.0 0.0))) $tv) ())))
   0.9975061460485739)

!(test
   (premises-expected-confidence
      (cons
         (assemble-runtime-fact
            (brand Statement (Creature $c))
            (brand KBContext (kb MAIN Nil))
            (brand Proof $prfC)
            (STV 1.0 1.0))
         ((CPU FoldAllCompiled (kb (Animal $a) extract-tv (BaseRateEvidence 0.0 0.0) BaseRateAcc base-rate result-tv) $tvA)
          (CPU FoldAllCompiled (kb (Creature $c2) extract-tv (BaseRateEvidence 0.0 0.0) BaseRateAcc base-rate result-tv) $tvBr)
          (CPU CTVInversionFormula ($tvA $tvBr (CTV (STV 0.8 0.632121) (STV 0.1 0.632121))) $iitv)
          (CPU CTVModusPonensFormula ((STV 1.0 1.0) $iitv) $mp-tv))))
   0.5689089)

!(compileadd inverseTotalKb
   (: inverseTotalRule
      (Implication (InverseTotalA) (InverseTotalB))
      (CTV (STV 0.8 0.9) (STV 0.1 0.9))))

!(test
   (collapse
      (once
         (match rules
            (runtime-rule-row
               $id
               ((InverseTotalA)
                  (inverseTotalKb $ctx $vars)
                  ((inverted inverseTotalRule with cpu cpu) $prfb-wit)
                  $mp-tv)
               (((InverseTotalB) (inverseTotalKb $ctx $vars) $prfb-wit $btv-wit)
                  (CPU FoldAllCompiled (inverseTotalKb (InverseTotalA) extract-tv (BaseRateEvidence 0.0 0.0) BaseRateAcc base-rate result-tv) $atv-est)
                  (CPU FoldAllCompiled (inverseTotalKb (InverseTotalB) extract-tv (BaseRateEvidence 0.0 0.0) BaseRateAcc base-rate result-tv) $btv-est)
                  (CPU ImplicationCTVFormula ($atv-est $btv-est (CTV (STV 0.8 0.9) (STV 0.1 0.9))) $rule-ctv)
                  (CPU CTVInversionFormula ($atv-est $btv-est $rule-ctv) $iitv)
                  (CPU CTVModusPonensFormula ($btv-wit $iitv) $mp-tv)))
            ok)))
   (ok))

!(test
   (let*
      (($heap0 (empty_heap))
       ($heap1 (add_to_heap $heap0 3.0 low))
       ($heap2 (add_to_heap $heap1 1.0 high))
       ($heap3 (add_to_heap $heap2 2.0 mid))
       ($pruned (heap-prune-to-size 2 $heap3))
       ($rest (get_from_heap $pruned $key1 $item1))
       ($_empty (get_from_heap $rest $key2 $item2)))
      ($item1 $item2 (heap_size $rest)))
   (high mid 1))

!(test
   (let*
      (($heap0 (empty_heap))
       ($heap1 (add_to_heap $heap0 1.0 high))
       ($heap2 (add_to_heap $heap1 2.0 low))
       ($kept (bounded-agenda-prune 1 $heap2)))
      (heap_size $kept))
   2)

!(test
   (let*
      (($heap0 (empty_heap))
       ($heap1 (add_to_heap $heap0 1.0 high))
       ($empty (bounded-agenda-prune 0 $heap1)))
      (heap_size $empty))
   1)

!(test
   (let*
      (($heap0 (empty_heap))
       ($heap1 (add_to_heap $heap0 1.0 high))
       ($_disable (set-bounded-agenda-pruning false))
       ($kept (bounded-agenda-prune 0 $heap1))
       ($_enable (set-bounded-agenda-pruning true)))
      (heap_size $kept))
   1)

(: clear-backward-state (-[det]-> (List Atom)))
(= (clear-backward-state)
   (progn
      (clear-backward-query-state!)
      (foreach-flat remove-all-atoms
         (&proof &proof_goal &proof_result
          &proof_current &proof_current_output
          &proof_current_result &proof_current_result_output
          &proof_current_result_dirty
          &proof_parent &proof_static_live
          &proof_superseded &proof_retired))
      ()))

(: test-runtime-fact
   (-[det]-> Statement (| Atom Expression) $tv
       (Statement KBContext Proof TV)))
(= (test-runtime-fact $statement $proof $tv)
   (test-runtime-fact-in-context
      $statement (brand KBContext (kb MAIN ())) $proof $tv))

(: test-runtime-fact-in-context
   (-[det]-> Statement KBContext (| Atom Expression) $tv
       (Statement KBContext Proof TV)))
(= (test-runtime-fact-in-context $statement $kbctx $proof $tv)
   (assemble-runtime-fact
      $statement
      $kbctx
      (brand Proof $proof)
      (the TV $tv)))

;; Test-only view of the claim protocol: an entry is current when it is owned
;; by the goal's live work generation and carries the current demand revision.
;; The engine itself validates entries through claim-goal-agenda-entry!.
(: agenda-entry-current? (-[det]-> AgendaEntry Bool))
(= (agenda-entry-current?
      (agenda-entry $kind $gid
         (agenda-revision-token $demand-revision $generation)))
   (if
      (agenda-entry-owned?
         (agenda-entry $kind $gid
            (agenda-revision-token $demand-revision $generation)))
      (== $demand-revision (goal-demand-revision $gid))
      false))

(: current-agenda-entry-count
   (-[det]-> (Heap AgendaEntry) Number))
(= (current-agenda-entry-count $agenda)
   (case (collapse (heap_pop $agenda)) (
      (() 0)
      ((cons $pop $_rest)
         (current-agenda-entry-count-pop $pop)))))

(: current-agenda-entry-count-pop
   (-[det]-> (Number AgendaEntry (Heap AgendaEntry)) Number))
(= (current-agenda-entry-count-pop ($_priority $entry $rest))
   (+ (if (agenda-entry-current? $entry) 1 0)
      (current-agenda-entry-count $rest)))

;; Repeated requests for one lane share one current entry.  Requesting another
;; lane advances the work generation and reissues both lanes, leaving the
;; previous generation stale rather than independently valid.
!(test
   (let*
      (($_clear (clear-backward-state))
       ($_gidreset (change-state! bwd_gid 0))
       ($gid
          (ensure-goal-at-depth
             (test-runtime-fact
                (AgendaGoal) (brand Proof $proof) $tv)
             0))
       ($agenda1
          (request-goal-agenda-kind-heap
             (empty_heap) $gid agenda-refresh))
       ($agenda2
          (request-goal-agenda-kind-heap
             $agenda1 $gid agenda-refresh))
       ($current2 (current-agenda-entry-count $agenda2))
       ($agenda3
          (request-goal-agenda-kind-heap
             $agenda2 $gid agenda-expand)))
      ((heap_size $agenda2)
       $current2
       (heap_size $agenda3)
       (current-agenda-entry-count $agenda3)))
   (1 1 3 2))

;; A prior-generation entry is rejected before demand evaluation. Even with a
;; deliberately dirty cache, claiming it cannot rebuild the cache or advance
;; the demand revision.
!(test
   (let*
      (($_clear (clear-backward-state))
       ($_gidreset (change-state! bwd_gid 0))
       ($gid
          (ensure-goal-at-depth
             (test-runtime-fact
                (StaleAgendaGoal) (brand Proof $proof) $tv)
             0))
       ($agenda1
          (request-goal-agenda-kind-heap
             (empty_heap) $gid agenda-refresh))
       (($_priority $stale-entry $_rest) (heap_pop $agenda1))
       ($_agenda2
          (request-goal-agenda-kind-heap
             $agenda1 $gid agenda-expand))
       ($_dirty (mark-goal-demand-dirty! $gid))
       ($before (goal-demand-revision $gid))
       ($disposition (claim-goal-agenda-entry! $stale-entry))
       ($after (goal-demand-revision $gid))
       ($cache
          (collapse
             (match &goal_demand_cache
                (goal-demand-cache-row $gid $_dependencies $_demands)
                cached))))
      ($disposition $before $after $cache))
   (agenda-stale 1 1 ()))

;; A lane whose score rises while it is pending gets a fresh current entry
;; immediately.  The stale 0.2 entry remains harmless in the heap while the
;; 0.4 replacement becomes the next item by priority.
!(test
   (let*
      (($_clear (clear-backward-state))
       ($_gidreset (change-state! bwd_gid 0))
       ($gid
          (ensure-goal-at-depth
             (CPU FoldAllCompiled reprioritized-args $result)
             0))
       ($_aggregate1
          (add-atom &aggregate
             (stored-aggregate-row
                $gid 99 reprioritized-args 0.2 0.0 ())))
       ($agenda1
          (request-goal-agenda-kind-heap
             (empty_heap) $gid agenda-aggregate))
       (($old-priority $_old-entry $_old-rest)
          (heap_pop $agenda1))
       ($_aggregate2
          (progn
             (remove-atom &aggregate
                (stored-aggregate-row
                   $gid 99 reprioritized-args 0.2 0.0 ()))
             (add-atom &aggregate
                (stored-aggregate-row
                   $gid 99 reprioritized-args 0.4 0.0 ()))))
       ($_revision (bump-goal-demand-revision! $gid))
       ($agenda2
          (request-goal-agenda-kind-heap
             $agenda1 $gid agenda-aggregate))
       (($fresh-priority
          (agenda-entry agenda-aggregate $_fresh-gid
             (agenda-revision-token $fresh-revision $fresh-generation))
          $_fresh-rest)
          (heap_pop $agenda2))
       ($fresh-score (agenda-kind-score agenda-aggregate $gid)))
      ((heap_size $agenda2)
       (< $fresh-priority $old-priority)
       $fresh-score $fresh-revision $fresh-generation
       (current-agenda-entry-count $agenda2)))
   (2 true 0.4 1 2 1))

;; A lower score does not eagerly replace pending work.  When that entry is
;; eventually popped, retokening refreshes its revision and score in place
;; without advancing the work generation or spending a search step.
!(test
   (let*
      (($_clear (clear-backward-state))
       ($_gidreset (change-state! bwd_gid 0))
       ($gid
          (ensure-goal-at-depth
             (CPU FoldAllCompiled lowered-priority-args $result)
             0))
       ($_aggregate1
          (add-atom &aggregate
             (stored-aggregate-row
                $gid 99 lowered-priority-args 0.4 0.0 ())))
       ($agenda1
          (request-goal-agenda-kind-heap
             (empty_heap) $gid agenda-aggregate))
       ($_aggregate2
          (progn
             (remove-atom &aggregate
                (stored-aggregate-row
                   $gid 99 lowered-priority-args 0.4 0.0 ()))
             (add-atom &aggregate
                (stored-aggregate-row
                   $gid 99 lowered-priority-args 0.2 0.0 ()))))
       ($_revision (bump-goal-demand-revision! $gid))
       ($agenda2
          (request-goal-agenda-kind-heap
             $agenda1 $gid agenda-aggregate))
       (($_priority $entry $_rest) (heap_pop $agenda2))
       ($disposition (claim-goal-agenda-entry! $entry))
       ((stored-goal-row
            $_claimed-gid $_claimed-depth $_claimed-goal $_claimed-expanded
            (goal-agenda-state
               $claimed-generation $claimed-revision $claimed-score
               $claimed-lanes))
          (goal-by-id $gid))
       ($retokened
          (retoken-goal-agenda-entry-heap
             (empty_heap) $entry))
       (($_new-priority $new-entry $_new-rest)
          (heap_pop $retokened))
       ((stored-goal-row
            $_stored-gid $_depth $_goal $_expanded
            (goal-agenda-state
               $generation $issued-revision $issued-score
               $_requested-lanes))
          (goal-by-id $gid)))
      ((heap_size $agenda2) $disposition
       $claimed-generation $claimed-revision $claimed-score
       (stored-list-member? agenda-aggregate $claimed-lanes)
       (heap_size $retokened)
       $generation $issued-revision $issued-score
       (agenda-entry-current? $new-entry)))
   (1 agenda-retoken 1 1 0.2 true 1 1 1 0.2 true))

;; A revision-only change with the same score claims in place.  It refreshes
;; the state's issued revision, clears the lane, and leaves no replacement
;; entry to perturb equal-priority ordering or consume an extra step.
!(test
   (let*
      (($_clear (clear-backward-state))
       ($_gidreset (change-state! bwd_gid 0))
       ($gid
          (ensure-goal-at-depth
             (CPU FoldAllCompiled equal-priority-args $result)
             0))
       ($_aggregate
          (add-atom &aggregate
             (stored-aggregate-row
                $gid 99 equal-priority-args 0.4 0.0 ())))
       ($agenda1
          (request-goal-agenda-kind-heap
             (empty_heap) $gid agenda-aggregate))
       ($_revision (bump-goal-demand-revision! $gid))
       ($agenda2
          (request-goal-agenda-kind-heap
             $agenda1 $gid agenda-aggregate))
       (($_priority $entry $rest) (heap_pop $agenda2))
       ($disposition (claim-goal-agenda-entry! $entry))
       ((stored-goal-row
            $_stored-gid $_depth $_goal $_expanded
            (goal-agenda-state
               $generation $issued-revision $issued-score
               $requested-lanes))
          (goal-by-id $gid)))
      ((heap_size $agenda2) $disposition (heap_size $rest)
       $generation $issued-revision $issued-score
       (stored-list-member? agenda-aggregate $requested-lanes)))
   (1 agenda-claimed 0 1 1 0.4 false))

;; Beam pruning retains current control work, releases a discarded current
;; expansion, and permits a later request to enqueue that expansion again.
!(test
   (let*
      (($_clear (clear-backward-state))
       ($_gidreset (change-state! bwd_gid 0))
       ($gid
          (ensure-goal-at-depth
             (test-runtime-fact
                (PrunedAgendaGoal) (brand Proof $proof) $tv)
             0))
       ($agenda1
          (request-goal-agenda-kind-heap
             (empty_heap) $gid agenda-refresh))
       ($agenda2
          (request-goal-agenda-kind-heap
             $agenda1 $gid agenda-expand))
       ($pruned (backward-agenda-prune-to-size 1 $agenda2))
       ($expand-after-prune
          (goal-agenda-kind-requested? $gid agenda-expand))
       ($refresh-after-prune
          (goal-agenda-kind-requested? $gid agenda-refresh))
       ($rescheduled
          (request-goal-agenda-kind-heap
             $pruned $gid agenda-expand)))
      ((heap_size $pruned)
       $expand-after-prune
       $refresh-after-prune
       (current-agenda-entry-count $rescheduled)
       (goal-agenda-kind-requested? $gid agenda-expand)))
   (1 false true 2 true))

;; Refreshing a result to the representative it already exposes must not mark
;; that proof superseded.
!(test
   (let* (($_clear (clear-backward-state))
          ($_same
             (supersede-current-proof-result! (42) 42)))
      (collapse
         (match &proof_superseded (42) true)))
   ())

;; Filtering current proofs preserves their indexed order while accumulating
;; accepted IDs in linear time.
!(test
   (let*
      (($_clear (clear-backward-state))
       ($_gidreset (change-state! bwd_gid 0))
       ($_pidreset (change-state! bwd_pid 0))
       ($gid
          (ensure-goal-at-depth
             (test-runtime-fact
                (OrderedGoal) (brand Proof $proof) $tv)
             0))
       ($first
          (store-proof-candidate $gid
             (proof-candidate
                (leaf
                   (test-runtime-fact
                      (OrderedGoal) orderedFirst (STV 1.0 0.8)))
                0.8 () ())))
       ($second
          (store-proof-candidate $gid
             (proof-candidate
                (leaf
                   (test-runtime-fact
                      (OrderedGoal) orderedSecond (STV 1.0 0.7)))
                0.7 () ())))
       ($third
          (store-proof-candidate $gid
             (proof-candidate
                (leaf
                   (test-runtime-fact
                      (OrderedGoal) orderedThird (STV 1.0 0.6)))
                0.6 () ()))))
      (== (goal-live-proof-ids $gid)
         ($first $second $third)))
   true)

;; A grouped snapshot commit partitions the old representatives once. It
;; retires every snapshot for the replaced key and preserves the relative
;; order of all other groups.
!(test
   (let*
      (($_clear (clear-backward-state))
       ($_gidreset (change-state! bwd_gid 0))
       ($_pidreset (change-state! bwd_pid 0))
       ($old-a-one-gid
          (ensure-goal-at-depth
             (CPU GroupedFoldAllCompiled (partition-key a) 1)
             1))
       ($b-gid
          (ensure-goal-at-depth
             (CPU GroupedFoldAllCompiled (partition-key b) 1)
             1))
       ($old-a-two-gid
          (ensure-goal-at-depth
             (CPU GroupedFoldAllCompiled (partition-key a) 2)
             1))
       ($new-a-gid
          (ensure-goal-at-depth
             (CPU GroupedFoldAllCompiled (partition-key a) 3)
             1))
       ($aggregate-gid
          (ensure-goal-at-depth
             (CPU FoldAllCompiled partition-controller $out)
             0))
       ($old-a-one
          (store-proof-candidate $old-a-one-gid
             (leaf-result-candidate
                (CPU GroupedFoldAllCompiled
                   (partition-key a) 1)
                ())))
       ($b
          (store-proof-candidate $b-gid
             (leaf-result-candidate
                (CPU GroupedFoldAllCompiled
                   (partition-key b) 1)
                ())))
       ($old-a-two
          (store-proof-candidate $old-a-two-gid
             (leaf-result-candidate
                (CPU GroupedFoldAllCompiled
                   (partition-key a) 2)
                ())))
       ($new-a
          (store-proof-candidate $new-a-gid
             (leaf-result-candidate
                (CPU GroupedFoldAllCompiled
                   (partition-key a) 3)
                ())))
       ($_aggregate
          (add-atom &aggregate
             (stored-aggregate-row
                $aggregate-gid $old-a-one-gid partition-controller
                1.0 0.0 ($old-a-one $b $old-a-two))))
       ($_append
          (append-grouped-aggregate-current-pid!
             $aggregate-gid $new-a))
       ((stored-aggregate-row
            $_stored-gid $_child $_args $_base $_pending $current)
          (aggregate-by-id $aggregate-gid)))
      ((== $current ($new-a $b))
       (proof-retired? $old-a-one)
       (proof-retired? $old-a-two)
       (proof-retired? $b)
       (proof-retired? $new-a)))
   (true true true false false))

!(test
   (let*
      (($_clear (clear-backward-state))
       ($_gidreset (change-state! bwd_gid 0))
       ($open-a (ensure-goal-at-depth (test-runtime-fact (Pet $a) (brand Proof $prf) $tv) 0))
       ($open-x (ensure-goal-at-depth (test-runtime-fact (Pet $x) (brand Proof $p) $t) 0))
       ($closed (ensure-goal-at-depth (test-runtime-fact (Pet max) (brand Proof $p2) $t2) 0))
       ($left-goal
          (test-runtime-fact
             (Shares $left $left $other-left)
             (brand Proof $left-proof) $left-tv))
       ($right-goal
          (test-runtime-fact
             (Shares $first-right $right $right)
             (brand Proof $right-proof) $right-tv))
       ($left-key (brand ProofGoalKey (goal-key $left-goal)))
       ($right-key (brand ProofGoalKey (goal-key $right-goal)))
       ($left-hash (index-hash $left-key))
       ($right-hash (index-hash $right-key))
       ($left-gid (ensure-goal-at-depth $left-goal 0))
       ($right-gid (ensure-goal-at-depth $right-goal 0)))
      ((== $open-a $open-x)
       (== $open-a $closed)
       (is-var $left-hash)
       (== $left-hash $right-hash)
       (=alpha $left-key $right-key)
       (== $left-gid $right-gid)))
   (true false false true false false))

;; Cycle checks memoize only the top-level empty-seen call. A colliding row
;; with a different cycle key must be ignored, recursive child checks must not
;; add their own rows, and ordinary query reset must clear the cache.
!(test
   (let*
      (($_clear (clear-backward-state))
       ($_gidreset (change-state! bwd_gid 0))
       ($_pidreset (change-state! bwd_pid 0))
       ($child-gid
          (ensure-goal-at-depth
             (test-runtime-fact
                (CycleMemoChild) (brand Proof $child-proof) $child-tv)
             1))
       ($parent-gid
          (ensure-goal-at-depth
             (test-runtime-fact
                (CycleMemoParent) (brand Proof $parent-proof) $parent-tv)
             0))
       ($target-gid
          (ensure-goal-at-depth
             (test-runtime-fact
                (CycleMemoTarget) (brand Proof $target-proof) $target-tv)
             0))
       ($child-pid
          (store-proof-candidate $child-gid
             (leaf-result-candidate
                (test-runtime-fact
                   (CycleMemoChild) child-cycle-proof (STV 1.0 0.8))
                ())))
       ($parent-pid
          (store-proof-candidate $parent-gid
             (aggregate-result-candidate
                (test-runtime-fact
                   (CycleMemoParent) parent-cycle-proof (STV 1.0 0.8))
                () ($child-pid))))
       ($_collision
          (add-atom &proof_cycle_cache
             ($parent-pid $target-gid different-cycle-key true)))
       ($first
          (proof-depends-on-goal-seen?
             $parent-pid $target-gid closed-goal ()))
       ($second
          (proof-depends-on-goal-seen?
             $parent-pid $target-gid closed-goal ()))
       ($rows-before-clear
          (collapse
             (match &proof_cycle_cache
                ($_cached-pid $_cached-gid $_cached-key $_cached-result)
                true)))
       ($_query-clear (clear-backward-query-state!))
       ($rows-after-clear
          (collapse
             (match &proof_cycle_cache
                ($_cleared-pid $_cleared-gid $_cleared-key $_cleared-result)
                true))))
      ($first $second
       (length $rows-before-clear) (length $rows-after-clear)))
   (false false 2 0))

!(test
   (let*
      (($_clear (clear-backward-state))
        ($_gidreset (change-state! bwd_gid 0))
        ($_pidreset (change-state! bwd_pid 0))
        ($gid (ensure-goal-at-depth (test-runtime-fact (Goal) (brand Proof $prf) (STV 1.0 1.0)) 0))
        ($pid
           (store-proof-candidate $gid
              (proof-candidate (leaf (test-runtime-fact (Goal) factA (STV 1.0 0.8)))
                 0.8
                 ((fact-ev (kb MAIN ()) factA (Goal)))
                 ()))))
      (once (proof-term-evidence-list-mode proof-walk-plain (proof-ref $pid))))
   ((fact-ev (kb MAIN ()) factA (Goal))))

!(test
   (let*
      (($_clear (clear-backward-state))
        ($_gidreset (change-state! bwd_gid 0))
        ($_pidreset (change-state! bwd_pid 0))
        ($gid (ensure-goal-at-depth (test-runtime-fact (Goal) (brand Proof $prf) (STV 1.0 1.0)) 0))
        ($pid-a
           (store-proof-candidate $gid
              (proof-candidate (leaf (test-runtime-fact (Goal) (bench-base-fact demo 1 1) (STV 1.0 0.8)))
                 0.8
                 ((fact-ev (kb MAIN ()) (bench-base-fact demo 1 1) (Goal)))
                 ())))
        ($pid-b
           (store-proof-candidate $gid
              (proof-candidate (leaf (test-runtime-fact (Goal) (bench-base-fact demo 1 2) (STV 1.0 0.7)))
                 0.7
                 ((fact-ev (kb MAIN ()) (bench-base-fact demo 1 2) (Goal)))
                 ()))))
      (evidence-sets-overlap? (snd (proof-stats-by-id $pid-a)) (snd (proof-stats-by-id $pid-b))))
   false)

;; Demand scoring caches the current confidence for each query-local goal.
;; Storing another candidate must invalidate that value before revision.
!(test
   (let*
      (($_clear (clear-backward-state))
       ($_gidreset (change-state! bwd_gid 0))
       ($_pidreset (change-state! bwd_pid 0))
       ($kbctx (brand KBContext (kb MAIN Nil)))
       ($gid
             (ensure-goal-at-depth
             (test-runtime-fact-in-context
                (ConfidenceCacheGoal) $kbctx (brand Proof $prf) $tv)
             0))
       ($empty (goal-current-confidence $gid))
       ($_first
          (store-proof-candidate $gid
             (proof-candidate
                (leaf
                   (test-runtime-fact-in-context
                      (ConfidenceCacheGoal) $kbctx
                      cacheA (STV 1.0 0.4)))
                0.4
                ((fact-ev
                    (kb MAIN Nil) cacheA (ConfidenceCacheGoal)))
                ())))
       ($first (goal-current-confidence $gid))
       ($_second
          (store-proof-candidate $gid
             (proof-candidate
                (leaf
                   (test-runtime-fact-in-context
                      (ConfidenceCacheGoal) $kbctx
                      cacheB (STV 1.0 0.5)))
                0.5
                ((fact-ev
                    (kb MAIN Nil) cacheB (ConfidenceCacheGoal)))
                ())))
       ($revised (goal-current-confidence $gid)))
      ($empty $first $revised))
   (no-current 0.4 0.625))

;; A raw proof stays live so it can be revised with later evidence. Ordinary
;; subgoal reasoning treats a parent that consumed the former representative
;; as stale, while the root result view retains it as a bounded-search
;; incumbent until a replacement root is committed.
!(test
   (let*
      (($_clear (clear-backward-state))
       ($_gidreset (change-state! bwd_gid 0))
       ($_pidreset (change-state! bwd_pid 0))
       ($child-gid (ensure-goal-at-depth (test-runtime-fact (Child) (brand Proof $cprf) $ctv) 1))
       ($parent-gid (ensure-goal-at-depth (test-runtime-fact (Parent) (brand Proof $pprf) $ptv) 0))
       ($first-child
          (store-proof-candidate $child-gid
             (proof-candidate (leaf (test-runtime-fact (Child) childA (STV 1.0 0.8)))
                0.8 ((fact-ev (kb MAIN ()) childA (Child))) ())))
       ($old-parent
          (store-proof-candidate $parent-gid
             (proof-candidate (rule (test-runtime-fact (Parent) (parentRule childA) (STV 1.0 0.8)))
                0.8 ((fact-ev (kb MAIN ()) childA (Child))) ($first-child))))
       ($_second-child
          (store-proof-candidate $child-gid
             (proof-candidate (leaf (test-runtime-fact (Child) childB (STV 1.0 0.7)))
                0.7 ((fact-ev (kb MAIN ()) childB (Child))) ()))))
      ((proof-live? $first-child)
       (proof-current-representative? $first-child)
       (proof-live? $old-parent)
       (length (goal-merged-proof-ids $child-gid))
       (goal-live-proof-ids $parent-gid)
       (== (goal-incumbent-proof-ids $parent-gid) ($old-parent))
       (not (== (root-goal-results-with-materialization $parent-gid false) ()))))
   (true false false 1 () true true))

;; One invalidation cascade may revisit a shared parent through multiple paths,
;; but a later cascade must re-evaluate it.  This conjunction parent survives
;; the first child's supersession, then becomes stale when its other child is
;; retired.
!(test
   (let*
      (($_clear (clear-backward-state))
       ($_gidreset (change-state! bwd_gid 0))
       ($_pidreset (change-state! bwd_pid 0))
       ($child-one-gid
          (ensure-goal-at-depth
             (test-runtime-fact
                (ChildOne) (brand Proof $p1) $tv1)
             1))
       ($child-two-gid
          (ensure-goal-at-depth
             (test-runtime-fact
                (ChildTwo) (brand Proof $p2) $tv2)
             1))
       ($parent-gid
          (ensure-goal-at-depth
             (test-runtime-fact
                (Parent) (brand Proof $pp) $ptv)
             0))
       ($child-one-pid
          (store-proof-candidate $child-one-gid
             (proof-candidate
                (leaf
                   (test-runtime-fact
                      (ChildOne) childOne (STV 1.0 0.8)))
                0.8
                ((fact-ev (kb MAIN ()) childOne (ChildOne)))
                ())))
       ($child-two-pid
          (store-proof-candidate $child-two-gid
             (proof-candidate
                (leaf
                   (test-runtime-fact
                      (ChildTwo) childTwo (STV 1.0 0.7)))
                0.7
                ((fact-ev (kb MAIN ()) childTwo (ChildTwo)))
                ())))
       ($parent-pid
          (store-proof-candidate $parent-gid
             (proof-candidate
                (rule
                   (test-runtime-fact
                      (Parent)
                      (conjunction childOne childTwo)
                      (STV 1.0 0.6)))
                0.6
                ((fact-ev (kb MAIN ()) childOne (ChildOne))
                 (fact-ev (kb MAIN ()) childTwo (ChildTwo)))
                ($child-one-pid $child-two-pid))))
       ($_prime (proof-live? $parent-pid))
       ($_supersede
          (once
             (add-atom &proof_superseded ($child-one-pid))))
       ($_first
          (invalidate-proof-dependents! $child-one-pid))
       ($after-first (proof-live? $parent-pid))
       ($_second
          (deactivate-current-proof! $child-two-pid)))
      ($after-first
       (proof-live? $parent-pid)
       (proof-retired? $parent-pid)
       (goal-live-proof-ids $parent-gid)))
   (true false true ()))

!(test
   (let*
      (($_clear (clear-backward-state))
        ($_gidreset (change-state! bwd_gid 0))
        ($_pidreset (change-state! bwd_pid 0))
        ($gid (ensure-goal-at-depth (test-runtime-fact (Goal) (brand Proof $prf) (STV 1.0 1.0)) 0))
        ($pid
           (store-proof-candidate $gid
              (proof-candidate (leaf (test-runtime-fact (Goal) factA (STV 1.0 0.8)))
                 0.8
                 ((fact-ev (kb MAIN ()) factA (Goal)))
                 ()))))
      (materialize-proof $pid))
   factA)

;; Materialized facts retain their upstream evidence identity, but a later
;; backward proof sees the materialized fact as one leaf and does not recreate
;; every upstream leaf in its proof DAG. Missing leaves disable factoring
;; instead of passing the no-tv sentinel into STV arithmetic.
!(test
   (let*
      (($_clear (clear-backward-state))
       ($_gidreset (change-state! bwd_gid 0))
       ($_pidreset (change-state! bwd_pid 0))
       ($gid
          (ensure-goal-at-depth
             (test-runtime-fact
                (MaterializedGoal) (brand Proof $prf) (STV 1.0 1.0))
             0))
       ($pid
          (store-proof-candidate $gid
             (proof-candidate
                (leaf
                   (test-runtime-fact
                      (MaterializedGoal) materialized (STV 0.8 0.7)))
                0.7
                ((fact-ev (kb MAIN ()) source (SourceFact)))
                ()))))
      (collapse
         (factor-required-leaf-tv $pid
            (factor-fact-key
               (fact-ev (kb MAIN ()) source (SourceFact))))))
   ())

!(test (proof-term-children-mode proof-walk-plain (custom-proof left right)) ())

!(test (once (proof-term-evidence-list-mode proof-walk-plain (own_have (fact-ev (kb MAIN ()) i_have_max (Have (i max))))))
   ((own_have (fact-ev (kb MAIN ()) i_have_max (Have (i max))))))

!(test
   (let*
      (($_clear (clear-backward-state))
        ($_gidreset (change-state! bwd_gid 0))
        ($_pidreset (change-state! bwd_pid 0))
        ($agg-gid (ensure-goal-at-depth (CPU FoldAllCompiled dummy-agg-args $out) 0))
        ($child-gid (ensure-goal-at-depth (test-runtime-fact (Child) (brand Proof $prf) (STV 1.0 1.0)) 1))
        ($_agg0 (add-atom &aggregate (stored-aggregate-row $agg-gid $child-gid dummy-agg-args 1.0 0.0 ())))
        ($pid-old
           (store-proof-candidate $agg-gid
              (leaf-result-candidate (CPU FoldAllCompiled dummy-agg-args 1) ())))
        ($_agg1
           (progn
              (remove-atom &aggregate (stored-aggregate-row $agg-gid $child-gid dummy-agg-args 1.0 0.0 ()))
              (add-atom &aggregate (stored-aggregate-row $agg-gid $child-gid dummy-agg-args 1.0 0.0 ($pid-old)))))
        ($pid-new
           (store-proof-candidate $agg-gid
              (leaf-result-candidate (CPU FoldAllCompiled dummy-agg-args 2) ())))
        ($_agg2
           (progn
              (remove-atom &aggregate (stored-aggregate-row $agg-gid $child-gid dummy-agg-args 1.0 0.0 ($pid-old)))
              (add-atom &aggregate (stored-aggregate-row $agg-gid $child-gid dummy-agg-args 1.0 0.0 ($pid-new)))
              (deactivate-current-proof! $pid-old))))
      ((proof-live? $pid-old) (proof-live? $pid-new)))
   (false true))

!(test
   (let*
      (($_clear (clear-backward-state))
        ($_gidreset (change-state! bwd_gid 0))
        ($_pidreset (change-state! bwd_pid 0))
        ($agg-gid (ensure-goal-at-depth (CPU FoldAllCompiled dummy-agg-args $out) 0))
        ($child-gid (ensure-goal-at-depth (test-runtime-fact (Child) (brand Proof $prf) (STV 1.0 1.0)) 1))
        ($_agg0 (add-atom &aggregate (stored-aggregate-row $agg-gid $child-gid dummy-agg-args 1.0 0.0 ())))
        ($pid-old
           (store-proof-candidate $agg-gid
              (leaf-result-candidate (CPU FoldAllCompiled dummy-agg-args 1) ())))
        ($_agg1
           (progn
              (remove-atom &aggregate (stored-aggregate-row $agg-gid $child-gid dummy-agg-args 1.0 0.0 ()))
              (add-atom &aggregate (stored-aggregate-row $agg-gid $child-gid dummy-agg-args 1.0 0.0 ($pid-old)))))
        ($pid-new
           (store-proof-candidate $agg-gid
              (leaf-result-candidate (CPU FoldAllCompiled dummy-agg-args 2) ())))
        ($path-id (ensure-frontier-path 0 $pid-old))
        ($_agg2
           (progn
              (remove-atom &aggregate (stored-aggregate-row $agg-gid $child-gid dummy-agg-args 1.0 0.0 ($pid-old)))
              (add-atom &aggregate (stored-aggregate-row $agg-gid $child-gid dummy-agg-args 1.0 0.0 ($pid-new)))
              (deactivate-current-proof! $pid-old))))
      (waiter-live?
         (frontier-waiter 99 bundle 1.0 () () $path-id
            (frontier-value-spec 1.0 1 1.0))))
   false)

!(test
   (let*
      (($_clear (clear-backward-state))
       ($_pathreset (change-state! bwd_frontier_path 0))
       ($first (ensure-frontier-path 0 10))
       ($same-first (ensure-frontier-path 0 10))
       ($second (ensure-frontier-path $first 20))
       ($proofs (frontier-path-rev-proof-ids $second))
       ($before
          ((frontier-path-live? $first)
           (frontier-path-live? $second)))
       ($_invalidate (invalidate-proof-dependents! 10)))
      ((== $first $same-first)
       $proofs
       $before
       (frontier-path-live? $first)
       (frontier-path-live? $second)))
   (true (20 10) (true true) false false))

;; Aggregate replacement is atomic from the caller's perspective: after the
;; new aggregate becomes current but before its parent is rebuilt, the parent
;; derived from the prior snapshot remains an available incumbent.
!(test
   (let*
      (($_clear (clear-backward-state))
        ($_gidreset (change-state! bwd_gid 0))
        ($_pidreset (change-state! bwd_pid 0))
        ($agg-gid
           (ensure-goal-at-depth
              (CPU FoldAllCompiled dummy-agg-args $out) 1))
        ($child-gid
           (ensure-goal-at-depth
              (test-runtime-fact
                 (Child) (brand Proof $prf) (STV 1.0 1.0)) 2))
        ($parent-gid
           (ensure-goal-at-depth
              (assemble-runtime-fact
                 (brand Statement (AggregateParent))
                 (brand KBContext (incumbentMaterializeKb MAIN Nil))
                 (brand Proof $parent-goal-proof)
                 (the TV $parent-goal-tv))
              0))
        ($_agg0
           (add-atom &aggregate
              (stored-aggregate-row
                 $agg-gid $child-gid dummy-agg-args 1.0 0.0 ())))
        ($pid-old
           (store-proof-candidate $agg-gid
              (leaf-result-candidate
                 (CPU FoldAllCompiled dummy-agg-args 1) ())))
        ($_agg1
           (progn
              (remove-atom &aggregate
                 (stored-aggregate-row
                    $agg-gid $child-gid dummy-agg-args
                    1.0 0.0 ()))
              (add-atom &aggregate
                 (stored-aggregate-row
                    $agg-gid $child-gid dummy-agg-args
                    1.0 0.0 ($pid-old)))))
        ($parent-pid
           (store-proof-candidate $parent-gid
              (proof-candidate
                 (rule
                    (assemble-runtime-fact
                       (brand Statement (AggregateParent))
                       (brand KBContext
                          (incumbentMaterializeKb MAIN Nil))
                       (brand Proof aggregateParentProof)
                       (the TV (STV 1.0 0.8))))
                 0.8 () ($pid-old))))
        ($pid-new
           (store-proof-candidate $agg-gid
              (leaf-result-candidate
                 (CPU FoldAllCompiled dummy-agg-args 2) ())))
        ($_agg2
           (progn
              (remove-atom &aggregate
                 (stored-aggregate-row
                    $agg-gid $child-gid dummy-agg-args
                    1.0 0.0 ($pid-old)))
              (add-atom &aggregate
                 (stored-aggregate-row
                    $agg-gid $child-gid dummy-agg-args
                    1.0 0.0 ($pid-new)))
              (deactivate-current-proof! $pid-old)))
        ($_materialize
           (let $_deps (collapse (materialize-list! (root-pids $parent-gid))) ())))
      ((proof-live? $pid-old)
       (proof-list-live? ($pid-old))
       (== (proof-children-by-id $parent-pid) ($pid-old))
       (proof-live? $parent-pid)
       (goal-live-proof-ids $parent-gid)
       (== (goal-incumbent-proof-ids $parent-gid) ($parent-pid))
       (not (== (root-goal-results-with-materialization $parent-gid false) ()))
       (not
          (==
             (collapse
                (match &kb
                   ((AggregateParent)
                      (incumbentMaterializeKb MAIN Nil) $_proof $_tv)
                   true))
             ()))))
   (false false true false () true true true))

!(test
   (let*
      (($_clear (clear-backward-state))
        ($_gidreset (change-state! bwd_gid 0))
        ($_pidreset (change-state! bwd_pid 0))
        ($agg-gid (ensure-goal-at-depth (CPU FoldAllCompiled dummy-agg-args $out) 0))
        ($child-gid (ensure-goal-at-depth (test-runtime-fact (Child) (brand Proof $prf) (STV 1.0 1.0)) 1))
        ($_agg0 (add-atom &aggregate (stored-aggregate-row $agg-gid $child-gid dummy-agg-args 1.0 0.0 ())))
        ($pid-old
           (store-proof-candidate $agg-gid
              (leaf-result-candidate (CPU FoldAllCompiled dummy-agg-args 1) ())))
        ($_agg1
           (progn
              (remove-atom &aggregate (stored-aggregate-row $agg-gid $child-gid dummy-agg-args 1.0 0.0 ()))
              (add-atom &aggregate (stored-aggregate-row $agg-gid $child-gid dummy-agg-args 1.0 0.0 ($pid-old)))))
        ($_prime-proof (proof-live? $pid-old))
        ($_prime-goal (goal-live-proof-ids $agg-gid))
        ($pid-new
           (store-proof-candidate $agg-gid
              (leaf-result-candidate (CPU FoldAllCompiled dummy-agg-args 2) ())))
        ($_agg2
           (progn
              (remove-atom &aggregate (stored-aggregate-row $agg-gid $child-gid dummy-agg-args 1.0 0.0 ($pid-old)))
              (add-atom &aggregate (stored-aggregate-row $agg-gid $child-gid dummy-agg-args 1.0 0.0 ($pid-new)))
              (deactivate-current-proof! $pid-old))))
      ((proof-live? $pid-old) (proof-live? $pid-new) (length (goal-live-proof-ids $agg-gid))))
   (false true 1))
