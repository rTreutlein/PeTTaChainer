(= (goal-by-id $gid) (match &goal ($gid $depth $goal $expanded $pending) ($depth $goal $expanded $pending)))

(= (ensure-goal-at-depth $goal $depth)
   (let*
      (($stored-goal (copy_term $goal))
        ($goal-key (goal-key $stored-goal))
        ($hits (collapse (once (match &goal_lookup ($goal-key $gid) $gid)))))
      (if (== $hits ())
         (let*
            (($gid (next-gid))
              ($_1 (add-atom &goal ($gid $depth $stored-goal false 0.0)))
              ($_2 (add-atom &goal_lookup ($goal-key $gid))))
            $gid)
         (car-atom $hits))))

(= (schedule-goal-heap $agenda $score $gid)
   (let*
      ((($depth $goal $expanded $current) (goal-by-id $gid)))
      (if $expanded $agenda
         (if (>= $current $score) $agenda
            (let*
               (($closed-proof-bonus (if (goal-has-type-vars? $goal) 0.0 1.0))
                 ($bonus (if (= $goal ($_type ($_kbid $_ctx $_vars) $_prf $_tv)) $closed-proof-bonus 2.0))
                 ($priority (+ (* 1000000000.0 $depth) (- 0 (+ (* 1000000.0 $score) $bonus))))
                 ($nagenda (add_to_heap $agenda $priority (qitem $score $gid)))
                 ($_set
                    (progn (remove-atom &goal ($gid $depth $goal $expanded $current))
                       (add-atom &goal ($gid $depth $goal $expanded $score)))))
               $nagenda)))))

(=
   (aggregate-child-goal
      (CPU FoldAllCompiled ($kb $pattern $_extractor $_init $_fun $_finish $_tv-mode) $_goalres))
   (let*
      (((compiled-query $child-goal $adds) (mm2compileQueryInternal $kb (: $prf $pattern $tvin)))
        ($_ (inject-compiled-adds $adds)))
      $child-goal))

(= (aggregate-step-value (extract-value $pattern $value) $child-atom $_child-tv)
   (let ($pattern ($_ckbid $_cctx $_cvars) $_cprf $_ctv) (copy_term $child-atom) $value))
(= (aggregate-step-value extract-tv $_child-atom $child-tv) $child-tv)

(= (aggregate-foldall-step-acc $extractor $fun $acc $child-atom $child-tv)
   (eval ($fun $acc (aggregate-step-value $extractor $child-atom $child-tv))))

(= (aggregate-finish identity $acc) $acc)
(= (aggregate-finish dist-average $acc) (reduce (reduce (DistAverageFromSumCount $acc))))

(= (advance-frontier-bundle (and-bundle $_goal ()) $_pid) ())
(= (advance-frontier-bundle (and-bundle $goal (cons $prem $rest)) $pid)
   (if (= $prem (proof-output-atom $pid)) (and-bundle $goal $rest) ()))

(=
   (advance-frontier-waiter-heap $agenda
      (frontier-waiter $parent-gid
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
               $next-bundle
               (min $score $pscore)
               (list_to_set (append $seen $pev))
               (cons $pid $rev-pids))))))

(= (advance-goal-waiter-heap $agenda (@ $waiter (head frontier-waiter)) $pid)
   (advance-frontier-waiter-heap $agenda $waiter $pid))
(= (advance-goal-waiter-heap $agenda (head aggregate-waiter) $_pid) $agenda)

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
      (($args (copy_term (let (CPU FoldAllCompiled $args $_goalres) $goal-view $args)))
        ($child-goal (aggregate-child-goal $goal-view))
        (($depth $_goal $_expanded $_pending) (goal-by-id $gid))
        ($child-gid (ensure-goal-at-depth $child-goal (+ 1 $depth))))
      (let*
         (($_1 (add-atom &goal_waiter ($child-gid (aggregate-waiter $gid $args))))
           ($nagenda (schedule-goal-heap $agenda $score $child-gid)))
         $nagenda)))

(= (aggregate-proof-key ($type ($kbid $ctx $vars) $_prf $_tv)) (($kbid $ctx $vars) $type))
(= (aggregate-proof-key $child-atom) $child-atom)

(= (aggregate-proof-fold-step $args (aggregate-state $acc $ev $seen) $pid)
   (let*
      ((($_agg-kb $_agg-pattern $extractor $_agg-init $fun $_agg-finish $_agg-tv-mode) (copy_term $args))
        ($child-atom (proof-output-atom $pid))
        ($child-key (aggregate-proof-key $child-atom))
        (($_pscore $pev) (proof-stats-by-id $pid))
        ($child-tv (if (= $child-atom ($_type $_kb $_prf $tv)) $tv no-tv)))
      (if (is-member $child-key $seen) (aggregate-state $acc $ev $seen)
         (let*
            (($nacc (aggregate-foldall-step-acc $extractor $fun $acc $child-atom $child-tv))
              ($nev (list_to_set (append $ev $pev)))
              ($nseen (cons $child-key $seen)))
            (aggregate-state $nacc $nev $nseen)))))

(= (aggregate-final-state $child-gid $args)
   (let*
      ((($_kb $_pattern $_extractor $init-acc $_fun $_finish $_tv-mode) (copy_term $args)))
      (fold-flat (aggregate-proof-fold-step $args)
         (aggregate-state $init-acc () ())
         (collapse (match &proof ($pid $child-gid $_output $_kind $_score $_ev $_children) $pid)))))

(= (finalize-aggregate-goal-heap $agenda $gid $child-gid $args)
   (if (== (collapse (once (match &goal_waiter ($child-gid (aggregate-waiter $gid $args)) true))) ()) $agenda
      (let*
         (($deps
              (collapse
                 (match &goal_waiter ($dep-child (aggregate-waiter $child-gid $dep-args))
                    ($child-gid $dep-child $dep-args))))
           ($agenda1 (fold-flat finalize-aggregate-entry-heap $agenda $deps))
           ($_remove
              (collapse
                 (match &goal_waiter ($child-gid (aggregate-waiter $gid $args))
                    (remove-atom &goal_waiter ($child-gid (aggregate-waiter $gid $args))))))
           ((aggregate-state $acc $ev $_seen) (aggregate-final-state $child-gid $args))
           (($kb $pattern $extractor $init $fun $finish $tv-mode) $args)
           ($result (CPU FoldAllCompiled $args (aggregate-finish $finish $acc))))
         (commit-proof-candidate-heap $agenda1
            $gid
            (classify-goal-proof-candidate $gid $ev (term-confidence $result))
            (leaf-result-candidate $result $ev)))))

(= (finalize-aggregate-entry-heap $agenda ($gid $child-gid $args))
   (finalize-aggregate-goal-heap $agenda $gid $child-gid $args))

(= (finalize-all-aggregates-heap $agenda)
   (fold-flat finalize-aggregate-entry-heap
      $agenda
      (collapse (match &goal_waiter ($child-gid (aggregate-waiter $gid $args)) ($gid $child-gid $args)))))

(= (direct-goal-results-view $steps (CPU $fun $args $_res)) (CPU $fun $args (cpu-call $steps $fun $args)))
(= (direct-goal-results-view $steps ($type $kb $prf $tv))
   (let $qtype (if (contains-hash? $type) (map-nested (|-> ($x) (if (== $x #) $any $x)) $type) $type)
      (match &kb ($qtype $kb $prf $tv)
         ($qtype $kb $prf $tv))))

(= (direct-result-exact-hit ($type $kb $prf $tv) $result) (=? ($type $kb $prf $tv) $result))
(= (direct-result-exact-hit (CPU $fun $args $res) $result)
   (or (== (CPU $fun $args $res) $result) (=alpha (CPU $fun $args $res) $result)))

(= (expand-direct-goal-step $gid $goal (expand-state $agenda $exact-hit) $result)
   (let*
      (($score (term-confidence $result))
        ($ev (leaf-evidence-for-result $result))
        ($accepted (classify-goal-proof-candidate $gid $ev $score))
        ($nagenda (commit-proof-candidate-heap $agenda $gid $accepted (leaf-result-candidate $result $ev)))
        ($nexact-hit (or $exact-hit (direct-result-exact-hit $goal $result))))
      (expand-state $nagenda $nexact-hit)))

(= (expand-direct-goal-heap $agenda $steps $gid $goal)
   (let*
      (($results (collapse (direct-goal-results-view $steps $goal)))
        ((expand-state $agenda1 $exact-hit)
           (fold-flat (expand-direct-goal-step $gid $goal) (expand-state $agenda false) $results)))
      (if $exact-hit $agenda1 (expand-rule-goal-heap $agenda1 $gid $goal))))

(= (spawn-frontier-heap $agenda $parent-gid $bundle $score $seen $rev-pids)
   (case $bundle (
        ((and-bundle $goal ())
           (let*
              (($pid-list (reverse $rev-pids)))
              (commit-proof-candidate-heap $agenda
                 $parent-gid
                 (classify-goal-proof-candidate $parent-gid $seen $score)
                 (proof-candidate (rule $goal) $score $seen $pid-list))))
        ((and-bundle $_goal (cons $prem $_rest))
           (let*
              ((($parent-depth $_goal1 $_expanded $_pending) (goal-by-id $parent-gid))
                ($gid (ensure-goal-at-depth $prem (+ 1 $parent-depth)))
                ($stored-bundle (copy_term $bundle)))
              (spawn-frontier-goal-heap $agenda
                 $score
                 $gid
                 (frontier-waiter $parent-gid
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
               ($args $goal $parent-gid))))))

(= (expand-rule-goal-fold $agenda ($args $goal $parent-gid))
   (let*
      (($bound (premises-expected-confidence $args))
        ($bundle (copy_term (and-bundle $goal $args))))
      (spawn-frontier-heap $agenda
         $parent-gid
         $bundle
         $bound
         ()
         ())))

(= (expand-goal-heap $agenda $steps $score $gid)
   (let*
      ((($depth $goal $expanded $pending) (goal-by-id $gid))
        ($_expand
           (progn (remove-atom &goal ($gid $depth $goal $expanded $pending))
              (add-atom &goal ($gid $depth $goal true $pending))))
        ($nagenda0
           (if (and (= $goal (CPU $fun $_args $_res)) (== $fun FoldAllCompiled))
              (spawn-aggregate-goal-heap $agenda $score $gid $goal)
              (expand-direct-goal-heap $agenda $steps $gid $goal)))
        ($nagenda (if (== $nagenda0 ()) (empty_heap) $nagenda0)))
      $nagenda))

(= (search-goals-heap $steps $agenda)
   (if (or (<= $steps 0) (== (heap_size $agenda) 0)) (search-state $steps $agenda)
      (let*
         (($rest (get_from_heap $agenda $_priority $item))
           ((qitem $score $gid) $item)
           (($depth $goal $expanded $pending) (goal-by-id $gid)))
         (if (and (not $expanded) (== $pending $score))
            (let*
               (($_clear
                    (progn (remove-atom &goal ($gid $depth $goal $expanded $pending))
                       (add-atom &goal ($gid $depth $goal $expanded 0.0))))
                 ($nagenda (expand-goal-heap $rest $steps $score $gid)))
               (search-goals-heap (- $steps 1) $nagenda))
            (search-goals-heap $steps $rest)))))

(= (clear-backward-state)
   (progn (foreach-flat remove-all-atoms (() &goal &goal_lookup &goal_waiter &proof)) ()))

(= (chainer $steps $goal)
   (let*
      (($_clear (clear-backward-state))
        ($_reset (foreach-flat (|-> ($key) (change-state! $key 0)) (() bwd_gid bwd_pid)))
        ($root-gid (ensure-goal-at-depth $goal 0))
        ($agenda0 (schedule-goal-heap (empty_heap) 1.0 $root-gid))
        ((search-state $search-steps-left $agenda1)
           (once (if (<= $steps 0) (search-state 0 $agenda0) (search-goals-heap (+ $steps 1) $agenda0))))
        ($agenda2 (once (finalize-all-aggregates-heap $agenda1)))
        ((search-state $_search-steps-left2 $_agenda3)
           (once
              (if (<= $search-steps-left 0) (search-state $search-steps-left $agenda2)
                 (search-goals-heap $search-steps-left $agenda2)))))
      (once (goal-results $root-gid))))
