(= (goal-term-by-id $gid) (match &goal_by_id ($gid $_depth $goal) $goal))

(= (goal-expanded? $gid) (first-or (collapse (once (match &goal_expanded ($gid true) true))) false))

(= (goal-pending-score-of $gid)
   (first-or (collapse (once (match &goal_pending_score ($gid $score) $score))) 0.0))

(= (goal-depth-of $gid)
   (first-or (collapse (once (match &goal_by_id ($gid $depth $_goal) $depth))) 0))

(= (clear-goal-pending-score $gid)
   (progn
      (collapse (match &goal_pending_score ($gid $score) (remove-atom &goal_pending_score ($gid $score))))
      ()))

(= (ensure-goal-at-depth $goal $depth)
   (let*
      (($stored-goal (copy_term $goal))
        ($goal-key (goal-view-key (goal-view $stored-goal)))
        ($hits (collapse (once (match &goal_lookup ($goal-key $gid) $gid)))))
      (if (== $hits ())
         (let*
            (($gid (next-gid))
              ($_1 (add-atom &goal_by_id ($gid $depth $stored-goal)))
              ($_2 (add-atom &goal_lookup ($goal-key $gid))))
            $gid)
         (car-atom $hits))))

(= (ensure-goal $goal) (ensure-goal-at-depth $goal 0))

(= (schedule-goal-heap $agenda $score $gid)
   (let*
      (($expanded (goal-expanded? $gid))
        ($current (goal-pending-score-of $gid))
        ($depth (goal-depth-of $gid)))
      (if $expanded $agenda
         (if (>= $current $score) $agenda
            (let*
               (($goal (goal-term-by-id $gid))
                 ($goal-view (goal-view $goal))
                 ($closed-proof-bonus (if (goal-view-has-type-vars? $goal-view) 0.0 1.0))
                 ($bonus (if (= $goal-view (proof-goal $_kb $_type $_prf $_tv)) $closed-proof-bonus 2.0))
                 ($priority (+ (* 1000000000.0 $depth) (- 0 (+ (* 1000000.0 $score) $bonus))))
                 ($nagenda (add_to_heap $agenda $priority (qitem $score $gid)))
                 ($_clear (clear-goal-pending-score $gid))
                 ($_set (add-atom &goal_pending_score ($gid $score))))
               $nagenda)))))

(= (aggregate-compiled-child-goal $compiled-query)
   (let*
      (($adds (compiled-query-adds $compiled-query))
        ($_ (inject-compiled-adds $adds))
        ($child-goal (compiled-query-goal-head $compiled-query)))
      $child-goal))

(= (aggregate-goal-spec (cpu-goal FoldAllFormulaCompiled ($kb $pattern $value $init $fun) $_goalres))
   (aggregate-spec (aggregate-compiled-child-goal (aggregate-compiled-query $kb $pattern))
      $init
      (aggregate-step-fold-value $fun $pattern $value)
      (aggregate-result-bare FoldAllFormulaCompiled ($kb $pattern $value $init $fun) identity)))
(= (aggregate-goal-spec (cpu-goal FoldAllTVFormulaCompiled ($kb $pattern $init $fun $finish) $_goalres))
   (aggregate-spec (aggregate-compiled-child-goal (aggregate-compiled-query $kb $pattern))
      $init
      (aggregate-step-fold-tv $fun)
      (aggregate-result-bare FoldAllTVFormulaCompiled ($kb $pattern $init $fun $finish) $finish)))

(= (aggregate-spec-step (aggregate-spec $_child-goal $_init $step-spec $_result-spec)) $step-spec)

(= (aggregate-spec-step-value (aggregate-step-fold-value $_fun $pattern $value) $child-atom)
   (let ($pattern ($_ckbid $_cctx $_cvars) $_cprf $_ctv) (copy_term $child-atom) $value))

(= (aggregate-spec-step-acc (aggregate-step-fold-value $fun $pattern $value) $acc $child-atom $_child-tv)
   (let $val (aggregate-spec-step-value (aggregate-step-fold-value $fun $pattern $value) $child-atom)
      (eval ($fun $acc $val))))
(= (aggregate-spec-step-acc (aggregate-step-fold-tv $fun) $acc $_child-atom $child-tv)
   (eval ($fun $acc $child-tv)))
(= (aggregate-spec-step-acc aggregate-step-dist-average $acc $_child-atom $child-tv)
   (reduce (reduce (DistSumCountAcc $acc $child-tv))))

(= (aggregate-spec-result (aggregate-result-bare $fun $args identity) $acc)
   (CPU $fun $args $acc))
(= (aggregate-spec-result (aggregate-result-bare $fun $args dist-average) $acc)
   (CPU $fun $args (reduce (reduce (DistAverageFromSumCount $acc)))))

(= (waiter-state-by-id $wid) (match &waiter_state ($wid $state) $state))

(= (set-waiter-state $wid $state)
   (progn (collapse (match &waiter_state ($wid $old-state) (remove-atom &waiter_state ($wid $old-state))))
      (add-atom &waiter_state ($wid $state))))

(= (spawn-waiting-goal-heap $agenda $score $gid $state)
   (let*
      (($wid (next-search-id bwd_wid))
        ($_1 (set-waiter-state $wid $state))
        ($_2 (add-atom &goal_waiter ($gid $wid)))
        ($agenda1
           (fold-flat (|-> ($acc $pid) (advance-goal-waiter-heap $acc $wid $pid))
              $agenda
              (collapse (match &goal_proof ($gid $pid) $pid))))
        ($nagenda (schedule-goal-heap $agenda1 $score $gid)))
      $nagenda))

(= (advance-frontier-bundle (and-bundle $_goal ()) $_pid) ())
(= (advance-frontier-bundle (and-bundle $goal (cons $prem $rest)) $pid)
   (if (= $prem (proof-output-atom $pid)) (and-bundle $goal $rest) ()))

(=
   (advance-waiter-state-heap $agenda
      $_wid
      (aggregate-waiter $_gid
         $_child-gid
         $_spec
         $_acc
         $_ev
         $_seen
         true)
      $_pid)
   $agenda)
(=
   (advance-waiter-state-heap $agenda
      $wid
      (aggregate-waiter $gid
         $child-gid
         $spec
         $acc
         $ev
         $seen
         false)
      $pid)
   (let*
      (($child-atom (proof-output-atom $pid))
        ($child-key
           (let $key (goal-key-components $child-atom)
              (if (== $key ()) $child-atom $key)))
        (($_pscore $pev) (proof-stats-by-id $pid))
        ($step-spec (copy_term (aggregate-spec-step $spec))))
      (if (is-member $child-key $seen) $agenda
         (let*
            (($nacc (aggregate-spec-step-acc $step-spec $acc $child-atom (proof-tv-by-id $pid)))
              ($nev (list_to_set (list-append $ev $pev)))
              ($nseen (cons $child-key $seen))
              ($_1 (set-waiter-state $wid (aggregate-waiter $gid $child-gid $spec $nacc $nev $nseen false))))
            $agenda))))
(=
   (advance-waiter-state-heap $agenda
      $_wid
      (frontier-waiter $parent-gid
         $aid
         $bundle
         $score
         $seen
         $rev-pids)
      $pid)
   (let*
      ((($pscore $pev) (proof-stats-by-id $pid))
        ($overlap (evidence-sets-overlap? $seen $pev))
        ($next-bundle (advance-frontier-bundle (copy_term $bundle) $pid)))
      (if $overlap $agenda
         (if (== $next-bundle ()) $agenda
            (spawn-frontier-heap $agenda
               $parent-gid
               $aid
               $next-bundle
               (min $score $pscore)
               (list_to_set (list-append $seen $pev))
               (cons $pid $rev-pids))))))

(= (advance-goal-waiter-heap $agenda $wid $pid)
   (advance-waiter-state-heap $agenda $wid (waiter-state-by-id $wid) $pid))

(= (spawn-aggregate-goal-heap $agenda $score $gid $goal-view)
   (let*
      (($spec (aggregate-goal-spec $goal-view))
        ((aggregate-spec $child-goal $init-acc $_step-spec $_result-spec) $spec)
        ($child-gid (ensure-goal-at-depth $child-goal (+ 1 (goal-depth-of $gid))))
        ($stored-spec (copy_term $spec)))
      (spawn-waiting-goal-heap $agenda
         $score
         $child-gid
         (aggregate-waiter $gid
            $child-gid
            $stored-spec
            $init-acc
            ()
            ()
            false))))

(=
   (finalize-waiter-state-heap $agenda
      $_wid
      (aggregate-waiter $_gid
         $_child-gid
         $_spec
         $_acc
         $_ev
         $_seen
         true))
   $agenda)
(= (finalize-waiter-state-heap $agenda $wid (aggregate-waiter $gid $child-gid $spec $acc $ev $seen false))
   (let*
      (($dep-wids
           (collapse
              (match &waiter_state
                 ($dep-wid
                    (aggregate-waiter $child-gid
                       $_dep-child
                       $_dep-spec
                       $_dep-acc
                       $_dep-ev
                       $_dep-seen
                       $_dep-finalized))
                 $dep-wid)))
        ($agenda1 (fold-flat finalize-aggregate-waiter-heap $agenda $dep-wids))
        ($_1 (set-waiter-state $wid (aggregate-waiter $gid $child-gid $spec $acc $ev $seen true)))
        ((aggregate-spec $_goal $_init $_step-spec $result-spec) $spec)
        ($result (aggregate-spec-result $result-spec $acc)))
      (commit-proof-candidate-heap $agenda1
         $gid
         (classify-goal-proof-candidate $gid $ev (term-confidence $result))
         (leaf-result-candidate $result $ev))))

(= (finalize-aggregate-waiter-heap $agenda $wid)
   (finalize-waiter-state-heap $agenda $wid (waiter-state-by-id $wid)))

(= (finalize-all-aggregates-heap $agenda)
   (fold-flat finalize-aggregate-waiter-heap $agenda
      (collapse
         (match &waiter_state
            ($wid (aggregate-waiter $_gid $_child-gid $_spec $_acc $_ev $_seen $_finalized))
            $wid))))

(= (direct-goal-results-view $steps (cpu-goal $fun $args $_res))
   (CPU $fun $args (cpu-call $steps $fun $args)))
(= (direct-goal-results-view $steps (proof-goal $kb $type $prf $tv))
      (let $qtype (if (contains-hash? $type) (map-nested (|-> ($x) (if (== $x #) $any $x)) $type) $type)
      (match &kb ($qtype $kb $prf $tv)($qtype $kb $prf $tv))))

(= (direct-result-exact-hit (proof-goal $kb $type $prf $tv) $result) (=? ($type $kb $prf $tv) $result))
(= (direct-result-exact-hit (cpu-goal $fun $args $res) $result) (goal-key-eq? (CPU $fun $args $res) $result))

(= (expand-direct-goal-step $gid $goal (expand-state $agenda $exact-hit) $result)
   (let*
      (($goal-view (goal-view $goal))
        ($score (term-confidence $result))
        ($ev (leaf-evidence-for-result $result))
        ($accepted (classify-goal-proof-candidate $gid $ev $score))
        ($nagenda (commit-proof-candidate-heap $agenda $gid $accepted (leaf-result-candidate $result $ev)))
        ($nexact-hit (or $exact-hit (direct-result-exact-hit $goal-view $result))))
      (expand-state $nagenda $nexact-hit)))

(= (expand-direct-goal-heap $agenda $steps $gid $goal)
   (let*
      (($results (collapse (direct-goal-results-view $steps (goal-view $goal))))
        ((expand-state $agenda1 $exact-hit)
           (fold-flat (expand-direct-goal-step $gid $goal) (expand-state $agenda false) $results)))
      (if $exact-hit $agenda1 (expand-rule-goal-heap $agenda1 $gid $goal))))

(= (spawn-frontier-heap $agenda $parent-gid $aid $bundle $score $seen $rev-pids)
   (case $bundle (
        ((and-bundle $goal ())
           (let*
              (($pid-list (list-reverse $rev-pids))
                ((and-bundle $instantiated-goal $_rest)
                   (instantiate-and-bundle
                      (copy_term (match &and_node ($aid $_parent $_rule $_bound $node-bundle) $node-bundle))
                      $pid-list))
                (($_type ($_kbid $_ctx $_vars) $_prf $tv) $instantiated-goal))
              (commit-proof-candidate-heap $agenda
                 $parent-gid
                 (classify-goal-proof-candidate $parent-gid $seen $score)
                 (proof-candidate (rule $aid $instantiated-goal)
                    $score
                    $seen
                    $pid-list))))
        ((and-bundle $_goal (cons $prem $_rest))
           (let*
              (($gid (ensure-goal-at-depth $prem (+ 1 (goal-depth-of $parent-gid))))
                ($stored-bundle (copy_term $bundle)))
              (spawn-waiting-goal-heap $agenda
                 $score
                 $gid
                 (frontier-waiter $parent-gid
                    $aid
                    $stored-bundle
                    $score
                    $seen
                    $rev-pids)))))))

(= (expand-rule-goal-heap $agenda $parent-gid $goal)
   (fold-flat expand-rule-goal-fold
      $agenda
      (collapse
         (match ccls_index ($goal $rule-id)
            (match rules ($rule-id $goal $args)
               ($args $goal $parent-gid $rule-id))))))

(= (expand-rule-goal-fold $agenda ($args $goal $parent-gid $rule-id))
   (let*
      (($bound (premises-expected-confidence $args))
        ($bundle (copy_term (and-bundle $goal $args)))
        ($aid (next-aid))
        ($_1 (add-atom &and_node ($aid $parent-gid $rule-id $bound $bundle))))
      (spawn-frontier-heap $agenda
         $parent-gid
         $aid
         $bundle
         $bound
         ()
         ())))

(= (expand-goal-heap $agenda $steps $score $gid)
   (let*
      (($goal (goal-term-by-id $gid))
        ($goal-view (goal-view $goal))
        ($_expand (add-atom &goal_expanded ($gid true)))
        ($nagenda0
           (if
              (and (= $goal-view (cpu-goal $fun $_args $_res))
                 (is-member $fun (() FoldAllFormulaCompiled FoldAllTVFormulaCompiled)))
              (spawn-aggregate-goal-heap $agenda $score $gid $goal-view)
              (expand-direct-goal-heap $agenda $steps $gid $goal)))
        ($nagenda (if (== $nagenda0 ()) (empty_heap) $nagenda0)))
      $nagenda))

(= (search-goals-heap $steps $agenda)
   (if (or (<= $steps 0) (== (heap_size $agenda) 0)) (search-state $steps $agenda)
      (let*
         (($rest (get_from_heap $agenda $_priority $item))
           ((qitem $score $gid) $item))
         (if (and (not (goal-expanded? $gid)) (== (goal-pending-score-of $gid) $score))
            (let*
               (($_clear (clear-goal-pending-score $gid))
                 ($nagenda (expand-goal-heap $rest $steps $score $gid)))
               (search-goals-heap (- $steps 1) $nagenda))
            (search-goals-heap $steps $rest)))))

(= (instantiate-and-bundle (and-bundle $goal ()) ()) (and-bundle $goal ()))
(= (instantiate-and-bundle (and-bundle $goal (cons $prem $rest)) (cons $pid $pids))
   (if (= $prem (proof-output-atom $pid)) (instantiate-and-bundle (and-bundle $goal $rest) $pids) (empty)))

(= (clear-backward-state)
   (progn
      (foreach-flat remove-all-atoms
         (() &goal_by_id
            &goal_lookup
            &goal_expanded
            &goal_pending_score
            &goal_waiter
            &waiter_state
            &and_node
            &goal_proof
            &proof_goal
            &proof_stats
            &proof_kind
            &proof_children))
      ()))

(= (chainer $steps $goal)
   (let*
      (($_clear (clear-backward-state))
        ($_reset
           (foreach-flat
              (|-> ($key) (change-state! $key 0))
              (() bwd_gid bwd_aid bwd_wid bwd_pid)))
        ($root-gid (ensure-goal $goal))
        ($agenda0 (schedule-goal-heap (empty_heap) 1.0 $root-gid))
        ((search-state $search-steps-left $agenda1)
           (once (if (<= $steps 0) (search-state 0 $agenda0) (search-goals-heap (+ $steps 1) $agenda0))))
        ($agenda2 (once (finalize-all-aggregates-heap $agenda1)))
        ((search-state $_search-steps-left2 $_agenda3)
           (once
              (if (<= $search-steps-left 0) (search-state $search-steps-left $agenda2)
                 (search-goals-heap $search-steps-left $agenda2)))))
      (once (goal-results $root-gid))))
