(= (goal-by-id $gid) (match &goal ($gid $depth $goal $expanded $pending) ($depth $goal $expanded $pending)))

(= (goal-term-by-id $gid)
   (let ($_depth $goal $_expanded $_pending) (goal-by-id $gid) $goal))

(= (goal-expanded? $gid)
   (first-or (collapse (let ($_depth $_goal $expanded $_pending) (goal-by-id $gid) $expanded)) false))

(= (goal-pending-score-of $gid)
   (first-or (collapse (let ($_depth $_goal $_expanded $pending) (goal-by-id $gid) $pending)) 0.0))

(= (goal-depth-of $gid)
   (first-or (collapse (let ($depth $_goal $_expanded $_pending) (goal-by-id $gid) $depth)) 0))

(= (set-goal-expanded $gid $expanded)
   (let ($depth $goal $old-expanded $pending) (goal-by-id $gid)
      (progn
         (remove-atom &goal ($gid $depth $goal $old-expanded $pending))
         (add-atom &goal ($gid $depth $goal $expanded $pending)))))

(= (set-goal-pending-score $gid $pending)
   (let ($depth $goal $expanded $old-pending) (goal-by-id $gid)
      (progn
         (remove-atom &goal ($gid $depth $goal $expanded $old-pending))
         (add-atom &goal ($gid $depth $goal $expanded $pending)))))

(= (clear-goal-pending-score $gid) (set-goal-pending-score $gid 0.0))

(= (ensure-goal-at-depth $goal $depth)
   (let*
      (($stored-goal (copy_term $goal))
        ($goal-key (goal-view-key (goal-view $stored-goal)))
        ($hits (collapse (once (match &goal_lookup ($goal-key $gid) $gid)))))
      (if (== $hits ())
         (let*
            (($gid (next-gid))
              ($_1 (add-atom &goal ($gid $depth $stored-goal false 0.0)))
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
                 ($_set (set-goal-pending-score $gid $score)))
               $nagenda)))))

(= (aggregate-compiled-child-goal $compiled-query)
   (let*
      (((compiled-query $raw-goal $raw-adds) $compiled-query)
        ($adds (internalize-proof-structure-list $raw-adds))
        ($_ (inject-compiled-adds $adds))
        ($child-goal (internalize-proof-structure $raw-goal)))
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

(= (advance-frontier-bundle (and-bundle $_goal ()) $_pid) ())
(= (advance-frontier-bundle (and-bundle $goal (cons $prem $rest)) $pid)
   (if (= $prem (proof-output-atom $pid)) (and-bundle $goal $rest) ()))

(= (advance-frontier-waiter-heap $agenda (frontier-waiter $parent-gid $rule-id $bundle $score $seen $rev-pids) $pid)
   (let*
      ((($pscore $pev) (proof-stats-by-id $pid))
        ($overlap (evidence-sets-overlap? $seen $pev))
        ($next-bundle (advance-frontier-bundle (copy_term $bundle) $pid)))
      (if $overlap $agenda
         (if (== $next-bundle ()) $agenda
            (spawn-frontier-heap $agenda
               $parent-gid
               $rule-id
               $next-bundle
               (min $score $pscore)
               (list_to_set (list-append $seen $pev))
               (cons $pid $rev-pids))))))

(= (advance-goal-waiter-heap $agenda $waiter $pid)
   (advance-frontier-waiter-heap $agenda $waiter $pid))

(= (spawn-frontier-goal-heap $agenda $score $gid $waiter)
   (let*
      (($_1 (add-atom &goal_waiter ($gid $waiter)))
        ($agenda1
           (fold-flat (|-> ($acc $pid) (advance-goal-waiter-heap $acc $waiter $pid))
              $agenda
              (collapse (match &proof ($pid $gid $_output $_kind $_score $_ev $_children) $pid))))
        ($nagenda (schedule-goal-heap $agenda1 $score $gid)))
      $nagenda))

(= (spawn-aggregate-goal-heap $agenda $score $gid $goal-view)
   (let*
      (($spec (aggregate-goal-spec $goal-view))
        ((aggregate-spec $child-goal $init-acc $_step-spec $_result-spec) $spec)
        ($child-gid (ensure-goal-at-depth $child-goal (+ 1 (goal-depth-of $gid))))
        ($stored-spec (copy_term $spec)))
      (let*
         (($_1 (add-atom &aggregate_waiter ($gid $child-gid $stored-spec)))
           ($nagenda (schedule-goal-heap $agenda $score $child-gid)))
         $nagenda)))

(= (aggregate-proof-key $child-atom)
   (let $key (goal-key-components $child-atom)
      (if (== $key ()) $child-atom $key)))

(= (aggregate-proof-fold-step $spec (aggregate-state $acc $ev $seen) $pid)
   (let*
      (($child-atom (proof-output-atom $pid))
        ($child-key (aggregate-proof-key $child-atom))
        (($_pscore $pev) (proof-stats-by-id $pid))
        ($step-spec (copy_term (aggregate-spec-step $spec))))
      (if (is-member $child-key $seen) (aggregate-state $acc $ev $seen)
         (let*
            (($nacc (aggregate-spec-step-acc $step-spec $acc $child-atom (proof-tv-by-id $pid)))
              ($nev (list_to_set (list-append $ev $pev)))
              ($nseen (cons $child-key $seen)))
            (aggregate-state $nacc $nev $nseen)))))

(= (aggregate-final-state $child-gid $spec)
   (let*
      (((aggregate-spec $_goal $init-acc $_step-spec $_result-spec) $spec))
      (fold-flat (aggregate-proof-fold-step $spec)
         (aggregate-state $init-acc () ())
         (collapse (match &proof ($pid $child-gid $_output $_kind $_score $_ev $_children) $pid)))))

(= (aggregate-waiter-live? $gid $child-gid $spec)
   (first-or (collapse (once (match &aggregate_waiter ($gid $child-gid $spec) true))) false))

(= (finalize-aggregate-goal-heap $agenda $gid $child-gid $spec)
   (if (aggregate-waiter-live? $gid $child-gid $spec)
      (let*
         (($deps
              (collapse
                 (match &aggregate_waiter ($child-gid $dep-child $dep-spec) ($child-gid $dep-child $dep-spec))))
           ($agenda1 (fold-flat finalize-aggregate-entry-heap $agenda $deps))
           ($_remove
              (collapse
                 (match &aggregate_waiter ($gid $child-gid $spec)
                    (remove-atom &aggregate_waiter ($gid $child-gid $spec)))))
           ((aggregate-state $acc $ev $_seen) (aggregate-final-state $child-gid $spec))
           ((aggregate-spec $_goal $_init $_step-spec $result-spec) $spec)
           ($result (aggregate-spec-result $result-spec $acc)))
         (commit-proof-candidate-heap $agenda1
            $gid
            (classify-goal-proof-candidate $gid $ev (term-confidence $result))
            (leaf-result-candidate $result $ev)))
      $agenda))

(= (finalize-aggregate-entry-heap $agenda ($gid $child-gid $spec))
   (finalize-aggregate-goal-heap $agenda $gid $child-gid $spec))

(= (finalize-all-aggregates-heap $agenda)
   (fold-flat finalize-aggregate-entry-heap $agenda
      (collapse
         (match &aggregate_waiter ($gid $child-gid $spec) ($gid $child-gid $spec)))))

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

(= (spawn-frontier-heap $agenda $parent-gid $rule-id $bundle $score $seen $rev-pids)
   (case $bundle (
        ((and-bundle $goal ())
           (let*
              (($pid-list (list-reverse $rev-pids)))
              (commit-proof-candidate-heap $agenda
                 $parent-gid
                 (classify-goal-proof-candidate $parent-gid $seen $score)
                 (proof-candidate (rule $rule-id $goal)
                    $score
                    $seen
                    $pid-list))))
        ((and-bundle $_goal (cons $prem $_rest))
           (let*
              (($gid (ensure-goal-at-depth $prem (+ 1 (goal-depth-of $parent-gid))))
                ($stored-bundle (copy_term $bundle)))
              (spawn-frontier-goal-heap $agenda
                 $score
                 $gid
                 (frontier-waiter $parent-gid
                    $rule-id
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
        ($bundle (copy_term (and-bundle $goal $args))))
      (spawn-frontier-heap $agenda
         $parent-gid
         $rule-id
         $bundle
         $bound
         ()
         ())))

(= (expand-goal-heap $agenda $steps $score $gid)
   (let*
      (($goal (goal-term-by-id $gid))
        ($goal-view (goal-view $goal))
        ($_expand (set-goal-expanded $gid true))
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

(= (clear-backward-state)
   (progn
      (foreach-flat remove-all-atoms
         (() &goal
            &goal_lookup
            &goal_waiter
            &aggregate_waiter
            &proof))
      ()))

(= (chainer $steps $goal)
   (let*
      (($_clear (clear-backward-state))
        ($_reset
           (foreach-flat
              (|-> ($key) (change-state! $key 0))
              (() bwd_gid bwd_pid)))
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
